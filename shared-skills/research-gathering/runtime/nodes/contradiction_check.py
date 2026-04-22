#!/usr/bin/env python3
"""contradiction_check — findings 에서 상충 감지 + verification_status 결정.

입력:  outputs/aggregate_dedup.json (findings 배열 with distinct_file_count, distinct_scanner_count)
출력:  outputs/contradiction_check.json

Round 1 consensus (2026-04-22 토론) 반영된 v1.1 논리:

verified 재정의:
  primary AND distinct_file_count >= 2 AND distinct_scanner_count >= 2
  (같은 파일 다른 라인은 verified 로 인정 안 함 — 진짜 독립 source 요구)

Contradiction 감지:
  더 이상 keyword-grouping 안 함.
  difflib.SequenceMatcher.ratio() >= 0.6 유사 quote 를 cluster 로 묶음.
  한 cluster 안에 서로 다른 source_identity 인 primary finding 2+ 있으면 contradiction.

contradicted tag:
  contradiction cluster 에 실제로 속한 findings 에만 설정.
  그 외 findings 는 verified / single-source / secondary-only 중 하나.

시간 축 ordering:
  contradicted 해결 시 최신 primary 우선 (resolution: most_recent_primary).
  immutable annotation 있으면 override.
"""
import argparse
import json
import sys
from difflib import SequenceMatcher
from pathlib import Path


SIMILARITY_THRESHOLD = 0.6


def normalize_for_similarity(text: str) -> str:
    """공백·대소문자 정규화."""
    return " ".join((text or "").split()).lower()


def classify_verification(finding: dict) -> str:
    """verification_status 기본 판정 (contradiction 별도 처리).

    Round 1 consensus (EC 발언): same content_hash appearing from
    2+ different scanners OR 2+ different paths = verified.
    (AND 아님 — practice 에서 cross-scanner content identity 는 드물어
     AND 조건은 verified=0 생성.)
    """
    sc = finding.get("source_class", "secondary")
    if sc == "secondary":
        return "secondary-only"
    # primary or primary-historical
    distinct_files = finding.get("distinct_file_count", 1)
    distinct_scanners = finding.get("distinct_scanner_count", 1)
    if distinct_files >= 2 or distinct_scanners >= 2:
        return "verified"
    return "single-source"


def apply_immutability_marker(finding: dict):
    """evidence 안에 immutable 단어 있으면 표시."""
    for ev in finding.get("evidence", []) or []:
        q = ev.get("quote", "") or ""
        if "immutable" in q.lower():
            finding["immutable_marker"] = True
            return


