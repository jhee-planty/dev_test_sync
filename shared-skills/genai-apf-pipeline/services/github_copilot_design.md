# GitHub Copilot — Warning Design (Phase 5)

**Service**: github_copilot (`api.individual.githubcopilot.com/github/chat/`)
**Source**: `services/github_copilot_frontend.md` (Phase 4 from #453, 2026-04-15 18:25 KST)
**Status**: Phase 5 designed — awaiting DB access window for Phase 6 application
**Supersedes**: prior design v1.0 dated 2026-04-02 which (incorrectly) assumed REST JSON / non-streaming. The #453 frontend-inspect proves Copilot uses **SSE (text/event-stream)** with HTTP 200, NOT 403.

---

## 1. Strategy Selection

**Selected: Option A — SSE Stream Injection** (HTTP 200 + `text/event-stream` body)

### Rationale (from Phase 4)

- Response Content-Type: **`text/event-stream`** (confirmed via test PC fetch override + Network tab Headers panel)
- Schema is the SIMPLEST observed across all Phase 4 captures:
  - `data: {"type":"content","body":"<text>"}\n\n` — content delta (cumulative)
  - `data: {"type":"complete","id":"<uuid>","parentMessageID":"<uuid>","model":"","turnId":"","createdAt":"<iso>","references":[],"role":"assistant","intent":"conversation","copilotAnnotations":{"CodeVulnerability":[],"PublicCodeReference":[]}}\n\n` — finalize
- A single `content` event followed by a `complete` event is sufficient (Copilot does not enforce many small chunks for short responses)
- Existing `copilot_403` envelope (HTTP 403 + JSON `{message,documentation_url,status}`) does NOT trigger any user-visible error UI for our warning text — Copilot's React app renders a static-i18n primer-react Banner ("I'm sorry but there was an error. Please try again.") regardless of body contents (Phase 4 §5)
- All other options (B/C/D/E) blocked or only marginally viable per Phase 4 §7

### Cross-Service Comparison

| Service | Strategy | Phase | Status |
|---------|----------|-------|--------|
| **github_copilot** (this) | **Option A SSE injection** | Phase 5 designed | **Awaiting DB** |
| deepseek (#451) | Option A SSE injection (JSON-Patch w/ path inheritance) | Phase 5 designed | Awaiting DB |
| v0 (#447, #448) | f+h pair (Option F + H) | Phase 5 designed | Awaiting DB |
| gemini3 (#452) | Strategy D (wrb.fr envelope) | Phase 5 schema_debug_required | needs raw response capture |

**Pipeline impact**: github_copilot is the THIRD service in the f5 backlog awaiting the same DB access window at 218.232.120.58. When the window opens, deepseek + v0 + github_copilot can all be applied in a single transaction.

---

## 2. Envelope Specification

### Wire format (canonical)

```
HTTP/1.1 200 OK
Content-Type: text/event-stream
Cache-Control: no-cache, no-transform
Connection: keep-alive
Access-Control-Allow-Origin: https://github.com
Access-Control-Allow-Credentials: true
Access-Control-Expose-Headers: x-github-request-id
Content-Length: {{BODY_INNER_LENGTH}}

data: {"type":"content","body":"{{MESSAGE}}"}

data: {"type":"complete","id":"{{UUID:msg}}","parentMessageID":"{{UUID:parent}}","model":"","turnId":"","createdAt":"{{TIMESTAMP_ISO}}","references":[],"role":"assistant","intent":"conversation","copilotAnnotations":{"CodeVulnerability":[],"PublicCodeReference":[]}}

```

### Critical CORS notice

`api.individual.githubcopilot.com` is a **separate cross-origin host** from `github.com`. The browser enforces CORS on every response from this host. APF MUST emit the following response headers, otherwise the browser rejects the response BEFORE the React app sees it:

- `Access-Control-Allow-Origin: https://github.com`
- `Access-Control-Allow-Credentials: true`
- `Access-Control-Expose-Headers: x-github-request-id` (observed in real responses)

**Cycle 30+31 investigation (2026-04-15):** Read `ai_prompt_filter.cpp` lines 1107–1137 (`json_escape` / `json_escape2`), 1249–1328 (`render_envelope_template`), 1602–1677 (`generate_block_response`), 300–380 (`validate_template` CLI), and `functions/ai_prompt_filter/sql/apf_db_driven_migration.sql` lines 138–153 (existing copilot_403 template). Findings:

1. `render_envelope_template()` is a **pure template renderer** — performs ONLY placeholder substitution (`{{MESSAGE}}`, `{{MESSAGE_RAW}}`, `{{MESSAGE}}`, `{{UUID:name}}`, `{{TIMESTAMP}}`, `{{BODY_INNER_LENGTH}}`) + Content-Length recalculation via `recalculate_content_length()`
2. `generate_block_response()` loads `envelope_template` from DB via `_config_loader->get_envelope_template(lookup_key)`, passes it verbatim through `render_envelope_template()`, then optionally converts to HTTP/2 frames via `convert_to_http2_response()`
3. **APF synthesizes the entire response from scratch.** The envelope_template row IS the wire response (modulo placeholders). There is no "preserve upstream X-header" code — the DB row is ground truth, including CORS headers.
4. **CORS not the problem**: Cycle 31 read of `apf_db_driven_migration.sql` lines 138–153 proves the existing `copilot_403` template **already includes** `access-control-allow-credentials: true` + `access-control-allow-origin: https://github.com`. The old envelope is CORS-correct. My earlier cycle 30 "CORS as root cause" hypothesis was **WRONG**.
5. **Real root cause of old copilot_403 failure**: GitHub Copilot's React app treats any non-200 response as an error and renders the static-i18n primer-react Banner ("I'm sorry but there was an error. Please try again.") **regardless of response body contents** — this was already confirmed by Phase 4 §5 via the empty-500 fetch override test. The old copilot_403 body (JSON with `message`/`documentation_url`/`status`) is fetched successfully by the browser but never read by the error handler. **The fix is to return HTTP 200 + `text/event-stream`**, which enters the success code path and feeds events into the chat bubble. Status code, not CORS, was the blocker.

**Implication for this design:** The Phase 5 envelope template (§2 wire format) remains **structurally correct** — CORS headers are embedded and will emit verbatim, matching the pattern used by `chatgpt_sse`, `claude`, `grok_ndjson`, `m365_copilot_sse`, and the existing `copilot_403`. **No C++ code change is required for Phase 6.** The HTTP/1.1 status line change from `403 Forbidden` to `200 OK` is the critical piece of the fix.

### Placeholder correction (cycle 31)

Reviewing the placeholder semantics against `json_escape2 = json_escape(json_escape(...))`:

- `{{MESSAGE}}` — single json_escape: `"` → `\"`, `\` → `\\`, `\n` → `\n`, `\r` → `\r`, `\t` → `\t`. This is the correct escape for embedding user text into a **single level** of JSON string.
- `{{MESSAGE}}` — double json_escape. Only correct when the text is embedded in a JSON string that is itself embedded in another JSON string (e.g. a JSON string-of-JSON payload).
- `{{MESSAGE_RAW}}` — no escape. Used when the upstream template provides text that's already JSON-escaped.

The github_copilot SSE envelope embeds the warning into `data: {"type":"content","body":"<text>"}` — a **single** level of JSON nesting. Therefore **`{{MESSAGE}}` is correct, not `{{MESSAGE}}`**. The §2 wire format and §4 migration SQL both use `{{MESSAGE}}` — this is a bug. Correction applied below.

Comparable templates confirm the pattern:
- `claude` → `"text":"{{MESSAGE}}"` (single escape for SSE JSON body) ✅
- `copilot_403` → `"message":"{{MESSAGE}}"` (single escape for 403 JSON body) ✅
- `chatgpt_sse` → `"{{MESSAGE_RAW}}"` (explicit raw, not double escape) ✅

No existing working envelope uses `ESCAPE2` in an SSE-with-JSON-body pattern.

### Phase 6 pre-check: `validate_template` CLI

The running etap binary exposes an `ai_prompt_filter.validate_template <response_type>` command (confirmed in `ai_prompt_filter.cpp:319–384`). It:

1. Loads envelope from DB via `get_envelope_template(response_type)`
2. Renders with `"__VALIDATION_TEST__"` as the message
3. Validates HTTP status line (`HTTP/`), header-body separator (`\r\n\r\n`), and Content-Length consistency
4. Returns a `[VALID]`/`[INVALID]` summary + first 2048 bytes of rendered output

**Phase 6 pre-check procedure:**

```bash
# After INSERT but BEFORE the ai_prompt_services UPDATE, validate the new template:
ssh -p 12222 solution@218.232.120.58 "etapcomm ai_prompt_filter.validate_template copilot_sse"
# Expected output: [VALID] response_type='copilot_sse' template_size=~700 rendered_size=~720
# The rendered output should contain both 'data: {"type":"content"...' and 'data: {"type":"complete"...'
```

If validation fails (INVALID), rollback the INSERT before switching `ai_prompt_services.response_type`. This prevents a botched template from going live. **This is a significant Phase 6 de-risk** — we can verify the rendered wire bytes without triggering a real block.

### Placeholder semantics

| Placeholder | Source | Notes |
|-------------|--------|-------|
| `{{MESSAGE}}` | DB-configured warning text, single json_escape | Backslash-escape `"`, `\`, `\n`, `\r`, `\t` per JSON spec. CORRECTED cycle 31 from earlier `{{ESCAPE2:MESSAGE}}` typo — ESCAPE2 is `json_escape(json_escape(x))` which would double-escape the text visible to the user. |
| `{{BODY_INNER_LENGTH}}` | computed body byte length excluding headers | Required for Content-Length |
| `{{UUID:msg}}` | per-request random UUID | Used as `complete.id` |
| `{{UUID:parent}}` | per-request random UUID OR reflected from request body's `responseMessageID` field | Reflecting maintains React threading state — preferred but requires request body parse |
| `{{TIMESTAMP_ISO}}` | now in ISO8601 millisecond precision | `2026-04-15T09:16:31.000Z` style; nanosecond precision (as observed) is not required |

### Body sizing

Estimated raw template bytes (without warning text):

```
Headers:                                    ~280 B
"data: {\"type\":\"content\",\"body\":\"\"}\n\n"  ~36 B (excluding warning text)
"data: {\"type\":\"complete\",...}\n\n"          ~270 B (with empty model/turnId, real UUIDs, real timestamp)
```

Total skeleton ≈ **~590 B** (without warning text) + warning text length. With a typical Korean warning (`⚠️ 보안 정책...`) of ~120 B (UTF-8), final body ≈ **~710 B**.

**Critical: this exceeds the 500 B `h2_end_stream=2` ceiling** that constrains chatgpt and others. github_copilot's current DB row uses:

```
service_name    h2_mode  h2_end_stream  h2_goaway
github_copilot  2        1              0
```

`h2_end_stream=1` means the envelope is sent as an HTTP/2 DATA frame with END_STREAM set — there is NO 500 B ceiling here (that ceiling applies to `h2_end_stream=2` keep-alive class). So **710 B is fine** for github_copilot. No body trimming required.

If Phase 6 needs to increase the ceiling further, leave `h2_end_stream=1` as-is.

---

## 3. Warning Text Drafts

### Default (Korean, ~120 B UTF-8)

```
⚠️ 보안 정책에 따라 해당 요청이 차단되었습니다. 자세한 사항은 IT 관리자에게 문의하세요.
```

### Markdown-formatted (richer; Copilot renders body as markdown)

```markdown
**⚠️ 보안 정책 차단**

해당 요청은 사내 보안 정책에 의해 차단되었습니다.

자세한 사항은 IT 관리자에게 문의하세요.
```

Markdown rendering is supported by Copilot's chat bubble (verified in Phase 4 §4). The bold + paragraph version provides slightly better visual emphasis but adds ~30 B. Both fit comfortably under any practical envelope limit for `h2_end_stream=1`.

---

## 4. Phase 6 Migration SQL

### Pre-check (run first to capture baseline)

```sql
-- Capture current state for rollback
SELECT id, table_name, revision_cnt, sync_flag
  FROM etap.etap_APF_sync_info
  WHERE table_name IN ('ai_prompt_services','ai_prompt_response_templates')
  ORDER BY table_name;

SELECT id, service_name, response_type, h2_mode, h2_end_stream, h2_goaway, h2_hold_request, update_date
  FROM etap.ai_prompt_services
  WHERE service_name = 'github_copilot';

SELECT id, service_name, response_type, priority, enabled, LENGTH(envelope_template) AS env_len, update_date
  FROM etap.ai_prompt_response_templates
  WHERE service_name = 'github_copilot' OR response_type = 'copilot_403'
  ORDER BY id;
```

**Expected baseline (from cycle 21 L2 intel + cycle 25 addendum)**:
- `etap_APF_sync_info.ai_prompt_services.revision_cnt` = 103
- `etap_APF_sync_info.ai_prompt_response_templates.revision_cnt` = 4
- `ai_prompt_services.github_copilot.response_type` = `copilot_403`, `h2_mode=2`, `h2_end_stream=1`, `h2_goaway=0`
- `ai_prompt_response_templates.github_copilot.envelope_template` length ≈ 346 B (current copilot_403 — HTTP 403 + JSON body)

### Migration (apply in single transaction)

```sql
BEGIN;

-- 1. Insert new copilot_sse envelope template row
-- Cycle 31 note: mirrors the chatgpt_sse pattern in apf_db_driven_migration.sql
--   lines 91–111 (INSERT ... SELECT ... ON DUPLICATE KEY UPDATE). The actual
--   unique key on ai_prompt_response_templates should be (service_name, response_type)
--   based on chatgpt coexisting with chatgpt_sse + chatgpt_prepare rows. Verify at
--   Phase 6 dry-run via SHOW CREATE TABLE etap.ai_prompt_response_templates.
--   If the key is service_name only, convert to UPDATE instead (and the existing
--   copilot_403 row becomes the copilot_sse row — the old envelope is lost).
INSERT INTO etap.ai_prompt_response_templates
  (service_name, response_type, http_response, envelope_template, priority, enabled, description)
VALUES (
  'github_copilot',
  'copilot_sse',
  '',  -- legacy http_response field unused for SSE class
  CONCAT(
    'HTTP/1.1 200 OK\r\n',
    'Content-Type: text/event-stream\r\n',
    'Cache-Control: no-cache, no-transform\r\n',
    'Connection: keep-alive\r\n',
    'Access-Control-Allow-Origin: https://github.com\r\n',
    'Access-Control-Allow-Credentials: true\r\n',
    'Access-Control-Expose-Headers: x-github-request-id\r\n',
    'Content-Length: {{BODY_INNER_LENGTH}}\r\n',
    '\r\n',
    'data: {"type":"content","body":"{{MESSAGE}}"}\n\n',
    'data: {"type":"complete","id":"{{UUID:msg}}","parentMessageID":"{{UUID:parent}}","model":"","turnId":"","createdAt":"{{TIMESTAMP_ISO}}","references":[],"role":"assistant","intent":"conversation","copilotAnnotations":{"CodeVulnerability":[],"PublicCodeReference":[]}}\n\n'
  ),
  100,
  1,
  'GitHub Copilot SSE warning envelope (#453 Phase 5 — replaces copilot_403)'
);

-- 2. Switch github_copilot service to use the new response_type
UPDATE etap.ai_prompt_services
   SET response_type = 'copilot_sse',
       h2_mode = 2,
       h2_end_stream = 1,
       h2_goaway = 0,
       h2_hold_request = h2_hold_request   -- preserve current value
 WHERE service_name = 'github_copilot';

-- 3. Bump reload signals so etap process re-reads both tables
UPDATE etap.etap_APF_sync_info
   SET revision_cnt = revision_cnt + 1
 WHERE table_name = 'ai_prompt_services';

UPDATE etap.etap_APF_sync_info
   SET revision_cnt = revision_cnt + 1
 WHERE table_name = 'ai_prompt_response_templates';

COMMIT;
```

### Post-check (verify reload picked up)

```sql
SELECT id, table_name, revision_cnt FROM etap.etap_APF_sync_info ORDER BY id;
-- Expect ai_prompt_services 103→104, ai_prompt_response_templates 4→5

SELECT service_name, response_type FROM etap.ai_prompt_services WHERE service_name = 'github_copilot';
-- Expect copilot_sse

SELECT response_type, LENGTH(envelope_template) FROM etap.ai_prompt_response_templates
  WHERE service_name = 'github_copilot' AND response_type = 'copilot_sse';
-- Expect ~720 B
```

### Rollback (if Phase 6 verification fails)

```sql
BEGIN;
UPDATE etap.ai_prompt_services SET response_type = 'copilot_403' WHERE service_name = 'github_copilot';
DELETE FROM etap.ai_prompt_response_templates WHERE service_name = 'github_copilot' AND response_type = 'copilot_sse';
UPDATE etap.etap_APF_sync_info SET revision_cnt = revision_cnt + 1 WHERE table_name IN ('ai_prompt_services','ai_prompt_response_templates');
COMMIT;
```

The original `copilot_403` envelope row is NOT deleted — it stays in the table as a fallback in case other future services want to reuse the GitHub 403+JSON pattern.

---

## 5. Phase 6 Test Criteria (must all pass)

1. **DB UPDATE applied** — both `ai_prompt_services` and `ai_prompt_response_templates` show new state, `etap_APF_sync_info.revision_cnt` bumped by 1 each
2. **etap process reload** — within ~5 seconds of the UPDATE, etap detects the revision change and reloads (verifiable via etap.log `[APF] reload` entries or by waiting one polling cycle)
3. **APF block fires correctly** — submit a sensitive prompt to Copilot, expect:
   - L2 etap.log: `[APF:hold_set]` and `[APF:block]` entries with `service=github_copilot response_type=copilot_sse`
   - `[APF:envelope]` entry with `rendered via DB template` and the byte length
   - `[APF:h2_params]` entry with `h2_end_stream=1`
4. **Browser observation (test PC ground truth)**:
   - DevTools Network panel shows the POST to `/messages` returning **HTTP 200**, `Content-Type: text/event-stream`
   - Response body contains both `content` and `complete` SSE events
   - **Chat bubble in the UI shows the warning text** as if it were a normal assistant response (NOT the generic primer-react error banner)
   - No JS console errors from CORS rejection
   - No legacy `.flash-error` populated (Copilot uses primer-react, not legacy flash)
5. **Regression**: chatgpt/claude/genspark/etc. unaffected — verify by L2 etap.log spot check after migration

If any criterion fails, rollback per §4 and update Phase 5 design.

---

## 6. Test Log Protocol

Per `genai-apf-pipeline/SKILL.md` Test Log Protocol, instrument the SSE envelope rendering site with:

```cpp
bo_mlog_info("[APF_WARNING_TEST:github_copilot] envelope rendered service=%s template=%s body_len=%zu request_id=%s",
             service_name.c_str(), template_name.c_str(), body_len, x_request_id.c_str());
```

Insert at the rendering call site in `ai_prompt_filter.cpp` (already present for other services per cycle 22 L2 trace showing `[APF_WARNING_TEST:hold_release]`). The bo_mlog_info instrument is REMOVED at Phase 7 release build per the test log gate.

---

## 7. Schema Drift Monitoring

GitHub may change Copilot's response schema in future deployments. Drift indicators to watch:

- New event types beyond `content` and `complete` (e.g., `tool_use`, `cancel`, `error`)
- `complete` event field additions/removals
- CORS header changes (e.g., dropping `Access-Control-Expose-Headers`)
- Endpoint path changes (e.g., `/threads/{threadId}/messages` → `/threads/{threadId}/turns`)
- API host changes from `api.individual.githubcopilot.com` to a new subdomain

Re-run a 5-minute mini frontend-inspect probe **once a quarter** OR when GitHub announces a Copilot UI refresh. If schema drifts, re-derive the envelope from the new wire format.

The captured stream is small enough (373 B for a 1-token response) that schema diffs are easy to spot in the test PC result.

---

## 8. Open Questions for Phase 6

1. ~~**Does APF currently strip CORS headers on copilot_403 responses?**~~ **RESOLVED (cycle 30+31):** Two-part answer. (a) APF does not strip or preserve headers at all — it synthesizes the whole response from `envelope_template` (cycle 30). (b) The existing `copilot_403` envelope (confirmed via `functions/ai_prompt_filter/sql/apf_db_driven_migration.sql` lines 138–153) **already contains** `access-control-allow-credentials: true` + `access-control-allow-origin: https://github.com`, so CORS was never the blocker (cycle 31 correction). The **real root cause** of the old failure is that GitHub's React Copilot app treats any non-200 status as an error and renders a static-i18n primer-react Banner regardless of body contents — proven by Phase 4 §5 empty-500 fetch-override test. The new copilot_sse envelope fixes this by returning HTTP 200 + SSE, which enters the success code path. See §2 for the full investigation.
2. **Should `parentMessageID` reflect the request body's `responseMessageID` field?** Phase 4 noted this maintains React threading state. If APF can parse the request JSON cheaply (it's already buffered for the prompt-content match), reflecting is preferred. If not, generating fresh UUIDs is acceptable per Phase 4 §3.
3. **Does Copilot's React app retry on its own if the SSE stream looks malformed?** Phase 4 didn't probe this. If yes, our envelope must be perfectly valid (no truncation, valid JSON, proper `\n\n` boundaries) — already specified above.
4. **Initial-load Option D combination**: should we also implement Option D (initial-load disclaimer banner) as a complementary measure? Probably YES for a one-time session warning, but defer to a follow-up task; Phase 6 focuses on Option A only.

---

## 9. Implementation Cost Estimate

- DB migration: 1 INSERT + 1 UPDATE + 2 sync_info bumps = ~5 minutes once DB access is open
- C++ code changes: 0 (existing SSE rendering path handles `text/event-stream` already, since deepseek uses the same content-type; just need template lookup by `response_type='copilot_sse'`)
- Test PC verification: 1 sensitive prompt submit + screenshot capture = ~3 minutes
- L2 etap.log verification: ~2 minutes
- Total Phase 6 time: **~10 minutes** assuming no surprises

Combined with deepseek + v0 in same DB window: ~25 minutes for all three services.
