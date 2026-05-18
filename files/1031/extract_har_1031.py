#!/usr/bin/env python3
"""Extract sanitized SSE schema from native Genspark ask_proxy capture (#1031).

Goal: Provide ground-truth SSE event schema (event types, payload field paths,
content path used to assemble the visible assistant text/UI) so dev can design
the iter13 engine envelope. Strips auth tokens, cookies, JWT bearers.
"""
import json
import re
import collections
from urllib.parse import urlparse

HAR_PATH = r'C:\Users\최장희\Documents\dev_test_sync\.claude\worktrees\unruffled-mcnulty-8a516d\files\1031\genspark_native_1031.har'
OUT_PATH = r'C:\Users\최장희\Documents\dev_test_sync\.claude\worktrees\unruffled-mcnulty-8a516d\files\1031\extract_1031.json'

SENSITIVE_HEADER_KEYS = {
    'cookie', 'set-cookie', 'authorization',
    'x-csrftoken', 'x-csrf-token', 'csrf-token',
    'x-auth-token', 'x-session-token',
}
SENSITIVE_NAME_FRAGMENTS = ('token', 'session', 'auth', 'cookie', 'jwt')

def sanitize_headers(headers):
    out = []
    for h in headers:
        name = h.get('name', '')
        nl = name.lower()
        val = h.get('value', '')
        if nl in SENSITIVE_HEADER_KEYS or any(f in nl for f in SENSITIVE_NAME_FRAGMENTS):
            out.append({'name': name, 'value': f'<REDACTED_LEN_{len(val)}>'})
        else:
            out.append({'name': name, 'value': val if len(val) < 300 else val[:300] + '...<truncated>'})
    return out

def parse_sse(text):
    """Parse SSE stream text into list of event dicts."""
    events = []
    # SSE blocks separated by blank line. Each block has lines like `data: {...}`.
    for block in text.split('\n\n'):
        block = block.strip()
        if not block:
            continue
        # Collect all data: lines (multi-line data is concatenated with newlines per SSE spec)
        data_lines = []
        for line in block.split('\n'):
            if line.startswith('data:'):
                data_lines.append(line[5:].lstrip())
        if not data_lines:
            continue
        raw = '\n'.join(data_lines)
        try:
            obj = json.loads(raw)
            events.append(obj)
        except json.JSONDecodeError:
            events.append({'__parse_error__': True, 'raw_preview': raw[:200]})
    return events

def sample_payload(ev, max_field_len=120):
    """Return a redacted-but-shape-preserving sample of an event."""
    def red(v):
        if isinstance(v, str):
            return v if len(v) <= max_field_len else v[:max_field_len] + '...<truncated>'
        if isinstance(v, dict):
            return {k: red(x) for k, x in v.items()}
        if isinstance(v, list):
            return [red(x) for x in v[:5]] + (['...'] if len(v) > 5 else [])
        return v
    return red(ev)

with open(HAR_PATH, 'r', encoding='utf-8') as f:
    har = json.load(f)

entries = har['log']['entries']
ask_proxy_entry = None
for e in entries:
    if 'ask_proxy' in e['request']['url']:
        ask_proxy_entry = e
        break

if ask_proxy_entry is None:
    raise SystemExit('ask_proxy entry not found in HAR')

req = ask_proxy_entry['request']
resp = ask_proxy_entry['response']
parsed_url = urlparse(req['url'])

# Parse request body
req_body_obj = None
post_data = req.get('postData', {})
post_text = post_data.get('text', '')
try:
    req_body_obj = json.loads(post_text) if post_text else None
except Exception:
    req_body_obj = {'__raw_preview__': post_text[:300]}

# Parse SSE body
resp_text = resp.get('content', {}).get('text', '') or ''
events = parse_sse(resp_text)

# Aggregate event statistics
type_counter = collections.Counter()
type_first_sample = {}
field_name_counter = collections.Counter()  # for message_field / message_field_delta / project_field
field_paths_per_type = collections.defaultdict(set)
delta_concatenations = collections.defaultdict(list)  # by (message_id, field_name)

for ev in events:
    if not isinstance(ev, dict):
        continue
    et = ev.get('type', '__no_type__')
    type_counter[et] += 1
    if et not in type_first_sample:
        type_first_sample[et] = sample_payload(ev)
    for k in ev.keys():
        field_paths_per_type[et].add(k)
    # Concatenate deltas to reconstruct emitted content
    if et == 'message_field_delta':
        mid = ev.get('message_id', '?')
        fname = ev.get('field_name', '?')
        delta = ev.get('delta', '')
        delta_concatenations[(mid, fname)].append(delta)
    if 'field_name' in ev:
        field_name_counter[ev['field_name']] += 1

# Reconstruct deltas
reconstructed = {}
for (mid, fname), parts in delta_concatenations.items():
    joined = ''.join(parts)
    reconstructed[f'{mid[:8]}|{fname}'] = {
        'message_id_prefix': mid[:8] + '...',
        'field_name': fname,
        'delta_count': len(parts),
        'joined_length': len(joined),
        'joined_preview': joined if len(joined) <= 800 else joined[:800] + '...<truncated>',
    }

