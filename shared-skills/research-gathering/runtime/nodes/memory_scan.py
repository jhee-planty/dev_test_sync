#!/usr/bin/env python3
"""memory_scan — ~/.claude/projects/.../memory/*.md 전수 grep.

입력:  query.json (keyword + expanded_terms)
출력:  outputs/memory_scan.json

규칙:
- MEMORY.md, project_*.md, feedback_*.md 모두 대상
- 모든 .md 파일 읽기 (메모리 디렉터리는 크기 작음, 전수 스캔 부담 없음)
- 파일명 + 라인 번호 + 주변 맥락 (3줄) 기록
- source_class: primary (사용자 영구 선호 기록 이므로)
"""
import argparse
import json
import sys
from pathlib import Path

MEMORY_DIR = Path.home() / ".claude/projects/-Users-jhee-Documents-workspace-Officeguard-EtapV3/memory"
CONTEXT_LINES = 2  # lines before/after each hit


def grep_file(path: Path, keywords: list):
    """Return list of hits for any keyword."""
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").split("\n")
    except Exception as e:
        return [], f"read_error: {e}"

    hits = []
    for i, line in enumerate(lines, 1):
        for kw in keywords:
            if kw.lower() in line.lower():
                start = max(0, i - 1 - CONTEXT_LINES)
                end = min(len(lines), i + CONTEXT_LINES)
                context = "\n".join(lines[start:end])
                hits.append({
                    "line": i,
                    "line_text": line,
                    "keyword_matched": kw,
                    "context": context,
                })
                break  # one hit per line
    return hits, None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--query-dir", required=True)
    args = ap.parse_args()

    query_dir = Path(args.query_dir)
    with open(query_dir / "query.json", encoding="utf-8") as f:
        query = json.load(f)

    keywords = [query["keyword"]] + list(query.get("expanded_terms", []) or [])

    scanned_files = []
    all_hits = []
    errors = []

    if not MEMORY_DIR.exists():
        result = {
            "status": "FAILED",
            "node_id": "memory_scan",
            "reason": f"memory dir not found: {MEMORY_DIR}",
            "severity": "medium",
            "hit_count": 0,
            "hits": [],
        }
    else:
        for md in sorted(MEMORY_DIR.glob("*.md")):
            scanned_files.append(str(md))
            hits, err = grep_file(md, keywords)
            if err:
                errors.append({"file": str(md), "error": err})
                continue
            for h in hits:
                h["path"] = str(md)
                h["source_class"] = "primary"
                all_hits.append(h)

        result = {
            "status": "DONE",
            "node_id": "memory_scan",
            "scanned_files": scanned_files,
            "errors": errors,
            "coverage": {
                "files_scanned": len(scanned_files),
                "files_total": len(scanned_files) + len(errors),
                "target": "all",
            },
            "hit_count": len(all_hits),
            "hits": all_hits,
        }

    out_path = query_dir / "outputs" / "memory_scan.json"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2, ensure_ascii=False)

    print(f"[memory_scan] {result['hit_count']} hits across {len(scanned_files)} files", file=sys.stderr)
    print(json.dumps({"status": result["status"], "hit_count": result["hit_count"]}, ensure_ascii=False))


if __name__ == "__main__":
    main()
