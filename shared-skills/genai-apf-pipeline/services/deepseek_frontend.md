# DeepSeek — Frontend Profile (Phase 4)

> Source: `results/451_deepseek-frontend-inspect_result.json` (2026-04-15 17:18 KST)
> Test PC: autonomous /loop polling, windows-mcp browser automation, logged-in Chrome profile
> Status: **FRONTEND_PROFILED** — Option A (SSE injection) viable, proceed to Phase 5

## Service Context

| Field | Value |
|-------|-------|
| Service | DeepSeek (chat.deepseek.com) |
| URL tested | `https://chat.deepseek.com` (authenticated session) |
| Locale | Korean |
| Framework (inferred) | Next.js SPA (Tailwind + CSS-modules class hashing) |
| CDN | CloudFront (`Via` + `X-Amz-Cf-Id` headers) |
| Server | `a19` |
| CSP | **null** (no Content-Security-Policy header on main document) |
| Bot mitigation | Custom PoW challenge at `/api/v0/chat/create_pow_challenge` (NOT Kasada, NOT Cloudflare) |
| Telemetry | Volcengine (ByteDance) APM + data collection via `gator.volces.com/list`, `apm.volccdn.com/mars-web/apmplus/web/browser.cn.js` — ignore in HAR analysis |

## Primary API Endpoint

```
POST https://chat.deepseek.com/api/v0/chat/completion
Content-Type (req):  application/json
Content-Type (resp): text/event-stream; charset=utf-8
HTTP version:        h2
Remote address:      3.172.21.63:443
Referrer-Policy:     strict-origin-when-cross-origin
HSTS:                max-age=31536000; includeSubDomains; preload
```

**Sibling endpoints observed (not targeted by APF):**
- `/api/v0/chat_session/create` — new chat session creation
- `/api/v0/client/settings?did=<deviceId>&scope=model` — client config
- `/api/v0/client/settings?did=<deviceId>&scope=main` — client config
- `/api/v0/chat/create_pow_challenge` — DeepSeek's own PoW bot mitigation (pass-through)
- `gator.volces.com/list` — Volcengine telemetry (ignore)

## SSE Protocol — Full Reverse-Engineered Schema

Captured from the completion of "What is the capital of France?" (small response, full envelope fits in one capture).

### Wire format

```
event: ready
data: {"request_message_id":1,"response_message_id":2,"model_type":"default"}
event: update_session
data: {"updated_at":1776240175.0825849}
data: {"v":{"response":{"message_id":2,"parent_id":1,"model":"","role":"ASSISTANT","thinking_enabled":false,"ban_edit":false,"ban_regenerate":false,"status":"WIP","incomplete_message":null,"accumulated_token_usage":0,"files":[],"feedback":null,"inserted_at":1776240175.07845,"search_enabled":true,"fragments":[{"id":2,"type":"RESPONSE","content":"The","references":[],"stage_id":1}],"has_pending_fragment":false,"auto_continue":false}}}
data: {"p":"response/fragments/-1/content","o":"APPEND","v":" capital"}
data: {"v":" of"}
data: {"v":" France"}
data: {"v":" is"}
data: {"v":" **"}
data: {"v":"Paris"}
data: {"v":"**."}
data: {"p":"response","o":"BATCH","v":[{"p":"accumulated_token_usage","v":53},{"p":"quasi_status","v":"FINISHED"}]}
data: {"p":"response/status","o":"SET","v":"FINISHED"}
event: update_session
data: {"updated_at":1776240175.498642}
event: title
data: {"content":"France capital Paris"}
event: close
data: {"click_behavior":"none","auto_resume":false}
```

### Named events

| Event | Data shape | Role |
|-------|-----------|------|
| `ready` | `{request_message_id, response_message_id, model_type}` | Session handshake |
| `update_session` | `{updated_at}` OR JSON-Patch ops following | Session state sync |
| `title` | `{content: string}` | Auto-generated chat title |
| `close` | `{click_behavior, auto_resume}` | Stream end marker |

### Unnamed `data:` events = JSON Patch operations

Applied to the **response object** state in client memory.

- Fields: `p` (path, optional), `o` (op, optional), `v` (value, required)
- Ops observed: `APPEND`, `SET`, `BATCH`, `SETLASTIDX`
- Path examples: `response`, `response/status`, `response/fragments/-1/content`, `accumulated_token_usage`, `quasi_status`
- **Path inheritance rule**: A data event with only `{v: ...}` and no `p`/`o` inherits the path+op from the previous explicit patch. This is how DeepSeek streams tokens efficiently — first patch declares `p=response/fragments/-1/content o=APPEND`, subsequent `{v:" of"}`, `{v:" France"}`, ... inherit that append-to-content op.
- **Initialization pattern**: The first content-bearing patch is typically a full-object assignment (`data: {"v":{"response":{...,"fragments":[{...,"content":"The",...}]}}}`) which creates the response object and carries the first token simultaneously.

### Completion markers (any of these finalizes the stream)

1. `data: {"p":"response","o":"BATCH","v":[..., {"p":"quasi_status","v":"FINISHED"}]}`
2. `data: {"p":"response/status","o":"SET","v":"FINISHED"}`
3. `event: close` + `data: {click_behavior, auto_resume}`

