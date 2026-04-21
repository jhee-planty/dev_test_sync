## Wrtn — Warning Design

### Checklist Results
- 통신 유형: SSE (openai_compat_sse)
- 프로토콜: HTTP/2
- 다중화: YES (Next.js SPA, 동시 API 호출 다수 — analytics, feature flags, API 병렬)
- 에러 핸들러: 불명 (로그인 필요로 차단 시 UI 미관찰)
- 에러 UI: 불명 (로그인 필요로 차단 시 에러 UI 미관찰)
- payload 검증: NO (OpenAI 호환 SSE — chatgpt와 동일 형식, 검증 없을 것으로 예상)
- 조기 판정 해당 여부: NO — SSE 표준 전달 시도 가능
- 로그인 필요: Partial-function (페이지 로드 가능, AI 기능만 인증 필요)

### Strategy
- Pattern: SSE_STREAM_WARNING (chatgpt와 동일한 OpenAI 호환 SSE 패턴)
- HTTP/2 strategy: D (END_STREAM only) — 다중화 보호 (h2_mode=2, h2_goaway=0)
- Based on: 통신 유형 SSE + payload 검증 없음 + 다중화 YES → Strategy D + SSE_STREAM_WARNING

### Response Specification
- HTTP Status: 200 OK
- Content-Type: text/event-stream; charset=utf-8
- Transfer-Encoding: N/A (Content-Length 사용)
- Body format: OpenAI 호환 SSE (data: JSON + data: [DONE])
- SSE delimiter: `\n\n`
- Warning text: "⚠️ 보안 경고: 입력하신 내용에 개인정보(비밀번호, 주민등록번호 등)가 포함되어 있어 전송이 차단되었습니다. 개인정보를 제거한 후 다시 시도해 주세요."
- Required fields: choices[0].delta.content (경고 텍스트), model, id, finish_reason="stop"
- Expected body size: ~400-500 bytes
- end_stream: true (h2_end_stream=1)
- GOAWAY: no (h2_goaway=0, 다중화 보호)

### Existing Envelope Template (DB id=34)
```
HTTP/1.1 200 OK
Content-Type: text/event-stream; charset=utf-8
Cache-Control: no-cache
Connection: keep-alive
Access-Control-Allow-Origin: *
Content-Length: {{BODY_INNER_LENGTH}}

data: {"choices":[{"delta":{"content":"{{ESCAPE2:MESSAGE}}"},"index":0,"finish_reason":"stop"}],"model":"blocked","id":"{{UUID:chatcmpl}}"}

data: [DONE]
```

### Frontend Rendering Prediction
- Warning appears in: 채팅 응답 영역 (사용자 메시지 하단)
- Rendered as: 마크다운 렌더링 (Next.js + React 기반, 마크다운 지원 예상)
- User experience: 사용자가 메시지 전송 후 AI 응답 대신 경고 문구가 표시됨
- Known artifacts: 없음 (Strategy D — END_STREAM만 사용, GOAWAY 없어 cascade failure 없음)
- 주의: #476에서 차단 시 "뤼튼 아바타는 보이지만 텍스트 없음" → 현재 envelope이 이미 동작하나 경고 텍스트가 렌더링되지 않을 가능성. Phase 6에서 로그인 후 확인 필요.

### Test Criteria
- [ ] 경고 문구가 채팅 응답 영역에 표시됨
- [ ] 경고 문구에 "보안 경고" 또는 "개인정보" 텍스트가 포함됨
- [ ] 경고 후 채팅 입력이 계속 가능함 (페이지 크래시 없음)
- [ ] 다른 탭/기능이 정상 동작함 (Strategy D, GOAWAY 없음)
- [ ] Console에 ERR_HTTP2_PROTOCOL_ERROR 없음

