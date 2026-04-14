# v0 Phase 5 Design — Option E (Block Page Substitution)

> Phase 5 deliverable. Promoted from `local_archive/v0_design_skeleton_2026-04-14.md`
> on 2026-04-14. Based on #447 frontend-inspect result (anonymous-only profile) and
> direct code inspection of `ai_prompt_filter.cpp` + `ai_prompt_filter_db_config_loader.cpp`.

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

## Final option verdicts (post-#447)

| Option | Verdict | Notes |
|--------|---------|-------|
| a. SSE/stream injection | UNKNOWN (auth rerun needed) | Frontend ignores JSON bodies on `/chat/api/send` (proven by #438). Needs real SSE envelope. |
| b. HTTP body HTML on `/chat/api/send` | BLOCKED | `fetch()` parse error, not rendered. |
| c. JS error UI activation | BLOCKED | v0 has **no** in-page error UI. All errors → Sentry → invisible. |
| d. Direct DOM injection | BLOCKED | APF is network-layer. |
| **e. Block page substitution** | **PRIMARY** | Intercept top-level document request for `/chat/<id>` → return `text/html` → browser renders as top-level page. |
| f. 303 redirect | ALT | Fallback if `/chat/<id>` is CSR-only. |

**Path order**: **e → f → a (contingent)**

## Recovery Path E — Mechanism

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

### Migration SQL

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

-- 1. Service attrs — cover v0.app rebrand + switch to HTML block page
UPDATE etap.ai_prompt_services
   SET domain_patterns = 'v0.dev,v0.app',
       path_patterns   = '/chat',
       response_type   = 'v0_html_block_page',
       h2_mode         = 1,
       h2_end_stream   = 2,
       h2_goaway       = 0,
       h2_hold_request = 0
 WHERE service_name = 'v0';

-- 2. Envelope template — Content-Type header decides
UPDATE etap.ai_prompt_response_templates
   SET response_type     = 'v0_html_block_page',
       envelope_template = CONCAT(
         'HTTP/1.1 200 OK\r\n',
         'Content-Type: text/html; charset=utf-8\r\n',
         'Cache-Control: no-store\r\n',
         'Content-Length: 0\r\n',
         '\r\n',
         '<!doctype html><title>차단</title>',
         '<meta charset=utf-8>',
         '<body style="font:1rem system-ui;max-width:40em;margin:3em auto;padding:1em">',
         '<h2 style="color:#b00">⚠ 보안 정책 안내</h2>',
         '<p>{{MESSAGE}}</p></body>'
       )
 WHERE service_name = 'v0';

-- 3. Trigger reload
UPDATE etap.etap_APF_sync_info SET revision_cnt = revision_cnt + 1
 WHERE table_name = 'ai_prompt_services';
UPDATE etap.etap_APF_sync_info SET revision_cnt = revision_cnt + 1
 WHERE table_name = 'ai_prompt_response_templates';

COMMIT;
```

### Size estimate

Headers ~115B + trimmed inline HTML ~260B + `{{MESSAGE}}` (~60B) ≈ **435B total**.
Under the 500B h2_end_stream=2 ceiling with ~65B margin.

## Phase 6 handoff checklist

1. Capture pre-migration state via the pre-check SELECT.
2. Apply the DB UPDATE in transaction; verify revision_cnt bump.
3. Observe APF reload: `ssh -p 12222 solution@218.232.120.58 "grep 'Loaded.*services' /var/log/etap.log | tail -5"`
4. Test PC verification:
   - Navigate to `https://v0.app/` as authenticated user.
   - Submit a prompt containing a sensitive keyword registered for v0.
   - Expect: HTML block page rendered as top-level document (not SPA chat).
5. **Risk path**: if `/chat/<id>` turns out to be client-side-routed (SPA `router.push()`
   without a real document fetch), Option E produces nothing. In that case:
   - Fall back to Option F (303 redirect).
   - OR request #448 authenticated HAR rerun to characterize the navigation hook.

## Recovery Path F — 303 redirect (fallback)

If Option E fails the Phase 6 test, return HTTP 303 on `/chat/api/send` with
`Location:` pointing to an Etap-served `/apf-blocked` page.

```
HTTP/1.1 303 See Other
Location: https://etap.officeguard.local/apf-blocked?service=v0
Content-Length: 0

```

**Caveats**: 302 is unsafe on POST — 303 required. Loses inline UX; user navigates away.
Requires Etap to serve `/apf-blocked` outside the APF C++ path.

## Recovery Path A — SSE injection (contingent fallback)

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
- `functions/ai_prompt_filter/ai_prompt_filter_db_config_loader.cpp:72,146` (matchers)
- `local_archive/apf_infra_scoping_2026-04-14.md` (500B ceiling analysis)
