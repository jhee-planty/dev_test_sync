## Gemini — Warning Design

**Service ID:** gemini (also aliases: gemini3)
**Frontend Profile Source:** Phase 1 capture #153 (2026-04-02)
**Status:** Warning delivery design (Phase 2)

---

## Strategy

**Selected: Strategy D (END_STREAM only, GOAWAY=false)**

### Rationale

Gemini uses HTTP/2 with active multiplexing on the same connection. The batchexecute protocol maintains multiple concurrent streams within a single H2 connection.

- **Primary constraint:** GOAWAY frame on multiplexed H2 connections causes cascade failure. When Etap sends GOAWAY, Chrome's H2 implementation treats the entire connection as closed, terminating all concurrent streams — blocking subsequent prompts in the same session.
- **History (B2):** Attempt with `is_http2=2, GOAWAY=true` → server response collision → ERR_HTTP2_PROTOCOL_ERROR
- **History (B6):** Restored `is_http2=1, GOAWAY=true` → server connection close + client graceful shutdown (works, but not ideal for warning delivery)
- **Current decision:** END_STREAM=true without GOAWAY. This signals "this specific stream is complete" while allowing the connection to remain open for multiplexed operations.

### HTTP/2 Behavior Under Strategy D

```
Client → Gemini request (stream N)
              ↓
Etap MITM intercepts
              ↓
Generate warning in protobuf-over-JSON format
              ↓
Send HTTP/2 DATA frame (stream N):
  - Flag: END_STREAM=true (close this stream only)
  - Flag: GOAWAY=false (do NOT close the connection)
  - Content: wrb.fr envelope + )]}' security header + payload
              ↓
Chrome/Blink HTTP/2 codec:
  - Stream N marked complete (received full response)
  - Connection remains open (no cascade failure)
  - Multiplexed streams unaffected
  - Frontend receives warning, can issue next request on new stream
```

---

## Response Specification

### Overall Structure

```
)]}'\n\n{length}\n{wrb.fr_envelope}
```

### Components

#### 1. Security Header
```
)]}'\n\n
```
- XSS prevention header used by Google APIs
- Prevents JSON from being executed as script
- Literal bytes: `)`, `]`, `}`, `'`, `\n`, `\n`

#### 2. Length Declaration
```
{decimal_length}\n
```
- Decimal length of the wrb.fr envelope (not including )]}' or the length line itself)
- Single newline terminator

#### 3. wrb.fr Envelope (JSON Array)

The response must be a JSON array containing a single wrb.fr frame:

```json
[["wrb.fr","XqA3Ic","{payload_inner_json_string}",null,null,null,"generic"]]
```

**Field breakdown:**
- Index 0: `"wrb.fr"` — frame type identifier
- Index 1: `"XqA3Ic"` — request ID (fixed for warning responses)
- Index 2: `"{payload_inner_json_string}"` — the actual response payload (itself a JSON string)
- Indices 3–6: null, null, null, `"generic"` — required padding

#### 4. Payload Inner Structure (Double-Escaped JSON)

The content at envelope[2] is a **JSON string** (quoted, escaped), containing the actual nested array:

```json
"[[\"warning_text\",null,null,null,[],null,null,null,null,null,null,null,null,null,null,null,null,null,[],null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null]]"
```

**Key detail:** The warning text must be at position `[0][0]` (first element of the first sub-array).

### Escaping Rules (Two Levels)

#### Level 1: Warning Message → JSON String
Escape the warning message for embedding in a JSON string:
- `"` → `\"`
- `\` → `\\`
- `\n` → `\n` (literal backslash-n, not newline)
- `\r` → `\r`
- `\t` → `\t`

#### Level 2: Envelope Payload → JSON String
The Level 1 result must be escaped again for the outer JSON layer:
- `"` → `\"`
- `\` → `\\`
- (No need to re-escape control characters; they're already escaped from Level 1)

### Complete Example

Warning message: `"This request was blocked."`

Level 1 escape:
```
This request was blocked.
```
(No special characters, remains unchanged)

Level 2 escape + wrb.fr construction:
```json
[[\"This request was blocked.\",null,null,null,[],null,null,null,null,null,null,null,null,null,null,null,null,null,[],null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null]]
```

Envelope:
```json
[["wrb.fr","XqA3Ic","[[\"This request was blocked.\",null,null,null,[],null,null,null,null,null,null,null,null,null,null,null,null,null,[],null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null]]",null,null,null,"generic"]]
```

Final body:
```
)]}'\n\n{envelope_length}\n{envelope_json}
```

### HTTP Headers

```
HTTP/1.1 200 OK
Content-Type: application/x-protobuf
Cache-Control: no-cache
access-control-allow-credentials: true
access-control-allow-origin: https://gemini.google.com
Content-Length: {body_length}

