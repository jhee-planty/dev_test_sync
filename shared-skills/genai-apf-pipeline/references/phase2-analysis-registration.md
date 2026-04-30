---
name: apf-add-service
description: Add a new GenAI service to the EtapV3 ai_prompt_filter (APF) module. Use when adding a service (Gemini, Perplexity, Copilot, etc.) to the APF block list — covers HAR analysis, SQL generation, C++ block response generator implementation, and handoff.md update.
argument-hint: "<service_id> (e.g. gemini)"
user-invokable: true
---

# APF Add Service Skill

## When to Use This Skill

- Adding a new GenAI service to the APF block list
- A `genai-har-capture` output directory is available for the target service
- Writing `generate_{service_id}_sse_block_response()` and registering it
- Generating DB SQL for `ai_prompt_services` and `ai_prompt_response_templates`

**Trigger keywords:** apf-add-service, new AI service, APF, block response generator

---

## Purpose

Add a new AI service to the `ai_prompt_filter` module end-to-end:
HAR capture output → SQL → C++ code → file modifications → handoff.md update.

---

## Prerequisites

Before starting, confirm:

1. A HAR capture directory exists at:
   `~/Documents/workspace/Officeguard/EtapV3/genAI_har_files/{service_id}_{stamp}/`
   (produced by the `genai-har-capture` skill)

2. The `AI_prompt` branch is checked out in EtapV3:
   ```bash
   cd ~/Documents/workspace/Officeguard/EtapV3 && git branch --show-current
   # Expected output: AI_prompt
   ```
   If not on `AI_prompt`, run: `git checkout AI_prompt`

---

## Project Reference Paths

```
EtapV3_ROOT = ~/Documents/workspace/Officeguard/EtapV3/

Key files:
  functions/ai_prompt_filter/ai_prompt_filter.h      ← class declaration
  functions/ai_prompt_filter/ai_prompt_filter.cpp    ← implementation
  functions/ai_prompt_filter/sql/                    ← SQL output directory
  handoff.md                                         ← living design document
```

---

## service_id Naming Convention

`service_id` is used as the DB key, C++ function suffix, and directory name. Follow these rules:

- **Lowercase letters, digits, underscores only** — no hyphens, no spaces
- **Prefer the brand name** in lowercase: `gemini`, `perplexity`, `copilot`
- **Use underscore for multi-word names**: `clova_x`, `google_bard`
- **Keep it short** — it appears in function names: `generate_{service_id}_sse_block_response()`

| Brand | service_id |
|-------|------------|
| ChatGPT | `chatgpt` |
| Claude.ai | `claude` |
| Clova-X | `clova_x` |
| Google Gemini | `gemini` |
| Microsoft Copilot | `copilot` |
| Perplexity | `perplexity` |

---

## Step 0 — Communication Method Pre-Classification (2026-04-14 회고 반영)

HAR 분석에 들어가기 전에 서비스의 통신 방식을 먼저 확인한다.
WebSocket/gRPC 기반 서비스는 HTTP 응답 주입이 불가능하므로 조기 분류하여 불필요한 분석 시간을 절약한다.

**확인 방법:**
1. `websocket.json` 파일 존재 여부 확인 (AI 응답이 WS로 전달되는지)
2. HAR에서 `Upgrade: websocket` 또는 gRPC 관련 헤더 검색
3. `sse_streams.json`이 비어있고 `websocket.json`에 AI 응답 데이터가 있으면 → WS 기반 서비스

**판정:**
- WebSocket으로 AI 응답 전달 확인 → 즉시 **NEEDS_ALTERNATIVE** 분류. Step 1-4 분석 스킵.
- gRPC 사용 확인 → 즉시 **NEEDS_ALTERNATIVE** 분류.
- SSE/REST/batchexecute 확인 → Step 1로 진행 (정상 플로우).

→ See `warning-delivery-checklist.md` § 1-5 for WebSocket 판정 기준.

---

## Step 1 — Analyze HAR Capture: Request Endpoints

Read all `*.req.txt` files in `genAI_har_files/{service_id}_{stamp}/raw/`.

For each file, extract:

