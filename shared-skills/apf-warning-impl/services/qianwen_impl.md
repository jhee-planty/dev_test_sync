# qianwen — Implementation Journal

## Service Info
- service_name: qianwen
- domains: tongyi.ai, *.tongyi.ai, chat2.qianwen.com, qianwen.com, *.qianwen.com, tongyi.aliyun.com, *.tongyi.aliyun.com
- response_type: qianwen_sse (dedicated template, native format)
- envelope: SSE (data:{sessionId:...,msgId:...,contents:[{contentType:"text",content:...}],msgStatus:"finished"})
- Prior classification: BLOCK_ONLY → testing (2026-04-20) → active iteration (2026-04-22)

## DB State (2026-04-22 current, revision 122/23)
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

### Iteration 3c (2026-04-22) — v4 template: Content-Length removed (#524) — IN PROGRESS
- Fix: Removed `Content-Length: 0` header from template (SSE streaming should have no Content-Length)
- Template size: 1167B → 1148B (v4)
- DB revision templates=23, etapd reload confirmed at 18:20:25
- #524 check-warning pushed
- Fallback plan if #524 fails:
  - (A) CORS origin: try https://tongyi.aliyun.com instead
  - (B) h2_end_stream=0 (keep stream open)
  - (C) Check if qianwen uses fetch() vs EventSource (different parsing behavior)
