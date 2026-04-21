# v0.dev (v0.app) — Frontend Profile

> Phase 4 deliverable. Captured from request #447 result (2026-04-14).
> **Partial profile**: anonymous session only — Vercel login was not available on test PC.
> An authenticated rerun is recommended for SSE envelope details but Phase 5 design is
> NOT blocked on it (Option E can be designed from current data).

## Service basics

| Field | Value |
|-------|-------|
| service_id | v0 |
| Original host | v0.dev |
| **Current host** | **v0.app** (Vercel rebrand — v0.dev redirects to v0.app) |
| Framework | Next.js (Turbopack build; chunks at `/chat-static/_next/static/chunks/*.js`) |
| HTTP | h2 |
| Bot protection | Kasada (`x-kpsdk-v=j-1.2.308`, `ips.js?KP_UIDz=...`, `/fp` endpoints) |
| Observability | Sentry (`o205439.ingest.us.sentry.io`), Vercel Insights (`/_vercel/insights/view`), OTEL metrics |
| Login required | **YES** for real chat flow (anonymous silently reroutes to login) |

**⚠ APF match rule hazard**: rules matching hostname `v0.dev` exactly will miss v0.app. Verify the
current block rule covers both hosts (or switches to `v0.app`).

## Chat API endpoints

### Primary (APF target)

