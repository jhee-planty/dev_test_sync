# Phase 2 Review — 2026-03-20 (based on Phase 1 queues 120~125)

## Summary

All 6 services have existing design documents. Phase 1 re-capture validated most designs.
Key changes identified below.

## Service-by-Service Review

### Gemini ✅ No changes needed
- Design: WEBCHANNEL_WARNING, Strategy D
- Phase 1 confirms: batchexecute RPC, 200 OK response
- Consistent

### Grok ✅ No changes needed
- Design: SSE_STREAM_WARNING, Strategy A
- Phase 1 reveals REST fetch for short responses, but SSE for streaming
- Design targets the streaming path (where block response intercepts), so still valid

### Gamma ⚠️ DB domain update needed
- Design: JSON_ERROR_WARNING, Strategy A, 403 Forbidden
- Phase 1 reveals: AI generation uses `ai.api.gamma.app/ai/v2/generation`
- Current DB may only have `api.gamma.app` → need to add `ai.api.gamma.app`
- **Action**: Verify DB patterns include `ai.api.gamma.app`

### GitHub Copilot ✅ No changes needed
- Design: SSE_STREAM_WARNING, Strategy A
- Phase 1 confirms: api.individual.githubcopilot.com
- Consistent

### M365 Copilot ✅ No changes needed (automation now possible)
- Design: SSE_STREAM_WARNING with copilotConversation events
- Phase 1 reveals: SendKeys works now (previous "manual_input_required" is outdated)
- Design is valid, testing is now feasible

### Notion AI — Design UPDATED (was TBD)
- Pattern: JSON_ERROR_WARNING (same as Gamma)
- HTTP/2 strategy: A (END_STREAM=true, GOAWAY=true)
- HTTP Status: 403 Forbidden
- Content-Type: application/json; charset=utf-8
- Body: `{"errorId":"apf-block-{uuid8}","name":"ContentPolicyError","message":"{warning}"}`
- Code: `generate_notion_block_response()` already implemented (ai_prompt_filter.cpp:1780)
- DB: service_name="notion", domain="www.notion.so", path="/api/v3/"
- SendKeys works on notion.so/chat interface
- Phase 1 confirms: Fetch API pattern, syncRecordValues-based sync

## Phase 3 Readiness

All 6 services have:
- ✅ Design documents (existing or updated)
- ✅ C++ generator functions registered
- ✅ Frontend profiles from Phase 1

**Blocking issue**: Gamma DB domain may need `ai.api.gamma.app` in addition to `api.gamma.app`.
This should be verified during Phase 3 testing.
