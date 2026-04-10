-- Gemini3: set h2_hold_request=1 so APF fully controls response
-- With h2_hold_request=0, APF tries to modify real server response → fails silently
-- With h2_hold_request=1, APF blocks request and returns its own response directly
UPDATE etap.ai_prompt_services 
SET h2_hold_request = 1
WHERE service_name = 'gemini3';

-- Verify
SELECT service_name, h2_mode, h2_hold_request, h2_goaway, h2_end_stream, response_type 
FROM etap.ai_prompt_services WHERE service_name = 'gemini3';
