# APF Warning Pipeline Status
Updated: 2026-03-26 09:00 KST

## Service Status

| # | Service | Block | Warning | Status | Notes |
|---|---------|-------|---------|--------|-------|
| 1 | ChatGPT | ✅ | ✅ | **DONE** | SSE delta working |
| 2 | Claude | ✅ | ✅ | **DONE** | SSE content_block_delta working |
| 3 | Perplexity | ✅ | ✅ | **DONE** | SSE working |
| 4 | Gemini | ✅ | ✅ | **DONE** | JSON batch working |
| 5 | Clova-X | ✅ | ✅ | **DONE** | SSE working |
| 6 | Notion | ✅ | ❌ | **DEFERRED** | Strike 4. Multiple endpoints blocked → frontend stalls. Silent block. |
| 7 | Gamma | ✅ | ❌ | **DEFERRED** | Strike 5. SSE data delivered but outline parser ignores text. Silent block. |
| 8 | Genspark | ✅ | ❌ | **BLOCKED** | Frontend changed to Super Agent 3.0. HAR re-capture needed. |
| 9 | Copilot | ✅ | ❌ | **DEFERRED** | Strike 4+. Server writes succeed but browser receives empty EventStream. Silent block. |
| 10 | Wrtn | ✅ | ❓ | **NEXT** | Warning implementation pending. |

## Summary
- **DONE**: 5/10 (ChatGPT, Claude, Perplexity, Gemini, Clova-X)
- **DEFERRED** (silent block): 3/10 (Notion, Gamma, Copilot)
- **BLOCKED** (needs HAR re-capture): 1/10 (Genspark)
- **NEXT**: 1/10 (Wrtn)
