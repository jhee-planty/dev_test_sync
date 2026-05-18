#!/usr/bin/env python3
"""
Extract & sanitize SSE schema from genspark plain-text branch HAR (#1043).
Counterpart to extract_har_1031.py (tool-call branch).

Output: extract_1043.json with per-event schema, type counts, terminator analysis,
and a side-by-side comparison vs the #1031 tool-call branch.
"""
import json
import re
import sys
from collections import Counter, OrderedDict
from pathlib import Path

WORKTREE = Path(r"C:\Users\최장희\Documents\dev_test_sync\.claude\worktrees\unruffled-mcnulty-8a516d")
HAR_PATH = WORKTREE / "files" / "1043" / "genspark_plain_1043.har"
OUT_PATH = WORKTREE / "files" / "1043" / "extract_1043.json"
PRIOR_EXTRACT = WORKTREE / "files" / "1031" / "extract_1031.json"


def find_ask_proxy_entry(har):
    for entry in har["log"]["entries"]:
        url = entry["request"]["url"]
        if "/api/agent/ask_proxy" in url:
            return entry
    return None


def parse_sse(body_text):
    """Each SSE event = 'data: <json>\\n\\n'. Return list of dicts."""
    events = []
    # Split on double newline boundaries
    chunks = re.split(r"\n\n+", body_text)
    for chunk in chunks:
        chunk = chunk.strip()
        if not chunk:
            continue
        # Strip 'data:' prefix from each line; an event may have multiple data: lines
        data_lines = []
        for line in chunk.split("\n"):
            if line.startswith("data:"):
                data_lines.append(line[len("data:"):].lstrip())
        if not data_lines:
            continue
        payload = "\n".join(data_lines)
        if payload == "[DONE]":
            events.append({"_raw_sentinel": "[DONE]"})
            continue
        try:
            events.append(json.loads(payload))
        except json.JSONDecodeError as e:
            events.append({"_parse_error": str(e), "_raw": payload[:500]})
    return events


def sanitize_uuid(s, mapping):
    """Replace UUID-like values with stable aliases."""
    uuid_re = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")

    def repl(m):
        u = m.group(0)
        if u not in mapping:
            mapping[u] = f"<uuid-{len(mapping)}>"
        return mapping[u]

    if isinstance(s, str):
        return uuid_re.sub(repl, s)
    return s


def sanitize_event(ev, mapping):
    out = {}
    for k, v in ev.items():
        if isinstance(v, str):
            out[k] = sanitize_uuid(v, mapping)
        elif isinstance(v, dict):
            out[k] = sanitize_dict(v, mapping)
        elif isinstance(v, list):
            out[k] = [sanitize_dict(x, mapping) if isinstance(x, dict) else sanitize_uuid(x, mapping) if isinstance(x, str) else x for x in v]
        else:
            out[k] = v
    return out


def sanitize_dict(d, mapping):
    out = {}
    for k, v in d.items():
        if isinstance(v, str):
            out[k] = sanitize_uuid(v, mapping)
        elif isinstance(v, dict):
            out[k] = sanitize_dict(v, mapping)
        elif isinstance(v, list):
            out[k] = [sanitize_dict(x, mapping) if isinstance(x, dict) else sanitize_uuid(x, mapping) if isinstance(x, str) else x for x in v]
        else:
            out[k] = v
    return out


