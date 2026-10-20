"""Recognize page structure (Markdown tables, LaTeX formulas, block positions) for Bookside.

`run` starts a private mlx-vlm server on a free localhost port, renders each requested PDF
page with pdfium, runs PaddleOCR-VL with one recognition request at a time, and prints one
JSON line per finished page. mlx-vlm 0.7.6 corrupts output under concurrent requests, so
the pipeline's concurrency is fixed at 1. Library output goes to stderr (the caller's log).
`convert` turns a saved PaddleOCR-VL result into the same page record without the engine.

Compatible with Python 3.9 so the `convert` checks run with a system interpreter.
"""

import argparse
import json
import os
import re
import signal
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request

PROTOCOL = 1
# Paddle leaves these out of the page Markdown; they are content, so they are appended.
APPENDED_LABELS = ("footnote", "aside_text")
FORMULA_LABELS = ("display_formula", "inline_formula", "formula")
TABLE = re.compile(r"<table\b.*?</table>", re.S | re.I)
CELL = re.compile(r"(<t[dh]\b[^>]*>)(.*?)(</t[dh]>)", re.S | re.I)
TAG = re.compile(r"<(/?)(table|thead|tbody|tr|td|th)\b([^>]*)>", re.I)
SPAN_ATTRIBUTES = re.compile(r"""\b(rowspan|colspan)\s*=\s*["']?(\d+)["']?""", re.I)
MATH = re.compile(r"\$\$.*?\$\$|\$[^$]*\$|\\\(.*?\\\)", re.S)
LOOP = re.compile(r"(.{4,120}?)\1{4,}", re.S)
LOOP_MIN_CHARACTERS = 200
QUOTES = "'\"`\\"


def emit(stream, event, **values):
    values["event"] = event
    stream.write(json.dumps(values, ensure_ascii=False) + "\n")
    stream.flush()


# ---------- conversion (stdlib only) ----------

def cell_breaks(text):
    """Paddle writes a line break inside a table cell as the two characters `\\n`.

    Outside math, a backslash-n between two ordinary characters becomes <br>. One next to a
    quote, backtick or backslash is kept, because a programming book's table may show the
    escape sequence itself, as in "\\n" or printf("a\\n").
    """
    parts, last = [], 0
    for match in MATH.finditer(text):
        parts.append((False, text[last:match.start()]))
        parts.append((True, match.group(0)))
        last = match.end()
    parts.append((False, text[last:]))
    out = []
    for is_math, part in parts:
        if is_math:
            out.append(part)
            continue
        result, i = [], 0
        while i < len(part):
            if part.startswith("\\n", i):
                before = part[i - 1] if i > 0 else ""
                after = part[i + 2] if i + 2 < len(part) else ""
                if before and after and not before.isspace() and not after.isspace() and before not in QUOTES and after not in QUOTES:
                    result.append("<br>")
                    i += 2
                    continue
            result.append(part[i])
            i += 1
        out.append("".join(result))
    return "".join(out)


def clean_table(html):
    """Drop Paddle's per-cell inline styles (most of a table's characters) and fix cell breaks."""
    def tag(match):
        spans = "".join(" %s=\"%s\"" % (name.lower(), value) for name, value in SPAN_ATTRIBUTES.findall(match.group(3)))
        return "<%s%s%s>" % (match.group(1), match.group(2).lower(), spans if not match.group(1) else "")
    html = TAG.sub(tag, html)
    return CELL.sub(lambda m: m.group(1) + cell_breaks(m.group(2)) + m.group(3), html)


def latex_of(content):
    value = content.strip()
    for left, right in (("$$", "$$"), ("\\[", "\\]"), ("\\(", "\\)"), ("$", "$")):
        if value.startswith(left) and value.endswith(right) and len(value) >= len(left) + len(right):
            return value[len(left):len(value) - len(right)].strip()
    return value


def latex_problem(latex):
    depth, i = 0, 0
    while i < len(latex):
        char = latex[i]
        if char == "\\":
            i += 2
            continue
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth < 0:
                return True
        i += 1
    if depth:
        return True
    return sorted(re.findall(r"\\begin\{([^}]*)\}", latex)) != sorted(re.findall(r"\\end\{([^}]*)\}", latex))


