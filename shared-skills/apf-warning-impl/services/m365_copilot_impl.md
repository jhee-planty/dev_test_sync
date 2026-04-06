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
