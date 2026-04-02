## Grok — Warning Design (Updated 2026-04-01)

### Phase 1 Inspection
- accessible: true, login_required: false (basic chat)
- etap_proxy_active: true, protocol: h2
- comm_type: NDJSON streaming (NOT SSE, NOT single JSON)
- API: POST grok.com/rest/app-chat/conversations/new
- Content-Type: application/json (response)
- WebSocket: 없음

### Response Format (#113 HAR 확인)
- NDJSON: 여러 JSON 객체가 }{ 경계로 연속
- Chunk 1: `{"result":{"conversation":{...}}}` — conversation metadata
- Chunk 2: `{"result":{"response":{"userResponse":{...}}}}` — user echo
- Chunk 3+: `{"result":{"response":{"token":"텍스트","isThinking":false,"isSoftStop":false,"messageTag":"final"}}}` — tokens
- Error: `{"result":{"response":{"error":{"message":"...","severity":"STREAM_ERROR_SEVERITY_FATAL"}}}}}`
- Model: grok-4-auto

### Strategy
- Pattern: NDJSON_STREAM_WARNING (custom — Grok-specific)
- HTTP/2 strategy: D (is_http2=2 keep-alive, END_STREAM=true, GOAWAY=false)
- Content-Type: application/json

### Response Specification (Build Phase3-B4)
- HTTP Status: 200 OK
- Content-Type: application/json
- Body: NDJSON — conversation chunk + token chunk with warning
- token chunk: messageTag="final" + warning text in "token" field
- end_stream: true, GOAWAY: false

### Build History
| Build | 방식 | 결과 |
|-------|------|------|
| B1 | SSE (OpenAI chat.completion.chunk) | 400 Bad Request (#097) |
| B2 | JSON error | 자체 에러 UI (#105) |
| B3 | SSE + is_http2=2 | BLOCKED_NO_WARNING (#111) |
| B4 | NDJSON (#113 HAR 기반) | PENDING (#115) |

### Existing Code
- Generator: generate_grok_sse_block_response (line ~1654)
- DB: grok service_id로 등록
- is_http2=2 (keep-alive group)
