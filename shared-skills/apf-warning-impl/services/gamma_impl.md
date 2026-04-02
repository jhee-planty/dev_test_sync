## Gamma (gamma) — Implementation Journal

### Service Info
- Domain: ai.api.gamma.app
- Path: /ai/v2/
- Endpoint: POST ai.api.gamma.app/ai/v2/generation (outline SSE)
- Protocol: H2, SSE (EventSource)
- is_http2: 2 (keep-alive), END_STREAM=false, GOAWAY=false

### Current Status: 🔶 ARCHITECTURAL_LIMIT (Strike 5+)
- 차단O, 경고X
- Generator 호출 확인 (body_size=391, h2_size=579)
- Chrome EventSource에서 SSE 이벤트 0개로 파싱됨
- 정상 HAR 캡처(#029) 결과 대기 중

### Iteration 1 (2026-03-23) — Test 134
- DB: domain=ai.api.gamma.app, path=/ai/v2/
- Test result: 결과 미도착

### Iteration 2 (2026-03-26) — Test #008
- 초기 warning test: PARTIAL — 차단O, 빈 개요만 생성
- Generator가 이미 SSE 형식이었지만 경고 텍스트 미표시

### Iteration 3 (2026-03-26) — Test #023 (Build #15)
- 변경: SSE `\r\n` → `\n`, outline.title + cards[0].title + description에 경고 삽입
- 결과: PARTIAL_BLOCK — 카드 1개 빈 제목
- 서버 로그: end_stream=1 → Chrome ReadableStream 즉시 닫힘
- 근본 원인: gamma가 use_end_stream 제외 목록에 없었음

### Iteration 4 (2026-03-27) — Test #027 (Build #16)
- 변경: END_STREAM=false (gamma를 use_end_stream 제외 목록에 추가)
- 결과: WARNING_NOT_DISPLAYED
  - 서버: 200 OK, 0.6kB 전송
  - Chrome: EventStream 탭에 이벤트 0개
  - 카드: 1개, title="1" (기본값?)
  - 콘솔: WebSocket to api.gamma.app/graphql closed 에러
- 진단:
  - H2 DATA frame은 전달됨 (크기 확인)
  - Chrome EventSource가 SSE 이벤트로 파싱하지 못함
  - 가능 원인: (1) generator의 SSE 포맷이 실제 포맷과 다름, (2) EventSource 버퍼링 이슈
- 해결 방향: Gamma 정상 응답 HAR 캡처(#029)로 실제 SSE 포맷 확인 필요

### Key Technical Findings
- Gamma는 EventSource (native API) 사용 — fetch+ReadableStream이 아님
- GraphQL WebSocket (wss://api.gamma.app/graphql) 도 사용
- render-generation은 generation 이후 호출되는 별도 엔드포인트
- 정상 응답의 SSE 이벤트 구조를 아직 확인하지 못함 (← 핵심 missing info)

### Iteration 5 (2026-03-27) — Test #033 (Build #18b)
- 변경: END_STREAM=true + chunk/done SSE 포맷
- 결과: WARNING_NOT_DELIVERED — EventStream 0건 (Copilot #032와 동일 패턴)
- 0.3kB (헤더만), Response body 없음
- 모든 END_STREAM 설정에서 0건: false(#027,#031), true(#033)

### Server Log Analysis
- stream_id=1 (첫 번째 H2 스트림)
- h2_size=322 bytes (HEADERS 179 + DATA 143)
- body_size=134, hdr_size=201
- HPACK 인코딩 정상 (:status 200, content-type 포함)
- 비교: Copilot stream_id=15 (높은 스트림) → 이벤트 수신됨
- Gamma stream_id=1 → 이벤트 미수신

### H2 Configuration History
```
Build #15: is_http2=2, END_STREAM=false, GOAWAY=false → 0 events
Build #18: chunk/done SSE + END_STREAM=false, GOAWAY=false → 0 events
Build #18b: chunk/done SSE + END_STREAM=true, GOAWAY=false → 0 events
Build #19: chunk/done SSE + END_STREAM=false, GOAWAY=true → 0 events
Build #20: 2-frame DATA + END_STREAM=true + GOAWAY → 0 events
```

### Conclusion
- 모든 H2 설정 조합 (END_STREAM true/false, GOAWAY true/false, 2-frame DATA)에서 EventStream 0건
- Copilot은 END_STREAM=false에서 이벤트 수신 가능 (stream_id=15), Gamma는 불가 (stream_id=1)
- 근본 원인: Etap의 H2 DATA frame이 Gamma 연결에서 브라우저에 전달되지 않음
- 차단은 정상 동작 (빈 outline 생성 → 실질적 차단)
- 경고 표시를 위해서는 Etap H2 응답 주입 메커니즘 자체의 디버깅 필요
  (tcpdump로 실제 wire 레벨의 DATA frame 전송 확인 등)

### Production Config (Build #20)
- is_http2=2, END_STREAM=true (2-frame DATA), GOAWAY=true
- 결과: 깨끗한 차단 (에러 없음, 빈 outline → 발표 생성 실패)


### Iteration 6 (2026-03-27) — Test #041 (Build #21 REAL deploy)
- 변경: SSE → JSON error response (422 Unprocessable Entity + JSON body)
- Generator: `generate_gamma_block_response()` → JSON error body
- H2 설정: is_http2=2, END_STREAM=true (2-frame DATA), GOAWAY=true
- 이전 #039는 Build #20 바이너리로 실행됨 (배포 실패). #041이 실제 Build #21 테스트.
- 결과: **PARTIAL_PASS** ✅
  - 422 Unprocessable Content 확인!
  - Console: `POST https://ai.api.gamma.app/ai/v2/generation 422 (Unprocessable Content)`
  - Console: `[PromptAndOutlineSettings] error generating outline: Unable to complete request`
  - DevTools에서 response body 로드 불가 (No data found for resource)
  - Gamma UI: 빈 개요 (카드 1개, content="1") — 이전과 동일한 퇴화 패턴
  - 경고 텍스트 미표시 — Gamma 프론트엔드가 422를 catch하고 최소 outline fallback 생성
- 결론: 네트워크 레벨에서 422 전달 성공. Copilot과 동일 패턴.
  차단은 실질적으로 동작 (발표 생성 불가).
  경고 텍스트 표시를 위해서는 JS injection 등 프론트엔드 개입 필요.

### H2 Configuration History (Updated)
```
Build #15: is_http2=2, END_STREAM=false, GOAWAY=false → 0 events
Build #18: chunk/done SSE + END_STREAM=false, GOAWAY=false → 0 events
Build #18b: chunk/done SSE + END_STREAM=true, GOAWAY=false → 0 events
Build #19: chunk/done SSE + END_STREAM=false, GOAWAY=true → 0 events
Build #20: 2-frame DATA + END_STREAM=true + GOAWAY → 0 events
Build #21: JSON error 422 + 2-frame DATA + GOAWAY → 422 확인! (PARTIAL_PASS)
```

### Production Config (Build #21)
- is_http2=2, END_STREAM=true (2-frame DATA), GOAWAY=true
- Generator: JSON error 422 + `{"error":{"message":"...","type":"policy_violation","code":"content_filter"}}`
- 결과: 차단 성공 + 빈 outline 표시 (PARTIAL_PASS)

### Iteration 7 (2026-03-27) — Builds #22~#25: 다양한 HTTP 응답 코드 시도
| Build | 방식 | 결과 |
|-------|------|------|
| #22 | 200+text/plain | "Unable to complete request", 1 card |
| #23 | 403 Forbidden | 1 card degradation, 경고 텍스트 없음 |
| #24 | 429 Rate Limit | "Unable to complete request", 1 card |
| #25 | 200+text/html error page | "Unable to complete request", 1 card |
- 공통 결론: Gamma 프론트엔드가 모든 에러를 catch하여 최소 outline fallback 생성. 경고 텍스트 전달 불가.

### Iteration 8 (2026-03-27) — Build #26: SSE BREAKTHROUGH
- 변경: SSE + JSON object body + 1-frame DATA (use_end_stream=false, use_goaway=false)
- is_http2=2 (keep-alive)
- 결과: **BREAKTHROUGH** — 데이터가 Gamma UI에 표시됨 (세로로 한 글자씩)
- 최초로 SSE 데이터가 EventSource를 통과하여 렌더링됨
- 그러나 경고 문구가 "읽을 수 있는" 형태로는 아님 (JSON object의 각 char가 별도 카드 텍스트로)

### Iteration 9 (2026-03-27) — Builds #27~#29: Build #26 재현 시도
| Build | 방식 | 결과 |
|-------|------|------|
| #27 | SSE plain text (Build #26과 동일 H2 flags) | REGRESSION — "Unable to complete request" |
| #28 | SSE JSON string literal | JSON string discarded |
| #29 | SSE multi-chunk JSON | Empty — single chunk only |
- 결론: Build #26 성공 조건 재현 불가. JSON object만 통과했지만, 일관성 없음.

### Iteration 10 (2026-03-27) — Builds #30~#33: ERR_CONNECTION_CLOSED 연속
| Build | 방식 | 결과 |
|-------|------|------|
| #30 | SSE single-key JSON {content:msg} | Failed to fetch (status 0) |
| #31 | SSE multi-key JSON, no done event | ERR_CONNECTION_CLOSED 200 (OK) |
| #32 | SSE large 11-key JSON (~800B body) | ERR_CONNECTION_CLOSED 200 (OK) — body size 무관 확인 |
| #33 | SSE real Gamma format (9 plain text chunks + done=stop, ~2.5kB) | ERR_CONNECTION_CLOSED 200 (OK) — exact format도 무관 |

**핵심 발견:**
- Build #30~#33 모두 동일 증상: HEADERS(200 OK) 수신 후 DATA frame 미도착
- Body 크기 무관 (154B → 800B → 2.5kB 모두 동일 실패)
- SSE content 형식 무관 (JSON, plain text, real format 모두 동일 실패)
- Build #26의 성공은 일시적 조건(기존 H2 연결 재사용, 타이밍 등)으로 추정
- convert_to_http2_response()에서 동일 코드 경로(single DATA, flags=0x00) 사용

### BLOCKED_ONLY 판정 (2026-03-27)
- **시도한 방식:**
  - ① HTTP 응답 body 조작: 13+ builds (422/403/429/200+HTML/SSE JSON/SSE plaintext/SSE real format)
  - ② 에러 페이지 교체: Build #25 (200+text/html)
  - ③ JS injection: 미시도 (Etap에서 JS injection 메커니즘 없음)
- **차단 동작:** 정상 — 빈 outline 생성 → 발표 생성 실패 (실질적 차단)
- **커스텀 경고 불가 원인:**
  - H2 DATA frame이 브라우저 EventSource로 전달되지 않음 (ERR_CONNECTION_CLOSED)
  - Gamma 프론트엔드가 모든 HTTP 에러를 catch하여 자체 fallback UI 표시
  - Build #26의 1회성 SSE 성공은 재현 불가
- **향후 재시도 조건:**
  - Etap H2 응답 주입 메커니즘 개선 시 (tcpdump 레벨 디버깅)
  - 또는 Gamma 프론트엔드 업데이트로 에러 처리 방식 변경 시

### Final Production Config
- is_http2=2, END_STREAM=false (1-frame DATA, flags=0x00), GOAWAY=false
- Generator: SSE format (현재 Build #33 코드 유지 — 차단 동작 정상)
- 상태: **BLOCKED_ONLY** — 차단O, 경고 텍스트 표시X

### Iteration 7 (2026-03-27) — Builds #22-#25 (non-SSE approaches)
- Build #22: 200 OK + text/plain → "Unable to complete request", 1 empty card
- Build #23: 403 Forbidden → 1 card degradation, no warning
- Build #24: 429 Rate Limit → "Unable to complete request", 1 empty card
- Build #25: 200 OK + text/html error page → "Unable to complete request", 1 empty card
- 결론: 모든 non-SSE HTTP 응답은 동일한 퇴화 패턴 (빈 outline)

### Iteration 8 (2026-03-27) — Test #050 (Build #26) **BREAKTHROUGH**
- 변경: SSE `text/event-stream` + 2-frame DATA delivery (`use_end_stream=false`, `use_goaway=false`)
- Generator: `event: chunk\r\ndata: {large JSON object with many keys}\r\n`
- 결과: **BREAKTHROUGH** — SSE 이벤트가 Gamma EventSource에서 최초로 파싱됨!
  - JSON 오브젝트의 각 문자가 수직으로 렌더링 (char-by-char)
  - "Unable to complete request" 에러는 여전히 발생하지만 데이터 표시됨
  - 이전 SSE 시도 (Build #16-#20, END_STREAM+GOAWAY)는 모두 0 events
- 핵심 발견: `use_end_stream=false` + `use_goaway=false` 조합이 EventSource 파싱의 핵심
- 남은 문제: JSON 데이터가 수직 문자로 렌더링됨 → 올바른 포맷 필요

### Iteration 9 (2026-03-27) — Test #051 (Build #27) REGRESSION
- 변경: SSE data를 plain text로 변경 (JSON → 일반 텍스트)
- 결과: **REGRESSION** — 빈 outline로 복귀
- 원인: Gamma의 chunk handler가 JSON.parse() 호출 → plain text는 파싱 실패 → 폐기
- 교훈: SSE data 필드는 반드시 JSON object여야 함

### Iteration 10 (2026-03-27) — Test #052 (Build #28)
- 변경: SSE data를 JSON string literal ("warning text") 로 변경
- 결과: 빈 outline — JSON string도 폐기됨
- 원인: JSON.parse()가 string을 반환하면 Gamma의 iterator가 처리 불가 (object만 가능)
- Stack trace 에러 발생 (H, h, c, u — minified 함수)

### Iteration 11 (2026-03-27) — Test #053 (Build #29)
- 변경: multi-chunk JSON objects (chunk1: {title:...}, chunk2: {cards:[...]})
- 결과: 빈 outline — 여러 chunk로 분리하면 처리 안됨
- 원인: Gamma는 단일 chunk의 단일 JSON object만 처리
- 교훈: Build #26처럼 단일 chunk + 단일 JSON object가 유일한 작동 포맷

### Iteration 12 (2026-03-27) — Test #054 (Build #30) **PENDING**
- 변경: 단일 chunk에 최소 JSON `{"content":"warning_text"}` — key 1개만 사용
- 가설: key가 적으면 Gamma가 value를 통째로 사용하여 가독성 있는 렌더링 기대
- 결과: **대기 중** — test PC 워커 비활성

### H2 Configuration History (Complete)
```
Build #15: is_http2=2, END_STREAM=false, GOAWAY=false → 0 events
Build #18: chunk/done SSE + END_STREAM=false, GOAWAY=false → 0 events
Build #18b: chunk/done SSE + END_STREAM=true, GOAWAY=false → 0 events
Build #19: chunk/done SSE + END_STREAM=false, GOAWAY=true → 0 events
Build #20: 2-frame DATA + END_STREAM=true + GOAWAY → 0 events
Build #21: JSON error 422 + 2-frame DATA + GOAWAY → 422 확인! (PARTIAL_PASS)
Build #22: 200+text/plain + 2-frame DATA + GOAWAY → 1 empty card
Build #23: 403 Forbidden + 2-frame DATA + GOAWAY → 1 card degradation
Build #24: 429 Rate Limit + 2-frame DATA + GOAWAY → 1 empty card
Build #25: 200+text/html + 2-frame DATA + GOAWAY → 1 empty card
Build #26: SSE 200 + 2-frame DATA (END_STREAM=false, GOAWAY=false) → **BREAKTHROUGH** chars visible
Build #27: SSE plain text + 2-frame (ES=false, GA=false) → REGRESSION (text discarded)
Build #28: SSE JSON string + 2-frame (ES=false, GA=false) → discarded (only objects work)
Build #29: SSE multi-chunk JSON + 2-frame (ES=false, GA=false) → empty (single chunk only)
Build #30: SSE single-key JSON + 2-frame (ES=false, GA=false) → PENDING
```

### Key Technical Findings (Updated)
- Gamma EventSource 파싱 조건: `use_end_stream=false` + `use_goaway=false` (2-frame DATA 전략)
- SSE data 필드: JSON **object** 필수 (plain text, string literal 모두 폐기)
- 단일 chunk만 작동 (multi-chunk 불가)
- Build #26에서 JSON object의 각 문자가 수직 렌더링 → outline parser가 JSON을 char-by-char 순회
- Build #30 (단일 key JSON)이 마지막 시도 — 성공 시 PARTIAL_PASS, 실패 시 BLOCKED_ONLY 판정