def tag_formula(markdown, content, number):
    """Put a formula number into its display formula as \\tag, which KaTeX renders."""
    original = content.strip()
    if not original.startswith("$$") or original not in markdown:
        return markdown, False
    inner = number.strip()
    tag = "\\tag{%s}" % inner[1:-1] if re.match(r"^\(.+\)$", inner) else "\\tag*{%s}" % inner
    tagged = "$$ " + latex_of(original) + " " + tag + " $$"
    return markdown.replace(original, tagged, 1), True


def overlap(a, b):
    return max(0.0, min(a[3], b[3]) - max(a[1], b[1]))


def match_formula_numbers(blocks):
    """Pair each formula number with the display formula on the same line, to its left."""
    numbers = [b for b in blocks if b.get("block_label") == "formula_number"]
    formulas = [b for b in blocks if b.get("block_label") == "display_formula"]
    pairs, used = [], set()
    for number in numbers:
        nb = number["block_bbox"]
        best, gap = None, None
        for index, formula in enumerate(formulas):
            fb = formula["block_bbox"]
            if index in used or overlap(nb, fb) < 0.5 * max(1.0, nb[3] - nb[1]) or nb[0] < fb[0]:
                continue
            distance = max(0.0, nb[0] - fb[2])
            if gap is None or distance < gap:
                best, gap = index, distance
        if best is not None:
            used.add(best)
            pairs.append((formulas[best], number))
    return pairs


def page_rect(box, geometry):
    """Pixel box on the rendered (displayed) page -> [x, y, width, height] in PDF points.

    The origin is the lower-left corner of the page's crop box in unrotated page space,
    the space PDFKit uses for a page; y grows upward.
    """
    scale, rotation = geometry["scale"], geometry.get("rotation", 0) % 360
    width, height = geometry["width"], geometry["height"]
    def unrotate(xd, yd):
        if rotation == 90:
            xu, yu = yd, height - xd
        elif rotation == 180:
            xu, yu = width - xd, height - yd
        elif rotation == 270:
            xu, yu = width - yd, xd
        else:
            xu, yu = xd, yd
        return xu, height - yu
    x1, y1, x2, y2 = (float(v) / scale for v in box[:4])
    (ax, ay), (bx, by) = unrotate(x1, y1), unrotate(x2, y2)
    return [round(min(ax, bx), 2), round(min(ay, by), 2), round(abs(bx - ax), 2), round(abs(by - ay), 2)]


def loop_problem(text):
    plain = re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", text))
    for match in LOOP.finditer(plain):
        if len(match.group(0)) >= LOOP_MIN_CHARACTERS:
            return match.group(1).strip()[:40]
    return None


def page_record(result, markdown, geometry, token_limit_hits=0):
    """PaddleOCR-VL result JSON + its Markdown -> Bookside page record."""
    result = result.get("res", result)
    raw = result.get("parsing_res_list") or []
    ignored = set((result.get("model_settings") or {}).get("markdown_ignore_labels") or [])
    text = markdown
    text = re.sub(r"<div\b[^>]*>(.*?)</div>", r"\1", text, flags=re.S | re.I)
    text = re.sub(r"<img\b[^>]*>", "[figure]", text, flags=re.I)
    text = TABLE.sub(lambda m: clean_table(m.group(0)), text)
    tagged = set()
    for formula, number in match_formula_numbers(raw):
        text, done = tag_formula(text, formula.get("block_content", ""), number.get("block_content", ""))
        if done:
            tagged.add(id(number))
    appended = [b.get("block_content", "").strip() for b in raw if b.get("block_label") in APPENDED_LABELS and b.get("block_label") in ignored]
    appended = [value for value in appended if value]
    text = re.sub(r"\n{3,}", "\n\n", text).strip()
    if appended:
        text = (text + "\n\n---\n\n" if text else "") + "\n\n".join(appended)
    blocks, reasons = [], []
    # parsing_res_list is in Paddle's reading order; block_order covers only the text flow.
    for item in raw:
        label = item.get("block_label", "text")
        content = item.get("block_content", "") or ""
        block = {"type": label, "bbox": page_rect(item["block_bbox"], geometry)}
        if label in FORMULA_LABELS:
            block["latex"] = latex_of(content)
            if latex_problem(block["latex"]) and "malformed LaTeX formula" not in reasons:
                reasons.append("malformed LaTeX formula")
        elif label == "table":
            block["markdown"] = clean_table(content.strip())
        elif content.strip():
            block["text"] = content.strip()
        if label == "formula_number" and id(item) in tagged:
            block["inMarkdown"] = True
        blocks.append(block)
    for match in MATH.finditer(text):
        if latex_problem(latex_of(match.group(0))) and "malformed LaTeX formula" not in reasons:
            reasons.append("malformed LaTeX formula")
    repeated = loop_problem(text)
    if repeated:
        reasons.append("repeated text: %s" % repeated)
    if token_limit_hits:
        reasons.append("%d recognition request(s) hit the token limit" % token_limit_hits)
    return {"markdown": text, "blocks": blocks, "reasons": reasons}


