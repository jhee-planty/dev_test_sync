# GitHub Copilot — Warning Design

**Service:** GitHub Copilot Chat (copilot.github.com / github.com/copilot)
**Phase 1 Source:** frontend-profile Request #157, captured 2026-04-02
**Design Document Version:** 1.0

---

## Strategy

**Selected Strategy: C — Content-Length (HTTP/1.1 equivalent)**

GitHub Copilot communicates via REST JSON over HTTP/2. The response is a complete, sized JSON object (non-streaming). The response payload can be calculated in advance before transmission, making Content-Length-based delivery the most appropriate strategy.

**Rationale:**
- Communication type: REST JSON (synchronous, non-SSE)
- Frontend sends POST to `/messages` endpoint → receives single 200 OK response with full JSON body
- Response is deterministic (not streaming chunks)
- H2 allows Content-Length just as HTTP/1.1 does (Etap converts between protocols)
- No multiplexing concerns for this synchronous request-response pattern
- Strategy C avoids H2-specific complexity (GOAWAY, END_STREAM) while ensuring reliable delivery

---

## Response Specification

### HTTP Response Format

```
HTTP/1.1 403 Forbidden
Content-Type: application/json; charset=utf-8
Cache-Control: no-cache
access-control-allow-credentials: true
access-control-allow-origin: https://github.com
X-RateLimit-Remaining: 0
Content-Length: {calculated_size}

{
  "message": "{warning_text}",
  "documentation_url": "https://docs.github.com/copilot",
  "status": "403"
}
```

### Key Fields

| Field | Purpose | Notes |
|-------|---------|-------|
| `message` | Warning text | Escaped JSON string containing the policy violation message |
| `documentation_url` | Error context link | GitHub API standard field; points to Copilot docs |
| `status` | HTTP status indicator | Redundant with HTTP status line but included for GitHub API compatibility |

### Status Code Choice: 403 Forbidden

