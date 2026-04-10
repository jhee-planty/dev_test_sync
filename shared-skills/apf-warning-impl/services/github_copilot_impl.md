## GitHub Copilot (github_copilot) — Implementation Journal

### Iteration 1 (2026-03-23) — Test 135
- DB: domain=api.individual.githubcopilot.com, path=/github/chat
- Test result: blocked=true, warning_visible=false
- Observations:
  - Prompt '한글날' submitted successfully
  - API POST to /github/chat/threads/.../messages returned 200 (1.3kB)
  - SSE stream opened but data never arrived → stuck on "Thinking..." for 25+ seconds
  - Proxy allows initial SSE connection but blocks/strips streaming data
  - Model: Claude Haiku 4.5
  - Console: only NavigatorClientEntry warning (unrelated)
- 진단: block response가 SSE 형식이 아니거나 stream을 끊는 방식에 문제
  - 3/20 etap log: HTTP/1.1 403 Forbidden for HTTP/2 connection → protocol mismatch 의심
  - Generator code 검증 필요
- Re-test: 140_check-warning.json (systemctl 재시작 후)

### Service Info (Updated)
- API Endpoint: POST api.individual.githubcopilot.com/github/chat/threads/{thread_id}/messages
- Protocol: H2, SSE (text/event-stream)
- SSE Events: message_delta → message_end → data: [DONE]
- is_http2: 2 (keep-alive)

### Test #007 (2026-03-26) — 초기 warning test
- 결과: PARTIAL — 차단O, Thinking 무한대기
- 원인: is_http2=1 (disconnect after write) → H2 연결 즉시 끊김

### Test #022 (2026-03-27) — 로그인 재테스트
- 결과: BLOCKED_BY_LOGIN — 시크릿 모드에서 GitHub 로그인 필요

### Test #024 (2026-03-27) — 일반 모드 재테스트
- 결과: NOT_BLOCKED — 민감 프롬프트 미사용 ("Hello, how are you?")

### Test #028 (2026-03-27) — 민감 프롬프트 재테스트
- 결과: WARNING_PARTIALLY_DELIVERED
- SSE 이벤트 2건 수신 (EventStream 탭에서 확인)
- 경고 텍스트: "민감정보가 포함된 요청은 보..."
- ERR_CONNECTION_CLOSED → Copilot UI에 generic error 표시
- 원인: END_STREAM=false 상태에서 연결 종료 → 에러 처리

### Test #030 (2026-03-27) — Build #17 [DONE] 시그널 추가
- 변경: data: [DONE]\n\n SSE 종료 시그널 추가
- 결과: WARNING_PARTIALLY_DELIVERED
- SSE 이벤트 3건 (message_delta + message_end + [DONE])
- 에러: ERR_CONNECTION_CLOSED → ERR_HTTP2_PROTOCOL_ERROR로 변경
- [DONE] 수신되지만 END_STREAM=false → H2 스트림 정상 종료 안 됨
- UI: 여전히 generic error

### Test #032 (2026-03-27) — Build #18 END_STREAM=true
- 변경: END_STREAM=true 복원
- 결과: WARNING_NOT_DELIVERED — 0건, 에러 없음, 13ms
- END_STREAM=true → Chrome이 이벤트 파싱 전에 스트림 종료

### Test #034 (2026-03-27) — Build #19 END_STREAM=false + GOAWAY=true
- 변경: GOAWAY 추가로 프로토콜 에러 방지 시도
- 결과: WARNING_NOT_DELIVERED — 3건 수신, ERR_HTTP2_PROTOCOL_ERROR
- GOAWAY가 프로토콜 에러를 방지하지 못함

### Test #036 (2026-03-27) — Build #20 2-frame DATA
- 변경: DATA(body,END_STREAM=0) + DATA(empty,END_STREAM=1) + GOAWAY
- 결과: WARNING_NOT_DELIVERED — 0건, 에러 없음, 6ms
- 2-frame DATA로 프로토콜 에러 해소, 하지만 이벤트도 미수신

