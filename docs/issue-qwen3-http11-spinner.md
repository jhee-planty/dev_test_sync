# qwen3 HTTP/1.1 Perpetual Spinner — Root Cause Analysis

**Date**: 2026-04-10
**Issue**: #363 — qwen3 keyword block confirmed, but warning message not displayed. Perpetual "생각 중..." spinner.
**Severity**: HIGH — affects all services that fall back to HTTP/1.1 delivery

## Summary

qwen3 is configured with `h2_mode=2` (HTTP/2 keep-alive) but the actual connection falls back to HTTP/1.1 (`http2=0` in etap.log). The block response is delivered as raw HTTP/1.1 bytes (570B, 100% SSL_write success), but the browser shows a perpetual spinner instead of the warning message.

## Key Findings

### 1. Template Structure is CORRECT
- DB HEX dump confirms: headers use CRLF (0D 0A), body uses LF (0A) for SSE events
- Content-Length correctly recalculated by `recalculate_content_length()` (line 1077-1110)
- Template total: 342 bytes raw → ~570 bytes after placeholder rendering
- SSE format: `data: {"choices":[...]}\n\ndata: [DONE]\n\n` — valid per SSE spec

### 2. Content-Length:0 Fix Was UNNECESSARY
- `recalculate_content_length()` at line 1077-1110 ALWAYS recalculates Content-Length to actual `body.size()`
- The bulk CL:0 → `{{BODY_INNER_LENGTH}}` fix (26 templates) was redundant
- Response size remained exactly 570B before and after the fix
- However, the fix is harmless — `{{BODY_INNER_LENGTH}}` in the CL header doesn't resolve (marker is in headers, code looks after body_start), and `recalculate_content_length()` overwrites it

### 3. NO HOLD for HTTP/1.1 — Potential Race Condition
- Hold logic (`_apf_hold_for_inspection`) is ONLY set in `on_http2_request()` (line 648-650)
- `on_http_request()` (HTTP/1.1 handler, line 494) has NO hold logic
- This means for HTTP/1.1: POST is forwarded to server immediately
- If server responds before APF blocks, both responses collide on same connection
- For test cases: keyword detected immediately, server hasn't responded yet → race unlikely
- **For production**: if server is fast or network is slow, race condition IS possible

### 4. Immediate Disconnect After Write
```
Line 639: write_visible_data(&_cproxy, response, 570) → SSL_write success
Line 694: on_disconnected(socket) → tears down connection (HTTP/1.1 mode)
```
- `Connection: keep-alive` in template contradicts immediate disconnect
- Browser receives valid HTTP/1.1 response then connection close
- Content-Length present → browser should parse body before connection close

### 5. BODY_INNER_LENGTH Marker Behavior
- `{{BODY_INNER_LENGTH}}` in Content-Length header → replaced by bil_marker in first pass
- Phase 4 searches for marker AFTER body_start → NOT FOUND (marker is in headers)
- Phase 5: `recalculate_content_length()` replaces entire Content-Length line → marker removed
- Net effect: Content-Length is always correct regardless of template value

## Hypotheses (Ranked by Likelihood)

### H1: Frontend JavaScript SSE Parser Issue (HIGH)
- qwen3's JS expects streaming SSE chunks, receives complete response in one chunk
- OR: JS parser expects `event:` fields, `id:` fields, or specific format we don't provide
- OR: `finish_reason:"stop"` in first delta causes JS to skip content rendering
- OR: `model:"blocked"` triggers error handling instead of content display
- **Verification**: Need browser DevTools Network tab from test PC

### H2: Connection: keep-alive + Disconnect Mismatch (MEDIUM)
- Template says keep-alive, server disconnects
- Browser may log this as connection error and suppress response
- **Fix**: Replace `Connection: keep-alive` with `Connection: close` for HTTP/1.1

### H3: SSL/TLS Record Delivery Race (LOW)
- `write_visible_data` → SSL_write → kernel buffer → TLS record
- `on_disconnected` → SSL_shutdown → close_notify → TCP FIN/RST
- If close_notify arrives in same TCP segment as response, browser may reject
- Unlikely for 570B payload (fits in one TLS record)

### H4: Missing Hold Causes Server Race (LOW for test, HIGH for production)
- POST forwarded to server without hold
- Server responds before APF block response
- Two HTTP responses on same connection → malformed
- Needs code fix for production safety

## Recommended Fixes

### Fix 1: Connection: close for HTTP/1.1 templates (DB)
```sql
-- Not a DB change — handle in C++ instead:
-- In generate_block_response(), for HTTP/1.1 mode,
-- replace "Connection: keep-alive" with "Connection: close"
```

### Fix 2: Add hold support for HTTP/1.1 (C++ code)
Move the hold logic from `on_http2_request()` to `on_http_request()` as well:
```cpp
// In on_http_request() — add after line 523:
auto method = headers->get_method();
bool is_post = (method == "POST");
if (is_post && sd->h2_hold_request && !sd->check_completed) {
    tuple._session._apf_hold_for_inspection = 1;
}
```

### Fix 3: Replace Connection header for HTTP/1.1 in generate_block_response()
```cpp
// In generate_block_response(), before return for HTTP/1.1:
if (!sd->is_http2) {
    // Replace Connection: keep-alive with Connection: close
    auto conn_pos = http1_response.find("Connection: keep-alive");
    if (conn_pos != std::string::npos) {
        http1_response.replace(conn_pos, 22, "Connection: close");
    }
    return http1_response;
}
```

## Verification Plan
- #365: qwen3 CL fix retest (CL:0→BODY_INNER_LENGTH) — likely shows same spinner
- #366: v0 domain fix + qwen3 retest — combined test
- If spinner persists: need browser DevTools HAR capture from test PC
- If spinner resolves: CL fix was the cause despite `recalculate_content_length()` logic

## Related Issues
- `recalculate_content_length()` already fixes Content-Length for ALL templates
- H2 mode conversion strips Content-Length and Connection headers (line 1298-1303)
- Only HTTP/1.1 raw delivery path is affected by these header issues
