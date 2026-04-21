# Gemini3 — Frontend Profile (Phase 4)

> Source: `results/452_gemini3-frontend-inspect_result.json` (2026-04-15 17:22 KST)
> Test PC: autonomous /loop polling, windows-mcp browser automation, logged-in Google account (jjanghee28@gmail.com)
> Status: **FRONTEND_PROFILED_WITH_BLOCKERS** — silent-fail confirmed, CSP strict-dynamic blocks DOM, wrb.fr envelope replacement is the only marginal path
> Supersedes: `services/gemini_frontend.md` (old Phase 1 capture #15x, 2026-04-02)

## Service Context

| Field | Value |
|-------|-------|
| Service | Gemini3 (gemini.google.com) |
| URL tested | `https://gemini.google.com/app` (authenticated) |
| Framework | Angular (ng-version attribute, `_nghost-ng-c304432922`, `<chat-app>` custom element, `ngcm` ChangeManagement) |
| Build label | `boq_assistant-bard-web-server_20260413.06_p1` (2026-04-13 post-fix release) |
| Session id | `f.sid=8887047125100837041` (stable per session) |
| CDN | Google edge (`[2404:6800:4010:626::2004]:443` IPv6) |
| CSP | **PRESENT and STRICT** — nonce + strict-dynamic policy |
| Bot mitigation | Google internal fraud/abuse (not Kasada/Cloudflare, no visible captcha triggered) |

## Primary API Endpoint

```
POST https://gemini.google.com/_/BardChatUi/data/batchexecute
    ?rpcids=<RPCID>
    &source-path=%2Fapp
    &bl=boq_assistant-bard-web-server_20260413.06_p1
    &f.sid=8887047125100837041
    &hl=ko
    &_reqid=<incrementing_id>
    &rt=c

Content-Type (req):  application/x-www-form-urlencoded (Google boq framework)
Content-Type (resp): application/javascript (wrb.fr envelope, protobuf-over-JSON,
                     prefixed with `)]}'\n` security guard)
HTTP version:        h2
```

**Request body**: `f.req` parameter (x-www-form-urlencoded) containing the protobuf-over-JSON user prompt. **Not decoded in this probe** — requires either manual DevTools Payload tab drill-down or a base64+JSON+JS-array decoder. The existing `gemini_design.md` already described this; #452 confirms the endpoint URL template and rpcid map but does not re-derive the payload schema.

### rpcid map (this session)

| rpcid | Guessed role | Observed |
|-------|--------------|----------|
| `c3wobe` | Initial listing / chats endpoint | Baseline load 1x |
| `L5adhe` | Chat send / assistant query | 3x per conversation (most frequent) |
| `ESY5D` | Conversation update / persistence | 2x |
| `PCck7e` | Chat session metadata update | 1x |
| `aPya6c` | **Pre-send validation / setup** | Fires first on submit — **this is the one that aborts during Offline and causes the rest of the flow to silently stop** |

`_reqid` starts around `2962048` and increments by `100000` per request.

## Response model (NOT SSE)

Unlike DeepSeek (#451 true SSE) or v0 (#447-448 pure CSR pushState), Gemini's chat API is a **single POST/response pair**. The response body is a `wrb.fr` envelope containing zero or more assistant fragments that get applied to the Angular state in one batch after the HTTP transaction closes.

**Implication**: Strategy D (envelope replacement) is the only logical approach — replace the entire response body. No streaming semantics to mimic.

## Silent-fail confirmed (method 1: DevTools Offline)

The "silent fail" hypothesis from the existing `gemini_design.md` is **CONFIRMED** via DevTools Offline toggle + jserror telemetry inspection.

### UI symptom
- User's new prompt ("Tell me about quantum physics") was **NOT rendered** as a new user bubble (or if briefly rendered, was immediately removed)
- **No** thinking spinner
- **No** error text
- **No** toast
- **No** modal
- Previous conversation remained visible unchanged

### Under-the-hood evidence
1. `batchexecute?rpcids=aPya6c&...` POST fired and failed with `HTTP Status=0, XHR Error Code=6`
2. **FIVE `jserror` telemetry POSTs** immediately afterward to `https://gemini.google.com/_/BardChatUi/jserror` with payload:
   ```
   Error code = 7, Path = /_/BardChatUi/data/batchexecute,
   Message = There was an error during the transport or processing of this request.,
   HTTP status = 0, Unknown HTTP error in underlying XHR
   (HTTP Status: 0) (XHR Error Code: 6) (XHR Error Message: ' [0]')
   ```
