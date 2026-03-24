# Warning Pipeline — Service Status

| Service | service_id | Phase | Status | Last updated | Notes |
|---------|-----------|-------|--------|-------------|-------|
| ChatGPT | chatgpt | Done | DONE | 2026-03-17 | Strategy C (HTTP/1.1), SSE warning |
| Claude | claude | Done | DONE | 2026-03-18 | Strategy A (END_STREAM + GOAWAY) |
| Perplexity | perplexity | Done | DONE | 2026-03-17 | SSE stream warning |
| Genspark | genspark | 3 | TESTING | 2026-03-20 | Strategy B, 경고 표시되나 network error artifact 잔존 |
| Gemini | gemini3 | 3 | RE-TESTING | 2026-03-23 | DB 수정 완료, systemctl 재시작 후 re-test 138 대기 |
| Grok | grok | 3 | EXCLUDED | 2026-03-23 | 자동화 불가 (입력 거부, 인증 필요, cert mismatch). 수동 테스트 필요 |
| GitHub Copilot | github_copilot | 3 | TEST_FAIL | 2026-03-23 | blocked=true, warning 미표시 (SSE stuck). Re-test 140 대기 |
| Gamma | gamma | 3 | PENDING | 2026-03-23 | 134 결과 미도착. cert error 가능성 |
| M365 Copilot | m365_copilot | 3 | EXCLUDED | 2026-03-23 | 자동화 불가 + API endpoint 불확실. 수동 HAR 필요 |
| Notion AI | notion | 3 | TEST_FAIL | 2026-03-23 | 미차단. detect 0건. WebSocket 우회 또는 API endpoint 불일치. Re-test 141 대기 |

## Infrastructure Note (2026-03-23)
- 08:20 runetap 재시작 → DPDK init 실패 → 전체 TLS 인터셉션 중단
- 10:05 systemctl restart → DPDK 정상 초기화, detect 복구 (10:07:09)
- 138-141 재테스트 진행 중