| Field | How to find |
|-------|-------------|
| **Host** | `=== HEADERS` section → `host:` header |
| **Method** | `Method:` line |
| **URL path** | `URL:` line → path component only |
| **Content-Type** | `content-type:` header |
| **Body structure** | `=== BODY` section |

**Target:** Find POST requests where the body contains the user's prompt text.

**Body field path examples by Content-Type:**

- `application/json` → inspect JSON keys, find the field holding the prompt text
  - ChatGPT: `messages[].content` (array of strings or objects)
  - Claude: `messages[].content[].text`
- `multipart/form-data` → check each part's `Content-Disposition: name=` attribute
  - Clova-X: part `name="form"` → JSON body → `text` field
- `application/x-www-form-urlencoded` → decode and find prompt key

**Prepare API detection:**
If there is a request to an endpoint where the path ends with `/prepare`, `/preflight`, `/check`, or similar, it likely needs a **separate JSON error response** (not SSE). When found:

1. Open the corresponding `*.resp.txt` file for that endpoint.
2. Read the actual error response structure from the `=== BODY` section.
   A real error response (e.g., when the service rejects a request) typically looks like:
   ```json
   {"status":"error","error_code":"...","error":"..."}
   ```
   but **the exact keys differ per service**. Always use the actual observed structure, not the
   ChatGPT-based template in Step 4.
3. Note the key name that holds the human-readable error message — this is where the block
   message text will be injected.
4. Record for Step 4: endpoint path, JSON key structure, HTTP status code used.

---

## Step 2 — Analyze HAR Capture: SSE Response Format

Read the `*.resp.txt` file corresponding to the main conversation endpoint.

Find the `=== BODY` section and extract the raw SSE text:

```python
# How to extract SSE body from .resp.txt
body_section = text.split('=== BODY')[1]   # everything after "=== BODY"
body = body_section.split('\n', 1)[1]       # skip the "(...) ===" header line
```

For each SSE event, record:

| Field | Example (Claude) |
|-------|-----------------|
| `event:` field name | `message_start`, `content_block_delta`, `message_stop` |
| `data:` JSON structure | `{"type":"content_block_delta","delta":{"type":"text_delta","text":"..."}}` |
| Where message text goes | `delta.text` in `content_block_delta` |
| Termination event | `message_stop` |
| Dynamic IDs used | UUID format, prefix pattern (e.g., `chatcompl_` + 24 hex chars) |

**`event:` field presence check:**
Some services (OpenAI-compatible APIs, older endpoints) omit the `event:` line and use
`data:` only. Check whether the raw SSE body has `event:` lines:

```
# Has event: field (named events)          # data-only (no event: line)
event: message_start                        data: {"id":"chatcmpl-...","choices":[...]}
data: {"type":"message_start",...}
                                            data: {"choices":[{"delta":{"content":"Hi"}}]}
event: message_stop
data: {"type":"message_stop"}               data: [DONE]
```

- **Named events** → use `event: {name}\r\ndata: {json}\r\n\r\n` in the generator
- **Data-only** → use `data: {json}\r\n\r\n` only (no `event:` line); termination is `data: [DONE]\r\n\r\n`

---

## Step 3 — Generate SQL

Create or append to `functions/ai_prompt_filter/sql/{service_id}.sql`:

```sql
-- ============================================================
-- {Service Display Name} APF registration
-- Generated: {date}
-- ============================================================

-- Service detection (domain + path matching)
INSERT INTO ai_prompt_services (service_name, display_name, domain_patterns, path_patterns, block_mode, enabled)
VALUES ('{service_id}', '{Service Display Name}',
        '{domain}',
        '{path_pattern}',
        1, 1);

-- Block message text (plain text only — SSE envelope is generated in C++)
INSERT INTO ai_prompt_response_templates (service_name, http_response, enabled, priority)
VALUES ('{service_id}', '⚠️ This request has been blocked by security policy due to sensitive information.', 1, 100);
```

