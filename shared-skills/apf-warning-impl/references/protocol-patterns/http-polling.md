# HTTP polling (request/response) Pattern

## Mechanism
- Standard HTTP request/response
- Client polls server periodically OR submits one-shot request
- Response: HTML document, JSON, or simple text
- No long-lived connection, no streaming

## Engine emit
- `on_http2_response_data` (or HTTP/1.1 equivalent)
- `[APF:block_response]` for direct response substitution

## Envelope schema requirements (general)
- Service-specific JSON or HTML response
- Direct content substitution (no streaming complications)
- Easier to engineer than SSE/WebSocket

## Common pitfalls (47-56차 evidence)
- **SPA SSR vs CSR**: server-rendered HTML response → engine substitution OK. Client-rendered (CSR) → SPA fetch 후 render, harder to intercept
- **Reload behavior**: hard reload 시 SSR document return 가능 (V6-D notion case 와 비슷)
- **HTTP/1.1 vs HTTP/2 substitution**: H1 single connection, H2 multiplexing — 둘 다 engine on_http2_response_data hook 으로 cover
- **gamma-style intent confirmation**: warning 표시 전 사용자 intent 확인 패턴 (gamma `pending_user_confirm:warning_slide_pattern_intent`)

## Verify path
- T1: production log for service endpoints
- T2: test PC verdict (simple — direct substitution)
- T3: per-service analysis

## Cross-reference
- gamma: `apf-operation/services/gamma/` (slide pattern intent)
- you.com: `apf-operation/services/you/` (V10 series — SSR HTML substitution)
- baidu: `apf-operation/services/baidu/` (cycle 92 hook deployment evidence)
