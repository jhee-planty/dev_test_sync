## GitHub Copilot — Warning Design

### Strategy
- Pattern: SSE_STREAM_WARNING
- HTTP/2 strategy: A (END_STREAM=true, GOAWAY=true)
  - Rationale: Standard SSE service with named events.
- Based on: GitHub Copilot uses SSE with custom event types (message_delta, message_end)

### Response Specification
- HTTP Status: 200
- Content-Type: text/event-stream; charset=utf-8
- Body format: SSE events with named event types
  - Event 1 (type=message_delta): `event: message_delta\r\ndata: {json}\r\n\r\n`
  - Event 2 (type=message_end): `event: message_end\r\ndata: {json}\r\n\r\n`
- JSON structure (message_delta):
  ```json
  {
    "content": "{escaped_warning_text}",
    "delta": {
      "content": "{escaped_warning_text}"
    }
  }
  ```
- JSON structure (message_end):
  ```json
  {
    "content": "{escaped_warning_text}"
  }
  ```
- Warning text: "⚠️ [보안 경고] 입력하신 내용에 민감한 정보가 포함되어 있어 전송이 차단되었습니다."
- JSON escaping: Standard (single-level)
- end_stream: true
- GOAWAY: yes

### Frontend Rendering Prediction
- Warning appears in: GitHub Copilot chat pane in IDE (VS Code, JetBrains, etc.)
- Rendered as: Assistant message text
- Known artifacts: None identified

### Test Criteria
- [ ] Send request with sensitive keyword to GitHub Copilot API
- [ ] Verify HTTP 200 response received
- [ ] Verify message_delta event with warning text received
- [ ] Verify message_end event received
- [ ] Verify warning appears in IDE chat pane
- [ ] Verify no error states or connection failures

### Relationship to Existing Code
- Existing generator: `ai_prompt_filter::generate_github_copilot_sse_block_response()` (implemented at line 1629)
- Current implementation: Complete
  - Proper SSE event naming with message_delta and message_end
  - Duplicate warning text in both content and delta fields
  - CORS headers for github.com
- Changes needed: NONE to generator code
- DB patterns needed:
  - `service_name`: "github_copilot"
  - `domain_pattern`: "api.individual.githubcopilot.com" (CORRECTED from "github.com")
  - `path_pattern`: "/github/chat/threads/{threadId}/messages"

### Known Issues
- **DB registration error**: Previously registered as "github.com" domain, which is incorrect
  - Must be updated to "api.individual.githubcopilot.com"
  - Old pattern captures all GitHub traffic, not just Copilot API
- Generator code is correct; only DB patterns need fixing

### Implementation Notes
- Generator produces valid SSE format with explicit event names
- Both delta and content fields carry the same warning text (redundant but safe)
- No UUID or timestamp generation needed (unlike ChatGPT/Grok)
