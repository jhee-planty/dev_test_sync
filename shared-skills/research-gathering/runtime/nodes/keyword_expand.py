#!/usr/bin/env python3
"""keyword_expand — 키워드 동의어·관련어 확장 (serial loop, ≤3 iter).

입력:  query.json 의 keyword + (이전 iter 의 scan 결과가 있으면 관련어 힌트)
출력:  outputs/keyword_expand_loop/iter_{1,2,3}.json
사이드이펙트: query.json 의 expanded_terms 필드 갱신.

규칙:
- iter 1: 휴리스틱 기반 (Korean↔English translation, 자주 쓰이는 동의어 dict)
- iter 2~3: 이전 scan 결과가 있으면 파일명/인접 단어에서 관련어 추출
- 총 3회까지만 실행. Fixed point 도달 (새 용어 0개 추가) 시 조기 종료.
- incident_registry.jsonl 의 missed-keyword 기록이 있으면 expansion dict 에 반영.
"""
import argparse
import json
import os
import re
import sys
from pathlib import Path

# ─── 휴리스틱 expansion dictionary ────────────────────────────────────
# Korean ↔ English 및 자주 쓰이는 동의어 / 관련어.
# 본 dict 는 v1 휴리스틱. v1.1 에서 incident_registry 학습으로 확장.
HEURISTIC_DICT = {
    # Data structures
    "링크드 리스트": ["linked list", "linked-list", "batch linked list", "linked list of batches"],
    "linked list": ["링크드 리스트", "linked-list", "batch linked list"],
    "스택": ["stack", "LIFO", "콜스택", "push pop"],
    "stack": ["스택", "LIFO", "call stack"],
    "배치": ["batch", "parallel batch", "batch node"],
    "batch": ["배치", "parallel batch"],
    "병렬": ["parallel", "parallelism", "concurrent"],
    "parallel": ["병렬", "parallelism"],
    "직렬": ["serial", "sequential"],
    "serial": ["직렬", "sequential"],
    # Execution modes
    "execution_mode": ["execution mode", "실행 모드", "serial | parallel"],
    "barrier_policy": ["barrier policy", "barrier", "all_done", "first_failure_aborts_batch"],
    # Sources / tiers
    "transcript": ["jsonl", "세션 기록", "대화 기록"],
    "jsonl": ["transcript", "session log"],
    # Research concepts
    "자료 조사": ["research gathering", "information gathering", "정보 수집", "pre-collection", "phase 0"],
    "정보 수집": ["자료 조사", "research gathering", "pre-collection"],
    "research-gathering": ["자료 조사", "research gathering", "정보 수집"],
    # Persistence
    "compact": ["context compression", "세션 압축"],
    "persistence": ["영구 저장", "보존", "스냅샷"],
    # Project-specific
    "INTENTS": ["intents.md", "사용자 의도", "immutable 원칙"],
    "stall_count": ["stall-count", "stalled", "polling stall"],
}


def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def save_json(path, data):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)


def heuristic_expand(keyword: str) -> list:
    """Dict lookup. 정확 매치 + 부분 매치."""
    hits = set()
    k_lower = keyword.lower()

    # Exact match
    if keyword in HEURISTIC_DICT:
        hits.update(HEURISTIC_DICT[keyword])

    # Case-insensitive / partial match
    for k, vs in HEURISTIC_DICT.items():
        if k_lower == k.lower() or k_lower in k.lower() or k.lower() in k_lower:
            hits.update(vs)

    hits.discard(keyword)
    return sorted(hits)


def load_incident_dict(skill_dir: Path) -> dict:
    """incident_registry.jsonl 의 missed-keyword 기록을 확장 dict 에 편입."""
    registry = skill_dir / "runtime" / "incident_registry.jsonl"
    if not registry.exists():
        return {}
    result = {}
    with open(registry, encoding="utf-8") as f:
        for line in f:
            try:
                rec = json.loads(line)
                mk = rec.get("missed_keyword", "").strip()
                desc = rec.get("description", "").strip()
                if mk and desc:
                    # Missed keyword 를 description 의 주요 단어들과 연결
                    words = re.findall(r"\b\w{3,}\b", desc)
                    result.setdefault(mk, []).extend(words[:5])
            except Exception:
                continue
    return result


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--query-dir", required=True)
    ap.add_argument("--max-iter", type=int, default=3)
    args = ap.parse_args()

    query_dir = Path(args.query_dir)
    skill_dir = Path(__file__).resolve().parent.parent.parent
    expand_out_dir = query_dir / "outputs" / "keyword_expand_loop"
    expand_out_dir.mkdir(parents=True, exist_ok=True)

    query = load_json(query_dir / "query.json")
    original_keyword = query["keyword"]
    expanded_terms = set(query.get("expanded_terms", []) or [])

    incident_dict = load_incident_dict(skill_dir)

    print(f"[keyword_expand] original='{original_keyword}' max_iter={args.max_iter}", file=sys.stderr)

    prev_size = len(expanded_terms)
    for iteration in range(1, args.max_iter + 1):
        # 이번 iter 의 후보 수집
        candidates = set()

        # Source 1: 휴리스틱 dict (iter 1 주력)
        candidates.update(heuristic_expand(original_keyword))
        for e in list(expanded_terms):
            candidates.update(heuristic_expand(e))

        # Source 2: incident-learned
        if original_keyword in incident_dict:
            candidates.update(incident_dict[original_keyword])

        # Source 3: iter ≥ 2 — 이전 scan 결과가 있으면 그 중 인접 단어 추출
        if iteration >= 2:
            for scan_name in ["git_scan.json", "memory_scan.json", "filesystem_scan.json"]:
                scan_path = query_dir / "outputs" / scan_name
                if scan_path.exists():
                    try:
                        scan = load_json(scan_path)
                        for hit in (scan.get("hits", []) or [])[:20]:
                            ctx = hit.get("context", "") or hit.get("line_text", "") or ""
                            words = re.findall(r"[\w-]{4,}", ctx)
                            candidates.update(words[:3])
                    except Exception:
                        pass

        # 필터: 원본 키워드 제외, 너무 긴/짧은 제외, stopwords 제외
        filtered = {
            c for c in candidates
            if c != original_keyword
            and c not in expanded_terms
            and 2 <= len(c) <= 60
            and not c.lower() in {"the", "and", "for", "with", "from", "into", "this", "that"}
        }

        expanded_terms.update(filtered)

        # iter 결과 저장
        iter_result = {
            "iteration": iteration,
            "new_terms_added": sorted(filtered),
            "cumulative_expanded": sorted(expanded_terms),
            "fixed_point_reached": len(filtered) == 0,
        }
        save_json(expand_out_dir / f"iter_{iteration}.json", iter_result)

        print(f"[keyword_expand] iter {iteration}: +{len(filtered)} terms (total {len(expanded_terms)})",
              file=sys.stderr)

        # Fixed point 도달 시 조기 종료
        if len(filtered) == 0 and iteration > 1:
            print(f"[keyword_expand] fixed point at iter {iteration}, stopping early", file=sys.stderr)
            break

        prev_size = len(expanded_terms)

    # query.json 갱신
    query["expanded_terms"] = sorted(expanded_terms)
    save_json(query_dir / "query.json", query)

    # Final summary
    summary = {
        "status": "DONE",
        "node_id": "keyword_expand_loop",
        "iterations_run": iteration,
        "total_expanded": len(expanded_terms),
        "expanded_terms": sorted(expanded_terms),
    }
    save_json(expand_out_dir / "summary.json", summary)
    print(json.dumps(summary, ensure_ascii=False))


if __name__ == "__main__":
    main()
