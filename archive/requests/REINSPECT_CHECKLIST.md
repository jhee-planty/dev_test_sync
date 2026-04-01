# Phase 1 재검증 표준 체크리스트

모든 서비스에 동일하게 적용한다. 이전 경험이나 판정을 참조하지 않는다.

## 필수 확인 항목

### 1. 접근성
- [ ] URL 접근 가능 여부
- [ ] 로그인 필요 여부 (필요 시 어떤 계정 유형인지)
- [ ] Etap 프록시 경유 여부 (차단/경고가 동작하려면 필수)

### 2. 네트워크 통신 분석 (DevTools Network 탭)
- [ ] AI 프롬프트 전송 시 사용되는 API endpoint (URL 패턴)
- [ ] 프로토콜: HTTP/1.1, HTTP/2, 기타
- [ ] 응답 형식: JSON, SSE (text/event-stream), plain text, 기타
- [ ] 총 요청 수 (페이지 로드 시 / AI 프롬프트 전송 후)

### 3. WebSocket 확인 (DevTools Network > WS 필터)
- [ ] WebSocket 연결 수 (0이면 명시적으로 "0" 기록)
- [ ] WS endpoint URL (있는 경우)
- [ ] WS로 전달되는 데이터 유형 (AI 응답 vs telemetry)

### 4. Service Worker 확인
- [ ] DevTools Application > Service Workers 탭 확인
- [ ] API 요청이 SW에 의해 가로채지는지 여부

### 5. 차단 동작 확인
- [ ] Etap이 트래픽을 인터셉트하는지 (프록시 경유 확인)
- [ ] 차단 시 어떤 응답이 돌아오는지 (HTTP status, body)
- [ ] 프론트엔드가 차단 응답을 어떻게 처리하는지

### 6. 스크린샷
- [ ] 정상 동작 화면
- [ ] DevTools Network 탭 (AI 프롬프트 전송 후)
- [ ] DevTools WS 필터 화면
- [ ] 차단 시 화면 (가능한 경우)

## 결과 형식

```json
{
  "service": "",
  "url": "",
  "accessible": true/false,
  "login_required": true/false,
  "etap_proxy_active": true/false,
  "api_endpoint": "",
  "protocol": "",
  "response_format": "",
  "websocket_count": 0,
  "ws_endpoints": [],
  "service_worker": true/false,
  "sw_intercepts_api": true/false,
  "block_works": true/false,
  "block_response": "",
  "frontend_block_behavior": "",
  "total_requests_load": 0,
  "total_requests_chat": 0,
  "screenshots": []
}
```
