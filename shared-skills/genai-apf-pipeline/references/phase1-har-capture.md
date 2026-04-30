---
name: genai-har-capture
description: >
  Use this skill for capturing network traffic from GenAI services (ChatGPT, Claude, Clova-X, Perplexity, etc.)
  via Playwright automation — collecting both raw traffic and analyzed data.
  Apply this skill when:
  - Recording/capturing HAR files + raw request/response data from GenAI services
  - Browser automation for AI chatbots (ChatGPT / Claude / Clova-X / Genspark etc.)
  - Capturing and parsing SSE streaming responses from AI services
  - Capturing WebSocket messages
  - Analyzing AI service API endpoints (prompt filter, security audit)
  - Collecting traffic data for the ai_prompt_filter module
  - Bot detection bypass using Playwright + Chrome profile method
  Trigger keywords: GenAI, HAR, Playwright, bot detection, SSE, WebSocket, capture.
  Debug/Troubleshooting → see SKILL_debug.md
  Full pipeline (capture + EtapV3) → see genai-apf-pipeline/SKILL.md
---

# GenAI HAR Capture Skill

## Design Principle

This skill is built around a **2-layer storage architecture**.

```
┌─────────────────────────────────────────────────────────┐
│  Layer 1 — Raw (original, never modified)               │
│  raw/{seq}_{method}_{url}.req.txt                        │
│  raw/{seq}_{method}_{url}.resp.txt                       │
│  raw/ws_{seq}.jsonl                                      │
├─────────────────────────────────────────────────────────┤
│  Layer 2 — Analyzed (derived from Layer 1, regenerable) │
│  traffic.json   sse_streams.json   websocket.json        │
└─────────────────────────────────────────────────────────┘
```

**Why this structure:**
Parsing and transformation always cause information loss — body truncation, header filtering, encoding substitution, parser bugs.
By preserving the raw originals untouched, you can re-analyze from source at any time, even if the parser has bugs.
Layer 2 is only meaningful when Layer 1 is complete.

---

## Output Directory Structure

```
har-outputs/{service_id}/{YYYYMMDD_HHMMSS}/
│
├── raw/                         ← Layer 1: originals (no modification)
│   ├── 001_POST_conversation.req.txt   # full headers + full body
│   ├── 001_POST_conversation.resp.txt  # full headers + full body/SSE
│   ├── 002_POST_messages.req.txt
│   ├── 002_POST_messages.resp.txt
│   └── ws_001.jsonl                    # WebSocket frames (JSONL)
│
├── capture.har                  ← Playwright HAR (header ref; SSE may be absent)
├── traffic.json                 ← Layer 2: parsed request+response pairs
├── sse_streams.json             ← Layer 2: parsed SSE events
├── websocket.json               ← Layer 2: parsed WebSocket messages
├── screenshot_before.png        ← page state before prompt send
├── screenshot_after_login.png   ← after manual login (Category A, login required)
├── screenshot_after.png         ← page state after SSE completes
├── screenshot_selector_fail.png ← saved when all selectors fail (optional)
├── screenshot_error.png         ← saved on exception (optional)
└── metadata.json
```

**Script paths (absolute):**
```
~/Documents/workspace/claude_work/projects/officeguard-etapv3/scripts/capture/
├── capture_v2.py      ← main execution script
├── service_config.py  ← SERVICES configuration list (79 services)
└── sessions/          ← session cookie and signature files
```

**실행 예시:**
```bash
cd ~/Documents/workspace/claude_work/projects/officeguard-etapv3/scripts/capture
python3 capture_v2.py --list                           # 서비스 목록 확인
python3 capture_v2.py --id claude --copy-to-etap       # Claude AI 캡처 + EtapV3 복사
```

---

## Session Management (periodic re-capture support)

Prevents redundant logins and unnecessary EtapV3 overwrites when
re-running captures weekly or monthly. Two persistence mechanisms:

### Stored files

```
capture/sessions/
├── {service_id}_session.json    # per-service cookies (session reuse)
└── {service_id}_signature.json  # API signature (change detection)
```

### Flow summary

```
First run:
  Open browser → detect login → wait for manual login → capture
  → save cookies (_session.json) + save signature (_signature.json)
  → copy to EtapV3 (always, first time)

Re-run (cookie valid):
  Inject saved cookies → open browser → confirm login → capture
  → refresh cookies + generate new signature
  → compare with previous signature → skip EtapV3 if unchanged, push if changed

Re-run (cookie expired):
  Attempt cookie injection → login page detected after navigation
  → auto-prompt for manual login → capture
  → refresh cookies + compare signature
```

