## Notion AI — Warning Design

### Strategy
- Pattern: TBD (awaiting HAR capture result #089)
- HTTP/2 strategy: TBD
  - Rationale: Will be determined based on protocol analysis in Phase 1 inspection
- Based on: Notion AI is integrated into Notion's custom React application

### Response Specification
- HTTP Status: TBD (likely 200 for streaming or 403 for rejection)
- Content-Type: TBD (likely text/event-stream OR application/json)
- Body format: TBD
  - If streaming: SSE events (likely custom event type similar to Notion's internal format)
  - If REST: JSON error or completion object
- Warning text: "⚠️ [보안 경고] 입력하신 내용에 민감한 정보가 포함되어 있어 전송이 차단되었습니다."
- JSON escaping: Standard (single-level)
- end_stream: TBD
- GOAWAY: TBD

### Frontend Rendering Prediction
- Warning appears in: Notion page editor (in AI response panel)
- Rendered as: AI response text or error message
- Known artifacts: TBD based on Notion's implementation

### Test Criteria
- [ ] Capture HAR file for Notion AI request/response
- [ ] Analyze protocol and response format
- [ ] Determine if streaming or polling API
- [ ] Identify content fields where warning text appears
- [ ] Verify warning renders in Notion UI
- [ ] Verify request is blocked without generating content

### Relationship to Existing Code
- Existing generator: NONE (new service, needs implementation)
- Required implementations:
  1. `generate_notion_sse_block_response()` or `generate_notion_json_block_response()` in ai_prompt_filter.cpp
  2. Registration in `_response_generators` map: `_response_generators["notion"] = ...`
  3. Include corresponding declarations in ai_prompt_filter.h
- Changes needed: 
  - New generator function (type TBD)
  - Registration in module initialization
  - Header declarations
- DB patterns needed:
  - `service_name`: "notion"
  - `domain_pattern`: "TBD - pending capture result 089" (estimated: notion.so OR api.notion.com)
  - `path_pattern`: TBD (Notion's API routing pattern)

### Known Issues
- **Complete unknown**: Notion AI API protocol not yet analyzed
  - Waiting for HAR capture result #089
  - No existing generator code to reference
  - Need HAR analysis before implementation
- **Priority**: This is a NEW service requiring full implementation
  - Most effort will be in HAR analysis and protocol reverse-engineering
  - Generator implementation will follow once protocol is understood

### Implementation Workflow
1. Receive HAR capture result #089
2. Analyze request/response structure and protocol type
3. Document findings in this design
4. Implement generator function in ai_prompt_filter.cpp
5. Register generator in module initialization
6. Add DB patterns to ai_prompt_services table
7. Implement and test

### Questions Requiring HAR Analysis
- Is the API SSE (text/event-stream) or REST polling (JSON)?
- What is the exact domain for Notion AI requests?
- What HTTP path/endpoint is used for AI requests?
- What JSON/SSE format is used for responses?
- Are there multiple event types or a single response format?
- What fields contain the AI response text?
- How does Notion's frontend handle errors or non-200 responses?
