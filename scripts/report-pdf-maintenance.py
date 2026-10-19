"""Write a readable live/final report for a Bookside maintenance job; never changes PDFs or the catalog."""

import argparse
import json
import sqlite3
import subprocess
import time
from datetime import datetime
from pathlib import Path


def read_json(filename):
    return json.loads(filename.read_text(encoding="utf-8"))


def latest_rows(filename):
    result = {}
    if filename.exists():
        with filename.open(encoding="utf-8") as stream:
            for line in stream:
                if not line.endswith("\n"):
                    break
                row = json.loads(line)
                result[row["key"]] = {
                    key: value for key, value in row.items() if key != "metrics"
                }
    return result


def verify_notes(before_file, current_file):
    before = sqlite3.connect(before_file.as_uri() + "?mode=ro", uri=True)
    after = sqlite3.connect(current_file.as_uri() + "?mode=ro", uri=True)
    checks = {}
    for table in ["books", "notebooks", "highlights", "bookmarks"]:
        columns = (
            "book_id,page"
            if table == "bookmarks"
            else "id"
            if table in {"books", "highlights"}
            else "book_id"
        )
        old = set(before.execute(f"SELECT {columns} FROM {table}"))
        new = set(after.execute(f"SELECT {columns} FROM {table}"))
        checks[table] = {
            "before": len(old),
            "current": len(new),
            "missing_original_ids": len(old - new),
        }
    before.close()
    after.close()
    return checks


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("job", type=Path)
    parser.add_argument("--watch", action="store_true")
    args = parser.parse_args()
    while True:
        job = read_json(args.job / "job.json")
        summary_path = Path(job["report"])
        summary = read_json(summary_path)
        command = subprocess.run(
            ["ps", "-p", str(job["pid"]), "-o", "command="],
            text=True,
            capture_output=True,
            check=False,
        ).stdout
        alive = str(args.job) in command
        arguments = job["args"]
        audit = Path(arguments[arguments.index("--audit-dir") + 1])
        data = Path(arguments[arguments.index("--data-dir") + 1])
        records = latest_rows(audit / "00-audit.jsonl")
        events = latest_rows(summary_path.parent / "02-events.jsonl")
        finalizer = (
            read_json(args.job / "finalizer.json")
            if (args.job / "finalizer.json").exists()
            else {}
        )
        finalizer_command = subprocess.run(
            ["ps", "-p", str(finalizer.get("pid", 99999999)), "-o", "command="],
            text=True,
            capture_output=True,
            check=False,
        ).stdout
        finalizing = str(
            args.job / "tools/finish-pdf-maintenance.py"
        ) in finalizer_command and finalizer.get("phase") not in {
            "complete",
            "stopped",
            "error",
        }
        running = (summary["running"] and alive) or finalizing
        headline = (
            "PDF 라이브러리 개선 진행 중" if running else "PDF 라이브러리 개선 결과"
        )
        counts = {}
        for event in events.values():
            counts[event["status"]] = counts.get(event["status"], 0) + 1
        labels = {
            "ocr_attached": "새 OCR 연결",
            "spacing_applied": "공백 보정",
            "review_required": "사본 검토 필요",
            "failed": "처리 오류",
            "stopped": "재시도 대기",
            "existing_ocr_version": "기존 OCR 사본 유지",
            "planned": "계획",
        }
        lines = [
            f"# {headline}",
            "",
            f"갱신: {datetime.now().astimezone().isoformat(timespec='seconds')}",
            "",
            f"- 원래 대상: {len(records)}개 PDF",
            f"- 전체 페이지 검사: {summary['audited_pages']:,}쪽",
            f"- 아직 접근하거나 검사하지 못한 파일: {summary['audit_unavailable']}개",
            f"- 실행 중이거나 대기 중인 개선 작업: {summary['queued_or_running']}개",
        ]
        lines.extend(
            f"- {labels.get(key, key)}: {count}개"
            for key, count in sorted(counts.items())
        )
        lines += [
            "",
            "새 OCR은 별도 사본입니다. 검토가 필요한 사본은 앱의 ‘책 옵션 > 생성한 OCR 사본 검토’에서 비교할 수 있습니다.",
            "공백만 보정한 파일은 원본 백업 후 교체했습니다. 생성 성공이나 표본 통과가 모든 단어의 정확도를 뜻하지는 않습니다.",
            "읽는 순서/공백 지표는 전체 페이지, 화면 비교는 표본에 적용합니다. 새 OCR을 연결하기 전에 포함된 이미지 바이트도 대조합니다.",
            "",
        ]
        if not alive and summary["running"]:
            lines += [
                "프로세스가 종료됐지만 완료 기록이 없습니다. 완료로 처리하지 않았습니다.",
                "",
            ]
        if finalizer.get("phase") == "error":
            lines += [
                "늦게 내려받은 파일을 재확인하는 중 오류가 발생했습니다: "
                + str(finalizer.get("error", "")),
                "",
            ]
        if not alive:
            checks = verify_notes(
                args.job / "library-before.sqlite3", data / "library.sqlite3"
            )
            lines += [
                "## 책과 메모 식별자 확인",
                "",
                "```json",
                json.dumps(checks, ensure_ascii=False, indent=2),
                "```",
                "",
            ]
        lines += [
            "## 파일별 상태",
            "",
            "| PDF | 쪽 | 상태 | OCR 사본 |",
            "| --- | ---: | --- | --- |",
        ]
        for key, row in sorted(
            records.items(), key=lambda item: item[1]["relative_path"]
        ):
            event = events.get(key)
            if event:
                state = labels.get(event["status"], event["status"])
                if event.get("spacing_pages"):
                    state += f" / 공백 {event['spacing_pages']}쪽 보정"
            elif row["status"] == "no_spacing_flag":
                state = "공백 문제 지표 없음"
                if (
                    row.get("page_count", 0) >= 5
                    and row.get("text_pages", 0) < row["page_count"] * 0.8
                ):
                    state = "텍스트 부족, 처리 대기"
            elif row["status"] == "error":
                state = "접근/검사 실패"
            else:
                state = "개선 작업 대기"
            title = (
                row["relative_path"]
                .replace("|", "/")
                .replace("[", "\\[")
                .replace("]", "\\]")
            )
            link = (
                f"[열기](<{event['output']}>)" if event and event.get("output") else ""
            )
            lines.append(
                f"| [{title}](<{row['path']}>) | {row.get('page_count', '')} | {state} | {link} |"
            )
        destination = summary_path.parent / "04-report.md"
        temporary = destination.with_suffix(".md.tmp")
        temporary.write_text("\n".join(lines) + "\n", encoding="utf-8")
        temporary.replace(destination)
        if not args.watch or (not alive and not finalizing):
            break
        time.sleep(30)


if __name__ == "__main__":
    main()
