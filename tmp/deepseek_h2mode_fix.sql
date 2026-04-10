-- DeepSeek: h2_mode=1 (GOAWAY) → h2_mode=2 (keep-alive) for SSE delivery
-- GOAWAY kills connection before SSE response body can be read by client
-- keep-alive allows full SSE template delivery
UPDATE etap.ai_prompt_services 
SET h2_mode = 2, h2_goaway = 0, h2_end_stream = 0
WHERE service_name = 'deepseek';

-- Verify
SELECT service_name, h2_mode, h2_goaway, h2_end_stream, h2_hold_request, response_type 
FROM etap.ai_prompt_services WHERE service_name = 'deepseek';
