# APF Warning Pipeline Status
Updated: 2026-03-26 09:10 KST

## Service Status

| # | Service | Block | Warning | Status | Notes |
|---|---------|-------|---------|--------|-------|
| 1 | ChatGPT | ✅ | ✅ | **DONE** | SSE delta working (Task 008~035) |
| 2 | Claude | ✅ | ✅ | **DONE** | SSE content_block_delta working (Task 008~035) |
| 3 | Perplexity | ✅ | ✅ | **DONE** | SSE working (Task 008~035) |
| 4 | Gemini | ❌ | ❌ | **NOT WORKING** | Task 146: blocked=false, path_patterns 매칭 실패. 차단 자체가 안 됨. |
| 5 | Clova-X | ❓ | ❓ | **UNTESTED** | 경고 테스트 결과 없음 |
| 6 | Notion | ✅ | ❌ | **DEFERRED** | Strike 4. 차단은 되나 다중 엔드포인트 차단 → 프론트엔드 멈춤 |
| 7 | Gamma | ✅ | ❌ | **DEFERRED** | Strike 5. SSE 데이터 전달되나 outline 파서가 텍스트 무시 |
| 8 | Genspark | ✅ | ❌ | **BLOCKED** | Super Agent 3.0 프론트엔드 변경. HAR 재캡처 필요 |
| 9 | Copilot | ✅ | ❌ | **DEFERRED** | Strike 4+. 서버 write 성공, 브라우저 빈 EventStream |
| 10 | Wrtn | ❓ | ❓ | **NOT REGISTERED** | APF에 서비스 미등록. 전체 파이프라인 필요 |

## Summary
- **DONE**: 3/10 (ChatGPT, Claude, Perplexity)
- **NOT WORKING**: 1/10 (Gemini — 차단 자체 실패)
- **UNTESTED**: 1/10 (Clova-X)
- **DEFERRED** (silent block): 3/10 (Notion, Gamma, Copilot)
- **BLOCKED** (HAR 재캡처 필요): 1/10 (Genspark)
- **NOT REGISTERED**: 1/10 (Wrtn)