**Notes:**
- `domain_patterns`: exact domain (e.g., `gemini.google.com`) or wildcard (`*.google.com`)
- `path_patterns`: use `*` as wildcard (e.g., `/api/*/generate`, `/chat/completions`)
- `http_response` stores **message text only** — no HTML, no SSE structure
- If a service has multiple conversation endpoints, add one row per endpoint

### ⚠️ INSERT idempotency — table-specific patterns (cycle 45 finding)

The two APF tables have **different unique-key shapes**, so INSERT idempotency patterns differ:

| Table | Unique constraints | Idempotency pattern |
|-------|-------------------|---------------------|
| `ai_prompt_services` | `PRIMARY KEY (id)` + **`UNIQUE KEY uk_service_name (service_name)`** | `INSERT ... ON DUPLICATE KEY UPDATE` **works correctly** — keyed on `service_name` |
| `ai_prompt_response_templates` | `PRIMARY KEY (id)` auto-increment **only** (no composite unique) | `INSERT ... ON DUPLICATE KEY UPDATE` is a **NO-OP** — use DELETE-then-INSERT instead |

**Why the difference matters**: `ai_prompt_response_templates` has NO unique index on `(service_name, response_type)`. Every `INSERT` gets a fresh auto-increment `id`, so the duplicate-key check against `PRIMARY KEY` always fails and the ODKU `UPDATE` clause NEVER executes. The INSERT silently appends a new row every time.

**Historical evidence in live DB** (cycle 45 snapshot):
- 3 identical `(claude, claude, 1118B, MD5 022e27ac...)` rows — all re-run artifacts
- 5 identical `(*, openai_compat_sse, 342B, MD5 79553698...)` rows — chatglm/huggingface/kimi/qianwen/wrtn
- 2 identical `(*, chatgpt_sse, 1247B, MD5 aa64281b...)` rows — chatgpt/chatgpt2
- 7 identical `(*, generic_sse, 239B, MD5 baeb6791...)` rows — character/clova/consensus/copilot/dola/phind/poe

None of these break runtime behavior because cycle 41's `_envelopes` map dedupes by `response_type` and applies `ORDER BY priority DESC` first-row-wins — and the duplicates all have identical content so any winner is correct. BUT if you re-run an INSERT with an **updated** template (e.g., fixing a placeholder bug), the old row keeps winning via priority-tie + InnoDB insertion order, and your fix is **silently ignored**.

**Canonical safe INSERT pattern for `ai_prompt_response_templates`**:

```sql
BEGIN;

-- Idempotency guard: always DELETE the exact (service_name, response_type)
-- tuple before inserting. This is safe because the tuple uniquely identifies
-- the row you are creating — no other rows are touched.
DELETE FROM etap.ai_prompt_response_templates
 WHERE service_name = '{service_id}'
   AND response_type = '{response_type}';

INSERT INTO etap.ai_prompt_response_templates
       (service_name, http_response, response_type, envelope_template, priority, enabled)
VALUES ('{service_id}',
        '⚠️ 민감정보가 포함된 요청은 보안 정책에 의해 차단되었습니다.\n\nThis request has been blocked due to sensitive information detected.',
        '{response_type}', CONCAT(
         'HTTP/1.1 200 OK\r\n',
         -- ...
       ), 50, 1);

COMMIT;
```

**⚠️ `http_response` is NOT a placeholder** (cycle 47 finding). That column IS the block-message text substituted into envelope `{{MESSAGE}}` at block time via `get_response_template(service_name)` → `_templates[service_name] = http_response`. Never write `'BLOCK'`, `0`, `NULL`, or any schema-placeholder string — the user will see that literal value in the chat bubble. If the target `service_name` has a pre-existing row, copy its `http_response` verbatim (via `INSERT ... SELECT t.http_response FROM ... WHERE service_name='{service_id}' LIMIT 1`). If there is no pre-existing row, use the canonical text matching your priority tier:

| priority | canonical `http_response` text |
|---|---|
| 50 | `⚠️ 민감정보가 포함된 요청은 보안 정책에 의해 차단되었습니다.\n\nThis request has been blocked due to sensitive information detected.` (159 bytes) |
| 1 | `⚠️ 민감정보가 포함된 요청은 보안 정책에 의해 차단되었습니다.` (89 bytes, Korean-only) |

