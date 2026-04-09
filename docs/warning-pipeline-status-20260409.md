# APF Warning Pipeline Status — 2026-04-09

## Summary

Session covered tests #288–#303. Key achievement: **B24 RST_STREAM fix** resolves HTTP/2 protocol errors for h2_mode=2 + no-hold services.

## Service Status

| Service | Status | Warning Visible | Block Effective | h2_mode | Template | Notes |
|---------|--------|----------------|----------------|---------|----------|-------|
| ChatGPT | ✅ Working | Yes | Yes | 1 (GOAWAY) | SSE delta | Confirmed #245 |
| Claude | ✅ Working | Yes | Yes | 1 (GOAWAY) | SSE message_start | Confirmed #246 |
| Genspark | ✅ Working | Yes | Yes | 2 (keep-alive+hold) | SSE | Confirmed #254 |
| Perplexity | 🔶 Functional block | No | Yes | 2 (keep-alive, no-hold) | 422 JSON error | User data blocked, search just doesn't execute |
| Gamma | 🔶 BLOCKED_ONLY | No | Yes | 2 (keep-alive, no-hold) | 400 JSON error | Warning in console error; EventSource delivery impossible with current VTS |
| Gemini | 🔶 Functional block | No | Yes | 2 (keep-alive, no-hold) | 400 JSON error | CSP violations, silent failure |
| Grok | ❌ Silent block | No | Yes | 1 (GOAWAY) | NDJSON token | Frontend redirects to fake conversation → 400 |
| Mistral | ❌ Silent block | No | Yes | 2 (keep-alive+hold) | HTTP 400 | superjson NDJSON unfakeable |

## B24 Changes (this session)

### Code: RST_STREAM to server for no-hold streams
- **Files**: tuple.h, etap_packet.h, network_loop.cpp, ai_prompt_filter.cpp, visible_tls_session.cpp
- **Problem**: h2_mode=2 code assumed hold was always active (B16 comment: "is_http2=2는 항상 request buffering을 사용하므로"). With h2_hold_request=0, server responds on the same stream → duplicate HEADERS → ERR_HTTP2_PROTOCOL_ERROR
- **Fix**: Track `was_held` flag. When no-hold, send RST_STREAM(CANCEL) to server for the blocked stream
- **Result**: Gamma #300 — ERR_HTTP2_PROTOCOL_ERROR eliminated. HTTP 400 delivered cleanly. Fonts work. No collateral damage.

### Template: reload_templates discovery
- `etapcomm ai_prompt_filter.reload_services` only reloads `ai_prompt_services` table
- `etapcomm ai_prompt_filter.reload_templates` reloads `ai_prompt_response_templates` table
- Tests #293-295 ran with OLD templates because only reload_services was called

