-- DeepSeek SSE 템플릿 수정: Content-Length: 0 제거
-- SSE 스트리밍은 Content-Length 없이 전송해야 브라우저가 body를 읽음
-- Transfer-Encoding: chunked 추가하지 않음 — APF가 직접 body를 전송하므로 불필요
UPDATE ai_prompt_response_templates
SET envelope_template = CONCAT(
  'HTTP/1.1 200 OK\r\nContent-Type: text/event-stream; charset=utf-8\r\nCache-Control: no-cache\r\naccess-control-allow-origin: https://chat.deepseek.com\r\naccess-control-allow-credentials: true\r\n\r\n',
  'event: message\r\ndata: {"v":"","p":"/choices/0/delta","o":"replace"}\r\n\r\n',
  'event: message\r\ndata: {"v":"{{ESCAPE2:MESSAGE}}","p":"/choices/0/delta/content","o":"append"}\r\n\r\n',
  'event: message\r\ndata: {"v":"stop","p":"/choices/0/finish_reason","o":"replace"}\r\n\r\n',
  'event: close\r\ndata: {"click_behavior":"close"}\r\n\r\n'
)
WHERE id = 26 AND response_type = 'deepseek_sse';

-- Gemini3: CSP가 webchannel 템플릿을 차단하므로
-- 페이지 로드 인터셉트가 더 효과적. response_type을 비워서
-- 페이지 로드 시 HTML 경고 페이지를 반환하도록 전환
-- (API 레벨은 여전히 webchannel로 시도)
-- → gemini는 페이지 로드 인터셉트 + API 차단 병행

-- Meta.ai: 한국 접속 불가 → enabled 유지하되 메모 추가
-- (실제 접속 가능한 사용자가 있을 수 있으므로 비활성화하지 않음)
