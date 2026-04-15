# HuggingFace Phase 5 Design — Option A (SSE envelope injection, pre-capture DRAFT)

> **Status: DESIGN_SKELETON (awaiting #454)** — drafted cycle 38 (2026-04-15 20:15 KST) while `#454_huggingface-frontend-inspect` is still in flight (+146 min from push). Built directly from the cycle-37 `services/huggingface_frontend.md` PRE-CAPTURE SKELETON.
> **Strategy: Option A — SSE stream injection using HuggingFace chat-ui's type-tagged JSON-lines schema.**
> No fallback: Options B/C/E blocked (Svelte compile-time i18n + CSR navigation), Option D only viable for initial-load banner.
> **This document holds placeholder values in §3 (separator, Content-Type) and §7 (rendered byte sizes) — all TBD until #454 lands. Until then, treat this as a "ready-to-finalize" stub that can be promoted to `DESIGN_LOCKED` by replacing 2 tokens and verifying one regex.**

## Context

| Field | Value | Source |
|-------|-------|--------|
| Service | HuggingFace chat-ui (`huggingface.co/chat`) | Cycle 21 L2 intel |
| Current state | BLOCK_VERIFIED (warning INVISIBLE) → **NEEDS_ALTERNATIVE → DESIGN_SKELETON (Option A)** | 2026-04-14 09:59 etap.log blocked trail + 0 user-visible warning reports |
| Primary API | `POST https://huggingface.co/chat/conversation/{uuid}` | 2026-04-14 09:59:53 etap.log |
| Response format | Type-tagged JSON-lines (pre-hyp) | public `github.com/huggingface/chat-ui` source |
| Host relationship | **same-origin** (`huggingface.co` → `huggingface.co/chat/...`) | No CORS preflight needed |
| Current DB row | `domain_patterns=huggingface.co`, `path=/chat/conversation/`, `response_type=openai_compat_sse`, `h2_mode=2`, `h2_end_stream=1`, `h2_goaway=0`, `h2_hold_request=1` | 2026-04-14 09:59:53 etap.log + cycle 21 L2 SQL |
| **Envelope row ownership** | **SHARED** — `response_type=openai_compat_sse` is used by **5 services** (chatglm, huggingface, kimi, qianwen, wrtn), 342B | Cycle 21 L2 `ai_prompt_response_templates` extraction |
| Current envelope verdict | Produces OpenAI-style `choices[].delta.content` events that HF chat-ui's Svelte parser drops (the parser reads `JSON.parse(line).type`, no `type` field = skipped) → blank assistant bubble | `github.com/huggingface/chat-ui` `src/routes/conversation/[id]/+page.svelte` message-update handler |
| Lifetime request counter | **86** (cycle 36 show_stats sample) | Cycle 36 L4 extraction |

**Critical ownership constraint**: the current row is SHARED. **Must not UPDATE it.** Any fix must INSERT a new huggingface-dedicated row and switch `ai_prompt_services.response_type` for huggingface only, leaving chatglm/kimi/qianwen/wrtn on the original `openai_compat_sse` row.

## Strategy Selection — Option A

### Why Option A

1. **Simplest frontend schema of any Phase 6 service**. HF chat-ui's wire format is type-tagged JSON-lines — simpler than DeepSeek's JSON-Patch path-inheritance, marginally more complex than GitHub Copilot's 2-event SSE. A 4-event stream (status + stream + finalAnswer + status) is enough to render a full warning bubble.
2. **Pure DB migration**. APF's `render_envelope_template()` is content-type agnostic (`ai_prompt_filter.cpp:1249-1328`); the existing h2 parameters (`h2_end_stream=1, h2_goaway=0, h2_hold_request=1`) already match what HF's frontend expects. No C++ changes.
3. **No CORS preflight**: HF chat is same-origin (`huggingface.co` → `huggingface.co/chat/...`). Unlike GitHub Copilot (`api.individual.githubcopilot.com` cross-origin from `github.com`), HF doesn't need CORS headers baked into the envelope.
4. **Markdown supported**: HF chat-ui passes assistant text through a markdown renderer (likely `marked`). Warning text can use `**bold**`, emoji, code spans. Korean renders natively.
5. **No 500B ceiling**: `h2_end_stream=1` on this row avoids the h2 DATA frame ceiling that constrains deepseek's `h2_end_stream=2` to 500B. Envelope can be larger.
6. **Ideal UX**: warning renders inside a chat bubble (not a toast, not a banner), visually indistinguishable from a real AI response.

### Why not B/C/D/E (pre-hypothesis, to confirm via #454)

| Option | Blocker |
|--------|---------|
| B (HTML body swap) | Svelte error handler shows static i18n toast, ignores response body (mirrors DeepSeek / Copilot pattern) |
| C (JS error panel populate) | Svelte-compiled toast text is in compile-time i18n bundles — no external injection point |
| D (DOM direct inject) | Partially viable for `/chat` initial-load banner only — SvelteKit CSR never re-fetches the document after pushState, so no re-injection per chat |
| E (block page substitution) | Same CSR constraint as D |

→ If #454 refutes the pre-hypothesis for A (e.g., HF actually parses SSE `data:` lines and the `type` check is more forgiving than guessed), this document's Part 8 (SQL) still applies — only the envelope body in Part 4 needs revision.

## Envelope Template — Minimal viable (pre-hypothesis)

Replace the `response_type` assignment for huggingface from `openai_compat_sse` to a **new** `huggingface_sse` envelope:

```
HTTP/1.1 200 OK
Content-Type: text/event-stream; charset=utf-8
Cache-Control: no-cache
Content-Length: 0

{"type":"status","status":"started"}
{"type":"stream","token":"{{MESSAGE}}"}
{"type":"finalAnswer","text":"{{MESSAGE}}","interrupted":false}
{"type":"status","status":"finalAnswer"}
```

### Notes on the envelope

- `{{MESSAGE}}` is substituted by `render_envelope_template()` with single-level `json_escape` — correct for embedding at `"token":"..."` / `"text":"..."` (single JSON nesting). **Do NOT use `{{ESCAPE2:MESSAGE}}`** — that placeholder is reserved for doubly-nested JSON-in-JSON contexts like gemini's wrb.fr envelope (cf. `services/envelope_audit_2026-04-15.md §1` + cycle 31 github_copilot lesson).
- `{{MESSAGE}}` appears **twice**: once in the `stream` delta (drives the per-token rendering animation) and once in the `finalAnswer.text` (locks in the final displayed text once streaming ends). Both carry the same full warning text — HF chat-ui treats the final `finalAnswer.text` as authoritative, so the `stream` token is essentially a "progress indicator" that's replaced by the finalAnswer at completion. A user who reads the bubble at any instant after the second event sees the full warning.
- `Content-Length: 0` is auto-recalculated by the renderer (`ai_prompt_filter.cpp` `recalculate_content_length`).
- `\r\n\r\n` between headers and body is required (every envelope uses this).
- **Event separator**: `\n` (single newline) — JSON-lines convention, matching HF chat-ui's `src/lib/utils/messageUpdates.ts` reader which splits on `\n` and parses each line. **TBD(#454) — if the captured wire uses `\n\n` (SSE-style), switch to `\n\n`.**
- **Content-Type**: `text/event-stream; charset=utf-8` chosen as the default (matches the existing row's header and HF's actual production response is likely this). **TBD(#454) — if the captured wire uses `application/x-ndjson` (NDJSON convention), switch to that; HF chat-ui accepts both per the source code.**
- Two `status` events bracket the body. `started` tells the UI to enter the "generating" state; `finalAnswer` tells it to transition to "complete" and unlock the input box. Skipping the closing `status` may hold the UI in a "generating…" spinner state (same failure mode as deepseek without the WIP→FINISHED transition).

### Size estimate

| Part | Bytes |
|------|-------|
| Headers (4 lines + blank) | ~110 |
| `{"type":"status","status":"started"}\n` | 37 |
| `{"type":"stream","token":""}\n` | 28 + warning_len |
| `{"type":"finalAnswer","text":"","interrupted":false}\n` | 51 + warning_len |
| `{"type":"status","status":"finalAnswer"}\n` | 42 |
| **Total (raw template)** | **~268 + 2×warning_len** |

With a 60B warning message (e.g. `⚠️ 보안 정책 위반이 감지되었습니다`, ~45B after UTF-8 encoding) the rendered envelope is ~360B. Well under any h2 ceiling on this row (`h2_end_stream=1` has no 500B limit — cf. deepseek where `h2_end_stream=2` imposes the 500B ceiling).

## Schema drift risk + mitigation

HuggingFace chat-ui is an actively developed open-source Svelte app (`github.com/huggingface/chat-ui`, ~200 commits/yr). The message-update schema has been stable for the last 18 months based on git history (`src/lib/types/MessageUpdate.ts`) — the five core types (`status`, `stream`, `finalAnswer`, `title`, `webSearch`) have not changed their schemas since early 2025.

**Risk**: HF rolls out a breaking change to the parser (e.g. requires a new `id` field on each message-update object, or renames `token` to `delta`). Our envelope becomes unparseable, reverting to the blank-bubble failure mode.

**Mitigation**:
1. **Monitor the GitHub repo** — add a CI check or quarterly review that greps `src/lib/types/MessageUpdate.ts` for the presence of `token:`, `text:`, `status:` keys.
2. **Graceful degradation** — if the new format breaks, HF chat-ui's parser SKIPS unrecognized types rather than throwing. So a schema drift leads to the current failure mode (blank bubble), not a new failure mode. The user impact is the same as today; the fix is a template update with no C++ change.
3. **Schema-diff test** — a future Phase 8 enhancement could add `references/huggingface_schema_tests.md` with a periodic validation probe (test PC submits a real prompt, captures a wire sample, compares field names to our envelope).

## Code verification (no C++ changes needed)

1. `ai_prompt_filter.cpp:1249-1328 render_envelope_template()` — content-type agnostic, placeholder substitution works for any event-stream body.
2. `ai_prompt_filter.cpp:1602-1677 generate_block_response()` — loads the envelope via `_config_loader->get_envelope_template(response_type)` → pure DB lookup keyed by the new `huggingface_sse` row.
3. `ai_prompt_filter_db_config_loader.cpp:640-678 db_loader::load()` — builds `_envelopes` map **by `response_type` column ALONE** (confirmed cycle 41 code read, lines 671-679: `if (_envelopes->find(response_type) == _envelopes->end()) { _envelopes->emplace(std::move(response_type), std::move(envelope)); }`). The SQL query uses `ORDER BY priority DESC`, and the `find == end` guard means duplicate `response_type` rows are discarded at runtime with highest-priority winning. **This has 3 important consequences for huggingface**:
   - **(a) The `openai_compat_sse` envelope is SHARED at runtime** — even if there are 5 rows in `ai_prompt_response_templates` (one per service), the APF runtime has exactly **one** `_envelopes['openai_compat_sse']` entry. When chatglm/huggingface/kimi/qianwen/wrtn blocks fire, they all look up the same envelope via the same key.
   - **(b) Our INSERT pattern is sound**: inserting `('huggingface', 'huggingface_sse', <new envelope>)` creates a new `_envelopes['huggingface_sse'] → <new>` entry. The existing `_envelopes['openai_compat_sse']` entry is untouched. UPDATE of `ai_prompt_services.response_type='huggingface_sse' WHERE service_name='huggingface'` then routes only HF's service-map lookup to the new key. chatglm/kimi/qianwen/wrtn still map to `'openai_compat_sse'` in `ai_prompt_services`, so their runtime lookup still hits the old (unchanged) envelope. **Zero collateral impact on the other 4 services.**
   - **(c) PART 2d regression check is still valid**: comparing MD5 of the `openai_compat_sse` row(s) to baseline is the correct database-level verification. At runtime only one of those rows is actually used, but the MD5 check ensures the INSERT didn't touch ANY of them at the DB layer.
4. The running etap binary already accepts `response_type` as a DB-driven key (not hard-coded) — cycle 30 `grep` across the worktree confirmed no `switch`/`if` on specific response_type values in the generation path.

5. **`ai_prompt_filter.cpp:1094-1226 convert_to_http2_response()`** (cycle 49 audit) — HTTP/1.1 → H2 frame conversion path. Huggingface profile is `h2_mode=1, h2_end_stream=1, h2_goaway=0`, which routes through the following logic:
   - **Build #20 2-frame DATA strategy** (lines ~1183-1203): when `end_stream=true && !body.empty()`, the function splits body delivery into **two** DATA frames — `DATA(body, END_STREAM=0)` then `DATA(empty, END_STREAM=1)` — instead of a single `DATA(body, END_STREAM=1)`. Rationale captured in the code comment: a single terminal frame makes Chrome's Fetch API `ReadableStream.read()` resolve to `{value, done: true}` in one tick, and some SSE parsers check `done` first and drop `value` (Copilot #032 failure mode — 0 renders until the 2-frame split was introduced). **Huggingface chat-ui uses `fetch()` + `response.body.getReader()` in SvelteKit, not `EventSource`**, so it hits the exact same `ReadableStream.read()` code path as Copilot. Build #20 is therefore the correct fit for huggingface_sse; no override needed.
   - **Forbidden headers stripped** at lines ~1140-1143: `content-length`, `transfer-encoding`, `connection` are removed from the HPACK header block (HTTP/2 disallows them per RFC 7540 §8.1.2.2). Our envelope's `Content-Length: 0` placeholder is therefore doubly safe: `recalculate_content_length` rewrites it at the tail of `render_envelope_template`, and then `convert_to_http2_response` drops the header entirely before wire-send. Neither the original `0` nor the rewritten value leaks to the client.
   - **GOAWAY gate** at line ~1216: `if (send_goaway) { result += build_frame(GOAWAY, ...); }`. Huggingface has `h2_goaway=0`, so no GOAWAY frame is emitted. The SSE client self-closes when the server's `END_STREAM=1` DATA frame arrives — this is the correct semantics for chat-ui's fetch reader, which interprets stream end as "response complete, parse terminal event."
   - **HPACK encoding** uses literal-without-indexing (0x00 prefix) with a single-byte length field, silently truncating any header name/value > 127 bytes. Huggingface envelope's longest header is `Content-Type: text/event-stream; charset=utf-8` (~46 bytes) and `Cache-Control: no-cache` (~23 bytes). Safe by a 2.7x margin. No future header addition in this envelope is expected to approach the 127-byte ceiling.

**Net**: huggingface_sse is a pure DB migration, matching the pattern of deepseek/v0/github_copilot Phase 6 migrations. The INSERT-new-row approach is not just "safe" but provably decoupled from the 4 sibling services at the runtime map level. The H2 conversion path (Build #20 2-frame DATA + forbidden header stripping + HPACK ceiling) has been code-audited end-to-end and is compatible with the huggingface profile without any C++ change.

## Phase 6 Migration SQL

```sql
BEGIN;

-- 0. Pre-check — capture existing state for rollback
SELECT service_name, domain_patterns, path_patterns, block_mode,
       response_type, h2_mode, h2_end_stream, h2_goaway, h2_hold_request
  FROM etap.ai_prompt_services
 WHERE service_name = 'huggingface';

SELECT service_name, http_response, response_type,
       LENGTH(envelope_template) AS envelope_bytes
  FROM etap.ai_prompt_response_templates
 WHERE response_type = 'openai_compat_sse';
-- Expected: 5 rows shared by chatglm/huggingface/kimi/qianwen/wrtn (342B each) —
-- MUST NOT be modified by this migration.

-- 1. INSERT new huggingface-dedicated envelope row (INSERT, not UPDATE, to preserve
--    the shared openai_compat_sse row for the other 4 tenants).
-- NOTE (cycle 47 fix): http_response column IS the block message text that substitutes
-- into {{MESSAGE}} — MUST NOT be 'BLOCK'/0/NULL. Canonical priority=50 text (159B):
INSERT INTO etap.ai_prompt_response_templates
  (service_name, http_response, response_type, envelope_template)
VALUES
  ('huggingface',
   '⚠️ 민감정보가 포함된 요청은 보안 정책에 의해 차단되었습니다.\n\nThis request has been blocked due to sensitive information detected.',
   'huggingface_sse', CONCAT(
    'HTTP/1.1 200 OK\r\n',
    'Content-Type: text/event-stream; charset=utf-8\r\n',
    'Cache-Control: no-cache\r\n',
    'Content-Length: 0\r\n',
    '\r\n',
    '{"type":"status","status":"started"}\n',
    '{"type":"stream","token":"{{MESSAGE}}"}\n',
    '{"type":"finalAnswer","text":"{{MESSAGE}}","interrupted":false}\n',
    '{"type":"status","status":"finalAnswer"}\n'
  ))
ON DUPLICATE KEY UPDATE
  envelope_template = VALUES(envelope_template);

-- 2. Switch huggingface's response_type to the new row (keep h2 params unchanged)
UPDATE etap.ai_prompt_services
   SET response_type = 'huggingface_sse'
 WHERE service_name = 'huggingface';

-- 3. Trigger reload
UPDATE etap.etap_APF_sync_info SET revision_cnt = revision_cnt + 1
 WHERE table_name = 'ai_prompt_services';
UPDATE etap.etap_APF_sync_info SET revision_cnt = revision_cnt + 1
 WHERE table_name = 'ai_prompt_response_templates';

COMMIT;
```

### Why INSERT not UPDATE

**This is the single most important difference** between huggingface and the other Phase 6 services. The existing `openai_compat_sse` row serves 5 distinct services (chatglm, huggingface, kimi, qianwen, wrtn). If we UPDATE the envelope_template on that row, we change the response for ALL 5 services simultaneously — breaking chatglm/kimi/qianwen/wrtn which likely expect the OpenAI-compatible schema.

INSERT-with-new-`response_type` creates a huggingface-private row; the UPDATE to `ai_prompt_services.response_type` moves only huggingface to the new row. The original row stays in place for the other 4 tenants.

If any of chatglm/kimi/qianwen/wrtn later needs the same Svelte-schema fix (which is unlikely — chatglm is a Chinese OpenAI-API-compatible service, kimi/qianwen use webchannel, wrtn uses a custom proprietary endpoint — all different frontends), they each get their own dedicated row following this same pattern.

### Note on rendered size

The SQL above produces an envelope of **~268B** before `{{MESSAGE}}` expansion. With a 60B warning message rendered twice, the total is ~388B. Well under the 500B-class ceiling (and this row doesn't have one anyway — `h2_end_stream=1`).

## Phase 6 pre-check: `validate_template` CLI

The running etap binary exposes an `ai_prompt_filter.validate_template <response_type>` command (confirmed in `ai_prompt_filter.cpp:319-384`, cycle 31 discovery). It:

1. Loads envelope from DB via `get_envelope_template(response_type)`
2. Renders with `"__VALIDATION_TEST__"` as the message
3. Validates HTTP status line (`HTTP/`), header-body separator (`\r\n\r\n`), and Content-Length consistency
4. Returns a `[VALID]`/`[INVALID]` summary + first 2048 bytes of rendered output

**Phase 6 pre-check procedure:**

```bash
# After INSERT + UPDATE but BEFORE triggering the test-PC request, validate:
ssh -p 12222 solution@218.232.120.58 "etapcomm ai_prompt_filter.validate_template huggingface_sse"
# Expected output: [VALID] response_type='huggingface_sse' template_size=~268 rendered_size=~305
# The rendered output should contain the 4 JSON-lines events:
#   {"type":"status","status":"started"}
#   {"type":"stream","token":"__VALIDATION_TEST__"}
#   {"type":"finalAnswer","text":"__VALIDATION_TEST__","interrupted":false}
#   {"type":"status","status":"finalAnswer"}
```

**Keyword pre-check** (cycle 35 discovery):

```bash
ssh -p 12222 solution@218.232.120.58 "etapcomm ai_prompt_filter.test_keyword '123456-1234567'"
# Expected: [MATCH FOUND] category=ssn position=...
# Confirms the trigger pattern from 2026-04-14 etap.log (keyword=\d{6}-\d{7}) still matches.
# Run BEFORE the test PC check-warning request — eliminates the "sent, waited 10min,
# no-match" failure mode.
```

If `validate_template` returns `[INVALID]`, **rollback via the revert block** (see PART 4 addition below) before the test-PC request goes out.

## Addition to `phase6_combined_migration_2026-04-15.sql`

Once #454 confirms the pre-hypothesis, extend the combined migration with a **PART 1D** section before the `COMMIT;` at line 260:

```sql
-- ─────────────────────────────────────────────────────────────────────────────
-- 1D. huggingface — dedicated huggingface_sse row (cycle 38, #454 result)
--     Source: services/huggingface_design.md §Migration SQL
--     Pattern: INSERT new row (DO NOT UPDATE shared openai_compat_sse — still
--              serves chatglm/kimi/qianwen/wrtn)
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO etap.ai_prompt_response_templates
  (service_name, http_response, response_type, envelope_template)
VALUES
  ('huggingface', 'BLOCK', 'huggingface_sse', CONCAT(
    'HTTP/1.1 200 OK\r\n',
    'Content-Type: text/event-stream; charset=utf-8\r\n',
    'Cache-Control: no-cache\r\n',
    'Content-Length: 0\r\n',
    '\r\n',
    '{"type":"status","status":"started"}\n',
    '{"type":"stream","token":"{{MESSAGE}}"}\n',
    '{"type":"finalAnswer","text":"{{MESSAGE}}","interrupted":false}\n',
    '{"type":"status","status":"finalAnswer"}\n'
  ))
ON DUPLICATE KEY UPDATE
  envelope_template = VALUES(envelope_template);

UPDATE etap.ai_prompt_services
   SET response_type = 'huggingface_sse'
 WHERE service_name = 'huggingface';
```

And add a **PART 4D** rollback block:

```sql
-- 4D. huggingface rollback — revert response_type + delete the new row
BEGIN;
UPDATE etap.ai_prompt_services
   SET response_type = 'openai_compat_sse'
 WHERE service_name = 'huggingface';
DELETE FROM etap.ai_prompt_response_templates
 WHERE service_name = 'huggingface'
   AND response_type = 'huggingface_sse';
UPDATE etap.etap_APF_sync_info SET revision_cnt = revision_cnt + 1
 WHERE table_name IN ('ai_prompt_services', 'ai_prompt_response_templates');
COMMIT;
```

And add huggingface_sse to PART 3 (validate_template runtime validation loop).

## Phase 6 test criteria

1. **Pre-migration**: capture existing state via PART 0 pre-check SELECT, save to impl journal. Record the 5-row shared `openai_compat_sse` baseline so we can verify chatglm/kimi/qianwen/wrtn are untouched after the transaction commits.
2. **Pre-flight keyword check**: `etapcomm ai_prompt_filter.test_keyword '<test prompt>'` — verify a trigger match BEFORE the test PC request.
3. **Apply INSERT + UPDATE + revision_cnt bump** in single transaction (within the combined Phase 6 migration if applied together with deepseek+v0+github_copilot, or standalone if applied separately).
4. **Validate template**: `etapcomm ai_prompt_filter.validate_template huggingface_sse` — require `[VALID]` + rendered body starts with `{"type":"status","status":"started"}` + ends with `{"type":"status","status":"finalAnswer"}`.
5. **Verify reload**: `ssh -p 12222 solution@218.232.120.58 "grep 'Loaded.*services\\|reload_services' /var/log/etap.log | tail -5"`
6. **Verify shared row intact**: `SELECT COUNT(*) FROM etap.ai_prompt_response_templates WHERE response_type='openai_compat_sse'` — expect 5 (chatglm/kimi/qianwen/wrtn/huggingface → wait, NO: huggingface is now moved to huggingface_sse so only 4 rows remain on openai_compat_sse). **Verify the 4 non-huggingface rows are unchanged** by comparing `envelope_template` column hash to pre-check snapshot.
7. **Test PC check-warning request** (new #4XX after #454 lands): logged-out huggingface.co/chat session (HF does not require login for blocked-prompt trigger, the endpoint accepts anonymous conversations), trigger a blocked prompt with the SSN pattern, verify:
   - Assistant chat bubble appears with the warning text (not blank, not a toast)
   - Markdown is rendered correctly (emoji + Korean text)
   - No parser warnings in console
   - Chat session remains usable after the block
8. **Regression check**: verify chatglm/kimi/qianwen/wrtn still function (they remain on the shared `openai_compat_sse` row; the only expected change is their envelope_template hash is unchanged from PART 0 baseline). If chatglm is the easiest of the 4 to exercise, use it as the regression probe — the others require specialized test accounts.
9. **DONE services regression**: chatgpt, claude, genspark, blackbox, qwen3, grok — all show warnings correctly.

## Test Log Protocol (Phase 6 impl journal)

Per `apf-warning-impl/references/test-log-templates.md`, inject temporary markers:

```cpp
bo_mlog_info("[APF_WARNING_TEST:huggingface] envelope=%s http1_size=%zu h2_end_stream=%d",
             lookup_key.c_str(), http1_response.size(), sd->h2_end_stream);
```

Remove after verification (Phase 7 release build). The `lookup_key` should resolve to `huggingface_sse` post-migration; `http1_size` should be around 300-400 B depending on warning text length.

## NOT NEEDED

- **Sub-agent orchestration**: once #454 lands, Phase 5 is doable directly from the result by filling in the `TBD(#454)` placeholders in `services/huggingface_frontend.md` §2-§6 and updating this document's §3 (separator + Content-Type). No discussion-review needed.
- **Phase 1 HAR re-capture**: the 2026-04-14 09:59 etap.log trail already provides the DB row state, path, h2 params. Only the response wire format needs capture (which is what #454 provides).
- **Phase 2 re-analysis**: this design IS the Phase 5 output for huggingface.
- **C++ code changes**: pure DB migration.

## Expected outcome after Phase 6

HuggingFace moves **BLOCK_VERIFIED-but-warning-invisible → DONE** with Option A delivering a visible warning inside the chat bubble. This is the **10th service to reach DONE status** (after chatgpt, claude, genspark, blackbox, qwen3, grok + deepseek/v0/github_copilot from the same Phase 6 window).

**Net pipeline impact**: if the Phase 6 window applies all 4 services (deepseek + v0 + github_copilot + huggingface) in a single DB transaction, the DONE count moves from 6 → 10 (+67%). This is the largest single-cycle DONE-count jump the pipeline has ever had.

## Open questions (fill when #454 lands)

1. **Separator**: `\n` vs `\n\n` — confirm from captured wire format.
2. **Content-Type**: `text/event-stream` vs `application/x-ndjson` — confirm from response headers.
3. **Token field semantics**: `stream.token` is the per-token delta. Confirm whether HF chat-ui REPLACES displayed text with each token (cumulative) OR APPENDS (delta). If cumulative, the `stream` event must carry the full warning text (already the case in our template). If delta, the single `stream` event above is equivalent because it carries the full text in one shot.
4. **Which `type` values are mandatory**: is the leading `status:started` required, or does HF render directly from `stream` events? If not required, the envelope can be trimmed to 3 events.
5. **Post-block chat reusability**: after a blocked prompt, can the user type a new prompt in the same conversation UUID, or does the conversation-level `finalAnswer` lock the session? (Same concern as deepseek's WIP→FINISHED transition.)
6. **Markdown vs plain text**: confirm which markdown features HF's renderer supports (marked / markdown-it). Our warning should be plain-text-safe but can leverage markdown if present.

Each of these is a **single token** in the envelope template once #454 answers it — no structural redesign needed.

## Source

- `services/huggingface_frontend.md` (cycle 37 PRE-CAPTURE SKELETON, 2026-04-15 20:03 KST)
- 2026-04-14 09:59:52-53 etap.log blocked trail (service=huggingface, keyword=\d{6}-\d{7}, response_type=openai_compat_sse, h2_mode=2, h2_end_stream=1)
- Cycle 21 L2 SSH extraction (openai_compat_sse envelope shared by 5 services, 342B)
- Cycle 36 show_stats sample (huggingface: 86 lifetime requests) — `references/apf-cli-commands.md` §5
- `github.com/huggingface/chat-ui` (open-source Svelte frontend: `src/lib/types/MessageUpdate.ts`, `src/routes/conversation/[id]/+page.svelte`, `src/lib/utils/messageUpdates.ts`)
- `services/envelope_audit_2026-04-15.md` §1 (ESCAPE2 semantics — single `{{MESSAGE}}` correct for single-nesting context)
- `services/phase6_combined_migration_2026-04-15.sql` (target for PART 1D addition once #454 confirms)
- `functions/ai_prompt_filter/ai_prompt_filter.cpp:1249-1328` (render_envelope_template — content-type agnostic)
- `functions/ai_prompt_filter/ai_prompt_filter.cpp:1602-1677` (generate_block_response — pure DB lookup)

## Promotion to DESIGN_LOCKED

When #454 result arrives, promote this document by:

1. Replace `§3 "Content-Type"` TBD with the observed header value.
2. Replace `§3 "Event separator"` TBD with the observed separator.
3. Verify the proposed envelope's 4 event types match the wire format (if additional mandatory events appear, add them).
4. Update `§12 Open questions` — mark resolved items.
5. Fill in `services/huggingface_frontend.md` §12 TBD checklist.
6. Change this document's status banner from `DESIGN_SKELETON (awaiting #454)` to `DESIGN_LOCKED`.
7. Extend `phase6_combined_migration_2026-04-15.sql` with the PART 1D + PART 4D blocks above.
8. Commit + push.

Estimated promotion effort: **~15 minutes** once the result is in hand.
