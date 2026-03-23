## Gemini — Warning Design

### Strategy
- Pattern: WEBCHANNEL_WARNING
- HTTP/2 strategy: D (END_STREAM=true, GOAWAY=false)
  - Rationale: GOAWAY causes cascade failure in Google Webchannel multiplexed streams. Use END_STREAM to signal message completion without closing connection.
- Based on: Gemini uses proprietary Google Webchannel (protobuf-over-JSON in wrb.fr envelope format)

### Response Specification
- HTTP Status: 200 (MUST be 200, not 403 - frontend ignores 403)
- Content-Type: application/x-protobuf
- Body format: Google Webchannel wrb.fr envelope
  - XSS protection header: `)]}'\n\n`
  - Envelope structure: `[[["wrb.fr","XqA3Ic","{payload_json}",null,null,null,"generic"]]]`
  - Payload: Double JSON-escaped nested array with warning text at index [0][0]
  - Length prefix: `{size}\n{data}`
- Warning text: "⚠️ [보안 경고] 입력하신 내용에 민감한 정보가 포함되어 있어 전송이 차단되었습니다."
- Double JSON escaping: Required due to nested JSON in wrb.fr envelope payload string
- end_stream: true
- GOAWAY: no (causes cascade failure)

### Frontend Rendering Prediction
- Warning appears in: Gemini chat window as regular assistant message
- Rendered as: Plain text in chat message bubble
- Known artifacts: 
  - 403 status causes silent failure (frontend does not parse response)
  - GOAWAY triggers cascade reconnection failures
  - Message must be parseable as valid protobuf/webchannel or discarded

### Test Criteria
- [ ] Send request with sensitive keyword to Gemini API endpoint
- [ ] Verify HTTP 200 response received
- [ ] Verify warning message appears in chat UI (not error state)
- [ ] Verify connection remains open (no GOAWAY cascade)
- [ ] Verify page does not show "connection error" or retry prompts

### Relationship to Existing Code
- Existing generator: `ai_prompt_filter::generate_gemini_block_response()` (implemented at line 1494)
- Current implementation: Complete and correct
  - Proper double JSON escaping for wrb.fr envelope
  - Correct HTTP 200 status
  - Correct Content-Type header
  - CORS headers for gemini.google.com
- Changes needed: None to generator code; DB pattern verification only
- DB patterns needed:
  - `service_name`: "gemini" or "gemini3"
  - `domain_pattern`: "signaler-pa.clients6.google.com"
  - `path_pattern`: "/punctual/multi-watch/channel"

### Implementation Notes
- Generator includes debug logging: `[APF_WARNING_TEST:gemini]`
- Payload structure matches BardChatUi JS parser expectations
- Text position at `payload[0][0]` matches frontend parsing code
