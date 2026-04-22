#!/usr/bin/env python3
"""transcript_scan — 세션 transcript (jsonl) 전수 스캔 (solo long-running).

입력:  query.json (keyword + expanded_terms)
출력:  outputs/transcript_scan.json

규칙:
- ~/.claude/projects/-Users-jhee-Documents-workspace-Officeguard-EtapV3/*.jsonl 전수
- 현재 세션 + 이전 세션 모두 포함 (cross-session bias 방지)
- 각 hit:
  * line 번호 + timestamp (jsonl 에 있으면)
  * jsonl type: user | assistant | tool_use | ...
  * quote 발췌 (최대 500자)
  * source_class:
    - user → primary
    - assistant → secondary
    - tool_use (Write/Edit content) → primary-if-user-approved-else-secondary
      (단순 hueristic: 직전 user message 가 승인 발언이면 primary)
- transcript 크기 큼 → MAX_HITS_PER_FILE 제한
- coverage: user_messages_read / user_messages_matched
"""
import argparse
import json
import sys
from pathlib import Path

TRANSCRIPT_DIR = Path.home() / ".claude/projects/-Users-jhee-Documents-workspace-Officeguard-EtapV3"
MAX_HITS_PER_FILE = 100
MAX_QUOTE_LEN = 500

APPROVAL_PATTERNS = ["반영", "적용", "진행", "저장", "수행", "맞", "좋", "승인", "approve", "apply", "proceed"]


def extract_text(msg_content):
    """jsonl message content 에서 텍스트 추출. list 또는 str."""
    if isinstance(msg_content, str):
        return msg_content
    if isinstance(msg_content, list):
        parts = []
        for b in msg_content:
            if isinstance(b, dict):
                if b.get("type") == "text":
                    parts.append(b.get("text", ""))
                elif b.get("type") == "tool_use":
                    inp = b.get("input", {})
                    for k in ("content", "new_string", "file_path", "command"):
                        if inp.get(k):
                            parts.append(str(inp[k]))
        return "\n".join(parts)
    return ""


def matches_keyword(text: str, keywords: list):
    """Return (keyword_matched, first_offset) or (None, -1)."""
    t_lower = text.lower()
    for kw in keywords:
        idx = t_lower.find(kw.lower())
        if idx >= 0:
            return kw, idx
    return None, -1


def classify_source(jsonl_type: str, text: str, prev_user_approval: bool) -> str:
    if jsonl_type == "user":
        return "primary"
    if jsonl_type == "assistant":
        return "secondary"
    if jsonl_type == "tool_use":
        return "primary" if prev_user_approval else "secondary"
    return "secondary"


def is_approval_message(text: str) -> bool:
    tl = text.lower()
    return any(p.lower() in tl for p in APPROVAL_PATTERNS)


def scan_jsonl(path: Path, keywords: list):
    hits = []
    user_msg_count = 0
    user_msg_matched = 0
    total_lines = 0
    parse_errors = 0
    last_user_approval = False

    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line_no, line in enumerate(f, 1):
                total_lines += 1
                try:
                    rec = json.loads(line)
                except Exception:
                    parse_errors += 1
                    continue

                rec_type = rec.get("type", "")
                msg = rec.get("message", {})
                if isinstance(msg, dict):
                    content = msg.get("content")
                else:
                    content = msg
                text = extract_text(content)

                if rec_type == "user":
                    user_msg_count += 1
                    # 시스템 리마인더나 tool_result 는 source 로 부적합
                    if any(marker in text for marker in ["<system-reminder>", "tool_use_id"]):
                        if is_approval_message(text):
                            last_user_approval = True
                        continue

                kw, offset = matches_keyword(text, keywords)
                if kw is None:
                    if rec_type == "user" and is_approval_message(text):
                        last_user_approval = True
                    continue

                if rec_type == "user":
                    user_msg_matched += 1

                # Extract quote around offset
                start = max(0, offset - 50)
                end = min(len(text), offset + 200)
                quote = text[start:end]
                if len(quote) > MAX_QUOTE_LEN:
                    quote = quote[:MAX_QUOTE_LEN] + "..."

                ts = rec.get("timestamp") or (msg.get("timestamp") if isinstance(msg, dict) else None) or ""

                hits.append({
                    "path": str(path),
                    "line": line_no,
                    "jsonl_type": rec_type,
                    "timestamp": ts,
                    "quote": quote,
                    "keyword_matched": kw,
                    "source_class": classify_source(rec_type, text, last_user_approval),
                    "prev_user_approval": last_user_approval,
                })

                if rec_type == "user" and is_approval_message(text):
                    last_user_approval = True

                if len(hits) >= MAX_HITS_PER_FILE:
                    break
    except Exception as e:
        return [], {"error": str(e), "parse_errors": parse_errors, "total_lines": total_lines}

    return hits, {
        "total_lines": total_lines,
        "parse_errors": parse_errors,
        "user_msg_count": user_msg_count,
        "user_msg_matched": user_msg_matched,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--query-dir", required=True)
    args = ap.parse_args()

    query_dir = Path(args.query_dir)
    with open(query_dir / "query.json", encoding="utf-8") as f:
        query = json.load(f)

    keywords = [query["keyword"]] + list(query.get("expanded_terms", []) or [])

    all_hits = []
    file_stats = []
    total_user_msgs = 0
    total_user_matched = 0

    if not TRANSCRIPT_DIR.exists():
        result = {
            "status": "FAILED",
            "node_id": "transcript_scan",
            "reason": f"transcript dir not found: {TRANSCRIPT_DIR}",
            "hit_count": 0,
            "hits": [],
        }
    else:
        jsonls = sorted(TRANSCRIPT_DIR.glob("*.jsonl"))
        for jl in jsonls:
            hits, stats = scan_jsonl(jl, keywords)
            all_hits.extend(hits)
            file_stats.append({
                "path": str(jl),
                "stats": stats,
                "hits_found": len(hits),
            })
            if isinstance(stats, dict):
                total_user_msgs += stats.get("user_msg_count", 0)
                total_user_matched += stats.get("user_msg_matched", 0)

        result = {
            "status": "DONE",
            "node_id": "transcript_scan",
            "scanned_files": len(jsonls),
            "file_stats": file_stats,
            "coverage": {
                "user_messages_read": total_user_msgs,
                "user_messages_matched": total_user_matched,
                "target": "min(20, all matched)" if total_user_matched <= 20 else "top-20 by density",
            },
            "hit_count": len(all_hits),
            "hits": all_hits,
        }

    out_path = query_dir / "outputs" / "transcript_scan.json"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2, ensure_ascii=False)

    print(f"[transcript_scan] {result.get('hit_count', 0)} hits across {len(file_stats)} jsonl files",
          file=sys.stderr)
    print(json.dumps({"status": result["status"], "hit_count": result.get("hit_count", 0)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
