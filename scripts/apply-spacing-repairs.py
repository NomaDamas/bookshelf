"""Apply validated PDF candidates with verified local backups. Dry-run unless --apply is passed."""

import argparse
import hashlib
import json
import os
import shutil
import uuid
from pathlib import Path


def digest(path):
    with path.open("rb") as file:
        return hashlib.file_digest(file, "sha256").hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--library-root", type=Path, required=True)
    parser.add_argument("--backup-dir", type=Path, required=True)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    root, backup_root = args.library_root.resolve(), args.backup_dir.absolute()
    rows = [json.loads(line) for line in args.manifest.read_text().splitlines()]
    if not rows or any(row.get("status") != "validated" for row in rows):
        raise SystemExit("Every manifest entry must be validated")
    sources = [Path(row["source"]) for row in rows]
    if len({p.resolve() for p in sources}) != len(sources):
        raise SystemExit("Duplicate source paths")
    for row, source in zip(rows, sources):
        if source.is_symlink() or not source.resolve().is_relative_to(root):
            raise SystemExit("Source must be a regular file within the chosen library")
        candidate = Path(row["candidate"])
        if source.resolve() == candidate.resolve():
            raise SystemExit("Candidate must be a different file")
        if (
            digest(source) != row["original_sha256"]
            or digest(candidate) != row["candidate_sha256"]
        ):
            raise SystemExit(
                "A source or candidate changed since validation: " + str(source)
            )
        if not row.get("changed_pages"):
            raise SystemExit("Refusing a candidate with no improved pages")
    print(
        json.dumps(
            {
                "verified_files": len(rows),
                "apply": args.apply,
                "backup": str(backup_root),
            }
        ),
        flush=True,
    )
    if not args.apply:
        return
    backup_root.mkdir(parents=True, exist_ok=False)
    with (backup_root / "manifest.jsonl").open("x", encoding="utf-8") as log:
        for row, source in zip(rows, sources):
            relative = source.resolve().relative_to(root)
            backup = backup_root / "originals" / relative
            backup.parent.mkdir(parents=True, exist_ok=True)
            expected_stat = source.stat()
            shutil.copy2(source, backup)
            if digest(backup) != row["original_sha256"]:
                raise SystemExit("Backup verification failed: " + str(source))
            temporary = source.parent / (
                ".bookside-layer-" + uuid.uuid4().hex + ".pdf"
            )
            try:
                shutil.copyfile(row["candidate"], temporary)
                os.chmod(temporary, expected_stat.st_mode & 0o777)
                if digest(temporary) != row["candidate_sha256"]:
                    raise SystemExit("Candidate copy verification failed")
                current = source.stat()
                if (current.st_ino, current.st_size, current.st_mtime_ns) != (
                    expected_stat.st_ino,
                    expected_stat.st_size,
                    expected_stat.st_mtime_ns,
                ):
                    raise SystemExit("Source changed while preparing replacement")
                record = {**row, "backup": str(backup), "phase": "prepared"}
                log.write(json.dumps(record, ensure_ascii=False) + "\n")
                log.flush()
                os.fsync(log.fileno())
                os.replace(temporary, source)
                if digest(source) != row["candidate_sha256"]:
                    raise SystemExit("Installed PDF verification failed")
                record["phase"] = "applied"
                log.write(json.dumps(record, ensure_ascii=False) + "\n")
                log.flush()
                os.fsync(log.fileno())
                print(
                    json.dumps(
                        {"applied": str(source), "backup": str(backup)},
                        ensure_ascii=False,
                    ),
                    flush=True,
                )
            finally:
                if temporary.exists():
                    temporary.unlink()


if __name__ == "__main__":
    main()
