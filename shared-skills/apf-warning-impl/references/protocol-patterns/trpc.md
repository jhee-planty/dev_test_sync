# tRPC + superJSON Pattern

## Mechanism
- HTTP POST to `/api/trpc/{procedure}` (e.g., `message.newChat`)
- Body: JSON with superJSON serialization (preserves Date / Map / Set / etc)
- Response: tRPC envelope `{result: {data: ...}, error?: {...}}`
- Optional batch mode: `?batch=1` → array of operations

## Engine emit
- `on_http2_response_data` (similar to SSE/HTTP)
- `[APF:block_response]` when PII detected

## Envelope schema requirements (general)
- JSON.parse-able (NO truncation, NO syntax errors)
- superJSON top-level: `{json: ..., meta: ...}` for typed values
- Error envelope: `{error: {message, code, ...}}` (TRPCClientError class)

## Common pitfalls (47-56차 evidence — mistral)
- **JSON.parse SyntaxError**: V5-B engine generator bug — single-object body truncation. V5-A revert as known-better state (49-56차)
- **superJSON validation fail**: `Cannot convert undefined or null to object` — `meta` field omit 시 SPA crash
- **Batch mode mismatch**: batch=1 contracts ARRAY, single result returns `Object.keys(undefined)` TypeError (V7-F #654 evidence)
- **render_envelope_template + recalculate_content_length**: engine code path for body assembly. Bug source for single-object cases.

## Verify path
- T1: production log `[APF:block_response]` for tRPC endpoints
- T2: test PC verdict + SPA bubble render
- T3: per-service analysis with cause_pointer

## Cross-reference
- mistral: `apf-operation/services/mistral/` (V5-A V7-F 진행)
