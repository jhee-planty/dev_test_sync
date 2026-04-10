# APF Service Test Dashboard — 2026-04-10 13:45

## 핵심 변경 (이번 세션)
- **페이지 로드 즉시 차단 완전 제거**: 사용자 피드백 반영. APF는 POST body에 민감정보 키워드가 있을 때만 차단. 페이지 접속 자체를 막지 않음.
- **WebSocket 키워드 없는 즉시 차단 제거**: 같은 원칙 적용. WS에서도 키워드 매칭 후만 차단.
- **전 서비스 템플릿 완비**: 36개 서비스 모두 response_type 설정 완료 (plain template mode 0건)
- **h2_end_stream=1 전환**: 전 서비스 END_STREAM 활성화 (브라우저가 응답 완료를 인식하도록)
- **cross-domain API 도메인 추가**: blackbox(useblackbox.io), phind(https.api.phind.com), kimi(api.moonshot.cn)
- **v0 도메인 확장**: v0.dev 추가 (기존 v0.app만)
- **템플릿 정교화** (NEW):
  - kimi, huggingface, qianwen, chatglm → `openai_compat_sse` (OpenAI-compatible SSE 포맷)
  - cohere → `cohere_sse` (Cohere 전용 named event 포맷)
  - baidu → `baidu_sse` (ERNIE SSE 스트리밍 포맷, result 필드)
  - gemini → **Strategy D** (503 에러 응답으로 프론트엔드 자체 에러 UI 유도, CSP 우회 불필요)
- **누락 템플릿 보완**: chatgpt2, perfle, clova_x, gemini3 메시지 템플릿 추가

## DB 현황 요약
- 서비스: 37개 등록 (block_mode=1: 36개, block_mode=0: 1개)
- Response templates: 43개
- Envelope templates: 23개 (unique response_type)

## 서비스별 상태

### Tier 1 — Warning 정상 동작 (VERIFIED)
| 서비스 | response_type | 비고 |
|--------|--------------|------|
| chatgpt | chatgpt_sse | **#349 한국어 경고 채팅 버블 렌더링** |
| claude | claude | **#349 sparkle 아이콘 + 경고 메시지 렌더링** |
| genspark | genspark_sse | SSE 정상 |
| duckduckgo | duckduckgo_sse | **#348 한국어 경고 채팅 버블** (charset 수정 완료) |
| grok | grok_ndjson | **#349 한국어 경고 배너** (redirect → 경고 표시) |