See `services/envelope_audit_2026-04-15.md` §10 for the code walkthrough, the two in-draft migration bugs that cycle 47 caught (`BLOCK` in huggingface addendum, `0` in combined migration v0_api row), and the full priority convention.

**DO NOT use** `INSERT ... ON DUPLICATE KEY UPDATE` on `ai_prompt_response_templates` even though it looks idiomatic — the baseline `apf_db_driven_migration.sql:91-111` chatgpt_sse example uses this pattern and it's **semantically dead code**. The apparent idempotency is an illusion; it has been accidentally correct only because re-runs shipped identical content.

**For `ai_prompt_services`** — ODKU on `service_name` is still the right pattern:

```sql
INSERT INTO etap.ai_prompt_services
       (service_name, display_name, domain_patterns, path_patterns, block_mode, enabled)
VALUES ('{service_id}', '{Display Name}', '{domain}', '{path}', 1, 1)
    ON DUPLICATE KEY UPDATE
        display_name    = VALUES(display_name),
        domain_patterns = VALUES(domain_patterns),
        path_patterns   = VALUES(path_patterns);
```

See `services/envelope_audit_2026-04-15.md` §9 for full schema findings + 3 Phase 6 fix examples.

### ⚠️ service_name consistency check (required — established from experience)

After applying SQL, always verify that the DB value exactly matches the C++ `_response_generators` key.
**Typos cannot be fixed with `ON DUPLICATE KEY UPDATE` — requires a direct UPDATE statement.**

```sql
-- Verification query after applying SQL
SELECT service_name, domain_patterns, path_patterns
  FROM etap.ai_prompt_services
 WHERE service_name = '{service_id}';
-- Verify 1 row returned and service_name is exactly correct
-- 0 rows = INSERT not applied or service_name typo
```

C++ registry key: `_response_generators["{service_id}"]` (check register_block_response_generators())

**If a typo is found:**
```sql
-- ON DUPLICATE KEY UPDATE cannot fix PK typos → use direct UPDATE
UPDATE etap.ai_prompt_services
   SET service_name = 'correct_service_id'
 WHERE service_name = 'wrong_service_id';
```

---

## Step 4 — Write C++ Block Response Generator

### 4-1. Implement the function in `ai_prompt_filter.cpp`

Add after the last existing generator function (search for `generate_clova_x_sse_block_response`).

**SSE response function template:**

```cpp
/*
 * {Service Display Name} /{endpoint} block response.
 * Event sequence: {event1} → {event2} → ... → {termination_event}
 * {key observation from HAR analysis}
 */
std::string ai_prompt_filter::generate_{service_id}_sse_block_response(
    const std::string& message)
{
    // Generate dynamic IDs matching the service's format
    const std::string some_id = generate_uuid4();   // adapt format as needed

    std::string body;

    // ① First event (e.g., session/message start)
    body += "event: {event_name}\r\n"
            "data: {json_structure_with_ids}\r\n"
            "\r\n";

    // ② Content event — inject message text here
    body += "event: {content_event_name}\r\n"
            "data: {...,\"text\":\"" + message + "\",...}\r\n"
            "\r\n";

    // ③ Termination event
    body += "event: {termination_event}\r\n"
            "data: {termination_json}\r\n"
            "\r\n";

    char hdr[512];  // 512 bytes to safely accommodate long domains and 6-digit Content-Length
    snprintf(hdr, sizeof(hdr),
        "HTTP/1.1 200 OK\r\n"
        "Content-Type: text/event-stream; charset=utf-8\r\n"
        "Cache-Control: no-cache\r\n"
        "access-control-allow-credentials: true\r\n"
        "access-control-allow-origin: https://{domain}\r\n"
        "Content-Length: %zu\r\n"
        "\r\n",
        body.size());

    return std::string(hdr) + body;
}
```

**If the service has a prepare/preflight API** (JSON error response, not SSE):

