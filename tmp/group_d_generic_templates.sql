-- Group D: Generic JSON error templates for services without HAR data
-- These provide a user-readable error message instead of raw 403
-- Can be refined later with service-specific formats after HAR capture

-- Template for you.com (search AI, path=/search)
INSERT INTO etap.ai_prompt_response_templates 
  (service_name, http_response, response_type, envelope_template, priority, enabled, description)
VALUES (
  'you',
  '⚠️ 민감정보가 포함된 요청은 보안 정책에 의해 차단되었습니다.',
  'you_json',
  CONCAT(
    'HTTP/1.1 200 OK\n',
    'Content-Type: application/json; charset=utf-8\n',
    'Cache-Control: no-cache\n',
    'Content-Length: 0\n\n',
    '{"error":true,"message":"{{MESSAGE}}","code":"CONTENT_BLOCKED"}'
  ),
  50, 1,
  'You.com generic JSON error'
);
