## GitHub Copilot — Warning Design (RESET 2026-03-27)

### Phase 1 Reinspection (#077)
- accessible: true, login_required: true
- etap_proxy_active: true, protocol: h2
- comm_type: SSE streaming
- API: (DevTools 필터 이슈로 불완전)
- WebSocket: 없음

### Strategy
- Pattern: JSON_SINGLE_WARNING (403 Forbidden + GitHub API error format)
- HTTP/2 strategy: C (Content-Length 기반)
- Based on: SSE 방식 실패 이력 (Build #21-22), 403 JSON error로 전환

### SSE 방식 실패 이력
- Build #21: END_STREAM=false → ERR_HTTP2_PROTOCOL_ERROR → 폐기
- Build #21: END_STREAM=true → 이벤트 미수신 (즉시 종료)
- 근본 원인: Etap 단일 write → Chrome이 이벤트 파싱 전 스트림 종료
- Build #22: 200+JSON → "interrupted" 표시

### Response Specification
- HTTP Status: 403 Forbidden
- Content-Type: application/json; charset=utf-8
- Body: {"message":"경고텍스트","documentation_url":"...","status":"403"}
- X-RateLimit-Remaining: 0
- end_stream: true

### Test Criteria
- [ ] Copilot 에러 핸들러가 403 body의 message를 표시하는지 확인
- [ ] generic error만 표시되면 → 다른 status code 시도 (400, 429)
- [ ] 경고 메시지가 사용자에게 가시적으로 전달되는지 확인

### Existing Code
- Generator: generate_github_copilot_sse_block_response (line 1682)
- 현재 403 Forbidden + GitHub API 에러 포맷
- Build #21→#23 진화 (SSE→422→403)

### Notes
- 이전 PASS 판정이었으나 재검증 대상
- SSE 방식이 H2 환경에서 구조적으로 실패 — JSON error 방식 유지
- 프론트엔드 에러 핸들러 동작 확인 필요
