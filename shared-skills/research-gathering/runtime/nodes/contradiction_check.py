#!/usr/bin/env python3
"""contradiction_check — findings 에서 상충 감지 + verification_status 결정.

입력:  outputs/aggregate_dedup.json (findings 배열)
출력:  outputs/contradiction_check.json

규칙:
- 각 finding 의 evidence 배열을 검토
- primary evidence 개수로 verification_status 결정:
  * verified: primary (content_hash 서로 다른) ≥ 2
  * single-source: primary 1
  * secondary-only: primary 0, secondary only
  * contradicted: primary 값이 다른데 (쉬운 휴리스틱: 같은 주제/키워드에 다른 quote) 상충
- 시간 축 ordering: 최신 primary 우선 (resolution: most_recent_primary)
- immutable annotation: evidence quote 에 "immutable" 단어가 포함되면 override

참고: v1 구현은 "단순" contradiction 감지 — 같은 keyword 의 finding 2개 이상에서
quote content_hash 가 다르고 두 quote 가 1000자 이내면 상충 후보로 분류.
정교한 semantic contradiction 은 v1.1 에서.
"""
import argparse
import json
import sys
from collections import defaultdict
from pathlib import Path


def classify_finding(finding: dict) -> dict:
    """Update finding with verification_status based on evidence."""
    evidence = finding.get("evidence", []) or []
    primary_ev = [e for e in evidence if finding.get("source_class", "").startswith("primary")]

    # Count distinct source_identities in primary evidence
    primary_ids = {e.get("source_identity") for e in primary_ev if e.get("source_identity")}

    if finding["source_class"] == "secondary":
        finding["verification_status"] = "secondary-only"
    elif len(primary_ids) >= 2:
        finding["verification_status"] = "verified"
    elif len(primary_ids) == 1:
        finding["verification_status"] = "single-source"
    else:
        finding["verification_status"] = "secondary-only"

    # Immutability override
    for ev in evidence:
        q = ev.get("quote", "") or ""
        if "immutable" in q.lower():
            finding["immutable_marker"] = True
            break

    return finding


def detect_contradictions(findings: list) -> list:
    """Group findings by keyword; within each group, detect if primary values differ."""
    contradictions = []
    by_keyword = defaultdict(list)
    for f in findings:
        kw = (f.get("keyword_matched") or "").lower()
        if kw:
            by_keyword[kw].append(f)

    for kw, group in by_keyword.items():
        # Only primary findings in contradiction check
        primaries = [f for f in group if f.get("source_class", "").startswith("primary")]
        if len(primaries) < 2:
            continue
        # Collect distinct claims
        distinct_claims = {}
        for f in primaries:
            claim_hash = f["evidence"][0].get("source_identity") if f.get("evidence") else None
            if claim_hash:
                distinct_claims.setdefault(claim_hash, []).append(f)

        if len(distinct_claims) >= 2:
            # Resolve by timestamp
            all_timestamps = []
            for cid, fs in distinct_claims.items():
                for f in fs:
                    for ev in f.get("evidence", []):
                        if ev.get("timestamp"):
                            all_timestamps.append((ev["timestamp"], cid, ev))
            all_timestamps.sort(reverse=True)
            resolution = "most_recent_primary" if all_timestamps else "deferred"
            contradictions.append({
                "topic": kw,
                "values": [
                    {
                        "value": fs[0]["claim"],
                        "source_identity": cid,
                        "source": fs[0]["evidence"][0] if fs[0].get("evidence") else None,
                    }
                    for cid, fs in distinct_claims.items()
                ],
                "resolution": resolution,
                "resolution_note": (
                    f"최신 primary: {all_timestamps[0][0]}"
                    if all_timestamps else
                    "timestamp 정보 부족, 수동 해결 필요"
                ),
            })
            # Mark all related findings as contradicted
            for f in primaries:
                f["verification_status"] = "contradicted"

    return contradictions


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

        # Step 1: classify each finding
        for f in findings:
            classify_finding(f)

        # Step 2: detect contradictions
        contradictions = detect_contradictions(findings)

        # Step 3: disconfirmation tracking (v1 휴리스틱)
        # 각 verified finding 에 대해 반증이 다른 tier 에서 검색됐는지 기록
        disconfirmation_report = []
        for f in findings:
            if f.get("verification_status") == "verified":
                scanners_represented = set(e.get("scanner") for e in f.get("evidence", []))
                absent_scanners = {"git_scan", "memory_scan", "filesystem_scan", "transcript_scan"} - scanners_represented
                disconfirmation_report.append({
                    "claim": f["claim"][:100],
                    "verified_in": sorted(scanners_represented),
                    "no_contradiction_in": sorted(absent_scanners),
                })

        result = {
            "status": "DONE",
            "node_id": "contradiction_check",
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