# ---------- engine run ----------

def protocol_stream():
    """Keep fd 1 for protocol lines; anything a library prints goes to stderr instead."""
    stream = os.fdopen(os.dup(1), "w", encoding="utf-8")
    os.dup2(2, 1)
    sys.stdout = sys.stderr
    return stream


def free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def package_version(name, interpreter=None):
    code = "import importlib.metadata as m; print(m.version(%r))" % name
    if interpreter is None:
        try:
            import importlib.metadata as metadata
            return metadata.version(name)
        except Exception:
            return "unknown"
    try:
        return subprocess.run([interpreter, "-I", "-c", code], capture_output=True, text=True, timeout=60).stdout.strip() or "unknown"
    except Exception:
        return "unknown"


def server_interpreter(server):
    try:
        with open(server, "rb") as handle:
            line = handle.readline(4096).decode("utf-8", "replace").strip()
            second = handle.readline(4096).decode("utf-8", "replace").strip()
    except OSError:
        return None
    if line.startswith("#!/") and " " not in line[2:] and not line.endswith("/sh"):
        return line[2:]
    # Launchers whose path is too long for a shebang line re-exec their Python from /bin/sh.
    match = re.match(r"^'''exec' '([^']+)'", second)
    return match.group(1) if match else None


def wait_until_ready(server, port, timeout, stream):
    started, notice = time.time(), 0.0
    while True:
        if server.poll() is not None:
            raise RuntimeError("mlx-vlm server exited with status %s; see the server log" % server.returncode)
        try:
            urllib.request.urlopen("http://127.0.0.1:%d/health" % port, timeout=2).read()
            return time.time() - started
        except Exception:
            pass
        if time.time() - started > timeout:
            raise RuntimeError("mlx-vlm server did not become ready within %d s" % timeout)
        if time.time() - notice > 15:
            emit(stream, "status", message="loading the recognition model")
            notice = time.time()
        time.sleep(0.5)


def stop(server):
    if server is None or server.poll() is not None:
        return
    for sig, wait in ((signal.SIGINT, 15), (signal.SIGTERM, 5)):
        try:
            os.killpg(server.pid, sig)
        except OSError:
            return
        try:
            server.wait(wait)
            return
        except subprocess.TimeoutExpired:
            continue
    os.killpg(server.pid, signal.SIGKILL)
    server.wait()


def token_limit_hits(log_path, offset):
    """Count finished requests that stopped at max_tokens since `offset` (mlx-vlm 0.7 log lines)."""
    try:
        with open(log_path, "rb") as handle:
            handle.seek(offset)
            data = handle.read().decode("utf-8", "replace")
            end = handle.tell()
    except OSError:
        return 0, offset
    hits = 0
    for line in data.splitlines():
        if "Request completed" in line and "finish_reason=length" in line:
            generated = re.search(r"generated_tokens=(\d+)", line)
            if generated is None or int(generated.group(1)) >= 256:
                hits += 1
    return hits, end


def render(document, number, dpi, max_side, directory):
    page = document[number - 1]
    shown_width, shown_height = page.get_size()
    rotation = page.get_rotation() % 360
    scale = min(dpi / 72.0, max_side / max(1.0, shown_width, shown_height))
    image = page.render(scale=scale, may_draw_forms=True).to_pil()
    path = os.path.join(directory, "page-%d.png" % number)
    image.save(path)
    left, bottom, right, top = page.get_cropbox()
    width, height = (shown_width, shown_height) if rotation in (0, 180) else (shown_height, shown_width)
    geometry = {"scale": scale, "rotation": rotation, "width": width, "height": height,
                "cropBox": [round(left, 2), round(bottom, 2), round(right - left, 2), round(top - bottom, 2)],
                "imageSize": [image.width, image.height], "renderDPI": round(scale * 72.0, 1)}
    page.close()
    return path, geometry