**Why 403, not other codes?**
- **422 (Build #21):** Generic error, frontend treats as processing failure. No specific error rendering path.
- **200 OK (Build #22):** Copilot would interpret as successful response, displaying as "interrupted" or parse error.
- **403 Forbidden:** GitHub API standard for policy/permission violations. Copilot has specific error handler for 403 that displays the error body's `message` field to user. Aligns with GitHub's own blocked-content responses.

### Content-Length Calculation

Response size is computed from the JSON body before transmission, ensuring the Content-Length header accurately reflects the byte count (UTF-8 encoded).

---

## Frontend Rendering Prediction

### Error UI Path

When Copilot receives 403 + JSON body:
1. Fetch completes with HTTP 403
2. Frontend's error handler catches the response
3. Error handler checks for `message` field in JSON body
4. If present, displays `message` text in error UI (error modal or alert box)
5. User sees the warning message

### Expected Outcome

Error message alert in chat interface; does NOT render in normal chat bubble flow.

### Formatting

- Plain text only (no Markdown in error UI)
- Line breaks (\n) are allowed and will render as new lines
- Emoji supported (UTF-8 safe in JSON)
- Keep text <200 chars for readability

---

## Test Criteria

| # | Criterion | Pass Condition |
|---|-----------|----------------|
| T1 | Warning reaches user | User sees warning text in error UI after sending blocked prompt |
| T2 | Content-Length accuracy | HTTP response completely transmitted; no truncation |
| T3 | JSON validity | Response parses as valid JSON; no syntax errors |
| T4 | No side effects | Chat thread remains usable; follow-up prompts work normally |
| T5 | CORS compliance | Access-Control-Allow-Origin: https://github.com present |
| T6 | Protocol handling | H2 and HTTP/1.1 both transport response correctly via Etap |

---

## Test Log Points

Key metrics to capture during Phase 3:

```
[APF_WARNING_TEST:copilot]
  response_code=403
  body_size={Content_Length_value}
  message_length={JSON_message_field_byte_count}
  strategy=content_length_403
  error_ui_displayed={true|false}
```

### Failure Modes

| Symptom | Likely Cause | Investigation |
|---------|--------------|----------------|
| 200 response instead of 403 | Rule not matching or interception failed | Check APF rule registration |
| JSON parse error in console | Malformed JSON (escaping issue) | Validate special character escaping |
| Message truncated | Content-Length mismatch | Verify byte count (UTF-8 encoding) |
| CORS error in console | Missing/wrong Access-Control-Allow-Origin header | Verify origin matches https://github.com |
| Error UI shows but empty | Missing `message` field in JSON | Check JSON structure includes all required fields |

---

## Relationship to Existing Code

### Current Implementation

**File:** `/sessions/ecstatic-loving-davinci/mnt/Officeguard/EtapV3/functions/ai_prompt_filter/ai_prompt_filter.cpp`
**Lines:** 1744–1784
**Function:** `generate_github_copilot_sse_block_response()`

The function already implements Strategy C with:
- JSON escaping of special characters
- 403 Forbidden status with GitHub API error format
- Content-Length header computed from body size
- CORS headers for GitHub origin
- Audit logging (`bo_mlog_info`)

**Status:** Ready for Phase 3 testing without modification.

### Entry Point

Registered in service map (line 119):
```cpp
_response_generators["github_copilot"] = generate_github_copilot_sse_block_response;
```

---

## Notes

### Why Strategy C (Content-Length), not A or D?

- **Strategy A (END_STREAM + GOAWAY):** For streaming responses requiring clean H2 termination. Copilot uses non-streaming JSON, so A is overly complex.
- **Strategy D (END_STREAM without GOAWAY):** Protects multiplexing cascade failure. GitHub Copilot's API is sequential (no concurrent H2 streams), so D is unnecessary.
- **Strategy C:** Simplest, most stable across H1 and H2. Content-Length tells browser exactly when body ends. Etap handles protocol conversion transparently.

### Prior Build History

- **Build #21 (SSE_STREAM_WARNING with 422):** Generic error handling, SSE mimic failed due to Etap single-write limitation (H2 stream closed before events parsed)
- **Build #22 (200 OK + JSON):** Frontend attempted to parse as normal AI response, showed "interrupted"
- **Build #23 (403 + JSON_SINGLE_WARNING):** Error handler recognizes 403 and displays `message` field — success path identified

### No SSE Pattern Here

Original design attempted SSE_STREAM_WARNING, but this service doesn't use SSE. Phase 1 confirms:
- Copilot's `/messages` endpoint returns `application/json`, not `text/event-stream`
- Normal response is single JSON object, not streamed events
- Injecting SSE would violate frontend's expectations and fail parsing

### Testing Priority

1. Manual Phase 3a: Send blocked prompt via web UI, screenshot error UI, verify message is readable
2. Automated Phase 3b: POST to `/messages` with blocked payload, validate HTTP 403, Content-Length match, JSON format
3. Regression: Send normal prompt after warning, verify normal response still works

---

## Checklist Results Summary

### Section 1: Frontend Characteristics

| Item | Result |
|------|--------|
| Communication type | REST JSON (not SSE) |
| HTTP Protocol | HTTP/2 |
| Multiplexing | No simultaneous streams in normal flow |
| WebSocket | No |

### Section 2: Frontend Rendering

| Item | Result |
|------|--------|
| Content-Type | application/json |
| Error UI type | Displays custom message from `message` field |
| Markdown support | No (plain text error modal) |
| Message creation minimum | JSON with `message` field + HTTP 403 status |

### Section 3: Error Handling

| Item | Result |
|------|--------|
| Error handler scope | All API calls (fetch) wrapped |
| Error UI approach | Custom message display (not generic) |
| 403 handling | Recognized, displays message field |

### Section 4: Deliverability

| Item | Result |
|------|--------|
| Payload validation | None detected |
| Modifiable response field | YES — `message` field |
| Side effects | Minimal (error-only field) |
| Alternative paths | 403 JSON is primary option |

### Strategy Selection Matrix

**Condition matched:** Content-Length possible + non-streaming response
**Selection:** **Strategy C** ✓

Confidence: **HIGH** (standard REST JSON API, no unusual protocol constraints)

---

## Status

- Checklist: COMPLETE
- Risk assessment: LOW
- Phase 3 readiness: YES
- Code changes required: NO (existing implementation matches design)
