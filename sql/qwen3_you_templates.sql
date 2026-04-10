-- qwen3 SSE template (OpenAI-compatible chat completions format)
INSERT INTO ai_prompt_response_templates (service_name, response_type, http_response, envelope_template, description)
VALUES (
  'qwen3',
  'qwen3_sse',
  '[경고] 민감한 개인정보가 포함된 메시지가 감지되었습니다. 보안 정책에 따라 해당 요청이 차단되었습니다. 개인정보(주민등록번호, 전화번호, 주소 등)를 AI 서비스에 입력하지 마세요.',
  CONCAT(
    'data: {"choices":[{"delta":{"content":"{{ESCAPE2:MESSAGE}}"},"index":0,"finish_reason":"stop"}],"model":"blocked","id":"{{UUID:chatcmpl}}"}\n\n',
    'data: [DONE]\n\n'
  ),
  'Qwen3 SSE streaming response with warning'
);

-- you.com JSON template (Next.js pageProps format)
INSERT INTO ai_prompt_response_templates (service_name, response_type, http_response, envelope_template, description)
VALUES (
  'you',
  'you_json',
  '[경고] 민감한 개인정보가 포함된 메시지가 감지되었습니다. 보안 정책에 따라 해당 요청이 차단되었습니다. 개인정보(주민등록번호, 전화번호, 주소 등)를 AI 서비스에 입력하지 마세요.',
  '{"pageProps":{"error":true,"message":"{{ESCAPE2:MESSAGE}}"},"__N_SSP":true}',
  'You.com Next.js JSON error response with warning'
);
