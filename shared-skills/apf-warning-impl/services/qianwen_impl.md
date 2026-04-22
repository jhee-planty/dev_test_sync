# qianwen — Implementation Journal

## Service Info
- service_name: qianwen
- domains: tongyi.ai, *.tongyi.ai, chat2.qianwen.com, qianwen.com, *.qianwen.com, tongyi.aliyun.com, *.tongyi.aliyun.com
- response_type: qianwen_sse (dedicated template, native format)
- envelope: SSE (data:{sessionId:...,msgId:...,contents:[{contentType:"text",content:...}],msgStatus:"finished"})
- Prior classification: BLOCK_ONLY → testing (2026-04-20) → active iteration (2026-04-22)

## DB State (2026-04-22 current, revision 124/23)
- h2_mode=2, h2_end_stream=2, h2_goaway=0, h2_hold_request=1, block_mode=1
- response_type=qianwen_sse (dedicated, 1148B — v4, Content-Length removed)
- CORS: Access-Control-Allow-Origin: https://qianwen.com + Access-Control-Allow-Credentials: true
- Template format: qianwen ACTUAL web frontend format (multi_load/iframe, audit_info, event:complete)
- http_response: 159 bytes (warning text with emoji)
- etapd reload confirmed: 17:59:56 + 18:03:12

## Classification Review (2026-04-20)

status.md classified qianwen as BLOCK_ONLY with "DB변경 불가(❌)" — this is INCORRECT.
- DB has valid response template (openai_compat_sse, 342B envelope)
- CORS header already present in envelope
- The ERR_HTTP2 component may be caused by h2_end_stream=1 (immediate END_STREAM)
- h2_end_stream=2 (deepseek success pattern) has not been tried

Reclassifying: BLOCK_ONLY → testing (h2_end_stream=2 trial)

---

### Iteration 1 (2026-04-20) — h2_hold_request fix
- Problem: h2_hold_request=0 → ERR_HTTP2_PROTOCOL_ERROR (dual HEADERS on same stream)
- Fix: h2_hold_request=1 via DB
- Result: #516 safe prompt SUCCESS ✅. ERR_HTTP2 resolved.

### Iteration 2 (2026-04-22) — h2_mode/GOAWAY trials (#517-#520)
- #517: h2_mode=2, h2_end_stream=2 → NOT_RENDERED (차단O, 경고미표시)
- #518: run-scenario → FAIL (재시도 우회, AI 답변 렌더링됨)
- #519: h2_mode=1, h2_goaway=1 → PARTIAL (재시도 차단O, 경고 미표시 — GOAWAY kills connection before envelope delivered)
- #520: h2_mode=2, h2_end_stream=1 → FAIL (envelope bytes sent but parser rejects non-schema content)
- Root cause identified: OpenAI format (choices/delta) ≠ qianwen native format (sessionId/msgId/contents/msgStatus)

### Iteration 3a (2026-04-22) — v2 template from qwen-free-api (#522) — SUPERSEDED
- Template: qianwen native format reverse-engineered from qwen-free-api (DashScope API)
  - `data:{"sessionId":"..","msgId":"..","msgStatus":"finished","contents":[...]}`
- **Problem discovered**: qwen-free-api is DashScope backend API, NOT the web frontend API
- #522 expected to fail — wrong format basis

### Iteration 3b (2026-04-22) — v3 template from ACTUAL capture (#523) — IN PROGRESS
- #521 run-scenario captured ACTUAL qianwen web SSE response (2.3MB, 45 events)
- Key discovery: web frontend uses completely different schema:
  - `mime_type: "multi_load/iframe"` (content field identifier)
  - `audit_info: {problem_code: "blocked", error_code: 1}` (block signal)
  - `event:complete` prefix on final event (NOT `data:[DONE]`)
  - `communication: {disconnection_signal: 1}` (stream termination)
  - Content is CUMULATIVE (full text each event, not delta)
- v3 template (1167B): two SSE events — initial data + event:complete final
- DB: revision_cnt services=122, templates=22. etapd reload confirmed 17:59+18:03
- h2_end_stream=2, h2_mode=2, CORS https://qianwen.com + credentials
- #522: APF_DID_NOT_TRIGGER (prompt didn't match — likely timing issue during DB reload)
- #523: PARTIAL/NOT_RENDERED — APF blocked ✅, envelope sent (1405B H2) ✅, but browser showed native error "消息生成失败" instead of warning text
- Root cause: `Content-Length: 0` in HTTP headers told browser body is empty → SSE events never parsed