### CLI options

```bash
# Default: reuse session, copy to EtapV3 only if changed
python3 capture_v2.py --id clova_x --copy-to-etap

# Force copy even if no change detected
python3 capture_v2.py --id chatgpt --copy-to-etap --force-push

# Ignore saved session and re-login (session file is regenerated)
python3 capture_v2.py --id clova_x --force-login --copy-to-etap

# List all configured services
python3 capture_v2.py --list
```

---

## Pre-Capture Checklist

Before running `capture()`, verify these conditions.
Skipping this causes empty or incomplete captures that are easy to miss until the EtapV3 copy step.

### 1. Chrome profile has a valid login session

For **Category A** services (login required), the Chrome Default profile must already
contain a live session cookie for the target service. The temp-copy approach preserves
all cookies, but if the session was never established, the service will redirect to its
login page and no API traffic will be captured.

```bash
# Quick check: open the service URL in Chrome manually and confirm you are logged in
# If not logged in → log in manually, then close all Chrome windows, then run capture
```

### 2. Identify whether the service needs a pre-login step

| Condition | Action |
|-----------|--------|
| Already logged in via Chrome Default profile | Proceed with `capture()` directly |
| Not logged in, but can log in via Chrome profile | Run `--force-login` flag |
| Enterprise SSO or special auth required | Manual session setup; category C |

---

## Layer 1: Raw File Storage Format

### Request format (`*.req.txt`)

All headers and the full body are stored without truncation. Binary bodies are base64-encoded.

```
=== REQUEST ===
Seq: 1
Method: POST
URL: https://chatgpt.com/backend-api/conversation
Timestamp: 2026-02-27T10:53:57.123456

=== HEADERS (all) ===
content-type: application/json
authorization: Bearer sk-proj-...
[all headers, no omissions]

=== BODY (application/json, 2847 bytes) ===
{"model":"gpt-4o","messages":[{"role":"user","content":"Hello, how are you?"}],"stream":true}
```

Binary/multipart case:
```
=== BODY (multipart/form-data, binary, 15420 bytes, base64-encoded) ===
LS0tLS0tV2ViS2l0Rm9ybUJvdW5kYXJ5...
```

### Response format (`*.resp.txt`)

SSE streams are stored as-is, without parsing.

```
=== RESPONSE ===
Status: 200
Timestamp: 2026-02-27T10:53:58.456789
Body-Size: 48210 bytes

=== HEADERS (all) ===
content-type: text/event-stream
cache-control: no-cache
[all headers, no omissions]

=== BODY (text/event-stream, 48210 bytes) ===
data: {"id":"chatcmpl-AbC123","choices":[{"delta":{"role":"assistant","content":""},"finish_reason":null}]}

data: {"choices":[{"delta":{"content":"Hello"}}]}

data: [DONE]
```

### WebSocket format (`ws_*.jsonl`)

One line = one frame, JSON Lines format.

```jsonl
{"seq":1,"direction":"sent","url":"wss://chatgpt.com/...","ts":"2026-02-27T10:53:57.001","payload":"{...}","encoding":"utf8"}
{"seq":2,"direction":"received","url":"wss://chatgpt.com/...","ts":"2026-02-27T10:53:58.123","payload":"AQIDBA==","encoding":"base64"}
```

---

## Capture Flow Overview

```
1. Create out_dir / raw_dir
2. launch_with_chrome_profile() → copy Chrome profile to temp dir + start HAR recording
3. page.goto(service.url) + screenshot_before.png
4. [--force-login] wait for manual login
5. Register request / response / websocket interceptors
6. send_prompt() → type prompt + press Enter
7. wait_for_timeout(15s) → wait for SSE stream to complete
8. screenshot_after.png
9. asyncio.gather(resp_tasks) → wait for all response bodies
10. ctx.close() → save HAR file
11. Build Layer 2 files (traffic.json, sse_streams.json)
12. Save metadata.json
13. [--copy-to-etap] quality check then copy to EtapV3
```

**⚠️ Critical:** `resp_tasks` gather must complete before `ctx.close()`.
Otherwise `raw/*.resp.txt` files will be saved empty.

