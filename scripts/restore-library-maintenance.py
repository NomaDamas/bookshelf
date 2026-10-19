"""Restore this maintenance job's original selections and backed-up PDFs, keeping OCR copies and notes."""

import argparse
import json
import os
import signal
import subprocess
import sys
import time
import unicodedata
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("job", type=Path)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--stop-running", action="store_true")
    args = parser.parse_args()
    job = json.loads((args.job / "job.json").read_text())
    command = subprocess.run(
        ["ps", "-p", str(job["pid"]), "-o", "command="],
        text=True,
        capture_output=True,
        check=False,
    ).stdout
    if str(args.job) in command:
        if not args.apply or not args.stop_running:
            raise SystemExit(
                "Stop the maintenance job before restoring (or use --apply --stop-running)"
            )
        os.kill(job["pid"], signal.SIGTERM)
        for _ in range(90):
            current = subprocess.run(
                ["ps", "-p", str(job["pid"]), "-o", "command="],
                text=True,
                capture_output=True,
                check=False,
            ).stdout
            if str(args.job) not in current:
                break
            time.sleep(1)
        else:
            raise SystemExit("Maintenance is still saving; restoration has not started")
    options = job["args"]
    cli = options[options.index("--cli") + 1]
    env = {**os.environ, "BOOKSIDE_DATA_DIR": options[options.index("--data-dir") + 1]}
    events, history = {}, []
    for line in (
        Path(job["report"]).parent.joinpath("02-events.jsonl").read_text().splitlines()
    ):
        row = json.loads(line)
        history.append(row)
        events[row["key"]] = row
    books = {
        book["id"]: book
        for book in json.loads(
            subprocess.check_output([cli, "books"], env=env, text=True)
        )
    }
    selections = []
    for event in events.values():
        if event["status"] != "ocr_attached":
            continue
        book = books[event["book_id"]]
        if not book.get("ocrPath"):
            continue
        if unicodedata.normalize("NFC", book["ocrPath"]) != unicodedata.normalize(
            "NFC", event["output"]
        ):
            raise SystemExit(
                "A different OCR version is now selected; refusing to replace that choice: "
                + book["title"]
            )
        selections.append(book["id"])
    backups = {event["backup"] for event in history if event.get("backup")}
    if "--backup-root" in options:
        backup_root = Path(options[options.index("--backup-root") + 1])
        backups.update(
            str(manifest.parent) for manifest in backup_root.glob("*/manifest.jsonl")
        )
    backups = sorted(backups)
    print(
        json.dumps(
            {
                "apply": args.apply,
                "book_selections": len(selections),
                "spacing_backups": len(backups),
            },
            ensure_ascii=False,
        )
    )
    if not args.apply:
        return
    for book_id in selections:
        subprocess.run(
            [cli, "ocr-original", book_id], env=env, check=True, capture_output=True
        )
    helper = Path(__file__).with_name("restore-text-layer-backup.py")
    for backup in backups:
        subprocess.run([sys.executable, str(helper), backup], check=True)
    print("Original selections and PDFs restored. OCR copies and notes were retained.")


if __name__ == "__main__":
    main()
