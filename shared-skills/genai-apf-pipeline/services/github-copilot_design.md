## GitHub Copilot — Warning Design

### Strategy
- Pattern: SSE_STREAM_WARNING (attempted) → BLOCKED_ONLY
- HTTP/2 strategy: B (keep-alive, is_http2=2)
- Based on: GitHub Copilot uses SSE via SPA fetch handler that ignores injected responses.

### Response Specification
- API: api.individual.githubcopilot.com/github/chat
- Content-Type: text/event-stream
- is_http2: 2 (keep-alive)

### Current State: BLOCKED_ONLY
SPA fetch handler가 Etap의 응답을 무시. H2 single write도 실패.
8회 연속 실패 이력.

### Known Constraints
- GitHub SPA의 fetch handler가 SSE 응답을 인터셉트
- Etap이 주입한 SSE 응답이 fetch handler에 의해 무시됨
- H2 single write 실패

### 새로운 접근법 (Phase 2 재설계)
1. **api 도메인 차단 + 에러 응답**: api.individual.githubcopilot.com에 에러 HTTP 응답 → 프론트엔드 에러 UI
2. **block page**: github.com/copilot 페이지 자체 차단
3. **Content-Type 변경**: SSE 대신 text/html 등 다른 Content-Type 시도

### Test Criteria
- [ ] 차단 동작 확인
- [ ] SPA fetch handler 우회 가능 여부 확인
- [ ] 새로운 접근법 테스트 결과

### Relationship to Existing Code
- Existing generator: 없음 (register_block_response_generators에 github_copilot 미등록)
- is_http2 value: 2
- DB: api.individual.githubcopilot.com, path=/github/chat

### Notes
- 8회 연속 실패 이력. SPA fetch handler가 근본 원인.