### Iteration 3c (2026-04-22) — v4 template: Content-Length removed (#524, #525)
- Fix: Removed `Content-Length: 0` header from template (SSE streaming should have no Content-Length)
- Template size: 1167B → 1148B (v4)
- DB revision templates=23, etapd reload confirmed at 18:20:25
- #524: **FAIL / APF_DID_NOT_TRIGGER** — APF가 프롬프트를 차단하지 않음. qianwen이 AI 응답 전체 스트리밍 (주민등록번호 18자리 형식 상세 설명)
- ⚠️ APF 트리거 비일관성: #522 pass → #523 block → #524 pass. 동일 프롬프트 3회 중 1회만 차단
- 가능 원인: (a) DB reload 타이밍, (b) APF rate/session 기반 필터링, (c) 세션별 상태 추적, (d) CDN 에지 노드 차이
- #525: **PARTIAL / NOT_RENDERED** — APF 차단 ✅, 하지만 "消息生成失败" 표시 (same as #523). Content-Length 제거(v4)는 효과 없음.
- 근본 원인 재분석: `net::ERR_FAILED` → h2_mode=2 (RST_STREAM)가 브라우저를 연결 실패로 처리
- APF 트리거 비일관성 확인: #522 pass / #523 block / #524 pass / #525 block (50% 차단율)

### Iteration 4 (2026-04-22) — v5: h2_mode=0 (RST_STREAM disabled, #526)
- DB change: h2_mode=2→0 (RST_STREAM 비활성화). END_STREAM(delayed 10ms)만으로 스트림 종료.
- revision services=123, templates=23. etapd reload 18:56:22 confirmed.
- 가설: RST_STREAM이 SSE body 파싱 전에 도착하여 브라우저가 전체 응답을 ERR_FAILED로 처리.
  h2_mode=0은 RST_STREAM을 보내지 않으므로 브라우저가 SSE body를 정상 파싱할 수 있음.
- 참고: deepseek는 h2_mode=2로 성공 — 프론트엔드 구현 차이 (fetch library / error handling)
- #526: **PARTIAL / NOT_RENDERED** — h2_mode=0도 동일 결과 (消息生成失败)
- ⚠️ C++ 코드 분석 결과 h2_mode=0은 RST_STREAM 비활성화가 아님!
  - h2_mode=0: HTTP/1.1 양방향 종료 (전체 TCP 연결 끊김 — 오히려 나쁨)
  - h2_mode=1: H2 cascade shutdown + on_disconnected()
  - h2_mode=2: H2 RST_STREAM (해당 스트림만 종료 — 가장 부드러움)
- h2_mode=2로 원복 (revision 124)
- 결론: H2 종료 방식이 문제가 아님. 3가지 모두 NOT_RENDERED.

### Iteration 5 (2026-04-22) — DevTools 진단 (#527) ✅ ROOT CAUSE FOUND
- #527 DevTools Network 캡처 결과:
  - **Chrome이 APF 차단 요청에서 0바이트 수신** (size: 0.0 kB)
  - Response 탭: "Failed to load response data - No data found for resource with given identifier"
  - 두 번째 요청(재시도)은 APF를 우회하여 정상 AI 응답 수신 (32.2 kB)
- **근본 원인**: h2_end_stream=2 (10ms 지연 END_STREAM)에서 RST_STREAM이 DATA 프레임보다 먼저 도착
  → Chrome이 응답 전체를 파기 → 0바이트 → fetch() 실패 → "消息生成失败" 표시
- **핵심 증거**: #520(h2_end_stream=1)은 "envelope bytes sent but parser rejects" → 바이트가 전달됨!
  h2_end_stream=1은 DATA 프레임에 END_STREAM 포함 → RST_STREAM 전에 응답 완료

### Iteration 6 (2026-04-22) — h2_end_stream=1 + v4 format (#528) — IN PROGRESS
- DB: h2_end_stream=2→1, h2_mode=2. revision services=125, templates=23.
- 가설: h2_end_stream=1은 DATA+END_STREAM을 즉시 전송 → Chrome이 body를 읽을 수 있음
  + v4 올바른 qianwen SSE 포맷 → 프론트엔드가 경고 문구를 표시
- #520 대비 변경점: 포맷만 다름 (OpenAI→qianwen native SSE). H2 전달 동일.
- #528 check-warning pushed
