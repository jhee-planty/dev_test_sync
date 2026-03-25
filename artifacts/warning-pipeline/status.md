# APF Warning Pipeline Status
Updated: 2026-03-26 08:40 KST

## Service Status

| # | Service | Block | Warning | Status | Notes |
|---|---------|-------|---------|--------|-------|
| 1 | ChatGPT | ✅ | ✅ | **DONE** | SSE delta working |
| 2 | Claude | ✅ | ✅ | **DONE** | SSE content_block_delta working |
| 3 | Perplexity | ✅ | ✅ | **DONE** | SSE working |
| 4 | Gemini | ✅ | ✅ | **DONE** | JSON batch working |
| 5 | Clova-X | ✅ | ✅ | **DONE** | SSE working |
| 6 | Notion | ✅ | ❌ | **DEFERRED** | Strike 4+. Block works but warning not rendered. Multiple endpoints blocked → frontend stalls. Silent block for now. |
| 7 | Gamma | ✅ | ❓ | **TESTING** | Build #13: error:true removed. Task 190 pending. |
| 8 | Genspark | ✅ | ❌ | **BLOCKED** | Frontend changed to Super Agent 3.0. HAR re-capture needed. |
| 9 | Copilot | ✅ | ❌ | **DEFERRED** | 4+ failures. Server writes succeed but browser receives empty EventStream. Silent block for now. |
| 10 | Wrtn | ✅ | ❓ | **NOT STARTED** | |

## Build History (Recent)

| Build | Date | Service | Change | Result |
|-------|------|---------|--------|--------|
| #13 | 03-26 08:32 | Gamma | error:true removed, done:true only | Pending (Task 190) |
| #13 | 03-26 08:18 | Notion | patch-end + endedAt added | ❌ Warning not rendered (Strike 4) |
| #12 | 03-25 | Gamma | event:generation + done+error | ❌ Outline empty, error aborted |
| #11 | 03-25 | Copilot | message_delta+message_end SSE | ❌ EventStream EMPTY |
| #11 | 03-25 | Gamma | event:error SSE | ❌ EventStream EMPTY |

## Next Actions
1. Wait for Gamma Task 190 result
2. If Gamma works → mark DONE, move to next service
3. Genspark: needs HAR re-capture (Super Agent 3.0)
4. Notion/Copilot: deferred to silent block
