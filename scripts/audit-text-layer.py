"""Read-only PDFKit/Poppler comparison; placeholder download requires an explicit file list."""

import argparse
import hashlib
import json
import os
import re
import signal
import stat
import subprocess
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from difflib import SequenceMatcher
from pathlib import Path


def materialize(script, pdf, wait):
    process = subprocess.Popen(
        [str(script), str(pdf), "--wait", str(wait)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        start_new_session=True,
    )
    try:
        stdout, stderr = process.communicate(timeout=wait + 15)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGTERM)
        process.communicate()
        raise
    if process.returncode:
        raise RuntimeError((stdout + stderr).decode("utf-8", errors="replace")[-1500:])


def metrics(text):
    runs = re.findall(r"[가-힣]+", text)
    count = sum(map(len, runs))
    latin = re.findall(r"[A-Za-z]+", text)
    latin_count = sum(map(len, latin))
    return {
        "characters": len(text),
        "nonspace": len(re.sub(r"\s+", "", text)),
        "hangul_characters": count,
        "hangul_mean_run": round(count / len(runs), 3) if runs else None,
        "hangul_single_fraction": round(sum(len(x) == 1 for x in runs) / len(runs), 3)
        if runs
        else None,
        "latin_characters": latin_count,
        "latin_mean_run": round(latin_count / len(latin), 3) if latin else None,
        "latin_single_fraction": round(sum(len(x) == 1 for x in latin) / len(latin), 3)
        if latin
        else None,
    }


