#!/usr/bin/env python3
"""
archive_results.py — 테스트 결과 자동 분류 및 아카이브
Usage:
  python3 archive_results.py --input <dir> --output <dir> [--rules <rules.json>]
"""
import argparse
import json
import os
import glob
import shutil
import tarfile
import hashlib
from datetime import datetime
from collections import defaultdict, Counter
from pathlib import Path


# ─── JSON 파싱 (BOM 대응) ───
def safe_json_load(filepath):
    """UTF-8 BOM이 있어도 안전하게 JSON을 읽는다."""
    try:
        with open(filepath, encoding='utf-8-sig') as f:
            return json.load(f)
    except (json.JSONDecodeError, UnicodeDecodeError):
        return None


# ─── 파일 탐색 ───
def discover_files(input_dir, live_dir=None):
    """input_dir(archive) + live_dir(현재 results/) 내 모든 request/result 쌍을 탐색한다.
    반환: list of {namespace, id, request_path, result_path}
    """
    entries = []
    seen = set()

    scan_specs = [
        # (namespace, request_glob, result_glob)
        ("old", "old-requests/*_*.json", "old-results/*_result.json"),
        ("0325", "2026-03-25/*_check-warning.json", "2026-03-25/*_result.json"),
        ("0325", "2026-03-25/*_run-scenario.json", None),
        ("0327", "2026-03-27/requests/*_*.json", "2026-03-27/results/*_result.json"),
        ("gemini", "gemini-history/*_*.json", None),
    ]

    # live_dir가 있으면 현재 활성 requests/results도 스캔
    if live_dir:
        req_dir = os.path.join(live_dir, "requests")
        res_dir = os.path.join(live_dir, "results")
        if os.path.isdir(req_dir) or os.path.isdir(res_dir):
            # live_dir 기준 상대 패턴 생성
            scan_specs.append(
                ("live", "requests/*_*.json", "results/*_result.json")
            )

    for ns, req_pattern, res_pattern in scan_specs:
        # live namespace는 live_dir 기준, 나머지는 input_dir 기준
        base = live_dir if (ns == "live" and live_dir) else input_dir

        # Collect results by ID
        result_map = {}
        if res_pattern:
            for f in glob.glob(os.path.join(base, res_pattern)):
                fid = os.path.basename(f).split('_')[0]
                result_map[fid] = f

        # Collect requests and pair
        req_files = glob.glob(os.path.join(base, req_pattern))
        for f in req_files:
            basename = os.path.basename(f)
            if '_result.json' in basename:
                continue
            fid = basename.split('_')[0]
            key = f"{ns}/{fid}"
            if key in seen:
                continue
            seen.add(key)
            entries.append({
                "namespace": ns,
                "id": fid,
                "request_path": f,
                "result_path": result_map.get(fid),
            })

        # Results without matching request
        for fid, rpath in result_map.items():
            key = f"{ns}/{fid}"
            if key not in seen:
                seen.add(key)
                entries.append({
                    "namespace": ns,
                    "id": fid,
                    "request_path": None,
                    "result_path": rpath,
                })

    return entries


# ─── 서비스 식별 ───
SERVICE_KEYWORDS = {
    "chatgpt": "chatgpt", "claude": "claude", "gemini": "gemini",
    "genspark": "genspark", "perplexity": "perplexity", "notion": "notion",
    "grok": "grok", "gamma": "gamma", "copilot": "copilot",
    "m365": "m365_copilot", "github copilot": "github_copilot",
    "m365 copilot": "m365_copilot", "clova": "clova",
}


def _extract_service_from_text(text):
    """텍스트(description, URL 등)에서 서비스명을 추출한다."""
    if not text or not isinstance(text, str):
        return None
    text_lower = text.lower()
    # 긴 키워드 먼저 매칭 (github copilot > copilot)
    for keyword in sorted(SERVICE_KEYWORDS.keys(), key=len, reverse=True):
        if keyword in text_lower:
            return SERVICE_KEYWORDS[keyword]
    return None


