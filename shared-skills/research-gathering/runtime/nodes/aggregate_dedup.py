#!/usr/bin/env python3
"""aggregate_dedup — 4 scanner 출력 통합 + content hash dedup.

입력:  outputs/{git_scan,memory_scan,filesystem_scan,transcript_scan}.json
출력:  outputs/aggregate_dedup.json

규칙:
- 각 scanner 의 hits 를 한 리스트로 모음
- content hash = sha256(normalized_quote) 로 dedup key
- 같은 identity 가 여러 scanner / tier 에서 나오면 "locations" 배열로 묶음
- hit count 인플레이션 방지
- findings 리스트 생성 (claim + source_class + evidence 배열)
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path


def content_hash(text: str) -> str:
    """Normalize whitespace and hash."""
    normalized = " ".join((text or "").split()).lower()
    return "sha256:" + hashlib.sha256(normalized.encode("utf-8", errors="replace")).hexdigest()[:16]


def load_scan(path: Path):
    if not path.exists():
        return None
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def normalize_hit(hit: dict, scanner: str):
    """Normalize different scanner output shapes into a unified hit record."""
    text_for_hash = hit.get("quote") or hit.get("line_text") or hit.get("message") or ""
    return {
        "scanner": scanner,
        "path": hit.get("path") or hit.get("repo", ""),
        "line": hit.get("line"),
        "timestamp": hit.get("timestamp", ""),
        "quote": text_for_hash[:500] if text_for_hash else "",
        "keyword_matched": hit.get("keyword_matched", ""),
        "source_class": hit.get("source_class", "secondary"),
        "sha": hit.get("sha"),
        "jsonl_type": hit.get("jsonl_type"),
        "source_identity": content_hash(text_for_hash),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--query-dir", required=True)
    args = ap.parse_args()

    query_dir = Path(args.query_dir)
    outputs = query_dir / "outputs"

    scanners = {
        "git_scan": outputs / "git_scan.json",
        "memory_scan": outputs / "memory_scan.json",
        "filesystem_scan": outputs / "filesystem_scan.json",
        "transcript_scan": outputs / "transcript_scan.json",
    }

    unified_hits = []
    scanner_statuses = {}
    for name, path in scanners.items():
        data = load_scan(path)
        if data is None:
            scanner_statuses[name] = {"status": "MISSING", "hit_count": 0}
            continue
        scanner_statuses[name] = {
            "status": data.get("status", "UNKNOWN"),
            "hit_count": data.get("hit_count", 0),
        }
        for h in data.get("hits", []) or []:
            unified_hits.append(normalize_hit(h, name))

    # Dedup by source_identity — group locations.
    # Preserve distinct_files + distinct_scanners for verification logic (Round 1 consensus).
    import os
    by_identity = {}
    for h in unified_hits:
        sid = h["source_identity"]
        path = h["path"] or ""
        # "distinct file" = distinct (directory, filename) — not distinct line in same file
        file_key = os.path.basename(path) + "|" + os.path.dirname(path)
        if sid not in by_identity:
            by_identity[sid] = {
                "source_identity": sid,
                "quote": h["quote"],
                "keyword_matched": h["keyword_matched"],
                "source_class": h["source_class"],
                "locations": [],
                "distinct_files": set(),
                "distinct_scanners": set(),
            }
        by_identity[sid]["locations"].append({
            "scanner": h["scanner"],
            "path": h["path"],
            "line": h["line"],
            "timestamp": h["timestamp"],
            "jsonl_type": h["jsonl_type"],
            "sha": h["sha"],
        })
        by_identity[sid]["distinct_files"].add(file_key)
        by_identity[sid]["distinct_scanners"].add(h["scanner"])
        # Escalate source_class: primary beats secondary, primary-historical is primary for evidence purposes
        existing = by_identity[sid]["source_class"]
        if existing == "secondary" and h["source_class"].startswith("primary"):
            by_identity[sid]["source_class"] = h["source_class"]

    # Build findings: each unique source_identity is one finding (initial).
    # Later nodes (contradiction_check, promotion_suggest) add more structure.
    findings = []
    for sid, entry in by_identity.items():
        findings.append({
            "claim": entry["quote"][:200] if entry["quote"] else "(empty)",
            "source_class": entry["source_class"],
            "verification_status": "pending",  # contradiction_check 가 결정
            "evidence": [
                {
                    "path": loc["path"],
                    "line": loc["line"],
                    "timestamp": loc["timestamp"],
                    "quote": entry["quote"][:500],
                    "source_identity": sid,
                    "scanner": loc["scanner"],
                    "jsonl_type": loc.get("jsonl_type"),
                }
                for loc in entry["locations"]
            ],
            "location_count": len(entry["locations"]),
            "distinct_file_count": len(entry["distinct_files"]),
            "distinct_scanner_count": len(entry["distinct_scanners"]),
            "distinct_scanners": sorted(entry["distinct_scanners"]),
            "keyword_matched": entry["keyword_matched"],
        })

    # Sort: primary first, higher location_count first
    source_class_rank = {
        "primary": 0,
        "primary-historical": 1,
        "secondary": 2,
    }
    findings.sort(key=lambda f: (source_class_rank.get(f["source_class"], 3), -f["location_count"]))

    result = {
        "status": "DONE",
        "node_id": "aggregate_dedup",
        "scanner_statuses": scanner_statuses,
        "total_raw_hits": len(unified_hits),
        "unique_identities": len(by_identity),
        "dedup_ratio": round(len(by_identity) / max(1, len(unified_hits)), 3),
        "findings": findings,
    }

    out_path = outputs / "aggregate_dedup.json"
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2, ensure_ascii=False)

    print(f"[aggregate_dedup] {len(unified_hits)} raw → {len(by_identity)} unique identities",
          file=sys.stderr)
    print(json.dumps({"status": "DONE", "unique_identities": len(by_identity)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
