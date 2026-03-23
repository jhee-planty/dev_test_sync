## Notion AI — Warning Design (Updated 2026-03-20)

### Strategy
- Pattern: JSON_ERROR_WARNING (similar to Gamma)
- HTTP/2 strategy: A (END_STREAM=true, GOAWAY=true)
  - Rationale: Notion uses standard REST JSON API (www.notion.so/api/v3/), not streaming.
- Based on: Phase 1 result (queue 113) + existing code analysis

### Response Specification
- HTTP Status: 403 Forbidden
- Content-Type: application/json; charset=utf-8
- Body format: JSON error object
  ```json
  {
    "errorId": "apf-block-{uuid8}",
    "name": "ContentPolicyError",
    "message": "{escaped_warning_text}"
  }
  ```
- Warning text: "⚠️ [보안 경고] 입력하신 내용에 민감한 정보가 포함되어 있어 전송이 차단되었습니다."
- JSON escaping: Standard (single-level)
- CORS: access-control-allow-origin: https://www.notion.so
- end_stream: true
- GOAWAY: yes

### Frontend Rendering Prediction
- Warning appears in: Notion AI response panel (within page editor)
- Rendered as: Error message in AI popup
- User experience: AI popup shows error instead of generated content
- Known artifacts: Contenteditable automation fails — manual testing required

### Test Criteria
- [ ] Warning text visible in Notion AI response area
- [ ] Page does not crash or reload
- [ ] No console errors that break page functionality
- [ ] Error message is readable (not raw JSON)

### Test Log Points
- Log point 1: Service detection (notion matched by domain/path)
- Log point 2: Block response generated (body size, status)
- Log point 3: Response write success/failure

### Relationship to Existing Code
- Existing generator: `generate_notion_block_response()` (ai_prompt_filter.cpp:1780)
- Registered: `_response_generators["notion"]` (line 131)
- Declaration: ai_prompt_filter.h:518
- Changes needed: NONE — already implemented
- is_http2 value: 0 (HTTP/1.1 response format in code)
- Shared approach with: Gamma (JSON error pattern)
- DB patterns: service_name="notion", domain="www.notion.so", path="/api/v3/"

### Notes
- Automation challenge: Notion's contenteditable rejects SendKeys/clipboard/JS
- Phase 3 testing will require manual prompt input on test PC
- Generator code already exists and follows JSON error pattern similar to Gamma