def identify_service(entry, known_service_dirs):
    """request 또는 result에서 service 이름을 추출한다."""
    # namespace가 서비스 고정인 경우 (gemini-history 등)
    ns = entry["namespace"]
    for dir_key, svc in known_service_dirs.items():
        if ns == dir_key or ns == svc:
            return svc

    # request에서 추출 — params.service 우선
    if entry["request_path"]:
        req = safe_json_load(entry["request_path"])
        if req:
            svc = req.get("params", {}).get("service")
            if svc:
                return svc
            # description에서 추출 시도
            desc = req.get("params", {}).get("description", "")
            svc = _extract_service_from_text(desc)
            if svc:
                return svc
            # steps URL에서 추출 시도
            for step in req.get("params", {}).get("steps", []):
                url = step.get("url", "")
                svc = _extract_service_from_text(url)
                if svc:
                    return svc

    # result에서 추출
    if entry["result_path"]:
        res = safe_json_load(entry["result_path"])
        if res:
            svc = res.get("service")
            if svc:
                return svc
            # notes/summary에서 추출 시도
            for key in ["notes", "summary", "diagnosis"]:
                svc = _extract_service_from_text(res.get(key, ""))
                if svc:
                    return svc

    return "unknown"


# ─── 결과 타입 감지 ───
def detect_result_type(result_data):
    """result JSON의 구조로 타입을 판별한다."""
    if result_data is None:
        return "no_result"
    r = result_data.get("result", result_data)
    if not isinstance(r, dict):
        return "flat"
    if "blocked" in r:
        return "check-warning"
    if "steps" in r:
        return "run-scenario"
    if "results" in r:
        return "multi-test"
    return "other"


# ─── 성공/실패 판정 ───
def judge_outcome(result_data, result_type, rules):
    """rules.json 기반으로 성공/실패를 판정한다.
    반환: 'success' | 'partial' | 'fail' | 'unknown'
    """
    if result_data is None:
        return "unknown"

    r = result_data.get("result", result_data)
    if not isinstance(r, dict):
        return "unknown"

    if result_type == "check-warning":
        blocked = r.get("blocked", False)
        warning_visible = r.get("warning_visible", False)
        if blocked and warning_visible:
            return "success"
        elif blocked and not warning_visible:
            return "partial"
        else:
            return "fail"

    elif result_type == "run-scenario":
        if r.get("all_passed") is True:
            return "success"
        return "fail"

    elif result_type == "multi-test":
        results = r.get("results", [])
        if not results:
            return "unknown"
        # multi-test 내부 구조: list of dicts or nested
        for item in results:
            if isinstance(item, dict):
                passed = item.get("pass", item.get("passed",
                         item.get("warning_visible", None)))
                if passed is False or passed is None:
                    return "fail"
        return "success"

    return "unknown"


# ─── notes 추출 ───
def extract_notes(result_data):
    """result에서 사람이 읽을 수 있는 notes/diagnosis를 추출한다."""
    if result_data is None:
        return ""
    notes_parts = []
    # Top-level notes
    for key in ["notes", "diagnosis", "summary"]:
        val = result_data.get(key)
        if val and isinstance(val, str):
            notes_parts.append(val)
    # Nested in result
    r = result_data.get("result", {})
    if isinstance(r, dict):
        for key in ["notes", "diagnosis", "observed_behavior", "observation"]:
            val = r.get(key)
            if val and isinstance(val, str):
                notes_parts.append(val)
    return " | ".join(notes_parts) if notes_parts else ""


