"""Follow a full-library audit, repair proven spacing errors, and prepare/verify OCR copies.

Dry-run by default. --apply authorizes backed-up spacing replacements and attaching verified
OCR copies. Originals are retained; candidates requiring review remain withheld in the app.
Run with the OCRmyPDF Python environment (pikepdf/Pillow), and an immutable CLI build.
"""

import argparse
import hashlib
import json
import os
import shutil
import signal
import subprocess
import sys
import threading
import time
import unicodedata
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path

import pikepdf

STOP = threading.Event()


def write_json(destination, value):
    temporary = destination.with_suffix(destination.suffix + ".tmp")
    temporary.write_text(
        json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    temporary.replace(destination)


def digest(filename):
    with Path(filename).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def image_hashes(filename):
    with pikepdf.open(filename) as pdf:
        return sorted(
            (
                int(obj.get("/Width", 0)),
                int(obj.get("/Height", 0)),
                hashlib.sha256(obj.read_raw_bytes()).hexdigest(),
            )
            for obj in pdf.objects
            if isinstance(obj, pikepdf.Stream) and obj.get("/Subtype") == "/Image"
        )


def run(command, log, environment, timeout=14400, atomic=False):
    with log.open("a", encoding="utf-8") as stderr:
        process = subprocess.Popen(
            command,
            stdout=subprocess.PIPE,
            stderr=stderr,
            text=True,
            env=environment,
            start_new_session=True,
        )
        started = time.monotonic()
        while True:
            try:
                stdout, _ = process.communicate(timeout=2)
                break
            except subprocess.TimeoutExpired:
                if (
                    STOP.is_set() and not atomic
                ) or time.monotonic() - started > timeout:
                    os.killpg(process.pid, signal.SIGINT)
                    try:
                        process.communicate(timeout=30)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, signal.SIGTERM)
                        process.communicate(timeout=30)
                    raise RuntimeError("stopped" if STOP.is_set() else "timed out")
        if process.returncode:
            raise RuntimeError(
                f"{Path(command[0]).name} exited {process.returncode}; see {log}"
            )
        return stdout


def next_output(source):
    stem = source.stem.removesuffix("_ocr")
    for number in range(1, 10000):
        suffix = "_ocr.pdf" if number == 1 else f"_{number}_ocr.pdf"
        candidate = source.with_name(stem + suffix)
        if not candidate.exists():
            return candidate
    raise RuntimeError("No unused output filename")


