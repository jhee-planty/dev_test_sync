# Grok — Warning Design

**Document Date**: 2026-04-02
**Status**: BLOCKED_ONLY (Phase 1 Analysis)
**Based on**: grok_frontend.md (Phase 1 inspection), ai_prompt_filter.cpp (existing B6 implementation)

---

## Strategy

### Primary: BLOCKED_ONLY

**Reason**: Grok uses NDJSON (newline-delimited JSON) over HTTP/2, which presents fundamental delivery obstacles.

**Key Facts**:
- Grok uses a custom NDJSON protocol — not OpenAI SSE, not standard REST JSON
- Frontend expects specific multi-chunk response sequence with newline delimiters
- Warning text injection into the token field has been tested (Build B1–B7 iterations)
- Best achieved state (B6): Partial success — NDJSON parsing succeeds, token text appears, but redirect occurs and response is incomplete
- Protocol complexity + multiplexing risk on H2 make reliable warning delivery infeasible

**Fallback if BLOCKED_ONLY is unacceptable**:
- See "Alternative Approach (Requires Extended Discussion)" at end of document

---

## Response Specification

### Current Implementation (B6 — Partial Success State)

The existing `generate_grok_sse_block_response()` in `ai_prompt_filter.cpp:1662` delivers a 3-chunk NDJSON response:

```
HTTP/1.1 200 OK
Content-Type: application/json
Cache-Control: no-cache
access-control-allow-credentials: true
access-control-allow-origin: https://grok.com
Content-Length: {body_size}

{result:{conversation:{conversationId:"00000000-apf0-warn-0000-000000000001",...}}}\n
{result:{response:{userResponse:{responseId:"...",message:"",sender:"human",...},...}}}\n
{result:{response:{token:"{WARNING_TEXT}",responseId:"...",messageTag:"final",...}}}\n
```

### B6 State Observation:
- ✓ NDJSON parsing succeeds (frontend reads all 3 chunks)
- ✓ Warning token text is transmitted and partially visible
- ✗ HTTP redirect occurs during streaming (not after completion)
- ✗ Response is truncated/incomplete — user sees partial state, not full conversation
- ✗ Cannot guarantee that all lines are delivered before H2 stream termination

### Why B6 is "Partial Success":
The existing code minimally demonstrates text delivery into the Grok response pipeline. However, it does not guarantee:
1. **Clean termination**: Grok protocol expects additional metadata/finalize events after `messageTag:final`
2. **Frontend synchronization**: The redirect suggests the frontend's state machine (conversation initialization, response completion) does not fully stabilize
3. **H2 multiplexing safety**: Single write into H2 stream carries risk of stream closure before all chunks are buffered/parsed (B3 bug reference — SSE+is_http2=2 scenario)

---

## Frontend Rendering Prediction

### Expected Outcome if B6 Response Delivered:

**Success Case (if all 3 chunks arrive before H2 close)**:
1. Chunk 1 → Grok initializes conversation in state machine (conversationId stored)
2. Chunk 2 → userResponse triggers response bubble creation (empty message, human sender)
3. Chunk 3 → token field populated, messageTag=final signals completion
4. **Result**: Warning text appears in right-aligned AI bubble, but conversation state is inconsistent (duplicate initialization, missing response metadata)

**Failure Case (more likely due to H2 timing)**:
1. H2 stream closes before all chunks are buffered
2. Partial NDJSON parse → incomplete conversation object
3. **Result**: Blank or error state; warning not visible

**Redirect Issue**:
- Phase 1 observation detected a redirect during response (network observation: HTTP 200, but subsequent request redirects suggest Grok interprets B6 state as incomplete)
- This implies the frontend's promise/async handling expects additional finalization events
- Warning is overshadowed by redirect/navigation

### UI Elements That Would Render:
- Chat bubble (if token field arrives): ✓ responsive to token updates
- Warning text content: ✓ (JSON escaping applied)
- Action buttons (regenerate, etc.): ✗ (response metadata incomplete, buttons likely disabled)

### Markdown/Emoji Support:
- Grok supports markdown and emoji → warning text can include formatted emphasis
- Example: `token: "⚠️ **Content policy violation detected**"`

