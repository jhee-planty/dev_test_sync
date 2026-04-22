#!/usr/bin/env python3
"""git_scan — git log pickaxe across registered repos.

입력:  query.json (keyword + expanded_terms)
출력:  outputs/git_scan.json

규칙:
- dev_test_sync, cowork-micro-skills, Officeguard/EtapV3 가 기본 repos (존재하면 스캔)
- 각 repo 에서 `git log --all -S "<keyword>"` pickaxe 수행
- Non-git dir 이면 skip + failed_nodes 에 기록
- 각 commit: SHA + message + timestamp + author
- coverage: commits_inspected / commits_returned 기록
"""
import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

REPOS = [
    Path.home() / "Documents/workspace/dev_test_sync",
    Path.home() / "Documents/workspace/claude_cowork/projects/cowork-micro-skills",
    Path.home() / "Documents/workspace/Officeguard/EtapV3",
]

MAX_COMMITS_PER_REPO = 20  # head limit per repo to avoid runaway


def run(cmd, cwd=None, timeout=30):
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True,
                           cwd=str(cwd) if cwd else None, timeout=timeout)
        return r.stdout, r.stderr, r.returncode
    except subprocess.TimeoutExpired:
        return "", "timeout", -1
    except Exception as e:
        return "", str(e), -2


def is_git_repo(path: Path) -> bool:
    return (path / ".git").exists()


def pickaxe(repo: Path, keyword: str):
    """Return list of commit dicts where keyword appeared/disappeared."""
    kw_escaped = keyword.replace('"', '\\"').replace("'", "'\\''")
    cmd = f'git log --all --format="%H|%ai|%an|%s" -S "{kw_escaped}" | head -{MAX_COMMITS_PER_REPO}'
    out, err, rc = run(cmd, cwd=repo)
    if rc != 0:
        return [], err
    commits = []
    for line in out.strip().split("\n"):
        if not line:
            continue
        parts = line.split("|", 3)
        if len(parts) < 4:
            continue
        commits.append({
            "sha": parts[0],
            "timestamp": parts[1],
            "author": parts[2],
            "message": parts[3],
        })
    return commits, None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--query-dir", required=True)
    args = ap.parse_args()

    query_dir = Path(args.query_dir)
    with open(query_dir / "query.json", encoding="utf-8") as f:
        query = json.load(f)

    keywords = [query["keyword"]] + list(query.get("expanded_terms", []) or [])

    scanned_repos = []
    skipped_repos = []
    hits = []
    total_commits_returned = 0
    total_commits_inspected = 0

    for repo in REPOS:
        if not repo.exists():
            skipped_repos.append({"path": str(repo), "reason": "does not exist"})
            continue
        if not is_git_repo(repo):
            skipped_repos.append({"path": str(repo), "reason": "not a git repository"})
            continue
        scanned_repos.append(str(repo))

        for kw in keywords:
            commits, err = pickaxe(repo, kw)
            if err:
                skipped_repos.append({"path": str(repo), "keyword": kw, "reason": err[:200]})
                continue
            for c in commits:
                hits.append({
                    "repo": str(repo),
                    "keyword_matched": kw,
                    "sha": c["sha"],
                    "timestamp": c["timestamp"],
                    "author": c["author"],
                    "message": c["message"][:300],
                    "source_class": "primary",  # commit messages are primary artifacts
                })
                total_commits_returned += 1
                total_commits_inspected += 1

    # Dedup by sha (same commit may match multiple keywords)
    seen = set()
    deduped = []
    for h in hits:
        key = (h["repo"], h["sha"])
        if key in seen:
            continue
        seen.add(key)
        deduped.append(h)

    result = {
        "status": "DONE",
        "node_id": "git_scan",
        "scanned_repos": scanned_repos,
        "skipped_repos": skipped_repos,
        "hit_count": len(deduped),
        "coverage": {
            "commits_inspected": total_commits_inspected,
            "commits_returned": total_commits_returned,
            "repos_scanned": len(scanned_repos),
            "repos_available": len([r for r in REPOS if r.exists() and is_git_repo(r)]),
        },
        "hits": deduped,
    }

    out_path = query_dir / "outputs" / "git_scan.json"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2, ensure_ascii=False)

    print(f"[git_scan] {len(deduped)} hits across {len(scanned_repos)} repos", file=sys.stderr)
    print(json.dumps({"status": "DONE", "hit_count": len(deduped)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
