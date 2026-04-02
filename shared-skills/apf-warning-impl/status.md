# APF Warning Implementation — Service Status (2026-04-02)

## Summary

| Service | Status | Block | Warning | Notes |
|---------|--------|-------|---------|-------|
| ChatGPT | PASS | ✅ | ✅ | SSE 기반, 안정적 |
| Perplexity | PASS | ✅ | ✅ | SSE 기반, 안정적 |
| Genspark | PASS | ✅ | ✅ | SSE 기반, 안정적 |
| Grok | PASS | ✅ | ✅ | SSE 기반, 안정적 |
| Gamma | PASS | ✅ | ✅ | SSE 기반, 안정적 |
| Gemini | IN_PROGRESS | ⚠️ | ❌ | block 발동 확인, is_http2=2 배포, 브라우저 경고 미확인 |
| GitHub Copilot | PARTIAL_PASS | ✅ | ❌ | block 작동, generic error 표시 (custom warning 미표시) |
| M365 Copilot | EXCLUDED | ❌ | ❌ | WebSocket 기반 — APF 인터셉션 불가 |
| Notion AI | EXCLUDED | ❌ | ❌ | WebSocket 기반 — APF 인터셉션 불가 |

## Detailed Status

### Gemini (gemini3) — IN_PROGRESS
- **DB**: domain=gemini.google.com, path=/, enabled=true
- **Code**: is_http2=2 (cascade disconnect 방지), generate_gemini_block_response (wrb.fr format)
- **Iteration 8** (2026-04-02):
  - path_matcher regex 버그 발견 및 수정 (`escape_regex()`에 `*` 추가)
  - catch-all path=/ 사용 (regex 버그 우회)
  - is_http2=2 재배포 완료 (17:15)
  - etap log: block 발동 + is_http2=2 확인 (vts_pre log)
  - **대기**: Test #181 브라우저 결과
- **Risk**: 서버가 이미 HEADERS를 보냈으면 중복 HEADERS → ERR_HTTP2_PROTOCOL_ERROR

### GitHub Copilot — PARTIAL_PASS
- block 작동, 403 Forbidden JSON 전달됨
- 프론트엔드가 generic error 표시 (custom warning 미표시)
- 원인: Etap이 H2 HEADERS+DATA를 single write()로 전송 → Chrome이 한번에 처리
- 해결 방향: delayed END_STREAM 또는 response injection

### M365 Copilot — EXCLUDED
- WebSocket(wss://copilot.microsoft.com/c/api/chat) 기반 채팅
- APF는 HTTP request body만 검사 가능, WebSocket 프레임 불가
- 향후: WebSocket 인터셉션 기능 추가 필요

### Notion AI — EXCLUDED
- WebSocket(primus-v8, Engine.IO v4) 기반 AI chat
- HTTP `/api/v3/runInferenceTranscript` 존재하지만 주 채팅은 WebSocket
- 향후: WebSocket 지원 시 재검토

## Bug Fixes Applied (2026-04-02)
1. **CT caching bug**: H2 멀티플렉싱에서 Content-Type 캐싱 오염 수정
2. **path_matcher regex bug**: `escape_regex()`가 `*`를 이스케이프하지 않아 와일드카드 패턴 실패 → `*` 추가로 수정
3. **is_http2 code-build mismatch**: 소스 변경 후 빌드 미반영 → 재배포

## Deployment History (2026-04-02)
- 16:39 — gemini3 path=/, is_http2=1 (코드 미반영)
- 17:15 — gemini3 is_http2=2 정상 반영
- 17:27 — path_matcher regex 버그 수정 추가 배포
