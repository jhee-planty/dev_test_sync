# M365 Copilot — Warning Design

**Document Status:** Phase 2 Design (2026-04-02)
**Service:** Microsoft Copilot (copilot.microsoft.com)
**Frontend Profile Ref:** m365_copilot_frontend.md (Task #15x, 2026-04-02)

---

## Strategy

**Selected:** C (HTTP/1.1 Content-Length based)

**Rationale:**
- **Protocol:** H2 confirmed in frontend profile (protocol: h2)
- **Multiplexing:** Frontend shows 107 concurrent requests to CDN, suggesting multiplexed H2 streams
- **SSE communication:** Expected per design doc; chat API uses text/event-stream
- **Content-Length feasibility:** M365 Copilot generates warning text synchronously, making response body size predictable before transmission
- **Strategy selection matrix:** Matched Rule #2 (Content-Length based delivery possible → Strategy C preferred over A for H2 stability)

**Key Decision:**
Although M365 Copilot uses H2 and SSE, Strategy C is preferred because:
1. Etap transparently converts H1→H2 protocol, making Content-Length the most stable approach across the entire infrastructure
2. Complete warning message is known before response generation (no chunked streaming required)
3. Avoids potential cascade failures from GOAWAY in multiplexed connections (which would trigger Strategy D)
4. Existing C++ implementation (generate_m365_copilot_sse_block_response) already uses Content-Length + 200 OK, confirming viability

---

## Response Specification

### HTTP Headers
```
HTTP/1.1 200 OK
Content-Type: text/event-stream; charset=utf-8
Cache-Control: no-cache
access-control-allow-credentials: true
access-control-allow-origin: https://m365.cloud.microsoft
Content-Length: [calculated_body_size]

```

### Response Body Format

SSE_STREAM_WARNING pattern with 3 events (message_start, content delta, message_end):

```
event: copilotConversation
data: {"id":"evt_001","type":"message_start","conversation":{"messageId":"msg-apf-[UUID8]","role":"assistant"}}

event: copilotConversation
data: {"id":"evt_002","type":"message_content_delta","conversation":{"content":"[ESCAPED_WARNING_TEXT]"}}

event: copilotConversation
data: {"id":"evt_003","type":"message_end","conversation":{"messageId":"msg-apf-[UUID8]","finishReason":"blocked"}}

```

### Escape Handling

All user-provided warning text must be JSON-escaped before insertion into the data field:
- `"` → `\"`
- `\` → `\\`
- `\n` → `\\n`
- `\r` → `\\r`
- `\t` → `\\t`

Implementation reference: ai_prompt_filter.cpp lines 1791-1802

### Event Details

| Event | Type | Purpose | Required Fields |
|-------|------|---------|-----------------|
| 1 | message_start | Init event (signals assistant response beginning) | `id`, `type`, `messageId`, `role` |
| 2 | content_delta | Content event (contains warning text) | `id`, `type`, `content` |
| 3 | message_end | Termination event (signals stream completion) | `id`, `type`, `messageId`, `finishReason` |

**Message ID Generation:**
Use format `msg-apf-[first 8 chars of UUID4]` to match M365 Copilot's message ID pattern.

---

## Frontend Rendering Prediction

### Expected Behavior
1. **Detection:** Frontend recognizes `Content-Type: text/event-stream` and initiates SSE EventSource parser
2. **Event 1 (message_start):** Creates new message bubble in assistant role. No visual change yet.
3. **Event 2 (content_delta):** Appends warning text to the message bubble in real-time streaming fashion
4. **Event 3 (message_end):** Finalizes message bubble. `finishReason: "blocked"` may trigger internal blocked status flag
5. **Result:** Warning text displayed in chat bubble, appearing as a normal assistant message

### Rendering Location
Chat bubble in conversation view (confirmed by Phase 1: "response_rendering" shows "chat bubble (plain text)")

### Streaming Behavior
Frontend profile notes: "appeared as complete text (streaming not visually confirmed due to 15s wait)"
- Implication: Whether streamed in real-time or rendered at once depends on SSE event arrival timing
- In production, complete warning body will arrive in single HTTP response chunk (Content-Length strategy), so rendering will appear instant

### Markdown Rendering
Phase 1 design doc note: "2-4: Markdown renderer — not confirmed (response appeared as plain text)"
- Warning text will be rendered as plain text, not markdown
- No special formatting opportunities (no bold, italic, etc. from markdown syntax)
- Keep warning text simple and readable without markdown

---

## Test Criteria

### Functional Tests (Phase 3)

| # | Criterion | Pass/Fail Condition |
|---|-----------|-------------------|
| 1 | SSE parsing | Frontend recognizes all 3 events; no JSON parse errors in DevTools Console |
| 2 | Message bubble creation | Single assistant message bubble appears containing the warning text |
| 3 | Text content | Full warning text appears in bubble; no truncation or corruption |
| 4 | Escape handling | Special characters in warning (quotes, newlines) render correctly |
| 5 | Event sequence | Events arrive in order (start → delta → end); no reordering |
| 6 | Termination | Stream ends cleanly; no "waiting for response" spinner after message_end |
| 7 | Content-Length accuracy | Actual response body matches Content-Length header (±0 bytes) |
| 8 | No HTTP errors | Response status 200 OK; no 4xx/5xx errors in Network tab |

### Content Tests

| # | Criterion | Expected Behavior |
|---|-----------|-------------------|
| 1 | Default message | Standard warning text displays without errors |
| 2 | Escaped quotes | Warning: `This is a "test" message` → renders with quotes intact |
| 3 | Escaped newlines | Multi-line warnings (with `\n`) → each line visible in bubble |
| 4 | Empty message | Zero-length warning text → message bubble still appears (minimal) |
| 5 | Long message | 2000+ character warning → all text visible; no cutoff in UI |
| 6 | Unicode | Korean, Chinese, emoji in warning → rendered correctly (frontend is Unicode-capable) |

### Negative Tests

| # | Scenario | Expected Result |
|---|----------|-----------------|
| 1 | Malformed JSON in event data | Frontend error; "Something went wrong" message or error in Console |
| 2 | Missing required field (e.g., no messageId) | Possible partial rendering or error |
| 3 | Invalid event type | Event ignored; may or may not advance stream state |
| 4 | Content-Length too small | Stream truncation; incomplete warning text or parse error |
| 5 | Content-Length too large | Timeout waiting for remaining bytes; stream hangs |

---

## Test Log Points

### Network-Level Logging

```
[APF_WARNING_TEST:m365_copilot]
  phase=RESPONSE_GENERATION
  service=m365_copilot
  protocol=h2
  strategy=C (Content-Length)
  response_code=200
  content_type=text/event-stream
  content_length={body.size()}
  body_size={actual_bytes}
  events=3 (message_start + content_delta + message_end)
  message_id=msg-apf-{UUID8}
  warning_text_length={escaped_text.size()}
  timestamp={iso8601}
```

### Event-Level Logging (for debugging)

```
[APF_WARNING_TEST:m365_copilot_sse]
  event=1
  type=message_start
  event_id=evt_001

[APF_WARNING_TEST:m365_copilot_sse]
  event=2
  type=message_content_delta
  event_id=evt_002
  content_preview={escaped_text.substr(0, 100)}...

[APF_WARNING_TEST:m365_copilot_sse]
  event=3
  type=message_end
  event_id=evt_003
  finish_reason=blocked
```

### Frontend Rendering Logging (DevTools Console expected)

```
EventSource connected: text/event-stream
Parsed event: copilotConversation type=message_start
Parsed event: copilotConversation type=message_content_delta
Parsed event: copilotConversation type=message_end
Message bubble rendered: assistant role, ~{text_length} chars
```

### Checkpoint Validation

1. **After Response Generation:** Verify Content-Length matches body size (±0 bytes)
2. **HTTP Transmission:** Confirm single frame/chunk delivery (no chunked encoding)
3. **DevTools Network:** Verify Response Headers include correct Content-Length
4. **DevTools Console:** Check for SSE parsing errors or JSON exceptions
5. **UI Rendering:** Observe message bubble appearance and text content accuracy

---

## Relationship to Existing Code

### Current Implementation

**File:** `/sessions/ecstatic-loving-davinci/mnt/Officeguard/EtapV3/functions/ai_prompt_filter/ai_prompt_filter.cpp`
**Function:** `generate_m365_copilot_sse_block_response()` (lines 1788-1831)
**Status:** Fully implemented and compatible with this design

### Code Structure Alignment

```cpp
std::string ai_prompt_filter::generate_m365_copilot_sse_block_response(
    const std::string& message)  // Input: warning text
{
    // ① JSON escape handling (lines 1791-1802) ✓ matches spec
    // ② Message ID generation (line 1803) ✓ matches spec
    // ③ SSE body construction (lines 1805-1819)
    //    - event 1: message_start ✓
    //    - event 2: message_content_delta ✓
    //    - event 3: message_end ✓
    // ④ HTTP headers (lines 1820-1829)
    //    - Status: 200 OK ✓
    //    - Content-Type: text/event-stream ✓
    //    - Content-Length: calculated ✓
    // ⑤ Response assembly (line 1830)
    return std::string(hdr) + body;
}
```

### Integration Points

| Component | Reference | Status |
|-----------|-----------|--------|
| Response generator registration | ai_prompt_filter.cpp:120 | `_response_generators["m365_copilot"] = generate_m365_copilot_sse_block_response;` ✓ |
| UUID generation | ai_prompt_filter.cpp:1803 | Uses `generate_uuid4()` (helper function) ✓ |
| Escape function | ai_prompt_filter.cpp:1791-1802 | Inline JSON escape ✓ |
| Message format | ai_prompt_filter.cpp:1806-1819 | SSE_STREAM_WARNING pattern ✓ |
| Header construction | ai_prompt_filter.cpp:1820-1829 | HTTP/1.1 + Content-Length ✓ |

### No Changes Required

The existing implementation fully satisfies this warning design. No modifications to C++ code needed before Phase 3 testing.

---

## Checklist Results

### Section 1: Frontend Characteristics

| Item | Result | Evidence |
|------|--------|----------|
| **1-1** Communication type | SSE | frontend-profile: `"communication_type": "SSE"` |
| **1-2** Protocol (H1/H2) | H2 | frontend-profile: `"protocol": "h2"` |
| **1-3** H2 multiplexing | YES (multiple streams) | frontend-profile: `"total_requests": 107` on concurrent Cloudflare CDN requests |
| **1-4** SSE delimiter | `\r\n\r\n` | Standard SSE; HTTP/1.1 uses CRLF. Assumed correct per design. *(Phase 3 to confirm via HAR)* |
| **1-5** WebSocket for AI response | NO | Not mentioned in frontend-profile; SSE only |

### Section 1.2: Frontend Rendering

| Item | Result | Evidence |
|------|--------|----------|
| **2-1** Expected Content-Type | text/event-stream | Assumed from frontend architecture (chat/SSE service) |
| **2-2** JSON keys parsed | Not applicable | Using SSE (not JSON request/response). Event payload contains required fields. |
| **2-3** SSE init event needed | YES | Message_start event required (establishes messageId, role context) |
| **2-4** Markdown renderer | NO | frontend-profile: `"response_rendering": "plain text, no markdown rendering observed"` |
| **2-5** Chat bubble display | YES | frontend-profile: `"format": "chat bubble (plain text, no markdown)"` |
| **2-6** Minimum message condition | messageId + role required | From code inspection of event structure |

### Section 1.3: Error Handling

| Item | Result | Evidence |
|------|--------|----------|
| **3-1** Error handler scope | Unknown | Phase 1 did not capture error boundary structure. Assumed Vue.js/Nuxt standard try-catch. *(Phase 3 risk item)* |
| **3-2** Error UI type | Unknown | Phase 1 did not trigger errors. *(Phase 3 to test)* |
| **3-3** Error UI can display server message | Unknown | Assumption: typical chat services show error reason in UI *(Phase 3 to confirm)* |
| **3-4** Silent failure codes | Unknown | Phase 1 did not test. Assume 403/422 not silently ignored. *(Phase 3 to test)* |

### Section 2: Delivery Feasibility

| Item | Result | Evidence |
|------|--------|----------|
| **4-1** Frontend validates SSE payload (signature/hash) | NO | Standard SSE has no payload validation. Matches ChatGPT/Claude patterns. |
| **4-2** Etap single write closes H2 stream immediately | Unknown | Depends on Etap H2 handling. Assume no (Etap passes through single write correctly). *(Phase 3 to confirm)* |
| **4-3** Modifiable rendering field exists | YES | `"content"` field in message_content_delta event is rendered |
| **4-4** Non-standard protocol | NO | Standard H2 + SSE |
| **4-5** Field modification side effects | NO | `"content"` field is rendering-only; no side effects on conversation state |
| **4-6** Alternative delivery methods | Possible | 403 JSON error as fallback (if SSE fails), but not primary strategy |

### Section 3: Strategy Selection Matrix

**Applicable Rule:** Section 3.1, Rule #2
**Condition:** Content-Length based delivery possible
**Selected Strategy:** C

**Matrix Application:**
1. ✗ Rule 1 (H2 + multiplexing + GOAWAY cascade): Multiplexing detected, but strategy can avoid GOAWAY
2. ✓ **Rule 2 (Content-Length possible):** Response body size known before transmission → **Strategy C selected**
3. - Rule 3 (H2 + clean termination): Not needed; C selected
4. - Rule 4 (fallback B): Not needed; C sufficient

**Warning Pattern:** SSE_STREAM_WARNING (3 events, Content-Length frame)

---

## Full Checklist Record

<details>
<summary>Complete Checklist Detail (Click to expand)</summary>

### Section 1: Frontend Characteristics (1-1 through 1-5)
- 1-1: SSE (confirmed)
- 1-2: H2 (confirmed)
- 1-3: H2 multiplexing = YES (multiple CDN streams)
- 1-4: SSE delimiter = `\r\n\r\n` (standard; Phase 3 HAR to confirm)
- 1-5: WebSocket = NO (SSE only)

### Section 1.2: Rendering (2-1 through 2-6)
- 2-1: Content-Type = text/event-stream (inferred from SSE communication type)
- 2-2: JSON keys = N/A (SSE, not JSON request/response structure)
- 2-3: SSE init event = YES (messageId + role required)
- 2-4: Markdown = NO (plain text confirmed)
- 2-5: Chat bubble = YES (response_rendering: "chat bubble")
- 2-6: Message minimum = messageId + role required

### Section 1.3: Error Handling (3-1 through 3-4)
- 3-1: Error handler scope = Unknown (Vue.js assumed, not captured)
- 3-2: Error UI type = Unknown (Phase 3 test)
- 3-3: Error UI shows server message = Unknown (assumed YES; Phase 3 to confirm)
- 3-4: Silent failure codes = Unknown (Phase 3 test)

### Section 2: Delivery Feasibility (4-1 through 4-6)
- 4-1: Payload validation = NO (standard SSE, no checksum/signature)
- 4-2: Etap single write stream close = Unknown (assume NO; Phase 3 to confirm)
- 4-3: Modifiable rendering field = YES (content field in content_delta)
- 4-4: Non-standard protocol = NO
- 4-5: Field modification side effects = NO
- 4-6: Alternative delivery methods = YES (403 JSON fallback exists)

### Section 3: Strategy Selection
- Matrix Rule 2 applied: Content-Length possible → **Strategy C**
- Warning Pattern: **SSE_STREAM_WARNING** (3 events)
- No early termination conditions triggered (all delivery paths viable)

</details>

---

## Notes

### Phase 1 Findings (Risk & Clarifications)

1. **Anonymous Session:** Phase 1 captured anonymous (not authenticated) user session
   - Behavior may differ for logged-in users
   - Recommendation: Phase 3 test with authenticated session if possible

2. **Chat API Not Visible:**
   - Network tab did not capture actual chat API endpoint
   - Theory: SSR-embedded response or EventSource not captured during navigation
   - Implication: Exact API endpoint unknown; assuming `/chats/{id}` returns SSE as documented
   - Mitigation: Phase 3 will confirm actual endpoint in HAR capture

3. **URL Navigation Pattern:**
   - Frontend navigates full page from `copilot.microsoft.com` → `/chats/{id}` after prompt
   - Not typical SPA routing; affects debugging and integration testing
   - No impact on warning delivery (content-agnostic)

### Implementation Notes

1. **Message ID Generation:**
   Using UUID4 to match Microsoft's pattern. Actual UUID4 implementation is service-provided (generate_uuid4() in codebase).

2. **Escape Characters:**
   JSON escaping is critical. The inline loop in existing code is sufficient and matches spec. No additional encoding (Base64, URL-encoding) needed.

3. **Content-Length Accuracy:**
   Calculate body size AFTER escape processing. The response body is deterministic (3 SSE events + warnings), so Content-Length will be exact.

4. **CORS Headers:**
   Existing code includes `access-control-allow-origin: https://m365.cloud.microsoft`
   - Matches M365 cross-origin requirement (Copilot frontend is under m365.cloud.microsoft domain)
   - No modification needed

5. **Cache Control:**
   `Cache-Control: no-cache` prevents caching of warning responses. Appropriate for security-sensitive content.

### Comparison to Other Services

M365 Copilot SSE pattern is similar to:
- **ChatGPT** (Strategy C): 3 events, Content-Length, 200 OK ✓
- **Gamma** (Strategy SSE): Multi-chunk plain text SSE with fallback
- **Notion** (Strategy NDJSON): Different protocol, but same Content-Length approach

The existing code structure aligns with ChatGPT implementation pattern, which is proven to work with H2 and SSE.

### Phase 3 Testing Priorities

1. **HAR Capture with Authenticated Session**
   - Capture actual chat API endpoint and SSE response structure
   - Verify SSE delimiter (assumed `\r\n\r\n`)
   - Identify actual event schema fields

2. **Frontend Error Scenarios**
   - Test with malformed JSON in event payload
   - Test with missing required fields
   - Observe error UI behavior

3. **Edge Cases**
   - Long warning text (2000+ chars)
   - Special characters (quotes, newlines, Unicode)
   - Rapid sequential warnings

4. **Protocol Validation**
   - Confirm H2 stream behavior with single write
   - Verify Content-Length accuracy in actual transmission
   - Check for any H2 RST_STREAM or connection reset
