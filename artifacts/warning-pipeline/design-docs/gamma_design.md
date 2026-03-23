## Gamma — Warning Design

### Strategy
- Pattern: JSON_ERROR_WARNING
- HTTP/2 strategy: A (END_STREAM=true, GOAWAY=true)
  - Rationale: Gamma uses poll-based REST API, not streaming. Standard HTTP error response applies.
- Based on: Gamma is a presentation/document generation tool using REST JSON API (not chat)

### Response Specification
- HTTP Status: 403 Forbidden
- Content-Type: application/json; charset=utf-8
- Body format: JSON error object
  ```json
  {
    "message": "{escaped_warning_text}",
    "statusCode": 403,
    "error": {
      "code": "CONTENT_POLICY_VIOLATION",
      "message": "{escaped_warning_text}"
    }
  }
  ```
- Warning text: "⚠️ [보안 경고] 입력하신 내용에 민감한 정보가 포함되어 있어 전송이 차단되었습니다."
- JSON escaping: Standard (single-level)
- end_stream: true
- GOAWAY: yes

### Frontend Rendering Prediction
- Warning appears in: Gamma generation form (React-based)
- Rendered as: Error toast or modal dialog with error code
- Known artifacts: May show "CONTENT_POLICY_VIOLATION" instead of our warning text depending on frontend error handling

### Test Criteria
- [ ] Send request with sensitive keyword to Gamma API (e.g., /api/generate or /v1.0/generations)
- [ ] Verify HTTP 403 Forbidden response received
- [ ] Verify JSON error structure has CONTENT_POLICY_VIOLATION code
- [ ] Verify warning text in both message and error.message fields
- [ ] Verify generation is blocked (no draft created)
- [ ] Verify React frontend properly renders error dialog

### Relationship to Existing Code
- Existing generator: `ai_prompt_filter::generate_gamma_block_response()` (implemented at line 1736)
- Current implementation: Complete
  - Proper HTTP 403 status
  - Correct JSON error structure with CONTENT_POLICY_VIOLATION code
  - Warning text in both top-level and nested error message fields
  - CORS headers for gamma.app
- Changes needed: None to generator code
- DB patterns needed:
  - `service_name`: "gamma"
  - `domain_pattern`: "api.gamma.app"
  - `path_pattern`: "/api/generate" OR "/v1.0/generations" (requires HAR analysis to determine which)

### Implementation Notes
- Gamma is unique: NOT a chat service but a presentation generator
- Uses REST JSON instead of SSE or streaming
- Poll-based API (POST request returns immediate status, not streaming response)
- 403 status is appropriate for policy violation (unlike Gemini where 403 causes silent failure)
- React frontend error handling may suppress or transform our warning text
