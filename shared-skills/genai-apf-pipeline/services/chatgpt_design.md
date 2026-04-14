## ChatGPT — Warning Design

### Strategy

- Pattern: `SSE_STREAM_WARNING`
- HTTP/2 strategy: **C** (Content-Length based)
- Based on:
  - Frontend Phase 1 inspection confirms text/event-stream (SSE) over HTTP/2
  - React/Next.js frontend with markdown renderer support
  - Error UI shows generic "Something went wrong" with retry button
  - Existing `generate_chatgpt_sse_block_response()` demonstrates proven SSE event structure
  - Response size is fully determined (not streaming) — Content-Length calculation is exact

### Response Specification

- **HTTP Status**: 200 OK
- **Content-Type**: `text/event-stream; charset=utf-8`
- **Transfer-Encoding**: Not included (Content-Length used instead)
- **Body format**: Server-Sent Events (SSE) with ChatGPT delta encoding v1
- **SSE delimiter**: `\r\n\r\n` (standard SSE)
- **Warning text**: Inserted into message content via delta patch event
- **Required fields**:
  - `event: delta_encoding` with `data: "v1"` (encoding declaration)
  - `event: delta` with message initialization (conversation_id, message_id, author role=assistant, status=in_progress)
  - `event: delta` with content patch appending warning text to `/message/content/parts/0`
  - `event: delta` with completion patches (status=finished_successfully, end_turn=true)
  - Termination event: `data: [DONE]` and `data: {\"type\":\"message_stream_complete\", ...}`
- **Expected body size**: ~1,200–1,500 bytes (calculated before sending; includes event overhead)
- **end_stream**: true (H2 signal after all data sent)
- **GOAWAY**: false (no connection close; allows other streams on same H2 connection)

### Frontend Rendering Prediction

- **Warning appears in**: Chat message bubble, right-aligned as AI response
- **Rendered as**: Markdown-formatted text (bold, links, code blocks supported)
- **User experience**: Warning message displays in chat UI indistinguishable from normal AI response
- **Known artifacts**:
  - After warning, chat input box remains ready (no retry button)
  - Message marked as finished_successfully, so no "loading" indicator
  - No error UI triggered (status 200, valid SSE structure)

### Test Criteria

- [ ] HTTP 200 response received by frontend
- [ ] Content-Type correctly parsed as text/event-stream
- [ ] Content-Length header matches actual body size
- [ ] SSE delta_encoding event with v1 parsed without error
- [ ] Message initialization event creates assistant message with correct conversation_id and message_id
- [ ] Warning text appears in chat bubble without truncation
- [ ] Markdown formatting (if present in warning text) renders correctly
- [ ] Message marked as finished_successfully (no "loading" spinner)
- [ ] Chat UI remains interactive after warning (input box functional)
- [ ] No retry button or error dialog appears
- [ ] HAR shows H2 stream ends cleanly (no RST_STREAM errors)

### Test Log Points

- `[APF_WARNING_TEST:chatgpt] SSE response generated, body_size=%zu bytes, Content-Length=%zu`
- `[APF_WARNING_TEST:chatgpt] Delta encoding v1 event sent`
- `[APF_WARNING_TEST:chatgpt] Message init: conversation_id=%s, message_id=%s`
- `[APF_WARNING_TEST:chatgpt] Warning text appended: %d bytes to /message/content/parts/0`
- `[APF_WARNING_TEST:chatgpt] Stream completion events sent, final [DONE] marker`
- `[APF_WARNING_TEST:chatgpt] Frontend rendering: warning visible in chat bubble`

### Relationship to Existing Code

- **Existing generator**: `ai_prompt_filter::generate_chatgpt_sse_block_response()`
  - Location: `/sessions/ecstatic-loving-davinci/mnt/Officeguard/EtapV3/functions/ai_prompt_filter/ai_prompt_filter.cpp:1049`
  - Already implements correct SSE event structure (delta_encoding, message init, content patch, completion)
  - Dynamically generates conversation_id and message_id using `generate_uuid4()`
  - Properly escapes JSON special characters in message text
  - Uses HTTP/1.1 headers with Content-Length (Etap converts to HTTP/2 automatically)

- **Changes needed**: None required — existing implementation already follows this design
  - Confirm `is_http2` flag is true when handler is invoked (Etap framework handles conversion)
  - Verify `generate_uuid4()` is available and linked
  - Ensure Content-Length calculation includes all SSE event bytes

- **is_http2 value**: true (ChatGPT API uses HTTP/2; Etap's `convert_to_http2_response()` processes the HTTP/1.1 formatted response)

- **Shared approach with**:
  - Claude (`generate_claude_block_response()`) — both use SSE event sequencing, but Claude's event types differ
  - Perplexity (`generate_perplexity_block_response()`) — both use SSE for streaming responses

### Notes

**Phase 1 findings validated:**
- Non-logged-in access confirmed working
- React/Next.js frontend with ProseMirror-like input confirmed
- SSE (text/event-stream) confirmed
- HTTP/2 (h2) confirmed from frontend-profile
- Markdown renderer confirmed from render analysis
- CORS headers present in existing implementation

**Design decision rationale:**
1. **Strategy C over A**: Although SSE is used, the warning response is entirely pre-generated (no need for chunked streaming). The complete body size is known before sending, making Content-Length calculation possible. This is more robust than relying on stream-end signaling.

2. **No payload verification**: ChatGPT frontend does not validate SSE payload checksums or signatures (unlike Perplexity). Standard delta encoding format is sufficient.

3. **SSE event structure**: Existing code provides a proven template. The four-event sequence (encoding → init → content patch → completion) matches ChatGPT's frontend expectations based on HAR analysis.

4. **H2 GOAWAY omission**: No other multiplexed streams are expected in typical usage, but omitting GOAWAY follows best practice for CDN-fronted APIs where multiple requests may share a single H2 connection.

**Risk mitigation:**
- UUID generation must succeed; `generate_uuid4()` should not return empty string
- Message text must not exceed Content-Length calculation; escape sequences must account for all special characters
- HTTP header ordering should match ChatGPT's typical response (not a blocking issue, but helps with debugging)

**Prior art reference:**
→ Prior network-level analysis: `_backup_20260317/apf-add-service/services/chatgpt.md` (if available — this design supersedes it with Phase 1 frontend inspection data)