> **IMPORTANT:** The JSON structure below is based on ChatGPT's format.
> **Always verify the actual error response** from the prepare endpoint's `*.resp.txt` file
> (Step 1 → Prepare API detection) and adapt the key names accordingly.
> The key holding the human-readable message may be `"error"`, `"message"`, `"detail"`, etc.

```cpp
/*
 * {Service Display Name} /{prepare_endpoint} block response.
 * HTTP 200 + JSON error status
 * JSON structure: based on actual error response observed in *.resp.txt
 * (below is ChatGPT format example — key names differ per service)
 */
std::string ai_prompt_filter::generate_{service_id}_prepare_block_response(
    const std::string& message)
{
    // TODO: Replace with actual JSON structure observed in *.resp.txt
    std::string body =
        "{\"status\":\"error\","
         "\"error_code\":\"content_policy_violation\","
         "\"error\":\"" + message + "\"}";

    char hdr[512];  // 512 bytes to safely accommodate long domains and 6-digit Content-Length
    snprintf(hdr, sizeof(hdr),
        "HTTP/1.1 200 OK\r\n"
        "Content-Type: application/json; charset=utf-8\r\n"
        "access-control-allow-credentials: true\r\n"
        "access-control-allow-origin: https://{domain}\r\n"
        "Content-Length: %zu\r\n"
        "\r\n",
        body.size());

    return std::string(hdr) + body;
}
```

**Utility available:** `generate_uuid4()` — thread-safe UUID v4 generator (no mutex needed).

**HTTP/2:** No extra work needed. `generate_block_response()` automatically calls
`convert_to_http2_response()` when `is_http2 == true`.

### 4-2. Declare in `ai_prompt_filter.h`

Find the private section grouped with other service generators (search for
`generate_clova_x_sse_block_response`) and add:

```cpp
// ========================================
// {Service Display Name} response generators
// ========================================

/**
 * @brief /{endpoint} block response
 * {brief description of SSE format}
 */
static std::string generate_{service_id}_sse_block_response(const std::string& message);

// Only if prepare API exists:
static std::string generate_{service_id}_prepare_block_response(const std::string& message);
```

### 4-3. Register in `register_block_response_generators()`

In `ai_prompt_filter.cpp`, find `register_block_response_generators()` and add:

```cpp
_response_generators["{service_id}"]         = generate_{service_id}_sse_block_response;
_response_generators["{service_id}_prepare"] = generate_{service_id}_prepare_block_response;  // if applicable
```

**DO NOT modify `generate_block_response()`.** It is a registry-based dispatcher
that requires no changes when new services are added.

### 4-4. ⚠️ event 0 init field supplement (pitfall of FINAL-based block responses)

**Background (established from experience):**
Block responses use a strategy of condensing the stream into a single FINAL/COMPLETED event,
skipping intermediate PENDING events. This is intentional — the `text` field shown to the user
exists only in the FINAL event.

**However, if the block response omits a field that the client JS uses for routing/state
initialization on the very first chunk, it will throw an exception during init even when
the FINAL event arrives as the first chunk.**
Symptoms: `STREAM_FAILED_FIRST_CHUNK_ERROR` or `{field} is required on first message`

**Always perform the following analysis and reflect results in the block response:**

```python
# Compare event 0 and FINAL event keys in sse_streams.json
import json
with open("genAI_har_files/{service_id}_{stamp}/sse_streams.json") as f:
    data = json.load(f)
events = data["streams"][0]["events"]
ev0_keys     = set(events[0]["data"].keys())     # first event keys
evfinal_keys = set(events[-2]["data"].keys())    # FINAL/COMPLETED event keys
init_only    = ev0_keys - evfinal_keys           # keys in event 0 but not in FINAL
print("Fields in event 0 only (absent in FINAL):", init_only)
# → Determine which fields are required for client init and add to block response
```

**Decision criteria:**
- Fields involved in routing/URL initialization → must include in block response
- Fields used only for progress state (PENDING/status, partial text accumulation) → can omit

**Known required init fields (accumulated per service):**

| Service | Field | Description | Symptom when missing |
|---------|-------|-------------|----------------------|
| perplexity | `thread_url_slug` | Thread URL routing. event 0 only, but required in block response | `STREAM_FAILED_FIRST_CHUNK_ERROR` |