{body}
```

**Critical:** Status must be 200 OK (not 403 or 4xx). Gemini frontend silently ignores error responses — 403 produces BLOCKED_SILENT_RESET.

---

## Frontend Rendering Prediction

### Expected Behavior (Success)

1. **Frontend receives response:** Chrome HTTP/2 codec processes DATA frame with END_STREAM=true on stream N
2. **XHR completion:** The batchexecute XHR handler detects response ready
3. **Response parsing:** BardChatUi JS module (boq-bard-web) parses wrb.fr envelope
4. **Message extraction:** JS reads `payload[0][0]` for the text content
5. **UI rendering:** Text appears in the left-aligned AI response bubble with Gemini sparkle icon
6. **Markdown rendering:** If warning contains markdown, it will be rendered (BardChatUi supports markdown)

### Observed UI Result

User sees a chat bubble containing the warning text, indistinguishable from a normal Gemini response. The warning message is rendered in the standard Gemini response style.

### Failure Mode: Silent Reset

If the response uses HTTP status 403 or 422, the frontend ignores it entirely. The batchexecute handler treats the error response as a no-op, and the UI resets to the initial prompt screen without showing any message.

---

## Test Criteria

### Phase 3 Validation Checklist

- [ ] **HTTP/2 Stream State:**
  - Etap sends DATA frame with END_STREAM=true
  - Etap does NOT send GOAWAY frame
  - Frame lands on the same stream as the original batchexecute request

- [ ] **Response Format:**
  - Body begins with `)]}'\n\n` (exact bytes)
  - Length declaration is present and accurate
  - wrb.fr envelope parses as valid JSON
  - Payload inner JSON is correctly double-escaped

- [ ] **Frontend Reception:**
  - Warning appears in the left chat bubble (not error page)
  - Text content is exactly as specified
  - Markdown in the warning (if any) is rendered

- [ ] **Connection Persistence:**
  - After warning is received, the H2 connection remains open
  - User can send a subsequent prompt in the same conversation
  - No ERR_HTTP2_PROTOCOL_ERROR or cascade failure

- [ ] **No Silent Reset:**
  - Frontend does NOT silently reset to the initial screen
  - Chat history remains visible

### Failure Indicators

| Symptom | Root Cause | Recovery |
|---------|-----------|----------|
| Chat bubbles show nothing; UI resets to blank | Status code 403/422 used | Change to 200 OK |
| "Something went wrong" error displayed | wrb.fr JSON invalid or payload missing keys | Verify envelope structure and double-escaping |
| ERR_HTTP2_PROTOCOL_ERROR in DevTools | GOAWAY frame sent or stream flags incorrect | Verify END_STREAM=true, GOAWAY=false |
| Cascade failure: subsequent prompts blocked | Connection closed after warning | Ensure GOAWAY not sent |
| Text truncated or misaligned in bubble | Escaping error in Level 1/2 | Verify quote and backslash handling |

---

## Test Log Points

Deploy Etap with generate_gemini_block_response active. Capture the following:

1. **APF Module Log:**
   ```
   [APF_WARNING_TEST:gemini] Generated Gemini block response: body_size={N}
   ```
   - Confirm: body_size is positive (typically 500–800 bytes for typical warning)
   - Confirm: log appears when gemini service is blocked

2. **HTTP/2 Frame Inspection (via Etap logs or Chrome DevTools):**
   - Stream ID: should match the incoming batchexecute request stream
   - Flags: DATA frame with END_STREAM=true
   - Payload: matches the body constructed above

