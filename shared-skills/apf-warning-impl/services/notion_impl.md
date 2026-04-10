## Notion AI (notion) — Implementation Journal

### Service Info
- Domain: www.notion.so (API), msgstore-001.www.notion.so (WebSocket)
- AI Chat URL: https://www.notion.so/chat
- Protocol: **WebSocket (primus-v8, Engine.IO v4)** — HTTP API 없음
- is_http2: 2 (keep-alive)

### Current Status: ❌ INFRA — WEBSOCKET_BASED
- AI 통신이 WebSocket 전용 — HTTP 응답 주입 방식으로는 경고 불가
- 표준 H2 차단 방식(SSE/JSON 응답) 적용 불가
- 아키텍처 레벨의 접근 변경 필요

### Test #005 (2026-03-26) — 초기 warning test
- 결과: PARTIAL — 차단O (빈 화면), 경고X
- DB template fallback으로 차단은 되지만 경고 텍스트 전달 불가

### Iteration 1 (2026-03-23) — Test 137
- DB: domain=[*.]notion.so, path=/api/v3/
- 결과: NOT_BLOCKED (detect 0건)
- 진단: AI chat traffic이 WebSocket 기반 → HTTP detect 안 됨

### Test #026 (2026-03-27) — HAR 캡처 확인
- 결과: WEBSOCKET_BASED
- AI 통신 흐름:
  1. WebSocket 연결 (wss://msgstore-001.www.notion.so/primus-v8/)
  2. 프롬프트 → 기존 WebSocket으로 전송
  3. AI 응답 → 기존 WebSocket으로 수신
  4. syncRecordValuesSpaceInitial → 응답 후 상태 동기화 (CRDT)
- 별도 HTTP AI API 엔드포인트 없음
- WebSocket은 페이지 로드 시 설립, 프롬프트당 새 연결 없음

### 경고 전달 가능성 분석
1. **WebSocket 프레임 수정**: DIFFICULT — 바이너리/텍스트 프레임 인터셉션 필요
2. **WebSocket 업그레이드 차단**: 가능 — HTTP 101 대신 에러 응답 반환
   - 단, Notion의 모든 실시간 기능이 중단됨 (협업 포함)
3. **syncRecordValuesSpaceInitial 주입**: record sync에 경고 삽입
   - chat flow와 직접 연관 없어 효과 미지수
4. **도메인 레벨 차단**: msgstore-001.www.notion.so 차단
   - 전체 실시간 기능 중단 (과도한 사이드이펙트)

### Architectural Decision Needed
- WebSocket 기반 서비스에 대한 APF 아키텍처 확장이 필요
- 현재 APF는 HTTP 요청/응답만 처리 가능
- Option A: WebSocket 프레임 인터셉션 기능 추가 (대규모 개발)
- Option B: PARTIAL 상태로 유지 (차단만, 경고 없음)
- Option C: 도메인 레벨 차단으로 전환 (사이드이펙트 있음)

### BLOCKED_ONLY 공식 판정 (2026-04-01)

**구조적 한계 요약:**
1. AI 통신이 WebSocket 전용 — HTTP 응답 주입 불가
2. NDJSON 시도 (#100-103): fake UUID → syncRecordValue 타임아웃
3. WebSocket 프레임 인터셉션은 APF 아키텍처 범위 밖

**VERDICT (수정됨, 2026-04-10):** ~~BLOCKED_ONLY~~ → **NEEDS_ALTERNATIVE**
- 도메인 레벨 차단으로 AI 요청 자체는 방지 가능 (blocked=1)
- 경고 텍스트 전달은 WebSocket 아키텍처 제약으로 불가
- Escalation ②③ 또는 WebSocket 프레임 인터셉션 필요

### 대안 접근법 (2026-04-10)
WebSocket 기반 서비스 — `apf-technical-limitations.md` §1 참조:
1. HTTP Upgrade 응답 단계 인터셉트 (101 대신 403 + 경고 HTML)
2. 초기 페이지 로드 시 경고 페이지 주입 (Accept: text/html)
3. WS 프레임 레벨 인젝션 (APF 기능 확장 시)
4. REST API 병행 차단 (초기화 단계)
5. DNS/리다이렉트 방식