| Field | Value |
|-------|-------|
| Name | `send` |
| URL | `https://v0.app/chat/api/send` |
| Method | POST |
| APF current behavior (#438) | 200 OK + JSON `{"error":true,"message":"..."}` — v0 frontend **ignores** |

### Siblings observed in the anonymous flow

| Endpoint | Purpose |
|----------|---------|
| `https://v0.app/chat/api/send-site` | v0 site/deployment creation (separate from prompt send) |
| `https://v0.app/chat/api/rate-limit?scope=anon:<ephemeralId>` | anon rate-limit pre-check |
| `https://v0.app/chat/api/integrations?chatId=<chatId>` | integration lookup for new chat id |
| `https://v0.app/api/git/connection?chatId=<chatId>` | git integration init |
| `https://v0.app/api/auth/validate` | session probe |
| `https://v0.app/api/auth/info` | session probe |
| `https://v0.app/api/auth/login?next=/chat&...` | login redirect (fails for anon) |
| `https://v0.app/api/chat/global/daily-model-usage` | quota (auth required) |
| `https://v0.app/api/chat/global/free-fix-with-v0-usage` | quota (auth required) |

### Streaming format

**Not yet captured in a real stream.** The anonymous submit flow is rejected pre-stream by auth,
so the `send` endpoint never produced a genuine assistant reply. For authenticated users, #438
confirmed that when APF matches, the body is `application/json`. Normal operation is likely SSE
or ndjson chunked (TBD).

**TODO (authenticated rerun)**: click `send` row in Network → Preview to capture:
- Content-Type (`text/event-stream` vs `application/x-ndjson` vs `application/json`)
- Transfer-Encoding: chunked
- First 2KB of body to identify envelope shape

## Observed flow (anonymous user)

```
0. User types prompt, Enter
1. Browser navigates to /chat/<newChatId>  (URL visibly changes to v0.app/chat/s4JfHDVOPhL)
2. Chat page renders user message bubble + "Thinking" spinner
3. rate-limit check (scope=anon:<ephemeralId>) — OK
4. auth/validate + auth/info probes — user is unauthenticated
5. Three /api/auth/login fetches — all fail ("Fetch request failed" in DevTools)
6. Frontend silently reroutes page back to /chat (landing page)
7. Prompt text restored into input field. No error text / modal / toast.
8. 20+ console errors + 11 warnings → all captured by Sentry (not user-visible)
9. Final state is indistinguishable from a fresh landing page
```

**Implication**: v0 treats "anonymous submit" as a "honeypot" mode — UI allows typing without
preventing it, but silently fails on server. This means **test PC sessions MUST be kept logged in
to Vercel**, OR APF verdict logic must distinguish "blocked by APF" from "blocked by auth redirect".

## "Thinking" spinner DOM

| Attribute | Value |
|-----------|-------|
| Accessible name | `Thinking` |
| Observed AX role | 단추(button) / 목록 항목(listitem) — spinner is inside a semantic message list element |
| Replacement behavior (anon) | **Abandoned** — page unmounts/reroutes before the stream resolves |
| Replacement behavior (auth, #438) | Never transitions (frontend doesn't handle `{error: true}` bodies) |

**Selector hints to confirm under auth**:
- `[data-sentry-component*='Thinking']` or `[data-testid*='thinking']`
- `role='listitem'` whose textContent is `Thinking`, sibling of the user message bubble
- Next.js + Sentry wraps components → likely `data-sentry-component` attribute

## Native error UI

**DOES NOT EXIST.** Across the full anonymous flow the app NEVER rendered a visible error string.
The only user-perceptible signals are: (a) URL changes back to /chat, (b) input is repopulated.
Everything else is Sentry telemetry invisible to users.

**Implication for APF**: v0 has **no DOM slot** that APF can indirectly trigger by producing an
error-like HTTP response. There is no "error toast" / "error bubble" / "error panel" component
to light up. The frontend reaction to failed network calls is to reroute silently.

→ This rules out Recovery Path C (JS error UI activation) entirely.

## Warning Delivery Options checklist

| Option | Verdict | Rationale |
|--------|---------|-----------|
| **a. SSE/WebSocket stream interception** | **UNKNOWN for auth** / BLOCKED for anon | Needs auth HAR to learn SSE envelope shape. Anonymous flow never opens a stream. Existing #438 attempt (JSON replacement) is already at the stream boundary and frontend ignores it. |
| b. HTTP body HTML replacement | BLOCKED | `/chat/api/send` is JSON/SSE endpoint consumed by `fetch()`. Returning HTML causes a parse error, not a rendered page. This is exactly the current #438 failure class. |
| c. JS error panel usage | BLOCKED | v0 routes JS errors to Sentry (invisible to users). No in-page error console exists. |
| d. Direct DOM injection | BLOCKED | APF operates at HTTP layer; cannot manipulate loaded SPA DOM. |
| **e. Block page substitution** | **POSSIBLE — most promising candidate** | See below. |
| f. Redirect to a dedicated block page (not in original 5) | POSSIBLE (alt) | See below. |

### Option E — Block page substitution (RECOMMENDED PRIMARY)

**Mechanism**: v0 has a well-defined navigation hook — on submit, the browser issues a full
document request that ends up hitting `/api/auth/login` (for anon) or possibly a server-component
fetch for `/chat/<id>`. If APF intercepts **that** request (not `/chat/api/send`) and returns an
HTML document with HTTP 200 + `text/html`, the browser renders it as the new top-level page,
bypassing the SPA entirely.

**Why this works**: the failure already forces a document-level redirect in the anonymous case,
proving the navigation hook exists. We hijack that hook.

**Required work**:
1. Confirm (via authenticated test) that the same document-navigation hook exists: does
   `/chat/<id>` server-render, or is it pure client-side?
2. Add an APF rule matching `host=v0.app AND path-prefix=/chat/` with template_type=html,
   returning a full standalone HTML warning page (NOT a JSON fragment).
3. Template should NOT depend on v0's styling chain (standalone CSS) so it renders even when
   the host page's CSS isn't loaded.

### Option F — Redirect to a dedicated block page (ALT)

**Mechanism**: Since anonymous submits already bounce to the login route via `/api/auth/login`,
APF could force the same redirect for authenticated users by returning an HTTP 302/303 on
`/chat/api/send` pointing to a dedicated `/apf-blocked` page served by Etap itself. The
frontend's existing redirect-handling for auth failures would follow the redirect.

**Caveat**: 302 from a POST /send is unusual — browsers may not follow. **303 is safer**.

## Recommended Phase 5 design options

| Rank | Option | Short summary | Why |
|------|--------|--------------|-----|
| 1 | **e (block page)** | Intercept `/chat/<id>` (and/or `/chat/api/send` with HTML content-type) and return standalone HTML warning page. | Only option whose success depends on network-layer behavior APF already controls. Does not require reverse-engineering v0's SSE envelope. |
| 2 | a (SSE injection, auth only) | Craft a valid SSE event mimicking a v0 assistant token containing the warning text. Frontend renders inside the expected chat bubble. | Cleanest UX — warning appears inside the assistant bubble. Requires authenticated HAR capture first. |

## Key insights

1. **Anonymous flow is a honeypot**: v0 lets you type and pretend to chat while logged out, then
   silently reroutes on submit. Any APF rule that only watches `/chat/api/send` will see a lot of
   never-actually-streamed requests from any test PC where the session expired — it will look
   like the block is working when the frontend is actually just kicking out unauthenticated users.
   **Test PC sessions must be kept logged in** or APF verdict logic must distinguish
   "blocked by APF" from "blocked by auth redirect".

2. **No native error UI means Option E is primary**: Because v0 has no error toast / error bubble
   / error panel, the "make v0's own error UI show the warning" style of approach doesn't work.
   Block-page substitution (return a full HTML document) is the only option that doesn't depend
   on v0 cooperating.

3. **Rebrand in progress**: v0.dev redirects to v0.app. APF block rules matching `v0.dev` exactly
   would miss any request actually hitting v0.app. Verify match pattern covers both.

## Follow-up work

1. **Authenticated rerun** (for SSE envelope capture — Option A fallback path)
2. **Phase 5 design** centered on Option E
3. **Verify APF match rule** covers both `v0.dev` and `v0.app`
4. **Phase 6 implementation**: new `template_type=html` handling in `ai_prompt_filter` may be
   needed if the existing envelope system doesn't support raw HTML document responses

## Screenshots (artifacts)

- `results/files/447/01_baseline.png`
- `results/files/447/02_devtools_network_ready.png`
- `results/files/447/03_after_submit_3s.png`
- `results/files/447/04_thinking_state.png`
- `results/files/447/05_after_18s.png`
- `results/files/447/06_send_request_clicked.png`

## Source

- Request: `requests/447_frontend-inspect-v0.json`
- Result: `results/447_frontend-inspect-v0_result.json`
- Captured by: test-pc (autonomous polling, windows-mcp browser automation)
- Date: 2026-04-14T13:42:00+09:00
