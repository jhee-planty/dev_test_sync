# v0 Phase 5 Design — Option E BLOCKED → Option F primary (303 redirect)

> Phase 5 deliverable. Promoted from `local_archive/v0_design_skeleton_2026-04-14.md`
> on 2026-04-14. Based on #447 frontend-inspect result (anonymous-only profile) and
> direct code inspection of `ai_prompt_filter.cpp` + `ai_prompt_filter_db_config_loader.cpp`.
>
> **2026-04-14 14:30 update** — Option E BLOCKED. See "etap log verdict" section
> below. Path forward pivoted to Option F (303 redirect on `/chat/api/send`) as a
> cheap Phase 6 experiment; if fetch-follow semantics make Option F silent, v0
> transitions to NEEDS_USER_SESSION for Option A (authenticated SSE envelope).

## Context

| Field | Value |
|-------|-------|
| Service | v0 (Vercel v0.dev / v0.app) |
| Current state | BLOCK_ONLY — 200 OK + error JSON ignored by Next.js frontend |
| Primary API | `POST https://v0.app/chat/api/send` (streaming) |
| Framework | Next.js (Turbopack), HTTP/2, Kasada bot protection |
| Observability | Sentry — **all frontend errors invisible to user** |
| Rebrand | v0.dev → v0.app (current APF rule may be outdated) |
| Size budget | ≤500B body (h2_end_stream=2 empirical ceiling) |

## Final option verdicts (post-#447, post-etap-log-2026-04-14-14:30)

