# BLOCK_ONLY 서비스 템플릿 분석 — deepseek 교훈 적용 검토
> Date: 2026-04-20
> 기반: deepseek sweet-spot 실험 (935B, SSE 파서 호환성이 핵심)

## 핵심 교훈 (deepseek에서 확인)

1. **H2 DATA 프레임 크기는 원인이 아님** — 249B~1463B 모두 ERR_HTTP2 미발생
2. **프론트엔드 SSE 파서 호환성이 핵심** — 프론트엔드가 기대하는 이벤트 시퀀스와 필드 구조를 정확히 맞춰야 함
3. **너무 작으면 INVALID_JSON, 너무 크면 파서 한계** — sweet spot 존재

## 서비스별 분석

### 1. Perplexity (h2_es=2, h2_mode=2) — 테스트 진행 중 (#488)

| 항목 | 값 |
|------|---|
| 현재 템플릿 | perplexity_sse (4225B) |
| 이전 시도 | perplexity_v3 (193B), perplexity_v2 (208B), perplexity_simple (172B) — 모두 실패 |
| 변경 근거 | deepseek 교훈 — 전체 SSE 이벤트 시퀀스 필요 |
| 위험 | 4225B가 프론트엔드에 과부하 줄 수 있음 (deepseek는 1463B에서 실패) |
| 대안 | 실패 시 이벤트 수를 줄인 중간 크기 템플릿 시도 |

### 2. Baidu ERNIE (h2_es=1, h2_mode=2) — Content-Length 문제 의심

| 항목 | 값 |
|------|---|
| 현재 템플릿 | baidu_sse_v2 (478B) |
| 실패 원인 | "ERNIE UI가 APF SSE 콘텐츠 무시" |
| **발견**: Content-Length: 0 | 실제 body ~450B인데 0으로 선언 |
| 이벤트 구조 | event:major + event:message (ERNIE 네이티브 형식) |
| 필드 구조 | is_end, sent_id, chat_id, isSafe, isBan 등 (적절) |
| **제안** | Content-Length: 0 → {{BODY_INNER_LENGTH}}로 변경 후 재테스트 |
| 기대 효과 | 중간 — 포맷은 적절하나 Content-Length 불일치가 원인이면 해결 가능 |

### 3. HuggingFace (h2_es=1, h2_mode=2) — Content-Length 문제 + NDJSON 포맷

| 항목 | 값 |
|------|---|
| 현재 템플릿 | huggingface_ndjson_v2 (321B) |
| 실패 원인 | "빈 채팅" — 스트리밍 중단 |
| **발견**: Content-Length: 0 | 실제 body ~300B인데 0으로 선언 |
| Content-Type | text/event-stream (SSE인데 NDJSON 본문) |
| **제안** | 1) Content-Length: {{BODY_INNER_LENGTH}} 2) Content-Type을 실제 전송 포맷과 일치시키기 |

### 4. v0.dev (h2_es=2, h2_mode=1) — HTML block page 방식의 한계

| 항목 | 값 |
|------|---|
| 현재 템플릿 | v0_html_block_page (124B) |
| 실패 원인 | "Thinking 무한" — SPA가 HTML 응답을 무시 |
| **발견**: Content-Length: 0 + Content-Type: text/html | SPA는 API 응답을 JSON으로 기대 |
| **제안** | v0_json (208B, JSON 에러) 템플릿으로 전환 시도. 단, h2_es=2이므로 deepseek 패턴 필요할 수 있음 |
| 추가 | v0 프론트엔드 HAR 분석 후 네이티브 SSE/JSON 형식 확인 필요 |

### 5. Gamma (h2_es=1, h2_mode=2) — 정상 포맷이나 400 상태 코드 문제

| 항목 | 값 |
|------|---|
| 현재 템플릿 | gamma_sse (286B, {{BODY_INNER_LENGTH}} 사용) |
| 실패 원인 | "생성 조용히 실패" |
| 포맷 | 400 Bad Request + application/json + CORS 헤더 |
| **분석** | Content-Length 정상, CORS 정상. 400 status code를 프론트엔드가 에러로 처리하되 사용자에게 표시 안 함 |
| **제안** | 200 OK로 변경 + SSE event-stream 포맷 시도 |

### 6. Qianwen (h2_es=1, h2_mode=2) — CORS + 포맷 복합 문제

| 항목 | 값 |
|------|---|
| 현재 템플릿 | qianwen_sse (497B, {{BODY_INNER_LENGTH}} 사용, CORS 포함) |
| 실패 원인 | "CORS + ERR_HTTP2 on chat2.qianwen.com" |
| **분석** | Access-Control-Allow-Origin: * 설정했으나, 실제 CORS preflight 처리가 APF에서 안 될 수 있음 |
| **제안** | CORS preflight(OPTIONS)가 정상 통과되는지 확인 필요. 이것은 인프라 수준 문제일 수 있음 |

### 7. Poe (h2_es=1, h2_mode=2) — GraphQL+SSE 과차단 위험

| 항목 | 값 |
|------|---|
| 현재 템플릿 | ws_fallback_error (216B) |
| 실패 원인 | "사이트 전체 크래시" — gql+receive 과차단 위험 |
| **분석** | WS fallback 에러로는 부적절. 하지만 poe는 GraphQL over WS → NEEDS_ALTERNATIVE 범주 |
| **제안** | WebSocket 인프라 완료 후 재검토 |

### 8. Wrtn (h2_es=1, h2_mode=2) — 차단 성공, 경고 테스트에 로그인 필요

| 항목 | 값 |
|------|---|
| 현재 상태 | Phase 4 완료 (#479), DB 키워드 수정 후 차단 성공 |
| **분석** | 경고 테스트에 로그인 필요 (NEEDS_USER_SESSION) |
| **제안** | 사용자 협업 세션에서 진행 |

## 우선순위 (개선 효과 기대 순)

| 순위 | 서비스 | 변경 | 난이도 | 기대 효과 |
|------|--------|------|--------|----------|
| 1 | perplexity | perplexity_sse 테스트 중 (#488) | 완료 | 높음 — 전체 SSE 시퀀스 |
| 2 | baidu | Content-Length: 0 → {{BODY_INNER_LENGTH}} | 낮음 (SQL만) | 중간 — 포맷은 이미 적절 |
| 3 | huggingface | Content-Length + Content-Type 수정 | 낮음 | 중간 |
| 4 | v0 | v0_json으로 전환 + 프론트엔드 분석 | 중간 | 중간 — SPA 호환 필요 |
| 5 | gamma | 200 OK + SSE 포맷 시도 | 중간 | 낮음 — 프론트엔드가 에러 숨김 |
| 6 | qianwen | CORS preflight 인프라 확인 | 높음 | 불확실 |

## 즉시 실행 가능 (DB UPDATE만으로 가능)

1. **baidu**: `UPDATE ai_prompt_response_templates SET envelope_template = REPLACE(envelope_template, 'Content-Length: 0', 'Content-Length: {{BODY_INNER_LENGTH}}') WHERE response_type = 'baidu_sse_v2';`
2. **huggingface**: 동일 Content-Length 수정
3. **v0**: `UPDATE ai_prompt_services SET response_type = 'v0_json' WHERE service_name = 'v0';`
