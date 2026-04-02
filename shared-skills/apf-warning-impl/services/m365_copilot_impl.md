## M365 Copilot (m365_copilot) — Implementation Journal

### Iteration 1 (2026-03-23) — Test 136
- DB: domain=substrate.office.com, path=/search/api/v1/
- Test result: NOT blocked, response fully delivered
- Observations:
  - Prompt '한글날' → full Korean response (언제? 무엇을 기념? 어떤 행사?)
  - Input automation failed (SendKeys, clipboard, JS — all rejected)
  - DevTools opened after prompt already submitted → POST request not captured
  - substrate.office.com NOT observed in Network tab
  - config.edge.skype.com → ERR_CERT_COMMON_NAME_INVALID (proxy cert mismatch)
  - Auth popup 나타남 but response still delivered
- 진단: 
  - Chat API가 substrate.office.com이 아닌 다른 도메인 사용 가능
  - 자동화 불가 + API endpoint 불확실
- Status: EXCLUDED (automation impossible + API endpoint unconfirmed)
- TODO: 수동 HAR 캡처로 실제 chat API endpoint 확인 필요

### Iteration 2 (2026-04-02) — Domain fix + network capture
- DB 변경: domain_patterns에 `copilot.microsoft.com` 추가, CORS origin → `*`
- Test #171: BLOCK_FAILED — SSE requests to browser.events.data.microsoft.com 200 OK
- Test #172 (network-capture): 실제 API 엔드포인트 확인 완료
  - **API 기본 경로**: `copilot.microsoft.com/c/api/`
  - 대화 생성: `POST /c/api/conversations` (application/json)
  - 히스토리: `GET /c/api/conversations/{id}/history`
  - 스트리밍: fetch() + ReadableStream (module: use-fetch-conversation-with-history)
  - 텔레메트리: `browser.events.data.microsoft.com` (OneCollector, 차단 대상 아님)
- **근본 문제**: DB path_patterns가 `/search/api/v1/` → 실제 `/c/api/`와 불일치
- **수정 필요**:
  - domain_patterns: `copilot.microsoft.com`
  - path_patterns: `/c/api/`
- Status: SSH 접속 불가로 DB 수정 대기 중
