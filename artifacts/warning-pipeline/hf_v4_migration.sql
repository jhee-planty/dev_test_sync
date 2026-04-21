-- HuggingFace v4 envelope migration
-- Strategy: h2_end_stream=0 (never close stream) to prevent invalidateAll() wipe
-- Root cause: HF chat-ui calls invalidateAll() in finally block after stream ends,
-- which fetches GET /api/v2/conversations/{id} -> messages=[] -> UI wipe.
-- Fix: never send END_STREAM so the for-await loop never exits.

DELETE FROM ai_prompt_response_templates WHERE service_name='huggingface' AND response_type IN ('huggingface_ndjson_v3','huggingface_ndjson_v4');

INSERT INTO ai_prompt_response_templates (service_name, http_response, response_type, envelope_template) VALUES ('huggingface', '⚠️ 민감정보가 포함된 요청은 보안 정책에 의해 차단되었습니다.\n\nThis request has been blocked due to sensitive information detected.', 'huggingface_ndjson_v4', CONCAT('HTTP/1.1 200 OK\r\nContent-Type: application/jsonl\r\nCache-Control: no-cache\r\nContent-Length: {{BODY_INNER_LENGTH}}\r\n\r\n', '{"type":"status","status":"started"}\n{"type":"stream","token":"{{MESSAGE}}"}\n{"type":"finalAnswer","text":"{{MESSAGE}}","interrupted":false}\n'));

UPDATE ai_prompt_services SET response_type='huggingface_ndjson_v4', h2_end_stream=0 WHERE service_name='huggingface';

UPDATE etap_APF_sync_info SET revision_cnt=revision_cnt+1 WHERE table_name='ai_prompt_services';
UPDATE etap_APF_sync_info SET revision_cnt=revision_cnt+1 WHERE table_name='ai_prompt_response_templates';
