## Genspark (genspark) — Implementation Journal

### Service Info
- Domain: www.genspark.ai
- Previous endpoint: POST /api/agent/ask_proxy (SSE)
- Current endpoint: UNKNOWN (프론트엔드 변경됨)
- Framework: Nuxt.js (Vue-based)
- is_http2: 2 (keep-alive), END_STREAM=false, GOAWAY=false

### Current Status: ✅ VERIFIED (2026-04-01)
- ask_proxy SSE 엔드포인트가 사라짐
- "슈퍼 에이전트" UI로 전환됨
- Nuxt.js SSR 또는 서비스워커 기반 통신으로 변경된 것으로 추정
- 기존 generator (generate_genspark_sse_block_response) 무효화됨

### Test #006 (2026-03-26) — 초기 warning test
- 결과: PARTIAL — 차단O, 경고X
- UI: "변경 사항을 적용하려면 새로고침이 필요합니다" 표시
- URL: genspark.ai/agents?type=super_agent&action=init-agent

### Test #025 (2026-03-27) — HAR 캡처
- 결과: FRONTEND_CHANGED
- 576개 네트워크 요청 중 ask_proxy 없음
- SSE 엔드포인트 없음, WebSocket 없음
- 유일한 Genspark API: recommend_next_steps_after_ask (302)
- 서비스워커: Active (workbox-based, SW_CHANNEL_READY)

### 프론트엔드 변경 상세
- 이전: POST ask_proxy → SSE text/event-stream (project_start → message_field_delta → FINISHED)
- 현재: 통신 메커니즘 불명
  - 가능성 1: Nuxt.js useAsyncData/useFetch 내부 데이터 패칭
  - 가능성 2: Service Worker 메시징
  - 가능성 3: SSR (서버사이드 렌더링)

### Re-verification (2026-04-01) — Pipeline Reset, Build 260402
- HTTP/2 strategy: B (keep-alive, is_http2=2)
- Test: #138 check-warning
- Test PC result: warning_displayed=true
- Warning text: "⚠ 민감정보가 포함된 요청은 보안 정책에 의해 차단되었습니다."
- Warning format: Yellow banner with ⚠ icon below user message in chat area
- URL: genspark.ai/agents?id=eec4a736-805d-4a2c-906a-20a25e449383
- Framework: Nuxt.js (Vue-based SSR)
- Console: Rating-related logs only, no errors
- Etap log: block_session service=genspark response_size=1855 is_http2=2, written=1855 expected=1855
- Result: ✅ PASS → VERIFIED
- Note: 프론트엔드 변경 이후에도 기존 generator가 정상 동작. ask_proxy 엔드포인트가 복원되었거나 다른 경로로 매칭된 것으로 추정.

### Previous Issue Resolution
- "프론트엔드 변경으로 인한 FRONTEND_CHANGED" 상태는 해소됨
- 기존 generate_genspark_sse_block_response() 유효
