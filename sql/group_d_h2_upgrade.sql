-- Group D: 템플릿 없는 13개 서비스를 h2_mode=2 + h2_hold_request=1로 업그레이드
-- 페이지 로드 인터셉트(Accept: text/html 감지 → HTML 경고 페이지)가 자동 동작하게 됨
-- API 레벨 템플릿은 개별 서비스 조사 후 추가

UPDATE ai_prompt_services
SET h2_mode = 2,
    h2_hold_request = 1,
    h2_goaway = 0,
    h2_end_stream = 0
WHERE service_name IN (
  'baidu', 'character', 'chatglm', 'cohere', 'consensus',
  'dola', 'huggingface', 'kimi', 'phind', 'poe',
  'qianwen', 'v0', 'wrtn'
) AND block_mode = 1;

-- character.ai: WebSocket 서비스 → on_upgraded() 콜백이 처리
-- poe.com: GraphQL over WebSocket → on_upgraded() 콜백이 처리
-- 둘 다 페이지 로드 인터셉트로도 경고 가능

-- huggingface: path=/chat 유지 (비AI 콘텐츠 보호)
-- 나머지: path=/ (전체 경로 매칭, 페이지 로드만 인터셉트)