3. **XHR Request/Response in Chrome DevTools (Network tab):**
   - Request: POST to batchexecute endpoint with rpcids=...
   - Status: 200 OK
   - Response preview: should show the `)]}'\n\n...` content
   - (Note: DevTools may not render the JSON preview correctly due to the )]}' prefix; raw response must be inspected)

4. **Frontend Behavior:**
   - Screenshot: warning text appears in left-aligned bubble with Gemini sparkle icon
   - Console: no JavaScript errors related to parsing or rendering

5. **Connection State Post-Warning:**
   - Issue a follow-up prompt
   - Log: new batchexecute request on the same or new stream
   - Confirm: connection did not close (no GOAWAY seen)

---

## Relationship to Existing Code

### Current Implementation (ai_prompt_filter.cpp)

**Function:** `ai_prompt_filter::generate_gemini_block_response(const std::string& message)`
**Location:** Lines 1578–1640

**Key behaviors:**
1. **Two-level JSON escaping** (lines 1583–1604):
   - Level 1 (je1): Escape message for JSON string
   - Level 2 (je2): Escape je1 for the envelope payload field

2. **wrb.fr Envelope construction** (lines 1615–1621):
   - Builds the nested array with the escaped message at position [0][0]
   - Wraps it in `[["wrb.fr","XqA3Ic",...]]`

3. **Length + data format** (lines 1622–1626):
   - Computes envelope size
   - Prepends `)]}'\n\n` and length declaration

4. **HTTP 200 response headers** (lines 1628–1637):
   - Status: 200 OK (not 403)
   - Content-Type: application/x-protobuf
   - CORS headers for gemini.google.com

**Design decisions codified:**
- Uses HTTP/1.1 in the response header (line 1630), but Etap converts to HTTP/2 during transmission
- Content-Length is explicit (allows Strategy C/D to function)
- No streaming; entire response sent in one write (supports Strategy D)

### Integration with APF Block Flow

1. **Registration:** Line 116–117 maps "gemini" and "gemini3" service names to `generate_gemini_block_response`
2. **Invocation:** Called during block decision, passed the warning message string
3. **Return value:** Complete HTTP response (headers + body)
4. **Transmission:** Etap's H2 handler sends the response with END_STREAM=true

### No Strategy A or B for Gemini

- **Strategy A (END_STREAM + GOAWAY):** Would trigger cascade failure on Gemini's multiplexed streams. Not viable.
- **Strategy B (keep-alive, network error):** Would leave the stream in an ambiguous state. Not appropriate for warning delivery where clean termination is necessary.
- **Strategy C (Content-Length based):** Theoretically possible (the current code uses Content-Length), but Strategy D is preferable because it explicitly marks the stream complete without signaling connection closure.

---

## Notes

### Design Complexity: Why Gemini is Hardest

Gemini's warning delivery is the most complex in the APF suite because it combines:

1. **Non-SSE protocol:** Unlike ChatGPT (SSE) or Claude (SSE), Gemini uses batchexecute/webchannel with custom protobuf-over-JSON encoding. No standard streaming format.
2. **Multiplexed connection:** H2 multiplexing means a single close (GOAWAY) breaks ALL concurrent streams, not just the target.
3. **Double-escaped JSON:** The wrb.fr envelope requires JSON escaping at two levels, creating a high error surface.
4. **Strict status code requirement:** 403 response is silently ignored (BLOCKED_SILENT_RESET). Only 200 works.
5. **Google security header:** The `)]}'\n\n` prefix is unusual and must be exact.

### Historical Context: B2 vs B6

- **Build B2 (failed):** Attempted `is_http2=2` with GOAWAY=true. Server's H2 codec collided with Etap's frame interpretation → ERR_HTTP2_PROTOCOL_ERROR.
- **Build B6 (works for block, not ideal for warning):** Restored `is_http2=1, GOAWAY=true`. Works for block scenarios because users don't expect to continue. But for warnings, we want the connection to stay open.
- **Current design (Strategy D):** END_STREAM only. Balances safety (no cascade failure) with usability (connection remains open for follow-up prompts).

### Markdown Support

The BardChatUi renderer (boq-bard-web) supports markdown. Warning messages can include:
- `**bold**`
- `*italic*`
- `` `code` ``
- Lists, headings, etc.

