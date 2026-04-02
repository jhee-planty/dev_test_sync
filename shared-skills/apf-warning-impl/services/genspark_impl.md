## Genspark (genspark) — Implementation Journal

### Service Info
- Domain: www.genspark.ai
- Previous endpoint: POST /api/agent/ask_proxy (SSE)
- Current endpoint: UNKNOWN (프론트엔드 변경됨)
- Framework: Nuxt.js (Vue-based)
- is_http2: 2 (keep-alive), END_STREAM=false, GOAWAY=false

### Current Status: ❌ INFRA — FRONTEND_CHANGED
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

### Next Steps
- fetch/XHR 인터셉션으로 실제 통신 메커니즘 확인 필요
- Chrome DevTools Application 탭에서 Service Worker 메시지 확인
- 또는 Nuxt.js _payload 응답에서 데이터 전달 방식 확인
- ★ 기존 generator 코드는 유지하되, 새 프론트엔드에 맞는 접근 필요