→ Update this table when adding new services

---

## Step 5 — Update `handoff.md`

File: `~/Documents/workspace/Officeguard/EtapV3/handoff.md`

### 5-1. "Current implementation → completed items" table — add row:
```
| {Service Display Name} block response (SSE) | {SSE format name} ({event1} → ... → {termination}) |
```

### 5-2. "DB configuration" section — add SQL blocks (copy from Step 3 output)

### 5-3. "Key files and code locations" table — add code location row:
```
| `ai_prompt_filter.cpp:{line}` | `generate_{service_id}_sse_block_response()` |
```

### 5-4. "Known limitations and notes" section — add if applicable:
- Add any new service-specific caveats (CORS, ID format quirks, etc.)
- Note: The `response generator if-else chain` limitation has already been resolved by the registry
  pattern. Do not re-add it.

> **Build and runtime testing**: Not executed on this PC.
> After completing the code checklist, build/deploy/verify via SSH CI/CD pipeline.

---

## Step 6 — Code Completion Checklist

Verify all code is written, then hand off to SSH CI/CD.

```
[ ] functions/ai_prompt_filter/sql/{service_id}.sql created
[ ] ai_prompt_filter.h: static method declaration(s) added
[ ] ai_prompt_filter.cpp: generate_{service_id}_sse_block_response() implemented
[ ] ai_prompt_filter.cpp: register_block_response_generators() entry added
[ ] generate_block_response() body NOT modified
[ ] handoff.md: completed items table updated
[ ] handoff.md: DB configuration SQL blocks added
[ ] handoff.md: key files and code locations table updated
```

> **Build and runtime testing**: Not executed on this PC.
> After passing this checklist, build/deploy/verify via SSH CI/CD pipeline.

---

## Common Pitfalls

| Issue | Cause | Fix |
|-------|-------|-----|
| Blocked but no UI message | DB template empty | Check after `etapcomm reload_services` |
| SSE event structure mismatch | Typo in event/field names from HAR | Cross-check against raw `.resp.txt` original |
| HTTP/2 block response corrupted | Content-Length calculation error | Ensure `body.size()` is called after body is fully built |
| `snprintf` buffer truncation | `char hdr[256]` too small for domain length + 6-digit Content-Length | Declare header buffer as `char hdr[512]` |
| `generate_block_response()` not called | Service not detected | No `AI service detected: {service_id}` in etap log → check DB `ai_prompt_services` |
| Multipart prompt not detected | Boundary parsing failure | Check log for `Multipart decoded:` output |
| JSON message escaping error | Message contains quotes | Restrict DB `http_response` value to plain text without special characters |
| Block message not rendered / `STREAM_FAILED_FIRST_CHUNK_ERROR` | Block response (FINAL-based) missing client init field (event 0 only field) | Run event 0 analysis in Step 4-4 and add the field to block response |
| `service_name` DB typo causes no blocking | Typo on INSERT. Cannot fix with `ON DUPLICATE KEY UPDATE` | Verify with Step 3 service_name check query, fix with UPDATE statement |
| APF log shows block success but chat message not displayed (delta-driven services) | Block response omits `message_field_delta` event. Some services (e.g. Genspark) create the chat bubble only when the first `message_field_delta` is received; skipping straight to `message_field`(field_value) leaves the UI blank | Add `message_field_delta` event (with full message as `delta`) between `message_start` and `message_field`. Check HAR to confirm service uses delta-driven rendering. <!-- added 2026-03-06 --> |
| EtapV3 log: `No generator registered for '{name}'` | DB `service_name`과 C++ `_response_generators` 키 불일치 (typo 등) | `SELECT service_name FROM etap.ai_prompt_services WHERE domain_patterns LIKE '%{domain}%'`로 DB 값 확인 후 UPDATE |
| SSE `\r\n\r\n` separator causes `ERR_CONNECTION_CLOSED` | 서비스 클라이언트가 naive `\n`-split SSE parser 사용. CRLF separator로 인해 `JSON.parse("{...}\r")` 실패 | 모든 SSE 이벤트 separator를 `\n\n` (LF only)로 통일. 서비스별 확인 → SKILL_debug.md |
| `TypeError: network error` after 200 OK | `convert_to_http2_response`에서 `END_STREAM=1` 전송 → Chrome이 ReadableStream 즉시 닫음 → SSE 루프 실패 | 해당 서비스에 `end_stream=false` 적용. 서비스별 확인 → SKILL_debug.md |

