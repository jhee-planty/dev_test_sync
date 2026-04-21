# DeepSeek Phase 5 Design — Option A (SSE envelope injection)

> Phase 5 deliverable. Built directly from `services/deepseek_frontend.md` (#451, 2026-04-15).
> **Strategy: Option A — SSE stream injection using DeepSeek's JSON-Patch schema.**
> No fallback: Options B/C/D/E all blocked, no infrastructure gap.

## Context

| Field | Value |
|-------|-------|
| Service | DeepSeek (chat.deepseek.com) |
| Current state | BLOCK_ONLY → transitioning to **NEEDS_ALTERNATIVE → DESIGNED (Option A)** |
| Primary API | `POST https://chat.deepseek.com/api/v0/chat/completion` |
| Response format | `text/event-stream; charset=utf-8`, h2 |
| DB row (current) | `domain_patterns=deepseek.com,*.deepseek.com,chat.deepseek.com`, `path=/api/v0/chat/completion`, `response_type=deepseek_sse`, `h2_mode=2`, `h2_end_stream=2` (current setting after #315 breakthrough) |
| Envelope status | Existing `deepseek_sse` envelope produces 0 parsed events on the frontend → this design REPLACES the envelope body |

## Strategy Selection — Option A

### Why Option A

1. **Protocol fully captured (#451)**: DeepSeek's SSE consists of named events + unnamed JSON-Patch data frames mutating an in-memory `response` object. The full wire format is in `deepseek_frontend.md`.
2. **State-driven rendering**: The assistant chat bubble is rendered off `state.response.fragments[-1].content`. A single content-bearing patch that creates the fragments array is enough to render the full warning text.
3. **Path inheritance**: The schema allows later `{v: ...}` events to inherit path+op from earlier patches, but we don't need this — a single initialization patch handles everything.
4. **Permissive schema**: Omitted optional fields (`updated_at`, `title`) cause at most console warnings, not render failures.
5. **No CSP / no DOM tricks**: APF operates at network layer and delivers the envelope as normal SSE — the frontend treats it as a legitimate assistant reply.
6. **Ideal UX**: Warning renders inside a chat bubble (not as a toast, not as a banner), visually indistinguishable from a real AI response.

### Why not B/C/D/E

| Option | Blocker |
|--------|---------|
| B (HTML body swap) | `fetch()` streams SSE — HTML is parser error, not navigation |
| C (JS error panel) | Error UI is static i18n `네트워크를 확인하고 다시 시도하세요.` — not content-addressable |
| D (DOM injection) | APF is network-layer, no DOM access |
| E (block page) | `/a/chat/s/<chatId>` is SPA route, completion is fetch not document |

## Envelope Template — Minimal viable

Replace the existing `deepseek_sse` envelope in `ai_prompt_response_templates` with:

```
HTTP/1.1 200 OK
Content-Type: text/event-stream; charset=utf-8
Cache-Control: no-cache, no-transform
X-Accel-Buffering: no
Connection: keep-alive
Content-Length: 0

event: ready
data: {"request_message_id":1,"response_message_id":2,"model_type":"default"}

event: update_session
data: {"v":{"response":{"message_id":2,"parent_id":1,"model":"","role":"ASSISTANT","thinking_enabled":false,"ban_edit":false,"ban_regenerate":false,"status":"WIP","incomplete_message":null,"accumulated_token_usage":0,"files":[],"feedback":null,"inserted_at":0,"search_enabled":false,"fragments":[{"id":2,"type":"RESPONSE","content":"{{MESSAGE}}","references":[],"stage_id":1}],"has_pending_fragment":false,"auto_continue":false}}}

data: {"p":"response/status","o":"SET","v":"FINISHED"}

event: close
data: {"click_behavior":"none","auto_resume":false}
```

### Notes on the envelope

- `{{MESSAGE}}` is substituted by `render_envelope_template()` at `ai_prompt_filter.cpp:974` with the per-rule warning text.
- `Content-Length: 0` is auto-recalculated by the renderer.
- `\r\n\r\n` between headers and body is required (SSE parser accepts either line ending).
- Double-newline `\n\n` between SSE events is **required** — each event must be terminated by a blank line or the parser will treat consecutive data lines as one event.
- `message_id=2`, `parent_id=1` are arbitrary small integers. The frontend uses them for client-side state tracking but doesn't validate against a server DB for a block response (the entire chat session is virtualized by this envelope).
- `content` carries the full warning text. **Markdown is rendered** — `**bold**`, `*italic*`, emoji, and URLs all render correctly in the DeepSeek chat bubble.
- `fragments` is an array because DeepSeek supports multi-fragment assistant responses (thinking+answer+tool-call). We ship a single RESPONSE fragment.
- `status: "WIP"` in the initial assignment + `status: "FINISHED"` in the subsequent patch is the **correct state transition**. Skipping the WIP→FINISHED transition may cause the frontend to hold the bubble in a "generating..." state indefinitely.

### Size estimate

Headers ~170B + body ~650B (with a 60B warning message) ≈ **820B total**.

**⚠️ This exceeds the 500B h2_end_stream=2 ceiling.** See size-mitigation strategies below.

## h2 DATA frame size constraint

DeepSeek's current DB row has `h2_end_stream=2` (the 500B-class setting that limits payload for services in this category). The raw envelope above is ~820B, which exceeds that ceiling by ~320B.

### Mitigation options (in order of preference)

1. **Trim the `update_session` payload** — drop non-essential fields from the response object:
   - Remove: `thinking_enabled`, `ban_edit`, `ban_regenerate`, `incomplete_message`, `accumulated_token_usage`, `files`, `feedback`, `inserted_at`, `search_enabled`, `has_pending_fragment`, `auto_continue`
   - Remove: `model`, `parent_id` (if the renderer tolerates it — test required)
   - Keep: `message_id`, `role`, `status`, `fragments`
   - Estimated post-trim size: ~480B total. **Fits under 500B with margin.**

2. **Switch to `h2_end_stream=1`** — if the pipeline allows escalating this service out of the 500B class. Requires confirming that DeepSeek still accepts h2 END_STREAM without GOAWAY. Historically (`deepseek_failures.md` #311-#313) GOAWAY mode (`h2_mode=1`) killed the connection before any data frames were written, so we'd stay on `h2_mode=2` keep-alive while only changing `h2_end_stream` to 1.

3. **Infrastructure expansion (H2 DATA frame splitting)** — documented as a pending item in `references/apf-technical-limitations.md §5`. Not ready for production.

**Preferred path**: Start with mitigation 1 (trim). Fall back to 2 if trimming breaks the frontend parser.

## Trimmed envelope (proposed primary — under 500B)

```
HTTP/1.1 200 OK
Content-Type: text/event-stream; charset=utf-8
Cache-Control: no-cache
Content-Length: 0

event: ready
data: {"request_message_id":1,"response_message_id":2,"model_type":"default"}

data: {"v":{"response":{"message_id":2,"role":"ASSISTANT","status":"WIP","fragments":[{"id":2,"type":"RESPONSE","content":"{{MESSAGE}}","references":[],"stage_id":1}]}}}

data: {"p":"response/status","o":"SET","v":"FINISHED"}

event: close
data: {"click_behavior":"none"}
```

**Size estimate**: Headers ~95B + body ~360B + `{{MESSAGE}}` (~60B) ≈ **515B**.

**Still ~15B over the 500B ceiling.** Further trims required:

- Shorten content from `{{MESSAGE}}` (which expands ~60B) to a shorter warning: **"⚠️ 보안 정책"** (~14B) → final size ~469B. **Under 500B.**
- OR: drop the initial `ready` event — test whether the frontend requires it or will accept skipping directly to the response object patch. If drop works, saves ~90B.

## Schema drift risk + mitigation

- DeepSeek could update their SSE schema in a future frontend release — adding required fields, renaming ops, or introducing a signed field (e.g. HMAC on `response.message_id`).
- **Mitigation**: Capture a fresh completion response monthly (or on any DeepSeek UI update) and diff against the saved wire-format sample in `deepseek_frontend.md`. If the schema drifts, update the envelope template before the running production envelope breaks.
- **Early-warning signal**: The APF dispatcher logs `[APF:envelope] service=deepseek response_type=deepseek_sse rendered via DB template`. If after a schema change users start reporting "network error" instead of seeing the warning, check whether the frontend now expects a new field.

## Code verification (no C++ changes needed)

1. `ai_prompt_filter.cpp:974 render_envelope_template()` — content-type agnostic, placeholder substitution works for SSE bodies (`{{MESSAGE}}`, `{{MESSAGE_RAW}}`, `{{TIMESTAMP}}`, `{{UUID:name}}`, `{{BODY_INNER_LENGTH}}`) with auto Content-Length recalculation. Already used by `chatgpt_sse`, `gamma_sse`, `perplexity_sse`.
2. `ai_prompt_filter.cpp:1254-1263` — dispatcher is pure DB lookup: `_config_loader->get_envelope_template("deepseek_sse")` returns whatever is currently in `ai_prompt_response_templates`. Zero C++ awareness of new envelope content.
3. `ai_prompt_filter_db_config_loader.cpp:640-678 db_loader::load()` — builds the `_envelopes` map keyed by `response_type` column directly.
4. Existing DeepSeek row state (must be verified via pre-check): currently serves a `deepseek_sse` envelope that produces 0 parsed events. The Phase 6 migration **updates the envelope body in place**, not the `response_type` key.

## Phase 6 Migration SQL

```sql
BEGIN;

-- 0. Pre-check — capture existing state
SELECT service_name, domain_patterns, path_patterns, block_mode,
       response_type, h2_mode, h2_end_stream, h2_goaway, h2_hold_request
  FROM etap.ai_prompt_services
 WHERE service_name = 'deepseek';

SELECT service_name, http_response, response_type, envelope_template,
       LENGTH(envelope_template) AS envelope_bytes
  FROM etap.ai_prompt_response_templates
 WHERE service_name = 'deepseek';

-- 1. Service attrs — keep existing keep-alive, ensure h2_end_stream=2
UPDATE etap.ai_prompt_services
   SET domain_patterns = 'deepseek.com,*.deepseek.com,chat.deepseek.com',
       path_patterns   = '/api/v0/chat/completion',
       response_type   = 'deepseek_sse',
       h2_mode         = 2,   -- keep-alive, no GOAWAY (#313 failure history)
       h2_end_stream   = 2,   -- 500B-class ceiling
       h2_goaway       = 0,
       h2_hold_request = 1    -- hold request body until envelope is emitted
 WHERE service_name = 'deepseek';

-- 2. Envelope — replace with trimmed Option A envelope
UPDATE etap.ai_prompt_response_templates
   SET response_type     = 'deepseek_sse',
       envelope_template = CONCAT(
         'HTTP/1.1 200 OK\r\n',
         'Content-Type: text/event-stream; charset=utf-8\r\n',
         'Cache-Control: no-cache\r\n',
         'Content-Length: 0\r\n',
         '\r\n',
         'event: ready\n',
         'data: {"request_message_id":1,"response_message_id":2,"model_type":"default"}\n',
         '\n',
         'data: {"v":{"response":{"message_id":2,"role":"ASSISTANT","status":"WIP","fragments":[{"id":2,"type":"RESPONSE","content":"{{MESSAGE}}","references":[],"stage_id":1}]}}}\n',
         '\n',
         'data: {"p":"response/status","o":"SET","v":"FINISHED"}\n',
         '\n',
         'event: close\n',
         'data: {"click_behavior":"none"}\n',
         '\n'
       )
 WHERE service_name = 'deepseek';

-- 3. Trigger reload
UPDATE etap.etap_APF_sync_info SET revision_cnt = revision_cnt + 1
 WHERE table_name = 'ai_prompt_services';
UPDATE etap.etap_APF_sync_info SET revision_cnt = revision_cnt + 1
 WHERE table_name = 'ai_prompt_response_templates';

COMMIT;
```

### Note on size inside the DB row

The SQL above produces an envelope of **~555B** before `{{MESSAGE}}` expansion (515B of literal content + 40B for Content-Length line which later auto-recalcs). The rendered size after `{{MESSAGE}}` substitution depends on the warning text length from the rule row (`ai_prompt_rules.message` or equivalent). If the warning text is kept under 40B, the total stays under 500B.

**Recommendation**: Use a short warning text like `⚠️ 보안 정책 위반이 감지되었습니다` (~45B) and verify the rendered envelope size via `bo_mlog_info("[APF:h2_params] ... http1_size=%zu")` at `ai_prompt_filter.cpp:1285` (which is already logged). If rendered size > 500B, either trim more envelope fields OR escalate to `h2_end_stream=1` (mitigation path 2).

## Phase 6 pre-check: `validate_template` CLI

The running etap binary exposes an `ai_prompt_filter.validate_template <response_type>` command (confirmed in `ai_prompt_filter.cpp:319–384`, cycle 31 discovery). It:

1. Loads envelope from DB via `get_envelope_template(response_type)`
2. Renders with `"__VALIDATION_TEST__"` as the message
3. Validates HTTP status line (`HTTP/`), header-body separator (`\r\n\r\n`), and Content-Length consistency
4. Returns a `[VALID]`/`[INVALID]` summary + first 2048 bytes of rendered output

**Phase 6 pre-check procedure:**

```bash
# After UPDATE but BEFORE triggering test-PC request, validate the updated template:
ssh -p 12222 solution@218.232.120.58 "etapcomm ai_prompt_filter.validate_template deepseek_sse"
# Expected output: [VALID] response_type='deepseek_sse' template_size=~555 rendered_size=~575
# The rendered output should contain the JSON-Patch op events:
#   data: {"v":[{"p":"response/content","o":"append","v":"..."}]}
# and end with 'data: [DONE]'
```

If validation fails (`[INVALID]`), **rollback the UPDATE** via the revert block in `phase6_combined_migration_2026-04-15.sql` PART 4 before the test-PC request goes out. This prevents a botched template from going live. **This is a significant Phase 6 de-risk** — we verify the rendered wire bytes without triggering a real block, which matters for deepseek specifically because `h2_end_stream=2` imposes a 500B ceiling and rendered_size must be measured before commit.

## Phase 6 test criteria

1. **Pre-migration**: capture existing envelope via pre-check SELECT, save to impl journal.
2. **Apply UPDATE + revision_cnt bump** in single transaction.
3. **Validate template** via `etapcomm ai_prompt_filter.validate_template deepseek_sse` (see pre-check above). Require `[VALID]` + rendered_size ≤ 500B before proceeding.
4. **Verify reload**: `ssh -p 12222 solution@218.232.120.58 "grep 'Loaded.*services' /var/log/etap.log | tail -5"`
5. **Test PC check-warning request** (new #4XX): logged-in deepseek session, trigger a blocked prompt, verify:
   - Assistant chat bubble appears with the warning text (not a network error)
   - Markdown is rendered correctly (`⚠️ 보안 정책` emoji + Korean text)
   - No "네트워크를 확인하고 다시 시도하세요" error UI appears
   - No console errors from SSE parse failure
   - Chat session remains usable after the block (can type next prompt without reload)
6. **Regression check**: Verify that chatgpt, claude, genspark, blackbox, qwen3, grok (done services) all still show their warnings correctly.

## Test Log Protocol (Phase 6 impl journal)

Per `apf-warning-impl/references/test-log-templates.md`, inject temporary markers:

```cpp
bo_mlog_info("[APF_WARNING_TEST:deepseek] envelope=%s http1_size=%zu h2_end_stream=%d",
             lookup_key.c_str(), http1_response.size(), sd->h2_end_stream);
```

Remove after verification (Phase 7 release build).

## NOT NEEDED

- **Sub-agent orchestration**: Phase 5 is doable directly from the #451 result without a discussion-review or sub-agent design session. The envelope template is essentially transcribed from the captured wire format.
- **Phase 1 re-capture**: The current `deepseek_sse` envelope row exists and the path `/api/v0/chat/completion` is confirmed correct. No fresh HAR capture needed.
- **Phase 2 re-analysis**: The schema analysis is in `deepseek_frontend.md`, and this design is the direct output.

## Expected outcome after Phase 6

DeepSeek moves **BLOCK_ONLY → DONE** with Option A delivering a visible warning inside the chat bubble. This is the 7th service to reach DONE status (after chatgpt, claude, genspark, blackbox, qwen3, grok).

## Source

- `results/451_deepseek-frontend-inspect_result.json` (2026-04-15 17:18 KST)
- `services/deepseek_frontend.md` (Phase 4 deliverable, 2026-04-15)
- `functions/ai_prompt_filter/ai_prompt_filter.cpp:974` (render_envelope_template)
- `functions/ai_prompt_filter/ai_prompt_filter.cpp:1254-1270` (dispatcher = pure DB lookup)
- `functions/ai_prompt_filter/ai_prompt_filter_db_config_loader.cpp:640-678` (envelope map load)
- `local_archive/archived/lessons/deepseek_failures.md` (historical attempts #309-#356)
- `local_archive/apf_infra_scoping_2026-04-14.md` (500B ceiling analysis)
