# Warning Pipeline — Service Status (2026-03-24 updated)

| Service | service_id | Phase | Status | Last updated | Notes |
|---------|-----------|-------|--------|-------------|-------|
| ChatGPT | chatgpt | Done | DONE | 2026-03-17 | Strategy C (HTTP/1.1), SSE warning |
| Claude | claude | Done | DONE | 2026-03-18 | Strategy A (END_STREAM + GOAWAY) |
| Perplexity | perplexity | Done | DONE | 2026-03-17 | SSE stream warning |
| Genspark | genspark | 3 | TESTING | 2026-03-20 | Strategy B, 경고 표시되나 network error artifact 잔존 |
| Gemini | gemini3 | 3 | TEST_FAIL | 2026-03-24 | Test 145: NOT blocked. DB domain(signaler-pa)≠실제 API(gemini.google.com). 미감지. |
| Grok | grok | 3 | EXCLUDED | 2026-03-23 | 자동화 불가 (입력 거부, 인증 필요, cert mismatch). 수동 테스트 필요 |
| GitHub Copilot | github_copilot | 3 | TEST_FAIL | 2026-03-24 | Test 146: blocked=true but warning NOT visible. SSE data 미수신, Thinking... 무한대기. |
| Gamma | gamma | 3 | TEST_FAIL | 2026-03-24 | Test 147: NOT blocked. ai.api.gamma.app 미감지. 모든 요청 200. |
| M365 Copilot | m365_copilot | 3 | EXCLUDED | 2026-03-23 | 자동화 불가 + API endpoint 불확실. 수동 HAR 필요 |
| Notion AI | notion | 3 | TEST_FAIL | 2026-03-24 | Test 148: NOT blocked. block_mode 0→1 수정했으나 미감지. API endpoint 불일치. |

## Test 145-148 결과 요약 (2026-03-24)

### Category 1 — 미감지 (3개)
| 서비스 | DB 등록 domain | 실제 API domain | 진단 |
|--------|---------------|----------------|------|
| Gemini | signaler-pa.clients6.google.com | gemini.google.com | DB domain ≠ 실제 API |
| Gamma | ai.api.gamma.app | gamma.app | 실제 요청이 다른 도메인/경로 사용 |
| Notion | [*.]notion.so /api/v3/ | www.notion.so (etClient, getAssetsJsonV2) | AI chat API 경로가 /api/v3/ 아님 |

### Category 2 — 차단됨 but 경고 안 보임 (1개)
| 서비스 | 증상 | 진단 |
|--------|------|------|
| GitHub Copilot | blocked=true, SSE data 미수신, Thinking... 무한대기 | block response가 SSE 형식으로 전달되지 않거나 connection 차단 |

### 다음 조치
- Gemini: DB domain을 gemini.google.com으로 수정, path를 실제 API 경로로 변경
- Gamma: DevTools에서 실제 프롬프트 API endpoint 확인 필요
- Notion: DevTools에서 실제 AI chat API endpoint 확인 필요
- GitHub Copilot: block response SSE 형식 검증 + HTTP/2 프로토콜 호환성 확인