---

## Test Criteria

### Phase 3 Testing (if BLOCKED_ONLY is overridden):

#### Minimal Success Threshold:
- B6 response delivered completely (all 3 chunks buffered before H2 stream close)
- Warning token text visible in conversation bubble
- No page redirect or error page
- User can read the warning before any error state appears

#### Confirmation Points:
1. **Network capture**: Verify all 3 `\n`-delimited JSON lines are transmitted before TCP FIN
2. **Frontend state**: Inspect browser DevTools Network tab for response completeness (no early stream close)
3. **Rendering**: Screenshot shows warning text in AI bubble (right-aligned, Grok styling)
4. **Non-blocking**: Verify no 403/404/5xx response is shown after warning

#### Failure Indicators:
- H2 RST_STREAM or END_STREAM before chunk 3 is buffered
- NDJSON parse error (malformed JSON in chunks)
- Redirect response (e.g., 302/307) interrupts rendering
- Warning text missing or truncated in bubble

---

## Test Log Points

### Key Metrics to Log:

1. **Response Bytes Sent**:
   - `body.size()` (NDJSON chunk total, excluding headers)
   - Individual chunk sizes (for H2 fragmentation analysis)

2. **H2 Frame Sequence**:
   - Number of DATA frames transmitted
   - END_STREAM flag state for each frame
   - Stream ID consistency

3. **Frontend Rendering**:
   - Presence of `result.response.token` in final parsed JSON
   - Conversation state (conversationId registered)
   - Redirect or error page appearance

4. **Timing**:
   - Request-to-response latency
   - H2 stream close timestamp
   - JavaScript fetch completion/error callback

### Log Line Example:
```
[APF_WARNING_TEST:grok] B6_response_generated:
  body_size={sz}, chunks=3, h2_write_count={n_writes},
  stream_id={id}, token_length={tok_len},
  expected_result=partial_success, fallback_expectation=error_page
```

---

## Relationship to Existing Code

### Current State (B1–B7 Iterations):

**File**: `/sessions/ecstatic-loving-davinci/mnt/Officeguard/EtapV3/functions/ai_prompt_filter/ai_prompt_filter.cpp:1662`

**Function**: `generate_grok_sse_block_response(const std::string& message)`

**Current Implementation**: B6 — 3-chunk NDJSON with `\n` delimiters and `messageTag:final`

