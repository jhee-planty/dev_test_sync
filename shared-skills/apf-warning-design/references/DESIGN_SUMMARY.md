# Phase 2 Warning Design — 6 AI Services

## Summary

Created comprehensive design documents for 6 AI services in the EtapV3 APF (AI Prompt Filter) warning pipeline. Documents follow the Phase 1 inspection results and existing code analysis.

## Documents Created

All files are located in `/sessions/busy-relaxed-wright/tmp/`:

### 1. Gemini
**File**: `gemini_design.md`
- **Pattern**: WEBCHANNEL_WARNING (Google's proprietary protocol)
- **HTTP/2 Strategy**: D (END_STREAM=true, GOAWAY=false)
- **Status**: Implementation complete, verified in code
- **Generator**: `generate_gemini_block_response()` (line 1494)
- **Key Detail**: Must use HTTP 200 (not 403) or frontend silently ignores response
- **Code Changes**: None needed
- **DB Changes**: Verify patterns: signaler-pa.clients6.google.com + /punctual/multi-watch/channel

### 2. Grok
**File**: `grok_design.md`
- **Pattern**: SSE_STREAM_WARNING (OpenAI-compatible format)
- **HTTP/2 Strategy**: A (END_STREAM=true, GOAWAY=true)
- **Status**: Implementation complete, uncertainty on rendering
- **Generator**: `generate_grok_sse_block_response()` (line 1574)
- **Key Detail**: Grok shows its own error UI instead of our SSE text - needs verification
- **Code Changes**: None needed
- **DB Changes**: Verify patterns: grok.com + /api/chat/completions (TBD from HAR)
- **Risk**: Frontend rendering behavior uncertain

### 3. GitHub Copilot
**File**: `github_copilot_design.md`
- **Pattern**: SSE_STREAM_WARNING (custom message_delta/message_end events)
- **HTTP/2 Strategy**: A (END_STREAM=true, GOAWAY=true)
- **Status**: Implementation complete, DB registration incorrect
- **Generator**: `generate_github_copilot_sse_block_response()` (line 1629)
- **Key Detail**: Previous DB registration used "github.com" (wrong), need api.individual.githubcopilot.com
- **Code Changes**: None needed
- **DB Changes**: MUST UPDATE domain_pattern from "github.com" to "api.individual.githubcopilot.com"
- **Priority**: HIGH - Fix DB pattern to prevent false positives

### 4. Gamma
**File**: `gamma_design.md`
- **Pattern**: JSON_ERROR_WARNING (REST API, not chat)
- **HTTP/2 Strategy**: A (END_STREAM=true, GOAWAY=true)
- **Status**: Implementation complete
- **Generator**: `generate_gamma_block_response()` (line 1736)
- **Key Detail**: Gamma is a presentation generator, not chat - uses polling REST API
- **Code Changes**: None needed
- **DB Changes**: Verify patterns: api.gamma.app + (/api/generate OR /v1.0/generations)
- **Note**: 403 status is correct here (unlike Gemini)

### 5. M365 Copilot
**File**: `m365_copilot_design.md`
- **Pattern**: SSE_STREAM_WARNING (copilotConversation events)
- **HTTP/2 Strategy**: A (END_STREAM=true, GOAWAY=true) - may need D
- **Status**: Implementation complete, API domain TBD
- **Generator**: `generate_m365_copilot_sse_block_response()` (line 1678)
- **Key Detail**: API domain not confirmed, waiting for HAR capture result #088
- **Code Changes**: None needed (CORS header may need adjustment once domain confirmed)
- **DB Changes**: DOMAIN AND PATH PATTERNS PENDING - awaiting capture result #088
- **Uncertainty**: Exact API domain (m365.cloud.microsoft vs substrate.office.com vs other)
- **Risk**: May need HTTP/2 strategy D if multiplexing causes issues

### 6. Notion AI
**File**: `notion_design.md`
- **Pattern**: TBD (awaiting analysis)
- **HTTP/2 Strategy**: TBD
- **Status**: NEW SERVICE - no existing implementation
- **Generator**: NONE YET - needs implementation
- **Key Detail**: Completely new service, requires full HAR analysis and implementation
- **Code Changes**: Required
  - Implement `generate_notion_[sse|json]_block_response()` function
  - Register in `_response_generators` map
  - Add header declarations
- **DB Changes**: ALL PATTERNS PENDING - awaiting capture result #089
- **Priority**: MEDIUM - New implementation, can follow after other services

## Status Summary

| Service | Generator Status | Code Changes | DB Changes | Blockers |
|---------|------------------|--------------|------------|----------|
| Gemini | Complete | None | Pattern verification | None |
| Grok | Complete | None | Pattern verification | Frontend rendering uncertainty |
| GitHub Copilot | Complete | None | URGENT: Fix domain | DB error fix |
| Gamma | Complete | None | Pattern verification | None |
| M365 Copilot | Complete | None | PENDING #088 | API domain TBD |
| Notion AI | NEW | REQUIRED | PENDING #089 | HAR analysis pending |

## Implementation Priority

1. **URGENT**: Fix GitHub Copilot DB domain pattern (github.com → api.individual.githubcopilot.com)
2. **BLOCKING**: Receive HAR capture #088 (M365 Copilot API domain and path)
3. **BLOCKING**: Receive HAR capture #089 (Notion AI protocol, domain, path)
4. **AFTER CAPTURES**: Implement Notion AI generator function
5. **VERIFY**: Grok frontend rendering behavior with live traffic

## Key Technical Insights

### Protocol Types
- **Webchannel** (Gemini): Double JSON escaping, XSS header, wrb.fr envelope
- **SSE Events** (ChatGPT, Grok, GitHub Copilot, M365): text/event-stream with JSON payloads
- **REST JSON Error** (Gamma): 403 status with error object
- **TBD** (Notion): Need HAR analysis

### HTTP/2 Strategies Used
- **Strategy A** (Standard): END_STREAM=true, GOAWAY=true (4 services)
- **Strategy D** (Connection preservation): END_STREAM=true, GOAWAY=false (Gemini)
- **Strategy TBD**: M365 may need D if multiplexing issues arise

### Code Status
- 5 generators already implemented and correct
- 1 generator (Notion) needs new implementation
- All generators use proper JSON escaping and Unicode support
- No code changes needed for existing 5 services

### DB Status
- 1 service has critical error: GitHub Copilot (domain pattern wrong)
- 2 services waiting for HAR captures (#088, #089)
- 3 services ready for pattern verification against capture files

## File Locations

All design documents are in `/sessions/busy-relaxed-wright/tmp/`:
```
gemini_design.md
grok_design.md
github_copilot_design.md
gamma_design.md
m365_copilot_design.md
notion_design.md
DESIGN_SUMMARY.md (this file)
```

Note: Original target directory `/sessions/busy-relaxed-wright/mnt/.skills/skills/apf-warning-design/services/` is read-only. Documents should be migrated once write access is available.
