#!/usr/bin/env python3
"""promotion_suggest — findings → INTENTS/MEMORY/lessons 승격 후보 제안.

입력:  outputs/contradiction_check.json (findings with verification_status)
출력:  outputs/promotion_suggest.json
       promotion_proposal.md (human-readable, query_dir 최상위)

규칙:
- 승격 후보 = primary 이고 현재 공식 문서에 없는 것
- 검사 대상 공식 문서:
  * cowork-micro-skills/INTENTS.md
  * cowork-micro-skills/lessons.md
  * ~/.claude/projects/.../memory/*.md
- source_class=primary + 해당 문서에 quote 없음 → strong 후보
- source_class=primary-historical + 해당 문서에 quote 없음 → weak 후보
- secondary-only 는 승격 후보 아님 (재검증 대상)
- target 결정 heuristic:
  * "immutable" / "원칙" / "intent" 포함 → INTENTS.md
  * "실수" / "lesson" / "재발 방지" 포함 → lessons.md
  * "피드백" / "사용자 선호" 포함 → MEMORY/feedback_*.md
  * 그 외 → MEMORY (기본)
"""
import argparse
import json
import re
import sys
from pathlib import Path


OFFICIAL_DOCS = [
    Path.home() / "Documents/workspace/claude_cowork/projects/cowork-micro-skills/INTENTS.md",
    Path.home() / "Documents/workspace/claude_cowork/projects/cowork-micro-skills/lessons.md",
    Path.home() / "Documents/workspace/claude_cowork/projects/cowork-micro-skills/master-plan.md",
    Path.home() / "Documents/workspace/claude_cowork/projects/cowork-micro-skills/README.md",
]

MEMORY_DIR = Path.home() / ".claude/projects/-Users-jhee-Documents-workspace-Officeguard-EtapV3/memory"


def load_official_corpus():
    """Load all official doc texts for presence check."""
    corpus = ""
    for p in OFFICIAL_DOCS:
        if p.exists():
            try:
                corpus += "\n\n" + p.read_text(encoding="utf-8", errors="replace")
            except Exception:
                pass
    if MEMORY_DIR.exists():
        for p in MEMORY_DIR.glob("*.md"):
            try:
                corpus += "\n\n" + p.read_text(encoding="utf-8", errors="replace")
            except Exception:
                pass
    return corpus


def is_in_corpus(claim: str, corpus: str) -> bool:
    """키워드 일부가 corpus 에 있으면 '이미 반영' 으로 간주 (느슨)."""
    # 짧은 토큰으로 대체
    tokens = re.findall(r"[\w가-힣]{4,}", claim)
    if not tokens:
        return False
    # 3개 이상 의미 있는 토큰이 corpus 에 있으면 이미 반영으로 판단
    hits = sum(1 for t in tokens[:10] if t.lower() in corpus.lower())
    return hits >= 3


def decide_target(claim: str) -> str:
    cl = claim.lower()
    if any(w in cl for w in ["immutable", "원칙", "intent", "invariant", "의도"]):
        return "INTENTS.md"
    if any(w in cl for w in ["실수", "lesson", "재발", "방지", "checklist"]):
        return "lessons.md"
    if any(w in cl for w in ["피드백", "feedback", "사용자 선호", "preference"]):
        return "MEMORY/feedback_*.md"
    return "MEMORY (new project_*.md or feedback_*.md)"


def decide_strength(source_class: str, location_count: int) -> str:
    if source_class == "primary" and location_count >= 2:
        return "strong"
    if source_class == "primary":
        return "strong"
    if source_class == "primary-historical":
        return "weak"
    return "weak"