---

## Reference: Existing Generator Patterns

| Service | Function | SSE Format | Dynamic IDs |
|---------|----------|------------|-------------|
| ChatGPT | `generate_chatgpt_sse_block_response()` | `event: delta` / `data: [DONE]` | UUID v4 (conv_id, msg_id) |
| ChatGPT prepare | `generate_chatgpt_prepare_block_response()` | JSON error (no SSE) | none |
| Claude | `generate_claude_sse_block_response()` | `message_start` → `content_block_delta` → `message_stop` | `chatcompl_` + hex24, req_, UUID |
| Clova-X | `generate_clova_x_sse_block_response()` | `info` → `status` → `token` → `result` | UUID v4 (conv_id, bot_turn_id) |
| Perplexity | `generate_perplexity_sse_block_response()` | `event: message` / `event: end_of_stream` | UUID v4 (backend_uuid, context_uuid, uuid, frontend_context_uuid, frontend_uuid) |
| Genspark | `generate_genspark_sse_block_response()` | data-only: `project_start` → `message_start` → `message_field` → `message_result` → `project_field(FINISHED)` | UUID v4 (project_id, message_id) |
<!-- added 2026-03-06 -->

All generators follow the same signature:
```cpp
static std::string generate_{service_id}_sse_block_response(const std::string& message);
```
Return value: complete HTTP/1.1 response string including headers and body (with correct `Content-Length`).

---

## Related Skills

- **`genai-apf-pipeline`**: Full workflow orchestrator (capture → registration end-to-end).
- **`genai-har-capture`**: Phase 1 — Playwright capture of GenAI service network traffic.
  Run before this skill. Uses `genAI_har_files/{service_id}_{stamp}/raw/` as input.
- **`genai-har-capture/SKILL_debug.md`**: Debugging capture failures, empty results, SSE parse errors.

---

## Adding Experience to This Skill

> **Principle**: Never delete existing entries. Always append.

| Situation | Location |
|-----------|----------|
| New service registration complete | Append row to Reference: Existing Generator Patterns table |
| New C++ pitfall found | Append row to Common Pitfalls table |
| New event 0 init-only field discovered | Append row to Step 4-4 Known Init Fields table |
| Service-specific capture issue | → `genai-har-capture/SKILL_debug.md` Known Service Notes |

---

## Phase 2 Decision Checklist (31차 normalized)

> 출처: 31차 discussion-review (`cowork-micro-skills/discussions/2026-04-30_apf-pipeline-workflow-normalization.md`) Round 2 PD.

| ID | Decision Point | Criteria | Source of Truth |
|----|---------------|----------|-----------------|
| **D2.1** | SQL draft naming convention | `apf_db_driven_{service}_{timestamp}.sql` — canonical naming | `apf-cli-commands.md` |
| **D2.2** | Generator naming canonical | C++ generator function 이름 = service id 와 1:1 (synonym 금지, e.g., `chatgpt_block_response_generator`) | apf-warning-impl §generator-name-discipline |
| **D2.3** | reload command 구분 | envelope_template DB change → `etapcomm ai_prompt_filter.reload_templates`. Service registration change → `reload_services`. 혼용 금지 | `feedback_etapcomm_reload_distinction` (MEMORY note), apf-cli-commands.md |

**FAIL handling**:
- D2.1 violation → SQL re-name before commit
- D2.2 synonym detected → INTENTS append (lessons.md §generator-name-discipline 강화)
- D2.3 wrong reload → reload-correct command 다시 호출 + result.notes 에 기록

**Cross-references**: SKILL.md §Workflow Pattern P1 / failure-class PROTOCOL_MISMATCH (P3 default = debug_envelope:schema_revise).