### Tier 1.5 — 차단 동작 확인 (에러 UI 표시)
| 서비스 | response_type | 이슈 | 조치 |
|--------|--------------|------|------|
| mistral | mistral_trpc_sse | tRPC 프로토콜 | NDJSON array format → Error 6002 표시 (#322,#326). 커스텀 경고 불가, 에러 UI는 표시됨 |
| perplexity/perfle | perplexity_sse | thread 아키텍처 | 실시간 로그에서 차단 확인 (14:22). 경고 렌더링 검증 필요 |

### Tier 2 — 차단 확인, 경고 개선 진행 중
| 서비스 | response_type | 이슈 | 조치 |
|--------|--------------|------|------|
| deepseek | deepseek_sse | SSE 미렌더링 | end_stream=1 수정, #350 리테스트 대기 |
| gemini3 | gemini | webchannel + CSP | **#349 UI 프리즈** (503 → stop 버튼 멈춤). 400으로 변경, #355 리테스트 |

### Tier 3A — OpenAI-compatible SSE (정교화 완료)
| 서비스 | response_type | h2_mode | hold | 상태 |
|--------|--------------|---------|------|------|
| kimi | openai_compat_sse | 2 | 1 | 테스트 대기 (API: api.moonshot.cn) |
| huggingface | openai_compat_sse | 2 | 1 | 테스트 대기 |
| qianwen | openai_compat_sse | 2 | 1 | 테스트 대기 |
| chatglm | openai_compat_sse | 2 | 1 | 테스트 대기 |

### Tier 3B — 서비스 전용 SSE/JSON (정교화 완료)
| 서비스 | response_type | h2_mode | hold | 상태 |
|--------|--------------|---------|------|------|
| cohere | cohere_sse | 2 | 1 | 테스트 대기 (named event: stream-start/text-generation/stream-end) |
| baidu | baidu_sse | 2 | 1 | 테스트 대기 (ERNIE SSE, result 필드) |
| qwen3 | qwen3_sse | 2 | 1 | #342 대기 |
| you | you_json | 2 | 1 | #342 대기 |
| blackbox | blackbox_json | 2 | 1 | 테스트 대기 |
| v0 | v0_json | 2 | 1 | 테스트 대기 |

### Tier 3C — generic_sse (정보 부족, 테스트 후 개선)
| 서비스 | response_type | h2_mode | hold | 상태 |
|--------|--------------|---------|------|------|
| character | generic_sse | 2 | 1 | 테스트 대기 (WebSocket 서비스) |
| clova | generic_sse | 1 | 0 | 테스트 대기 |
| clova_x | generic_sse | 1 | 0 | 테스트 대기 |
| consensus | generic_sse | 2 | 1 | 테스트 대기 |
| copilot | generic_sse | 1 | 0 | 테스트 대기 (WebSocket 주의) |
| dola | generic_sse | 2 | 1 | 테스트 대기 |
| phind | generic_sse | 2 | 1 | 테스트 대기 (API: https.api.phind.com) |
| poe | generic_sse | 2 | 1 | 테스트 대기 (GraphQL/WebSocket) |
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

## APF 실시간 차단 로그 (2026-04-10, etap.log)
| 서비스 | 차단 횟수 | 비고 |
|--------|----------|------|
| claude | 18 | Tier 1 — 가장 활발 |
| gemini3 | 11 | Tier 2 — Strategy D 동작 확인 |
| mistral | 8 | Tier 1.5 — Error 6002 표시 |
| notion | 3 | Tier 4 — WS 전용이지만 HTTP 차단 동작 |
| deepseek | 3 | Tier 2 — h2_end_stream=1 수정됨 |
| perplexity | 2 | Tier 1.5 — "스레드 없음" 표시 |
| perfle | 2 | Tier 1.5 — perplexity와 동일 |
| grok | 2 | Tier 1 — 한국어 경고 배너 |
| chatgpt | 2 | Tier 1 — SSE 채팅 버블 |
| you | 1 | Tier 3 — you_json 차단 동작 |
| wrtn | 1 | Tier 3 — openai_compat_sse 차단 동작 |
| qwen3 | 1 | Tier 3 — qwen3_sse 차단 동작 |
| phind | 1 | Tier 3 — SERVICE_DOWN 이전 차단 |
| duckduckgo | 1 | Tier 1 — 채팅 버블 경고 |
| blackbox | 1 | Tier 3 — blackbox_json 차단 동작 |
| **총계** | **57** | **15개 서비스에서 실제 차단 발생** |

## 테스트 결과 (추가)
- **#348**: batch test 1 결과 도착
  - duckduckgo: ✅ WARNING_SUCCESS (채팅 버블 경고, charset 인코딩 수정 완료)
  - huggingface: ⚠️ LOGIN_REQUIRED (로그인 필요)
  - phind: ⚠️ SERVICE_DOWN (404, 서비스 오프라인)
  - you: ⚠️ INPUT_FAILED (DPI 좌표 불일치)
  - perplexity: ⚠️ PARTIAL_BLOCK (차단 성공, "스레드 없음" 에러)

## 대기 중인 테스트
- **#349**: batch test 2 (mistral, grok, chatgpt, claude, gemini) — test PC 대기
- **#350**: deepseek 리테스트 (h2_end_stream=1) — test PC 대기
- **#351**: openai_compat_sse batch (kimi, huggingface, cohere) — test PC 대기
- **#352**: Gemini Strategy D 검증 — test PC 대기

## 알려진 이슈
1. **cross-domain API**: blackbox(useblackbox.io), phind(https.api.phind.com), kimi(api.moonshot.cn) — VT SNI 추가 필요 여부 확인
2. **WebSocket 서비스**: character.ai, poe.com, copilot — 주로 WebSocket 통신. HTTP POST 차단은 동작하나 경고 렌더링 불가 (에러 UI 표시)
3. **Gemini CSP**: ~~webchannel 차단 시 프론트엔드가 silent fail~~ → **Strategy D 적용 완료** (503 응답)
4. **generic_sse 호환성**: 프론트엔드가 `{"text":"..."}` 포맷을 파싱하지 못할 수 있음 → 테스트 결과에 따라 개별 수정
5. **Perplexity Tier 1.5 확정**: thread_url_slug "blocked-{uuid}" → 후속 API 400 → 에러 표시. 차단+데이터 보호는 달성.
6. **copilot 도메인 확장**: copilot.microsoft.com 추가됨 (기존 www.bing.com만)
7. **clova_x envelope 수정**: NULL → generic_sse envelope 복사

## Tier 3C 프로토콜 분석 결과
| 서비스 | 실제 프로토콜 | generic_sse 호환성 | 전략 |
|--------|-------------|-------------------|------|
| character | WebSocket | ❌ 불가 | HTTP POST 차단, 에러 표시 (Tier 1.5) |
| copilot | SignalR WS | ❌ 불가 | HTTP POST 차단, 에러 표시 (Tier 1.5) |
| poe | WS + GraphQL | ❌ 불가 | HTTP POST 차단, 에러 표시 (Tier 1.5) |
| clova/clova_x | Naver SSE | ⚠️ 테스트 필요 | 커스텀 포맷 가능성 |
| phind | HTTP SSE | ⚠️ 서비스 다운 | 복구 후 테스트 |
| consensus | HTTP API | ⚠️ 테스트 필요 | generic_sse 가능성 |
| dola | Unknown | ⚠️ 테스트 필요 | generic_sse 가능성 |

## 템플릿 포맷 매핑 (API 조사 기반)
| response_type | 포맷 | 서비스 |
|--------------|------|--------|
| openai_compat_sse | `data: {"choices":[{"delta":{"content":"..."}}]}` | kimi, huggingface, qianwen, chatglm, wrtn |
| cohere_sse | `event: text-generation\ndata: {"text":"..."}` | cohere |
| baidu_sse | `data: {"result":"...","is_end":true}` | baidu |
| generic_sse | `data: {"text":"..."}` | clova, clova_x, consensus, dola, phind |
| generic_sse (WS fallback) | `data: {"text":"..."}` | character, copilot, poe |
| gemini (Strategy D) | HTTP 503 (빈 응답) | gemini, gemini3 |
