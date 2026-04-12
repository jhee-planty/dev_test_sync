#!/usr/bin/env python3
"""
dev_metrics.py — Dev PC 측 turnaround 메트릭 자동 계산

git log 타임스탬프를 기반으로 request→result turnaround 시간을 계산한다.
test-pc-worker 메트릭에 의존하지 않는 독립적 측정 도구.

사용법:
  python3 dev_metrics.py [--repo-path PATH] [--since DATE] [--output FORMAT]

예시:
  python3 dev_metrics.py --repo-path ~/Documents/workspace/dev_test_sync
  python3 dev_metrics.py --since 2026-04-06 --output markdown
"""

import argparse
import subprocess
import re
import json
from datetime import datetime, timedelta
from pathlib import Path


def get_file_commit_time(repo_path: str, filepath: str) -> datetime | None:
    """git log에서 파일이 처음 추가된 시각을 가져온다."""
    try:
        result = subprocess.run(
            ["git", "log", "--format=%aI", "--diff-filter=A", "--follow", "--", filepath],
            capture_output=True, text=True, cwd=repo_path
        )
        lines = result.stdout.strip().split("\n")
        if lines and lines[-1]:
            # --follow는 가장 오래된 것이 마지막 줄
            return datetime.fromisoformat(lines[-1])
    except Exception:
        pass
    return None


def find_request_result_pairs(repo_path: str, since: str | None = None) -> list[dict]:
    """requests/와 results/ 디렉토리에서 번호로 매칭되는 쌍을 찾는다."""
    requests_dir = Path(repo_path) / "requests"
    results_dir = Path(repo_path) / "results"

    if not requests_dir.exists() or not results_dir.exists():
        print(f"Error: requests/ or results/ directory not found in {repo_path}")
        return []

    # 요청 파일 수집: {번호} → 파일명
    req_pattern = re.compile(r"^(\d+)_.*\.json$")
    requests = {}
    for f in requests_dir.iterdir():
        m = req_pattern.match(f.name)
        if m:
            requests[int(m.group(1))] = f"requests/{f.name}"

    # 결과 파일 수집
    res_pattern = re.compile(r"^(\d+)_.*\.json$")
    results = {}
    for f in results_dir.iterdir():
        m = res_pattern.match(f.name)
        if m:
            results[int(m.group(1))] = f"results/{f.name}"

    # 매칭 및 turnaround 계산
    pairs = []
    for num in sorted(requests.keys()):
        req_time = get_file_commit_time(repo_path, requests[num])
        if req_time is None:
            continue

        if since:
            since_dt = datetime.fromisoformat(since)
            if req_time.replace(tzinfo=None) < since_dt:
                continue

        entry = {
            "number": num,
            "request_file": requests[num],
            "request_time": req_time.isoformat(),
            "result_file": None,
            "result_time": None,
            "turnaround_min": None,
            "status": "PENDING"
        }

        if num in results:
            res_time = get_file_commit_time(repo_path, results[num])
            if res_time:
                entry["result_file"] = results[num]
                entry["result_time"] = res_time.isoformat()
                delta = res_time - req_time
                entry["turnaround_min"] = round(delta.total_seconds() / 60, 1)
                entry["status"] = "COMPLETED"

        pairs.append(entry)

    return pairs


def calculate_summary(pairs: list[dict]) -> dict:
    """통계 요약을 계산한다."""
    completed = [p for p in pairs if p["status"] == "COMPLETED"]
    pending = [p for p in pairs if p["status"] == "PENDING"]

    if not completed:
        return {
            "total": len(pairs),
            "completed": 0,
            "pending": len(pending),
            "avg_turnaround_min": None,
            "min_turnaround_min": None,
            "max_turnaround_min": None,
            "median_turnaround_min": None,
            "over_30min": 0
        }

    turnarounds = [p["turnaround_min"] for p in completed]
    turnarounds_sorted = sorted(turnarounds)
    n = len(turnarounds_sorted)
    median = turnarounds_sorted[n // 2] if n % 2 == 1 else \
        (turnarounds_sorted[n // 2 - 1] + turnarounds_sorted[n // 2]) / 2

    return {
        "total": len(pairs),
        "completed": len(completed),
        "pending": len(pending),
        "avg_turnaround_min": round(sum(turnarounds) / len(turnarounds), 1),
        "min_turnaround_min": min(turnarounds),
        "max_turnaround_min": max(turnarounds),
        "median_turnaround_min": round(median, 1),
        "over_30min": sum(1 for t in turnarounds if t > 30)
    }


def format_markdown(pairs: list[dict], summary: dict) -> str:
    """마크다운 형식으로 출력한다."""
    lines = ["# Dev Metrics Report", ""]
    lines.append(f"Generated: {datetime.now().isoformat()}")
    lines.append("")

    # Summary
    lines.append("## Summary")
    lines.append("")
    lines.append(f"| 항목 | 수치 |")
    lines.append(f"|------|------|")
    lines.append(f"| 총 요청 | {summary['total']} |")
    lines.append(f"| 완료 | {summary['completed']} |")
    lines.append(f"| 대기 중 | {summary['pending']} |")
    if summary['avg_turnaround_min'] is not None:
        lines.append(f"| 평균 turnaround | {summary['avg_turnaround_min']}분 |")
        lines.append(f"| 최소 | {summary['min_turnaround_min']}분 |")
        lines.append(f"| 최대 | {summary['max_turnaround_min']}분 |")
        lines.append(f"| 중앙값 | {summary['median_turnaround_min']}분 |")
        lines.append(f"| 30분 초과 | {summary['over_30min']}건 |")
    lines.append("")

    # Detail table
    lines.append("## Detail")
    lines.append("")
    lines.append("| # | Request Time | Result Time | Turnaround | Status |")
    lines.append("|---|-------------|-------------|------------|--------|")
    for p in pairs:
        req_t = p['request_time'][:16] if p['request_time'] else "-"
        res_t = p['result_time'][:16] if p['result_time'] else "-"
        ta = f"{p['turnaround_min']}min" if p['turnaround_min'] is not None else "-"
        lines.append(f"| {p['number']} | {req_t} | {res_t} | {ta} | {p['status']} |")

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Dev PC turnaround metrics calculator")
    parser.add_argument("--repo-path", default=".", help="Path to dev_test_sync repo")
    parser.add_argument("--since", default=None, help="Only include requests after this date (ISO format)")
    parser.add_argument("--output", choices=["json", "markdown"], default="markdown", help="Output format")
    args = parser.parse_args()

    pairs = find_request_result_pairs(args.repo_path, args.since)
    summary = calculate_summary(pairs)

    if args.output == "json":
        print(json.dumps({"summary": summary, "pairs": pairs}, indent=2, ensure_ascii=False))
    else:
        print(format_markdown(pairs, summary))


if __name__ == "__main__":
    main()
