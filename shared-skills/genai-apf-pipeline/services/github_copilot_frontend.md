# github_copilot Frontend Profile — Phase 4 (NEEDS_ALTERNATIVE pathfinding)

**Source**: `results/453_github-copilot-frontend-inspect_result.json` (test PC, 2026-04-15 18:25 KST)
**Captured by**: test PC desktop-commander, ~40min execution across multiple /loop cycles
**Login state**: `still_logged_in` (jhee-planty, Copilot subscription active, default model `claude-haiku-4.5`)
**Supersedes**: previous capture from 2026-04-02 (Task #15x) — kept in git history

> Phase 4 verdict: **FRONTEND_PROFILED — Option A (SSE injection) HIGHLY VIABLE.**
> github_copilot uses standard SSE with a 2-event-type schema simpler than DeepSeek's. Joins deepseek in the "Option A works cleanly" bucket. Recommended Phase 5 = SSE envelope replacement; Phase 6 = swap `copilot_403` → new `copilot_sse` envelope.

## 1. Service Context

| Field | Value |
|-------|-------|
| Main origin | `https://github.com` |
| Chat URL | `https://github.com/copilot` (initial) → `https://github.com/copilot/c/{conversationUuid}` (after first message, via React Router pushState) |
| API host | **`api.individual.githubcopilot.com`** (separate cross-origin host) |
| API endpoint | `https://api.individual.githubcopilot.com/github/chat/threads/{threadId}/messages` |
| HTTP version | h2 |
| Method | `POST` |
| Status (success) | 200 |
| Request body type | `application/json` |
| **Response Content-Type** | **`text/event-stream`** ← critical |
| CORS preflight | `OPTIONS` precedes the POST (visible as duplicate row in DevTools Network) |
| Initiator | `github.githubassets.com/assets/packages/fetch-patch/fetch-patch.ts:11` (live `window.fetch` wrapper — interceptable) |
| Framework | React Router (development build) + primer-react (Banner/Buttons) + custom React + CSS Modules (`<Module>-module__<name>__<hash>`) |
| Bundler | Webpack or Vite with content-hashed CSS class names |
| Routing | Pure CSR React Router pushState — `is_document_request: false` for all subsequent navigations |
| `#__next` | does NOT exist — NOT a Next.js app router |

**Critical L2 cross-check** (from cycle 20 intel + matched by #453): the existing DB row for `github_copilot` correctly classifies the API host. APF detect_service is firing on the right host.

```
service_name    domain_patterns                    path_patterns       response_type
github_copilot  api.individual.githubcopilot.com   /github/chat/       copilot_403
```

## 2. Request Body Shape (POST /messages)

JSON body fields (verbatim from #453):

```json
{
  "responseMessageID": "<client-generated UUID>",
  "parentMessageID": "<threading parent UUID>",
  "content": "<user prompt text verbatim>",
  "intent": "conversation",
  "mode": "assertive",
  "model": "claude-haiku-4.5",
  "currentURL": "https://github.com/copilot",
  "references": [],
  "context": [],
  "confirmations": [],
  "customInstructions": [],
  "mediaContent": [],
  "skillOptions": { "deepCodeSearch": false },
  "streamJz_or_stream": true,
  "requestTrace": false
}
```

**Threading model**: `responseMessageID` is the client-allocated UUID for the assistant message that THIS POST will produce. `parentMessageID` is the prior assistant message in the thread (or null/UUID for first turn). The same endpoint is used for both first and subsequent messages — no separate `/start` vs `/continue` paths. The `streamJz_or_stream` field is an SSE enable flag (boolean).

**Critical for Option A**: APF can read `responseMessageID` from the request body and reflect it in the response `complete.id` (or `complete.parentMessageID`) to maintain the React app's threading state.

## 3. SSE Wire Format (Phase A capture)

**Captured via `window.fetch` override** — GitHub's `fetch-patch.ts` uses live `window.fetch` reference at call time, so a JS `window.fetch = (orig => async (...args) => { const r = await orig(...args); /* clone + read */ return r; })(window.fetch)` interceptor was honored. (Compare: Google's BardChatUi uses a captured fetch reference, blocking this technique on Gemini.)

**Captured stream verbatim** (373 bytes total):

```
data: {"type":"content","body":"ready"}

data: {"type":"complete","id":"95bc484f-2bf0-4cb7-b7be-ca2621b92f7b","parentMessageID":"fc075f1a-22a7-44d2-817b-3209728bc584","model":"","turnId":"","createdAt":"2026-04-15T09:16:31.627141074Z","references":[],"role":"assistant","intent":"conversation","copilotAnnotations":{"CodeVulnerability":[],"PublicCodeReference":[]}}

```

**Schema breakdown**:

| Event type | Schema | Notes |
|------------|--------|-------|
| `content` | `{"type":"content","body":"<text_delta>"}` | Body is **cumulative** text since last content event. Client appends to displayed bubble. |
| `complete` | `{"type":"complete","id":"<msgUuid>","parentMessageID":"<parentMsgUuid>","model":"<string>","turnId":"<string>","createdAt":"<ISO8601>","references":[],"role":"assistant","intent":"conversation","copilotAnnotations":{"CodeVulnerability":[],"PublicCodeReference":[]}}` | Required for bubble finalization. `model` and `turnId` are observed as empty strings. `createdAt` is RFC3339 nanosecond precision. `copilotAnnotations` is GitHub's code-safety annotation block (always empty for non-code responses). |

**Critical observations**:
- **Classic SSE format** (`data: <json>\n\n`) — NO `event:` lines. This is why Chrome DevTools' EventStream tab renders empty (it requires `event:` lines).
- **Only 2 event types** (content + complete) — much simpler than DeepSeek's 4 named events + JSON-Patch ops with path inheritance.
- **Single `content` event suffices for short responses** — Copilot does not enforce many small chunks; a single content event with the full text is acceptable.
- **CORS headers must be present** in the response (separate cross-origin from github.com): `Access-Control-Allow-Origin: https://github.com` + `Access-Control-Allow-Credentials: true` are required, otherwise the browser rejects the response before the React app sees it.

## 4. Chat Bubble DOM (Phase C)

Containers found (CSS Modules `<Module>-module__<className>__<hash>`):
- `div.ImmersiveChat-module__messageContent__FCvt1` — outer immersive chat message wrapper
- `div.message-container + div.ChatMessage-module__chatMessage_*` — per-message container
- `div.ChatMessage-module__content__haI0H` — message body content node

Stable partial selectors (hash-tolerant):
```
[class*="ImmersiveChat-module__messageContent"]
[class*="ChatMessage-module__chatMessage"]
[class*="ChatMessage-module__content"]
.message-container             // unhashed static class
```

**Markdown rendering**: Copilot renders markdown as HTML inside `message-container` — fenced code blocks (with dedicated `View file: X.py` button), ordered/unordered lists (`<li>` with bullets), syntax-highlighted `<code>` spans. Feedback row (Good response / Bad response / Copy / Retry with Claude Haiku 4.5 / Retry with model) appears as primer-react `IconButton` row below each assistant message.

**Implication for Option A**: Since Copilot renders the `body` text as markdown, the APF warning text can use markdown formatting (bold, code spans, links) for richer presentation. Pure text also works.

## 5. Error UI (Phase B — DevTools fetch override returning 500 + empty body)

**Method used**: Console fetch override returning a synthesized `Response` with `status=500` and empty body, gated on URL matching `/messages`. This was more surgical than DevTools Offline toggle or Block URL — same effect, no ambient noise.

**Result UI**:

> **Inline primer-react Banner** rendered below the user message with:
>   - text: *"I'm sorry but there was an error. Please try again."*
>   - warning icon
>   - retry button

**Critical finding**: Banner text is **STATIC i18n** — confirmed by returning empty body → generic text appeared regardless. The React error handler does NOT read the response body for the banner text.

**DOM evidence**:
- `div.BannerDescription` — Copilot's error message text node (static i18n content)
- `div.prc-Banner-BannerContent-LraS2` — primer-react Banner content wrapper (hashed class)
- `div.prc-Banner-BannerContainer-T-S*` — primer-react Banner outer container (hashed class)
- `BannerDescription` is populated by React on render, not by mutation; the text is imported from a locale bundle at compile time.

**Legacy GitHub error infrastructure** (PRESENT but UNUSED by Copilot):
- `div#js-stale-session-flash.stale-session-flash` — legacy session expiry flash, EXISTS in DOM, NOT used by Copilot Chat
- `div#ajax-error-message.ajax-error-message.flash.flash-error` — legacy XHR error flash, EXISTS but EMPTY text, NOT used by Copilot Chat

→ **Option C (populate js-flash from APF body) BLOCKED** — Copilot's error UI is React-rendered primer-react Banner with hardcoded i18n text, NOT the legacy `.flash` infrastructure.

## 6. CSP Analysis (Phase D)

**Length**: 3768 bytes for `github.com/copilot` document response.

| Directive | Value |
|-----------|-------|
| `script-src` | `github.githubassets.com` (host-allowlist only) |
| `script-src` nonce | NO |
| `script-src` strict-dynamic | NO |
| `script-src` unsafe-inline | NO |
| `script-src` unsafe-eval | NO |
| `script-src` self | NO — only `github.githubassets.com` host allowlisted |
| `connect-src` | includes `*.githubcopilot.com` (must — otherwise the messages POST would be blocked) |

**Verdict**: HOST-BASED allowlisting. Any inline `<script>` or non-allowlisted host is blocked. **Non-script DOM additions (text, divs, spans, attributes) are NOT constrained by `script-src`.** Style-src may be host-restricted — use inline style attributes sparingly.

**Critical insight**: Since APF operates at the HTTP transport layer, **CSP is largely IRRELEVANT to envelope/body replacement**. The browser trusts what APF serves because APF *IS* the network transport, and the CSP applies to the document response, not to fetch responses parsed as `text/event-stream`. As long as the response body contains valid SSE (no inline scripts, no HTML attributes), CSP is a non-issue for Option A.

**Comparison**: Less strict than Gemini #452 (nonce + strict-dynamic) but still blocks inline script. Same overall shape as v0 #447.

## 7. Warning Delivery Options — 5-way Verdict Matrix

| # | Option | Verdict | Rationale (1-line) |
|---|--------|---------|---------------------|
| **A** | **SSE stream injection** | **✅ HIGHLY VIABLE** | text/event-stream with simple 2-event schema; APF can synthesize content+complete events containing warning text; React renders as normal assistant bubble |
| B | HTTP body HTML replacement | ❌ BLOCKED | React error handler ignores body — empty 500 → generic banner text |
| C | JS error banner populate | ❌ BLOCKED | primer-react Banner uses hardcoded i18n at compile time, no external string injection point |
| D | DOM direct inject | ⚠️ PARTIALLY VIABLE (initial load only) | Can prepend banner div to `/copilot` document HTML before React mounts, BUT React rehydration removes it; CSR navigation never re-fetches document, so warning shows only on initial load |
| E | Block page substitution | ❌ BLOCKED (intra-session), ⚠️ POSSIBLE (initial load only) | Same CSR constraint as v0 #447; SPA never re-fetches /copilot HTML after pushState navigation |

## 8. Recommended Path

**Primary: Option A — SSE stream injection.**

The ONLY option that reliably delivers a user-visible warning bubble on EVERY Copilot chat interaction, without page reload, without breaking the SPA. Schema is **simpler than DeepSeek's JSON-Patch format** — just 2 event types with flat JSON. APF already handles SSE envelope replacement for DeepSeek; extending to Copilot requires a new envelope template but shares the same transport layer.

**Secondary (optional): Option D — initial-load banner.**

For a first-time session disclaimer (e.g., "Reminder: you are subject to corporate usage policy"), APF can inject a banner div into the `/copilot` document HTML before React mounts. Combine with Option A for chat-level warnings.

**Skip**: Options B, C, E — blocked or only marginally viable.

## 9. Phase 5 Implementation Hand-Off (preview)

Full design in `services/github_copilot_design.md`. Key parameters:

- **APF match rule**: existing — `domain=api.individual.githubcopilot.com` `path=/github/chat/` (already correct in DB)
- **Trigger**: `body.content` matches APF_SENSITIVE patterns
- **Replacement**: synthesize SSE body with **content** event (warning text) + **complete** event (with reflected `parentMessageID` from request body)
- **Status**: 200 (NOT 403 like current copilot_403)
- **Content-Type**: `text/event-stream`
- **CORS**: must preserve `Access-Control-Allow-Origin: https://github.com` + `Access-Control-Allow-Credentials: true` from upstream
- **id**: `crypto.randomUUID()` for `complete.id`; could also use `responseMessageID` extracted from request
- **createdAt**: `new Date().toISOString()` (millisecond precision is fine; nanosecond as observed is not required)

## 10. Comparative Notes

| Service | API format | Error UI | Option A | Notes |
|---------|-----------|----------|----------|-------|
| **github_copilot** (#453) | **SSE (text/event-stream)** simple 2-event schema | static i18n primer-react Banner | ✅ STRONG | SIMPLEST SSE schema observed so far; CORS preservation required |
| deepseek (#451) | SSE (text/event-stream) JSON-Patch with path inheritance | static i18n "네트워크를 확인…" | ✅ STRONG | More complex schema (named events + {p,o,v} ops); same Option A approach |
| gemini3 (#452) | single POST batchexecute (NOT SSE) | silent fail (5 jserror POSTs) | ❌ | wrb.fr envelope replacement is only marginal path; Strategy D |
| v0 (#447) | streaming + non-SSE | NO error UI at all | ❌ | f+h pair (Option F + H) needed |

**Pipeline impact**: github_copilot **joins deepseek** in the "Option A works cleanly" bucket. **Recommend prioritizing Copilot envelope implementation NEXT** (easier than DeepSeek's JSON-Patch) to quickly bring 2 services to Option-A parity in a single DB-window session.

## 11. Source Evidence Files

- `results/files/453/01_baseline.png` — pre-DevTools Copilot main UI
- `results/files/453/04_console_diag.png` — pre-hydration DIAG output
- `results/files/453/07_visible_page.png` — fully-rendered baseline
- `results/files/453/08_thinking.png` — Phase A response rendered + Network with messages×3
- `results/files/453/11_messages_headers.png` — Headers tab: POST + 200 + text/event-stream
- `results/files/453/14_payload.png` — Payload tab: full JSON request body
- `results/files/453/15_sse_live.png` — second send capture
- `results/files/453/18_error_500.png` — Phase B error UI (primer-react Banner)
- `results/files/453/19_final_state.png` — final snapshot

## 12. Test PC Notes

- Actual execution time: ~40min (vs request spec 10-15min) — extended due to pre-hydration DIAG false positive, mid-session context checkpoint, and DevTools Response tab limitations requiring fetch override fallback
- DevTools EventStream tab shows empty for Copilot SSE because there are no `event:` lines (classic data-only SSE) — use Response tab or fetch override to inspect
- Screenshot 10_messages_headers.png discarded (captured Claude Code window when Chrome lost focus)
