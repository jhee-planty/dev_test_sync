#!/usr/bin/env python3
"""disconfirmation_check — antonym-bounded pointed search for verified findings.

입력:  outputs/contradiction_check.json
출력:  outputs/disconfirmation_check.json
       각 finding 에 `disconfirmation: {checked, counter_evidence, antonyms_used}` 필드 추가.

Round 3 consensus (2026-04-22 토론):
- verified finding 에 대해서만 반의어 기반 targeted rescan 수행.
- 반의어 dict 는 ANTONYM_DICT + incident_registry 학습.
- 반의어 없으면 checked="N/A" (honest: can't verify negation).
- 반의어 있으면 transcript + filesystem 재스캔 → counter_evidence 수집.
- counter_evidence 발견 시 해당 finding 의 verification_status 를 "contradicted" 로 재분류.

status 규칙 (derive_status 에서 사용):
- 어떤 verified finding 이 disconfirmation.checked==false 이면 insufficient.
- N/A 는 insufficient 유발하지 않음 (antonym 없는 것은 skill 의 한계, 은폐 아님).
"""
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path


# ─── Antonym dictionary (seed) ────────────────────────────────────────
# Batch Linked List 맥락에서의 반의어 + 일반 antonym.
# v1.1 에서 incident_registry 학습으로 확장 예정.
ANTONYM_DICT = {
    # Data structures
    "linked list": ["DAG", "directed acyclic graph", "tree", "hash table"],
    "링크드 리스트": ["DAG", "트리", "해시맵"],
    "batch linked list": ["full DAG", "flat sequence", "single serial"],
    "parallel": ["serial", "sequential", "순차"],
    "병렬": ["직렬", "순차", "serial"],
    "serial": ["parallel", "concurrent", "병렬"],
    "직렬": ["병렬", "parallel"],
    "batch": ["solo", "single node", "단독"],
    "배치": ["단독", "solo", "개별"],
    # Execution
    "all_done": ["first_failure_aborts_batch", "early exit"],
    "immutable": ["mutable", "editable", "가변"],
    # Research concepts
    "primary": ["secondary", "derived", "의역"],
    "verified": ["unverified", "secondary-only", "contradicted"],
    "contradicted": ["verified", "consistent"],
    # Research-gathering specific
    "자료 조사": ["조사 생략", "기억 기반", "추측"],
    "정보 수집": ["추측", "기억"],
    "research-gathering": ["ad-hoc guess", "memory-only"],
    # Project-specific
    "stall_count": ["no stall tracking", "제거된 stall"],
    "compact": ["full context", "no compression"],
}


TRANSCRIPT_DIR = Path.home() / ".claude/projects/-Users-jhee-Documents-workspace-Officeguard-EtapV3"
FS_ROOTS = [
    Path.home() / "Documents/workspace/claude_work/projects/cowork-micro-skills",
    Path.home() / "Documents/workspace/dev_test_sync/shared-skills",
]
MAX_COUNTER_EVIDENCE_PER_FINDING = 5


def find_antonyms(claim: str, matched_keyword: str) -> list:
    """Lookup antonyms for finding. Try matched keyword first, then scan claim for known terms."""
    antonyms = set()
    # Direct lookup
    for key in [matched_keyword.lower(), matched_keyword]:
        if key in ANTONYM_DICT:
            antonyms.update(ANTONYM_DICT[key])
    # Scan claim text for known keywords
    claim_lower = (claim or "").lower()
    for k, vs in ANTONYM_DICT.items():
        if k.lower() in claim_lower:
            antonyms.update(vs)
    return sorted(antonyms)


def grep_fs(antonym: str) -> list:
    """Quick filesystem grep for antonym."""
    hits = []
    for root in FS_ROOTS:
        if not root.exists():
            continue
        try:
            # 얕은 grep — 성능 위해 .md / .sh / .py 만
            r = subprocess.run(
                ["grep", "-r", "-l", "--include=*.md", "--include=*.sh", "--include=*.py",
                 "-F", antonym, str(root)],
                capture_output=True, text=True, timeout=15
            )
            for path in r.stdout.strip().split("\n")[:MAX_COUNTER_EVIDENCE_PER_FINDING]:
                if path:
                    hits.append({"path": path, "antonym": antonym, "source": "filesystem"})
        except Exception:
            continue
    return hits


