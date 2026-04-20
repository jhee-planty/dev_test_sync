## H2 500B Ceiling Experiment — Step 1 Result (2026-04-20)

### Configuration
- response_type: deepseek_exp_200
- envelope_bytes: 249B
- h2_end_stream: 2, h2_mode: 2, h2_goaway: 0

### Result: NO ERR_HTTP2 (baseline confirmed)
- ERR_HTTP2_PROTOCOL_ERROR: **NOT observed** → 249B is below ceiling
- Warning text: NOT displayed (separate issue — format incompatibility)
- DeepSeek Lyla client does JSON.parse() on response body
- SSE format (data: {"v"...) → INVALID_JSON error
- User sees: generic "네트워크를 확인하고 다시 시도하세요"
- 2nd attempt: block bypassed entirely (h2_end_stream=2 keeps connection)

### Experiment Validity
The core question is "at what size does ERR_HTTP2 appear?"
- Step 1 (249B): No ERR_HTTP2 ✓ (expected)
- Step 2 (476B): Pending
- Step 3 (935B): Pending  
- Step 4 (1463B): Pending

Warning display failure is a separate issue (format, not size).
The ceiling experiment remains valid for detecting ERR_HTTP2 boundary.

### Next
Waiting for step 2 (476B, deepseek_sse) result from test PC.
DB already updated, reload done, request #485 pushed.