3. **NONE** of these errors surfaced to the UI — Angular template has no error-display binding for this failure type

### Why it's silent
Gemini's Angular app has a **full error-catch pipeline** (evidenced by the 5 jserror POSTs). The silent-fail behavior is **intentional** — Google chose to hide network errors from end users and log them to internal telemetry instead. This is a reliability/UX design choice with the side effect of blocking APF warning-delivery options that depend on a user-visible error slot.

**Hard constraint**: Any warning-delivery option that relies on Gemini displaying an error to the user is dead on arrival.

## CSP — strict-dynamic nonce (hard wall)

```
base-uri 'self';
object-src 'none';
script-src 'report-sample' 'nonce-<per-request-value>' 'unsafe-inline' 'strict-dynamic' https: http:;
report-uri /_/BardChatUi/cspreport;
[connect-src, frame-ancestors, etc. truncated]
```

### Key analysis

| Directive | Meaning |
|-----------|---------|
| `script-src 'nonce-<val>' 'strict-dynamic'` | Only scripts with the matching per-request nonce execute. `'unsafe-inline'` and `https:/http:` fallbacks are IGNORED by modern Chrome/Firefox when `'strict-dynamic'` is present. **No inline script or event handler can execute without the exact nonce.** |
| `base-uri 'self'` | Prevents `<base href>` hijacking |
| `object-src 'none'` | No Flash / legacy plugins |
| `report-uri /_/BardChatUi/cspreport` | CSP violations are POSTed to Google → any injected non-nonced script WILL be logged and may trigger automated bot detection |

### Implication for APF
Options C (JS error panel), D (DOM inject), and any script-based injection are **DEFINITIVELY BLOCKED**. Even if APF injected markup, browser CSP enforcement happens BEFORE JS runs — no inline handler, no dynamically-created script tag, no iframe escape works without the per-request nonce.

Non-script DOM text additions would need a pre-existing trusted script to read APF-controlled data and inject text — APF has no such hook into Gemini's Angular app.

## Chat bubble DOM

| Property | Value |
|----------|-------|
| Root component | `<chat-app id='app-root' _nghost-ng-c304432922>` |
| Selector style | Hashed Angular component host/template attrs (`_nghost-ng-c304432922`, `ng-tns-c304432922-0`) |
| Custom elements | `<chat-app>`, likely `<message-actions>`, `<message-content>`, `<user-query>`, `<model-response>` (all semantic but minified) |
| Render mode | Angular template rendering + change detection. Message text via sanitized HTML pipe (`DomSanitizer`). Markdown → HTML server-side in wrb.fr response, client-side just binds. |
| Streaming pattern | **Per-batchexecute response**, not token-level. Full response state applied in one pass. |
| Error slot hypothesis | A well-behaved Angular Material app would have `<mat-snack-bar-container>`, `<mat-dialog-container>`, `<div role='alert' aria-live='assertive'>`. The silent fail suggests **these slots exist in the template but are not BOUND to the batchexecute error path**. Different from "slot doesn't exist" → "slot exists but has no wiring". Either way, APF cannot reach them. |

## Warning Delivery Options — 5-Way Verdict

| Option | Verdict | Rationale |
|--------|---------|-----------|
| A. SSE stream injection | ❌ BLOCKED | No SSE — Gemini uses single POST/response |
| **A′. wrb.fr envelope replacement** | ⚠️ **UNKNOWN / ONLY MARGINAL PATH** | Existing Strategy D. Protobuf IDL is black-box Google internal. Current implementation produces "no warning visible" — most likely a protobuf schema mismatch, NOT a wrong approach. |
| B. HTTP body HTML swap | ❌ BLOCKED | fetch() parses response as application/javascript — HTML causes throw, swallowed by silent-fail pipeline |
| C. JS error panel | ❌ BLOCKED | Internal jserror handler exists but does NOT surface to UI. No user-visible error slot reads response body. |
| D. DOM direct injection | ❌ BLOCKED | Strict-dynamic nonce CSP blocks any inline script. APF has no pre-existing trusted hook to pass text through. |
| E. Block page substitution | ❌ BLOCKED | Deep Angular SPA session. HTML swap would (1) break SPA state, (2) log user out, or (3) trigger Google fraud detection. Not viable without collateral damage. |