### Template iterations for Perplexity
1. Complex SSE with thread_url_slug (#290): frontend navigated to fake thread, re-fetched → empty
2. HTTP 422 JSON error (#296): delivered, no navigation, but no visible error UI
3. Minimal SSE without thread_url_slug (#299): STREAM_FAILED_FIRST_CHUNK_ERROR
4. SSE with thread_url_slug restored (#302): parsed OK, but thread validation fails → redirects home
5. **Final: HTTP 422 JSON error** — cleanest block behavior (page stays on home)

### Template iterations for Gamma
1. SSE chunks (#291, #297): ERR_HTTP2_PROTOCOL_ERROR (pre-B24)
2. HTTP 400 JSON error (#300): **BEST** — error delivered, warning text in error body
3. SSE chunks with B24 (#303): frontend JSON.parse()s → SyntaxError (SSE format wrong for Gamma)
4. **Final: HTTP 400 JSON error** — proven transport, warning in error body

## B25 Changes (pending test #304)

### Gamma: Hold-based outline interception (DB-only change)
- **Hypothesis**: Build #26 proved SSE+JSON objects reach EventSource. Builds #30-#33 failed due to server response interference (h2_hold_request=0). B24 RST_STREAM fix works for render-generation (#300) but SSE format wrong for that endpoint (#303). Solution: target the OUTLINE endpoint with hold.
- **DB changes**:
  - `ai_prompt_services`: h2_hold_request=0→1, h2_end_stream=1→0, h2_goaway=0 (unchanged)
  - `ai_prompt_response_templates`: envelope changed from HTTP 400 JSON to SSE (200 OK + text/event-stream + JSON object data)
- **Why hold=1 fixes delivery**: With hold, the outline request is buffered and never reaches the server. No race condition, no duplicate HEADERS, no ERR_CONNECTION_CLOSED. The SSE response goes directly to the client via SSL_write.
- **VTS code path verification**: Line 622 `was_held=true` → buffer discarded → Line 654 h2_mode=2 → Line 658 `!was_held` is false → RST_STREAM skipped (correct, server never saw stream)
- **Risk**: Hold buffers ALL client→server packets per-connection (PING, WINDOW_UPDATE).
- **Expected outcome**: SSE events parsed by EventSource.

### Test #304 Result: FAILED
- h2_hold_request=1 blocked EVERYTHING (outline + render-generation)
- ERR_CONNECTION_CLOSED on SSE delivery — same as Builds #30-#33
- **Root cause confirmed**: ERR_CONNECTION_CLOSED is NOT from server interference. It's a VTS limitation with EventSource H2 delivery.
- fetch()-based endpoints (render-generation): H2 DATA works ✓
- EventSource-based endpoints (outline): H2 DATA fails ✗
- **Reverted to #300 config** (h2_hold_request=0, h2_end_stream=1, HTTP 400 JSON)

### Key insight: Two Gamma endpoints
- `/ai/v2/generation` (outline) — uses EventSource (SSE), is the first API call
- `/ai/v2/render-generation` (rendering) — uses fetch+JSON.parse, called after outline completes
- APF path_patterns=`/` matches both, but with h2_hold_request=0, only render-generation was blocked
- **Gamma classified as BLOCKED_ONLY** — all approaches exhausted (13+ SSE builds + #304 hold)

## Remaining Challenges

### Why visible warning is hard for Perplexity/Gamma/Gemini
- **Perplexity**: Frontend validates thread existence via REST API → fake threads rejected → redirects home
- **Gamma**: Frontend JSON.parse()s the API response → 400 JSON caught by error handler but not surfaced to user UI
- **Gemini**: CSP connect-src 'self' violations + frontend silently discards non-protobuf errors

### Potential future approaches
1. **Server→client stream filtering**: Parse H2 frames from server, drop blocked stream's data. Eliminates race condition entirely.
2. **Multi-endpoint interception**: For Perplexity, intercept both the SSE endpoint AND the thread validation endpoint
3. **JavaScript injection**: Inject warning UI via the response body (requires CSP bypass)
4. **Custom error page**: For h2_mode=1 services, return a full HTML error page instead of API response

## DB Configuration (current)

### ai_prompt_services
| service | h2_mode | h2_end_stream | h2_goaway | h2_hold_request |
|---------|---------|---------------|-----------|-----------------|
| chatgpt | 1 | 1 | 1 | 0 |
| claude | 1 | 1 | 1 | 0 |
| genspark | 2 | 1 | 0 | 1 |
| perplexity | 2 | 1 | 0 | 0 |
| perfle | 2 | 1 | 0 | 0 |
| gamma | 2 | 1 | 0 | 0 |
| gemini3 | 2 | 1 | 0 | 0 |
| grok | 1 | 1 | 1 | 0 |

### ai_prompt_response_templates (final)
| id | service | format | size |
|----|---------|--------|------|
| 10 | perplexity | HTTP 422 JSON error | 277 |
| 16 | gamma | HTTP 400 JSON error (reverted) | 266 |
| 19 | gemini | HTTP 400 JSON error | 268 |
| 21 | grok | NDJSON token-only | 928 |
| 22 | chatgpt | SSE delta | ~800 |
| 7 | claude | SSE message events | ~700 |
