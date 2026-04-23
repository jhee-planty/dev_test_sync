#!/usr/bin/env python3
"""filesystem_scan — 현재 파일 + 과거 상태 (.bak / .disabled / archived / file-history).

입력:  query.json (keyword + expanded_terms)
출력:  outputs/filesystem_scan.json

규칙:
- 대상 루트:
  * claude_work/projects/cowork-micro-skills/
  * dev_test_sync/shared-skills/
  * ~/.claude/skills/
  * ~/.claude/file-history/
- 파일 유형:
  * 현재: .md, .sh, .json, .py
  * 과거: *.bak-*, *.disabled-*, *archived* 디렉터리
- 각 hit: 파일 경로 + 라인 + 주변 맥락
- source_class 는 heuristic:
  * .bak, .disabled, archived, file-history → primary-historical (사용자 작업 흔적)
  * 현재 파일 → primary
"""
import argparse
import json
import subprocess
import sys
from pathlib import Path

ROOTS = [
    Path.home() / "Documents/workspace/claude_work/projects/cowork-micro-skills",
    Path.home() / "Documents/workspace/dev_test_sync/shared-skills",
    Path.home() / ".claude/skills",
    Path.home() / ".claude/file-history",
]

ARCHIVED_ROOTS = [
    Path.home() / "Documents/workspace/claude_work/projects",
    Path.home() / "Documents/workspace/dev_test_sync",
]

FILE_PATTERNS = ["*.md", "*.sh", "*.json", "*.py"]
BAK_PATTERNS = ["*.bak-*", "*.disabled-*"]

MAX_HITS_PER_FILE = 20
CONTEXT_LINES = 1


def grep_file(path: Path, keywords: list, source_class: str):
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").split("\n")
    except Exception:
        return []
    hits = []
    for i, line in enumerate(lines, 1):
        for kw in keywords:
            if kw.lower() in line.lower():
                start = max(0, i - 1 - CONTEXT_LINES)
                end = min(len(lines), i + CONTEXT_LINES)
                hits.append({
                    "path": str(path),
                    "line": i,
                    "line_text": line[:500],
                    "keyword_matched": kw,
                    "context": "\n".join(lines[start:end])[:800],
                    "source_class": source_class,
                })
                if len(hits) >= MAX_HITS_PER_FILE:
                    return hits
                break
    return hits


def iter_current_files(root: Path):
    for pattern in FILE_PATTERNS:
        for p in root.rglob(pattern):
            if p.is_file():
                yield p


def iter_bak_files(root: Path):
    for pattern in BAK_PATTERNS:
        for p in root.rglob(pattern):
            if p.is_file():
                yield p


def iter_archived_dirs(root: Path):
    """Find *archived* directories (up to depth 3)."""
    try:
        for depth1 in root.iterdir():
            if not depth1.is_dir():
                continue
            if "archived" in depth1.name.lower():
                yield depth1
            # Depth 2
            try:
                for depth2 in depth1.iterdir():
                    if depth2.is_dir() and "archived" in depth2.name.lower():
                        yield depth2
            except Exception:
                continue
    except Exception:
        return


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--query-dir", required=True)
    args = ap.parse_args()

    query_dir = Path(args.query_dir)
    with open(query_dir / "query.json", encoding="utf-8") as f:
        query = json.load(f)

    keywords = [query["keyword"]] + list(query.get("expanded_terms", []) or [])
    all_hits = []
    files_scanned = 0
    files_with_match = 0
    failed = []

    # 1) Current files
    for root in ROOTS:
        if not root.exists():
            failed.append({"root": str(root), "reason": "does not exist"})
            continue
        for f in iter_current_files(root):
            files_scanned += 1
            # Skip very large files
            try:
                if f.stat().st_size > 2_000_000:
                    continue
            except Exception:
                continue
            hits = grep_file(f, keywords, "primary")
            if hits:
                files_with_match += 1
                all_hits.extend(hits)

    # 2) .bak / .disabled files
    for root in ROOTS:
        if not root.exists():
            continue
        for f in iter_bak_files(root):
            files_scanned += 1
            try:
                if f.stat().st_size > 2_000_000:
                    continue
            except Exception:
                continue
            hits = grep_file(f, keywords, "primary-historical")
            if hits:
                files_with_match += 1
                all_hits.extend(hits)

    # 3) Archived dirs
    archived_dirs_found = []
    for root in ARCHIVED_ROOTS:
        if not root.exists():
            continue
        for d in iter_archived_dirs(root):
            archived_dirs_found.append(str(d))
            for f in iter_current_files(d):
                files_scanned += 1
                try:
                    if f.stat().st_size > 2_000_000:
                        continue
                except Exception:
                    continue
                hits = grep_file(f, keywords, "primary-historical")
                if hits:
                    files_with_match += 1
                    all_hits.extend(hits)

    result = {
        "status": "DONE" if not failed or files_scanned > 0 else "PARTIAL",
        "node_id": "filesystem_scan",
        "scanned_roots": [str(r) for r in ROOTS if r.exists()],
        "failed_roots": failed,
        "archived_dirs_found": archived_dirs_found,
        "coverage": {
            "files_scanned": files_scanned,
            "files_with_match": files_with_match,
            "target": "0.95 of reachable files under specified patterns",
        },
        "hit_count": len(all_hits),
        "hits": all_hits,
    }

    out_path = query_dir / "outputs" / "filesystem_scan.json"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2, ensure_ascii=False)

    print(f"[filesystem_scan] {len(all_hits)} hits / {files_scanned} files scanned", file=sys.stderr)
    print(json.dumps({"status": result["status"], "hit_count": len(all_hits)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
