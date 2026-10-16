"""Exercise real legacy OCR repair, review-before-attach, and stale-result rejection on synthetic PDFs."""

import hashlib
import json
import os
import subprocess
import sys
import uuid
from pathlib import Path

root = Path(__file__).resolve().parents[1]
binary = Path(sys.argv[1]).resolve()
run = root / ".runtime" / ("ocr-review-check-" + uuid.uuid4().hex[:8])
run.mkdir(parents=True)
scan, source, output = (
    run / name for name in ["scan.pdf", "legacy_ocr.pdf", "improved_ocr.pdf"]
)
env = {**os.environ, "BOOKSHELF_DATA_DIR": str(run / "data")}


def command(arguments, timeout=240):
    return subprocess.run(
        arguments, env=env, text=True, capture_output=True, timeout=timeout, check=False
    )


def call(*arguments):
    result = command([str(binary), *arguments])
    if result.returncode:
        raise RuntimeError(result.stderr)
    return json.loads(result.stdout)


subprocess.run(
    ["swift", str(root / "scripts/make-fixture.swift"), str(scan), "2"],
    env=env,
    check=True,
    capture_output=True,
)
legacy = command(
    [
        "ocrmypdf",
        "--ocr-engine",
        "appleocr",
        "--appleocr-recognition-mode",
        "livetext",
        "--pdf-renderer",
        "sandwich",
        "--output-type",
        "pdf",
        "--optimize",
        "0",
        "-l",
        "kor",
        str(scan),
        str(source),
    ]
)
assert legacy.returncode == 0, legacy.stderr
source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
book = call("import", str(source))[0]
book_id = book["id"]
call("note-set", book_id, "기존 OCR을 개선해도 이 메모를 유지합니다.")
call("bookmark", book_id, "2")
call("position", book_id, "2")
before = call("read", book_id, "1")["text"]
result = call("ocr", book_id, "--redo", "--review-only", "--output", str(output))
assert result["mode"] == "replaceText"
assert result["quality"]["improvedSpacingPages"], (before, result)
assert not result["quality"]["spacingSuspectPages"], result["quality"]
assert not result["quality"]["extractorDisagreementPages"], result["quality"]
current = call("books")[0]
assert current["sourcePath"] == book["sourcePath"]
assert current.get("ocrPath") == book.get("ocrPath")
assert call("read", book_id, "1")["text"] == before
call("import", str(source))
call("import", str(output))
assert len(call("books")) == 1
assert call("read", book_id, "1")["text"] == before
candidate_bytes = output.read_bytes()
output.write_bytes(candidate_bytes + b"\n%changed after review\n")
refusal = command([str(binary), "ocr-accept", result["reportPath"]])
assert refusal.returncode != 0 and "변경" in refusal.stderr
assert call("read", book_id, "1")["text"] == before
output.write_bytes(candidate_bytes)
accepted = call("ocr-accept", result["reportPath"])
assert accepted["id"] == book_id and accepted["lastPage"] == 2
assert (
    call("read", book_id, "1")["text"].count("이 문서는 직접 만든 테스트 자료입니다.")
    == 1
)
assert (
    call("read", book_id, "2")["text"].count("이 문서는 직접 만든 테스트 자료입니다.")
    == 1
)
notes = call("notes", book_id)
assert notes["notebook"]["body"] == "기존 OCR을 개선해도 이 메모를 유지합니다."
assert notes["bookmarks"] == [2]
assert hashlib.sha256(source.read_bytes()).hexdigest() == source_hash
call("ocr-original", book_id)
call("import", str(source))
call("import", str(output))
assert call("read", book_id, "1")["text"] == before
assert len(call("books")) == 1
assert (
    call("notes", book_id)["notebook"]["body"]
    == "기존 OCR을 개선해도 이 메모를 유지합니다."
)
report = {
    "passed": [
        "legacy character spacing reproduced",
        "accurate redo improves spacing",
        "candidate review does not attach",
        "modified candidate rejected",
        "accept keeps book identity notes bookmarks and progress",
        "original bytes preserved",
        "original selection survives rescan without deleting OCR copies",
    ],
    "run": str(run),
    "quality": result["quality"],
}
(root / ".runtime/ocr-review-check-result.json").write_text(
    json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
)
print(json.dumps(report, ensure_ascii=False, indent=2))