## Chat Bubble DOM

| Property | Value |
|----------|-------|
| Container selector | Hashed CSS-modules (e.g. `div._4b8ef8e`, `div._8b6260f`) — no semantic class names |
| Render mode | Markdown parsed client-side; `**bold**` → `<strong>`, emoji rendered |
| Streaming pattern | **APPEND-only** — response object held in memory, message fragment re-rendered as each APPEND patch lands. No full-message swap. |
| State source | `state.response.fragments[-1].content` (string) |

**Key implication**: A single SSE patch that creates the fragments array with the full warning text as `content` is sufficient to render a complete warning message — no need to simulate token-by-token streaming.

## Error UI Profile

| Property | Value |
|----------|-------|
| Text | `네트워크를 확인하고 다시 시도하세요.` (Check your network and try again) |
| Trigger | DevTools Offline toggle (fetch-level failure) |
| Location | **Inline** directly below the user message bubble (NOT toast, NOT modal, NOT bottom banner) |
| Visual | Small grey text + 2 icon buttons (retry + 1 other) |
| DOM class | `DIV.errorNew1` (best guess, semantic prefix `error`) |
| Text source | **Static i18n key**, not read from API response body |
| Retry button | Minified class, not captured precisely |

**Hard constraint**: APF **cannot** inject custom text through this error path — the frontend renders its own fixed string regardless of what APF returns. This rules out **Option C** (JS error panel) definitively.

## Warning Delivery Options — 5-Way Verdict

| Option | Verdict | Rationale |
|--------|---------|-----------|
| **A. SSE stream injection** | ✅ **POSSIBLE (STRONG)** | Protocol fully known, schema permissive, chat-bubble UX placement |
| B. HTTP body HTML swap | ❌ BLOCKED | `fetch()` consumes SSE stream — HTML causes parser error, not navigation |
| C. JS error panel | ❌ BLOCKED | Error UI uses static i18n string, cannot carry APF text |
| D. DOM direct injection | ❌ BLOCKED | APF is network-layer, no DOM access (CSP null is moot) |
| E. Block page substitution | ❌ BLOCKED | `chat.deepseek.com/a/chat/s/<chatId>` is SPA route, completion is fetch not document |

**Winner: Option A — by a landslide.** No fallback needed because A has high confidence and no infrastructure dependencies.

## Console Errors (session diagnostic)

- 6 errors + 3 warnings during the session
- Major sources: Volcengine APM SDK, `collect-rangers-v5.2.11.js`, `create_pow_challenge` failures during Offline mode
- **No Kasada, no Cloudflare bot management** on `chat.deepseek.com` itself — APF pass-through is safe
- PoW challenge is per-request header-based (not TLS-fingerprint-based) — APF does not need to solve it

## Screenshots

Stored at `results/files/451/`:

1. `01_baseline_loggedin.png` — main chat view after login
2. `03_thinking_state.png` — transient thinking/streaming state (minimal for Quick mode + short prompt)
3. `04_response_state.png` — completed assistant reply
4. `05_completion_headers.png`, `06_completion_headers_tab.png` — completion response headers
5. `07_offline_error_ui.png` — error UI triggered by DevTools Offline
6. `08_elements_assistant_bubble.png` — assistant bubble DOM structure
7. `09_console_diag.png` — console errors summary

## Comparison to v0 (#447-448)

| Dimension | DeepSeek | v0 |
|-----------|----------|----|
| SSE protocol readable | ✅ Yes, fully schema'd | ❌ No — JSON bodies ignored |
| State-driven rendering | ✅ `response.fragments[-1].content` | ❌ Black-box Sentry-only error path |
| CSP | None | None (but SPA routes block block-page) |
| Enterprise bot | Custom PoW, pass-through safe | Kasada — reloads cause bot probe iframes |
| Authenticated session | ✅ Stable | ❌ Redirect-to-signin trap |
| **Phase 5 readiness** | **Proceed with high confidence** | NEEDS_USER_SESSION for Option A, or NEEDS_ALTERNATIVE for f+h |

DeepSeek is a significantly cleaner target than v0 or gamma.

## Next steps

1. **Phase 5: `services/deepseek_design.md`** — write the envelope template directly from the captured schema (this file is a direct dependency).
2. **Schema drift monitoring** — add a quarterly task to re-capture a fresh completion response and compare against the saved envelope template (lightweight version-check).
3. **Phase 6 DB migration** — pure envelope update (no C++ changes, no new response_type registration patterns beyond what `chatgpt_sse` / `gamma_sse` already do).

## Source

- Test PC HAR + screenshot bundle: `results/451_deepseek-frontend-inspect_result.json` + `results/files/451/`
- Wire-format capture source: DevTools Network → `/api/v0/chat/completion` → EventStream tab (parsed) + underlying Code editor element value (raw, captured via windows-mcp Snapshot)
- Lesson reused: `local_archive/archived/lessons/deepseek_failures.md` confirmed #315's "HTTP 403+JSON gives visible status code" but the current design supersedes it with the true-SSE approach.
