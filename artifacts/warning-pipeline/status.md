# Warning Pipeline — Service Status (2026-03-25 17:15 updated)

| Service | service_id | Phase | Status | Last updated | Notes |
|---------|-----------|-------|--------|-------------|-------|
| ChatGPT | chatgpt | Done | DONE | 2026-03-17 | Strategy C (HTTP/1.1), SSE warning |
| Claude | claude | Done | DONE | 2026-03-18 | Strategy A (END_STREAM + GOAWAY) |
| Perplexity | perplexity | Done | DONE | 2026-03-17 | SSE stream warning |
| Genspark | genspark | 3 | NEAR_DONE | 2026-03-20 | 경고 표시됨! network error artifact만 잔존. 확인 테스트 필요 |
| Gemini | gemini3 | 3 | EXCLUDED_QUIC | 2026-03-24 | HTTP/3(QUIC) 사용. UDP 443 차단 필요 (네트워크팀) |
| Grok | grok | 3 | EXCLUDED | 2026-03-23 | 자동화 불가. 수동 테스트 필요 |
| GitHub Copilot | github_copilot | 3 | BUILD11_PENDING | 2026-03-25 | Build #11: is_http2=1 (on_disconnected TLS flush). Task 185 대기 |
| Gamma | gamma | 3 | BUILD11_PENDING | 2026-03-25 | Build #11: event:error SSE + empty cards[]. Task 184 대기 |
| M365 Copilot | m365_copilot | 3 | EXCLUDED | 2026-03-23 | 자동화 불가 + API endpoint 불확실 |
| Notion AI | notion | 3 | 3STRIKE_REVIEW | 2026-03-25 | 3회 실패 (Build #6/#8/#9). NDJSON 스키마 불일치. 실제 캡처 필요 (Task 186) |

## Summary
- **DONE**: 3/10 (ChatGPT, Claude, Perplexity)
- **NEAR_DONE**: 1/10 (Genspark — 경고 표시됨, artifact 잔존)
- **BUILD_PENDING**: 2/10 (Gamma, Copilot — Build #11 test PC 결과 대기)
- **3STRIKE_REVIEW**: 1/10 (Notion — 전략 재검토 필요)
- **EXCLUDED**: 3/10 (Gemini/QUIC, Grok/수동, M365 Copilot/수동)

## Build #11 Changes (2026-03-25 15:30)
1. **Gamma**: event:error SSE → error handler 트리거 + 빈 cards[] 로 생성 방지
2. **Copilot**: is_http2=1 (reverted from =2) → on_disconnected TLS flush

## Notion 3-Strike Analysis
- Strike 1 (Build #6): 403 JSON → frontend silently ignored
- Strike 2 (Build #8): 200 NDJSON → API error, body empty (double-write bug)
- Strike 3 (Build #9): 200 NDJSON body 전달됨 (0.7KB) → runInferenceTranscriptApiError (스키마 불일치)
- **필요 조치**: 실제 Notion AI 응답 NDJSON 캡처 (Task 186) 후 스키마 비교/수정
- **대안**: 더 단순한 접근법 검토 (에러 응답으로 Notion 자체 에러 UI 트리거)

## Priority (순차 전략)
1. Genspark 확인 → DONE 전환 (가장 쉬움)
2. Gamma Build #11 결과 → 성공 시 DONE
3. Copilot Build #11 결과 → 성공 시 DONE
4. Notion 전략 재검토 → 실제 NDJSON 캡처 후 진행

## Test PC Status
- **현재: OFFLINE** (ping 192.168.219.150 실패, 2026-03-25 17:10 확인)
- 마지막 결과 수신: ~15:16 (task 183, Build #10 Copilot)
- 약 2시간 무응답