# ─── 전체 처리 파이프라인 ───
def process_archive(input_dir, output_dir, rules, live_dir=None):
    """메인 파이프라인: 탐색 → 파싱 → 분류 → lessons → 압축"""
    known_dirs = rules.get("known_service_dirs", {})
    entries = discover_files(input_dir, live_dir=live_dir)

    index = []
    stats = defaultdict(lambda: Counter())
    failures_by_service = defaultdict(list)
    success_files = []
    parse_fail_count = 0
    unknown_service_count = 0

    for entry in entries:
        # Parse result
        result_data = None
        if entry["result_path"]:
            result_data = safe_json_load(entry["result_path"])
            if result_data is None:
                parse_fail_count += 1

        # Identify service
        service = identify_service(entry, known_dirs)
        if service == "unknown":
            unknown_service_count += 1

        # Detect type and judge
        result_type = detect_result_type(result_data)
        outcome = judge_outcome(result_data, result_type, rules)
        notes = extract_notes(result_data)

        record = {
            "namespace": entry["namespace"],
            "id": entry["id"],
            "service": service,
            "type": result_type,
            "outcome": outcome,
            "notes": notes[:200] if notes else "",
            "request_path": entry["request_path"],
            "result_path": entry["result_path"],
        }
        index.append(record)
        stats[service][outcome] += 1

        # Collect for output
        if outcome in ("fail", "partial", "unknown"):
            failures_by_service[service].append(record)
        else:
            for p in [entry["request_path"], entry["result_path"]]:
                if p:
                    success_files.append(p)

    # ─── Output: index.json ───
    os.makedirs(output_dir, exist_ok=True)
    index_path = os.path.join(output_dir, "index.json")
    with open(index_path, 'w', encoding='utf-8') as f:
        json.dump(index, f, ensure_ascii=False, indent=2)

    # ─── Output: lessons/ ───
    lessons_dir = os.path.join(output_dir, "lessons")
    os.makedirs(lessons_dir, exist_ok=True)
    lessons_count = 0
    for service, records in failures_by_service.items():
        md_path = os.path.join(lessons_dir, f"{service}_failures.md")
        with open(md_path, 'w', encoding='utf-8') as f:
            f.write(f"# {service} — Failure Analysis\n\n")
            f.write(f"Generated: {datetime.now().isoformat()}\n")
            f.write(f"Total failures: {len(records)}\n\n")

            # Detect repeated patterns
            pattern_counter = Counter()
            for rec in records:
                if rec["notes"]:
                    # 간단한 패턴 키: notes 앞 50자
                    pattern_key = rec["notes"][:50]
                    pattern_counter[pattern_key] += 1

            # Known issues (3회 이상 반복)
            threshold = rules.get("repeat_threshold_for_known_issue", 3)
            known = {k: v for k, v in pattern_counter.items() if v >= threshold}
            if known:
                f.write("## Known Issues (반복 패턴)\n\n")
                for pattern, count in sorted(known.items(),
                                             key=lambda x: -x[1]):
                    f.write(f"- **{count}회 반복**: {pattern}...\n")
                f.write("\n")

            # Individual failures
            f.write("## Details\n\n")
            for rec in records:
                f.write(f"### [{rec['namespace']}/{rec['id']}] "
                        f"{rec['type']} → {rec['outcome']}\n")
                if rec["notes"]:
                    f.write(f"- Notes: {rec['notes']}\n")
                if rec["result_path"]:
                    f.write(f"- Result: `{rec['result_path']}`\n")
                f.write("\n")
                lessons_count += 1

    # ─── Output: failures/ (원본 복사) ───
    failures_dir = os.path.join(output_dir, "failures")
    for service, records in failures_by_service.items():
        svc_dir = os.path.join(failures_dir, service)
        os.makedirs(svc_dir, exist_ok=True)
        for rec in records:
            for p in [rec["request_path"], rec["result_path"]]:
                if p and os.path.exists(p):
                    dst = os.path.join(svc_dir, os.path.basename(p))
                    if not os.path.exists(dst):
                        shutil.copy2(p, dst)

    # ─── Output: summary_stats.md ───
    stats_path = os.path.join(output_dir, "summary_stats.md")
    with open(stats_path, 'w', encoding='utf-8') as f:
        f.write("# Archive Summary Statistics\n\n")
        f.write(f"Generated: {datetime.now().isoformat()}\n")
        f.write(f"Input: `{input_dir}`\n")
        f.write(f"Total entries: {len(index)}\n")
        f.write(f"Parse failures: {parse_fail_count}\n")
        f.write(f"Unknown service: {unknown_service_count}\n\n")
        f.write("## Per-Service Results\n\n")
        f.write("| Service | Success | Partial | Fail | Unknown | Total |\n")
        f.write("|---------|---------|---------|------|---------|-------|\n")
        for svc in sorted(stats.keys()):
            c = stats[svc]
            total = sum(c.values())
            f.write(f"| {svc} | {c['success']} | {c['partial']} "
                    f"| {c['fail']} | {c['unknown']} | {total} |\n")
        f.write(f"\n**Total lessons generated: {lessons_count}**\n")

    # ─── Output: archive-success.tar.gz ───
    exclude_patterns = rules.get("exclude_from_success_archive", [])
    archive_path = os.path.join(output_dir, "archive-success.tar.gz")
    with tarfile.open(archive_path, "w:gz") as tar:
        for fpath in success_files:
            basename = os.path.basename(fpath)
            skip = False
            for pat in exclude_patterns:
                if pat.startswith("*"):
                    if basename.endswith(pat[1:]):
                        skip = True
                        break
            if not skip:
                tar.add(fpath, arcname=os.path.join("success", basename))

    # ─── Output: archive_metrics.jsonl (누적) ───
    metrics_path = os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "archive_metrics.jsonl"
    )
    metric = {
        "timestamp": datetime.now().isoformat(),
        "input_dir": input_dir,
        "total_entries": len(index),
        "parse_fail": parse_fail_count,
        "unknown_service": unknown_service_count,
        "lessons_generated": lessons_count,
        "per_service": {svc: dict(c) for svc, c in stats.items()},
    }

    # 이전 메트릭과 비교하여 이상 징후 감지
    anomalies = []
    if os.path.exists(metrics_path):
        with open(metrics_path, encoding='utf-8') as f:
            lines = f.readlines()
            if lines:
                prev = json.loads(lines[-1])
                prev_unknown_rate = (prev.get("unknown_service", 0)
                                     / max(prev.get("total_entries", 1), 1))
                curr_unknown_rate = (unknown_service_count
                                     / max(len(index), 1))
                if curr_unknown_rate > prev_unknown_rate + 0.05:
                    anomalies.append(
                        f"unknown 비율 증가: "
                        f"{prev_unknown_rate:.1%} → {curr_unknown_rate:.1%}")

                # 서비스별 실패율 급등 체크
                for svc, curr_counts in stats.items():
                    prev_svc = prev.get("per_service", {}).get(svc, {})
                    prev_fail = prev_svc.get("fail", 0) + prev_svc.get("partial", 0)
                    curr_fail = curr_counts.get("fail", 0) + curr_counts.get("partial", 0)
                    prev_total = sum(prev_svc.values()) if prev_svc else 0
                    curr_total = sum(curr_counts.values())
                    if prev_total > 0 and curr_total > 0:
                        prev_rate = prev_fail / prev_total
                        curr_rate = curr_fail / curr_total
                        if curr_rate > prev_rate + 0.2:
                            anomalies.append(
                                f"{svc} 실패율 급등: "
                                f"{prev_rate:.0%} → {curr_rate:.0%}")

    metric["anomalies"] = anomalies

    with open(metrics_path, 'a', encoding='utf-8') as f:
        f.write(json.dumps(metric, ensure_ascii=False) + "\n")

    return {
        "total": len(index),
        "parse_fail": parse_fail_count,
        "unknown_service": unknown_service_count,
        "lessons": lessons_count,
        "anomalies": anomalies,
        "stats": {svc: dict(c) for svc, c in stats.items()},
    }


