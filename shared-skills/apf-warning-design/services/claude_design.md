## Claude — Warning Design (RESET 2026-03-27)

### Phase 1 Reinspection (#071)
- accessible: true, login_required: true
- etap_proxy_active: true, protocol: h2
- comm_type: SSE streaming
- API: a-api.anthropic.com (chat completion endpoint)
- WebSocket: Intercom only (고객지원 위젯, AI API 아님)

### Strategy
- Pattern: SSE_STREAM_WARNING
- HTTP/2 strategy: A (END_STREAM + GOAWAY, 깔끔한 종료)
- Based on: Claude SSE 이벤트 시퀀스 (message_start → content_block_start → content_block_delta → content_block_stop → message_delta → message_stop)

### Response Specification
- HTTP Status: 200 OK
- Content-Type: text/event-stream; charset=utf-8
- Body format: Claude API SSE events
- SSE delimiter: \r\n\r\n
- Warning text: 경고 메시지 (DB에서 로드)
- Event sequence: message_start → content_block_start → content_block_delta(경고텍스트) → content_block_stop → message_delta(stop_reason=end_turn) → message_stop
- Required fields: message.id(msg_01 형식), model=claude-sonnet-4-6, role=assistant
- Headers: request-id, Server: cloudflare, vary, X-Robots-Tag
- end_stream: true
- GOAWAY: yes (Strategy A)

### Frontend Rendering Prediction
- Warning appears in: 채팅 버블 (assistant message)
- Rendered as: markdown (Claude 프론트엔드 마크다운 렌더러)
- User experience: AI 응답 대신 경고 메시지가 채팅 버블에 표시
- Known artifacts: 없음 (Strategy A, 깔끔한 종료)

### Test Criteria
- [ ] 경고 메시지가 채팅 버블에 정상 표시
- [ ] 529 에러/재시도 루프 미발생 (이전 버그)
- [ ] 콘솔에 치명적 에러 없음
- [ ] 페이지 정상 동작 유지

### Existing Code
- Generator: generate_claude_block_response (line 1102)
- JSON 특수문자 이스케이프 처리 포함
- 이전 529 JSON 에러 방식 → SSE 방식으로 전환 완료
- is_http2: 확인 필요 (DB)

### Notes
- 이전 DONE 판정이었으나 전면 재검증 대상
- 529 에러 응답 → SSE 스트림 전환 이력 있음 (코드 주석에 기록)
