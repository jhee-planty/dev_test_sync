# APF Warning Implementation — Service Status (2026-04-02 18:20 KST)

## Summary

| Service | Status | Block | Warning | Notes |
|---------|--------|-------|---------|-------|
| ChatGPT | PASS | ✅ | ✅ | SSE 기반, 안정적 |
| Perplexity | PASS | ✅ | ✅ | SSE 기반, 안정적 |
| Genspark | PASS | ✅ | ✅ | SSE 기반, 안정적 |
| Grok | PASS | ✅ | ✅ | SSE 기반, 안정적 |
| Gamma | PASS | ✅ | ✅ | SSE 기반, 안정적 |
| Gemini | IN_PROGRESS | ✅ | ❓ | server-only shutdown 적용, block+서버차단 확인, 브라우저 결과 대기 |
| GitHub Copilot | PARTIAL_PASS | ✅ | ❌ | block 작동, generic error 표시 (custom warning 미표시) |
| M365 Copilot | EXCLUDED | ❌ | ❌ | WebSocket 기반 — APF 인터셉션 불가 |
| Notion AI | EXCLUDED | ❌ | ❌ | WebSocket 기반 — APF 인터셉션 불가 |

## Detailed Status

### Gemini (gemini3) — IN_PROGRESS
- **DB**: domain=gemini.google.com, path=/, enabled=true
- **Code**: is_http2=2 (server-only shutdown), generate_gemini_block_response (wrb.fr format)
- **Iteration 10** (2026-04-02):
  - Test #181: block 전송됐지만 서버 응답이 덮어씀 → 브라우저에 AI 응답 렌더링
  - **근본 원인**: is_http2=2가 서버 연결 유지 → 서버 응답 통과 → block response 덮어쓰기
  - **수정**: server-only shutdown (서버 연결만 종료, 클라이언트 유지)
    - `_sub_sside_disconnected = 1` 선설정으로 cascade 방지
    - `_sproxy.shut_down(false)` → 서버 연결 종료
  - 배포 17:47 KST
  - **etap log 확인** (Test #182): 3회 block 모두 정상
    - `vts_sside_only: server-side shutdown, client kept alive` ✅
    - block → session close: 6초 간격 (정상 패턴)
  - **대기**: Test #182 브라우저 결과
- **Risk**: H2 stream에서 서버 HEADERS가 block HEADERS보다 먼저 도달하면 중복 → 같은 ms 내 처리되어 가능성 낮음

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
4. **Server response overwrite** (신규): is_http2=2가 서버 연결 유지 → 서버 응답이 block response 덮어씀 → server-only shutdown으로 수정

## Deployment History (2026-04-02)
- 16:39 — gemini3 path=/, is_http2=1 (코드 미반영)
- 17:15 — gemini3 is_http2=2 정상 반영
- 17:27 — path_matcher regex 버그 수정 추가 배포
- 17:47 — **server-only shutdown** 적용 (visible_tls_session.cpp: is_http2=2 → 서버만 종료)
