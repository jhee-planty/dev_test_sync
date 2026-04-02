# APF Warning Implementation — Service Status (2026-04-02 19:05 KST)

## Summary

| Service | Status | Block | Warning | Notes |
|---------|--------|-------|---------|-------|
| ChatGPT | PASS | ✅ | ✅ | SSE 기반, 안정적 |
| Perplexity | PASS | ✅ | ✅ | SSE 기반, 안정적 |
| Genspark | PASS | ✅ | ✅ | SSE 기반, 안정적 |
| Grok | PASS | ✅ | ✅ | SSE 기반, 안정적 |
| Gamma | PASS | ✅ | ✅ | SSE 기반, 안정적 |
| Gemini | IN_PROGRESS | ✅ | ❓ | keep-alive + RST_STREAM (Phase3-B12) 배포, Test #184 대기 |
| GitHub Copilot | PARTIAL_PASS | ✅ | ❌ | block 작동, generic error 표시 (custom warning 미표시) |
| M365 Copilot | EXCLUDED | ❌ | ❌ | WebSocket 기반 — APF 인터셉션 불가 |
| Notion AI | EXCLUDED | ❌ | ❌ | WebSocket 기반 — APF 인터셉션 불가 |

## Detailed Status

### Gemini (gemini3) — IN_PROGRESS
- **DB**: domain=gemini.google.com, path=/, enabled=true
- **Code**: is_http2=2 (keep-alive + RST_STREAM), generate_gemini_block_response (wrb.fr format)
- **Phase3 이력**:
  - B10: server-only shutdown → ERR_CONNECTION_CLOSED (#182: blocked=true, warning_visible=false)
  - B11: keep-alive → 서버 응답이 END_STREAM 후 도착 → H2 프로토콜 오류 (#183: HTTP status 0)
  - **B12 (현재)**: keep-alive + RST_STREAM(CANCEL) to server
    - 서버에 RST_STREAM 전송하여 차단된 스트림 취소
    - 다른 스트림은 영향 없음
    - 배포 18:58 KST
    - Test #184 대기 중 (테스트 PC 비활성)

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
4. **Server response overwrite**: is_http2=2 서버 연결 유지 → 서버 응답 덮어쓰기 → server-only shutdown
5. **H2 protocol error on keep-alive** (신규): 후속 패킷이 서버에 포워딩 → 서버 응답이 END_STREAM 후 도착 → RST_STREAM으로 수정

## Deployment History (2026-04-02)
- 16:39 — gemini3 path=/, is_http2=1 (코드 미반영)
- 17:15 — gemini3 is_http2=2 정상 반영
- 17:27 — path_matcher regex 버그 수정 추가 배포
- 17:47 — server-only shutdown 적용 (Phase3-B10)
- 18:33 — keep-alive 복원 (Phase3-B11)
- 18:58 — **keep-alive + RST_STREAM** 적용 (Phase3-B12)
