# APF Warning Pipeline Status — 2026-04-10 (Updated)

## Summary

Session covered tests #288–#326. Key achievements:
- **B24 RST_STREAM fix** resolves HTTP/2 protocol errors for h2_mode=2 + no-hold services
- **B25 Gamma hold test** (#304) confirmed VTS EventSource H2 limitation — Gamma classified BLOCKED_ONLY
- **DuckDuckGo** (#310) — ✅ WARNING VISIBLE. path_matcher trailing slash bug fixed, 403 JSON in chat bubble
- **DeepSeek** (#311–#315) — SSE approach failed 4x (0 body bytes), switched to 403 JSON → 🔶 status code visible
- **B26 path_matcher fix** — built [172/172], deployed to test server
- **Grok** (#316) — ✅ WARNING VISIBLE. APF NDJSON token + Korean warning. Free access confirmed
- **Mistral** (#317–#326) — 🔶 Visible Error 6002. 10 iterations. Only NDJSON array + h2_mode=2 produces visible error

## Service Status

| Service | Status | Warning Visible | Block Effective | h2_mode | Template | Notes |
|---------|--------|----------------|----------------|---------|----------|-------|
| ChatGPT | ✅ Working | Yes | Yes | 1 (GOAWAY) | SSE delta | Confirmed #245 |
| Claude | ✅ Working | Yes | Yes | 1 (GOAWAY) | SSE message_start | Confirmed #246 |
| Genspark | ✅ Working | Yes | Yes | 2 (keep-alive+hold) | SSE | Confirmed #254 |
| Perplexity | 🔶 Functional block | No | Yes | 2 (keep-alive, no-hold) | 422 JSON error | User data blocked, search just doesn't execute |
| Gamma | 🔶 BLOCKED_ONLY | No | Yes | 2 (keep-alive, no-hold) | 400 JSON error | VTS EventSource H2 limitation (13+ builds + #304 hold) |
| Gemini | 🔶 Functional block | No | Yes | 2 (keep-alive, no-hold) | 400 JSON error | CSP violations, silent failure |
| DuckDuckGo | ✅ Working | Yes | Yes | 1 (GOAWAY) | SSE OpenAI-like | Confirmed #310 — path fix verified, 403 JSON visible in chat bubble |
| DeepSeek | 🔶 403 Visible | Partial | Yes | 1 (GOAWAY+hold) | 403 JSON error | #315: 403 status visible in chat, JSON body in DevTools only |
| Grok | ✅ Working | Yes | Yes | 1 (GOAWAY) | APF redirect + banner | Confirmed #316 — Korean warning banner visible, free access |
| Mistral | 🔶 Visible Error | Partial | Yes | 2 (keep-alive+hold) | NDJSON superjson array | #326: Error 6002 confirmed reproducible. 10 iterations (#317-#326). Array format only |

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
| mistral | 2 | 1 | 0 | 1 |

### ai_prompt_response_templates (final)
| id | service | format | size |
|----|---------|--------|------|
| 10 | perplexity | HTTP 422 JSON error | 277 |
| 16 | gamma | HTTP 400 JSON error (reverted) | 266 |
| 19 | gemini | HTTP 400 JSON error | 268 |
| 21 | grok | NDJSON token-only | 928 |
| 22 | chatgpt | SSE delta | ~800 |
| 7 | claude | SSE message events | ~700 |
| 17 | duckduckgo | SSE OpenAI-like | 252 |
| — | deepseek | SSE OpenAI-like (pending #309) | ~300 |
| 24 | mistral | NDJSON superjson array (v4, empty meta) | 763 |

## ECH (Encrypted Client Hello) Issue

### Discovery
Test #307 (DuckDuckGo) failed with zero APF log entries. VT never intercepted the connection.

### Root Cause
duck.ai uses Cloudflare, which activated ECH globally in late 2024. ECH encrypts the SNI in TLS ClientHello, making the actual domain name invisible to MITM proxies. VT sees only the outer SNI (`cloudflare-ech.com`) and either:
1. Creates a cert mismatch (outer SNI ≠ expected domain) → TLS error
2. Encounters unknown TLS extension → handshake failure
3. Either way → `auto_bypass` triggers (all TLS errors → bypass in current config)

### VT Code Analysis
- `visible_tls_auto_bypass.xml`: ALL TLS errors trigger bypass (300+ reasons)
- `tls_proxy.cpp`: `get_server_name()` extracts outer SNI only — no ECH awareness
- No ECH-related code exists anywhere in VT source

### Fix Options (priority order)
1. **Chrome flag** (immediate test): Disable ECH in `chrome://flags` → test #308
2. **DNS-level**: Block HTTPS DNS records containing ECH keys → browser falls back to non-ECH TLS
3. **VT ECH stripping**: Strip ECH extension from ClientHello before forwarding (~200-400 LOC)

### Affected Services
Any Cloudflare-hosted service may be affected. Currently confirmed:
- **duck.ai**: ECH blocks VT MITM (#307)
- **chatgpt.com**: Cloudflare, but currently working (ECH may not be active for this zone yet)
- **claude.ai**: Cloudflare, but currently working (same)

### Diagnostic Test #308
- Disable ECH in Chrome on test PC → retest duck.ai
- If APF intercepts after ECH disabled → ECH confirmed as root cause

## New Service: DeepSeek

### HAR Capture #305 Results
- API: `POST https://chat.deepseek.com/api/v0/chat/completion`
- Protocol: h2, Content-Type: text/event-stream (SSE)
- Login: NOT required (free access)
- PoW: sha3 WASM proof-of-work challenge before chat
- Modes: Quick (DeepSeek-V3), Deep Think, Search

### DB Registration
- File: `apf-db-driven-service/deepseek_registration.sql`
- h2_mode=1 (GOAWAY), domain=deepseek.com,*.deepseek.com,chat.deepseek.com, path=/api/v0/chat/completion
- Template id=26: Named SSE events (event:message + event:close)

### SSE Approach Failed (#311–#314)
- All 4 SSE tests delivered 0 response body bytes regardless of h2_mode
- #311: h2_mode=1 (GOAWAY) → 0 events
- #312: Removed Content-Length:0 → 0 events
- #313: h2_hold_request=1 → 0 events
- #314: h2_mode=2 (keep-alive) + hold → 0 events
- Root cause unknown — APF code generates H2 DATA frames correctly (verified in code review)
- DeepSeek frontend may use EventSource API which handles SSE differently

### 403 JSON Approach SUCCESS (#315)
- Switched to HTTP 403 Forbidden + JSON error body (DuckDuckGo pattern)
- h2_mode=1 + h2_hold_request=1 + GOAWAY
- **Result: PARTIAL SUCCESS**
  - 403 status code VISIBLE in frontend: "전송 실패. 나중에 다시 시도하세요.. (403)"
  - JSON body delivered and visible in DevTools Response tab
  - Policy message NOT rendered in chat UI (DeepSeek shows its own error)
- Classification: 🔶 Functional block with visible status code

## Mistral Warning Attempts (#317–#318)

### #317: HTTP 400 tRPC Error (FAILED)
- Template id=24: `400 Bad Request` + tRPC batch error JSON
- tRPC error code: -32600 (BAD_REQUEST)
- **Result**: Silent block. tRPC error handler catches 400, resets page to initial state
- No error message, no warning banner, no redirect
- Page silently clears textarea — user has no indication content was blocked

### #318: HTTP 429 Too Many Requests (FAILED)
- Changed template: `400 Bad Request` → `429 Too Many Requests`
- tRPC error code: -32009, Added `Retry-After: 60` header
- **Result**: Silent block. tRPC swallows 429 identically to 400

### #319: HTTP 200 OK Fake tRPC Success (FAILED)
- Changed to `200 OK` with tRPC batch success format: `[{"result":{"data":{"json":{...}}}}]`
- **Result**: Silent block. tRPC client-side superjson schema validation rejects fake response

### #320: HAR Capture (KEY DISCOVERY)
- Captured normal Mistral chat response with APF disabled
- **Discovery**: Mistral does NOT use SSE — uses tRPC polling (message.newChat → message.get)
- Response format: NDJSON with superjson, batch result structure
- Key fields: chatId(UUID), messages[], generationStatus, meta.values for Dates
- API gateway: Kong proxy

### #322: NDJSON Exact Format + h2_mode=2 (VISIBLE ERROR!)
- Template: HAR-based exact NDJSON superjson format (827 bytes, 200 OK)
- **Result: VISIBLE_ERROR** — Error 6002 "Oops, Something's Fishy" displayed!
- ERR_HTTP2_PROTOCOL_ERROR on subsequent requests (h2_mode=2 keep-alive corruption)
- Mistral error handler catches protocol error and shows built-in error UI
- **Major improvement**: from silent block (#317-#319) to visible error (#322)

### #323: NDJSON v1 + h2_mode=1 GOAWAY (FAILED)
- Changed h2_mode from 2→1 (GOAWAY) to cleanly close connection after fake response
- **Result**: SILENT_RESET. GOAWAY kills connection before NDJSON payload reaches client
- Worse than #322 — no error, no warning, page silently returns to home

### #324: NDJSON v2 — No Array Brackets (FAILED)
- Removed outer `[...]` array — pure NDJSON object `{result:{...}}`
- title: null, realistic UUID v4, h2_mode=2 (reverted from GOAWAY)
- **Result**: SILENT_RESET. tRPC client rejects non-array format entirely

### #325: tRPC Error Response Format (FAILED)
- Returned tRPC error format `[{error:{message:"...",code:-32600}}]` instead of data
- **Result**: SILENT_RESET. Mistral frontend swallows tRPC errors without UI feedback

### #326: NDJSON v4 — Restored Array + Empty meta.values (CONFIRMED)
- Restored v1 array format `[{result:{data:{...}}}]` + empty `meta.values: {}`
- h2_mode=2 keep-alive + h2_hold_request=1
- **Result**: VISIBLE_ERROR — Error 6002 reproduced! Identical to #322
- User prompt visible in chat, Error 6002 overlay covers page
- **CONFIRMED REPRODUCIBLE**: Array format NDJSON + h2_mode=2 = consistent Error 6002

### Mistral Definitive Comparison (#317–#326)
| Test | Format | h2_mode | Result |
|------|--------|---------|--------|
| #317 | HTTP 400 tRPC error | 1 GOAWAY | SILENT_BLOCK |
| #318 | HTTP 429 tRPC error | 1 GOAWAY | SILENT_BLOCK |
| #319 | HTTP 200 fake tRPC | 1 GOAWAY | SILENT_BLOCK |
| #322 | NDJSON v1 array [{}] | 2 keep-alive | **VISIBLE_ERROR 6002** |
| #323 | NDJSON v1 array [{}] | 1 GOAWAY | SILENT_RESET |
| #324 | NDJSON v2 no array {} | 2 keep-alive | SILENT_RESET |
| #325 | tRPC error [{error}] | 2 keep-alive | SILENT_RESET |
| #326 | NDJSON v4 array+no meta | 2 keep-alive | **VISIBLE_ERROR 6002** |

### Mistral Classification: 🔶 Functional Block (Visible Error)
- Error 6002 is Mistral's built-in error handler — cannot inject custom message
- User sees clear visual feedback that something went wrong
- User's prompt is visible but message is not sent to Mistral servers
- Effective block with visible error indication (better than silent block)

### Mistral Technical Notes
- Protocol: tRPC over HTTP/2 with superjson serialization (NOT SSE)
- API: `message.newChat` batch mutation (POST /api/trpc/message.newChat?batch=1)
- Current: h2_mode=2 (keep-alive), h2_hold_request=1, h2_goaway=0
- Response: NDJSON with superjson encoding — exact format reverse-engineered from HAR #320
- tRPC validates response schema aggressively — HTTP status irrelevant (400/429/200 all fail)
- Only NDJSON array format `[{result:{data:{...}}}]` + h2_mode=2 triggers visible behavior (#322, #326)
- Free access confirmed (no login required)
- Input method: clipboard paste (React textarea requires physical keyboard events)

## B26 Code Fix (deployed)

### path_matcher trailing slash fix
- **File**: `ai_prompt_filter_db_config_loader.cpp` line 189
- **Problem**: Pattern ending with `/` (e.g., `/duckchat/`) failed prefix match against `/duckchat/v1/chat`
- **Fix**: Added `pattern.back() == '/'` condition — trailing slash already serves as separator
- **Build**: [172/172] compiled and linked successfully
- **Deploy**: etap-root-260409.sv.debug.x86_64.el.tgz → test server, etapd restarted
- **Binary timestamp**: Apr 9 13:49 (verified)
