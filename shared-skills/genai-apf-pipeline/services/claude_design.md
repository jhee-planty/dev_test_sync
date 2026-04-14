# Claude — Warning Design

**Date:** 2026-04-02
**Phase:** 2 (Warning Design)
**Reference Task:** Phase 1 Result #151
**Status:** COMPLETE

---

## Strategy

**Selected:** **A** (END_STREAM + GOAWAY, clean termination)

**Justification:** Claude uses HTTP/2 with SSE (text/event-stream) over H2, streaming a well-defined sequence of SSE events. The frontend parses discrete events as they arrive, and Claude does not multiplex multiple streams on the same connection. Strategy A provides clean stream termination with bidirectional close, eliminating network artifacts and ensuring the warning SSE sequence is fully consumed before connection teardown.

**Decision Matrix (Section 3.1):**
- Multiplexing check (1-3): Not observed in Phase 1. Single completion endpoint per conversation. ✓ A eligible.
- Content-Length availability (2): No pre-size confirmation possible; streaming is inherent to SSE. ✓ A required.
- H2 clean termination (3): END_STREAM + GOAWAY match Claude's expected protocol behavior. ✓ A confirmed.

---

## Response Specification

| Field | Value |
|-------|-------|
| **HTTP Status** | `200 OK` |
| **Content-Type** | `text/event-stream; charset=utf-8` |
| **Transfer-Encoding** | H2 framing (implicit; no TE header in H2) |
| **Body Format** | SSE events (RFC 9110 Server-Sent Events) |
| **SSE Delimiter** | `\r\n\r\n` (event terminator) |
| **Warning Text Location** | `content_block_delta` event, `delta.text` field |
| **Required Fields (init sequence)** | `message_start` (with id, type, role, content[], model, usage); `content_block_start` (with index, content_block type); `message_stop` (final terminator) |
| **Expected Body Size** | 1.2–1.8 kB (depending on warning text length; max ~2 kB recommended) |
| **end_stream** | `true` — H2 END_STREAM flag after final SSE event |
| **GOAWAY** | `true` — Bidirectional connection close (Etap policy for Strategy A) |

### HTTP Headers

```
HTTP/1.1 200 OK
Content-Type: text/event-stream; charset=utf-8
Cache-Control: no-cache
access-control-allow-credentials: true
access-control-allow-origin: https://claude.ai
request-id: req_01APFblock0000000000000z
Server: cloudflare
vary: Origin, Accept-Encoding
X-Robots-Tag: none
Content-Length: {body.size()}
```

(Note: Content-Length is generated but removed by `convert_to_http2_response()` in Etap H2 conversion.)

### SSE Event Sequence

The warning is delivered through a complete Claude-compatible SSE sequence:

```
event: message_start
data: {"type":"message_start","message":{"id":"msg_01APFblk0000000000000000z","type":"message","role":"assistant","content":[],"model":"claude-sonnet-4-6","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":1,"output_tokens":0}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"{WARNING_TEXT}"}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":1}}

event: message_stop
data: {"type":"message_stop"}

```

**Event Details:**
- **message_start:** Initializes the message context with a synthetic message ID and model name. Signals to the frontend that a new AI response is arriving.
- **content_block_start:** Opens a text content block (index 0). Frontend creates a message bubble.
- **content_block_delta:** Streams the warning text in the `delta.text` field. Each event carries a text fragment (or the full warning in one event).
- **content_block_stop:** Marks the end of the text block. Frontend stops appending text.
- **message_delta:** Reports completion metadata (stop_reason and usage tokens). Allows frontend to finalize the message.
- **message_stop:** Final terminator. Signals end of SSE stream to the frontend.

**JSON Escaping:** Newlines, quotes, backslashes, tabs within `{WARNING_TEXT}` are escaped (`\n`, `\"`, `\\`, `\t`).

---

## Frontend Rendering Prediction

| Aspect | Prediction | Confidence |
|--------|-----------|------------|
| **Warning appears in** | Chat message bubble (left-aligned, AI assistant styling) | High |
| **Rendered as** | Plain text within the last message bubble in the conversation. No special formatting (unless warning text includes markdown). | High |
| **User experience** | User sees the warning as a normal AI response, indistinguishable from a legitimate Claude answer. No error UI, no retry button. | High |
| **Known artifacts** | None expected. The SSE sequence is complete and matches Claude's normal response format. Chrome EventSource parser accepts the stream without error. | High |

**Rendering flow:**
1. Frontend receives `HTTP 200 + Content-Type: text/event-stream`.
2. EventSource (or fetch with manual SSE parsing) opens stream.
3. `message_start` event → Frontend creates new message context.
4. `content_block_start` → Frontend creates a new text bubble (left-aligned, assistant avatar).
5. `content_block_delta` → Frontend appends warning text to the bubble (character-by-character or batch).
6. `content_block_stop` → Frontend stops appending.
7. `message_delta` + `message_stop` → Frontend marks message as complete, re-enables input.
8. H2 END_STREAM + GOAWAY → Connection closes cleanly; no timeout or hang.

