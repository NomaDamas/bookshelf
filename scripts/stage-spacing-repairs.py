"""Create and validate candidate copies from an audit. Does not replace library files."""

import argparse
import json
import subprocess
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path


def stage(row, output, python, probe):
    source = Path(row["path"])
    folder = output / row["key"]
    folder.mkdir()
    candidate = folder / source.name
    scripts = Path(__file__).resolve().parent
    try:
        with (folder / "process.log").open("w") as log:
            subprocess.run(
                [
                    str(python),
                    str(scripts / "repair-ocr-spacing.py"),
                    str(source),
                    "--output",
                    str(candidate),
                    "--report",
                    str(folder / "repair.json"),
                ],
                check=True,
                stdout=log,
                stderr=subprocess.STDOUT,
                timeout=900,
            )
            subprocess.run(
                [
                    str(python),
                    str(scripts / "validate-text-layer.py"),
                    str(source),
                    str(candidate),
                    "--probe",
                    str(probe),
                    "--report",
                    str(folder / "validation.json"),
                    "--render-pages",
                    ",".join(map(str, row["suspect_pages"][:2])),
                ],
                check=True,
                stdout=log,
                stderr=subprocess.STDOUT,
                timeout=900,
            )
        validation = json.loads((folder / "validation.json").read_text())
        result = {
            "status": "validated",
            "source": str(source),
            "candidate": str(candidate),
            "key": row["key"],
            "page_count": validation["page_count"],
            "changed_pages": len(validation["changed_spacing_pages"]),
            "original_spaced_pages": len(validation["original_spaced_pages"]),
            "residual_spaced_pages": validation["residual_spaced_pages"],
            "original_sha256": validation["original_sha256"],
            "candidate_sha256": validation["repaired_sha256"],
        }
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        result = {
            "status": "failed",
            "source": str(source),
            "key": row["key"],
            "error": str(error),
        }
    (folder / "result.json").write_text(
        json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("audit", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--python", type=Path, required=True)
    parser.add_argument("--probe", type=Path, required=True)
    args = parser.parse_args()
    # Keep a venv executable's symlink path: resolving it would bypass its pyvenv.cfg.
    python = args.python.absolute()
    subprocess.run(
        [str(python), "-c", "import pikepdf; from PIL import Image"],
        check=True,
        capture_output=True,
    )
    args.output.mkdir()
    rows = [json.loads(line) for line in args.audit.read_text().splitlines()]
    rows = [row for row in rows if row["status"] == "spacing_suspect"]
    with (
        (args.output / "results.jsonl").open("w", encoding="utf-8") as result_file,
        ThreadPoolExecutor(max_workers=2) as pool,
    ):
        futures = [
            pool.submit(stage, row, args.output.resolve(), python, args.probe.resolve())
            for row in rows
        ]
        for number, future in enumerate(as_completed(futures), 1):
            result = future.result()
            result_file.write(json.dumps(result, ensure_ascii=False) + "\n")
            result_file.flush()
            print(
                json.dumps(
                    {"completed": number, "total": len(rows), **result},
                    ensure_ascii=False,
                ),
                flush=True,
            )


if __name__ == "__main__":
    main()
