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

### Iteration 6 (2026-04-22) — h2_end_stream=1 + v4 format (#528, #529)
- DB: h2_end_stream=2→1, h2_mode=2. revision services=125, templates=23.
- 가설: h2_end_stream=1은 DATA+END_STREAM을 즉시 전송 → Chrome이 body를 읽을 수 있음
  + v4 올바른 qianwen SSE 포맷 → 프론트엔드가 경고 문구를 표시
- #520 대비 변경점: 포맷만 다름 (OpenAI→qianwen native SSE). H2 전달 동일.
- #528: **APF_DID_NOT_TRIGGER** — APF 미차단 (50% 비일관성). BUT etap 로그 확인 결과:
  - 19:31:44 차단 발생: `end_stream=1, goaway=0, http1_size=1436`
  - VTS: `written=1414 expected=1414` ✅ + `vts_keepalive` ✅ + `vts_rst_server RST_STREAM to server` ✅
  - **delayed_ES 항목 없음** — h2_end_stream=1에서는 DATA+END_STREAM 동시 전송으로 race condition 제거됨
  - test PC는 DevTools 없이 테스트 → 재시도가 AI 응답 렌더링하여 PASS로 보고
  - H2 전달 측면에서는 성공 (1414B 전달 + END_STREAM on DATA)
- #529: DevTools 필수 지시 + 첫 번째 차단 요청 바이트 확인 지시 — IN PROGRESS

- #529: **NOT_RENDERED** — DevTools: 4회 모두 차단, 4회 모두 0.0 kB + "Failed to load response data"
  - etap VTS: 4회 모두 `written=1414 expected=1414` — SSL_write 성공
  - 그러나 Chrome은 0바이트로 보고. CORS error 동반.
  - **C++ 코드 분석 결론**: `convert_to_http2_response()`에서 `end_stream=true`이면
    `DATA(body,0x00) + DATA(empty,END_STREAM)` 2프레임을 **단일 SSL_write**로 전송.
    VTS 주석: "h2_end_stream=1은 데이터와 END_STREAM이 동시에 도착하여 브라우저가 이벤트를 파싱하지 못함"
  - 결론: h2_end_stream=1도 h2_end_stream=2도 qianwen에서는 실패.