---

## AI Input Field — send_prompt()

**`use_keyboard_type` field in service config:**

| Value | Target framework | Reason |
|-------|-----------------|--------|
| `False` (default) | React/Vue contenteditable, standard textarea | JS innerText injection + dispatch input/change events |
| `True` | Lexical / ProseMirror / Slate | These editors maintain a virtual state tree. Direct innerText mutation bypasses the tree → Enter key does not trigger form submit |

→ 서비스별 확인 내역은 `SKILL_debug.md` Known Service Notes 참조

---

## EtapV3 Handoff

Runs automatically with `--copy-to-etap` flag.

### Quality check criteria

| Field | Pass condition | Action on failure |
|-------|---------------|-------------------|
| `total_requests` | > 0 | Re-run capture (check login state, screenshot_before.png) |
| `sse_streams` | > 0 | Check if service uses WebSocket or plain JSON instead of SSE |

### EtapV3 copy destination

```
Source:      har-outputs/{service_id}/{stamp}/
Destination: ~/Documents/workspace/Officeguard/EtapV3/genAI_har_files/{service_id}_{stamp}/
```

---

## Service Configuration

Full service list: `capture/service_config.py`

**Required fields for a new service:**

```python
{
    "id":             "service_id",           # DB key + directory name. lowercase + underscore
    "name":           "Service Display Name",
    "url":            "https://example.com",
    "category":       "A",                    # A=login required, B=no login, C=skip
    "requires_login": True,
    "login_domains":  ["example.com"],        # cookie filter domains
    "login_patterns": ["/login", "/auth"],    # URL patterns for login page detection
    "input_selector": "textarea, div[contenteditable='true']",
    "prompt":         "Hello, how are you?",
    "use_keyboard_type": False,               # True if Lexical/ProseMirror/Slate
    "notes":          "SSE or WebSocket? multipart or JSON body?",
}
```

**⚠️ Missing `login_domains` → session cookies cannot be saved** → manual login required on every run

---

## Service Categories

| Category | Description | Login Method |
|----------|-------------|--------------|
| **A** | Login required (ChatGPT, Claude, Clova-X, Genspark, etc.) | Chrome profile session reuse. Use `--force-login` if session missing. |
| **B** | No login needed (Perplexity, YouChat, etc.) | Chrome profile or direct access |
| **C** | IDE/special env (GitHub Copilot, Cursor, etc.) | Skip — web HAR not feasible |
| **D** | Region-restricted (Chinese services) | VPN required |
| **E** | API-only | Separate API client required |

---

## Dependencies

```bash
pip install playwright
playwright install chromium
```

---

## Debug & Troubleshooting

→ **`genai-har-capture/SKILL_debug.md`**

---

## Adding Experience to This Skill

> **Principle**: Never delete existing entries. Always append only.

| Situation | Where to add |
|-----------|-------------|
| New `use_keyboard_type` editor type discovered | send_prompt() section above |
| New service category or session management pattern | Session Management section |
| New error/symptom during capture | → `SKILL_debug.md` Troubleshooting |
| Service-specific behavior confirmed | → `SKILL_debug.md` Known Service Notes |

---

## Phase 1 Decision Checklist (31차 normalized)

> 출처: 31차 discussion-review (`cowork-micro-skills/discussions/2026-04-30_apf-pipeline-workflow-normalization.md`) Round 2 PD.

| ID | Decision Point | Criteria | Source of Truth |
|----|---------------|----------|-----------------|
| **D1.1** | HAR scope 결정 | single-prompt vs multi-thread vs login flow — service known auth mode 기반 | `service-known-issues.md`, 사용자 directive |
| **D1.2** | HAR validity check | status 200 + body non-empty + endpoint matches expected (envelope structure observable) | HAR file |
| **D1.3** | Phase 2 진입 gate | HAR provides envelope structure (not empty wrapper / login redirect) | HAR analysis result |

**FAIL handling**:
- D1.1 ambiguous → service-known-issues.md 등록 + Phase 0 research-gathering sub-agent dispatch
- D1.2 fail (status non-200, empty body) → re-emit har-capture request with refined scope
- D1.3 fail (empty wrapper) → user HAR 필요, `defer:user_har` next_action

**Cross-references**: P1 macro-cycle (SKILL.md §Service Iteration Workflow), P3 SERVICE_CHANGED → debug_envelope:har_capture default.