**Build History**:
- B1–B3: Various chunk formats, incremental testing
- **B3 Bug Note**: "SSE+is_http2=2" — single write into H2 stream causes early closure before frontend parses events (similar risk applies to NDJSON)
- B4–B5: 2-chunk and malformed 3-chunk attempts → "응답 없음" (no response)
- **B6 (current)**: 3-chunk + `\n` → partial_success (#124) — this is the current deployed code
- B7: 2-chunk without conversation → blank

**Key Comment in Code**:
```cpp
// BLOCKED_ONLY 판정이지만, 차단 시 최소한 Grok 에러 페이지를 표시.
// (BLOCKED_ONLY determination, but at minimum show Grok error page on block)
```

### Why No Further Advancement:

The existing B6 code **represents the limit** of what can be reliably achieved with NDJSON injection:

1. **Protocol Mismatch**: Grok's NDJSON is not an SSE stream; it is a request-response protocol with strict sequencing expectations
2. **H2 Timing**: Etap's single-write architecture cannot guarantee all chunks are buffered before H2 closes the stream
3. **State Machine**: Grok frontend's async state machine expects finalization events beyond `messageTag:final`; attempts to provide these (B1–B5) caused parse errors or timeouts

### If BLOCKED_ONLY Is Overridden:

- **No C++ code change required**: B6 is already implemented and deployable
- **Test**: Phase 3 should confirm whether B6 + current H2 handling results in visible warning (unlikely) or error page (likely)
- **Escalation path**: If Phase 3 confirms B6 fails, recommend:
  - Architecture discussion with Grok backend team (can they support a simpler error protocol?)
  - H2 stream control investigation (can Etap ensure multi-frame writes are buffered?)

---

## Notes

### Design Rationale:

**Why BLOCKED_ONLY?**

1. **Grok Protocol Incompatibility**:
   - Unlike ChatGPT (SSE), Grok uses NDJSON — a multi-object, newline-delimited format designed for incremental streaming
   - Each line is a complete JSON object; the frontend expects a specific sequence: `conversation` → `userResponse` → `response.token`
   - Injecting a fake NDJSON response bypasses normal request-response flow, confusing the frontend's state machine

2. **H2 Multiplexing Risk**:
   - Phase 1 observed multiple concurrent requests (skills, monitoring, rate-limits)
   - Single H2 stream carrying warning response may be closed prematurely if other streams demand prioritization
   - B3 bug reference: SSE+is_http2=2 scenario where single write → early close → frontend misses events
   - **Same risk applies here**: Etap's single write of 3 NDJSON lines → H2 buffers → stream closes → Chrome receives partial data

3. **Frontend Async Handling**:
   - Grok uses async/await for response streaming
   - Phase 1 observed 1.7s response time — suggests incremental chunk processing with promise chains
   - Injected response lacks finalization handshake → redirect or incomplete state

4. **Testing Evidence**:
   - B1–B5 iterations confirm that minor protocol deviations → frontend error or no-render
   - B6 achieves "partial_success" but with redirect, meaning warning is overshadowed
   - No configuration parameter in code suggests path to "full success"

### Frontend Profile Alignment:

From grok_frontend.md:
- ✓ SSE over H2 → Actually NDJSON, not SSE
- ✓ OpenAI-compatible format → **False** — Grok format is proprietary
- ✓ React/Next.js frontend → Confirmed, uses async state machine
- ✓ 1.7s fast mode → Suggests incremental response handling
- ✓ 403 errors handled gracefully → But for skill endpoints, not chat responses
- ✗ No evidence that generic HTTP error responses are displayed to user

### Design Document Precedent:

Grok's BLOCKED_ONLY status mirrors:
- **Gemini**: WebSocket-based response → BLOCKED_ONLY (HTTP injection impossible)
- **Gamma**: Polling-based + card-consumption of text → BLOCKED_ONLY (warning absorbed into content)

Unlike:
- **ChatGPT**: OpenAI-compatible SSE → SSE_STREAM_WARNING (standard format, well-understood)
- **M365 Copilot**: Copilot-specific SSE + known init sequence → SSE_STREAM_WARNING (protocol documented, frontend predictable)

### Alternative Approach (Requires Extended Discussion):

If BLOCKED_ONLY is not acceptable, consider:

1. **Error Response with Grok API Compatibility**:
   - Return 403 or 422 JSON error response (not NDJSON)
   - Structure: `{"error":{"message":"{warning_text}","code":"policy_violation"}}`
   - Requires Phase 1 re-inspection to confirm Grok error UI accepts custom messages

2. **Redirect to Intermediate Error Page**:
   - Return 302/307 redirect to Etap-hosted error page
   - Page displays warning, then redirects back to Grok
   - Drawback: Interrupts user session, poor UX

3. **Arch Discussion with Grok Team**:
   - Propose simplified "warning protocol" endpoint on Grok backend (e.g., `/api/warning?msg=...`)
   - Etap redirects to it; Grok displays warning natively
   - Requires cross-team coordination

**Recommendation**: Proceed with BLOCKED_ONLY unless Phase 3 testing of B6 reveals that the error page (redirect target) is user-visible and acceptable.

---

## Summary Table

| Aspect | Finding |
|--------|---------|
| **Verdict** | BLOCKED_ONLY |
| **Reason** | NDJSON protocol mismatch, H2 multiplexing risk, no alternative delivery path |
| **Best Achievable** | B6 — Partial success (token text partial delivery, redirect overshadows warning) |
| **Fallback** | Error page display (requires Phase 1 re-inspection) or arch discussion with Grok |
| **Test Priority** | If Phase 3 required: confirm B6 response completeness, H2 stream timing, redirect detection |
| **Code Reference** | `ai_prompt_filter.cpp:1662` `generate_grok_sse_block_response()` |
| **Documentation** | Frontend profile: `grok_frontend.md` (Phase 1 inspection, 2026-04-02) |