This allows rich formatting without additional complexity.

### GOAWAY History

The comment at line 1641–1661 in ai_prompt_filter.cpp documents the Grok service's similar challenge. Grok also uses non-SSE (NDJSON) and faced GOAWAY cascade failures. Grok ultimately settled on BLOCKED_ONLY because NDJSON had incompatible payload validation. Gemini avoids this fate because the wrb.fr envelope is flexible enough to accept arbitrary text in the [0][0] position.

### Known Risks

1. **If frontend changes:** If Google modifies the boq-bard-web BardChatUi module to add payload signature validation or change the rendering position, this design will break. Phase 1 should be re-run on frontend changes.
2. **If Gemini migrates away from batchexecute:** Some speculation that Gemini may eventually move to a more standard protocol. Current design is specific to batchexecute.
3. **Multi-turn context:** The warning appears as a single AI response. If the user clicks "regenerate" or edits their original prompt, they will resend the request and may trigger another block. This is expected behavior (not a design flaw).

### Verification Notes for Phase 3

When testing, use the exact warning message:
```
This request was blocked by your organization's AI usage policy.
```

This message has no special characters, avoiding edge cases in escaping. Once Phase 3 confirms the basic mechanism works, test with messages containing:
- Quotes: `"example"`
- Backslashes: `path\to\file`
- Newlines (will appear as literal text in the bubble)
- Markdown: `**bold warning message**`

This will validate that Level 1 and Level 2 escaping are working correctly.

---

## Checklist Results

| Item | Result | Notes |
|------|--------|-------|
| **1-1: Communication type** | batchexecute (webchannel) | Non-SSE; protobuf-over-JSON via Google webchannel |
| **1-2: HTTP protocol** | H2 | HTTP/2, multiplexed |
| **1-3: Multiplexed streams** | YES | Multiple concurrent requests on same connection |
| **1-4: SSE delimiter** | N/A | Not SSE service |
| **1-5: WebSocket for responses** | NO | Uses HTTP batchexecute, not WebSocket |
| **2-1: Expected Content-Type** | application/x-protobuf | Frontend expects protobuf encoding (or wrb.fr JSON) |
| **2-2: JSON parsing keys** | payload[0][0] | Text extracted from nested array first position |
| **2-3: SSE init event** | N/A | Not SSE |
| **2-4: Markdown renderer** | YES | BardChatUi supports markdown formatting |
| **2-5: Chat bubble rendering** | YES | Response displayed in left-aligned bubble with icon |
| **2-6: Bubble creation condition** | Payload at [0][0] with valid wrb.fr envelope | Minimal structure: [["wrb.fr","XqA3Ic",payload,null,null,null,"generic"]] |
| **3-1: Error handler coverage** | Full catch | BardChatUi wraps entire XHR flow; errors are caught |
| **3-2: Error UI** | Generic error or silent reset | 403 → BLOCKED_SILENT_RESET; generic error on parse failure |
| **3-3: Error UI with server message** | NO | Error UI does not display custom messages; only generic "Something went wrong" |
| **3-4: Silent failure on status codes** | YES (403) | 403 Forbidden triggers silent reset without user notification |
| **4-1: Payload validation** | NO | wrb.fr envelope has no signature/checksum validation |
| **4-2: H2 stream termination** | Immediate (single write) | Etap sends entire response in one DATA frame; stream closes on END_STREAM |
| **4-3: Modifiable fields in rendering** | YES | Position [0][0] is the text field; fully modifiable |
| **4-4: Non-standard protocol** | YES | batchexecute/webchannel is Google-proprietary |
| **4-5: Side effects of field modification** | NO | Changing [0][0] does not break thread or state |
| **4-6: Alternative delivery paths** | NO | batchexecute is the sole AI response channel; no fallback |
| **Strategy Selection** | **D (END_STREAM only, GOAWAY=false)** | H2 multiplexing + non-SSE protocol demands Strategy D; History B2/B6 confirm constraint |
| **Warning Pattern** | **CUSTOM: Gemini wrb.fr + )]}' security header** | No existing pattern matches batchexecute; requires service-specific design |
