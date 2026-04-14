## Perplexity — Warning Design

### Strategy

**Selected: D (END_STREAM=true + GOAWAY=false)**

**Classification rationale:**
- Perplexity uses HTTP/2 with multiplexed streams (244 concurrent requests observed in Phase 1)
- SSE payload validation defeats SSE_STREAM_WARNING pattern (confirmed in C++ implementation v5-v11 iterations)
- Multiple cursor-based events in SSE stream require multiplexing protection
- GOAWAY frame would cascade-fail other active streams on same H2 connection
- Strategy D prioritizes stream isolation over clean termination

### Response Specification

**HTTP/2 Block Response Structure:**

```
:status: 200
content-type: text/event-stream; charset=utf-8
cache-control: no-cache
end_stream: true
goaway: false

[SSE event body — see Warning Pattern section]
```

**Key constraints:**
- Set END_STREAM flag on DATA frame containing final event
- Do NOT send GOAWAY frame (would cascade-fail concurrent streams)
- No Content-Length header (streaming required; size indeterminate until final event)
- Stream terminates cleanly at H2 layer when END_STREAM received

**HTTP/1.1 Fallback (if applicable):**
```
HTTP/1.1 200 OK
Content-Type: text/event-stream; charset=utf-8
Cache-Control: no-cache
Content-Length: {body_size}

[SSE event body]
```

### Frontend Rendering Prediction

**Expected user-facing behavior (if warning deliverable):**

1. **Message bubble appearance:** Flat left-aligned response bubble with warning text content
2. **Tabs visible:** "답변 | 링크 | 이미지" tabs rendered (from answer_tabs_block event)
3. **Action buttons:** share, download, copy, retry, thumbs up/down functional
4. **Markdown support:** Warning text processed through markdown renderer
5. **Thread state:** Response marked DONE; no spinner/loading state
6. **No citations:** source_citations field absent (per frontend profile)

**Side effects if answer field modified (v6-v11 failures):**
- Thread URL slug mismatch → [STREAM_FAILED_FIRST_CHUNK_ERROR] in console
- Frontend state machine breaks at first event validation
- User sees "Something went wrong" generic error instead of response

### Test Criteria

**Phase 3 validation checklist:**

1. **Stream closure behavior**
   - [ ] END_STREAM flag set on final DATA frame
   - [ ] GOAWAY NOT sent (verify H2 frame log)
   - [ ] Other multiplexed streams on same connection unaffected
   - [ ] Browser DevTools network tab shows 200 OK, no connection reset

2. **SSE parsing**
   - [ ] All 6 events parse correctly as JSON (no trailing \r in data field)
   - [ ] SSE delimiter is \n\n (verify in HAR raw bytes, not \r\n\r\n)
   - [ ] No truncated events (event: and data: paired correctly)

3. **Frontend rendering**
   - [ ] Message bubble appears in chat
   - [ ] Warning text visible in chunks field (not null/truncated)
   - [ ] Tabs render (답변 shown)
   - [ ] No console errors: [STREAM_FAILED_FIRST_CHUNK_ERROR], fetch abort, ERR_CONNECTION_CLOSED
   - [ ] No generic "Something went wrong" error

4. **UUID/slug validation**
   - [ ] thread_url_slug present in all events
   - [ ] backend_uuid, uuid fields populated (non-empty)
   - [ ] cursor value unique across events

5. **State flags**
   - [ ] status: PENDING in events 1-4, unchanged in event 5
   - [ ] final_sse_message: false in events 1-4, true in event 5
   - [ ] text_completed: false in events 1-4, true in event 5
   - [ ] answer: null in ALL events (critical)

### Test Log Points

**Etap APF debug logging (boTrace/bo_mlog):**

```cpp
// Line 1426-1427: Block response generation
bo_mlog_info("[APF_WARNING_TEST:perplexity] body_size=%zu events=6(init+tabs+plan+content+final+end) "
             "thread_url_slug=%s msg_len=%zu",
             body.size(), thread_url_slug.c_str(), message.size());

// Expected output example:
// [APF_WARNING_TEST:perplexity] body_size=5847 events=6 thread_url_slug=blocked-a1b2c3d4 msg_len=67
```

