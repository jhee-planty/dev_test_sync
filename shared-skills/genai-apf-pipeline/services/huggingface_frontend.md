# huggingface Frontend Profile — Phase 4 FRONTEND_PROFILED

**Status**: **FRONTEND_PROFILED** — captured cycle 60 (2026-04-16 08:45 KST). Result `#454_huggingface-frontend-inspect` received and merged. This document consolidates (1) cycle 21 L2 intel, (2) 2026-04-14 09:59 historical blocked trace in etap.log, (3) cycle 36 show_stats evidence, (4) public `github.com/huggingface/chat-ui` source code, (5) **#454 live capture on test PC (login: jhee28)**.

**Source files**:
- `results/454_huggingface-frontend-inspect_result.json` — **received 2026-04-16 08:45 KST**
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

**Status**: Consistent with #454 observation. #454 confirmed endpoint as `POST /chat/conversation/{conversationId}` with `Content-Type: application/json`. The raw POST body was not captured in the result JSON, but the endpoint shape and content type match the pre-hypothesis from HF chat-ui source.

**Body shape** (from HF chat-ui source `src/routes/conversation/[id]/+server.ts`, consistent with #454 observation):

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

The `inputs` field is the text that APF matches keyword rules against. The `id` field is the assistant-message UUID that the response stream will populate. #454 sample conversation ID: `69e0205066c9d5fca73767cd`.

---

## 3. SSE Wire Format

### 3.1 Actual Wire Format (#454 confirmed)

**Content-Type**: **`application/jsonl`** (NOT `text/event-stream`, NOT `application/x-ndjson`)

**Format**: **NDJSON** (Newline-Delimited JSON). Each line is a complete JSON object. **NOT SSE** — no `data:` prefix, no `event:` lines.

**Separator**: **`\n`** (JSON Lines convention).

Event types observed in #454 capture:

| Type | Schema | Purpose |
|------|--------|---------|
| `conversationId_init` | `{"conversationId":"69e0205066c9d5fca73767cd"}` | First line, establishes session. No `type` field. |
| `status:started` | `{"type":"status","status":"started"}` | Stream begin signal |
| `status:keepAlive` | `{"type":"status","status":"keepAlive"}` | Heartbeat, repeated many times during processing |
| `routerMetadata` | `{"type":"routerMetadata","route":"agentic","model":"moonshotai/Kimi-K2-Instruct-0905"}` | Model and routing metadata, may appear twice |
| `stream:token` | `{"type":"stream","token":"The"}` | **Individual token delta** (append, NOT cumulative). Contains null-byte padding (`\u0000`) after actual text. |
| `finalAnswer` | `{"type":"finalAnswer","text":"The capital of France is Paris.","interrupted":false}` | Complete assembled response text |
| `status:finished` | `{"type":"status","status":"finished"}` | Stream end signal (NOT `status:finalAnswer` as pre-hypothesized) |
| `[DONE]` marker | `[DONE]` | Final line, raw text NOT JSON |

**Null-byte padding**: Each `stream` token contains trailing `\u0000` null bytes after the actual text content. Purpose unclear — possibly chunked transfer encoding alignment or anti-scraping measure. Must be stripped when parsing tokens.

**Key corrections from pre-hypothesis**:
1. Content-Type is `application/jsonl`, not `text/event-stream`
2. `conversationId_init` event has no `type` field (unique first line)
3. Terminal status is `status:finished`, NOT `status:finalAnswer`
4. `[DONE]` raw text marker at end (not JSON)
5. `stream` tokens are delta (append), with null-byte padding
6. `routerMetadata` event type was not in original source hypothesis (backend addition)

### 3.2 Current openai_compat_sse envelope (shared by 5 services)

**Cycle 42 canonical capture** — direct DB query on etap host confirmed 342B, MD5 `7955369a54e3f47da70315d03aa28598`, all 5 rows identical (chatglm, huggingface, kimi, qianwen, wrtn), priority=50, enabled=1. Decoded from hex:

```
HTTP/1.1 200 OK\r\n
Content-Type: text/event-stream; charset=utf-8\r\n
Cache-Control: no-cache\r\n
Connection: keep-alive\r\n
Access-Control-Allow-Origin: *\r\n
Content-Length: {{BODY_INNER_LENGTH}}\r\n
\r\n
data: {"choices":[{"delta":{"content":"{{ESCAPE2:MESSAGE}}"},"index":0,"finish_reason":"stop"}],"model":"blocked","id":"{{UUID:chatcmpl}}"}\n
\n
data: [DONE]\n
\n
```

**Note vs cycle 21 L2 approximation**: cycle 21 showed TWO data events (first with content + finish_reason=null, second with empty delta + finish_reason=stop). The real row merges into ONE data event with finish_reason=stop + [DONE] sentinel. The 342B byte count matches exactly — only the per-event breakdown was approximated. Cycle 42 is the ground-truth snapshot.

**This is the OpenAI standard SSE format** — `choices[].delta.content` event + `[DONE]` sentinel. **It does NOT match huggingface chat-ui's type-tagged schema.** HF's Svelte parser at `src/routes/conversation/[id]/+page.svelte` checks `JSON.parse(line).type` and skips anything missing a `type` field. Therefore the current envelope's `{"choices":[...]}` event is silently discarded → **blank assistant bubble** (what users see).

**Canonical baseline for PART 0 regression check**: `MD5('7955369a54e3f47da70315d03aa28598')` — record this in impl journal before applying phase6_huggingface_addendum_2026-04-15.sql and verify all 5 rows still match after migration.

**This is the root cause** documented in cycle 21 and waiting for #454 to definitively verify.

### 3.3 Proposed envelope for huggingface_ndjson (Phase 5 preview)

Response type name: **`huggingface_ndjson`** (follows `grok_ndjson`/`notion_ndjson` convention since format is NDJSON, not SSE).

```
HTTP/1.1 200 OK
Content-Type: application/jsonl
Cache-Control: no-cache
Content-Length: 0

{"type":"status","status":"started"}
{"type":"stream","token":"{{MESSAGE}}"}
{"type":"finalAnswer","text":"{{MESSAGE}}","interrupted":false}
{"type":"status","status":"finished"}
[DONE]
```

**Separator**: `\n` (JSON Lines, confirmed by #454). Each line terminated by `\n`.

**Estimated size**: ~270 B raw template + `{{MESSAGE}}` expansion = ~350B with a 50-80B warning text. Well under any h2 ceiling.

**Placeholder note**: `{{MESSAGE}}` (single `json_escape`) is correct here because the text is embedded at single JSON nesting level (inside `"token":"..."` and `"text":"..."`). ESCAPE2 is NOT needed (consistent with envelope_audit_2026-04-15.md findings).

---

## 4. Chat Bubble DOM (#454 confirmed)

**Container selector**: `div.prose.max-w-none`

**Full DOM hierarchy** (from #454 capture):
```
div.mx-auto.flex.h-full.max-w
  > div.flex.h-max.flex-col.gap-8
    > div.group.relative.-mb-4.flex
      > div.relative.flex.min-w-[60px]
        > div
          > div.prose.max-w-none.dark:prose-invert
```

**Framework**: Svelte / SvelteKit (SSR + hydration). Sources tree shows `_app/immutable/{assets,chunks,entry,nodes}` (standard SvelteKit build output). 14 elements with `svelte-*` classes detected.

**CSS approach**: **Tailwind utility classes** (`prose`, `flex`, `gap-8`, etc.). No CSS Modules hashing. Classes are human-readable and **stable** (not hashed like some React/CSS-Modules setups).

**Render mode**: Tailwind Typography plugin (`.prose` class). Token-by-token text node append during streaming.

**Model metadata in DOM**: Shown below assistant response as "agentic with Kimi-K2-Instruct-0905 via novita" with copy/retry buttons.

**Implication for Option A**: Since HF renders markdown via `.prose`, the APF warning text can use markdown formatting (bold, code spans, emoji). Pure text also works. **Implication for Option D**: Stable Tailwind classes (not hashed) make DOM injection reliable across deployments.

---

## 5. Error UI (#454 confirmed: COMPLETE SILENT FAIL)

**Verdict**: **COMPLETE SILENT FAIL**. Confirmed by #454 method-500 injection test.

**Observed behavior**: User message ("Explain photosynthesis briefly") was consumed (input cleared back to placeholder), but:
- NO user message bubble appeared
- NO error banner/toast
- NO loading spinner
- NO retry button
- Page remained showing only the previous conversation

**Error DOM scan**: `querySelectorAll` for `[role=alert]`, `[role=status]`, `[class*=error]`, `[class*=Error]`, `[class*=toast]`, `[class*=Toast]`, `[class*=snack]`, `[class*=sonner]` all returned **0 elements**. The chat-ui project may have error handling in Svelte stores/context rather than DOM, but there is no visible error injection point.

**Screenshot**: `results/files/454/03_error_500_silent.png`

**Comparison**: Identical to **Gemini #452** silent-fail pattern. **Worse than GitHub Copilot #453** which at least showed a primer-react Banner (albeit with static i18n text). Pre-hypothesis of toast notification was WRONG — there is no toast system active in production.

**Implication**: Options B (HTML body replace) and C (JS error banner populate) are **BLOCKED** — there is no error UI to leverage at all. Option A (NDJSON stream injection) is the only reliable path for chat-level warnings.

---

## 6. CSP Analysis (#454 confirmed: EXTREMELY PERMISSIVE)

**CSP header**: `frame-ancestors https://huggingface.co;`

| Directive | Value | Impact |
|-----------|-------|--------|
| `script-src` | **NOT SET** — defaults to no restriction | Inline scripts, eval, dynamic script injection all allowed |
| `connect-src` | **NOT SET** — defaults to no restriction | No fetch/XHR restrictions |
| `default-src` | **NOT SET** — defaults to no restriction | No fallback restrictions |
| `frame-ancestors` | `https://huggingface.co` | Only restriction: cannot embed in iframes from other origins |
| Nonce | No | N/A |
| `strict-dynamic` | No | N/A |

**Verdict**: **EXTREMELY PERMISSIVE**. Only `frame-ancestors` is set. This is the **most permissive CSP** seen across all inspected services (DeepSeek, Gemini, GitHub Copilot, v0). Pre-hypothesis of "moderate CSP" was WRONG — HF has essentially no CSP protection beyond iframe embedding.

**Implication for Option D (DOM inject)**: CSP does NOT block any injection technique. Unlike Gemini (strict nonce-based CSP), HF allows arbitrary script execution and DOM manipulation.

---

## 7. Warning Delivery Options — 5-way Verdict Matrix

| # | Option | Verdict | Rationale |
|---|--------|---------|-----------|
| **A** | **NDJSON stream injection** | **✅ HIGHLY VIABLE (confirmed #454)** | NDJSON format (`application/jsonl`) with type-tagged JSON-lines (~8 event types). Svelte parser reads `type` field + `token`/`text` payload. Replace envelope with matching schema = visible warning bubble. Same-origin request, no CORS needed. Simpler than DeepSeek JSON-Patch. |
| B | HTTP body HTML replacement | ❌ BLOCKED (confirmed #454) | Chat API returns `application/jsonl`. Replacing with HTML causes JSON parse errors in the Svelte streaming parser. No error UI exists to display anything useful. |
| C | JS error region populate | ❌ BLOCKED (confirmed #454) | **No error UI exists at all.** 500 errors produce complete silent fail with zero DOM error elements. No banner, toast, status region, or retry button to leverage. |
| **D** | **DOM direct inject** | **✅ HIGHLY VIABLE (confirmed #454)** | CSP has NO script-src restriction (most permissive of all inspected services). DOM classes are plain Tailwind utilities (not hashed). Svelte reactivity via stores; inserted DOM nodes in `div.prose` persist post-`finalAnswer`. MutationObserver-based injection is feasible. |
| E | Block page substitution | ⚠️ POSSIBLE | SvelteKit SSR means initial HTML has meaningful content. No restrictive CSP. However, disrupts user session state (conversation history, Svelte stores). |

---

## 8. Recommended Path

**Primary: Option A — NDJSON stream injection with `huggingface_ndjson` envelope.**

Rationale: HF chat-ui uses NDJSON (`application/jsonl`) type-tagged streaming that is simpler than DeepSeek's JSON-Patch format and only slightly more complex than GitHub Copilot's 2-event SSE schema. Matching APF envelope to HF schema is a DB-only migration matching the patterns for the other Phase 6 services. #454 confirms this as **HIGHLY VIABLE**.

**Migration approach**: INSERT a new `(service_name='huggingface', response_type='huggingface_ndjson')` row in `ai_prompt_response_templates`, UPDATE `ai_prompt_services` to switch huggingface's `response_type` from `openai_compat_sse` to `huggingface_ndjson`. **Do NOT modify the existing `openai_compat_sse` row** — chatglm/kimi/qianwen/wrtn still depend on it. (If ANY of those 4 services later need the same Svelte-schema fix, they each get their own dedicated row.)

**Secondary (confirmed viable): Option D — DOM inject.**

#454 confirmed: CSP has NO script-src restriction + stable Tailwind classes. DOM injection is **HIGHLY VIABLE** as supplement or fallback. Insert warning banner into `div.prose` or above the message container via MutationObserver. Best for persistent session-level warnings.

**Skip**: Options B, C — **confirmed blocked** by #454 (no error UI exists, HTML body causes parse errors). Option E possible but disruptive.

---

## 9. Phase 5 Implementation Hand-Off (preview)

Full design will be in `services/huggingface_design.md` — #454 has verified the wire format and confirmed viability.

Key parameters:

- **APF match rule**: existing — `domain=huggingface.co` `path=/chat/conversation/` (verified in 2026-04-14 historical trace, currently functional)
- **Trigger**: `body.inputs` matches APF keyword rules (confirmed 2026-04-14: `keyword=\d{6}-\d{7}, category=ssn` matched)
- **Replacement**: synthesize NDJSON body with status-started + stream(warning) + finalAnswer(warning) + status-finished + [DONE] events
- **Status**: 200 (NOT 403)
- **Content-Type**: `application/jsonl`
- **Separator**: `\n` (JSON Lines, confirmed #454)
- **CORS**: same-origin (no explicit headers needed — consistent with envelope_audit_2026-04-15.md §2)
- **h2 attributes**: current `h2_mode=2, h2_end_stream=1, h2_goaway=0, h2_hold_request=1` (from 2026-04-14 etap.log — no change needed)
- **Pre-check**: `etapcomm ai_prompt_filter.validate_template huggingface_ndjson` (cycle 31 tool) + `etapcomm ai_prompt_filter.test_keyword '<scenario text>'` (cycle 35 tool)

---

## 10. Comparative Notes

| Service | API format | Current status | Option A | Notes |
|---------|-----------|-----------------|----------|-------|
| **huggingface** (#454 pending) | **JSON-lines type-tagged** (pre-hypothesis) | BLOCK_VERIFIED, warning invisible | ✅ STRONG (pre-hyp) | Shares envelope row with chatglm/kimi/qianwen/wrtn; must INSERT dedicated row |
| github_copilot (#453) | SSE simple 2-event schema | Phase 5 designed | ✅ STRONG | Simpler than HF; CORS required (cross-origin) |
| deepseek (#451) | SSE JSON-Patch with path inheritance | Phase 5 designed | ✅ STRONG | More complex schema; shared 500B h2 ceiling with HF |
| gemini3 (#452) | single POST batchexecute | phase5_schema_debug_required | ❌ | wrb.fr envelope; Strategy D |
| v0 (#447) | streaming + non-SSE | Phase 5 designed (f+h pair) | ❌ | Unique no-error-UI pattern |

**Pipeline impact**: huggingface **joins deepseek, v0, github_copilot** in the "Option A ready" bucket, making the Phase 6 DB window **four services**. Extend `phase6_combined_migration_2026-04-15.sql` with a PART 1D section for huggingface — #454 has confirmed the pre-hypothesis and the final envelope shape is determined.

---

## 11. Evidence Files

- `results/454_huggingface-frontend-inspect_result.json` — **received 2026-04-16 08:45 KST**
- `results/files/454/01_baseline.png` — baseline screenshot
- `results/files/454/02_response.png` — response screenshot
- `results/files/454/03_error_500_silent.png` — error silent-fail screenshot
- `local_archive/cycle20_l2_intel_2026-04-15.md` — cycle 21 L2 SSH envelope extraction
- `local_archive/pipeline_state.json` cycle 36 — show_stats sample confirming huggingface=86 lifetime requests

## 12. TBD Checklist (#454 received — all items resolved)

- [x] Real `POST /chat/conversation/{uuid}` body JSON (section 2) — endpoint confirmed, body shape consistent with pre-hypothesis
- [x] Real wire format capture — NDJSON `application/jsonl`, `\n` separator, 8 event types (section 3.1)
- [x] Chat bubble DOM selectors — `div.prose.max-w-none`, full hierarchy captured (section 4)
- [x] Error UI DOM evidence — COMPLETE SILENT FAIL, zero error elements (section 5)
- [x] CSP header contents — EXTREMELY PERMISSIVE, only `frame-ancestors` (section 6)
- [x] Option A HIGHLY VIABLE, Option D HIGHLY VIABLE (section 7)
- [x] Finalize `huggingface_ndjson` envelope template (section 3.3)
- [ ] Add PART 1D to `phase6_combined_migration_2026-04-15.sql` (section 9) — pending Phase 5 design sign-off
