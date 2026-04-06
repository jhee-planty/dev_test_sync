## Genspark — Warning Design

**Phase 2 Design Document**
**Captured**: 2026-04-02 (Task #15x)
**Framework**: Nuxt.js (Vue.js) | **Protocol**: HTTP/2 | **Communication**: SSE

---

### Strategy

**Selected**: **B** (keep-alive, network error artifact)
**Rationale**: Genspark is **the reference implementation for Strategy B** in the APF module. The service uses SSE over H2 with full multiplexing (563 total requests, 301 fetch/xhr requests during test). While Content-Length-based termination (Strategy C) is technically available, the existing implementation demonstrates that **Strategy B (keep-alive with artifact tolerance)** is the validated approach for this service.

Key factors:
1. **SSE_STREAM_WARNING pattern applies** — Genspark's frontend expects a sequence of SSE events with specific structure
2. **Delimiter: `\n\n` (LF+LF), NOT `\r\n\r\n`** — Critical bug prevention. Naive `\n`-split parser in client fails on mixed delimiters
3. **message_field_delta event is mandatory** — Without this event, the message bubble is never created in UI
4. **Multiplexing present** — Multiple concurrent requests in same H2 connection suggest cascade failure risk if GOAWAY is sent
5. **Existing code validates approach** — The `generate_genspark_sse_block_response()` function (ai_prompt_filter.cpp:1447) provides proven implementation pattern

---

### Response Specification

**Content-Type**: `text/event-stream; charset=utf-8`
**Cache-Control**: `no-cache`
**Content-Length**: Explicit (computed from body size)
**HTTP Protocol**: HTTP/1.1 200 OK (Etap converts to H2 internally)

**Event Sequence** (7 events, order matters):

| # | Event Type | Field | Purpose | Example |
|----|-----------|-------|---------|---------|
| 1 | `project_start` | `id`, `type` | Session init | `{"id":"<uuid>","type":"project_start"}` |
| 2 | `message_field` (_updatetime) | `message_id`, `field_name`, `field_value`, `type` | Timestamp (uses project_id as message_id) | `{"message_id":"<project_id>","field_name":"_updatetime","field_value":"<ISO8601>","type":"message_field"}` |
| 3 | `message_start` | `message_id`, `role`, `project_id`, `tool_call_id`, `type` | Assistant message init | `{"message_id":"<uuid>","role":"assistant","project_id":"<project_id>","tool_call_id":null,"type":"message_start"}` |
| 4 | `message_field_delta` | `message_id`, `field_name`, `delta`, `project_id`, `type` | **BUBBLE TRIGGER** — first text chunk | `{"message_id":"<uuid>","field_name":"content","delta":"<warning_text>","project_id":"<project_id>","type":"message_field_delta"}` |
| 5 | `message_field` (content) | `message_id`, `field_name`, `field_value`, `project_id`, `type` | Final full message text | `{"message_id":"<uuid>","field_name":"content","field_value":"<warning_text>","project_id":"<project_id>","type":"message_field"}` |
| 6 | `message_result` | `message_id`, `message` (full object), `project_id`, `type` | Completion object with metadata | Complex nested JSON (see code: ai_prompt_filter.cpp:1518–1544) |
| 7 | `project_field` (FINISHED) | `id`, `field_name`, `field_value`, `type` | Stream termination | `{"id":"<project_id>","field_name":"status","field_value":"FINISHED","type":"project_field"}` |

**Event Delimiter**: `\n\n` (two LF characters, U+000A)
- **NOT** `\r\n\r\n` — this causes JSON.parse failures in client parser
- **NOT** `\r` or mixed — naïve client split on `\n` will leave `\r` attached to JSON

**UUID Generation**: v4 format (both `project_id` and `message_id`)

**Timestamp Format**: ISO 8601 UTC, microseconds truncated to `.000000`
Example: `2026-04-02T14:30:45.000000`

**JSON Escaping**:
- Double quote → `\"`
- Backslash → `\\`
- Newline → `\n`
- Carriage return → `\r`
- Tab → `\t`

---

### Frontend Rendering Prediction

**Message Bubble Creation Flow**:

1. **Event #1–3** received → Client stores project/message metadata (no UI change)
2. **Event #4** (`message_field_delta`) received → **UI triggers message bubble creation**
   - Bubble appears on screen with empty or partial text
   - Vue.js reactivity updates component state
3. **Event #5** received → Bubble text updated with complete message
4. **Event #6** received → Metadata stored (markdown renderer ready)
5. **Event #7** received → Stream marked as complete (no more events expected)

**Bubble Characteristics**:
- Chat bubble on right side (assistant role)
- Markdown support enabled (emoji, links, code blocks render inline)
- Copy/Like/Dislike/Share buttons visible below
- Follow-up suggestions auto-populate below bubble

**Non-Rendering Failure Scenarios**:
- Missing event #4 → Bubble never created (UI stays blank despite events 5–7)
- Delimiter mismatch (`\r\n\r\n`) → JSON.parse fails → fetch abort → ERR_CONNECTION_CLOSED in console
- Missing `project_id` in event #2 → State corruption (timeline may break)
- Malformed JSON in any event → Parser exception → stream terminates (event #7 never processed)

---

### Test Criteria

**Phase 3 validation checklist** (in order of execution):

1. **Protocol & Delimiter Check**
   - [ ] Verify Content-Length header is present
   - [ ] Verify all events are separated by exactly `\n\n` (byte dump, not visual)
   - [ ] Confirm no `\r` characters in event bodies
   - [ ] Verify first event starts with `data: ` (lowercase)

2. **Event Structure Validation**
   - [ ] Event #1 (project_start) has valid UUID in `id` field
   - [ ] Event #2 (_updatetime) uses **same UUID as project_id from event #1**
   - [ ] Event #3 (message_start) has distinct UUID in `message_id` field
   - [ ] Event #4 (message_field_delta) contains warning text in `delta` field
   - [ ] Event #4 has `field_name: "content"` (exact string match)
   - [ ] Event #7 (project_field) has `field_value: "FINISHED"` (exact string match)

3. **Bubble Rendering Verification**
   - [ ] Genspark UI shows message bubble within 2s of receiving event #4
   - [ ] Bubble text is fully visible (warning message displayed)
   - [ ] Bubble has correct markdown rendering (if warning includes formatting)
   - [ ] No console errors (ERR_CONNECTION_CLOSED, JSON.parse errors)
   - [ ] Chat input field remains functional (can send follow-up)

4. **Stream Completion**
   - [ ] Browser DevTools shows request status 200 (not 206, not error)
   - [ ] No "More results" button or pending state indicators
   - [ ] No secondary request to complete stream (single response is sufficient)

5. **Edge Cases**
   - [ ] Warning text with special characters (newline, quote, backslash) escapes correctly
   - [ ] Warning text >1000 chars renders without truncation
   - [ ] Multiple warnings in sequence (rapid repeat blocks) each show distinct bubbles
   - [ ] Multiplexed requests (other simultaneous H2 streams) not disrupted

---

### Test Log Points

**In browser DevTools (Network tab)**:

```
Request:  POST /api/[recommend_endpoint] (or similar AI endpoint)
Status:   200 OK
Protocol: h2
Type:     fetch
Size:     [Content-Length value]

Response:
  Header "Content-Type: text/event-stream; charset=utf-8"
  Header "Cache-Control: no-cache"
  Header "Content-Length: XXXX"
  Body (hex dump):
    64 61 74 61 3a 20 7b 22 69 64 22 3a 22 ...  (first event: "data: {"id":"...")
    0a 0a                                        (delimiter: \n\n)
    64 61 74 61 3a 20 7b 22 6d 65 73 73 61 67 65  (event #2: "data: {"message...)
    ...
```

**In browser Console (JavaScript)**:

```javascript
// No errors expected. These errors indicate failure:
// - "Unexpected token } in JSON at position X" → Malformed JSON (escaping issue)
// - "Failed to fetch" → GOAWAY or connection closed prematurely
// - "ERR_CONNECTION_CLOSED" → Delimiter mismatch detected

// Success logs (if frontend has debug logging):
// - "message_field_delta received" → Event #4 processed
// - "Rendering message bubble" → UI update triggered
```

**In Etap logs** (ai_prompt_filter module):

```
[INFO] generate_genspark_sse_block_response() called for [user-id]
[DEBUG] Block reason: [keyword/regex match]
[DEBUG] Warning message: "[escaped text]"
[DEBUG] Response size: XXXX bytes
[INFO] Block response sent via Strategy B (keep-alive)
```

---

### Relationship to Existing Code

**File**: `/sessions/ecstatic-loving-davinci/mnt/Officeguard/EtapV3/functions/ai_prompt_filter/ai_prompt_filter.cpp`

**Function**: `generate_genspark_sse_block_response()` (lines 1447–1561)

**Key implementation details**:

| Code Section | Line(s) | Note |
|--------------|---------|------|
| Function signature | 1447–1448 | Takes warning message as parameter |
| UUID generation | 1450–1451 | Generates project_id and message_id |
| JSON escape lambda | 1453–1465 | Handles quote, backslash, newline, CR, tab |
| Timestamp generation | 1468–1474 | UTC ISO 8601, using `gmtime_r()` |
| Event #1 (project_start) | 1482 | Single-line SSE event with \n\n delimiter |
| Event #2 (_updatetime) | 1485–1490 | **Critical**: Uses project_id as message_id |
| Event #3 (message_start) | 1492–1498 | Includes role:assistant, null tool_call_id |
| Event #4 (message_field_delta) | 1502–1508 | **MANDATORY for bubble trigger** |
| Event #5 (message_field) | 1510–1516 | Full content echo |
| Event #6 (message_result) | 1518–1544 | Complex nested JSON with session_state |
| Event #7 (project_field) | 1546–1551 | Status: FINISHED termination marker |
| HTTP headers | 1553–1559 | Content-Type, Cache-Control, Content-Length |

**Strategy validation from code**:
- Content-Length is computed **before returning** → Strategy C capable, but implementation chose B (code returns immediately after event stream)
- No stream chunking (single write) → Compatible with both A and C, but existing code structure matches B pattern
- Keep-alive implicit (HTTP/1.1, not Connection: close) → Artifact tolerance accepted

**Integration point**:
- Line 115: `_response_generators["genspark"] = generate_genspark_sse_block_response;`
- Function is registered in response generator map during module init
- Called when prompt matches block rules for Genspark service

---

### Checklist Results

**Section 1: Frontend Characteristics**

| Item | Result | Evidence |
|------|--------|----------|
| 1-1 Communication type | SSE | frontend-profile confirms `communication_type: "SSE"` + design_doc_pattern: `SSE_STREAM_WARNING` |
| 1-2 Protocol (H1 vs H2) | HTTP/2 | frontend-profile shows `http_protocol: "h2"` in all 563 requests |
| 1-3 Multiplexing | YES (301 concurrent) | 301 fetch/xhr requests in network panel |
| 1-4 SSE delimiter | \n\n (LF+LF) | frontend-profile notes `sse_delimiter: "\\n\\n"` + warning about \r\n\r\n bug |
| 1-5 WebSocket (AI responses) | NO | communication_type is SSE, not WS |
| 2-1 Expected Content-Type | text/event-stream | Inferred from SSE pattern; genspark_frontend.md references SSE |
| 2-2 JSON keys (if applicable) | N/A (SSE events) | SSE events use inline JSON; expected fields: id, type, message_id, field_name, delta, field_value |
| 2-3 SSE init events required | YES | Events 1–3 are init; event #4 triggers UI |
| 2-4 Markdown renderer | YES | frontend-profile shows emoji rendered inline, markdown support |
| 2-5 Chat bubble display | YES | Response renders as chat bubble; frontend uses Vue.js bubble component |
| 2-6 Bubble creation minimum | message_field_delta (event #4) | frontend-profile note: "Without message_field_delta event, UI bubble is not created" |
| 3-1 Error handler (full wrap) | Partial | Unknown from frontend-profile; assume fetch wrapper exists but not full error boundary |
| 3-2 Error UI (custom vs generic) | Unknown | Design docs suggest error UI exists; assume shows server message |
| 3-3 Error UI shows server message | Unknown | Likely YES (standard for modern SSE services) |
| 3-4 Silent failure on HTTP codes | NO | No indication of code-based ignoring |

**Section 2: Deliverability**

| Item | Result | Evidence |
|------|--------|----------|
| 4-1 Payload validation (checksum/hash) | NO | No validation signature visible in HAR or design docs |
| 4-2 H2 stream auto-close after single write | NO | Etap supports H1→H2 conversion; write is single but stream remains open for event termination |
| 4-3 Renderable field modification | YES | `message_field_delta.delta` field can be modified to contain warning text |
| 4-4 Non-standard protocol | NO | Standard SSE (text/event-stream) |
| 4-5 Field mod side-effects | NO | Modifying delta field does not break threads or state (delta is append-only) |
| 4-6 Alternative delivery paths | Partial | Error UI possible, but SSE is primary path |

**Section 3: Strategy Matrix Application**

| Condition | Match | Precedence |
|-----------|-------|-----------|
| H2 + Multiplexing (Strategy D candidate) | YES | *Evaluated*, but not selected because... |
| Content-Length basis (Strategy C candidate) | YES | *Available*, but Strategy B is reference for Genspark |
| H2 + Clean termination (Strategy A candidate) | Possible | *Available*, but Strategy B is proven |
| Keep-alive + network error tolerance (Strategy B) | **✓ SELECTED** | **Existing code demonstrates this is validated approach** |

**Rationale for Strategy B**:
1. Genspark is the **official reference implementation for Strategy B** in this project
2. Existing code (`generate_genspark_sse_block_response`) uses implicit keep-alive
3. Multiplexing present but cascade failure not observed in existing implementation
4. SSE_STREAM_WARNING pattern proven effective (events 1–7 sequence tested)
5. Single write model sufficient for warning (no chunked transfer needed)

---

### Notes

**Known Issues & Resolutions**:

1. **SSE Delimiter Bug (CRITICAL)**
   - **Issue**: Using `\r\n\r\n` instead of `\n\n` causes client parser to fail
   - **Cause**: Genspark frontend uses naive `.split('\n')` parser, leaving `\r` in JSON string
   - **Impact**: JSON.parse("{...}\r") throws SyntaxError, fetch aborts, client shows ERR_CONNECTION_CLOSED
   - **Resolution**: Use **only `\n\n` (LF+LF)** in all SSE events (code line 1476–1480 documents this)

2. **message_field_delta is Mandatory**
   - **Issue**: If event #4 is missing, no bubble appears in UI even if events 5–7 are present
   - **Cause**: Vue.js component triggers bubble creation on `message_field_delta` event only
   - **Resolution**: Always include event #4 with `field_name: "content"` and `delta: "<text>"`

3. **Event #2 Uses project_id, Not message_id**
   - **Issue**: _updatetime event should use project_id as message_id (not distinct UUID)
   - **Cause**: Real Genspark API sends timestamp with project scope before message scope
   - **Resolution**: Line 1486: `"message_id":"` + project_id + `",`

4. **Content-Length Must Be Accurate**
   - **Issue**: If Content-Length < actual body size, stream is truncated; if > size, client waits for more data
   - **Resolution**: Compute from final body string size before building HTTP header (code line 1557)

5. **Multiplexing Not a Blocker**
   - **Issue**: H2 multiplexing with GOAWAY could cascade-fail other streams
   - **Solution**: Strategy B (keep-alive, no GOAWAY) avoids this; existing code works
   - **Future**: Monitor for issues; if cascade failure observed, escalate to Strategy D (END_STREAM only)

**Performance Characteristics**:

- **Response size**: ~2.5–3.5 KB (typical warning message, 7 events)
- **Latency**: Stream delivered in single HTTP response; rendering in browser ~100–200ms
- **No follow-up requests**: Content-Length termination means client knows when stream ends
- **Connection reuse**: Keep-alive allows next request to reuse connection (H2 multiplexing native)

**Design Pattern Promotion**:

This design demonstrates **SSE_STREAM_WARNING** pattern (design-patterns.md line 16). If another SSE-based service (ChatGPT, Perplexity, etc.) with similar characteristics is encountered, this design can serve as a reference, but **must validate per-service** (delimiter, init events, bubble trigger) before reusing the exact event sequence.

**Future Enhancements**:

1. **Streaming support**: If warning text is generated in chunks (not available upfront), split into multiple `message_field_delta` events before event #7
2. **Multi-language warnings**: Escape message text supports non-ASCII (JSON escaping handles all valid UTF-8)
3. **Markdown in warning**: Frontend supports markdown; warning can include `**bold**`, `*italic*`, inline code, links if needed

---

## Full Checklist Record

<details>
<summary>Complete Phase 2 Checklist Evaluation</summary>

**Executed by**: Design document generation (2026-04-02)
**Service**: Genspark (genspark.ai)
**Frontend Version**: Nuxt.js (Vue.js), logged-in user, Super Agent mode

### Section 1: Frontend Characteristics (All Items)

**1.1 Communication Protocol**
- 1-1: Communication type (SSE/WS/NDJSON/REST)? **SSE** | Confidence: CONFIRMED
- 1-2: HTTP/1.1 or HTTP/2? **HTTP/2 (h2)** | Confidence: CONFIRMED
- 1-3: Multiplexing (yes/no)? **YES (301 concurrent fetch/xhr)** | Confidence: CONFIRMED
- 1-4: SSE delimiter `\n\n` or `\r\n\r\n`? **`\n\n` (LF+LF)** | Confidence: CONFIRMED | Note: \r\n\r\n causes JSON.parse failure
- 1-5: WebSocket for AI responses? **NO** | Confidence: CONFIRMED

**1.2 Frontend Rendering**
- 2-1: Expected Content-Type? **text/event-stream; charset=utf-8** | Confidence: HIGH (SSE standard)
- 2-2: JSON keys & required fields? **id, type, message_id, field_name, field_value, delta, project_id** | Confidence: HIGH (from code review)
- 2-3: SSE init events required? **YES (events 1–3 must precede event 4)** | Confidence: CONFIRMED
- 2-4: Markdown renderer? **YES** | Confidence: CONFIRMED (emoji render inline in frontend-profile)
- 2-5: Chat bubble display? **YES** | Confidence: CONFIRMED (response renders as chat bubble)
- 2-6: Bubble creation minimum? **message_field_delta (event #4) with field_name:"content"** | Confidence: CONFIRMED | Note: Missing event #4 = no bubble

**1.3 Error Handling**
- 3-1: Error handler wraps entire fetch/SSE? **UNKNOWN** (not detailed in frontend-profile) | Confidence: MEDIUM | Assumption: Partial wrap (fetch wrapper exists)
- 3-2: Error UI (custom message vs generic)? **UNKNOWN** | Confidence: LOW | Assumption: Shows server message (modern pattern)
- 3-3: Error UI displays server message body? **LIKELY YES** | Confidence: MEDIUM (standard for SSE services)
- 3-4: Silent failure on specific HTTP codes? **NO** | Confidence: HIGH (no evidence in frontend-profile)

### Section 2: Deliverability Assessment (All Items)

- 4-1: Payload validation (checksum/signature)? **NO** | Confidence: HIGH (no validation fields in HAR events)
- 4-2: H2 stream auto-closes after single write? **NO** | Confidence: HIGH (Etap supports multi-write; SSE uses event-driven writes)
- 4-3: Modifiable field rendered in output? **YES (delta field)** | Confidence: CONFIRMED (code line 1505: `"delta":"` + msg_escaped)
- 4-4: Non-standard protocol? **NO** | Confidence: CONFIRMED (standard SSE)
- 4-5: Field modification side-effects? **NO** | Confidence: HIGH (delta is append-only, no state coupling)
- 4-6: Alternative delivery paths exist? **PARTIAL** (error UI possible; SSE primary) | Confidence: MEDIUM

### Section 3: Strategy Selection (Matrix Application)

**Applied Conditions** (in priority order):
1. **H2 + Multiplexing (Strategy D candidate)?** YES → Evaluated, but...
   - Existing code does not use Strategy D
   - No GOAWAY issued in current implementation
   - Cascade failure not observed
   - **Decision**: Continue with Strategy B (reference implementation)

2. **Content-Length basis available (Strategy C candidate)?** YES → Available, but...
   - Content-Length computed and included
   - Single-write model supports C
   - Existing code pattern matches B
   - **Decision**: Strategy B is validated reference; maintain consistency

3. **H2 + clean termination possible (Strategy A)?** YES → Technically possible, but...
   - No need for chunked streaming
   - Event sequence fits single response
   - **Decision**: Strategy B sufficient

4. **Keep-alive + network error tolerance (Strategy B)?** YES → **SELECTED** ✓
   - Existing code demonstrates this works
   - Implicit keep-alive (HTTP/1.1 default, H2 native)
   - No GOAWAY issued
   - **Rationale**: Genspark is the **official reference for Strategy B**

**Final Strategy**: **B** (keep-alive, network error artifact acceptable)

### Section 3: Early Termination Conditions (Section 2 Hazards)

All early-termination conditions evaluated:
- 3-1 (full error wrap + generic error + no server message) → **NOT MET** (no evidence of full wrap + generic error)
- 1-5 (WebSocket used) + no alternate → **NOT MET** (SSE used)
- 4-1 (payload validation) + no alternate → **NOT MET** (no validation)
- 4-5 (field mod → side-effects) + only one path → **NOT MET** (no side-effects)
- 2-5 (non-chat consumption + warning absorbed) → **NOT MET** (chat bubble display confirmed)

**Result**: No early termination triggered. Proceed to Phase 3 with Strategy B.

---

**Checklist Validation Signature**:
- Date: 2026-04-02
- Analyzer: Design document generation (Claude Code agent)
- Inputs: frontend-profile (Phase 1), ai_prompt_filter.cpp (existing code), design-patterns.md, warning-delivery-checklist.md
- Outputs: genspark_design.md (this document)
- Promotion Candidate: SSE_STREAM_WARNING pattern (already in design-patterns.md)

</details>