def main():
    har = json.loads(HAR_PATH.read_text(encoding="utf-8"))
    entry = find_ask_proxy_entry(har)
    if entry is None:
        print("ERROR: no ask_proxy entry found", file=sys.stderr)
        sys.exit(1)

    req = entry["request"]
    resp = entry["response"]
    body = resp.get("content", {}).get("text", "")
    body_size = resp.get("content", {}).get("size", len(body))
    content_type = next((h["value"] for h in resp.get("headers", []) if h["name"].lower() == "content-type"), "")
    status = resp.get("status")
    method = req.get("method")
    url = req.get("url")
    started = entry.get("startedDateTime")
    timings = entry.get("timings", {})
    total_time_ms = entry.get("time", 0)

    events = parse_sse(body)
    mapping = {}
    sanitized_events = [sanitize_event(e, mapping) for e in events]

    # Type counts (top-level discriminator)
    type_counts = Counter(e.get("type", "<no-type>") for e in events)

    # Per-field analysis for message_field_delta events
    delta_field_counts = Counter()
    delta_field_byte_total = {}
    for ev in events:
        if ev.get("type") == "message_field_delta":
            fname = ev.get("field_name", "<unknown>")
            delta_field_counts[fname] += 1
            delta_field_byte_total[fname] = delta_field_byte_total.get(fname, 0) + len(ev.get("delta", "") or "")

    # Assemble content from delta channel (plain-text path)
    assembled_by_field = {}
    for ev in events:
        if ev.get("type") == "message_field_delta":
            fname = ev.get("field_name", "<unknown>")
            assembled_by_field.setdefault(fname, []).append(ev.get("delta", ""))
    assembled = {fname: "".join(parts) for fname, parts in assembled_by_field.items()}

    # message_result terminator analysis
    message_results = [e for e in events if e.get("type") == "message_result"]
    terminator_info = []
    for mr in message_results:
        msg = mr.get("message", {}) if isinstance(mr.get("message"), dict) else {}
        terminator_info.append({
            "_event_index": mr.get("_event_index"),
            "message_id_alias": sanitize_uuid(mr.get("message_id", ""), mapping),
            "has_message_content": bool(msg.get("content")),
            "message_content_preview": (msg.get("content", "") or "")[:200],
            "has_tool_calls": bool(msg.get("tool_calls")),
            "tool_calls_count": len(msg.get("tool_calls", []) or []),
            "session_state_finish_reason": (msg.get("session_state", {}) or {}).get("_finish_reason"),
            "llm_usage": mr.get("_llm_usage") or msg.get("_llm_usage"),
            "role": msg.get("role"),
        })

    # Last 5 event types
    last5 = [e.get("type") for e in events[-5:]]
    # First 5 event types
    first5 = [e.get("type") for e in events[:5]]

    # Comparison vs #1031
    prior = {}
    if PRIOR_EXTRACT.exists():
        try:
            prior_data = json.loads(PRIOR_EXTRACT.read_text(encoding="utf-8"))
            prior = {
                "event_count": prior_data.get("event_count"),
                "type_counts": prior_data.get("type_counts"),
                "delta_field_counts": prior_data.get("delta_field_counts"),
                "body_size_bytes": prior_data.get("body_size_bytes"),
                "total_time_ms": prior_data.get("total_time_ms"),
                "message_result_count": prior_data.get("message_result_count"),
            }
        except Exception as e:
            prior = {"_load_error": str(e)}

    output = OrderedDict([
        ("schema_version", 1),
        ("captured_for", "request #1043 — genspark plain-text branch (engine DISABLED)"),
        ("comparison_target", "request #1031 — genspark tool-call branch (project card UI)"),
        ("prompt_submitted", "What is the result of one plus one?"),
        ("observed_user_visible_response", "1 더하기 1은 **2**입니다. ✨ (simple text bubble, NO tool-call card)"),
        ("project_id_alias", sanitize_uuid("2d768c46-7a8d-4478-a1b6-efbd0aec5b2e", mapping)),
        ("page_url_after_submit", f"https://www.genspark.ai/agents?id={sanitize_uuid('2d768c46-7a8d-4478-a1b6-efbd0aec5b2e', mapping)}"),
        ("endpoint", {
            "method": method,
            "url": url,
            "status": status,
            "content_type": content_type,
            "body_size_bytes": body_size,
            "total_time_ms": round(total_time_ms, 2),
            "started": started,
        }),
        ("event_count", len(events)),
        ("type_counts", dict(type_counts.most_common())),
        ("first_5_types", first5),
        ("last_5_types", last5),
        ("delta_field_counts", dict(delta_field_counts.most_common())),
        ("delta_field_byte_totals", delta_field_byte_total),
        ("assembled_content_per_field", {k: (v[:500] if len(v) > 500 else v) for k, v in assembled.items()}),
        ("assembled_content_full_lengths", {k: len(v) for k, v in assembled.items()}),
        ("message_result_count", len(message_results)),
        ("message_result_terminator_info", terminator_info),
        ("uuid_alias_count", len(mapping)),
        ("comparison_vs_1031_tool_call_branch", {
            "1043_plain_text": {
                "event_count": len(events),
                "type_counts": dict(type_counts.most_common()),
                "delta_field_counts": dict(delta_field_counts.most_common()),
                "body_size_bytes": body_size,
                "total_time_ms": round(total_time_ms, 2),
                "message_result_count": len(message_results),
            },
            "1031_tool_call": prior,
        }),
        ("sanitized_events_full", sanitized_events),
    ])

    OUT_PATH.write_text(json.dumps(output, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Wrote {OUT_PATH}")
    print(f"Event count: {len(events)}")
    print(f"Type counts: {dict(type_counts.most_common())}")
    print(f"Delta field counts: {dict(delta_field_counts.most_common())}")
    print(f"Body size: {body_size} bytes; total_time: {total_time_ms:.2f} ms")
    print(f"message_result count: {len(message_results)}")
    print(f"First 5 types: {first5}")
    print(f"Last 5 types: {last5}")


if __name__ == "__main__":
    main()
