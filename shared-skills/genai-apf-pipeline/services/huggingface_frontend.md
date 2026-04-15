# huggingface Frontend Profile — Phase 4 (PRE-CAPTURE skeleton, awaiting #454)

**Status**: **SKELETON** — drafted cycle 37 (2026-04-15 20:03 KST) while `#454_huggingface-frontend-inspect` is still in flight (+141 min from push). This document consolidates everything we already know from (1) cycle 21 L2 intel, (2) 2026-04-14 09:59 historical blocked trace in etap.log, (3) cycle 36 show_stats evidence, (4) public `github.com/huggingface/chat-ui` source code. When #454 lands, fill in the `TBD(#454)` placeholders and promote `STATUS: SKELETON` to `STATUS: FRONTEND_PROFILED` or similar.

**Source files**:
- `results/454_huggingface-frontend-inspect_result.json` — **not yet received**
- Cycle 21 L2 SSH envelope size extraction (openai_compat_sse=342B, shared by 5 services)
- 2026-04-14 09:59:52-53 etap.log historical blocked trail (the `#392_check-block-kimi-200ok` test run that accidentally captured HF wire data)
- Cycle 36 show_stats sample showing `huggingface: 86` lifetime requests
- `github.com/huggingface/chat-ui` (open source Svelte frontend)

---

## 1. Service Context

| Field | Value | Source |
|-------|-------|--------|
| Main origin | `https://huggingface.co` | 2026-04-14 etap.log Page load request trail |
| Chat URL | `https://huggingface.co/chat/conversation/{uuid}` | 2026-04-14 09:59:53.673 etap.log |
| API endpoint | **`POST /chat/conversation/{uuid}`** (same host, not a subdomain) | 2026-04-14 09:59:53 etap.log `service=huggingface stream=31 method=POST` |
| HTTP version | **h2** (is_http2=1) | 2026-04-14 etap.log `http2=1` |
| Host (CORS) | **SAME-ORIGIN** (`huggingface.co` → `huggingface.co/chat/...`) | No cross-origin — no explicit CORS headers needed |
| Framework | **Svelte** (NOT React/Next.js) | `github.com/huggingface/chat-ui` repo |
| Bundler | Vite | HF chat-ui repo |
| Routing | SvelteKit (CSR + SSR hybrid) | HF chat-ui repo |
| Current `response_type` | **`openai_compat_sse`** (shared row, 342B envelope) | Cycle 21 L2 SQL extraction + 2026-04-14 etap.log `response_type=openai_compat_sse` |
| Current verdict | **BLOCK_VERIFIED but WARNING INVISIBLE** | 2026-04-14 blocked trace + 0 user-visible warning reports |

**Critical L2 cross-check** (verified cycle 21 + cycle 36): the existing `ai_prompt_services` row for `huggingface` uses `response_type=openai_compat_sse`, **which is a row SHARED with 4 other services** (chatglm, kimi, qianwen, wrtn — 5 identical rows in `ai_prompt_response_templates`). Fix path MUST create a new huggingface-specific row to avoid affecting the other 4 services.

---

## 2. Request Body Shape (POST /chat/conversation/{uuid})

