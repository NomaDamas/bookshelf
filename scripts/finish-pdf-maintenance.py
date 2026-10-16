"""After the main pass, audit previously unavailable PDFs that have since downloaded, then resume once."""

import json
import os
import subprocess
import sys
import time
from pathlib import Path

job_dir = Path(sys.argv[1]).resolve()
state_file = job_dir / "finalizer.json"


def state(phase, **extra):
    temporary = state_file.with_suffix(".tmp")
    temporary.write_text(
        json.dumps(
            {"pid": os.getpid(), "phase": phase, **extra}, ensure_ascii=False, indent=2
        ),
        encoding="utf-8",
    )
    temporary.replace(state_file)


def metadata():
    return json.loads((job_dir / "job.json").read_text())


def wait_for_main():
    while True:
        job = metadata()
        command = subprocess.run(
            ["ps", "-p", str(job["pid"]), "-o", "command="],
            text=True,
            capture_output=True,
            check=False,
        ).stdout
        if str(job_dir / "tools/maintain-pdf-library.py") not in command:
            return json.loads(Path(job["report"]).read_text())
        time.sleep(15)


try:
    state("waiting")
    subprocess.Popen(
        ["caffeinate", "-i", "-w", str(os.getpid())],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    summary = wait_for_main()
    if summary.get("stopped"):
        state("stopped")
        raise SystemExit(0)
    if summary.get("running"):
        raise RuntimeError("The main controller exited without a completion record")
    job = metadata()
    arguments = job["args"]
    audit = Path(arguments[arguments.index("--audit-dir") + 1])
    root = Path(arguments[arguments.index("--library-root") + 1])
    probe = arguments[arguments.index("--probe") + 1]
    rows = {}
    with (audit / "00-audit.jsonl").open(encoding="utf-8") as stream:
        for line in stream:
            row = json.loads(line)
            rows[row["key"]] = row
    ready = []
    for row in rows.values():
        source = Path(row["path"])
        if (
            row["status"] == "error"
            and source.exists()
            and not source.stat().st_flags & 0x40000000
        ):
            ready.append(str(source))
    if ready:
        state("auditing", files=len(ready))
        listing = job_dir / "late-downloads.json"
        listing.write_text(
            json.dumps(ready, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        materializer = json.loads((audit.parent / "00-job.json").read_text())["args"]
        materializer = materializer[materializer.index("--materializer") + 1]
        subprocess.run(
            [
                sys.executable,
                str(job_dir / "tools/audit-text-layer.py"),
                str(root),
                str(audit),
                "--resume",
                "--all-pages",
                "--file-list",
                str(listing),
                "--jobs",
                "2",
                "--probe",
                probe,
                "--materializer",
                materializer,
            ],
            check=True,
        )
        state("resuming", files=len(ready))
        with Path(job["log"]).open("a", encoding="utf-8") as log:
            process = subprocess.Popen(
                arguments, stdout=log, stderr=subprocess.STDOUT, start_new_session=True
            )
        job["pid"] = process.pid
        temporary = job_dir / "job.json.tmp"
        temporary.write_text(
            json.dumps(job, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        temporary.replace(job_dir / "job.json")
        subprocess.Popen(
            ["caffeinate", "-i", "-w", str(process.pid)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        summary = wait_for_main()
        if summary.get("running"):
            raise RuntimeError(
                "The resumed controller exited without a completion record"
            )
    state(
        "stopped" if summary.get("stopped") else "complete", late_downloads=len(ready)
    )
except Exception as error:
    state("error", error=str(error))
    raise