### Test Log Points
- Log point 1: `block_session` — 차단 트리거 확인 (이미 #476에서 확인됨)
- Log point 2: `[APF_WARNING_TEST:wrtn]` — envelope 전송 확인
- Log point 3: H2 stream 상태 (h2_mode=2, end_stream 전송 확인)

### Relationship to Existing Code
- Existing generator: none (DB envelope 템플릿 기반 — C++ 하드코딩 없음)
- Changes needed: 없음 (DB id=34 envelope이 이미 등록됨, 차단 동작 확인됨)
- is_http2 value: h2_mode=2 (Strategy D)
- Shared approach with: chatgpt (동일 openai_compat_sse 패턴), kimi, huggingface, chatglm, qianwen

### Notes
- wrtn은 DB 기반으로 동작하며 C++ 코드 수정 불필요. envelope 템플릿(id=34)이 이미 등록됨.
- #476에서 키워드 차단은 확인됨 (ALL_PASS 2/2). 그러나 "아바타만 보이고 텍스트 없음" — envelope SSE가 프론트엔드에서 파싱되는지 로그인 후 확인 필요.
- path_patterns='/'가 모든 경로를 매칭하여 telemetry(/event/v3) 등 비채팅 요청도 키워드 검사 대상. regex FP 수정(2026-04-17)으로 즉시 문제는 해소됨.
- path_patterns 정밀화: 향후 wrtn의 실제 채팅 API 경로를 파악하여 path_patterns를 좁히는 것을 권장.
- 로그인 필요: Phase 6(Warning Impl & Test)에서 인증된 세션으로 테스트 필요 (NEEDS_USER_SESSION).

### Full Checklist Record
<details>
<summary>전체 체크리스트 판별 결과 (클릭하여 펼치기)</summary>

| # | 항목 | 결과 | 근거 |
|---|------|------|------|
| 1-1 | 통신 유형 | SSE (openai_compat_sse) | #479 frontend profile + DB response_type |
| 1-2 | 프로토콜 | HTTP/2 | #479 frontend profile: h2 |
| 1-3 | 다중화 | YES | Next.js SPA, analytics+API 병렬 호출 관찰 |
| 1-4 | SSE 구분자 | `\n\n` | OpenAI 호환 SSE 표준 |
| 1-5 | WebSocket 사용 | NO | HTTP/2 fetch/SSE 확인 (#475, #476) |
| 1-6 | 인증 필요 | Partial-function | 페이지 로드 가능, AI 채팅만 인증 필요 (#479) |
| 2-1 | Content-Type | text/event-stream; charset=utf-8 | DB envelope 템플릿 |
| 2-2 | 필수 JSON 키 | choices[0].delta.content | OpenAI 호환 형식 |
| 2-3 | SSE init 이벤트 | 불명 | 로그인 필요로 정상 응답 미관찰. 리스크: Phase 6에서 확인 |
| 2-4 | 마크다운 렌더러 | YES (예상) | Next.js + React 기반 AI 서비스 |
| 2-5 | 응답 소비 형태 | 채팅 버블 | 채팅 인터페이스 (#479) |
| 2-6 | 버블 생성 최소 조건 | 불명 | 로그인 필요. 리스크: Phase 6에서 확인 |
| 3-1 | 에러 핸들러 범위 | 불명 | 로그인 필요. 리스크: Phase 6에서 확인 |
| 3-2 | 에러 UI | 불명 | 로그인 필요. 리스크: Phase 6에서 확인 |
| 3-3 | 에러 UI 경고 대체 | 불명 | 로그인 필요 |
| 3-4 | silent failure | 불명 | 로그인 필요 |
| 4-1 | payload 검증 | NO (예상) | OpenAI 호환 SSE — chatgpt 동일 패턴에서 검증 없음 |
| 4-2 | 단일 write 종료 | YES (h2_end_stream=1) | DB 설정. chatgpt 동일 설정에서 정상 동작 확인됨 |
| 4-3 | 수정 가능 렌더링 필드 | choices[0].delta.content | OpenAI 호환 형식의 표준 텍스트 필드 |
| 4-4 | 비표준 프로토콜 | NO | 표준 SSE |
| 4-5 | 필드 수정 부작용 | NO (예상) | content 필드 수정은 텍스트 표시만 변경 |
| 4-6 | 대안 전달 방식 | 해당 없음 (SSE 표준 전달 시도) | SSE_STREAM_WARNING 패턴 사용 |

</details>