**Status**: TBD(#454) — need the actual JSON body from DevTools Payload tab.

**Pre-hypothesis** (from HF chat-ui source `src/routes/conversation/[id]/+server.ts`):

```json
{
  "inputs": "<user prompt text verbatim>",
  "id": "<client-generated message UUID>",
  "is_retry": false,
  "is_continue": false,
  "web_search": false,
  "tools": [],
  "files": []
}
```

The `inputs` field is the text that APF matches keyword rules against. The `id` field is the assistant-message UUID that the response stream will populate.

**Action for #454 verification**: Capture a real POST body via DevTools Payload tab, compare against this pre-hypothesis. If the schema matches, pre-hypothesis holds. If different, replace this section with the real shape.

---

## 3. SSE Wire Format

### 3.1 Pre-hypothesis from HF chat-ui source

HF chat-ui uses **type-tagged JSON-lines streaming** (NOT SSE `data:` prefix, NOT OpenAI `choices[].delta.content`). The response body is a sequence of JSON objects separated by newline, each with a `type` discriminator field.

Event types (from `src/lib/types/MessageUpdate.ts` in the public repo):

| Type | Schema | Purpose |
|------|--------|---------|
| `status` | `{"type":"status","status":"started"\|"pending"\|"error"\|"finalAnswer"}` | Conversation state machine |
| `stream` | `{"type":"stream","token":"<text delta>"}` | Cumulative or delta text (verify which) |
| `finalAnswer` | `{"type":"finalAnswer","text":"<full text>","interrupted":false}` | Completion marker |
| `title` | `{"type":"title","title":"<generated conv title>"}` | Side-channel for conversation title |
| `webSearch` | `{"type":"webSearch","messageType":"update","message":"..."}` | Web search progress |
| `file` | `{"type":"file","name":"...","sha":"..."}` | File attachment |

**Status**: TBD(#454) — verify via test PC capture. The `stream` token may be cumulative (replace displayed text) OR delta (append to displayed text). Need wire capture.

**Separator**: TBD(#454) — probably `\n` (JSON-lines) OR `\n\n` (SSE-style), not confirmed without capture.

**Content-Type**: TBD(#454) — probably `text/event-stream` OR `application/x-ndjson`.

### 3.2 Current openai_compat_sse envelope (shared by 5 services)

From cycle 21 L2 extraction — openai_compat_sse is 342B:

```
HTTP/1.1 200 OK
Content-Type: text/event-stream; charset=utf-8
Cache-Control: no-cache
Content-Length: 0

data: {"choices":[{"delta":{"content":"{{MESSAGE}}"},"index":0,"finish_reason":null}]}

data: {"choices":[{"delta":{},"index":0,"finish_reason":"stop"}]}

data: [DONE]

```

**This is the OpenAI standard SSE format** — `choices[].delta.content` delta events + `[DONE]` sentinel. **It does NOT match huggingface chat-ui's type-tagged schema.** HF's Svelte parser at `src/routes/conversation/[id]/+page.svelte` checks `JSON.parse(line).type` and skips anything missing a `type` field. Therefore the current envelope's `{"choices":[...]}` events are silently discarded → **blank assistant bubble** (what users see).

**This is the root cause** documented in cycle 21 and waiting for #454 to definitively verify.

### 3.3 Proposed envelope for huggingface_sse (Phase 5 preview)

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

**Estimated size**: ~260 B raw template + `{{MESSAGE}}` expansion = ~340B with a 50-80B warning text. Well under any h2 ceiling.

**Placeholder note**: `{{MESSAGE}}` (single `json_escape`) is correct here because the text is embedded at single JSON nesting level (inside `"token":"..."` and `"text":"..."`). ESCAPE2 is NOT needed (consistent with envelope_audit_2026-04-15.md findings).

**Separator convention**: TBD(#454). If HF frontend parses JSON-lines with `\n` separator, use `\n`. If it uses `\n\n` SSE-style, use `\n\n`. Verify before committing to the template.

---

## 4. Chat Bubble DOM

**Status**: TBD(#454) — need DOM snapshot from test PC.

**Pre-hypothesis** (from HF chat-ui Svelte components):
- Outer container: `<div class="... chat-message ...">` — Svelte-compiled class names (hash suffixes)
- Assistant message body: `<div class="prose ...">` (likely Tailwind prose class)
- Markdown rendered to HTML via `marked` or `markdown-it` (HF chat-ui uses marked)

**Implication for Option A**: Since HF renders markdown, the APF warning text can use markdown formatting (bold, code spans, emoji). Pure text also works.

---

## 5. Error UI

**Status**: TBD(#454) — need DevTools Offline or fetch-override capture to see the native error UI.

**Pre-hypothesis** (from HF chat-ui Svelte error handling):
- On fetch/stream parse error, HF chat-ui shows a toast notification using Svelte's built-in toast system
- Toast text is i18n'd from `messages/{lang}.json` bundles at compile time
- **Similar to DeepSeek / GitHub Copilot pattern** — static i18n error text, doesn't read response body

**Implication**: Options B (HTML body replace) and C (JS error banner populate) likely BLOCKED. Option A (SSE stream injection) is the only reliable path.

---

## 6. CSP Analysis

**Status**: TBD(#454) — need CSP header from `huggingface.co/chat` document response.

**Pre-hypothesis**: HF uses moderate CSP. Inline scripts may be blocked (Svelte compiles to external bundles), but DOM additions via APF envelope body are fine (same argument as DeepSeek/Copilot — CSP applies to the document response, not to fetch responses parsed as `text/event-stream`).

---

## 7. Warning Delivery Options — 5-way Verdict Matrix

| # | Option | Verdict | Rationale |
|---|--------|---------|-----------|
| **A** | **SSE stream injection** | **✅ STRONG (pre-hypothesis)** | type-tagged JSON-lines schema is simple (~4 events); Svelte parser reads `type` field + `token`/`text` payload. Replace envelope with matching schema = visible warning bubble. **VERIFY via #454.** |
| B | HTTP body HTML replacement | ❌ BLOCKED (pre-hypothesis) | Svelte error handler shows static i18n toast, ignores response body. Mirrors DeepSeek/Copilot pattern. |
| C | JS error toast populate | ❌ BLOCKED (pre-hypothesis) | Svelte-compiled toast text is in compile-time i18n bundles, no external injection point. |
| D | DOM direct inject | ⚠️ PARTIALLY VIABLE (initial-load only) | Can prepend banner div to `/chat` document HTML before SvelteKit hydrates, BUT SvelteKit rehydration removes it; CSR navigation never re-fetches document. |
| E | Block page substitution | ❌ BLOCKED (intra-session), ⚠️ POSSIBLE (initial load only) | Same CSR constraint — SvelteKit never re-fetches /chat HTML after pushState. |

---

## 8. Recommended Path

**Primary: Option A — SSE stream injection with `huggingface_sse` envelope.**

Rationale: HF chat-ui uses type-tagged JSON-lines streaming that is arguably simpler than DeepSeek's JSON-Patch format and only slightly more complex than GitHub Copilot's 2-event SSE schema. Matching APF envelope to HF schema is a DB-only migration matching the patterns for the other Phase 6 services.

**Migration approach**: INSERT a new `(service_name='huggingface', response_type='huggingface_sse')` row in `ai_prompt_response_templates`, UPDATE `ai_prompt_services` to switch huggingface's `response_type` from `openai_compat_sse` to `huggingface_sse`. **Do NOT modify the existing `openai_compat_sse` row** — chatglm/kimi/qianwen/wrtn still depend on it. (If ANY of those 4 services later need the same Svelte-schema fix, they each get their own dedicated row.)

**Secondary (optional): Option D — initial-load banner.**

For a first-time session disclaimer, APF can inject a banner div into the `/chat` document HTML before SvelteKit mounts. Combine with Option A for chat-level warnings.

**Skip**: Options B, C, E — likely blocked by Svelte's compile-time i18n + CSR navigation pattern.

---

## 9. Phase 5 Implementation Hand-Off (preview)

Full design will be in `services/huggingface_design.md` when #454 verifies the pre-hypothesis.

Key parameters:

- **APF match rule**: existing — `domain=huggingface.co` `path=/chat/conversation/` (verified in 2026-04-14 historical trace, currently functional)
- **Trigger**: `body.inputs` matches APF keyword rules (confirmed 2026-04-14: `keyword=\d{6}-\d{7}, category=ssn` matched)
- **Replacement**: synthesize JSON-lines body with status-started + stream(warning) + finalAnswer(warning) + status-finalAnswer events
- **Status**: 200 (NOT 403)
- **Content-Type**: `text/event-stream` OR `application/x-ndjson` (TBD)
- **Separator**: `\n` OR `\n\n` (TBD)
- **CORS**: same-origin (no explicit headers needed — consistent with envelope_audit_2026-04-15.md §2)
- **h2 attributes**: current `h2_mode=2, h2_end_stream=1, h2_goaway=0, h2_hold_request=1` (from 2026-04-14 etap.log — no change needed)
- **Pre-check**: `etapcomm ai_prompt_filter.validate_template huggingface_sse` (cycle 31 tool) + `etapcomm ai_prompt_filter.test_keyword '<scenario text>'` (cycle 35 tool)

---

## 10. Comparative Notes

| Service | API format | Current status | Option A | Notes |
|---------|-----------|-----------------|----------|-------|
| **huggingface** (#454 pending) | **JSON-lines type-tagged** (pre-hypothesis) | BLOCK_VERIFIED, warning invisible | ✅ STRONG (pre-hyp) | Shares envelope row with chatglm/kimi/qianwen/wrtn; must INSERT dedicated row |
| github_copilot (#453) | SSE simple 2-event schema | Phase 5 designed | ✅ STRONG | Simpler than HF; CORS required (cross-origin) |
| deepseek (#451) | SSE JSON-Patch with path inheritance | Phase 5 designed | ✅ STRONG | More complex schema; shared 500B h2 ceiling with HF |
| gemini3 (#452) | single POST batchexecute | phase5_schema_debug_required | ❌ | wrb.fr envelope; Strategy D |
| v0 (#447) | streaming + non-SSE | Phase 5 designed (f+h pair) | ❌ | Unique no-error-UI pattern |

**Pipeline impact**: huggingface would **join deepseek, v0, github_copilot** in the "Option A ready" bucket, making the Phase 6 DB window **four services** instead of three. Suggest extending `phase6_combined_migration_2026-04-15.sql` with a PART 1D section for huggingface once #454 confirms the pre-hypothesis and the final envelope shape is determined.

---

## 11. Evidence Files

- `results/454_huggingface-frontend-inspect_result.json` — **not yet received**
- `results/files/454/*` — **not yet received**
- `local_archive/cycle20_l2_intel_2026-04-15.md` — cycle 21 L2 SSH envelope extraction
- `local_archive/pipeline_state.json` cycle 36 — show_stats sample confirming huggingface=86 lifetime requests

## 12. TBD Checklist (fill when #454 lands)

- [ ] Real `POST /chat/conversation/{uuid}` body JSON (section 2)
- [ ] Real wire format capture — confirm type-tagged, separator, content-type (section 3.1)
- [ ] Chat bubble DOM selectors (section 4)
- [ ] Error UI DOM evidence — toast or banner, static i18n confirmation (section 5)
- [ ] CSP header contents (section 6)
- [ ] Option A ✅ / ❌ final verdict vs pre-hypothesis (section 7)
- [ ] Finalize `huggingface_sse` envelope template (section 3.3)
- [ ] Add PART 1D to `phase6_combined_migration_2026-04-15.sql` (section 9)