def build_proposal_md(candidates: list, query_keyword: str) -> str:
    lines = [
        "# Promotion Proposal",
        "",
        f"**Query**: `{query_keyword}`",
        f"**Candidates**: {len(candidates)}",
        "",
        "아래 candidate 는 primary 증거가 있으나 현재 공식 문서 (INTENTS / lessons / master-plan / README / memory) 에 반영되지 않은 항목입니다.",
        "",
        "사용자가 `promote 1, 3, 5` 같은 지시를 주시면 해당 항목을 target 문서에 append 합니다.",
        "",
    ]
    for i, c in enumerate(candidates, 1):
        lines.append(f"## Candidate {i} — {c['target']} (strength: {c['strength']})")
        lines.append("")
        lines.append(f"**Claim**: {c['claim']}")
        lines.append("")
        lines.append(f"**Rationale**: {c['rationale']}")
        lines.append("")
        if c.get("evidence"):
            lines.append("**Evidence**:")
            for ev in c["evidence"][:3]:
                ts = ev.get("timestamp", "(no timestamp)")
                pth = ev.get("path", "(no path)")
                ln = ev.get("line", "?")
                lines.append(f"- `{pth}:{ln}` ({ts})")
                q = ev.get("quote", "")[:200]
                lines.append(f"  > {q}")
            lines.append("")
        lines.append("**Proposed action**:")
        lines.append(f"- Target: `{c['target']}`")
        lines.append(f"- Section hint: {c.get('section_hint', '(manual placement)')}")
        lines.append("- Approve by: `promote " + str(i) + "`")
        lines.append("")
        lines.append("---")
        lines.append("")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--query-dir", required=True)
    args = ap.parse_args()

    query_dir = Path(args.query_dir)
    with open(query_dir / "query.json", encoding="utf-8") as f:
        query = json.load(f)

    # Prefer disconfirmation_check 의 업데이트된 findings. fallback: contradiction_check.
    dc_path = query_dir / "outputs" / "disconfirmation_check.json"
    cc_path = query_dir / "outputs" / "contradiction_check.json"

    source_path = dc_path if dc_path.exists() else cc_path

    if not source_path.exists():
        result = {
            "status": "FAILED",
            "node_id": "promotion_suggest",
            "reason": "disconfirmation_check.json / contradiction_check.json not found",
            "promotion_candidates": [],
        }
    else:
        with open(source_path, encoding="utf-8") as f:
            cc = json.load(f)
        findings = cc.get("findings", []) or []

        corpus = load_official_corpus()
        candidates = []

        for f in findings:
            sc = f.get("source_class", "secondary")
            vs = f.get("verification_status", "")
            # 승격 후보 조건:
            if sc == "secondary":
                continue  # secondary-only 는 재검증 대상
            if vs == "contradicted":
                # contradicted 는 사용자 판단 필요 — weak 로 분리
                strength = "weak"
                rationale = "Contradicted primary evidence — 사용자 결정 필요."
            else:
                strength = decide_strength(sc, f.get("location_count", 1))
                rationale = f"{sc} finding ({vs}), {f.get('location_count', 1)} locations, 공식 문서 미반영."

            claim = f.get("claim", "") or ""
            if not claim:
                continue
            if is_in_corpus(claim, corpus):
                continue  # 이미 반영됨

            target = decide_target(claim)

            candidates.append({
                "claim": claim,
                "source_class": sc,
                "verification_status": vs,
                "target": target,
                "strength": strength,
                "rationale": rationale,
                "section_hint": None,
                "evidence": f.get("evidence", []),
            })

        result = {
            "status": "DONE",
            "node_id": "promotion_suggest",
            "candidate_count": len(candidates),
            "promotion_candidates": candidates,
        }

        # Write human-readable proposal
        proposal_md = build_proposal_md(candidates, query.get("keyword", ""))
        with open(query_dir / "promotion_proposal.md", "w", encoding="utf-8") as f:
            f.write(proposal_md)

    out_path = query_dir / "outputs" / "promotion_suggest.json"
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2, ensure_ascii=False)

    print(f"[promotion_suggest] {result.get('candidate_count', 0)} candidates", file=sys.stderr)
    print(json.dumps({"status": result["status"], "candidate_count": result.get("candidate_count", 0)},
                     ensure_ascii=False))


if __name__ == "__main__":
    main()
