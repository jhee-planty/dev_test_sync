# Notion AI — Warning Design

**Captured**: 2026-04-02 (Task #15x, Phase 1 completed)
**Framework**: React SPA with service worker
**Communication**: NDJSON (REST API over HTTP/2)
**Status**: CUSTOM NDJSON_WARNING pattern

---

## Strategy

**Selected**: **CUSTOM: NDJSON_WARNING** (Strategy C candidate, finalized as custom NDJSON pattern)

**Rationale:**
- Notion AI uses **NDJSON** (newline-delimited JSON) with **JSON Patch** operations — a non-streaming, non-SSE protocol
- The frontend expects responses as JSON Patch sequences (`type: "patch"` objects) modifying a hierarchical state tree (`/s/[index]/field` paths)
- Response is **not** SSE (`text/event-stream`) nor streaming-required; entire response is generated upfront and sent with `Content-Length`
- This maps to **Strategy C** in the HTTP/2 strategy matrix: "Content-Length based" — Etap can send the complete NDJSON body with accurate `Content-Length`, then cleanly close the stream without `GOAWAY`
- **Multiplexing check**: Phase 1 shows 24 concurrent fetch/xhr requests, confirming H2 multiplexing is active → Strategy D (END_STREAM only, no GOAWAY) would be safer, but Strategy C is acceptable because the response is fully self-contained and terminal

---

## Response Specification

### HTTP Headers
```
HTTP/1.1 200 OK
Content-Type: application/x-ndjson
Cache-Control: no-cache
access-control-allow-credentials: true
access-control-allow-origin: https://www.notion.so
Content-Length: {calculated_size}
```

**Rationale for each:**
- `200 OK`: Frontend expects success response; error codes (403, 500) would trigger error UI, not custom rendering
- `application/x-ndjson`: Matches HAR observation of API response type; required for frontend parser
- `Cache-Control: no-cache`: Notion API standard; prevents browser cache interference
- `access-control-allow-*`: Notion's CORS headers; necessary for frontend JS to accept the response
- `Content-Length`: Exact byte count of NDJSON body; **critical** for clean termination without `GOAWAY`

### NDJSON Body Format

The response is a sequence of JSON Patch operations building a minimal AI response state:

```
{type: "patch-start", data: {s: [STATE_OBJECT]}}
{type: "patch", v: [{o: "a", p: "/s/-", v: RECORD_MAP_OBJECT}]}
{type: "patch", v: [{o: "a", p: "/s/-", v: INFERENCE_OBJECT}]}
{type: "patch", v: [{o: "a", p: "/s/2/finishedAt", v: 1}]}
{type: "patch", v: [{o: "a", p: "/s/1/recordVersions", v: []}]}
{type: "record-map", recordMap: {__version__: 3}}
```

**Structure explanation:**

| Line | Type | Purpose | Content |
|------|------|---------|---------|
| 1 | patch-start | Initialize state root | `agent-instruction-state` with empty sources and instruction pages |
| 2 | patch | Add record map (turn container) | `agent-turn-full-record-map` object; **MUST be present** for frontend to recognize turn |
| 3 | patch | Add inference (AI response) | `agent-inference` object with `value` array containing text content |
| 4 | patch | Mark inference complete | Set `finishedAt: 1` on the inference object at `/s/2` |
| 5 | patch | Initialize record versions | Add empty `recordVersions` array to record map |
| 6 | record-map | Stream termination | End of NDJSON; type = "record-map" signals frontend that response is complete |

**Key fields in INFERENCE_OBJECT:**
```json
{
  "id": "00000000-0000-0000-0000-000000000002",
  "type": "agent-inference",
  "value": [
    {
      "type": "text",
      "id": "apf-warning-text-001",
      "content": "{warning_message}"
    }
  ],
  "traceId": "00000000-0000-0000-0000-000000000003",
  "startedAt": 0,
  "previousAttemptValues": [],
  "finishedAt": 1
}
```

**JSON Patch path semantics:**
- `/s/-`: Append to state array
- `/s/0`, `/s/1`, `/s/2`: Index into state array (0=state, 1=record-map, 2=inference after appends)
- `/s/2/finishedAt`: Set completion flag on inference object

---

## Frontend Rendering Prediction

### Expected Behavior
1. **Parse NDJSON**: Frontend's `getInferenceTranscrip` endpoint handler parses each line as JSON
2. **Apply patches**: JSON Patch engine applies each patch object to internal state tree
3. **Recognize turn**: `agent-turn-full-record-map` object signals frontend that a user-AI turn is starting
4. **Render text**: When `type: "agent-inference"` is processed, frontend extracts `value[0].content` (the warning text)
5. **Display bubble**: Text is rendered in chat bubble UI (left-aligned, with copy/add/like/dislike buttons)
6. **Mark complete**: `finishedAt: 1` triggers final rendering pass; `record-map` signals end of response

### Visual Result
The warning message appears as a normal AI response in the chat thread, indistinguishable from a legitimate AI reply.

### Potential Breakpoints (Phase 3 test points)
- **Missing record-map line**: Frontend may treat stream as incomplete, hang waiting for more data
- **Wrong path indices**: Patches applied to `/s/0/...` or `/s/3/...` may fail silently or corrupt state
- **Missing finishedAt**: Inference may remain in "streaming" state; button UI not rendered
- **Missing agent-turn-full-record-map**: Frontend may not recognize the inference as a distinct turn, causing state corruption

---

## Test Criteria

### Phase 3 Validation (Manual Testing)

**Test Environment**: Notion AI (https://www.notion.so/ai) in logged-in state, with Etap MITM active

**Test Steps**:
1. **Baseline**: Send a normal prompt ("Hello, how are you today?"), capture network response (HAR)
2. **APF trigger**: Send a blocked prompt (e.g., policy-violating content), confirm Etap APF intercepts
3. **Response inspection**:
   - Verify response headers match spec (Content-Type, Content-Length)
   - Verify NDJSON body is valid (6 lines, each a complete JSON object)
   - Verify no stray bytes or truncation
4. **Frontend rendering**:
   - Check chat UI: warning text appears in left-aligned bubble
   - Check thread state: no error message, no "Something went wrong"
   - Check UI responsiveness: buttons (copy, like, dislike) functional
5. **State validation**:
   - Open DevTools → Application → Storage → IndexedDB
   - Inspect Notion internal state tree (if accessible)
   - Verify no corruption of subsequent prompts in same thread

**Success Criteria**:
- Warning renders correctly as chat bubble
- No console errors (check DevTools → Console)
- Subsequent prompts in thread work normally (no state corruption)
- User can copy/interact with warning text

**Failure Modes & Recovery**:
| Failure Mode | Indicator | Recovery |
|--------------|-----------|----------|
| Stream incomplete | Frontend hangs or shows loading spinner for >10s | Check NDJSON line count and Content-Length accuracy |
| State corruption | Error UI appears ("Something went wrong") | Verify JSON Patch paths match state array indices |
| Text not visible | Chat bubble empty or missing | Verify `value[0].content` field contains text (not escaped twice) |
| Thread broken | Subsequent prompts fail in same thread | Verify `recordVersions` array is populated (may need non-empty array) |

---

## Test Log Points

**APF C++ code** (`generate_notion_block_response`):
- Line 1976: `bo_mlog_info("[APF_WARNING_TEST:notion] body_size=%zu hdr_size=%zu", ...)`
  - **Inspect**: Verify `body_size` ≈ 800–900 bytes (message-dependent)
  - **Inspect**: Verify `hdr_size` ≈ 250–280 bytes

**Etap response interception**:
- When APF block is triggered, logging should show:
  - Service ID: "notion"
  - Generator function: `generate_notion_block_response`
  - Response body logged above

**Frontend DevTools (Chrome Network tab)**:
- Endpoint: `getInferenceTranscrip...` (or similar)
- Status: `200`
- Protocol: `h2`
- Size: Should match calculated body_size + hdr_size
- Preview: Should show NDJSON preview (6 JSON objects)

**Frontend Console (Chrome DevTools → Console)**:
- No errors like "Failed to parse JSON" or "Unexpected patch path"
- Look for Notion internal logs (if enabled) showing state tree updates

---

## Relationship to Existing Code

### Current Implementation (`ai_prompt_filter.cpp` lines 1898–1979)

The C++ generator is already implemented with the following details:

**Structure**:
- Constructs 6 NDJSON lines, each with specific type and payload
- Escapes warning message for JSON embedding (quotes, backslashes, newlines, carriage returns, tabs)
- Calculates exact `Content-Length` via `body.size()`
- Adds standard Notion API response headers

**Key design decisions**:
- **Path indices**: `/s/0` (state), `/s/1` (record-map), `/s/2` (inference) — determined by JSON Patch append sequence
  - Each `"o": "a", "p": "/s/-"` appends a new element, incrementing the index
- **finishedAt marker**: Placed on `/s/2` after inference object is added
- **recordVersions**: Set to empty array `[]` (Notion may use this for concurrency; empty is safe default)
- **trace IDs**: All UUIDs set to fixed values (not randomized); Notion does not validate these for warnings
- **previousAttemptValues**: Empty array; not required for single-turn warnings

**Deviation from baseline**:
- Not Strategy A (END_STREAM + GOAWAY) nor B (keep-alive)
- Uses Strategy C: `Content-Length` header + normal 200 response
- This avoids H2 frame-level termination complexity and works with Etap's H1→H2 translation layer

### Integration Points

1. **Service registration** (line 122):
   ```cpp
   _response_generators["notion"]          = generate_notion_block_response;
   ```
   - Notion service ID: `"notion"`
   - Generator function registered; APF will call this when blocking a Notion request

2. **Logging** (line 1976):
   - Test assertion point for Phase 3; confirms generator was invoked

3. **DB logging** (lines 2024–2047 and beyond):
   - Existing `log_writer_thread_func()` will record the block event (if logging enabled)
   - No changes needed; generator is independent of logging

---

## Notes

### Design Decisions

**1. Why NDJSON_WARNING instead of JSON_SINGLE_WARNING?**
- Notion's API is built on JSON Patch streaming, not single-response API
- Returning `{error: "..."}` would be parsed as a patch failure, not a response
- NDJSON matches the actual protocol contract; frontend parser is already deployed

**2. Why not use SSE_STREAM_WARNING?**
- Notion does not use `text/event-stream`; it uses `application/x-ndjson`
- SSE parser would fail on JSON Patch format
- Although both are "streaming," the framing is incompatible

**3. Why Strategy C (Content-Length) instead of Strategy A (END_STREAM)?**
- Response is fully deterministic: 6 fixed lines + escaped message = fixed structure
- No chunking or uncertainty; body size can be calculated exactly
- H2 multiplexing is active (24 concurrent requests), so Strategy D (END_STREAM only, no GOAWAY) would be safer
- However, **Strategy C is acceptable** because:
  - Response is terminal (no client follow-up expected on same stream)
  - Content-Length prevents client from waiting indefinitely
  - Cleaner exit: close stream after Content-Length bytes, no frame protocol flags needed
  - Matches existing Etap architecture (H1→H2 translation handles cleanup)

**4. Multiplexing protection:**
- Phase 1 shows 24 fetch/xhr requests in parallel → H2 multiplexing confirmed
- If GOAWAY is sent, other streams may be reset (cascade failure)
- Current design avoids this by:
  - Using Content-Length (no ambiguity about response size)
  - Not sending GOAWAY (clean per-stream termination only)
  - Allowing other streams to continue unaffected

**5. Fixed UUIDs in response:**
- Notion does not validate turn IDs or trace IDs for security
- Fixed values simplify implementation; randomization adds no security benefit
- If Notion later adds validation, this can be randomized in Phase 3

**6. Empty recordVersions array:**
- Notion may use this for conflict resolution / concurrency control
- Empty array is safe default (no prior versions exist for a synthetic warning)
- If rendering breaks, this is the first field to populate with generated version numbers

### Known Limitations

- **No markdown rendering**: Warning text is plain text only. Notion's response value type is "text", not "markdown".
- **No threading info**: Warning appears as a single inference turn; no context about what prompt was blocked.
- **State isolation**: If user reopens the same thread later, warning turn is preserved as part of thread history (like any normal turn).

### Phase 3 Risks

1. **Index misalignment**: If `/s/` indices don't match actual array state, patches fail silently and nothing renders
   - **Mitigation**: Log actual state tree after each patch (inspect DevTools IndexedDB)

2. **recordVersions requirement**: If Notion requires non-empty recordVersions, rendering may fail
   - **Mitigation**: Pre-populate with `[{id: "...", version: 1}]`

3. **Frontend caching**: Service worker (sw.js) may cache unexpected responses
   - **Mitigation**: Verify `Cache-Control: no-cache` header; if needed, add `Pragma: no-cache`

4. **CORS preflight**: If frontend sends OPTIONS preflight, Etap must respond with matching access-control headers
   - **Mitigation**: Existing headers should cover this; test with DevTools Network tab

---

## Checklist Results

| Item | Value | Notes |
|------|-------|-------|
| **1-1: Communication type** | NDJSON | REST API, not SSE/WS |
| **1-2: HTTP protocol** | h2 | Phase 1 confirms; H1→H2 translation by Etap is transparent |
| **1-3: H2 multiplexing** | YES | 24 concurrent fetch/xhr; cascade failure risk exists → Strategy D safer, but C acceptable |
| **1-4: SSE delimiter** | N/A | Not SSE |
| **1-5: WebSocket** | NO | REST only; HTTP response injection feasible |
| **2-1: Content-Type** | application/x-ndjson | Must match; frontend parser expects NDJSON |
| **2-2: JSON keys** | Patch operations with `/s/` paths | Required keys: `type`, `v`, `p`, `o`; `value` in inference object |
| **2-3: SSE init** | N/A | Not SSE |
| **2-4: Markdown support** | NO | Value type is "text", not "markdown" |
| **2-5: Chat bubble rendering** | YES | Full-page chat interface; warning renders as AI response bubble |
| **2-6: Minimal message condition** | All 6 NDJSON lines required | Missing any line → state corruption or incomplete render |
| **3-1: Error handler scope** | React error boundary (global) | Does not prevent custom response rendering; warning can be injected as valid response |
| **3-2: Error UI type** | Generic error ("Something went wrong") | Not expected to trigger for 200 OK responses |
| **3-3: Error UI accepts server message** | NO | Error UI is generic; but not relevant (we return 200, not error) |
| **3-4: Silent status codes** | NO | 200 is respected |
| **4-1: Payload validation** | NO | No checksum/signature on NDJSON in HAR analysis |
| **4-2: H2 stream termination** | Content-Length based (Strategy C) | Not immediate frame closure; Etap handles translation |
| **4-3: Modifiable rendered field** | YES | `value[0].content` is rendered directly; under our control |
| **4-4: Non-standard protocol** | NDJSON is REST-based standard | Not exotic; widely supported |
| **4-5: Field modification side effects** | NONE | Modifying content field does not affect other turns or state |
| **4-6: Alternative delivery paths** | NDJSON only viable | Error responses would fail; no fallback mechanism |

### Early Termination Checks (Section 3.3)
- **3-1 = global scope, 3-2 = generic, 3-3 = NO**: Not applicable (we return 200 OK, not error)
- **1-5 = WS + no architecture**: Not applicable (REST only)
- **4-1 = validation + no alternative**: Not applicable (no validation detected)
- **4-5 = field modification + only path**: Not applicable (multiple fields modifiable, no side effects)
- **2-5 = non-chat consumption**: Not applicable (chat bubble format, standard rendering)

**Conclusion**: No early termination conditions met; proceed to Phase 3 testing.

---

## Implementation Status

**Code**: Complete
- File: `/sessions/ecstatic-loving-davinci/mnt/Officeguard/EtapV3/functions/ai_prompt_filter/ai_prompt_filter.cpp`
- Function: `generate_notion_block_response` (lines 1898–1979)
- Status: Ready for testing

**Next Phase**: Phase 3 (Testing & Validation)
- Deploy APF to test environment
- Trigger blocks with Notion AI prompts
- Verify NDJSON rendering in chat UI
- Confirm no state corruption
- Document lessons learned