# ─── CLI ───
def main():
    parser = argparse.ArgumentParser(
        description="테스트 결과 자동 분류 및 아카이브")
    parser.add_argument("--input", required=True,
                        help="입력 디렉토리 (local_archive)")
    parser.add_argument("--output", required=True,
                        help="출력 디렉토리")
    parser.add_argument("--rules", default=None,
                        help="rules.json 경로 (미지정 시 기본값 사용)")
    parser.add_argument("--live", default=None,
                        help="현재 활성 dev_test_sync/ 경로 (requests/+results/ 포함)")
    args = parser.parse_args()

    # Load rules
    rules = {}
    if args.rules and os.path.exists(args.rules):
        rules = safe_json_load(args.rules) or {}
    elif os.path.exists(os.path.join(os.path.dirname(__file__), "rules.json")):
        rules = safe_json_load(
            os.path.join(os.path.dirname(__file__), "rules.json")) or {}

    result = process_archive(args.input, args.output, rules,
                             live_dir=args.live)

    print(f"\n=== Archive Complete ===")
    print(f"Total entries: {result['total']}")
    print(f"Parse failures: {result['parse_fail']}")
    print(f"Unknown service: {result['unknown_service']}")
    print(f"Lessons generated: {result['lessons']}")
    if result['anomalies']:
        print(f"\n⚠️  Anomalies detected:")
        for a in result['anomalies']:
            print(f"  - {a}")
    print(f"\nPer-service:")
    for svc, counts in sorted(result['stats'].items()):
        print(f"  {svc}: {dict(counts)}")


if __name__ == "__main__":
    main()