def run(args):
    stream = protocol_stream()
    pages = [int(value) for value in args.pages.split(",") if value]
    stopping = {"value": False}
    def interrupt(signum, frame):
        if not stopping["value"]:
            stopping["value"] = True
            raise KeyboardInterrupt
    signal.signal(signal.SIGINT, interrupt)
    signal.signal(signal.SIGTERM, interrupt)
    parent, server, log = os.getppid(), None, None
    try:
        import pypdfium2 as pdfium
        document = pdfium.PdfDocument(args.pdf)
        port = free_port()
        log = open(args.server_log, "ab")
        emit(stream, "status", message="starting the recognition server")
        server = subprocess.Popen([args.server, "--host", "127.0.0.1", "--port", str(port), "--model", args.model],
                                  stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        ready = wait_until_ready(server, port, args.server_timeout, stream)
        offset = os.path.getsize(args.server_log)
        started = time.time()
        from paddleocr import PaddleOCRVL
        pipeline = PaddleOCRVL(vl_rec_backend="mlx-vlm-server", vl_rec_server_url="http://127.0.0.1:%d/" % port,
                               vl_rec_api_model_name=args.model, vl_rec_max_concurrency=1,
                               use_doc_orientation_classify=False, use_doc_unwarping=False)
        engine = {"engine": "PaddleOCR-VL", "engineVersion": package_version("paddleocr"),
                  "paddlexVersion": package_version("paddlex"), "model": args.model, "layoutModel": "PP-DocLayoutV3",
                  "server": "mlx-vlm", "serverVersion": package_version("mlx-vlm", server_interpreter(args.server)),
                  "concurrency": 1, "serverReadySeconds": round(ready, 1), "pipelineSeconds": round(time.time() - started, 1)}
        emit(stream, "engine", protocol=PROTOCOL, **engine)
        with tempfile.TemporaryDirectory(prefix="bookside-structure-") as directory:
            for index, number in enumerate(pages):
                if os.getppid() != parent:
                    raise RuntimeError("Bookside stopped; the structure run stops with it")
                started = time.time()
                try:
                    path, geometry = render(document, number, args.dpi, args.max_side, directory)
                    output = list(pipeline.predict(path))[0]
                    markdown = output.markdown.get("markdown_texts", "") if isinstance(output.markdown, dict) else str(output.markdown)
                    hits, offset = token_limit_hits(args.server_log, offset)
                    record = page_record(output.json, markdown, geometry, hits)
                    os.remove(path)
                except KeyboardInterrupt:
                    raise
                except Exception as error:
                    emit(stream, "page_error", page=number, error=repr(error)[:500])
                    continue
                emit(stream, "page", page=number, index=index + 1, total=len(pages), seconds=round(time.time() - started, 2),
                     geometry=geometry, **record)
        emit(stream, "done")
        return 0
    except KeyboardInterrupt:
        emit(stream, "cancelled")
        return 130
    except Exception as error:
        import traceback
        traceback.print_exc()
        emit(stream, "error", message=repr(error)[:500])
        return 1
    finally:
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        stop(server)
        if log is not None:
            log.close()


def convert(args):
    with open(args.result, encoding="utf-8") as handle:
        result = json.load(handle)
    with open(args.markdown, encoding="utf-8") as handle:
        markdown = handle.read()
    record = page_record(result, markdown, json.loads(args.geometry), args.token_limit_hits)
    sys.stdout.write(json.dumps(record, ensure_ascii=False) + "\n")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    commands = parser.add_subparsers(dest="command", required=True)
    runner = commands.add_parser("run")
    runner.add_argument("--pdf", required=True)
    runner.add_argument("--pages", required=True, help="comma-separated 1-based PDF page indices")
    runner.add_argument("--server", required=True, help="mlx_vlm.server executable")
    runner.add_argument("--server-log", required=True)
    runner.add_argument("--model", default="PaddlePaddle/PaddleOCR-VL-1.6")
    runner.add_argument("--dpi", type=float, default=200.0)
    runner.add_argument("--max-side", type=float, default=2400.0, help="longest rendered side in pixels")
    runner.add_argument("--server-timeout", type=float, default=900.0)
    converter = commands.add_parser("convert")
    converter.add_argument("--result", required=True)
    converter.add_argument("--markdown", required=True)
    converter.add_argument("--geometry", required=True)
    converter.add_argument("--token-limit-hits", type=int, default=0)
    args = parser.parse_args()
    return run(args) if args.command == "run" else convert(args)


if __name__ == "__main__":
    sys.exit(main())
