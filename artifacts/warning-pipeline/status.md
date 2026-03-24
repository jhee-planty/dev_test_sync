# Warning Pipeline — Service Status (2026-03-24 12:35 updated)

| Service | service_id | Phase | Status | Last updated | Notes |
|---------|-----------|-------|--------|-------------|-------|
| ChatGPT | chatgpt | Done | DONE | 2026-03-17 | Strategy C (HTTP/1.1), SSE warning |
| Claude | claude | Done | DONE | 2026-03-18 | Strategy A (END_STREAM + GOAWAY) |
| Perplexity | perplexity | Done | DONE | 2026-03-17 | SSE stream warning |
| Genspark | genspark | 3 | TESTING | 2026-03-20 | Strategy B, 경고 표시되나 network error artifact 잔존 |
| Gemini | gemini3 | 3 | DETECT_FAIL | 2026-03-24 | detect 0건. gemini.google.com TLS SNI 미인터셉트. HAR 캡처로 실제 API domain 확인 필요 |
| Grok | grok | 3 | EXCLUDED | 2026-03-23 | 자동화 불가 (입력 거부, 인증 필요, cert mismatch). 수동 테스트 필요 |
| GitHub Copilot | github_copilot | 3 | TEST_FAIL | 2026-03-24 | blocked=true but warning NOT visible. SSE stuck, Thinking... 무한대기 |
| Gamma | gamma | 3 | PARTIAL_BLOCK | 2026-03-24 | /graphql BLOCKED (SSN감지) but render-generation 201 통과. 다중API 구조 |
| M365 Copilot | m365_copilot | 3 | EXCLUDED | 2026-03-23 | 자동화 불가 + API endpoint 불확실. 수동 HAR 필요 |
| Notion AI | notion | 3 | BLOCKED_NO_WARN | 2026-03-24 | /api/v3/runInferenceTranscript BLOCKED! 경고 미표시 → warning impl 수정 필요 |

## Test 152-154 결과 (2026-03-24, etapd restart 후)

### Gemini (Test 152) — DETECT_FAIL
- batchexecute 200 (192ms), AI 정상 응답
- etap log: gemini detect 0건 (오늘 전체)
- 원인: `gemini.google.com` TLS SNI가 인터셉트되지 않음
- **필요 조치**: HAR 캡처로 실제 API domain/SNI 확인. 또는 etap debug log에서 TLS handshake 확인

### Gamma (Test 153) — PARTIAL_BLOCK  
- etap log: `BLOCKED, /graphql, gamma.app, \d{6}-\d{7}, ssn` (CreateDocGeneration mutation)
- 그러나 `render-generation` 201로 콘텐츠 생성 완료 (10 cards)
- Console: `api.gamma.app/graphql 403` — Etap 차단 확인
- 원인: Gamma가 graphql 차단 후에도 별도 render endpoint로 콘텐츠 전달
- **필요 조치**: render-generation endpoint 도메인 확인 + 추가 패턴 등록

### Notion (Test 154) — BLOCKED, WARNING NOT VISIBLE
- etap log: `BLOCKED, /api/v3/runInferenceTranscript, www.notion.so, \d{6}-\d{7}, ssn`
- Test: `runInferenceTranscriptApiError` — AI inference 차단 성공!
- 경고 텍스트 미표시, 빈 채팅 영역
- **필요 조치**: `generate_notion_block_response` 함수 수정 → 경고 메시지 렌더링

## 서비스별 다음 액션

| 서비스 | 액션 | 우선순위 |
|--------|------|---------|
| Notion | warning impl: generate_notion_block_response 경고 렌더링 수정 | HIGH |
| Gamma | render-generation endpoint 분석 + 추가 차단 패턴 등록 | HIGH |
| Gemini | HAR 캡처 또는 etap debug log로 실제 TLS SNI/API domain 확인 | HIGH |
| GitHub Copilot | SSE block response 전달 방식 수정 (HTTP/2 호환성) | MEDIUM |
| Grok | 수동 테스트 | LOW |
| M365 Copilot | 수동 HAR 캡처 | LOW |
