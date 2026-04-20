## HuggingFace (huggingface) — Implementation Journal

### Service Info
- Domain: huggingface.co
- Path: /chat/conversation/
- Endpoint: POST huggingface.co/chat/conversation/{uuid}
- Protocol: H2, NDJSON (application/jsonl)
- is_http2: 2 (keep-alive), h2_end_stream=1, h2_goaway=0, h2_hold_request=1
- Framework: Svelte/SvelteKit (chat-ui open source)

### Current Status: 🔶 BLOCK_ONLY (NDJSON 파서 호환성)
- 차단O (blocked=1, 빈 채팅 영역)
- 경고X (NDJSON 응답 수신되나 프론트엔드 렌더링 불가)

### Template Applied
- response_type: huggingface_ndjson
- Content-Type: application/jsonl
- Body (5 lines NDJSON):
  ```
  {"type":"status","status":"started"}
  {"type":"stream","token":"{{MESSAGE}}"}
  {"type":"finalAnswer","text":"{{MESSAGE}}","interrupted":false}
  {"type":"status","status":"finished"}
  [DONE]
  ```

### Iteration 1 (#490, 2026-04-20) — huggingface_ndjson + Content-Length fix

**변경:** openai_compat_sse → huggingface_ndjson 전용 템플릿 전환
- Content-Type: application/jsonl (SSE 아닌 NDJSON)
- 5-event NDJSON body: status:started, stream, finalAnswer, status:finished, [DONE]
- Content-Length: {{BODY_INNER_LENGTH}} (이전 0에서 수정)

**결과: FAIL — 빈 채팅 영역**
- 차단 동작: 200/h2 수신 (APF 응답 전달 성공)
- 새 대화 생성됨 (/conversation/{id} 이동)
- 콘솔 에러: 없음
- 경고 텍스트: 미표시 (빈 assistant 영역)

### 소스코드 분석 (2026-04-20, github.com/huggingface/chat-ui)

**파서 코드 (messageUpdates.ts):**
```
parseMessageUpdates(value):
  inputs = value.split("\n")
  for input of inputs:
    try: messageUpdates.push(JSON.parse(input))
    catch SyntaxError: return {messageUpdates, remainingText: inputs.at(-1)}
  return {messageUpdates, remainingText: ""}
```
- `\n` 기준 split → 각 줄 JSON.parse → 실패 시 나머지 반환
- 우리 템플릿의 4개 유효 이벤트는 정상 파싱됨 (확인)

**이벤트 타입 enum (MessageUpdate.ts):**
- MessageUpdateType.Status = "status" ✓ 일치
- MessageUpdateType.Stream = "stream" ✓ 일치
- MessageUpdateType.FinalAnswer = "finalAnswer" ✓ 일치
- MessageUpdateStatus.Started = "started" ✓ 일치
- MessageUpdateStatus.Finished = "finished" ✓ 일치

**페이지 처리 (+page.svelte):**
1. status:started → updates 배열에 추가
2. stream token → buffer에 추가, scheduleFrameFlush(rAF) 예약
3. finalAnswer → buffer flush 후 messageToWriteTo.content = finalText
4. status:finished → updates 배열에 추가

**이론상 content가 설정되어야 하나 빈 화면이 나오는 근본 원인 후보:**

#### 후보 A: ReadableStream 전달 실패 (H2 2-frame DATA)
- h2_end_stream=1 → 2-frame DATA 전략 사용
- 전체 ~350B body가 단일 DATA frame에 포함
- Chrome ReadableStream이 body를 전달하지 못할 가능성
- 검증: DevTools Network → Response 탭에서 body 확인 필요

#### 후보 B: fetchMessageUpdates의 `.catch()` 소비
- `fetchMessageUpdates(...).catch((err) => { error.set(err.message); })`
- Promise rejection 시 iterator가 undefined → early return
- APF 응답이 어떤 이유로 fetch 에러를 유발하면 즉시 종료
- 검증: 콘솔에 에러 없었으므로 가능성 낮음

#### 후보 C: Svelte 반응성 미트리거
- 모든 이벤트가 동기적으로 처리되면 Svelte DOM 갱신 누락 가능
- for-await 루프는 async generator이므로 microtask 단위
- 하지만 실제 서버도 빠르게 응답할 수 있으므로 가능성 낮음

#### 후보 D: SvelteKit 서버 경로 문제
- POST /chat/conversation/{id}는 SvelteKit +server.ts 엔드포인트
- APF가 응답하면 SvelteKit 서버 미경유
- SvelteKit 클라이언트가 서버 미경유 응답을 다르게 처리할 가능성
- 검증: DevTools에서 response headers 확인 필요

#### 후보 E: 서버 응답과의 차이점
서버 실제 응답 vs APF 응답 비교:
| 항목 | 서버 | APF |
|------|------|-----|
| 전달 속도 | 수 초 streaming | 즉시 (단일 frame) |
| stream token padding | \0 null bytes | 없음 |
| finalAnswer 후 padding | 4096 spaces | 없음 |
| conversationId init | 첫 줄 {"conversationId":"..."} | 없음 |
| keepAlive heartbeat | 여러 번 | 없음 |

**가장 유력한 원인: 후보 A (ReadableStream 전달 실패)**
- 콘솔 에러 없음 + 빈 화면 = body가 전달되지 않았을 가능성
- 다른 서비스(Copilot 등)의 2-frame DATA에서도 유사 증상 관찰
- fetch() response.body가 비어있으면 파서가 실행되지 않으므로 에러도 없음

### 진단 테스트 계획 (#494)

**목표: ReadableStream에 body가 실제 도달하는지 확인**

