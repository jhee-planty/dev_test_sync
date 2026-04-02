## Genspark — Warning Design (RESET 2026-03-27)

### Phase 1 Reinspection (#076)
- accessible: true, login_required: true
- etap_proxy_active: true, protocol: h2
- comm_type: REST JSON (Phase 1 보고) — 코드는 SSE text/event-stream
- API: /api/agent/ask_proxy (DevTools 필터 이슈로 불완전)
- WebSocket: 없음

### Strategy
- Pattern: SSE_STREAM_WARNING (Genspark 고유 이벤트 형식)
- HTTP/2 strategy: B (keep-alive, network error artifact 가능)
- Based on: data-only SSE (event: 필드 없음), project/message 구조

### Response Specification
- HTTP Status: 200 OK
- Content-Type: text/event-stream; charset=utf-8
- SSE delimiter: \n\n (LF+LF — ★ \r\n\r\n 사용 금지, naive parser 문제)
- Event sequence: project_start → message_field(_updatetime) → message_start → message_field_delta(content) → message_field(content) → message_result → project_field(FINISHED)
- Required: project_id(UUID4), message_id(UUID4)
- end_stream: true

### Test Criteria
- [ ] 경고 메시지가 채팅 버블에 정상 표시
- [ ] ERR_CONNECTION_CLOSED 발생 여부 확인
- [ ] 콘솔 JSON.parse 에러 없음
- [ ] message_field_delta가 버블 생성 트리거하는지 확인

### Existing Code
- Generator: generate_genspark_sse_block_response (line 1426)
- 7개 이벤트, \n\n 구분자 사용 (이전 \r\n\r\n 버그 수정됨)
- message_field_delta가 핵심 (이것 없으면 UI에 미표시)

### Notes
- SSE 구분자 주의: \n\n만 사용 (\r\n\r\n → JSON.parse 실패)
- 이전 INFRA_FRONTEND_CHANGED → 재검증 대상
