-- Meta AI: Create GraphQL error response template
-- Meta AI uses GraphQL at /api/graphql/
-- Return a GraphQL-compatible error response

-- First, add http_response (plain text message) for meta
INSERT INTO etap.ai_prompt_response_templates 
  (service_name, http_response, response_type, envelope_template, priority, enabled, description)
VALUES (
  'meta',
  '⚠️ 민감정보가 포함된 요청은 보안 정책에 의해 차단되었습니다.',
  'meta_graphql',
  CONCAT(
    'HTTP/1.1 200 OK\n',
    'Content-Type: application/json; charset=utf-8\n',
    'Cache-Control: no-cache\n',
    'access-control-allow-origin: https://www.meta.ai\n',
    'access-control-allow-credentials: true\n',
    'Content-Length: 0\n\n',
    '{"errors":[{"message":"{{MESSAGE}}","extensions":{"code":"CONTENT_BLOCKED","classification":"POLICY_VIOLATION"}}],"data":null}'
  ),
  50,
  1,
  'Meta AI GraphQL error response — content policy block'
);

-- Update meta service to use the new response_type
UPDATE etap.ai_prompt_services 
SET response_type = 'meta_graphql',
    h2_mode = 2,
    h2_hold_request = 1
WHERE service_name = 'meta';

-- Verify
SELECT s.service_name, s.response_type, s.h2_mode, s.h2_hold_request,
       t.id, LENGTH(t.envelope_template) as env_len
FROM ai_prompt_services s 
LEFT JOIN ai_prompt_response_templates t ON t.service_name = s.service_name
WHERE s.service_name = 'meta';