def detect_contradictions_by_similarity(findings: list) -> list:
    """
    Similarity-based contradiction detection.
    - primary findings 만 대상
    - pairwise SequenceMatcher ratio >= THRESHOLD
    - 같은 cluster 에 source_identity 가 다른 것 2+ → contradiction
    """
    primary_findings = [
        f for f in findings
        if f.get("source_class", "").startswith("primary")
    ]

    # Build clusters via simple union-find on similarity
    n = len(primary_findings)
    parent = list(range(n))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[ra] = rb

    # Normalize quotes once
    norm_quotes = [normalize_for_similarity(f.get("claim", "")) for f in primary_findings]

    # Pairwise similarity — O(n^2), but n is reasonable after dedup
    # Skip very short quotes (< 30 chars) as they generate false matches
    for i in range(n):
        if len(norm_quotes[i]) < 30:
            continue
        for j in range(i + 1, n):
            if len(norm_quotes[j]) < 30:
                continue
            if abs(len(norm_quotes[i]) - len(norm_quotes[j])) > max(len(norm_quotes[i]), len(norm_quotes[j])):
                continue
            ratio = SequenceMatcher(None, norm_quotes[i], norm_quotes[j]).ratio()
            if ratio >= SIMILARITY_THRESHOLD:
                union(i, j)

    # Group by cluster root
    clusters = {}
    for i, f in enumerate(primary_findings):
        root = find(i)
        clusters.setdefault(root, []).append(f)

    contradictions = []
    contradicted_identities = set()

    for root, cluster in clusters.items():
        if len(cluster) < 2:
            continue
        # Distinct source_identity 확인
        identities = {}
        for f in cluster:
            sid = None
            if f.get("evidence"):
                sid = f["evidence"][0].get("source_identity")
            if sid:
                identities.setdefault(sid, []).append(f)
        if len(identities) < 2:
            continue

        # 시간 축 ordering
        all_timestamps = []
        for sid, fs in identities.items():
            for f in fs:
                for ev in f.get("evidence", []):
                    if ev.get("timestamp"):
                        all_timestamps.append((ev["timestamp"], sid))
        all_timestamps.sort(reverse=True)

        # Immutable override check
        has_immutable = any(f.get("immutable_marker") for f in cluster)

        if has_immutable:
            resolution = "immutable_override"
            note = "immutable-tagged primary 보존, 나머지 historical"
        elif all_timestamps:
            resolution = "most_recent_primary"
            note = f"최신 primary: {all_timestamps[0][0]}, source_identity: {all_timestamps[0][1][:16]}..."
        else:
            resolution = "user_required"
            note = "timestamp 부족, 사용자 결정 필요"

        # cluster 의 대표 keyword/topic — 가장 긴 quote 의 첫 몇 단어
        longest = max(cluster, key=lambda f: len(f.get("claim", "")))
        topic = longest.get("claim", "")[:80]

        contradictions.append({
            "topic": topic,
            "cluster_size": len(cluster),
            "values": [
                {
                    "value": fs[0]["claim"][:200],
                    "source_identity": sid,
                    "source": fs[0]["evidence"][0] if fs[0].get("evidence") else None,
                }
                for sid, fs in identities.items()
            ],
            "resolution": resolution,
            "resolution_note": note,
        })

        # Mark affected findings
        for f in cluster:
            if f.get("evidence"):
                contradicted_identities.add(f["evidence"][0].get("source_identity"))

    return contradictions, contradicted_identities


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--query-dir", required=True)
    args = ap.parse_args()

    query_dir = Path(args.query_dir)
    aggr_path = query_dir / "outputs" / "aggregate_dedup.json"

    if not aggr_path.exists():
        result = {
            "status": "FAILED",
            "node_id": "contradiction_check",
            "reason": "aggregate_dedup.json not found",
            "findings": [],
            "contradictions": [],
        }
    else:
        with open(aggr_path, encoding="utf-8") as f:
            aggr = json.load(f)
        findings = aggr.get("findings", []) or []

        # Step 1: 각 finding 의 기본 verification_status (not yet aware of contradictions)
        for f in findings:
            f["verification_status"] = classify_verification(f)
            apply_immutability_marker(f)

        # Step 2: similarity-based contradiction detection (primary only)
        contradictions, contradicted_identities = detect_contradictions_by_similarity(findings)

        # Step 3: 실제 contradiction cluster 에 속한 findings 만 contradicted 로 재분류
        for f in findings:
            if not f.get("evidence"):
                continue
            sid = f["evidence"][0].get("source_identity")
            if sid in contradicted_identities:
                f["verification_status"] = "contradicted"

        # Step 4: disconfirmation report (v1 은 structural, v1.1 에서 antonym-pointed 로 강화 예정)
        disconfirmation_report = []
        for f in findings:
            if f.get("verification_status") == "verified":
                represented = set(f.get("distinct_scanners", []) or [])
                absent = {"git_scan", "memory_scan", "filesystem_scan", "transcript_scan"} - represented
                disconfirmation_report.append({
                    "claim": f["claim"][:100],
                    "verified_in": sorted(represented),
                    "no_contradiction_in": sorted(absent),
                    "checked": "structural",  # v1.1 에서 antonym-pointed 로 업그레이드
                })

        result = {
            "status": "DONE",
            "node_id": "contradiction_check",
            "algorithm_version": "v1.1-similarity-based",
            "findings": findings,
            "contradictions": contradictions,
            "disconfirmation_report": disconfirmation_report,
            "counts": {
                "verified": sum(1 for f in findings if f.get("verification_status") == "verified"),
                "single_source": sum(1 for f in findings if f.get("verification_status") == "single-source"),
                "secondary_only": sum(1 for f in findings if f.get("verification_status") == "secondary-only"),
                "contradicted": sum(1 for f in findings if f.get("verification_status") == "contradicted"),
            },
        }

    out_path = query_dir / "outputs" / "contradiction_check.json"
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2, ensure_ascii=False)

    print(f"[contradiction_check] {result.get('counts', {})}", file=sys.stderr)
    print(json.dumps({"status": result["status"], "counts": result.get("counts", {})}, ensure_ascii=False))


if __name__ == "__main__":
    main()