### Current Status: 🔶 ARCHITECTURAL_LIMIT
- 차단O, 경고X, 에러X (Build #20 - 깨끗한 차단)
- END_STREAM=false만 이벤트 수신 가능하지만 항상 프로토콜 에러 동반
- END_STREAM=true(단일/2-frame)는 에러 없지만 이벤트 미수신
- 근본 원인: Etap이 H2 응답을 단일 write()로 전송 → Chrome이 모든 프레임을 한번에 처리
- 해결: "지연된 END_STREAM" 필요 (DATA frame 후 100ms 대기 → END_STREAM frame)
- Etap 아키텍처 변경 필요: 비동기 분할 write 지원

### H2 Configuration History (Full)
```
Build #15: is_http2=2, END_STREAM=false, GOAWAY=false → 무한대기 해결
Build #17: + [DONE] signal → 3건 수신, ERR_HTTP2_PROTOCOL_ERROR
Build #18: END_STREAM=true → 0건, 에러 없음 (13ms)
Build #19: END_STREAM=false + GOAWAY=true → 3건, PROTOCOL_ERROR
Build #20: 2-frame DATA + GOAWAY → 0건, 에러 없음 (6ms, 깨끗한 차단)
```

### Production Config (Build #20)
- is_http2=2, END_STREAM=true (2-frame DATA), GOAWAY=true
- 결과: 깨끗한 차단 (에러 없음, 경고 없음, generic error 표시)


### Iteration 7 (2026-03-27) — Test #040 (Build #21 REAL deploy)
- 변경: SSE → JSON error response (422 Unprocessable Entity + JSON body)
- Generator: `generate_github_copilot_sse_block_response()` → JSON error body
- H2 설정: is_http2=2, END_STREAM=true (2-frame DATA), GOAWAY=true
- 이전 #038은 Build #20 바이너리로 실행됨 (배포 실패). #040이 실제 Build #21 테스트.
- 결과: **PARTIAL_PASS** ✅
  - 422 Unprocessable Content 확인!
  - JSON body에 경고 텍스트 전달됨: "⚠️ 민감정보가 포함된 요청은 보안 정책에 의해 차단되었습니다."
  - Console: `POST ...messages? 422 (Unprocessable Content)`
  - **BUT**: Copilot UI는 generic error 표시 ("I'm sorry but there was an error. Please try again.")
  - 프론트엔드가 422를 catch하고 자체 fallback error를 표시 → 커스텀 경고 텍스트 미노출
- 결론: 네트워크 레벨에서 422 + JSON error body 전달 성공. 차단은 완벽 동작.
  경고 텍스트 표시를 위해서는 JS injection 등 프론트엔드 개입 필요.
  현재 상태는 "차단 + generic error" — 사용자에게 에러는 보이지만 APF 경고 문구는 미표시.

### Production Config (Build #21)
- is_http2=2, END_STREAM=true (2-frame DATA), GOAWAY=true
- Generator: JSON error 422 + `{"error":{"message":"...","type":"policy_violation","code":"content_filter"}}`
- 결과: 차단 성공 + generic error 표시 (PARTIAL_PASS)
### BLOCKED_ONLY 공식 판정 (2026-04-01)

**구조적 한계 요약:**
1. SSE: END_STREAM=false만 이벤트 수신 가능하지만 항상 ERR_HTTP2_PROTOCOL_ERROR 동반
2. SSE: END_STREAM=true는 에러 없지만 이벤트 미수신 (Chrome이 파싱 전 스트림 종료)
3. JSON error (422/403): 프론트엔드가 catch하여 generic error 표시 ("Please try again")
4. 근본 원인: Etap 단일 write() + SPA fetch error handler

**VERDICT (수정됨, 2026-04-10):** ~~BLOCKED_ONLY~~ → **NEEDS_ALTERNATIVE**
- 차단 정상 동작 (blocked=1 + generic error UI)
- 커스텀 경고 텍스트 표시 불가
- Escalation ②③ (JS injection) 또는 Etap H2 비동기 분할 write 필요

### 대안 접근법 (2026-04-10)
1. 페이지 로드 인터셉트 (SPA이므로 Accept: text/html → 경고 HTML)
2. REST API 단계 차단 (초기화/인증 API에서 경고 반환)
