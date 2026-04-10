# APF Service Test Dashboard — 2026-04-10 12:25

## 핵심 변경 (이번 세션)
- **페이지 로드 즉시 차단 완전 제거**: 사용자 피드백 반영. APF는 POST body에 민감정보 키워드가 있을 때만 차단. 페이지 접속 자체를 막지 않음.
- **WebSocket 키워드 없는 즉시 차단 제거**: 같은 원칙 적용. WS에서도 키워드 매칭 후만 차단.
- **전 서비스 템플릿 완비**: 36개 서비스 모두 response_type 설정 완료 (plain template mode 0건)
- **h2_end_stream=1 전환**: 전 서비스 END_STREAM 활성화 (브라우저가 응답 완료를 인식하도록)
- **cross-domain API 도메인 추가**: blackbox(useblackbox.io), phind(https.api.phind.com), kimi(api.moonshot.cn)
- **v0 도메인 확장**: v0.dev 추가 (기존 v0.app만)

## DB 현황 요약
- 서비스: 37개 등록 (block_mode=1: 36개, block_mode=0: 1개)
- Response templates: 37개
- Envelope templates: 21개 (unique response_type)

## 서비스별 상태

### Tier 1 — Warning 정상 동작 (VERIFIED)
| 서비스 | response_type | 비고 |
|--------|--------------|------|
| chatgpt | chatgpt_sse | SSE 스트리밍 정상 |
| claude | claude | SSE 정상 |
| genspark | genspark_sse | SSE 정상 |
| duckduckgo | duckduckgo_sse | SSE 정상 |

### Tier 2 — 차단 확인, 경고 개선 진행 중
| 서비스 | response_type | 이슈 | 조치 |
|--------|--------------|------|------|
| deepseek | deepseek_sse | 한글 인코딩 깨짐 | ESCAPE2+CRLF 수정 완료, #347 리테스트 대기 |
| gemini3 | gemini | CSP가 webchannel 차단 | Strategy D (END_STREAM only) 필요 |
| perplexity/perfle | perplexity_sse | thread 아키텍처 | Thread API 차단으로 대안 |
| mistral | mistral_trpc_sse | 403→silent reset | tRPC 호환 에러 |
| grok | grok_ndjson | redirect 인식 실패 | NDJSON 재시도 |

### Tier 3 — 템플릿 신규 생성, 테스트 대기
| 서비스 | response_type | h2_mode | hold | 상태 |
|--------|--------------|---------|------|------|
| qwen3 | qwen3_sse | 2 | 1 | #342 대기 |
| you | you_json | 2 | 1 | #342 대기 |
| blackbox | blackbox_json | 2 | 1 | 테스트 대기 |
| baidu | baidu_json | 2 | 1 | 테스트 대기 |
| v0 | v0_json | 2 | 1 | 테스트 대기 |
| character | generic_sse | 2 | 1 | 테스트 대기 (WebSocket 서비스) |
| chatglm | generic_sse | 2 | 1 | 테스트 대기 |
| clova | generic_sse | 1 | 0 | 테스트 대기 |
| clova_x | generic_sse | 1 | 0 | 테스트 대기 |
| cohere | generic_sse | 2 | 1 | 테스트 대기 |
| consensus | generic_sse | 2 | 1 | 테스트 대기 |
| copilot | generic_sse | 1 | 0 | 테스트 대기 (WebSocket 주의) |
| dola | generic_sse | 2 | 1 | 테스트 대기 |
| huggingface | generic_sse | 2 | 1 | 테스트 대기 |
| kimi | generic_sse | 2 | 1 | 테스트 대기 (API: api.moonshot.cn) |
| phind | generic_sse | 2 | 1 | 테스트 대기 (API: https.api.phind.com) |
| poe | generic_sse | 2 | 1 | 테스트 대기 (GraphQL/WebSocket) |
| qianwen | generic_sse | 2 | 1 | 테스트 대기 |
| wrtn | generic_sse | 2 | 1 | 테스트 대기 |

### Tier 4 — 특수 환경 필요
| 서비스 | response_type | 이슈 |
|--------|--------------|------|
| github_copilot | copilot_403 | IDE 서비스, API 도메인 다름 |
| m365_copilot | m365_copilot_sse | Microsoft 계정 로그인 필요 |
| gamma | gamma_sse | EventSource 실패 → 대안 필요 |
| notion | notion_ndjson | WS 전용 → HTTP Upgrade 인터셉트 |
| meta | meta_graphql | 한국 리전 접속 불가 |

### 기타
| 서비스 | response_type | 비고 |
|--------|--------------|------|
| chatgpt2 | chatgpt_sse | chatgpt 중복 |
| gemini | gemini | gemini3 중복 |
| amazon | (none) | block_mode=0 (비활성) |

## 테스트 결과
- **#346**: claude.ai 접속 — ✅ ACCESS_OK (페이지 정상 로드, 차단 없음)
- **#347**: deepseek — ⚠️ PARTIAL_BLOCK (end_stream=0으로 SSE 미렌더링 → end_stream=1로 수정, #350 리테스트 대기)
- **#345**: blackbox — ⚠️ NO_BLOCK (페이지 로드만 테스트, API 차단은 프롬프트 입력 필요)

## 대기 중인 테스트
- **#348**: batch test 1 (duckduckgo, huggingface, phind, you, perplexity)
- **#349**: batch test 2 (mistral, grok, chatgpt, claude, gemini)
- **#350**: deepseek 리테스트 (h2_end_stream=1)

## 알려진 이슈
1. **cross-domain API**: blackbox(useblackbox.io), phind(https.api.phind.com), kimi(api.moonshot.cn) — VT SNI 추가 필요
2. **WebSocket 서비스**: character.ai, poe.com — on_upgraded() 콜백 + generic_sse 병행
3. **Gemini CSP**: webchannel 차단 시 프론트엔드가 silent fail → Strategy D 필요