**Browser console (Chrome DevTools):**

```javascript
// Success case (v5 format): No errors
// Failure case (v6+ with answer field):
//   [pplx-stream-worker.js] [STREAM_FAILED_FIRST_CHUNK_ERROR]
//   fetch status: 200, but JSON.parse failed in stream handler

// Check for:
// 1. "Blocked response received" in Network tab (custom header injection optional)
// 2. SSE event count = 6
// 3. No ERR_CONNECTION_CLOSED
```

**HAR inspection (Phase 3 capture):**

```json
{
  "request": {
    "method": "POST",
    "url": "https://www.perplexity.ai/rest/sse/perplexity_ask"
  },
  "response": {
    "status": 200,
    "headers": [
      {"name": "content-type", "value": "text/event-stream; charset=utf-8"},
      {"name": "cache-control", "value": "no-cache"},
      {"name": "content-length", "value": "..."}
    ],
    "content": {
      "text": "event: message\ndata: {\"backend_uuid\":\"...\", ... },\n\nevent: message\ndata: {...},\n\n...event: end_of_stream\ndata: {}\n\n"
    }
  }
}
```

### Relationship to Existing Code

**Implementation references:**

1. **Block response generator registration** (ai_prompt_filter.cpp:108-124)
   - Line 113: `_response_generators["perplexity"] = generate_perplexity_sse_block_response;`
   - Line 114: `_response_generators["perfle"] = generate_perplexity_sse_block_response;` (alias)
   - Both "perplexity" and "perfle" service names route to same generator

2. **Generator function** (ai_prompt_filter.cpp:1227-1438)
   - **Function signature:** `std::string generate_perplexity_sse_block_response(const std::string& message)`
   - **Return value:** HTTP response (headers + SSE body) as single string
   - **Message parameter:** User-facing warning text (already JSON-escaped by caller)