---

## Test Criteria

- [ ] **T1:** Warning text renders in chat bubble as expected (not in error panel, notification, or overlay).
- [ ] **T2:** Message bubble uses correct CSS classes (left-aligned, "assistant" role styling).
- [ ] **T3:** No console errors (no JSON.parse failure, no EventSource error events).
- [ ] **T4:** Warning text is readable and complete (no truncation, no escape-sequence artifacts).
- [ ] **T5:** Conversation thread state is correct after warning (can send next message, no duplicate bubbles, no lost history).
- [ ] **T6:** Network flow shows H2 END_STREAM flag set and GOAWAY frame sent by server.
- [ ] **T7:** Datadog RUM logs show normal response (HTTP 200, no client-side errors).
- [ ] **T8:** Intercom chat (if enabled) does not interfere with warning rendering.

---

## Test Log Points

1. **Frontend JavaScript:** Log EventSource open, message_start/content_block_start, each content_block_delta event, message_stop.
2. **Network:** Capture H2 frame sequence (HEADERS, DATA frames containing SSE events, RST_STREAM or GOAWAY).
3. **DOM:** Verify chat bubble element creation and text content insertion in real-time.
4. **Timing:** Record SSE event delivery interval and total stream lifetime (expected < 100ms for complete sequence).
5. **Error boundary:** Confirm React error boundary (if present) does not intercept the response.
6. **Session state:** Check Redux/Zustand state for conversation messages; verify warning is added as a valid message object.

---

## Relationship to Existing Code

| Aspect | Detail |
|--------|--------|
| **Existing generator** | `ai_prompt_filter::generate_claude_block_response(const std::string& message)` at line 1123 of `ai_prompt_filter.cpp` |
| **Changes needed** | None. The existing generator already implements SSE_STREAM_WARNING pattern with full event sequence, proper JSON escaping, and correct headers. **No code changes required.** |
| **is_http2 value** | `is_http2 = true`. Etap treats Claude responses as H2-compatible and invokes `convert_to_http2_response()` to strip hop-by-hop headers and add H2 framing. |
| **Shared approach with** | ChatGPT (also uses SSE_STREAM_WARNING with similar event sequence). Perplexity uses SSE but with a different event schema (payload validation required, so different pattern). |

### Code Review Notes

The existing `generate_claude_block_response()` function:
- Correctly escapes JSON special characters (quotes, backslashes, newlines).
- Includes all six required SSE events in the correct order.
- Generates synthetic but plausible metadata (message_id, request_id, model name).
- Omits Transfer-Encoding and Connection headers (correct for H2).
- Sets Content-Type and Cache-Control as expected by Claude frontend.

**Confidence in existing code:** Very High. The implementation aligns with Phase 1 frontend profile and RFC 9110 SSE spec.

---

## Notes

1. **Phase 1 Validation:** The Phase 1 frontend profile confirms:
   - SSE via completion endpoint ✓
   - H2 protocol ✓
   - React custom SPA with div#root ✓
   - No multi-stream multiplexing observed ✓
   - tree-sitter script support for markdown/code blocks ✓

2. **Strategy A vs C Distinction:** Although Claude's response is SSE (streaming), Strategy C (Content-Length) was not selected because:
   - Claude normally streams events, not a pre-sized JSON blob.
   - The warning SSE sequence must respect the event delimiters and allow frontend event-by-event parsing.
   - Content-Length would require buffering the entire response before transmission, which defeats SSE's purpose.
   - Strategy A (END_STREAM + GOAWAY) is the natural fit for H2 streaming.

3. **Integration with Etap:** The `convert_to_http2_response()` function in Etap:
   - Removes Content-Length from the response (H2 uses frame size).
   - Converts \r\n\r\n delimiters to H2-compatible framing.
   - Adds END_STREAM flag to the final DATA frame.
   - The caller (main APF filter loop) sends GOAWAY on the connection.

4. **Warning Text Guidelines:**
   - Keep warning under 500 characters for optimal mobile display.
   - Avoid special JSON characters or ensure they are escaped in the generator.
   - Use plain text or markdown (Claude supports markdown rendering).
   - Do not inject control characters or H2 frame breaks.

5. **Intercom + Datadog Integration:** The frontend includes Intercom chat and Datadog RUM. The warning SSE response is in the normal data path, so both services will log it as a normal response (status 200, content-type text/event-stream). No special handling needed.

6. **Known Limitations:**
   - The warning is rendered as a chat message, not a system notification or modal. This is by design (authenticity) but means the user must scroll to see it if the conversation is long.
   - No retry mechanism; once the warning SSE completes and the connection closes, the user cannot re-fetch it without sending a new prompt.

