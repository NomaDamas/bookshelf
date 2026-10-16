"""Repair standalone invisible GlyphLessFont spaces using matching Poppler text lines.

Only space-showing operands change. Letters, text matrices, images and visible content remain.
Unsupported, rotated, unmatched or ambiguous lines are left untouched. Never overwrites input/output.
Requires pikepdf and pdftotext. Without --output this reports a dry run.
"""

import argparse
import json
import subprocess
from collections import defaultdict
from pathlib import Path

import pikepdf


def compact(text):
    return "".join(c for c in text if not c.isspace())


def multiply(a, b):
    return (
        a[0] * b[0] + a[2] * b[1],
        a[1] * b[0] + a[3] * b[1],
        a[0] * b[2] + a[2] * b[3],
        a[1] * b[2] + a[3] * b[3],
        a[0] * b[4] + a[2] * b[5] + a[4],
        a[1] * b[4] + a[3] * b[5] + a[5],
    )


def target_boundaries(text):
    offset, result = 0, set()
    for char in text:
        if char.isspace():
            result.add(offset)
        else:
            offset += 1
    return result


def repair_page(pdf, page, reference):
    report = {"removed_spaces": 0, "matched_lines": 0, "unmatched_lines": 0}
    if int(page.get("/Rotate", 0)) % 360:
        return {**report, "skipped": "rotated page"}
    fonts = page.Resources.get("/Font", {})
    allowed = {
        str(name)
        for name, font in fonts.items()
        if "GlyphLessFont" in str(font.get("/BaseFont", ""))
        and font.get("/Encoding") == "/Identity-H"
    }
    if not allowed:
        return {**report, "skipped": "no supported top-level OCR font"}
    instructions = list(pikepdf.parse_content_stream(page))
    runs = []
    state = {"ctm": (1.0, 0.0, 0.0, 1.0, 0.0, 0.0), "font": "", "size": 1.0, "mode": 0}
    stack, tm = [], (1.0, 0.0, 0.0, 1.0, 0.0, 0.0)
    for index, instruction in enumerate(instructions):
        op, args = str(instruction.operator), instruction.operands
        if op == "q":
            stack.append(state.copy())
        elif op == "Q" and stack:
            state = stack.pop()
        elif op == "cm":
            state["ctm"] = multiply(state["ctm"], tuple(map(float, args)))
        elif op == "Tf":
            state["font"], state["size"] = str(args[0]), float(args[1])
        elif op == "Tr":
            state["mode"] = int(args[0])
        elif op == "Tm":
            tm = tuple(map(float, args))
        elif op in ("Td", "TD"):
            tm = multiply(tm, (1.0, 0.0, 0.0, 1.0, float(args[0]), float(args[1])))
        elif op in ("Tj", "TJ") and state["mode"] == 3 and state["font"] in allowed:
            values = [args[0]] if op == "Tj" else list(args[0])
            try:
                text = "".join(
                    bytes(v).decode("utf-16-be")
                    for v in values
                    if isinstance(v, pikepdf.String)
                )
            except UnicodeError:
                return {**report, "skipped": "unsupported font character encoding"}
            matrix = multiply(state["ctm"], tm)
            if (
                matrix[0] <= 0
                or matrix[3] <= 0
                or abs(matrix[1] / matrix[0]) > 0.02
                or abs(matrix[2] / matrix[3]) > 0.02
            ):
                continue
            if text:
                # A candidate space must be independently positioned; removing it cannot shift later glyphs.
                reset = False
                for following in instructions[index + 1 : index + 40]:
                    if str(following.operator) in ("Tm", "Td", "TD", "T*"):
                        reset = True
                        break
                    if str(following.operator) in ("Tj", "TJ", "'", '"'):
                        break
                standalone = (
                    text == " "
                    and len(values) == 1
                    and isinstance(values[0], pikepdf.String)
                    and reset
                )
                baseline = matrix[5] - matrix[1] / matrix[0] * matrix[4]
                runs.append(
                    {
                        "index": index,
                        "text": text,
                        "x": matrix[4],
                        "y": baseline,
                        "height": abs(matrix[3] * state["size"]),
                        "candidate": standalone,
                    }
                )
    if not runs:
        return {**report, "skipped": "no supported invisible text runs"}
    report["eligible_runs"] = len(runs)
    report["standalone_spaces"] = sum(r["candidate"] for r in runs)

    # Cluster only near-identical baselines, then match whole lines before using their whitespace.
    groups = []
    for run in sorted(runs, key=lambda r: (-r["y"], r["x"])):
        if groups and abs(groups[-1][0]["y"] - run["y"]) < max(
            0.5, min(groups[-1][0]["height"], run["height"]) * 0.06
        ):
            groups[-1].append(run)
        else:
            groups.append([run])
    reference_lines = defaultdict(list)
    reference_compact = compact(reference)
    reference_boundaries = target_boundaries(reference)
    for line in reference.splitlines():
        key = compact(line)
        if key:
            reference_lines[key].append(target_boundaries(line))

    for group in groups:
        group.sort(key=lambda r: r["x"])
        key = compact("".join(r["text"] for r in group))
        matches = reference_lines.get(key, [])
        if not matches and len(key) >= 8:
            start = reference_compact.find(key)
            if start >= 0 and reference_compact.find(key, start + 1) < 0:
                matches = [
                    {
                        n - start
                        for n in reference_boundaries
                        if start <= n <= start + len(key)
                    }
                ]
        # Never infer boundaries from similar or partially matched lines.
        if len(key) < 8 or not matches or any(m != matches[0] for m in matches):
            report["unmatched_lines"] += 1
            continue
        report["matched_lines"] += 1
        boundaries, offset = matches[0], 0
        for run in group:
            if run["candidate"] and offset not in boundaries and 0 < offset < len(key):
                old = instructions[run["index"]]
                operands = (
                    [pikepdf.String(b"")]
                    if str(old.operator) == "Tj"
                    else [pikepdf.Array([pikepdf.String(b"")])]
                )
                instructions[run["index"]] = pikepdf.ContentStreamInstruction(
                    operands, old.operator
                )
                report["removed_spaces"] += 1
            offset += len(compact(run["text"]))
    if report["removed_spaces"]:
        page.Contents = pdf.make_stream(pikepdf.unparse_content_stream(instructions))
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    source = args.input.resolve()
    if args.output and (args.output.exists() or args.output.resolve() == source):
        raise SystemExit("Refusing to overwrite the input or an existing output")
    before = source.stat()
    result = subprocess.run(
        ["pdftotext", str(source), "-"], check=True, text=True, capture_output=True
    )
    reference_pages = result.stdout.split("\f")
    with pikepdf.open(source) as pdf:
        if pdf.is_encrypted:
            raise SystemExit("Encrypted PDFs are not supported")
        reports = []
        for number, page in enumerate(pdf.pages, 1):
            report = repair_page(
                pdf,
                page,
                reference_pages[number - 1] if number <= len(reference_pages) else "",
            )
            reports.append({"page": number, **report})
        removed = sum(p["removed_spaces"] for p in reports)
        if args.output and removed:
            pdf.save(args.output)
    after = source.stat()
    if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
        raise SystemExit("Source changed during the operation; do not use this output")
    summary = {
        "source": str(source),
        "output": str(args.output) if args.output and removed else None,
        "dry_run": args.output is None,
        "removed_spaces": removed,
        "pages": reports,
        "source_metadata_unchanged": True,
    }
    args.report.write_text(
        json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    print(
        json.dumps(
            {k: v for k, v in summary.items() if k != "pages"}, ensure_ascii=False
        )
    )


if __name__ == "__main__":
    main()
