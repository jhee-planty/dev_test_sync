## Grok — Warning Design

### Strategy
- Pattern: SSE_STREAM_WARNING
- HTTP/2 strategy: A (END_STREAM=true, GOAWAY=true)
  - Rationale: Grok is a standard SSE consumer. Normal SSE completion protocol applies.
- Based on: Grok uses OpenAI-compatible API format (Next.js frontend, xAI backend)

### Response Specification
- HTTP Status: 200
- Content-Type: text/event-stream; charset=utf-8
- Body format: SSE events (data-only, no named events like ChatGPT)
  - Event 1: `data: {json_completion_chunk}\r\n\r\n`
  - Event 2: `data: [DONE]\r\n\r\n`
- JSON structure (event 1):
  ```json
  {
    "id": "cmpl-apf-{uuid8}",
    "object": "chat.completion.chunk",
    "created": {timestamp},
    "model": "grok-3",
    "choices": [{
      "index": 0,
      "delta": {
        "role": "assistant",
        "content": "{escaped_warning_text}"
      },
      "finish_reason": "stop"
    }]
  }
  ```
- Warning text: "⚠️ [보안 경고] 입력하신 내용에 민감한 정보가 포함되어 있어 전송이 차단되었습니다."
- JSON escaping: Standard (single-level)
- end_stream: true
- GOAWAY: yes

### Frontend Rendering Prediction
- Warning appears in: Grok chat window (may be replaced by Grok's own error UI)
- Rendered as: Assistant message text
- Known artifacts:
  - Grok shows its own error UI instead of our SSE warning text in some cases
  - Unknown if our SSE format properly renders in Grok's frontend
  - Need to verify actual rendering behavior with live traffic

### Test Criteria
- [ ] Send request with sensitive keyword to Grok API
- [ ] Verify HTTP 200 response received
- [ ] Verify SSE data event with warning text received
- [ ] Verify [DONE] marker signals stream completion
- [ ] Verify warning displays in chat UI (or Grok error UI appears)
- [ ] Verify CSP allows content from grok.com and *.x.ai

### Relationship to Existing Code
- Existing generator: `ai_prompt_filter::generate_grok_sse_block_response()` (implemented at line 1574)
- Current implementation: Complete
  - Proper OpenAI-compatible JSON structure
  - Correct model field: "grok-3"
  - Proper SSE format with data prefix and [DONE] terminator
  - CORS headers for grok.com
- Changes needed: None to generator code
- DB patterns needed:
  - `service_name`: "grok"
  - `domain_pattern`: "grok.com"
  - `path_pattern`: "/api/chat/completions" (verify against HAR)

### Implementation Notes
- Generator uses UUID generation: `generate_uuid4().substr(0, 8)`
- Timestamp uses current time: `time(nullptr)`
- Critical uncertainty: Whether Grok's Next.js frontend actually renders our SSE text or shows its own error UI instead
- CSP headers may restrict content rendering