1. DevTools Network → conversation POST → Response 탭 확인
   - body 내용이 보이면: 후보 A 배제 → 파서 문제
   - body 비어있으면: 후보 A 확정 → H2 전달 문제

2. DevTools Console에서 JS 주입 테스트:
   ```javascript
   // fetch intercept로 실제 response body 캡처
   const origFetch = window.fetch;
   window.fetch = async (...args) => {
     const resp = await origFetch(...args);
     if (args[0]?.includes?.('/chat/conversation/')) {
       const clone = resp.clone();
       clone.text().then(t => console.log('[APF-DIAG] body:', t.substring(0, 500)));
     }
     return resp;
   };
   ```

3. 템플릿 변형 A/B 테스트 준비


### Iteration 2 (#494, 2026-04-20) — NDJSON v2 3-bug fix

**변경 (DB UPDATE, 3중 버그 수정):**
1. Content-Type: text/event-stream → application/jsonl
2. Escaping: {{ESCAPE2:MESSAGE}} → {{MESSAGE}} (single nesting)
3. Header separator: \n → \r\n (HTTP spec 준수)
4. conversationId 이벤트 추가 (첫 줄)
5. [DONE] terminal marker 추가

**결과: FAIL — 빈 채팅 영역 (이전과 동일)**
- Conversation 생성됨 (URL에 conversation ID 표시)
- 채팅 영역 완전 비어있음 — user message도 미표시
- 콘솔 에러: 없음 (2 issues만 — possible improvements)
- 경고 텍스트: 미표시

**분석:**
- 3회 연속 FAIL (template format 카테고리)
- 템플릿 형식은 소스코드 분석 기준 정확 (이벤트 타입/상태 일치)
- **핵심 의심: 후보 A (ReadableStream 전달 실패)** — body가 브라우저에 도달하지 않는 구조적 문제
- body 미도달이면 어떤 템플릿 형식도 효과 없음

**3-Strike Rule 적용:**
- 카테고리: template_format (3회 연속)
- 에스컬레이션: frontend-inspect 전환 — DevTools Response body 확인 필요
- 진단 목표: POST /chat/conversation/{id} → Response 탭에 body 내용 존재 여부


### Iteration 3 (#496, 2026-04-20) — h2_hold_request=0→1 fix

**가설: 조기 응답으로 인한 ReadableStream 전달 실패**

h2_hold_request=0일 때:
1. Browser가 POST /chat/conversation/{id} 전송 시작 (multipart/form-data)
2. APF가 request body에서 keyword 감지 → 즉시 block response 전송
3. Browser의 fetch()가 아직 request body 전송 중 → 응답 수신 준비 안 됨
4. ReadableStream이 setup되지 않거나 body가 비어있는 상태로 resolve
5. chat-ui 파서가 빈 body를 받아 아무것도 렌더링하지 않음

h2_hold_request=1로 변경 시:
1. APF가 request body 전체를 버퍼링 (hold)
2. Request 완료 후 browser의 fetch()가 "응답 대기" 상태 진입
3. 그 후 APF가 block response 전송
4. Browser의 ReadableStream이 정상적으로 body 수신
5. chat-ui 파서가 NDJSON 이벤트를 처리하여 경고 텍스트 렌더링

**변경:** `UPDATE ai_prompt_services SET h2_hold_request=1 WHERE service_name='huggingface'`
**reload_services:** 성공
**#496 check-warning 전송:** 결과 대기 중

**근거:**
- etap 로그의 response size=496B (body 정상 생성 확인)
- 3회 연속 템플릿 형식 수정으로 해결 안 됨 → 형식이 아닌 전달 문제
- deepseek(h2_hold_request=1)에서는 SSE body가 정상 전달됨 → h2_hold_request 차이가 핵심


### #495 Diagnostic Result (2026-04-20) — DevTools Response body 확인

**결과: BODY_PRESENT — H2 delivery는 정상, PARSER_ISSUE 확정**

DevTools Network → Response 탭에서 확인:
- 6줄 NDJSON body가 browser ReadableStream에 도착
- Line 1: `{"conversationId":"b28564b5-..."}` (UUID)
- Line 2: `{"type":"status","status":"started"}`
- Line 3: `{"type":"stream","token":"경고 메시지 (한국어)"}` 
- Line 4: `{"type":"finalAnswer","text":"경고 메시지","interrupted":false}`
- Line 5: `{"type":"status","status":"finished"}`
- Line 6: `[DONE]`
- Format: HuggingChat 예상 NDJSON 형식과 정확히 일치
- Status: 200 OK, Protocol: h2

**핵심 결론:**
- h2_hold_request 가설 무효: body는 h2_hold_request=0일 때도 도착했음
- **SvelteKit 프론트엔드 파서가 APF 주입 NDJSON 스트림을 소비하지 않음**
- 구조적 한계: HuggingChat SvelteKit SSR streaming이 특정 서버측 프로세싱을 요구할 가능성

### #496 Result (2026-04-20) — h2_hold_request=1 → FAIL

**결과: FAIL — h2_hold_request=1도 동일 증상**
- 빈 채팅 영역 (경고 미표시)
- DevTools Response: NDJSON body 동일하게 도착 (#495와 동일 형식)
- h2_hold_request 변경은 효과 없음 (body가 원래부터 도착하고 있었으므로)

**종합 판정: BLOCK_ONLY**
- 4회 시도 (원본, 3-bug fix, h2_hold_request, 진단 확인)
- Root cause: SvelteKit frontend parser가 APF 주입 NDJSON을 렌더링하지 않음
- Body는 도착하지만 프론트엔드가 소비하지 않는 구조적 한계
- DB/template 접근법으로 해결 불가 → BLOCK_ONLY 확정