def inspect(
    pdf,
    root,
    probe,
    materializer,
    output,
    download=False,
    all_pages=False,
    download_wait=60,
):
    key = hashlib.sha256(str(pdf.relative_to(root)).encode()).hexdigest()[:16]
    result = {"path": str(pdf), "relative_path": str(pdf.relative_to(root)), "key": key}
    try:
        before = pdf.stat()
        result.update(size=before.st_size, mtime_ns=before.st_mtime_ns)
        if before.st_flags & getattr(stat, "SF_DATALESS", 0x40000000):
            if not download:
                return {**result, "status": "icloud_placeholder_skipped"}
            # Prime FileProvider first: a placeholder read can block before the helper reaches its fallback.
            subprocess.run(
                ["brctl", "download", str(pdf)],
                check=True,
                capture_output=True,
                timeout=15,
            )
            materialize(materializer, pdf, download_wait)
        else:
            materialize(materializer, pdf, 5)
        native = subprocess.run(
            [str(probe), str(pdf), *(["all"] if all_pages else [])],
            check=True,
            capture_output=True,
            text=True,
            timeout=600 if all_pages else 60,
        )
        data = json.loads(native.stdout)
        result.update(
            page_count=data["page_count"],
            creator=data["creator"],
            producer=data["producer"],
        )
        external_pages = None
        if all_pages:
            external_pages = subprocess.run(
                ["pdftotext", str(pdf), "-"],
                check=True,
                capture_output=True,
                text=True,
                timeout=300,
            ).stdout.split("\f")
        pages = []
        for entry in data["pages"]:
            number = str(entry["page"])
            external = (
                external_pages[entry["page"] - 1]
                if external_pages is not None and entry["page"] <= len(external_pages)
                else subprocess.run(
                    ["pdftotext", "-f", number, "-l", number, str(pdf), "-"],
                    check=True,
                    capture_output=True,
                    text=True,
                    timeout=30,
                ).stdout
            )
            a, b = metrics(entry["text"]), metrics(external)
            compact_a, compact_b = (
                re.sub(r"\s+", "", entry["text"]),
                re.sub(r"\s+", "", external),
            )
            excess = (
                a["hangul_characters"] >= 80
                and b["hangul_characters"] >= 80
                and a["hangul_mean_run"] < 1.45
                and b["hangul_mean_run"] > 1.8
                and a["hangul_single_fraction"] > 0.65
            )
            excess = excess or (
                a["latin_characters"] >= 120
                and b["latin_characters"] >= 120
                and a["latin_mean_run"] < 1.6
                and b["latin_mean_run"] > 2.5
                and a["latin_single_fraction"] > 0.65
            )
            agreement = (
                1.0
                if compact_a == compact_b
                else (
                    SequenceMatcher(None, compact_a, compact_b, autojunk=False).ratio()
                    if excess or not all_pages
                    else None
                )
            )
            excess = excess and agreement >= 0.93
            pages.append(
                {
                    **entry,
                    "poppler_text": external,
                    "pdfkit_metrics": a,
                    "poppler_metrics": b,
                    "nonspace_agreement": round(agreement, 4)
                    if agreement is not None
                    else None,
                    "pdfkit_spacing_suspect": excess,
                }
            )
        result["sample_pages"] = [p["page"] for p in pages]
        result["inspection_scope"] = "all_pages" if all_pages else "sample"
        result["text_pages"] = sum(p["pdfkit_metrics"]["nonspace"] > 30 for p in pages)
        result["low_text_pages"] = [
            p["page"] for p in pages if p["pdfkit_metrics"]["nonspace"] <= 30
        ]
        result["suspect_pages"] = [
            p["page"] for p in pages if p["pdfkit_spacing_suspect"]
        ]
        result["status"] = (
            "spacing_suspect"
            if result["suspect_pages"]
            else "no_spacing_flag"
            if all_pages
            else "no_spacing_flag_in_sample"
        )
        if not any(p["pdfkit_metrics"]["nonspace"] > 30 for p in pages):
            result["status"] = "little_text" if all_pages else "little_text_in_sample"
        result["metrics"] = [
            {k: v for k, v in p.items() if k not in ("text", "poppler_text")}
            for p in pages
        ]
        after = pdf.stat()
        result["source_metadata_unchanged"] = (before.st_size, before.st_mtime_ns) == (
            after.st_size,
            after.st_mtime_ns,
        )
        # Keep diagnostics bounded: metrics cover every page; text excerpts are only examples.
        samples = (
            pages
            if not all_pages
            else [
                p
                for p in pages
                if p["page"]
                in set(
                    result["suspect_pages"][:10]
                    + [1, max(1, data["page_count"] // 2), data["page_count"]]
                )
            ]
        )
        (output / "01-samples" / f"{key}.json").write_text(
            json.dumps({**result, "pages": samples}, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        result.update(status="error", error=str(error))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--probe", type=Path, required=True)
    parser.add_argument("--materializer", type=Path, required=True)
    parser.add_argument("--file-list", type=Path)
    parser.add_argument("--download-placeholders", action="store_true")
    parser.add_argument(
        "--all-pages",
        action="store_true",
        help="Inspect text on every page, not only three samples",
    )
    parser.add_argument("--jobs", type=int, choices=range(1, 9), default=2)
    parser.add_argument("--download-wait", type=int, default=60)
    parser.add_argument(
        "--resume",
        action="store_true",
        help="Append a retry for an explicit file list, preserving previous audit records",
    )
    args = parser.parse_args()
    root, output = args.root.resolve(), args.output.resolve()
    if args.download_placeholders and not args.file_list:
        raise SystemExit("Placeholder downloads require an explicit --file-list")
    output.mkdir(parents=True, exist_ok=True)
    (output / "01-samples").mkdir(exist_ok=True)
    manifest = output / "00-audit.jsonl"
    previous = {}
    if args.resume:
        if (
            not args.file_list
            or not manifest.exists()
            or not (output / "00-summary.json").exists()
        ):
            raise SystemExit(
                "Resume needs a completed audit and an explicit --file-list"
            )
        with manifest.open(encoding="utf-8") as stream:
            for line in stream:
                entry = json.loads(line)
                previous[entry["key"]] = entry["status"]
        history = output / "00-history"
        history.mkdir(exist_ok=True)
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S")
        for name in ["00-run.json", "00-summary.json"]:
            (output / name).rename(history / f"{stamp}-{name}")
    elif manifest.exists():
        raise SystemExit("Audit output already exists; choose a new output directory")
    excluded = {
        "00-Materials",
        "context",
        "scripts",
        "prompts",
        "_DEDUP_STAGING",
        "node_modules",
    }
    files = []
    if args.file_list:
        files = [Path(p) for p in json.loads(args.file_list.read_text())]
        if any(not p.resolve().is_relative_to(root) for p in files):
            raise SystemExit("Every listed PDF must be within the chosen root")
    else:
        for folder, directories, names in os.walk(root):
            directories[:] = [
                d for d in directories if not d.startswith(".") and d not in excluded
            ]
            files.extend(
                Path(folder) / name for name in names if name.lower().endswith(".pdf")
            )
    files.sort()
    (output / "00-run.json").write_text(
        json.dumps(
            {
                "pid": os.getpid(),
                "root": str(root),
                "files": len(files),
                "started": datetime.now(timezone.utc).isoformat(),
                "read_only": True,
                "sample_rule": "all pages; spacing/coverage indicators only, not full OCR accuracy"
                if args.all_pages
                else "pages 10, middle, 10 before end; clamped; no full-text accuracy claim",
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    counts = {}
    for status in previous.values():
        counts[status] = counts.get(status, 0) + 1
    with (
        manifest.open("a" if args.resume else "w", encoding="utf-8") as stream,
        ThreadPoolExecutor(max_workers=args.jobs) as pool,
    ):
        futures = [
            pool.submit(
                inspect,
                pdf,
                root,
                args.probe.resolve(),
                args.materializer.resolve(),
                output,
                args.download_placeholders,
                args.all_pages,
                args.download_wait,
            )
            for pdf in files
        ]
        for completed, future in enumerate(as_completed(futures), 1):
            record = future.result()
            if record["key"] in previous:
                counts[previous[record["key"]]] -= 1
            previous[record["key"]] = record["status"]
            counts[record["status"]] = counts.get(record["status"], 0) + 1
            stream.write(json.dumps(record, ensure_ascii=False) + "\n")
            stream.flush()
            print(
                json.dumps(
                    {
                        "completed": completed,
                        "total": len(files),
                        "counts": counts,
                        "last": record["relative_path"],
                    },
                    ensure_ascii=False,
                ),
                flush=True,
            )
    (output / "00-summary.json").write_text(
        json.dumps(
            {
                "files": len(previous),
                "attempted_files": len(files),
                "counts": counts,
                "finished": datetime.now(timezone.utc).isoformat(),
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
