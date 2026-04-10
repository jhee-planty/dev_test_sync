-- qwen3: SSE streaming at /api/v2/chat/completions
-- Update service config: h2_mode=2 (keep-alive), h2_hold_request=1, path narrowed
UPDATE ai_prompt_services
SET h2_mode = 2,
    h2_hold_request = 1,
    h2_goaway = 0,
    h2_end_stream = 0,
    path_patterns = '/api/v2/chat/completions',
    response_type = 'qwen3_sse'
WHERE service_name = 'qwen3';

-- you.com: Next.js JSON at /_next/data/... and /search
-- h2_mode=2, h2_hold_request=1, keep path=/search (covers page load + API)
UPDATE ai_prompt_services
SET h2_mode = 2,
    h2_hold_request = 1,
    h2_goaway = 0,
    h2_end_stream = 0,
    response_type = 'you_json'
WHERE service_name = 'you';

-- blackbox: API is at useblackbox.io (different domain)
-- But *.blackbox.ai covers frontend → page-load interception will work
-- h2_mode=2, h2_hold_request=1 for page-load HTML warning
UPDATE ai_prompt_services
SET h2_mode = 2,
    h2_hold_request = 1,
    h2_goaway = 0,
    h2_end_stream = 0,
    response_type = 'blackbox_page'
WHERE service_name = 'blackbox';

-- qwen3 SSE template (similar to chatgpt/claude pattern)
INSERT INTO ai_prompt_response_templates (service_name, response_type, template_data)
VALUES ('qwen3', 'qwen3_sse', CONCAT(
  'HTTP/1.1 200 OK\r\n',
  'Content-Type: text/event-stream\r\n',
  'Cache-Control: no-cache\r\n',
  'Connection: keep-alive\r\n',
  '\r\n',
  'data: {"choices":[{"delta":{"content":"[경고] 민감한 개인정보가 포함된 메시지가 감지되었습니다. 보안 정책에 따라 해당 요청이 차단되었습니다. 개인정보(주민등록번호, 전화번호, 주소 등)를 AI 서비스에 입력하지 마세요."},"index":0,"finish_reason":"stop"}],"model":"blocked","id":"{{UUID:chatcmpl}}"}\n\n',
  'data: [DONE]\n\n'
));

-- you.com JSON error template (Next.js compatible)
INSERT INTO ai_prompt_response_templates (service_name, response_type, template_data)
VALUES ('you', 'you_json', CONCAT(
  'HTTP/1.1 200 OK\r\n',
  'Content-Type: application/json\r\n',
  'Cache-Control: no-cache\r\n',
  '\r\n',
  '{"pageProps":{"error":true,"message":"[경고] 민감한 개인정보가 포함된 메시지가 감지되었습니다. 보안 정책에 따라 해당 요청이 차단되었습니다. 개인정보(주민등록번호, 전화번호, 주소 등)를 AI 서비스에 입력하지 마세요."},"__N_SSP":true}'
));