---

## Checklist Results

**Core Items (Summary):**

| Item | Result | Evidence |
|------|--------|----------|
| 1-1: Communication type | SSE | Phase 1 profile: `communication_type: "SSE"` |
| 1-2: HTTP/2 | Yes | Phase 1 profile: `http_protocol: "h2"` |
| 1-3: H2 multiplexing | No | Single completion endpoint observed; no concurrent streams. |
| 2-1: Content-Type | text/event-stream | HAR analysis: completion endpoint response header. |
| 2-3: SSE init events required | Yes | message_start event with role, model, usage fields required. |
| 3-2: Strategy selection | A | H2 + no multiplexing + SSE streaming → Strategy A (END_STREAM + GOAWAY). |

**Full Checklist Record:**

<details>
<summary>Expand full checklist</summary>

### Section 1: Frontend Characteristics

#### 1.1 Communication Protocol
- **1-1:** SSE ✓
- **1-2:** HTTP/2 ✓
- **1-3:** No H2 multiplexing (single stream per completion request) ✓
- **1-4:** SSE delimiter is `\r\n\r\n` (confirmed in existing code) ✓
- **1-5:** No WebSocket for AI responses ✓

#### 1.2 Frontend Rendering
- **2-1:** Expected Content-Type: `text/event-stream; charset=utf-8` ✓
- **2-2:** Frontend parses JSON keys: `type`, `index`, `delta`, `text`, `stop_reason`, `output_tokens` ✓
- **2-3:** SSE init event required: `message_start` with id, type, role, content[], model, usage ✓
- **2-4:** Markdown renderer enabled ✓
- **2-5:** Response consumed as chat bubble (left-aligned, assistant role) ✓
- **2-6:** Minimum condition for bubble creation: `message_start` + `content_block_start` + at least one delta ✓

#### 1.3 Error Handling
- **3-1:** Error handler wrapping level: Not tested in Phase 1; frontend has error boundary for async operations ✓
- **3-2:** Error UI: Generic "Something went wrong" (not fully observed in Phase 1) N/A
- **3-3:** Error UI serves warning role: No (error UI is separate) ✗
- **3-4:** Silent failure on specific status codes: Not observed ✓

### Section 2: Deliverability

- **4-1:** SSE payload validation (checksum/signature): None observed ✓
- **4-2:** Etap single write → H2 stream end: Yes; convert_to_http2_response() applies END_STREAM ✓
- **4-3:** Modifiable fields rendered: Yes; `delta.text` is directly rendered ✓
- **4-4:** Non-standard protocol: No; SSE over H2 is standard ✓
- **4-5:** Field modification side-effects: None expected; `delta.text` is a streaming field ✓
- **4-6:** Alternative delivery method: Not needed; SSE is primary path ✓

### Section 3: Strategy Matrix

| Condition | Result | Priority |
|-----------|--------|----------|
| H2 + multiplexing + GOAWAY → cascade | No multiplexing | N/A |
| Content-Length pre-determined | No (SSE streaming) | Skipped |
| H2 + clean streaming termination | Yes | **→ Strategy A** |
| Keep-alive fallback | Not required | N/A |

**Strategy A confirmed.**

### Section 3.2: Warning Pattern

| Condition | Result | Pattern |
|-----------|--------|---------|
| SSE + no payload validation + init fields known | Yes | **SSE_STREAM_WARNING** |

**Pattern confirmed: SSE_STREAM_WARNING**

### Section 3.3: Early Termination Conditions

None of the early termination conditions apply:
- Error handler wrapping: Not fully wrapped; fetch + EventSource error handling is normal. ✓
- Generic error UI only: Not the case; frontend renders SSE directly as chat. ✓
- WebSocket in use: No. ✓
- Payload validation failure: None observed. ✓

**No early termination; proceed to implementation.**

</details>

---

## Appendix: Phase 1 Reference Data

- **Frontend Profile ID:** 151
- **Service:** Claude
- **Captured:** 2026-04-02T12:25:00+09:00
- **Response Endpoint:** `/api/v1/messages` or `/v1/messages` (completion endpoint, SSE)
- **Streaming Duration:** 3.62s (typical AI response)
- **Third-party Services:** Intercom, Datadog RUM, Segment
- **Frontend Framework:** React custom SPA (div#root)
- **Build ID:** cd5ca868b5

---

## Handoff to Phase 3

**Status:** Ready for Phase 3 Implementation & Testing.

**Test Priority:** High. Claude is a reference implementation (Strategy A). Validation here informs all future H2+SSE services.

**Test Environment:** Etap testbed (Dell-1 → Etap → Dell-2) with live claude.ai network traffic capture.

**Next Step:** Implement Phase 3 test suite (Frontend rendering, console logs, H2 frame inspection, conversation state validation).
