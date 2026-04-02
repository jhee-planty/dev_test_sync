## ChatGPT — Warning Design (RESET 2026-03-27)

### Phase 1 Reinspection (#070)
- accessible: true, login_required: false
- etap_proxy_active: true, protocol: h2
- comm_type: SSE streaming
- API: /backend-anon/conversation (비로그인), /f/conversation (로그인)
- WebSocket: 없음

### Strategy
- Pattern: SSE_STREAM_WARNING
- HTTP/2 strategy: C (HTTP/1.1 Content-Length 기반, Etap이 H2로 변환)
- Based on: SSE text/event-stream, v1 delta 형식, 프론트엔드가 delta patch로 채팅 버블 렌더링

### Response Specification
- HTTP Status: 200 OK
- Content-Type: text/event-stream; charset=utf-8
- Body format: SSE events (v1 delta encoding)
- SSE delimiter: \r\n\r\n (기존 코드 기준)
- Warning text: 경고 메시지 (DB ai_prompt_filter_service.warn_msg)
- Event sequence: delta_encoding(v1) → delta(add, 메시지 초기화) → delta(patch, 경고텍스트) → delta(patch, 완료) → message_stream_complete → [DONE]
- Required fields: conversation_id(UUID4), message_id(UUID4), author.role=assistant, model_slug=gpt-4o
- end_stream: true (Content-Length 기반)
- GOAWAY: N/A (Strategy C)

### Dual Endpoint Coverage
- /backend-anon/conversation: 비로그인 사용자 (prepare 불필요)
- /f/conversation: 로그인 사용자
- /f/conversation/prepare: 사전 차단 (JSON error status 응답)
- 기존 코드에 chatgpt_prepare + chatgpt SSE 두 generator 모두 구현됨

### Frontend Rendering Prediction
- Warning appears in: 채팅 버블 (assistant message)
- Rendered as: plain text (markdown renderer 미확인)
- User experience: AI 응답 대신 경고 메시지가 채팅 버블에 표시
- Known artifacts: 없음 (Strategy C, 깔끔한 종료)

### Test Criteria
- [ ] 경고 메시지가 채팅 버블에 정상 표시
- [ ] "Something went wrong" 등 에러 UI 미발생
- [ ] 콘솔에 치명적 에러 없음
- [ ] 페이지 새로고침 없이 다음 질문 가능
- [ ] 비로그인(/backend-anon) 경로에서도 동일 동작

### Existing Code
- Generator: generate_chatgpt_sse_block_response (line 1028)
- Prepare: generate_chatgpt_prepare_block_response (line 1005)
- is_http2: 확인 필요 (DB)
- Changes needed: Phase 3 테스트 후 결정

### Notes
- 기존 DONE 판정이었으나 전면 재검증 대상
- 코드 구조가 가장 성숙한 서비스 중 하나