# Detect terminator
terminator = None
last_events = [ev.get('type') for ev in events[-5:] if isinstance(ev, dict)]
for candidate in ('message_end', 'project_end', 'done', 'project_done', 'message_done', 'stream_end'):
    if candidate in (ev.get('type') for ev in events if isinstance(ev, dict)):
        terminator = candidate
        break

extract = {
    '_meta': {
        'request_id': 1031,
        'iter': 13,
        'mode': 'HAR_CAPTURE_observation_only',
        'service': 'genspark',
        'engine_apf_state_dev_side': 'DISABLED (reload_services confirmed)',
        'capture_purpose': 'Ground-truth SSE schema for iter13 envelope design; iter7-12 envelope designs (project-style + OpenAI-compat) REFUTED',
        'prompt_submitted': '안녕하세요. 오늘 날씨가 어떤가요?',
        'observed_user_visible_response': 'Genspark answered naturally — rendered a regional weather picker UI (\"날씨를 확인할 지역\": 현재 위치 근처 / 서울 / 부산 / 인천 / 대구 / 직접 입력) inside a project card titled \"오늘 날씨 문의\"',
        'page_url_after_send': 'https://www.genspark.ai/agents?id=5f6d0a0c-98a9-40e1-855f-5b5933fce36c (project URL)',
        'capture_method': 'windows-mcp UI automation (no CDP) — DevTools Network panel + Export HAR (sanitized) button',
    },
    'streaming_endpoint': {
        'url': req['url'],
        'host': parsed_url.netloc,
        'path': parsed_url.path,
        'method': req['method'],
        'http_version': resp.get('httpVersion', '?'),
        'status': resp['status'],
        'status_text': resp.get('statusText', ''),
        'response_content_type': resp.get('content', {}).get('mimeType', ''),
        'response_body_size_bytes': resp.get('content', {}).get('size', 0),
        'response_compression': resp.get('content', {}).get('compression', None),
        'total_elapsed_ms_observed_in_devtools': 35240,
    },
    'request_headers_sanitized': sanitize_headers(req.get('headers', [])),
    'response_headers_sanitized': sanitize_headers(resp.get('headers', [])),
    'request_body_parsed': req_body_obj,
    'sse_summary': {
        'total_events_parsed': len(events),
        'event_type_counts': dict(type_counter),
        'unique_event_types': sorted(type_counter.keys()),
        'last_5_event_types': last_events,
        'terminator_event_detected': terminator,
        'field_name_counts_top20': dict(field_name_counter.most_common(20)),
    },
    'event_type_schemas': {
        et: {
            'count': type_counter[et],
            'observed_keys': sorted(field_paths_per_type[et]),
            'first_sample': type_first_sample[et],
        }
        for et in sorted(type_counter.keys())
    },
    'reconstructed_delta_streams': reconstructed,
    'iter13_design_hints': {
        'content_path_HYPOTHESIS': 'message_field_delta events carry the assistant payload incrementally; field_name="tool_calls[1].function.arguments" accumulates a JSON string that, once concatenated, is the structured tool-call argument the frontend uses to render the answer UI.',
        'natural_assistant_text_path_HYPOTHESIS': 'For a plain assistant text reply (not tool call), the corresponding delta field_name would likely be "content" or "tool_calls[0].function.arguments" — needs second observation capture with text-only response',
        'discriminator_field': '"type" (string)',
        'event_index_field': '"_event_index" (int, monotonic per stream)',
        'message_correlation_field': '"message_id" (uuid)',
        'project_correlation_field': '"project_id" / "id" (uuid; same value)',
        'completion_signal_CANDIDATES': [t for t in type_counter.keys() if 'end' in t.lower() or 'done' in t.lower() or 'finish' in t.lower()],
        'envelope_format_to_inject_INFERRED': (
            'Emit per-line `data: {json}\\n\\n` blocks. Minimum viable sequence for warning bubble: '
            '(1) {"id":"<proj-uuid>","type":"project_start","_event_index":0}, '
            '(2) {"message_id":"<msg-uuid>","role":"assistant","project_id":"<proj-uuid>","type":"message_start","_event_index":1}, '
            '(3) repeated message_field_delta with field_name="content" carrying chunks of warning text, '
            '(4) terminator (TBD — likely "message_end" + "project_end" but not observed in this benign capture).'
        ),
        'CAVEAT': 'This capture only shows the TOOL-CALL branch (project card UI). A second observation with a benign text-only prompt (e.g. \"1+1=?\") is recommended to confirm content path for plain text replies AND to capture the terminator events.',
    },
}

with open(OUT_PATH, 'w', encoding='utf-8') as f:
    json.dump(extract, f, ensure_ascii=False, indent=2)

print('Wrote', OUT_PATH)
print('Events parsed:', len(events))
print('Type counts:', dict(type_counter))
print('Terminator detected:', terminator)
print('Last 5 event types:', last_events)
