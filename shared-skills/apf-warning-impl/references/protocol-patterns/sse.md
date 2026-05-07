# Server-Sent Events (SSE) Pattern

## Mechanism
- Long-lived HTTP connection, server push chunked text
- Each chunk: `event: {name}\ndata: {json}\n\n` separated by `\n\n`
- HTTP/2 streaming or HTTP/1.1 chunked transfer

## Engine emit
- `on_http2_response_data` hook → APF engine intercepts SSE chunks
- `[APF:block_response]` event fire when PII detected in stream
- Production log: `grep '[APF:block_response]' /var/log/etap/etap.log | grep service={service}`

## Envelope schema requirements (general)
- SSE final-message format must match service SPA expectation
- Common: `data: {"type": "...", "content": "..."}` JSON object
- Some services: multi-event sequence (`event: started → running → applied`)

## Common pitfalls (47-56차 evidence)
- **Wrong endpoint targeting**: perplexity 7 deploys (V7-D~F) targeted `/rest/thread/<UUID>` (NEVER triggered), actual SSE endpoint = `/rest/sse/perplexity_ask` (49-56차 evidence)
- **HAR limitation**: standard HAR export 가 SSE body 미캡처 (size > 0 but text empty). Streaming-aware capture 필요 (Chrome DevTools EventStream tab).
- **Schema validation**: SPA 가 새 required field 추가 시 silent-drop (no error). HAR groundtruth 필수.

## Verify path
- T1 (engine_fire): production log grep 결과 ≥ 1
- T2 (UI_render): test PC check-warning + expected_text match
- T3 (verify_path): `apf-operation/services/{service}/analysis.md` cause_pointer + verify path

## Cross-reference
- perplexity: `apf-operation/services/perplexity/` (operational state)
- mistral: `apf-operation/services/mistral/` (partial SSE on some endpoints)