def process_book(row, args, environment):
    source = Path(row["path"])
    folder = args.output / "01-books" / row["key"]
    folder.mkdir(parents=True, exist_ok=True)
    result = {
        "key": row["key"],
        "source": str(source),
        "audit_status": row["status"],
        "status": "planned",
    }
    log = folder / "process.log"
    scripts = Path(__file__).resolve().parent
    if not args.apply:
        return result
    try:
        if source.is_symlink() or not source.resolve().is_relative_to(
            args.library_root.resolve()
        ):
            raise RuntimeError("Source is outside the library or is a symlink")
        if row["status"] == "spacing_suspect":
            single = folder / "audit.jsonl"
            single.write_text(
                json.dumps(row, ensure_ascii=False) + "\n", encoding="utf-8"
            )
            stage, final = folder / "stage", folder / "verified"
            if not stage.exists():
                run(
                    [
                        sys.executable,
                        str(scripts / "stage-spacing-repairs.py"),
                        str(single),
                        str(stage),
                        "--python",
                        sys.executable,
                        "--probe",
                        str(args.probe),
                    ],
                    log,
                    environment,
                )
            if not final.exists():
                run(
                    [
                        sys.executable,
                        str(scripts / "finalize-spacing-repairs.py"),
                        str(single),
                        str(stage),
                        str(final),
                        "--probe",
                        str(args.probe),
                    ],
                    log,
                    environment,
                )
            records = [
                json.loads(line)
                for line in (final / "results.jsonl").read_text().splitlines()
            ]
            repair = records[0]
            if repair["status"] == "validated" and repair["changed_pages"] > 0:
                backup = args.backup_root / row["key"]
                if not backup.exists():
                    run(
                        [
                            sys.executable,
                            str(scripts / "apply-spacing-repairs.py"),
                            str(final / "results.jsonl"),
                            "--library-root",
                            str(args.library_root),
                            "--backup-dir",
                            str(backup),
                            "--apply",
                        ],
                        log,
                        environment,
                        atomic=True,
                    )
                    shutil.copy2(
                        scripts / "restore-text-layer-backup.py",
                        backup / "restore-text-layer-backup.py",
                    )
                elif digest(source) != repair["candidate_sha256"]:
                    raise RuntimeError(
                        "Previously repaired source has changed; do not replay replacement"
                    )
                result.update(
                    spacing_pages=repair["changed_pages"],
                    backup=str(backup),
                    residual_pages=repair["residual_spaced_pages"],
                    preserved_pages=repair["preserved_pages"],
                )
                write_json(
                    folder / "spacing-applied.json",
                    {**result, "status": "spacing_applied"},
                )
                if not repair["residual_spaced_pages"]:
                    return {**result, "status": "spacing_applied"}
        if STOP.is_set():
            return {**result, "status": "stopped"}
        # Use the canonical store so the resulting copy keeps the user's book ID and notebook.
        books = json.loads(run([str(args.cli), "books"], log, environment, timeout=60))
        wanted = unicodedata.normalize("NFC", str(source.resolve()))
        book = next(
            (
                b
                for b in books
                if wanted
                in {
                    unicodedata.normalize("NFC", b["sourcePath"]),
                    unicodedata.normalize("NFC", b.get("ocrPath") or ""),
                }
            ),
            None,
        )
        if book is None:
            book = json.loads(
                run(
                    [str(args.cli), "import", str(source)], log, environment, timeout=60
                )
            )[0]
        if (
            book.get("ocrPath")
            and unicodedata.normalize("NFC", book["ocrPath"]) != wanted
        ):
            return {
                **result,
                "status": "existing_ocr_version",
                "output": book["ocrPath"],
            }
        checkpoint = folder / "ocr-result.json"
        if checkpoint.exists():
            ocr = json.loads(checkpoint.read_text())
        else:
            output = next_output(source)
            command = [
                str(args.cli),
                "ocr",
                book["id"],
                "--language",
                "und",
                "--review-only",
                "--output",
                str(output),
            ]
            if row["status"] == "spacing_suspect":
                command.append("--redo")
            ocr = json.loads(run(command, log, environment))
            write_json(checkpoint, ocr)
        quality = ocr["quality"]
        result.update(output=ocr["path"], report=ocr["reportPath"], quality=quality)
        if (
            digest(source) != ocr["sourceSHA256"]
            or digest(ocr["path"]) != ocr["outputSHA256"]
        ):
            raise RuntimeError("Source or OCR candidate changed after validation")
        if image_hashes(source) != image_hashes(ocr["path"]):
            return {
                **result,
                "status": "review_required",
                "reason": "image_stream_difference",
            }
        flags = (
            quality["spacingSuspectPages"]
            + quality["textLossPages"]
            + (quality.get("textGrowthPages") or [])
            + quality["extractorDisagreementPages"]
            + [
                check["page"]
                for check in quality.get("renderingChecks", [])
                if not check["passed"]
            ]
        )
        if (
            flags
            or not quality["popplerChecked"]
            or quality["substantialTextPages"] < max(1, quality["pageCount"] // 2)
        ):
            return {
                **result,
                "status": "review_required",
                "reason": "quality_flags_or_low_text_coverage",
            }
        if STOP.is_set():
            return {**result, "status": "stopped"}
        run(
            [str(args.cli), "ocr-accept", ocr["reportPath"]],
            log,
            environment,
            timeout=120,
            atomic=True,
        )
        return {**result, "status": "ocr_attached", "book_id": book["id"]}
    except (
        OSError,
        ValueError,
        RuntimeError,
        KeyError,
        subprocess.SubprocessError,
    ) as error:
        return {
            **result,
            "status": "stopped" if STOP.is_set() else "failed",
            "error": str(error),
        }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--audit-dir", type=Path, required=True)
    parser.add_argument("--library-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--backup-root", type=Path, required=True)
    parser.add_argument("--cli", type=Path, required=True)
    parser.add_argument("--probe", type=Path, required=True)
    parser.add_argument("--data-dir", type=Path, required=True)
    parser.add_argument("--jobs", type=int, choices=range(1, 5), default=2)
    parser.add_argument("--follow", action="store_true")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    environment = {**os.environ, "BOOKSIDE_DATA_DIR": str(args.data_dir)}
    signal.signal(signal.SIGTERM, lambda *_: STOP.set())
    signal.signal(signal.SIGINT, lambda *_: STOP.set())
    write_json(
        args.output / "00-job.json",
        {
            "pid": os.getpid(),
            "started": datetime.now(timezone.utc).isoformat(),
            "arguments": sys.argv,
            "apply": args.apply,
        },
    )
    event_path = args.output / "02-events.jsonl"
    events = (
        [json.loads(line) for line in event_path.read_text().splitlines()]
        if event_path.exists()
        else []
    )
    latest = {event["key"]: event for event in events}
    completed = {
        key
        for key, event in latest.items()
        if event["status"] not in {"failed", "stopped"}
    }
    rows, offset, futures = {}, 0, {}
    with (
        event_path.open("a", encoding="utf-8") as event_log,
        ThreadPoolExecutor(max_workers=args.jobs) as pool,
    ):
        while True:
            audit = args.audit_dir / "00-audit.jsonl"
            if audit.exists():
                with audit.open(encoding="utf-8") as stream:
                    stream.seek(offset)
                    while True:
                        start = stream.tell()
                        line = stream.readline()
                        if not line or not line.endswith("\n"):
                            offset = start
                            break
                        value = json.loads(line)
                        if (
                            value["status"] == "no_spacing_flag"
                            and value.get("page_count", 0) >= 5
                            and value.get("text_pages", 0) < value["page_count"] * 0.8
                        ):
                            value["status"] = "partial_text"
                        rows[value["key"]] = {
                            k: v for k, v in value.items() if k not in {"metrics"}
                        }
            # Finish smaller books first so real-library validation feedback arrives early.
            for key, row in sorted(
                rows.items(), key=lambda item: item[1].get("page_count", 1_000_000)
            ):
                if len(futures) >= args.jobs or STOP.is_set():
                    break
                if (
                    key not in completed
                    and key not in futures
                    and row["status"]
                    in {"spacing_suspect", "little_text", "partial_text"}
                ):
                    futures[key] = pool.submit(process_book, row, args, environment)
            for key, future in list(futures.items()):
                if future.done():
                    result = future.result()
                    event_log.write(json.dumps(result, ensure_ascii=False) + "\n")
                    event_log.flush()
                    os.fsync(event_log.fileno())
                    events.append(result)
                    latest[key] = result
                    completed.add(key)
                    del futures[key]
                    print(
                        json.dumps(
                            {"completed": len(completed), **result}, ensure_ascii=False
                        ),
                        flush=True,
                    )
            audit_done = (
                args.audit_dir / "00-summary.json"
            ).exists() or not args.follow
            remaining = sum(
                key not in completed
                and row["status"] in {"spacing_suspect", "little_text", "partial_text"}
                for key, row in rows.items()
            )
            counts = {}
            for event in latest.values():
                counts[event["status"]] = counts.get(event["status"], 0) + 1
            finished = (audit_done and remaining == 0 and not futures) or (
                STOP.is_set() and not futures
            )
            summary = {
                "running": not finished,
                "stopped": STOP.is_set(),
                "audit_finished": audit_done,
                "audit_records": len(rows),
                "audited_pages": sum(r.get("page_count", 0) for r in rows.values()),
                "audit_unavailable": sum(r["status"] == "error" for r in rows.values()),
                "queued_or_running": remaining,
                "completed": counts,
                "updated": datetime.now(timezone.utc).isoformat(),
            }
            write_json(args.output / "03-summary.json", summary)
            if finished:
                break
            time.sleep(2)
    lines = [
        "# PDF 라이브러리 개선 결과",
        "",
        "작업이 중지됐습니다. 같은 명령으로 이어서 처리할 수 있습니다."
        if STOP.is_set()
        else "접근 가능한 대상의 자동 처리를 마쳤습니다. 검토 필요/접근 실패 파일은 완료로 처리하지 않았습니다.",
        "",
        "```json",
        json.dumps(summary, ensure_ascii=False, indent=2),
        "```",
        "",
        "| 파일 | 결과 |",
        "| --- | --- |",
    ]
    lines.extend(
        f"| {Path(event['source']).name.replace('|', '/')} | {event['status']} |"
        for event in latest.values()
    )
    (args.output / "04-report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
