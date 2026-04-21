-- Baidu SSE v4 Migration: HTML Comment Delimiter Format
-- Date: 2026-04-21
-- Request: #511
-- Previous: baidu_sse_v3 (standard SSE event:/data: format — REJECTED by baidu JS parser)
-- Change: Use baidu's proprietary <!--chat-sse-data-start[type]:JSON...chat-sse-data-end--> protocol

-- 1. Insert v4 envelope template (HTML comment delimiter format)
INSERT INTO ai_prompt_response_templates (response_type, envelope_template)
VALUES ('baidu_sse_v4', CONCAT(
  'HTTP/1.1 200 OK', CHAR(13,10),
  'Content-Type: text/event-stream; charset=utf-8', CHAR(13,10),
  'Cache-Control: no-cache', CHAR(13,10),
  'Connection: keep-alive', CHAR(13,10),
  'Content-Length: 0', CHAR(13,10),
  CHAR(13,10),
  '<!--chat-sse-data-start[generator]:{"status":0,"data":{"message":{"content":{"text":"{{ESCAPE2:MESSAGE}}"},"metaData":{"endTurn":true,"state":"generate-complete","speedInfo":{},"logInfo":{}},"msgId":"apf-1"}},"sessionId":"apf","seq_id":1,"type":"text","qid":"apf-q"}chat-sse-data-end-->'
));

-- 2. Update service to use v4
UPDATE ai_prompt_services SET response_type='baidu_sse_v4' WHERE service_name='baidu';

-- 3. Trigger reload
UPDATE etap_APF_sync_info SET revision_cnt=revision_cnt+1 WHERE table_name='ai_prompt_services';
UPDATE etap_APF_sync_info SET revision_cnt=revision_cnt+1 WHERE table_name='ai_prompt_response_templates';

-- Verification:
-- SELECT response_type, LENGTH(envelope_template) FROM ai_prompt_response_templates WHERE response_type='baidu_sse_v4';
-- Expected: baidu_sse_v4, 421 bytes
-- SELECT config_type, revision_cnt FROM etap_APF_sync_info;
-- Expected: services=115, templates=17
