## Gamma — Warning Design

### Strategy
- Pattern: H2_DATA_WARNING (attempted) → **NEEDS_ALTERNATIVE**
- HTTP/2 strategy: B (keep-alive, is_http2=2)
- Based on: Gamma uses HTTP/2 streaming. H2 DATA frame delivery 실패.

### Response Specification
- API: ai.api.gamma.app, path=/
- is_http2: 2 (keep-alive)

### Current State: NEEDS_ALTERNATIVE
H2 DATA frame delivery 실패. 7빌드 실패 이력.

**대안 접근법** (2026-04-10, apf-technical-limitations.md §5):
1. EventSource 호환 에러 이벤트 전달

### Known Constraints
- H2 DATA frame이 클라이언트에 도달하지 않음
- cert error 가능성
- 7빌드 실패 이력

### 새로운 접근법 (Phase 2 재설계)
1. **is_http2 변경**: 2→1 또는 0으로 변경하여 다른 전송 전략 시도
2. **에러 응답**: HTTP 에러 코드로 프론트엔드 에러 UI 활용
3. **block page**: ai.api.gamma.app 차단 + HTML 경고 페이지

### Test Criteria
- [ ] 차단 동작 확인
- [ ] H2 DATA delivery 성공 여부 확인
- [ ] 경고 문구 표시 여부

### Relationship to Existing Code
- Existing generator: 없음 확인 필요 (register_block_response_generators 검색)
- is_http2 value: 2
- DB: ai.api.gamma.app, path=/

### Notes
- 7빌드 실패 + cert error 이력. 근본적 전송 계층 문제 가능성.
