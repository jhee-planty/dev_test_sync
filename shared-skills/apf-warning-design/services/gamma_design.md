## Gamma — Warning Design (RESET 2026-03-27)

### Phase 1 Reinspection (#078)
- accessible: true, login_required: true
- etap_proxy_active: true, protocol: h2
- comm_type: REST JSON (Phase 1 보고) — 코드는 SSE multi-chunk
- API: /ai/v2/generation (DevTools 필터 이슈로 불완전)
- WebSocket: 없음

### Strategy
- Pattern: SSE_STREAM_WARNING (Gamma 고유 chunk 형식)
- HTTP/2 strategy: B (keep-alive, ERR_CONNECTION_CLOSED 가능)
- Based on: 실제 Gamma 응답 = 9 chunk(plain text) + 1 done(data:stop)

### Response Specification
- HTTP Status: 200 OK
- Content-Type: text/event-stream; charset=utf-8
- SSE delimiter: \r\n\r\n
- Event: event:chunk (9개) + event:done
- Body: 경고 텍스트를 여러 chunk로 분할 전달
- Connection: keep-alive
- end_stream: true

### 이전 Build 이력
- Build #10: 200+SSE generation event → 경고가 카드 outline으로 소비 → 실패
- Build #11: event:error SSE → 에러 UI 표시 (부분 성공)
- Build #26: 유일한 성공 사례 → 재현 불가
- Build #33: 실제 형태 완전 재현 (9 chunk + done)

### Test Criteria
- [ ] 경고 메시지가 프레젠테이션 생성 대신 표시
- [ ] ERR_CONNECTION_CLOSED 발생 여부
- [ ] 에러 UI라도 경고 역할 수행 가능한지
- [ ] Build #33이 working인지 재확인

### Existing Code
- Generator: generate_gamma_block_response (line 1776)
- 현재 9 chunk + done 형식 (Build #33)

### Notes
- Gamma는 프레젠테이션/문서 생성기 (채팅 아님)
- 이전 BLOCKED_ONLY → 프론트엔드 변경 확인. 재검증 대상
- 경고 전달이 구조적으로 어려울 수 있음 (생성 콘텐츠로 소비됨)
