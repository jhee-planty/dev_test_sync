#!/usr/bin/env python3
"""generate_report — 모든 노드 출력을 통합해 report.json (schema v1) + report.md 작성.

입력:  outputs/{git,memory,filesystem,transcript,aggregate_dedup,contradiction_check,promotion_suggest}.json
출력:  report.json (schema v1), report.md (human-readable)
       stdout 에 report.json 경로 출력
exit 0 if status in (complete, insufficient); else 1.
"""
import argparse
import json
import sys
from pathlib import Path


def load(outputs: Path, name: str):
    p = outputs / f"{name}.json"
    if p.exists():
        try:
            with open(p, encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return None
    return None


def derive_status(failed, contradictions, findings):
    unresolved = any(c.get("resolution") in ("user_required", "deferred") for c in contradictions)
    if failed:
        return "partial"
    if unresolved:
        return "insufficient"
    if len(findings) == 0:
        return "insufficient"
    return "complete"


def build_report_md(query, status, coverage, findings, contradictions, failed, promotion_candidates):
    lines = []
    lines.append("# research-gathering report")
    lines.append("")
    lines.append(f"**Query**: `{query.get('keyword', '')}`")
    expanded = query.get("expanded_terms", []) or []
    lines.append(f"**Expanded**: {', '.join(expanded) if expanded else '(none)'}")
    lines.append(f"**Status**: **{status}**")
    lines.append(f"**Consumer**: {query.get('consumer', '')}")
    lines.append(f"**Invoked**: {query.get('invoked_at', '')}")
    lines.append("")
    lines.append("## Coverage")
    lines.append("")
    for tier, cov in coverage.items():
        num = cov.get("numerator", 0) if isinstance(cov, dict) else 0
        den = cov.get("denominator", 0) if isinstance(cov, dict) else 0
        lines.append(f"- **{tier}**: {num} / {den}")
    lines.append("")
    lines.append(f"## Findings ({len(findings)})")
    lines.append("")
    for i, fnd in enumerate(findings[:30], 1):
        sc = fnd.get("source_class", "?")
        vs = fnd.get("verification_status", "?")
        claim = (fnd.get("claim", "") or "").replace("\n", " ")[:200]
        lines.append(f"### {i}. [{sc} / {vs}]")
        lines.append(f"**Claim**: {claim}")
        lines.append("")
        for ev in (fnd.get("evidence", []) or [])[:3]:
            pth = ev.get("path", "?")
            ln = ev.get("line", "?")
            ts = ev.get("timestamp", "")
            q = (ev.get("quote", "") or "").replace("\n", " ")[:200]
            lines.append(f"- `{pth}:{ln}` ({ts})")
            if q:
                lines.append(f"  > {q}")
        lines.append("")

    if contradictions:
        lines.append(f"## Contradictions ({len(contradictions)})")
        lines.append("")
        for c in contradictions:
            topic = c.get("topic", "(no topic)")
            vals = c.get("values", [])
            res = c.get("resolution", "(no resolution)")
            lines.append(f"- **{topic}**: {len(vals)} distinct values → {res}")
        lines.append("")

    if failed:
        lines.append("## Failed Nodes")
        lines.append("")
        for nf in failed:
            lines.append(f"- **{nf.get('node_id', '?')}**: {nf.get('reason', '?')} (severity: {nf.get('severity', '?')})")
        lines.append("")

    if promotion_candidates:
        lines.append(f"## Promotion Candidates ({len(promotion_candidates)})")
        lines.append("")
        lines.append("See `promotion_proposal.md` for full actionable diffs.")
        lines.append("")

    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--query-dir", required=True)
    args = ap.parse_args()

    qd = Path(args.query_dir)
    outputs = qd / "outputs"

    query = json.load(open(qd / "query.json", encoding="utf-8"))
    plan = json.load(open(qd / "plan.json", encoding="utf-8"))

    git = load(outputs, "git_scan") or {}
    mem = load(outputs, "memory_scan") or {}
    fs  = load(outputs, "filesystem_scan") or {}
    tr  = load(outputs, "transcript_scan") or {}
    ag  = load(outputs, "aggregate_dedup") or {}
    cc  = load(outputs, "contradiction_check") or {}
    ps  = load(outputs, "promotion_suggest") or {}

    # Collect failed nodes
    failed = []
    for nid, n in plan["nodes"].items():
        if n.get("status") == "FAILED":
            failed.append({"node_id": nid, "reason": "runtime failure or not implemented", "severity": "medium"})
        if n.get("kind") == "batch":
            for child in n.get("children", []):
                if child.get("status") == "FAILED":
                    failed.append({"node_id": child["unit_id"], "reason": "runtime failure", "severity": "medium"})

    coverage = {
        "filesystem": fs.get("coverage", {}) if fs else {},
        "git":        git.get("coverage", {}) if git else {},
        "transcript": tr.get("coverage", {}) if tr else {},
        "memory":     mem.get("coverage", {}) if mem else {},
    }

    findings = cc.get("findings", []) or ag.get("findings", []) or []
    contradictions = cc.get("contradictions", []) or []
    promotion_candidates = ps.get("promotion_candidates", []) or []

    status = derive_status(failed, contradictions, findings)

    report = {
        "schema_version": 1,
        "query": query,
        "status": status,
        "coverage": coverage,
        "findings": findings,
        "contradictions": contradictions,
        "missing_actions": [],
        "promotion_candidates": promotion_candidates,
        "failed_nodes": failed,
    }
    for n in failed:
        report["missing_actions"].append(f"Retry or repair: {n['node_id']} ({n['reason']})")
    if any(c.get("resolution") in ("user_required", "deferred") for c in contradictions):
        report["missing_actions"].append("Resolve contradictions (see contradictions field)")

    with open(qd / "report.json", "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2, ensure_ascii=False)

    md = build_report_md(query, status, coverage, findings, contradictions, failed, promotion_candidates)
    with open(qd / "report.md", "w", encoding="utf-8") as f:
        f.write(md)

    print(str(qd / "report.json"))

    if status in ("complete", "insufficient"):
        sys.exit(0)
    sys.exit(1)


if __name__ == "__main__":
    main()
