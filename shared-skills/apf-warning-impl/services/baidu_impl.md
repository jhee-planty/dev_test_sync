## Baidu ERNIE (baidu) — Implementation Journal

### Service Info
- Domain: chat.baidu.com (yiyan.baidu.com 리다이렉트 포함)
- Endpoint: POST chat.baidu.com/eb/chat/conversation
- Protocol: H2, SSE (text/event-stream)
- is_http2: 2 (keep-alive), h2_end_stream=2 (delayed, 2026-04-20 변경), h2_goaway=0, h2_hold_request=1 (2026-04-20 변경)
- Framework: 자체 SPA (ERNIE Bot)

### Current Status: 🔶 TESTING (h2_end_stream=2 재시도)
- 이전 상태: NEEDS_ALTERNATIVE (#489 FAIL)
- 차단O (blocked=1)
- 경고X (ERNIE UI가 APF SSE 콘텐츠 무시)

### Template Applied
- response_type: baidu_sse_v2
- Content-Type: text/event-stream

### Iteration 1 (#489, 2026-04-20) — baidu_sse_v2

**결과: FAIL**
- 차단 동작: 200 OK + SSE 응답 전달
- ERNIE UI가 APF SSE 콘텐츠 무시
- onclose + AbortError 발생
- SPA navigation requirement

**분석:**
- onclose 이벤트는 EventSource/SSE stream이 닫힐 때 발생
- AbortError는 fetch abort signal이 trigger될 때 발생
- stream 조기 종료 → frontend가 에러로 처리 → SSE data 무시

**판정:** NEEDS_ALTERNATIVE (SPA navigation 필요)

### Iteration 2 (#499, 2026-04-20) — h2_end_stream=2 + h2_hold_request=1

**가설: stream 조기 종료가 onclose+AbortError의 원인**

h2_end_stream=1 (이전):
1. DATA(body, END_STREAM=0) + DATA(empty, END_STREAM=1) → 동시 전송
2. Stream 즉시 닫힘 → onclose 이벤트 발생
3. ERNIE UI가 onclose 핸들러에서 AbortError → SSE data 무시

h2_end_stream=2 (변경):
1. VTS가 DATA(body, END_STREAM=0) 전송 → stream 열림
2. 10ms 대기 → browser event loop이 SSE events 처리
3. ERNIE UI가 SSE data를 정상 수신 + 렌더링
4. VTS가 END_STREAM 전송 → stream 정상 종료

**변경:** 
- `UPDATE ai_prompt_services SET h2_end_stream=2, h2_hold_request=1 WHERE service_name='baidu'`
- reload: revision_cnt 증가, 17:14:18 reload 확인
- #499 check-warning 전송: 결과 대기 중

**근거:**
- deepseek(h2_end_stream=2)에서 SSE 정상 전달 + 경고 표시
- onclose+AbortError 패턴은 stream 조기 종료의 전형적 증상
- h2_hold_request=1로 request body 완료 후 응답 전송