| Option | Verdict | Notes |
|--------|---------|-------|
| a. SSE/stream injection | **NEEDS_USER_SESSION** | Frontend ignores JSON bodies on `/chat/api/send` (proven by #438). Needs real SSE envelope — authenticated HAR only. |
| b. HTTP body HTML on `/chat/api/send` | BLOCKED | `fetch()` parse error, not rendered. |
| c. JS error UI activation | BLOCKED | v0 has **no** in-page error UI. All errors → Sentry → invisible. |
| d. Direct DOM injection | BLOCKED | APF is network-layer. |
| e. Block page substitution | **BLOCKED (etap log verified 14:30)** | `/chat/<id>` is CSR pushState. Zero Page load request for `/chat/<id>` in etap log — SPA router handles navigation without top-level fetch. Nothing for APF to intercept. |
| **f. 303 redirect on `/chat/api/send`** | **Phase 6 experiment (low expected yield)** | fetch() auto-follows 303 → delivers HTML body as Response → JS can't navigate the window from fetch. Unlikely to show warning unless v0 has manual redirect handling. Still worth one cheap test. |
| **g. 403 + meta-refresh body on `/chat/api/send`** | **Phase 6 experiment (speculative)** | Return `HTTP/1.1 403 Forbidden` with `Content-Type: text/html` body containing `<meta http-equiv="refresh" url="...">`. JS error path MAY call `location.assign()`. Depends on v0's unknown error recovery hook. |
| **h. Block page on direct `/chat/<id>` document load (reload case)** | **Phase 6 safety net** | On page reload, browser issues a real GET document request to `/chat/<id>`. APF intercepts THAT and returns warning HTML. Does NOT help on initial block, but guarantees warning appears if user reloads. Pair with F/G as defense-in-depth. |
| a. SSE injection (authenticated) | **NEEDS_USER_SESSION** | Cleanest UX but requires Vercel login session to reverse-engineer v0's SSE envelope. |

**Path order (revised after #448)**: **f+h parallel → g experiment → NEEDS_USER_SESSION (Option A)**

- f and h target different scenarios and don't conflict (f = initial block, h = reload).
  Both can be migrated in one DB transaction by using different `path_patterns` wiring.
- If f/g/h all fail in Phase 6 test, v0 transitions to NEEDS_USER_SESSION awaiting
  authenticated HAR for Option A, or classified as PENDING_INFRA in the meantime.

## etap log verdict (2026-04-14 14:30 KST)

While #448 (anonymous DevTools probe) was in flight on the test PC, the APF dev
side verified the SSR-vs-CSR question directly from `/var/log/etap.log` via SSH.
`ai_prompt_filter.cpp:722 on_http2_request` logs every `Accept: text/html`
top-level request as `[APF] Page load request`. Filtering for v0 across the
entire available log history returned **only three distinct path shapes**:

```
2026-04-14 13:36:17.683  v0.dev/
2026-04-14 13:36:17.915  v0.dev/
2026-04-14 13:36:18.103  v0.app/
2026-04-14 13:37:40.189  v0.app/149e9513-.../fp?x-kpsdk-v=j-1.2.308     ← Kasada bot probe iframe
2026-04-14 13:37:46.065  v0.app/149e9513-.../fp?x-kpsdk-v=j-1.2.308     ← Kasada bot probe iframe
2026-04-14 14:19:03.235  v0.dev/                                         ← #448 test PC session start
2026-04-14 14:19:03.365  v0.app/                                         ← #448 (after v0.dev redirect)
```

During the same #448 session, XHR telemetry on `/chat/api/send-site` and
`/_vercel/insights/view` logged `path="/chat/hJ35MSWtyWu"` at 14:20:04, proving
that the SPA **did** navigate the URL to `/chat/hJ35MSWtyWu`. But **no matching
`Page load request` for `/chat/hJ35MSWtyWu` (or any `/chat/<id>`) ever appears
in the log** — neither during this session nor in the entire v0 log history.

**Definitive verdict**:
- `is_document_request: false`
- Next.js router handles `/chat/<id>` via CSR `router.push()` / pushState.
- The only top-level document requests v0 ever issues are the landing root `/`
  and Kasada bot-challenge iframes (`/fp?x-kpsdk-v=...`).
- **Option E has nothing to intercept and cannot work.**

The #448 result, when it arrives, should confirm `is_document_request=false`.
Its handling on arrival is post-hoc verification only — the design is already
pivoted based on this code-ground-truth.

**Update: #448 result arrived at 14:23 and confirmed `is_document_request: false`.**
Chat ID observed: `hJ35MSWtyWu` (same as etap log evidence). Key additional
insights from test PC DevTools inspection:
- Doc filter on Network panel during submit→navigate window: essentially empty
  (only the original v0.app landing doc from page open, already cleared).
- The only RSC fetch during the flow is `/chats?project=draft&_rsc=l5937` —
  this is the **sidebar chat list** (plural `/chats`), not the detail route.
  Zero RSC fetches for `/chat/hJ35MSWtyWu?_rsc=...`.
- v0 renders the new chat detail **entirely from already-loaded JS bundle**
  via React state + `history.pushState()`. Classic Next.js App Router client
  transition pattern.

**Corollary from #448**: pure Option F (303 redirect) is ALSO unlikely to work
because `/chat/api/send` is called via `fetch()`, not `<form submit>`. The
browser will auto-follow the 303 as a GET (for fetch default redirect mode),
deliver the redirected body to the JS code, and the page itself will NOT
navigate. This matches the concern in the Option F uncertainty section below.

## Recovery Path E — Mechanism (BLOCKED)

v0's anonymous-submit flow reveals the exploit surface: on submit, the browser issues
a top-level document request that navigates to `/chat/<newChatId>`. Next.js handles
this server-side (for authenticated users) or routes to `/api/auth/login` (for anon).
Either way, it is a **real document request**, not a pure fetch() call.

APF intercepts that top-level request (matching `/chat` path prefix) and returns an
HTTP 200 `text/html` document. The browser renders it as the new top-level page,
bypassing the SPA entirely. No need to understand v0's internal SSE envelope.

## Implementation — Pure DB migration

### Code verification (no C++ changes needed)

1. `ai_prompt_filter.cpp:974 render_envelope_template()` is **content-type agnostic** —
   whatever `Content-Type:` header you write in the envelope template is what ships.
   It does placeholder substitution (`{{MESSAGE}}`, `{{MESSAGE_RAW}}`, `{{UUID:name}}`,
   `{{TIMESTAMP}}`, `{{BODY_INNER_LENGTH}}`) + auto `Content-Length` recalculation.
2. `ai_prompt_filter_db_config_loader.cpp:146 path_matcher::match()` does prefix
   matching by default — `/chat` pattern matches `/chat`, `/chat/<id>`, `/chat/api/send`.
3. `ai_prompt_filter_db_config_loader.cpp:72 domain_matcher::match()` supports exact,
   `[*.]root.com`, `*.root.com`, `root.*` forms. `domain_patterns` column is
   comma/pipe/newline-delimited (parsed at `:459`).
4. **Dispatcher is pure DB lookup — no whitelist.**
   `ai_prompt_filter.cpp:1254-1263` selects `lookup_key = sd->response_type`
   (or `prepare_response_type` for prepare API), then
   `_config_loader->get_envelope_template(lookup_key)` returns the envelope as plain
   DB-loaded string. No switch/case, no registered-generator check.
   `ai_prompt_filter_db_config_loader.cpp:640-678 db_loader::load()` builds the
   `_envelopes` map keyed by `response_type` column from
   `ai_prompt_response_templates` directly — a new key like `v0_html_block_page`
   becomes available on the next `reload_services` with zero C++ awareness.
5. **v0 existing row state (inferred, confirm via pre-check).** v0 is currently
   BLOCK_ONLY serving plain error JSON — meaning a row in
   `ai_prompt_response_templates WHERE service_name='v0'` already exists with
   `envelope_template=NULL, response_type=''`. The `UPDATE` below sets the new
   columns in place. If pre-check returns 0 rows, use the INSERT fallback.

### Option E Migration SQL (archived — do not run)

Original Option E migration was designed to intercept `/chat/<id>` top-level
document requests with a `text/html` envelope. Archived because etap log verdict
proved `/chat/<id>` is never a top-level document request. SQL preserved below
for reference only.

<details>
<summary>Archived Option E SQL (click to expand)</summary>

```sql
-- DO NOT RUN — Option E is blocked per etap log verdict 2026-04-14 14:30
BEGIN;
UPDATE etap.ai_prompt_services
   SET domain_patterns = 'v0.dev,v0.app', path_patterns = '/chat',
       response_type = 'v0_html_block_page',
       h2_mode = 1, h2_end_stream = 2, h2_goaway = 0, h2_hold_request = 0
 WHERE service_name = 'v0';
UPDATE etap.ai_prompt_response_templates
   SET response_type = 'v0_html_block_page',
       envelope_template = CONCAT(
         'HTTP/1.1 200 OK\r\n',
         'Content-Type: text/html; charset=utf-8\r\n',
         'Cache-Control: no-store\r\n',
         'Content-Length: 0\r\n',
         '\r\n',
         '<!doctype html><title>차단</title><meta charset=utf-8>',
         '<body><h2>⚠ 보안 정책 안내</h2><p>{{MESSAGE}}</p></body>'
       )
 WHERE service_name = 'v0';
COMMIT;
```

</details>

## Recovery Path F — 303 redirect on `/chat/api/send` (Phase 6 PRIMARY experiment)

### Mechanism

Intercept v0's prompt submission endpoint `/chat/api/send` at the APF layer and
return HTTP 303 with a `Location:` header pointing to an Etap-served warning URL.

```
POST /chat/api/send   (fetch, expected: SSE stream)
      │
      └──[APF intercepts]──> HTTP 303 See Other
                              Location: https://etap.officeguard.local/apf-blocked?s=v0
                              Content-Length: 0
```

### Open questions / uncertainty

Option F's efficacy depends on how v0's JS handles the redirected response:

1. **Default fetch behavior** — `redirect: 'follow'` (default): browser auto-issues
   `GET Location`, delivers the HTML response body to the JS code. v0 expects an
   SSE stream → parse failure → Sentry → invisible. **This path fails silently.**
2. **If v0 uses `redirect: 'manual'`** — JS receives an opaque 0-status response
   and may choose to navigate via `window.location.href`. Unknown without HAR.
3. **If v0's error handler checks `response.redirected` or `response.url`** —
   it might display a toast. Unknown without HAR.

Only way to resolve: **run the experiment**. Cheap (pure DB migration) and
reversible (restore original envelope via revision bump).

### Option F Migration SQL

```sql
BEGIN;

-- 0. Pre-check (run alone first, capture existing row state)
SELECT service_name, domain_patterns, path_patterns, block_mode,
       response_type, h2_mode, h2_end_stream, h2_goaway, h2_hold_request
  FROM etap.ai_prompt_services
 WHERE service_name = 'v0';

SELECT service_name, http_response, response_type, envelope_template
  FROM etap.ai_prompt_response_templates
 WHERE service_name = 'v0';

-- 1. Service attrs — cover v0.app rebrand + target /chat/api/send
UPDATE etap.ai_prompt_services
   SET domain_patterns = 'v0.dev,v0.app',
       path_patterns   = '/chat/api/send',   -- exact API endpoint, not /chat prefix
       response_type   = 'v0_303_redirect',
       h2_mode         = 1,                  -- cascade shutdown after redirect
       h2_end_stream   = 2,                  -- 500B-class ceiling irrelevant (body empty)
       h2_goaway       = 0,
       h2_hold_request = 0
 WHERE service_name = 'v0';

-- 2. Envelope — 303 See Other with warning URL
UPDATE etap.ai_prompt_response_templates
   SET response_type     = 'v0_303_redirect',
       envelope_template = CONCAT(
         'HTTP/1.1 303 See Other\r\n',
         'Location: https://etap.officeguard.local/apf-blocked?s=v0\r\n',
         'Cache-Control: no-store\r\n',
         'Content-Length: 0\r\n',
         '\r\n'
       )
 WHERE service_name = 'v0';

-- 3. Trigger reload
UPDATE etap.etap_APF_sync_info SET revision_cnt = revision_cnt + 1
 WHERE table_name = 'ai_prompt_services';
UPDATE etap.etap_APF_sync_info SET revision_cnt = revision_cnt + 1
 WHERE table_name = 'ai_prompt_response_templates';

COMMIT;
```

### INSERT fallback (only if pre-check SELECT returns 0 rows)

Same defensive pattern as before — if no existing envelope row for v0, use
`INSERT ... ON DUPLICATE KEY UPDATE` mirroring `apf_db_driven_migration.sql:91-111`.

### Required supporting work (separate from APF)

Option F requires **Etap to serve** `https://etap.officeguard.local/apf-blocked`
outside the APF C++ path. This is a separate coordination item:
- URL: `/apf-blocked?s=<service_id>`
- Served by: Etap web tier (not APF)
- Content: minimal HTML warning page, reads `s` query param to customize text
- Size: unconstrained (no 500B ceiling since it's a normal Etap response)

If Etap-served `/apf-blocked` does not yet exist, alternative targets:
- Existing Etap warning page URL (if any) — preferred
- A data URL in the `Location:` header → NOT SAFE: major browsers block `data:`
  URLs from top-level navigation since 2017 for phishing prevention.

### Phase 6 test criteria

1. Pre-migration: capture state via pre-check SELECT
2. Apply UPDATE + revision_cnt bump
3. Verify reload: `grep 'Loaded.*services' /var/log/etap.log | tail -5`
4. Test PC verification: load `https://v0.app/`, submit a sensitive prompt
5. Observe:
   - **Success**: browser navigates to `/apf-blocked` and shows warning page → DONE
   - **Partial**: fetch() delivers HTML body to JS, v0 shows an inline error → investigate v0 error handler
   - **Failure**: "Thinking..." spinner forever, no visible change → Option F dead
     → transition v0 to **NEEDS_USER_SESSION** for Option A

### Size estimate

Headers ~115B + trimmed inline HTML ~260B + `{{MESSAGE}}` (~60B) ≈ **435B total**.
Under the 500B h2_end_stream=2 ceiling with ~65B margin.

## Schema finding — f+h coexistence via priority dispatch (2026-04-15 17:10, cycle 17)

While reviewing the design in idle time waiting on #451/#452 results, verified
**whether `ai_prompt_services` allows two envelopes for the same domain**.

Answer: **YES, via two separate rows with different `service_name` values** and
priority-based dispatch.

### Evidence

`ai_services_list::detect_service` at
`ai_prompt_filter_db_config_loader.cpp:198-296` collects **all** candidate
services whose `(domain, path)` match, then returns the **highest priority**
one. Priority = `domain_priority + path_priority`, where:

```cpp
// Domain priority (load_db_config_loader.cpp:238-242)
if (domain_pattern.find('*') == std::string::npos) {
    domain_priority = 1000 + pattern.length();
} else {
    domain_priority = 500 + pattern.length();
}

// Path priority (load_db_config_loader.cpp:260-266)
if (path_pattern.empty())                          path_priority = 100;
else if (path_pattern.find('*') == std::string::npos)  path_priority = 1000 + pattern.length();
else                                                    path_priority = 500 + pattern.length();
```

For two rows both matching `v0.app`:
- Row A: `service_name='v0'`,     `path_patterns='/chat'`          → priority 1000+5 = **1005** (matches `/chat`, `/chat/<id>`)
- Row B: `service_name='v0_api'`, `path_patterns='/chat/api/send'` → priority 1000+14 = **1014** (matches only `/chat/api/send`)

When path is `/chat/api/send`, Row B wins (1014 > 1005). Row A captures all
other `/chat*` paths it alone matches — i.e. `/chat/<id>` top-level document
requests on reload.

### Remaining single-row constraint

`is_prepare_api` dispatch at `ai_prompt_filter.cpp:525-526` is **hardcoded** to
paths ending in `/prepare`. It cannot be repurposed for arbitrary per-path
envelope selection within a single service row. So the only clean way to ship
two envelopes for v0 is two separate service rows.

### Updated Option F+H Migration SQL (proposed replacement for current Option F SQL above)

```sql
BEGIN;

-- 0. Pre-check (run alone first, capture existing state)
SELECT service_name, domain_patterns, path_patterns, block_mode,
       response_type, h2_mode, h2_end_stream, h2_goaway, h2_hold_request
  FROM etap.ai_prompt_services
 WHERE service_name IN ('v0', 'v0_api');

SELECT service_name, http_response, response_type, envelope_template
  FROM etap.ai_prompt_response_templates
 WHERE service_name IN ('v0', 'v0_api');

-- 1a. Row A — Option H: /chat/<id> reload-case block page (text/html document)
UPDATE etap.ai_prompt_services
   SET domain_patterns = 'v0.dev,v0.app',
       path_patterns   = '/chat',                    -- matches /chat, /chat/<id>, but LOSES priority to /chat/api/send (row B)
       response_type   = 'v0_html_block_page',
       h2_mode         = 1,
       h2_end_stream   = 2,
       h2_goaway       = 0,
       h2_hold_request = 0
 WHERE service_name = 'v0';

-- 1b. Row B — Option F: /chat/api/send 303 redirect (new row)
INSERT INTO etap.ai_prompt_services
       (service_name, display_name, domain_patterns, path_patterns, block_mode,
        response_type, h2_mode, h2_end_stream, h2_goaway, h2_hold_request)
VALUES ('v0_api', 'v0 (API)', 'v0.dev,v0.app', '/chat/api/send', 1,
        'v0_303_redirect', 1, 2, 0, 0)
    ON DUPLICATE KEY UPDATE
        domain_patterns = VALUES(domain_patterns),
        path_patterns   = VALUES(path_patterns),
        response_type   = VALUES(response_type),
        h2_mode         = VALUES(h2_mode),
        h2_end_stream   = VALUES(h2_end_stream),
        h2_goaway       = VALUES(h2_goaway),
        h2_hold_request = VALUES(h2_hold_request);

-- 2a. Envelope for v0_html_block_page (Option H, text/html body)
UPDATE etap.ai_prompt_response_templates
   SET response_type     = 'v0_html_block_page',
       envelope_template = CONCAT(
         'HTTP/1.1 200 OK\r\n',
         'Content-Type: text/html; charset=utf-8\r\n',
         'Cache-Control: no-store\r\n',
         'Content-Length: 0\r\n',
         '\r\n',
         '<!doctype html><title>차단</title><meta charset=utf-8>',
         '<body><h2>⚠ 보안 정책 안내</h2><p>{{MESSAGE}}</p></body>'
       )
 WHERE service_name = 'v0';

-- 2b. Envelope for v0_303_redirect (Option F, new row)
INSERT INTO etap.ai_prompt_response_templates
       (service_name, http_response, response_type, envelope_template)
VALUES ('v0_api', 0, 'v0_303_redirect',
        CONCAT(
          'HTTP/1.1 303 See Other\r\n',
          'Location: https://etap.officeguard.local/apf-blocked?s=v0\r\n',
          'Cache-Control: no-store\r\n',
          'Content-Length: 0\r\n',
          '\r\n'
        ))
    ON DUPLICATE KEY UPDATE
        response_type     = VALUES(response_type),
        envelope_template = VALUES(envelope_template);

-- 3. Trigger reload
UPDATE etap.etap_APF_sync_info SET revision_cnt = revision_cnt + 1
 WHERE table_name = 'ai_prompt_services';
UPDATE etap.etap_APF_sync_info SET revision_cnt = revision_cnt + 1
 WHERE table_name = 'ai_prompt_response_templates';

COMMIT;
```

### Test matrix for f+h pair

| Scenario | Expected hit | Expected UX |
|----------|-------------|-------------|
| User types prompt on v0.app (fetch POST `/chat/api/send`) | Row B (`v0_api`, priority 1014) → 303 redirect | Browser auto-follows 303 via fetch → delivers HTML body to JS → Sentry silent (LOW yield, known failure mode) |
| User reloads `/chat/<hJ35MSWtyWu>` (top-level GET document) | Row A (`v0`, priority 1005) → 200 text/html | Browser renders warning HTML as top-level page (HIGH yield) |
| User navigates to `v0.app/` root | Neither (path `/` doesn't match `/chat`) | Normal site load |
| User submits via reload flow | Both rows fire on different requests | F fails silent + H catches the reload |

### Caveat — route conflict check

If ANY existing service row has `domain_patterns` containing `v0.dev` or
`v0.app` AND `path_patterns` matching `/chat/api/send` with priority ≥ 1014,
it would outrank Row B. Pre-check SELECT must include a query on all rows
containing `v0.app` in domain_patterns, not just the ones where
`service_name IN ('v0', 'v0_api')`. Add to Phase 6 pre-flight:

```sql
SELECT service_name, domain_patterns, path_patterns, response_type
  FROM etap.ai_prompt_services
 WHERE domain_patterns LIKE '%v0.app%' OR domain_patterns LIKE '%v0.dev%';
```

## Phase 6 handoff checklist (Option F primary)

1. Confirm Etap `/apf-blocked` landing URL exists (or coordinate creation).
2. Capture pre-migration state via the pre-check SELECT.
3. Apply the Option F DB UPDATE in transaction; verify revision_cnt bump.
4. Observe APF reload: `ssh -p 12222 solution@218.232.120.58 "grep 'Loaded.*services' /var/log/etap.log | tail -5"`
5. Test PC verification:
   - Navigate to `https://v0.app/` (anonymous is fine — #447 proved input works).
   - Submit a prompt containing a sensitive keyword registered for v0.
   - Observe whether browser navigates to `/apf-blocked` or stays on chat page.
6. **Risk path**: if Option F produces no visible change (silent fetch-follow
   with SSE parse error buried in Sentry), transition v0 to **NEEDS_USER_SESSION**
   for Option A. User coordination required to capture authenticated HAR.

## Recovery Path A — SSE injection (NEEDS_USER_SESSION contingency)

Deferred. Requires a Vercel-authenticated HAR capture of a successful assistant reply
to learn v0's real SSE/ndjson envelope. Would produce the cleanest UX (warning inside
the chat bubble) but depends on internal envelope knowledge not yet available.

## Cross-service opportunity

If Option E works for v0, the `text/html` block-page pattern should be applicable to
any NEEDS_ALTERNATIVE service that matches: SPA consuming fetch/XHR stream, no native
in-page error UI, top-level document navigation hook. Re-evaluate candidates:
**gamma**, **gemini3**, **huggingface**.

## Source

- `results/447_frontend-inspect-v0_result.json`
- `shared-skills/genai-apf-pipeline/services/v0_frontend.md`
- `functions/ai_prompt_filter/ai_prompt_filter.cpp:974` (render_envelope_template)
- `functions/ai_prompt_filter/ai_prompt_filter.cpp:1254-1270` (dispatcher = pure DB lookup)
- `functions/ai_prompt_filter/ai_prompt_filter_db_config_loader.cpp:72,146` (matchers)
- `functions/ai_prompt_filter/ai_prompt_filter_db_config_loader.cpp:640-678` (envelope map load)
- `functions/ai_prompt_filter/sql/apf_db_driven_migration.sql` (column schema + chatgpt_sse INSERT pattern ref)
- `local_archive/apf_infra_scoping_2026-04-14.md` (500B ceiling analysis)