def grep_transcript(antonym: str) -> list:
    """Transcript 에서 antonym 출현 line 번호 수집 (얕게)."""
    hits = []
    if not TRANSCRIPT_DIR.exists():
        return hits
    for jl in sorted(TRANSCRIPT_DIR.glob("*.jsonl"))[:5]:  # 성능 위해 최신 5개만
        try:
            with open(jl, encoding="utf-8", errors="replace") as f:
                for line_no, line in enumerate(f, 1):
                    if antonym.lower() in line.lower():
                        hits.append({
                            "path": str(jl),
                            "line": line_no,
                            "antonym": antonym,
                            "source": "transcript",
                        })
                        if len(hits) >= MAX_COUNTER_EVIDENCE_PER_FINDING:
                            return hits
        except Exception:
            continue
    return hits


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--query-dir", required=True)
    args = ap.parse_args()

    query_dir = Path(args.query_dir)
    cc_path = query_dir / "outputs" / "contradiction_check.json"

    if not cc_path.exists():
        result = {
            "status": "FAILED",
            "node_id": "disconfirmation_check",
            "reason": "contradiction_check.json not found",
        }
    else:
        with open(cc_path, encoding="utf-8") as f:
            cc = json.load(f)
        findings = cc.get("findings", []) or []

        verified_findings = [f for f in findings if f.get("verification_status") == "verified"]

        per_finding_reports = []
        newly_contradicted = 0

        for f in verified_findings:
            claim = f.get("claim", "") or ""
            kw = f.get("keyword_matched", "") or ""
            antonyms = find_antonyms(claim, kw)

            if not antonyms:
                report = {
                    "finding_identity": f["evidence"][0].get("source_identity") if f.get("evidence") else None,
                    "claim_preview": claim[:80],
                    "checked": "N/A",
                    "reason": "no antonym available in dict",
                    "antonyms_used": [],
                    "counter_evidence": [],
                }
                f["disconfirmation"] = {"checked": "N/A", "counter_evidence_count": 0,
                                         "antonyms_used": []}
                per_finding_reports.append(report)
                continue

            # Targeted rescan with antonyms (top 3)
            counter = []
            for ant in antonyms[:3]:
                counter.extend(grep_fs(ant))
                counter.extend(grep_transcript(ant))
                if len(counter) >= MAX_COUNTER_EVIDENCE_PER_FINDING:
                    break

            counter = counter[:MAX_COUNTER_EVIDENCE_PER_FINDING]

            if counter:
                # Counter evidence 발견 → contradicted 재분류
                f["verification_status"] = "contradicted"
                newly_contradicted += 1
                report = {
                    "finding_identity": f["evidence"][0].get("source_identity") if f.get("evidence") else None,
                    "claim_preview": claim[:80],
                    "checked": True,
                    "antonyms_used": antonyms[:3],
                    "counter_evidence": counter,
                    "note": "contradicted by counter_evidence, reclassified",
                }
                f["disconfirmation"] = {"checked": True, "counter_evidence_count": len(counter),
                                         "antonyms_used": antonyms[:3]}
            else:
                report = {
                    "finding_identity": f["evidence"][0].get("source_identity") if f.get("evidence") else None,
                    "claim_preview": claim[:80],
                    "checked": True,
                    "antonyms_used": antonyms[:3],
                    "counter_evidence": [],
                    "note": "no counter_evidence, verification confirmed",
                }
                f["disconfirmation"] = {"checked": True, "counter_evidence_count": 0,
                                         "antonyms_used": antonyms[:3]}

            per_finding_reports.append(report)

        # Recompute counts after reclassification
        counts_after = {
            "verified": sum(1 for f in findings if f.get("verification_status") == "verified"),
            "single_source": sum(1 for f in findings if f.get("verification_status") == "single-source"),
            "secondary_only": sum(1 for f in findings if f.get("verification_status") == "secondary-only"),
            "contradicted": sum(1 for f in findings if f.get("verification_status") == "contradicted"),
        }

        # Insufficient check: any verified with checked==false?
        insufficient_reason = None
        for f in findings:
            if f.get("verification_status") == "verified":
                dc = f.get("disconfirmation", {})
                if dc.get("checked") is False:
                    insufficient_reason = f"verified finding not disconfirmation-checked: {f.get('claim','')[:60]}"
                    break

        result = {
            "status": "DONE",
            "node_id": "disconfirmation_check",
            "verified_input_count": len(verified_findings),
            "newly_contradicted": newly_contradicted,
            "counts_after": counts_after,
            "per_finding_reports": per_finding_reports,
            "insufficient_reason": insufficient_reason,
            "findings": findings,  # pass through with updated fields
        }

    out_path = query_dir / "outputs" / "disconfirmation_check.json"
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2, ensure_ascii=False)

    print(f"[disconfirmation_check] verified_input={result.get('verified_input_count', 0)} "
          f"newly_contradicted={result.get('newly_contradicted', 0)}", file=sys.stderr)
    print(json.dumps({"status": result["status"],
                      "newly_contradicted": result.get("newly_contradicted", 0)},
                     ensure_ascii=False))


if __name__ == "__main__":
    main()
