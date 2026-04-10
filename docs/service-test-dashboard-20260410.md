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
| deepseek | deepseek_sse | SSE→Strategy D | **#350** network error (SSE JSON Patch 실패). **Strategy D 적용**: 400 Bad Request + JSON error. **#356** 리테스트 대기 |
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

### Tier 3C-1 — WebSocket → Strategy D (ws_fallback_error)
| 서비스 | response_type | h2_mode | hold | 상태 |
|--------|--------------|---------|------|------|
| character | ws_fallback_error | 2 | 1 | 400 에러 fallback 적용, 테스트 대기 |
| copilot | ws_fallback_error | 1 | 1 | 400 에러 fallback 적용, **h2_hold=1 수정** |
| poe | ws_fallback_error | 2 | 1 | 400 에러 fallback 적용, 테스트 대기 |

### Tier 3C-2 — generic_sse (테스트 후 개선)
| 서비스 | response_type | h2_mode | hold | 상태 |
|--------|--------------|---------|------|------|
| clova | generic_sse | 1 | 1 | 테스트 대기, **h2_hold=1 수정** |
| clova_x | generic_sse | 1 | 1 | 테스트 대기, **h2_hold=1 수정** |
| consensus | generic_sse | 2 | 1 | 테스트 대기 |
| dola | generic_sse | 2 | 1 | 테스트 대기 |
| phind | generic_sse | 2 | 1 | 테스트 대기 (SERVICE_DOWN) |
| wrtn | openai_compat_sse | 2 | 1 | 테스트 대기 |

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

## APF 실시간 차단 로그 (2026-04-10, etap.log — 15:45 업데이트)
| 서비스 | 차단 횟수 | 비고 |
|--------|----------|------|
| gemini3 | 20 | Tier 2 — Strategy D 400 동작 확인, VTS 전송 검증 완료 |
| claude | 18 | Tier 1 — 가장 활발 |
| mistral | 8 | Tier 1.5 — Error 6002 표시 |
| deepseek | 5 | Tier 2 — Strategy D 400으로 변경, #356 리테스트 대기 |
| notion | 3 | Tier 4 — WS 전용이지만 HTTP 차단 동작 |
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
| **총계** | **68+** | **15개 서비스에서 실제 차단 발생** |

## 테스트 결과 (추가)
- **#348**: batch test 1 결과 도착
  - duckduckgo: ✅ WARNING_SUCCESS (채팅 버블 경고, charset 인코딩 수정 완료)
  - huggingface: ⚠️ LOGIN_REQUIRED (로그인 필요)
  - phind: ⚠️ SERVICE_DOWN (404, 서비스 오프라인)
  - you: ⚠️ INPUT_FAILED (DPI 좌표 불일치)
  - perplexity: ⚠️ PARTIAL_BLOCK (차단 성공, "스레드 없음" 에러)

## 테스트 결과 (#353 — CRITICAL)
- **#353**: Tier 3 batch (consensus, dola, blackbox, v0, baidu) — **5/5 FAIL**
  - 전 서비스 ERR_HTTP2_PROTOCOL_ERROR로 JS 리소스 로딩 실패
  - 공통점: h2_hold=1, h2_mode=2 서비스
  - **분석**: etap.log에 test 시간대(15:36) 로그 0건 → 트래픽이 Etap을 경유하지 않았거나 VTS 하위 레이어에서 실패
  - **가설 A**: VTS H2 proxy의 h2_mode=2 핸들링 버그
  - **가설 B**: SetCertificate 실패 (8917건) 관련 TLS/H2 손상
  - **가설 C**: test PC 네트워크/브라우저 설정 이슈
  - **진단**: #359 diagnostic test 생성 (consensus vs claude 비교, 인증서 체인 확인)
  - **NOTE**: APF hold 코드는 POST만 적용 (line 648), GET 요청에 영향 없음 확인

## 대기 중인 테스트
- **#351**: openai_compat_sse batch (kimi, huggingface, cohere)
- **#352**: Gemini Strategy D 검증
- **#353**: generic_sse/JSON batch (consensus, dola, blackbox, v0, baidu)
- **#354**: WebSocket batch (character, copilot, poe)
- **#355**: Gemini 400 리테스트 (503→400 변경)
- **#356**: DeepSeek Strategy D 리테스트 (SSE→400 변경)
- **#357**: WebSocket Strategy D batch (character, copilot, poe — ws_fallback_error)
- **#358**: Korean/Chinese batch (wrtn, clova, clova_x)