**H2 END_STREAM 3단 비교:**
| h2_end_stream | 동작 | 결과 |
|---|---|---|
| 2 (delayed) | DATA → 10ms → END_STREAM | RST_STREAM 선행 → 0바이트 (#527) |
| 1 (immediate) | DATA + empty_DATA(ES) 동시 | SSE 파서 미실행 → 0바이트 (#529) |
| 0 (none) | DATA만 전송, 스트림 열림 | **미검증** — genspark 성공 패턴 |

### Iteration 7 (2026-04-22) — h2_end_stream=0 (streaming, no END_STREAM) (#530)
- DB: h2_end_stream=1→0, h2_mode=2, h2_goaway=0. etapd reload 19:52:33 confirmed.
- 가설: END_STREAM을 보내지 않으면 브라우저가 SSE를 스트리밍 모드로 파싱.
  스트림은 열린 채 유지 (로딩 인디케이터 표시 가능 — 허용).
  genspark이 이 패턴으로 DONE 달성.
- convert_to_http2_response: end_stream=false → `HEADERS(END_HEADERS) + DATA(body, 0x00)` 단일 전송.
  END_STREAM 없으므로 브라우저가 ReadableStream을 열어둠 → SSE 이벤트 순차 처리.
- #530 check-warning pushed → **결과: FAIL / NOT_RENDERED** — 동일 증상 (4 chat 요청 all 0-byte CORS, `Failed to load response data`).

### 종합 결과 (#529 + #530 후)
- h2_end_stream 값 2/1/0 세 변수 모두 NOT_RENDERED — **END_STREAM flag 단독이 원인 아님**.
- failure_history: qianwen NOT_RENDERED 2/3 strikes (apf-warning-impl 3-strike gate 진입 직전)
- Test PC DevTools 진단 인용 원문: "APF must emit HEADERS frame with :status=200 + valid CORS + content-type"

---

## Code-Review Findings (2026-04-23, cycle 91 — post 12차 session 재개)

Test PC 진단 후 dev PC 측 APF 소스 레벨 검증 수행. 3-strike 진입 전 blind build 금지.

### 1. HEADERS frame emission — C++ 구현 정상
`functions/ai_prompt_filter/ai_prompt_filter.cpp:1274-1496` `convert_to_http2_response()`:
- `:status` — HTTP/1.1 status line 에서 파싱 (L1347-1355). "HTTP/1.1 200 OK" → "200".
- Non-forbidden headers (content-length/transfer-encoding/connection 제외) HPACK literal encoding (L1399-1430).
- HEADERS frame = type 0x01, flags END_HEADERS(0x04) (L1464).
- DATA frame — `h2_end_stream==1` 분기로 2-frame (body + empty ES) or 단일 frame.
- De-chunk (L1319-1343), CRLF/LF separator 양쪽 지원 (L1284-1305).

**결론**: APF H2 frame 생성 경로는 correct. "HEADERS frame missing" 원인 아님.

### 2. Envelope template (`apf-operation/sql/qianwen_native_sse_v2.sql`) — 스펙 준수
```
HTTP/1.1 200 OK
Content-Type: text/event-stream;charset=UTF-8
Cache-Control: no-cache
Access-Control-Allow-Origin: https://qianwen.com
Access-Control-Allow-Credentials: true
Content-Length: 0
\r\n\r\n
data:{sessionId,msgId,msgStatus:"finished",contents:[...]}\n\n
data:[DONE]\n\n
```
- :status=200, Content-Type SSE, CORS origin 명시, credentials true — 스펙 상 correct
- Content-Length 는 H2 변환 시 filter 됨 (L1390)

**결론**: envelope 헤더 구성 correct.

### 3. 재진단 — "HEADERS frame invalid" 은 likely misdiagnosis

실제 symptoms ("Failed to load response data" / "CORS blocked" / 0 bytes) 은 **응답 body 가 browser 에 도달했으나 저장 불가** 을 가리킨다. HEADERS 가 아예 없다면 browser 는 "Stream reset" / "NETWORK_ERROR" 로 표시할 것.

재정립된 root cause 후보 (우선순위 순):

**(a) Origin mismatch** — chat API endpoint 가 `qianwen.com` 이 아닌 subdomain (예: `api.qianwen.com` / `tongyi.aliyun.com`) 에서 동작 시, request Origin 과 hardcoded `Access-Control-Allow-Origin: https://qianwen.com` 불일치 → CORS block.
- **검증**: DevTools Request Headers `Origin:` + `Host:` 확인
- **위험**: 0 (추가 iteration 없이 기존 #529/#530 screenshot 재검토 가능)

**(b) HEADERS frame 중복** — `h2_hold_request=1` 이지만 APF block 판정 전에 upstream HEADERS 가 이미 client 에 전달된 경우, APF 의 block HEADERS 가 same stream_id 로 재발행 → Chrome HTTP/2 COMPRESSION_ERROR.
- **검증**: etap VTS 로그 (`/var/log/etap/etap.log` `[APF:H2_*]`) 에서 upstream vs APF HEADERS 시점 비교
- **위험**: 0 (read-only log 분석)

**(c) VTS frame ordering** — 최근 `etap/core/network_loop.cpp` + `functions/visible_tls/visible_tls_session.cpp` 수정 (d676eb9 "H2 delayed END_STREAM 비블로킹 전환") 관련. APF 생성 HEADERS+DATA 가 VTS SSL_write 시 순서 역전 or 부분 전송.
- **검증**: VTS code audit + tcpdump capture (Dell testbed 필요)
- **위험**: 중 (C9 trigger 영역)

---

## Phase 6 scope 재정의 (cycle 91)

본 서비스는 **apf-warning-impl iteration scope 초과**:
- h2_end_stream 3 변수 모두 실패 → envelope/strategy 단위 수정으론 해결 불가
- 추가 iteration = 3rd strike → SUSPENDED 위험
- 실제 수정은 VTS 레벨 (C9 trigger critical infra change) 또는 envelope 동적 Origin 계산 (non-trivial)

**Status**: `needs_architectural_decision` — pipeline_state 에 반영. 다음 action user gate:
- 옵션 A: etap 로그 분석 (read-only, dev PC 작업) → (b) 확정 시도
- 옵션 B: DevTools Request Headers diagnostic capture (Test PC 1 run-scenario) → (a) 확정
- 옵션 C: qianwen defer + 다른 서비스 전환 (queue 상 전부 blocked 인 문제 별도)
- 옵션 D: VTS 수정 (full discussion-review 필수)

