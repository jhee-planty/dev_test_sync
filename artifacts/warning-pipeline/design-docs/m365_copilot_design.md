## M365 Copilot — Warning Design

### Strategy
- Pattern: SSE_STREAM_WARNING with copilotConversation events
- HTTP/2 strategy: A (END_STREAM=true, GOAWAY=true) - may need D if multiplexing issues arise
  - Rationale: Microsoft's SSE implementation appears standard. Monitor for multiplexing in Office 365 context.
- Based on: M365 Copilot uses SSE with copilotConversation event types (Fluent UI React frontend)

### Response Specification
- HTTP Status: 200
- Content-Type: text/event-stream; charset=utf-8
- Body format: SSE events with copilotConversation event type
  - Event 1 (message_start): `event: copilotConversation\r\ndata: {json}\r\n\r\n`
  - Event 2 (message_content_delta): `event: copilotConversation\r\ndata: {json}\r\n\r\n`
  - Event 3 (message_end): `event: copilotConversation\r\ndata: {json}\r\n\r\n`
- JSON structure (message_start):
  ```json
  {
    "id": "evt_001",
    "type": "message_start",
    "conversation": {
      "messageId": "msg-apf-{uuid8}",
      "role": "assistant"
    }
  }
  ```
- JSON structure (message_content_delta):
  ```json
  {
    "id": "evt_002",
    "type": "message_content_delta",
    "conversation": {
      "content": "{escaped_warning_text}"
    }
  }
  ```
- JSON structure (message_end):
  ```json
  {
    "id": "evt_003",
    "type": "message_end",
    "conversation": {
      "messageId": "msg-apf-{uuid8}",
      "finishReason": "blocked"
    }
  }
  ```
- Warning text: "⚠️ [보안 경고] 입력하신 내용에 민감한 정보가 포함되어 있어 전송이 차단되었습니다."
- JSON escaping: Standard (single-level)
- end_stream: true
- GOAWAY: yes

### Frontend Rendering Prediction
- Warning appears in: Office 365 Copilot pane (Fluent UI React)
- Rendered as: Assistant message in conversation
- Known artifacts: 
  - Fluent UI may apply styling/formatting
  - finishReason: "blocked" indicates policy rejection

### Test Criteria
- [ ] Send request with sensitive keyword to M365 Copilot API
- [ ] Verify HTTP 200 response received
- [ ] Verify copilotConversation event type in all three events
- [ ] Verify message_start with messageId and assistant role
- [ ] Verify message_content_delta with warning text
- [ ] Verify message_end with finishReason: "blocked"
- [ ] Verify warning appears in Office UI
- [ ] Verify Fluent UI renders the blocked message correctly

### Relationship to Existing Code
- Existing generator: `ai_prompt_filter::generate_m365_copilot_sse_block_response()` (implemented at line 1678)
- Current implementation: Complete
  - Proper SSE copilotConversation event naming
  - Correct three-phase message sequence (start → delta → end)
  - UUID generation for message IDs
  - finishReason: "blocked" indicates policy rejection
  - CORS headers for m365.cloud.microsoft
- Changes needed: None to generator code
- DB patterns needed:
  - `service_name`: "m365_copilot"
  - `domain_pattern`: "TBD - pending capture result 088" (estimated: m365.cloud.microsoft OR substrate.office.com)
  - `path_pattern`: TBD (typically /chat or /copilot endpoint)

### Known Issues
- **API domain TBD**: Exact M365 Copilot API domain not yet confirmed
  - Candidates: m365.cloud.microsoft, substrate.office.com, or other internal Microsoft endpoints
  - Waiting for HAR capture result #088
  - Generator CORS headers point to m365.cloud.microsoft (may need adjustment)
- **Multiplexing uncertainty**: If M365 uses HTTP/2 multiplexing heavily, may need HTTP/2 strategy D (no GOAWAY)

### Implementation Notes
- Generator uses UUID generation: `generate_uuid4().substr(0, 8)`
- Three-phase message delivery ensures frontend state machine compatibility
- Message IDs must be unique per session (UUID suffix provides this)
- finishReason: "blocked" is custom (not standard OpenAI, mimics Copilot conventions)
- No timestamp field needed (unlike ChatGPT/Grok)
