# Warning Pipeline — Service Status (2026-03-24 12:50 updated)

| Service | service_id | Phase | Status | Last updated | Notes |
|---------|-----------|-------|--------|-------------|-------|
| ChatGPT | chatgpt | Done | DONE | 2026-03-17 | Strategy C (HTTP/1.1), SSE warning |
| Claude | claude | Done | DONE | 2026-03-18 | Strategy A (END_STREAM + GOAWAY) |
| Perplexity | perplexity | Done | DONE | 2026-03-17 | SSE stream warning |
| Genspark | genspark | 3 | TESTING | 2026-03-20 | Strategy B, 경고 표시되나 network error artifact 잔존 |
| Gemini | gemini3 | 3 | QUIC_BYPASS | 2026-03-24 | HTTP/3(QUIC) 사용으로 TLS 인터셉션 불가. UDP 443 차단 필요 |
| Grok | grok | 3 | EXCLUDED | 2026-03-23 | 자동화 불가. 수동 테스트 필요 |
| GitHub Copilot | github_copilot | 3 | TEST_FAIL | 2026-03-24 | blocked=true but warning NOT visible. SSE stuck |
| Gamma | gamma | 3 | PARTIAL_BLOCK | 2026-03-24 | /graphql BLOCKED but render-generation 통과. 다중API 구조 |
| M365 Copilot | m365_copilot | 3 | EXCLUDED | 2026-03-23 | 자동화 불가 + API endpoint 불확실 |
| Notion AI | notion | 3 | TESTING | 2026-03-24 | BLOCKED 확인! NDJSON block response 배포완료, 경고표시 테스트 대기(req 157) |

## Gemini QUIC 분석 (2026-03-24)

etap log 분석 결과 `gemini.google.com` TLS 트래픽이 **전혀 인터셉트되지 않음**.
재시작 전: signaler-pa.clients6.google.com만 detect (구 DB 패턴)
재시작 후 (12:15, 12:43): gemini detect 0건

**진단**: Gemini은 HTTP/3 (QUIC, UDP 443) 사용. etap은 TCP 기반 TLS만 인터셉트.
**해결 방안**: 방화벽에서 gemini.google.com 대상 UDP 443 차단 → 브라우저 HTTP/2 폴백 → etap 인터셉션 가능

## Notion NDJSON Fix (2026-03-24 12:43 배포)

기존: `HTTP/1.1 403 + JSON error` → `runInferenceTranscriptApiError` → 빈 화면
수정: `HTTP/1.1 200 OK + NDJSON {"type":"success","completion":"경고텍스트"}` → 정상 AI 응답으로 렌더링 예상
테스트: req 157 대기 중 (test PC worker 재시작 필요)

## Gamma 부분 차단 분석

etap log: `BLOCKED, /graphql, gamma.app` (CreateDocGeneration mutation, SSN 감지)
그러나 render-generation (201) 별도 경로로 콘텐츠 생성 완료
→ Gamma의 다중 API 아키텍처: graphql → generation → render-generation
→ graphql만 차단해도 불완전. 모든 generation 경로 차단 필요

## 다음 액션

| 서비스 | 액션 | 상태 |
|--------|------|------|
| Notion | req 157 결과 확인 (NDJSON 경고 표시) | test PC 대기 |
| Gemini | UDP 443 차단 정책 적용 요청 (네트워크팀) | 사용자 판단 필요 |
| Gamma | render-generation 도메인 확인 + 추가 차단 패턴 | 분석 필요 |
| GitHub Copilot | SSE block response 수정 | 코드 수정 필요 |
