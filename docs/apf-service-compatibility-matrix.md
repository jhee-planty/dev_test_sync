# APF Service Compatibility Matrix — 2026-04-10 14:30

## 검증 결과 요약

| Tier | 서비스 수 | 설명 |
|------|----------|------|
| 1 — 경고 정상 | 5 | 사용자에게 한국어 경고 메시지 직접 표시 |
| 1.5 — 에러 표시 | 3 | 차단 동작, 서비스 자체 에러 UI 표시 (커스텀 경고 불가) |
| 2 — 리테스트 대기 | 2 | 수정 후 검증 필요 |
| 3 — 테스트 대기 | 19 | 템플릿 완비, 테스트 미실시 |
| 4 — 특수 환경 | 5 | IDE/로그인/리전 제한 |
| 비활성 | 1 | block_mode=0 |

## Tier 1 — 경고 정상 (5개)

| 서비스 | response_type | 프로토콜 | 검증 결과 | 비고 |
|--------|--------------|---------|----------|------|
| chatgpt | chatgpt_sse | SSE delta_encoding | #330 경고 채팅 버블 렌더링 | 가장 복잡한 템플릿 |
| claude | claude | SSE message_start | #346 접속 정상, 차단 시 경고 | Anthropic SSE 프로토콜 |
| genspark | genspark_sse | SSE project/message | 경고 정상 | 다중 이벤트 타입 |
| duckduckgo | duckduckgo_sse | SSE simple JSON | #310 채팅 버블 렌더링 | 가장 단순한 구현 |
| grok | grok_ndjson | NDJSON + redirect | #316 한국어 경고 배너 | APF redirect 방식 |

## Tier 1.5 — 에러 표시 (3개)

| 서비스 | response_type | 프로토콜 | 검증 결과 | 비고 |
|--------|--------------|---------|----------|------|
| mistral | mistral_trpc_sse | tRPC/NDJSON | #322,#326 Error 6002 | array-format NDJSON만 가능 |
| perplexity | perplexity_sse | SSE 6-event | #332 "스레드 없음" | thread ID 문제 |
| perfle | perplexity_sse | SSE 6-event | 실시간 차단 확인(14:23) | perplexity와 동일 이슈 |

## Tier 2 — 리테스트 대기 (2개)

| 서비스 | response_type | 수정 사항 | 대기 요청 |
|--------|--------------|----------|----------|
| deepseek | deepseek_sse | h2_end_stream=0→1 | #350 |
| gemini3 | gemini | Strategy D (503 에러) | #352 |

## Tier 3 — 테스트 대기 (19개)

### 3A: OpenAI-compatible SSE (4개)
| 서비스 | response_type | 포맷 | 비고 |
|--------|--------------|------|------|
| kimi | openai_compat_sse | choices[0].delta.content | Moonshot Platform 문서 확인 |
| huggingface | openai_compat_sse | choices[0].delta.content | HF TGI 문서 확인 |
| qianwen | openai_compat_sse | choices[0].delta.content | Alibaba Cloud 문서 확인 |
| chatglm | openai_compat_sse | choices[0].delta.content | Zhipu AI OpenAI-compat |

### 3B: 서비스 전용 포맷 (5개)
| 서비스 | response_type | 포맷 | 비고 |
|--------|--------------|------|------|
| cohere | cohere_sse | named events (stream-start/text-generation/stream-end) | Cohere API 문서 확인 |
| baidu | baidu_sse | SSE result 필드 | ERNIE 스트리밍 |
| qwen3 | qwen3_sse | OpenAI-compat | 별도 도메인 |
| blackbox | blackbox_json | JSON response | cross-domain: useblackbox.io |
| v0 | v0_json | JSON error | v0.dev 추가됨 |
| you | you_json | JSON answer | 검색+답변 형식 |

### 3C: generic_sse — 정보 부족 (9개)
| 서비스 | response_type | 주의사항 |
|--------|--------------|---------|
| character | generic_sse | WebSocket 서비스. HTTP fallback으로 차단 |
| poe | generic_sse | GraphQL/WebSocket. HTTP fallback |
| wrtn | generic_sse | 한국 서비스 |
| copilot | generic_sse | Bing Copilot, WebSocket |
| clova | generic_sse | Naver, h2_mode=1 |
| clova_x | generic_sse | Naver X, h2_mode=1 |
| phind | generic_sse | cross-domain: https.api.phind.com |
| consensus | generic_sse | 학술 검색 |
| dola | generic_sse | - |

## Tier 4 — 특수 환경 (5개)

| 서비스 | response_type | 제약 사항 |
|--------|--------------|----------|
| github_copilot | copilot_403 | IDE 전용 (VS Code/JetBrains) |
| m365_copilot | m365_copilot_sse | Microsoft 계정 로그인 필요 |
| gamma | gamma_sse | EventSource 실패 |
| notion | notion_ndjson | WebSocket 전용 |
| meta | meta_graphql | 한국 리전 접속 불가 |

## 기술 매트릭스

### Envelope 템플릿 커버리지
- 전체 22개 response_type → **22개 envelope 보유 (100%)**
- 전체 36개 block_mode=1 서비스 → **36개 message 템플릿 (100%)**

### H2 파라미터 분포
| h2_mode | h2_end_stream | h2_hold_request | 서비스 수 |
|---------|--------------|-----------------|----------|
| 2 (keep-alive) | 1 | 1 | 23 |
| 1 (GOAWAY) | 1 | 0 | 12 |
| 2 (keep-alive) | 1 | 0 | 1 (notion) |

### 키워드 패턴 (enabled=1)
| 패턴 | 카테고리 | 매칭 모드 |
|------|---------|----------|
| \d{6}-\d{7} | ssn (주민등록번호) | REGEX |
| sex | - | EXACT |
| 한글날 | - | PARTIAL |
| 전화번호 regex | phone | REGEX |
| 이메일 regex | email | REGEX |
