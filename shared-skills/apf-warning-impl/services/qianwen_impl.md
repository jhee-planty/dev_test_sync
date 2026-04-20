# qianwen — Implementation Journal

## Service Info
- service_name: qianwen
- domains: tongyi.ai, *.tongyi.ai, chat2.qianwen.com, qianwen.com, *.qianwen.com, tongyi.aliyun.com, *.tongyi.aliyun.com
- response_type: openai_compat_sse (shared template)
- envelope: SSE (data: {choices:[{delta:{content:...}}]})
- Prior classification: BLOCK_ONLY (CORS + ERR_HTTP2)

## DB State (2026-04-20 confirmed)
- h2_mode=1, h2_end_stream=1, h2_goaway=1, h2_hold_request=0, block_mode=1
- envelope has Access-Control-Allow-Origin: * (CORS already present)
- http_response: 159 bytes (warning text with emoji)

## Classification Review (2026-04-20)

status.md classified qianwen as BLOCK_ONLY with "DB변경 불가(❌)" — this is INCORRECT.
- DB has valid response template (openai_compat_sse, 342B envelope)
- CORS header already present in envelope
- The ERR_HTTP2 component may be caused by h2_end_stream=1 (immediate END_STREAM)
- h2_end_stream=2 (deepseek success pattern) has not been tried

Reclassifying: BLOCK_ONLY → testing (h2_end_stream=2 trial)

---

### Iteration 1 (2026-04-20) — STARTED
- Strategy: h2_end_stream=2 (delayed END_STREAM, deepseek pattern)
- Plan: Change h2_end_stream from 1 to 2 via DB, reload_services, push check-warning
- DB change: UPDATE ai_prompt_services SET h2_end_stream=2 WHERE service_name='qianwen';
- Hypothesis: ERR_HTTP2 caused by immediate END_STREAM closing stream before SSE parser processes data.
  Delayed END_STREAM (10ms gap) allows event loop to yield chunk to ReadableStream iterator.
- CORS: Access-Control-Allow-Origin: * already in envelope — if this causes issues with credentials,
  will need to change to specific origin (https://tongyi.aliyun.com) in Iteration 2.
- Files to modify: DB only (no C++ change, no build needed)
