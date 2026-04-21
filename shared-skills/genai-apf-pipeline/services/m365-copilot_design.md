## M365 Copilot — Warning Design

### Strategy
- Pattern: 미정 (자동화 불가, 수동 HAR 필요)
- HTTP/2 strategy: 미정
- Based on: substrate.office.com API. 자동화 입력 불가.

### Response Specification
- API: substrate.office.com, path=/
- is_http2: 미확인
- 스트리밍 프로토콜: 미확인

### Current State: 미진입
React contenteditable div가 모든 자동화 입력 거부.
API endpoint 불확실. 수동 HAR 캡처 필요.

### Known Constraints
- React contenteditable div: SendKeys, clipboard, JS injection 모두 거부
- CDP(--remote-debugging-port=9222)가 대안이나 미검증
- API endpoint 불확실
- 수동 테스트 필요

### 접근 방안
1. **수동 HAR 캡처**: 사용자가 직접 M365 Copilot에서 프롬프트 전송 → HAR 파일 저장
2. **HAR 분석**: 실제 API endpoint, Content-Type, 스트리밍 방식 파악
3. **CDP 자동화**: --remote-debugging-port=9222로 Chrome 원격 디버깅 → 입력 자동화 시도
4. **"수동 입력 필요" 보고**: 자동화 불가 시 수동 테스트 상태로 유지

### Test Criteria
- [ ] API endpoint 파악
- [ ] 스트리밍 프로토콜 확인
- [ ] 차단 가능 여부 확인
- [ ] 경고 전달 방식 결정

### Relationship to Existing Code
- Existing generator: 없음
- is_http2 value: 미확인
- DB: substrate.office.com, path=/

### Notes
- 난이도 매우 높음. 모든 다른 서비스 완료 후 마지막으로 진행.
- 사용자에게 수동 HAR 캡처 요청 필요.