3. **JSON escape helper** (lines 1243-1255)
   - Escapes `"`, `\`, `\n`, `\r`, `\t` for safe JSON embedding
   - Applied to message before injection into chunks array

4. **Version history** (lines 1230-1233)
   - v5: Confirmed working (LOCKED format)
   - v6-v11: Various regressions documented
   - Current: v5 is canonical; no future changes planned

5. **HTTP header construction** (lines 1429-1436)
   - Hardcoded 200 OK response
   - Content-Length set to body.size()
   - No Transfer-Encoding header (full body known at generation time)

### Notes

**Critical constraints (do not modify):**

- **answer field MUST be null.** The C++ implementation uses answer:null in ALL events (lines 1367, 1379, 1402, 1407). Non-null values trigger thread state machine corruption confirmed in v6, v8, v9, v10 iterations.

- **Final event is LOCKED.** Lines 1386-1420 comment: "v5와 100% 동일 (LOCKED — 절대 변경 금지). v6/v8/v9: 필드 추가 → 스레드 깨짐. v10: 블록 제거 → 스레드 깨짐."

- **thread_url_slug required from event 0.** JavaScript validation in pplx-stream-*.js checks for this field's presence in the first chunk. Omission triggers [STREAM_FAILED_FIRST_CHUNK_ERROR].

- **Cursor uniqueness.** Each event's cursor value must be distinct (random UUIDs). Repeated cursors may confuse state machine.

- **SSE delimiter.** Use \n\n (LF+LF), not \r\n\r\n. Genspark failure documented (ai_prompt_filter.cpp:1478-1480) shows naive \n-split parser breaks on \r characters.

**Warning delivery status:**

- **Block capability:** CONFIRMED (v5 working, 244 concurrent requests tested)
- **Warning capability:** IMPOSSIBLE via SSE (payload validation defeats injection)
- **Overall classification:** **PARTIAL** (Block=YES, Warning=NO per Phase 1 design doc note)

**Alternative architectures considered:**

1. **Error response injection (JSON):** Perplexity uses SSE/WebSocket, not JSON REST APIs. Not applicable.
2. **WebSocket interception:** Perplexity uses WS for real-time updates (Phase 1: "ws (status 101) detected"). Current Etap architecture does not support WebSocket request/response modification.

**Future reconsideration triggers:**

- If Perplexity frontend relaxes SSE payload validation (requires Phase 1 re-inspection)
- If Etap adds WebSocket transformation support (architecture change)
- If Perplexity introduces error response channel alongside SSE (frontend change)

---

**Checklist Results Summary:**

| Item | Result | Notes |
|------|--------|-------|
| 1-1: Communication type | SSE + WebSocket hybrid | H2 framing |
| 1-2: HTTP version | HTTP/2 | Strategy D enforced (multiplexing) |
| 1-3: Multiplexing | YES (244 requests) | Strategy D mandatory (GOAWAY cascade risk) |
| 1-4: SSE delimiter | \n\n (confirmed) | Not \r\n\r\n |
| 1-5: WebSocket for AI response | YES (status 101) | Streaming only; HTTP injection secondary |
| 2-1: Content-Type | text/event-stream | Must match block response |
| 2-2: JSON keys | per v5 spec | thread_url_slug, backend_uuid, uuid required |
| 2-3: SSE init fields | YES, strict requirement | Missing uuid → [STREAM_FAILED_FIRST_CHUNK_ERROR] |
| 2-4: Markdown renderer | YES | Warning text would be processed as markdown |
| 2-5: Chat bubble consumption | YES | Flat left-aligned response expected |
| 2-6: Bubble creation condition | chunks field non-empty + status=PENDING | Met by v5 format |
| 3-1: Error handler scope | Full fetch wrapped | Generic error on HTTP errors |
| 3-2: Error UI | Generic "Something went wrong" | No custom server message rendering |
| 3-3: Error UI as warning substitute | NO | Generic only |
| 3-4: Silent HTTP codes | Unknown (assume 200 only) | Requires Phase 1 re-test |
| 4-1: SSE payload validation | YES (confirmed) | v5-v11 iterations show validation present |
| 4-2: H2 single write → immediate close | UNKNOWN | Requires Phase 3 test with END_STREAM |
| 4-3: Modifiable renderable field | chunks (answer=null always) | Only safe injection point |
| 4-4: Non-standard protocol | Hybrid SSE+WS | Not applicable to HTTP block |
| 4-5: Field modification side effects | answer field → thread breakage | Documented in v6/v8/v9/v10 failures |
| 4-6: Alternative delivery paths | None viable | SSE validation defeats mimicking |

**대안 방법 트리거:** 4-1 (payload validation) + 4-6 (기존 대안 없음) → **NEEDS_ALTERNATIVE** (apf-technical-limitations.md §2: Thread API 차단, 유효 thread 구조 반환)

---

## Deprecated Section (Previous Design — v5 Blocking Format)

### Current Block Implementation (v5 — LOCKED)

The implementation remains as documented in `generate_perplexity_sse_block_response()`. Warning text injection is inserted into the `chunks` array (lines 1365, 1377, 1401, 1406) via the `msg_escaped` variable. However, this approach serves only as block indication, not as user-facing warning. (이전 BLOCKED_ONLY 판정 기준 — 현재는 NEEDS_ALTERNATIVE로 전환됨)

### Version History: SSE Mimic Attempts (v5-v11)

All SSE field modification attempts (v6-v11) resulted in thread corruption or missing blocks:
- **v6:** Added extra fields to final event → thread breakage
- **v7:** Removed null checks on answer field → thread breakage
- **v8-v9:** Modified plan_block structure → state machine failure
- **v10:** Removed blocks from final event → missing answer area
- **v11:** Attempted double-encoding in chunks → parsing failure

Conclusion: v5 payload structure is rigid. SSE mimicking for custom warnings not viable without frontend code changes or WebSocket-level transformation.
