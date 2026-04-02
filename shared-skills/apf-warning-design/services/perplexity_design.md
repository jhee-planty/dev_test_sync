## Perplexity — Warning Design (RESET 2026-03-27)

### Phase 1 Reinspection (#072)
- accessible: true, login_required: true
- etap_proxy_active: true, protocol: h2
- comm_type: REST JSON (Phase 1 보고) — 실제 코드는 SSE text/event-stream
- API: /rest/sse/perplexity_ask
- WebSocket: 없음

### ★ CRITICAL ISSUE: 경고 문구 미표시
코드 주석에 명시: "경고 텍스트 전달은 SSE 미믹으로는 불가능. PARTIAL(차단O, 경고X) 확정."
- answer 필드를 non-null로 설정하면 스레드 깨짐 (v5-v11 테스트 완료)
- chunks 필드에 경고 텍스트 포함하나 프론트엔드가 렌더링하지 않음
- 현재 상태: 차단 O, 경고 표시 X

### Strategy
- Pattern: SSE_STREAM_WARNING (현재) — 경고 표시 실패
- HTTP/2 strategy: B (keep-alive, 가능한 network error artifact)
- **재설계 필요**: SSE 미믹 외 대안 방식 탐색 필수

### 대안 탐색 필요 사항
1. **HTML error page**: HTTP 403/200 + text/html 경고 페이지
2. **JSON error response**: Perplexity error handler가 표시하는 에러 포맷
3. **redirect**: 경고 페이지로 리다이렉트
4. **plain text body**: text/plain 으로 경고 전달
5. **chunks 렌더링 조건 재조사**: 프론트엔드 JS 분석 필요

### Current Response Specification (v5 — 차단만 동작)
- HTTP Status: 200 OK
- Content-Type: text/event-stream; charset=utf-8
- SSE delimiter: \n\n (LF+LF)
- Event count: 6 (init + tabs + plan_done + content + final + end_of_stream)
- answer: null (LOCKED — 변경 시 스레드 깨짐)
- chunks: 경고 텍스트 포함하나 렌더링 안됨

### Test Criteria (Phase 3에서 대안 방식 테스트)
- [ ] 경고 메시지가 사용자에게 가시적으로 표시
- [ ] 페이지/스레드가 깨지지 않음
- [ ] 에러 UI가 경고 역할을 대체 가능한지 확인
- [ ] 대안 방식 중 최소 하나 이상 working 확인

### Existing Code
- Generator: generate_perplexity_sse_block_response (line 1206)
- 매우 복잡 (6개 이벤트, v5-v11 진화)
- is_http2: 확인 필요

### Notes
- 사용자 보고: "경고 문구가 표시 되지 않는다" — 코드가 이를 확인
- v5 이후 10회 이상 반복 테스트에서 answer non-null → 스레드 깨짐
- 근본 원인: Perplexity 프론트엔드의 엄격한 SSE payload 검증
- Phase 3에서 SSE 외 대안 (HTML error page, JSON error 등) 시도 필요
- **방식을 특정하지 말고 가능한 방법들이 있는지 전부 조사** (사용자 지시)
