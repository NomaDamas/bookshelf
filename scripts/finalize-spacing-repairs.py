"""Build verified candidates, restoring any pages whose PDFKit reading order changed."""

import argparse
import json
import shutil
import subprocess
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import pikepdf


def finish(row, stage, output, probe):
    folder = stage / row["key"]
    deadline = time.monotonic() + 1200
    while not (folder / "result.json").exists():
        if time.monotonic() > deadline:
            raise TimeoutError(str(folder))
        time.sleep(1)
    source = Path(row["path"])
    draft = folder / source.name
    validation_path = folder / "validation.json"
    if not validation_path.exists():
        return {
            "key": row["key"],
            "source": str(source),
            "status": "failed_before_validation",
        }
    validation = json.loads(validation_path.read_text())
    if validation["failures"] not in ([], ["non-whitespace text"]):
        return {
            "key": row["key"],
            "source": str(source),
            "status": "unsupported_validation_failure",
            "failures": validation["failures"],
        }
    out = output / row["key"]
    out.mkdir()
    candidate = out / source.name
    restored = validation["changed_character_pages"]
    if restored:
        with pikepdf.open(source) as original, pikepdf.open(draft) as repaired:
            for number in restored:
                repaired.pages[number - 1] = original.pages[number - 1]
            repaired.save(candidate)
    else:
        shutil.copy2(draft, candidate)
    scripts = Path(__file__).resolve().parent
    with (out / "validation.log").open("w") as log:
        run = subprocess.run(
            [
                __import__("sys").executable,
                str(scripts / "validate-text-layer.py"),
                str(source),
                str(candidate),
                "--probe",
                str(probe),
                "--report",
                str(out / "validation.json"),
                "--render-pages",
                ",".join(map(str, row["suspect_pages"][:2])),
            ],
            check=False,
            stdout=log,
            stderr=subprocess.STDOUT,
            timeout=900,
        )
    final = json.loads((out / "validation.json").read_text())
    result = {
        "status": "validated" if run.returncode == 0 else "failed",
        "key": row["key"],
        "source": str(source),
        "candidate": str(candidate),
        "page_count": final["page_count"],
        "changed_pages": len(final["changed_spacing_pages"]),
        "preserved_pages": restored,
        "original_spaced_pages": len(final["original_spaced_pages"]),
        "residual_spaced_pages": final["residual_spaced_pages"],
        "original_sha256": final["original_sha256"],
        "candidate_sha256": final["repaired_sha256"],
        "failures": final["failures"],
    }
    (out / "result.json").write_text(
        json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("audit", type=Path)
    parser.add_argument("stage", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--probe", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir()
    rows = [json.loads(line) for line in args.audit.read_text().splitlines()]
    rows = [row for row in rows if row["status"] == "spacing_suspect"]
    with (
        (args.output / "results.jsonl").open("w", encoding="utf-8") as file,
        ThreadPoolExecutor(max_workers=2) as pool,
    ):
        futures = [
            pool.submit(finish, row, args.stage, args.output, args.probe.resolve())
            for row in rows
        ]
        for number, future in enumerate(as_completed(futures), 1):
            result = future.result()
            file.write(json.dumps(result, ensure_ascii=False) + "\n")
            file.flush()
            print(
                json.dumps(
                    {"completed": number, "total": len(rows), **result},
                    ensure_ascii=False,
                ),
                flush=True,
            )


if __name__ == "__main__":
    main()
