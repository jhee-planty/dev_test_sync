## M365 Copilot — Warning Design (RESET 2026-03-27)

### Phase 1 Reinspection (#079)
- accessible: true, login_required: false
- etap_proxy_active: true, protocol: h2
- comm_type: SSE streaming
- API: (DevTools 필터 이슈로 불완전)
- WebSocket: 없음
- ★ 이전 EXCLUDED/BYPASS 오판 수정 — proxy 활성 확인

### Strategy
- Pattern: SSE_STREAM_WARNING (copilotConversation 이벤트 형식)
- HTTP/2 strategy: C (Content-Length 기반)
- Based on: M365 Copilot SSE (message_start → content_delta → message_end)

### Response Specification
- HTTP Status: 200 OK
- Content-Type: text/event-stream; charset=utf-8
- SSE delimiter: \r\n\r\n
- Event sequence:
  1. event:copilotConversation — type:message_start
  2. event:copilotConversation — type:message_content_delta (경고텍스트)
  3. event:copilotConversation — type:message_end (finishReason:blocked)
- Required: messageId(UUID), conversation structure
- end_stream: true

### Test Criteria
- [ ] 경고 메시지가 Copilot 채팅 UI에 표시
- [ ] 에러 핸들러가 finishReason:blocked를 어떻게 처리하는지 확인
- [ ] 로그인 없이 접근 시에도 동작 확인
- [ ] 콘솔에 치명적 에러 없음

### Existing Code
- Generator: generate_m365_copilot_sse_block_response (line 1726)
- 3개 이벤트 구조 (비교적 간결)

### Notes
- 이전 EXCLUDED → proxy 활성 확인됨. 완전히 새로운 테스트 필요
- 로그인 불필요 — 접근성 높음
- copilotConversation 이벤트 형식 정확성 확인 필요
