# qianwen — Implementation Journal

## Service Info
- service_name: qianwen
- domains: tongyi.ai, *.tongyi.ai, chat2.qianwen.com, qianwen.com, *.qianwen.com, tongyi.aliyun.com, *.tongyi.aliyun.com
- response_type: qianwen_sse (dedicated template, native format)
- envelope: SSE (data:{sessionId:...,msgId:...,contents:[{contentType:"text",content:...}],msgStatus:"finished"})
- Prior classification: BLOCK_ONLY → testing (2026-04-20) → active iteration (2026-04-22)

## DB State (2026-04-22 current, revision 122/21)
- h2_mode=2, h2_end_stream=2, h2_goaway=0, h2_hold_request=1, block_mode=1
- response_type=qianwen_sse (dedicated, 416B)
- CORS: Access-Control-Allow-Origin: https://qianwen.com + Access-Control-Allow-Credentials: true
- Template format: qianwen native (sessionId, msgId, contents[], msgStatus, canShare, errorCode)
- http_response: 159 bytes (warning text with emoji)

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

### Iteration 3 (2026-04-22) — native SSE format + CORS fix (#522) — IN PROGRESS
- THREE simultaneous fixes:
  1. Template: openai_compat_sse → qianwen native format (reverse-engineered from qwen-free-api)
     - `data:{"sessionId":"..","msgId":"..","msgStatus":"finished","contents":[{"contentType":"text","role":"assistant","content":"WARNING"}],"canShare":true,"errorCode":""}`
  2. CORS: `Access-Control-Allow-Origin: *` → `https://qianwen.com` + `Access-Control-Allow-Credentials: true`
     - Page loads on qianwen.com, API on chat2.qianwen.com → cross-origin with credentials
  3. H2: h2_end_stream=2 (delayed END_STREAM, deepseek success pattern)
- DB: revision_cnt services=122, templates=21
- Fallback plan if #522 fails:
  - (A) CORS origin: try https://tongyi.aliyun.com instead
  - (B) h2_end_stream=0 (keep stream open, let frontend close on [DONE])
  - (C) Use #521 captured actual SSE format to refine template
