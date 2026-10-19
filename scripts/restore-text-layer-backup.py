"""Restore originals only when current files still match this repair's recorded hashes."""

import hashlib
import json
import os
import shutil
import sys
import uuid
from pathlib import Path


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as file:
        for block in iter(lambda: file.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def main():
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent
    records = {}
    for line in (root / "manifest.jsonl").read_text().splitlines():
        row = json.loads(line)
        records[row["source"]] = row
    for row in records.values():
        source, backup = Path(row["source"]), Path(row["backup"])
        if digest(backup) != row["original_sha256"]:
            raise SystemExit("Original backup changed: " + str(backup))
        current = digest(source)
        if current == row["original_sha256"]:
            continue
        if current != row["candidate_sha256"]:
            raise SystemExit(
                "PDF changed after repair; refusing to overwrite: " + str(source)
            )
        relative = backup.relative_to(root / "originals")
        repaired_copy = root / "repaired" / relative
        repaired_copy.parent.mkdir(parents=True, exist_ok=True)
        if not repaired_copy.exists():
            shutil.copy2(source, repaired_copy)
        temporary = source.parent / (".bookside-restore-" + uuid.uuid4().hex + ".pdf")
        try:
            shutil.copy2(backup, temporary)
            if digest(temporary) != row["original_sha256"]:
                raise SystemExit("Restore copy verification failed")
            if digest(source) != row["candidate_sha256"]:
                raise SystemExit("PDF changed during restore")
            os.replace(temporary, source)
        finally:
            if temporary.exists():
                temporary.unlink()
        print("Restored: " + str(source))


if __name__ == "__main__":
    main()
