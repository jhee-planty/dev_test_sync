# H2 500B Ceiling Experiment — Final Report (2026-04-20)

## Experiment Goal
Determine whether H2 DATA frame size causes ERR_HTTP2_PROTOCOL_ERROR
at ~500B boundary for h2_end_stream=2 services (deepseek).

## Configuration
- Target: deepseek (h2_end_stream=2, h2_mode=2, h2_goaway=0)
- Method: response_type swap → reload_services → check-warning on test PC
- 4 envelope sizes tested: 249B, 476B, 935B, 1463B

## Results

| Step | response_type | Envelope | ERR_HTTP2 | Warning Displayed | Status |
|------|--------------|----------|-----------|-------------------|--------|
| 1 | deepseek_exp_200 | 249B | NO | NO (INVALID_JSON) | FAIL |
| 2 | deepseek_sse | 476B | NO | NO (blank chat) | PARTIAL |
| 3 | deepseek_exp_1k | 935B | NO | YES ✓ | SUCCESS |
| 4 | deepseek_exp_2k | 1463B | NO | NO (network error) | FAIL |

## Key Findings

### 1. 500B Ceiling Hypothesis: DISPROVEN
No ERR_HTTP2_PROTOCOL_ERROR occurred at any size (249B–1463B).
The previously observed ERR_HTTP2 was NOT caused by H2 DATA frame size.

### 2. Root Cause: SSE Envelope Format Compatibility
The real issue is DeepSeek's frontend SSE parser (Lyla HTTP client):
- Too small (249B): Missing SSE fields → JSON parse error (INVALID_JSON)
- Incomplete (476B): SSE parsed but insufficient fields → blank DOM
- Sweet spot (935B): All required SSE fields present → warning rendered ✓
- Too large (1463B): Extra fields cause parser to fail silently → network error

### 3. Sweet Spot Template: deepseek_exp_1k
The 935B envelope (deepseek_exp_1k) is the only size that successfully
renders the warning text. It includes:
- event: ready (with request/response message IDs)
- event: update_session (with timestamp)
- Main data payload with full response object structure
- Accumulated token usage update
- Status = FINISHED update
- event: close

### 4. What Was Missing in Smaller Templates
- deepseek_exp_200 (249B): Only had data + close event. Lyla tried JSON.parse()
  instead of SSE parsing → INVALID_JSON
- deepseek_sse (476B): Had data + close but missing event: ready, event: update_session,
  and incremental patch fields → SSE consumed but nothing rendered

### 5. What Broke in Larger Template
- deepseek_exp_2k (1463B): Had extra metadata, thinking_content, tool_calls,
  session title, UUID fields → parser could not process the extra complexity

## Action Items

1. **DONE**: Set deepseek response_type to deepseek_exp_1k (working template)
2. **TODO**: Apply deepseek_exp_1k pattern to other h2_end_stream=2 services
3. **TODO**: Update apf-technical-limitations.md — remove 500B ceiling as limitation
4. **TODO**: Document sweet-spot template pattern in references/phase2-analysis-registration.md
5. **TODO**: Re-examine previously failed services that were attributed to 500B ceiling

## Previous ERR_HTTP2 Root Cause (Revised Hypothesis)
Since frame size is not the cause, the previously observed ERR_HTTP2 errors
were likely caused by:
- Malformed SSE envelope triggering frontend to abort the H2 stream
- Or timing-related issues with delayed END_STREAM (h2_end_stream=2)
- Not by H2 protocol violations from oversized DATA frames

## DB State After Experiment
- deepseek response_type = deepseek_exp_1k (success template, kept active)
- Experiment templates (deepseek_exp_200, deepseek_exp_2k) remain in DB for reference
