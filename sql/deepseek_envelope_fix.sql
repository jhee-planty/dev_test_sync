-- DeepSeek SSE 템플릿 수정:
-- 1. {{MESSAGE}} → {{ESCAPE2:MESSAGE}} (이중 이스케이프, JSON 내부의 JSON)
-- 2. CRLF(\r\n) 정규화 (현재 LF만 사용 중)
-- 3. Content-Length 제거 → SSE는 Content-Length 없이 전송하는 것이 표준
--    (하지만 recalculate_content_length가 자동 재계산하므로 무관)

UPDATE ai_prompt_response_templates
SET envelope_template = CONCAT(
  'HTTP/1.1 200 OK\r\n',
  'Content-Type: text/event-stream; charset=utf-8\r\n',
  'Cache-Control: no-cache\r\n',
  'access-control-allow-origin: https://chat.deepseek.com\r\n',
  'access-control-allow-credentials: true\r\n',
  '\r\n',
  'event: message\r\ndata: {"v":"","p":"/choices/0/delta","o":"replace"}\r\n\r\n',
  'event: message\r\ndata: {"v":"{{ESCAPE2:MESSAGE}}","p":"/choices/0/delta/content","o":"append"}\r\n\r\n',
  'event: message\r\ndata: {"v":"stop","p":"/choices/0/finish_reason","o":"replace"}\r\n\r\n',
  'event: close\r\ndata: {"click_behavior":"close"}\r\n\r\n'
)
WHERE id = 26 AND response_type = 'deepseek_sse';