**Recommended path**: A′ (wrb.fr envelope replacement) with a NEW diagnostic step — byte-level comparison of captured success response vs APF-generated envelope. If byte-perfect replacement still fails, reclassify **PENDING_INFRA** until Google publishes (or a community reverse-engineering project decodes) the BardChatUi protobuf IDL.

## Comparison to DeepSeek (#451) and v0 (#447-448)

| Dimension | DeepSeek | v0 | Gemini3 |
|-----------|----------|----|---------| 
| Protocol readability | ✅ Full SSE schema | ❌ Black-box | ❌ Opaque protobuf inside wrb.fr |
| CSP | None | None | **Strict-dynamic nonce** |
| Error slot | Static i18n (C blocked) | None (all silent redirects to auth) | Internal jserror telemetry only |
| State-driven rendering | `response.fragments[-1].content` | SPA router.push | Angular change-detection on full response state |
| Authenticated session | ✅ Stable | ❌ Redirect trap | ✅ Stable |
| Phase 5 readiness | **Option A strong** | NEEDS_USER_SESSION for A / NEEDS_ALT for f+h | **A′ only (Strategy D) + schema debugging** |

**DeepSeek vs Gemini**: DeepSeek is a MUCH easier target. DeepSeek uses web-standard SSE + no CSP + permissive schema. Gemini has Google platform-wide security posture + proprietary wire formats. The difference is platform philosophy, not fixable by APF alone.

**v0 vs Gemini**: Both fundamentally resistant to warning injection because the frontend was designed assuming a cooperative backend, not an adversarial network intermediary. Same end result (silent fail), different mechanism (Next.js router.push vs Angular change-detection).

## Console Errors

- 20 errors + 5 warnings over the full session
- Categories: CSP report URL logs (allowed-sources whitelist), jserror POSTs during Offline, fetch failures for `batchexecute&rpcids=aPya6c`, Google Maps / Tag Manager loads (unrelated)
- No Kasada, no visible captcha — Google's internal fraud/abuse piggybacks on existing telemetry infrastructure

## Screenshots

Stored at `results/files/452/`:

1. `01_baseline_landing.png` — authenticated workspace
2. `02_devtools_console_csp_logs.png` — CSP report URL spam
3. `03_csp_diag.png` — CSP header dump
4. `04_gemini_response_state.png` — successful "speed of light" reply
5. `05_network_batchexecute_filter.png`, `06_batchexecute_row_detail.png` — batchexecute request details
6. `07_offline_silent_fail.png` — Offline state with no UI change
7. `08_silent_fail_network_jserror.png` — 5 jserror POSTs in Network panel

## Key insights

1. **Silent-fail is a feature, not a bug.** Gemini's internal jserror pipeline proves error handling exists — Google chose to hide errors from UI. Side effect: Options C/D are dead.
2. **CSP strict-dynamic is a hard wall.** Unlike v0/deepseek with weak-or-no CSP, Gemini's nonce-based policy fundamentally prevents DOM-script injection.
3. **wrb.fr envelope replacement is the only non-zero path.** Most likely failure mode of existing Strategy D is protobuf schema mismatch, not wrong approach. Byte-level diff needed before declaring it dead.
4. **Google internal protobuf is a black box.** BardChatUi uses google3 internal schemas not published externally. Schema reverse-engineering by observation is slow and error-prone — this is the root-cause reason Strategy D is hard.

## Next steps

1. **Phase 5: update `services/gemini_design.md`** (or fork to `gemini3_design.md`) with:
   - Captured URL template and rpcid map
   - Confirmed silent-fail mechanism + WHY Options B/C/D/E are dead ends
   - Debugging checklist for Strategy D envelope replacement (capture success response raw → diff against APF output → look for field-level differences)
2. **If byte-perfect envelope still fails**, reclassify as **PENDING_INFRA**.
3. **Do not** pursue NEEDS_ALTERNATIVE with a new option — there is no alternative option space to explore.

## Source

- Test PC HAR + screenshot bundle: `results/452_gemini3-frontend-inspect_result.json` + `results/files/452/`
- Supersedes: `services/gemini_frontend.md` (2026-04-02 Phase 1 capture)
- Existing design: `services/gemini_design.md` (Strategy D, needs update per §Next steps)
