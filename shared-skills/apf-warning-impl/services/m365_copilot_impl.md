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
- Status: **NEEDS_USER_SESSION** (이전: EXCLUDED)
- TODO: 수동 HAR 캡처로 실제 chat API endpoint 확인 필요

### 사용자 협업 필요 (2026-04-10)
로그인 분류: No-function (즉시 로그인 리다이렉트)
→ NEEDS_USER_SESSION으로 전환. 사용자 협업 세션에서 일괄 테스트 예정.
`apf-technical-limitations.md` §6 참조:
1. 로그인 상태에서 재테스트 (실제 chat API endpoint 확인)
2. 비로그인 리다이렉트 페이지에서 경고 주입 시도