## 알려진 이슈 (15:45 업데이트)
1. ~~cross-domain API SNI~~ → **해결**: VT use_white_list_servers=0 (전체 MITM, SNI 불필요)
2. ~~WebSocket 서비스 generic_sse 불가~~ → **해결**: character/copilot/poe → ws_fallback_error (400 에러)
3. ~~Gemini CSP/webchannel~~ → **해결**: Strategy D 400 Bad Request
4. **generic_sse 호환성**: clova/clova_x/consensus/dola — 테스트 결과에 따라 개별 수정 필요
5. **Perplexity Tier 1.5 확정**: 차단+데이터 보호 달성 (커스텀 경고 불가)
6. **DeepSeek Strategy D**: SSE JSON Patch 실패 → 400 에러로 변경, #356 리테스트
7. **Gemini URL decode 에러**: webchannel 바이너리 데이터 null byte → 정상 동작 (chat 메시지는 정상 디코딩+차단)
8. **copilot h2_hold=1**: PII 서버 전달 방지 수정 완료
9. **gamma/notion h2_hold=1**: 미테스트 서비스 안전 보호 수정 완료
10. ~~**copilot www.bing.com 과도 포함**~~ → **해결**: domain_patterns에서 www.bing.com 제거 (일반 Bing 검색 차단 방지)
11. ~~**copilot/m365_copilot 도메인 충돌**~~ → **해결**: m365_copilot에서 copilot.microsoft.com 제거 (substrate.office.com만 유지)
12. **Gemini hold_overflow**: 234KB webchannel POST → 64KB 버퍼 한계 초과 시 flush/re-hold 반복. binary 데이터이므로 PII 위험 없으나 불필요한 CPU 사용. 낮은 우선순위.
13. **Dola WebSocket**: www.dola.com/chat에서 WS 업그레이드 확인됨. 현재 허용 처리 (keyword-less blocking 없음). 채팅은 WS로 전송되므로 HTTP POST 기반 차단 불가 — ws_fallback_error 전환 검토 필요
14. **"sex" EXACT 키워드 오탐**: claude에서 7초간 10건 연속 차단 (12:00). EXACT 모드로 "sex" 서브스트링 매칭 → "sexual", "sexist" 등 정상 텍스트에서도 차단. `\bsex\b` word-boundary regex 또는 키워드 제거 검토 필요
15. **VTS hold_discard 로그 누락**: 15:39 차단에서 VTS delivery 로그만 있고 APF "AI prompt blocked" 로그 없음. 기능 정상이나 로그 추적성 개선 필요

## Tier 3C 프로토콜 분석 결과
| 서비스 | 실제 프로토콜 | response_type | 전략 |
|--------|-------------|--------------|------|
| character | WebSocket | ws_fallback_error | 400 에러 → 프론트엔드 에러 UI |
| copilot | SignalR WS | ws_fallback_error | 400 에러 → 프론트엔드 에러 UI |
| poe | WS + GraphQL | ws_fallback_error | 400 에러 → 프론트엔드 에러 UI |
| clova/clova_x | Naver SSE | generic_sse | h2_hold=1, 테스트 필요 |
| phind | HTTP SSE | generic_sse | SERVICE_DOWN, 복구 후 테스트 |
| consensus | HTTP API | generic_sse | 테스트 필요 |
| dola | **WebSocket** (확인됨) | generic_sse | WS 사용 확인 → ws_fallback_error 전환 검토 |

## 템플릿 포맷 매핑 (API 조사 기반)
| response_type | 포맷 | 서비스 |
|--------------|------|--------|
| openai_compat_sse | `data: {"choices":[{"delta":{"content":"..."}}]}` | kimi, huggingface, qianwen, chatglm, wrtn |
| cohere_sse | `event: text-generation\ndata: {"text":"..."}` | cohere |
| baidu_sse | `data: {"result":"...","is_end":true}` | baidu |
| generic_sse | `data: {"text":"..."}` | clova, clova_x, consensus, dola, phind |
| ws_fallback_error | `{"error":{"message":"...","code":"content_filter"}}` | character, copilot, poe |
| gemini (Strategy D) | HTTP 400 + JSON error | gemini, gemini3 |
| deepseek_sse (Strategy D) | HTTP 400 + JSON error | deepseek |
| gamma_sse (Strategy D) | HTTP 400 + JSON error | gamma |
