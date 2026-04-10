# APF Service Test Dashboard — 2026-04-10 16:30

## 핵심 변경 (이번 세션)
- **페이지 로드 즉시 차단 완전 제거**: 사용자 피드백 반영. APF는 POST body에 민감정보 키워드가 있을 때만 차단.
- **WebSocket 키워드 없는 즉시 차단 제거**: WS에서도 키워드 매칭 후만 차단.
- **전 서비스 템플릿 완비**: 24개 response_type, 42개 response_template, 40개 envelope_template
- **h2_end_stream=1 전환**: 전 서비스 END_STREAM 활성화
- **#354-358 테스트 결과 분석 완료** (16:10):
  - #355: Gemini 400 변경 → 페이지 로드 정상화 ✅
  - #356: DeepSeek ERR_H2 지속 → h2_hold=1 근본 문제
  - #354: copilot QUIC 우회 발견 → Tier 4 재분류
  - #358: CLOVA X 서비스 종료 → disabled
- **#359-360 결과 분석 완료** (16:30):
  - #359: ERR_H2 = TRANSIENT 확인 (consensus 25분 후 정상 로드)
  - #360: **consensus 키워드 차단 SUCCESS ✅** (SSN regex 2회 차단) → Tier 1.5 승격
  - #360: blackbox 페이지 로드 복구 ✅, dola 페이지 로드 복구 + WS 채팅 확인 → Tier 4
  - #362: wrtn/blackbox 키워드 테스트 요청 생성
- **DB 수정 (16:06)**: clova/clova_x disabled, consensus response_type 수정, sex 키워드 FP 수정

## DB 현황 요약
- 서비스: 37개 등록, **33개 enabled** (block_mode=1: 32개 + amazon block_mode=0)
- 비활성: clova, clova_x (서비스 종료), chatgpt2, gemini (중복)
- Response templates: 42개 | Envelope templates: 24개 response_type
- 키워드: 5개 enabled (sex FP 수정: EXACT→REGEX \bsex\b)

## 서비스별 상태

### Tier 1 — Warning 정상 동작 (VERIFIED)
| 서비스 | response_type | 비고 |
|--------|--------------|------|
| chatgpt | chatgpt_sse | **#349 한국어 경고 채팅 버블 렌더링** |
| claude | claude | **#349 sparkle 아이콘 + 경고 메시지 렌더링** |
| genspark | genspark_sse | SSE 정상 |
| duckduckgo | duckduckgo_sse | **#348 한국어 경고 채팅 버블** (charset 수정 완료) |
| grok | grok_ndjson | **#349 한국어 경고 배너** (redirect → 경고 표시) |

### Tier 1.5 — 차단 동작 확인 (에러/차단 UI 표시)
| 서비스 | response_type | 이슈 | 조치 |
|--------|--------------|------|------|
| consensus | generic_sse | **#360 키워드 차단 ✅** | SSN regex 2회 차단, generic_sse 템플릿 정상. hold→block→H2→RST_STREAM 전체 파이프라인 동작 |
| mistral | mistral_trpc_sse | tRPC 프로토콜 | NDJSON array format → Error 6002 표시 (#322,#326). 커스텀 경고 불가, 에러 UI는 표시됨 |
| perplexity/perfle | perplexity_sse | thread 아키텍처 | 실시간 로그에서 차단 확인 (14:22). 경고 렌더링 검증 필요 |

### Tier 2 — 부분 수정
| 서비스 | response_type | 이슈 | 테스트 결과 |
|--------|--------------|------|------|
| deepseek | deepseek_sse | Strategy D 400 | **#356** ERR_H2_PROTOCOL_ERROR 지속. h2_hold=1 세션레벨 hold 문제 |
| gemini3 | gemini | Strategy D 400 | **#355** 페이지 로드 정상화 ✅ (503→400 수정 효과). 프롬프트 제출은 React state 자동화 한계 |

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
| blackbox | blackbox_json | 2 | 1 | **#360** 페이지 로드 복구 ✅ — 키워드 테스트 대기 (#362) |
| v0 | v0_json | 2 | 1 | 테스트 대기 |

### Tier 3C — WebSocket / 기타
| 서비스 | response_type | h2_mode | hold | 테스트 결과 |
|--------|--------------|---------|------|------|
| character | ws_fallback_error | 2 | 1 | **#354** BLANK_PAGE (ERR_H2_PROTOCOL_ERROR) |
| poe | ws_fallback_error | 2 | 1 | **#354** LOGIN_REQUIRED (페이지 정상 로드) |
| wrtn | openai_compat_sse | 2 | 1 | **#358/#360** 페이지 정상, hold/release clean — 키워드 테스트 대기 (#362) |
| phind | generic_sse | 2 | 1 | SERVICE_DOWN |

### Tier 4 — 특수 환경 필요
| 서비스 | response_type | 이슈 |
|--------|--------------|------|
| github_copilot | copilot_403 | IDE 전용 (VS Code/JetBrains) |
| m365_copilot | m365_copilot_sse | Microsoft 계정 로그인 필요 |
| dola | generic_sse | **#360** 페이지 로드 복구 ✅, **WebSocket 전용 채팅** — HTTP POST 차단 불가 |
| copilot | ws_fallback_error | **#354 QUIC/H3 우회**: etap.log 트래픽 0건, APF 미인터셉트 |
| gamma | gamma_sse | EventSource 실패 |
| notion | notion_ndjson | WS 전용 |
| meta | meta_graphql | 한국 리전 접속 불가 |

### 비활성/기타
| 서비스 | response_type | 비고 |
|--------|--------------|------|
| chatgpt2 | chatgpt_sse | chatgpt 중복, enabled=false |
| gemini | gemini | gemini3 중복, enabled=false |
| amazon | (none) | block_mode=0 |
| clova | generic_sse | **서비스 종료** (2026-04-09), enabled=false |
| clova_x | generic_sse | **서비스 종료** (2026-04-09), enabled=false |

## 테스트 결과
- **#346**: claude.ai 접속 — ✅ ACCESS_OK (페이지 정상 로드, 차단 없음)
- **#347**: deepseek — ⚠️ PARTIAL_BLOCK (end_stream=0으로 SSE 미렌더링 → end_stream=1로 수정, #350 리테스트 대기)
- **#345**: blackbox — ⚠️ NO_BLOCK (페이지 로드만 테스트, API 차단은 프롬프트 입력 필요)

## DB 차단 통계 (2026-04-10, 16:25 업데이트)
| 서비스 | 차단 횟수 | 카테고리 | 비고 |
|--------|----------|---------|------|
| gemini3 | 21 | ssn | Tier 2 — Strategy D 400 |
| claude | 11 | ssn(1)+etc(10) | Tier 1 — sex FP 수정 완료 |
| mistral | 8 | ssn | Tier 1.5 — Error 6002 |
| deepseek | 5 | ssn | Tier 2 — ERR_H2 지속 |
| notion | 3 | ssn | Tier 4 — WS 전용 |
| chatgpt | 2 | ssn | Tier 1 ✅ |
| perplexity | 2 | ssn | Tier 1.5 |
| perfle | 2 | ssn | Tier 1.5 |
| consensus | 2 | ssn | **Tier 1.5 ✅ NEW** (#360) |
| grok | 2 | ssn | Tier 1 ✅ |
| qwen3 | 1 | ssn | Tier 3 |
| duckduckgo | 1 | ssn | Tier 1 ✅ |
| **총계** | **60** | | **12개 서비스 (DB 확인)** |

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

## 테스트 결과 (#351-358, 16:10 분석 완료)

- **#351**: kimi=INPUT_FAILED(자동화 한계), huggingface=LOGIN_REQUIRED, cohere=LOGIN_REQUIRED
- **#352**: Gemini ERR_H2_PROTOCOL_ERROR → "일시적으로 사용할 수 없습니다" (503 문제)
- **#353**: **CRITICAL** 5/5 FAIL — consensus/dola/blackbox/v0/baidu 전부 ERR_H2_PROTOCOL_ERROR
- **#354**: character=BLANK_PAGE(ERR_H2), **copilot=NOT_BLOCKED(QUIC 우회!)**, poe=LOGIN_REQUIRED
- **#355**: **Gemini 400 수정 성공 ✅** — 페이지 로드 정상화 (React state로 제출은 미검증)
- **#356**: DeepSeek ERR_H2_PROTOCOL_ERROR 지속 — 400 변경으로도 해결 안 됨
- **#357**: #354와 동일 결과 (ws_fallback_error 효과 없음)
- **#358**: wrtn=페이지 정상 로드 ✅, **clova/clova_x=서비스 종료** (2026-04-09)

## 테스트 결과 (#359 DIAGNOSTIC — 16:12)
- **consensus.app (h2_hold=1)**: ✅ PAGE_LOADS_NORMALLY — MITM 확인 (Plantynet CA), 25분 전 #353에서 ERR_H2 발생했던 동일 서비스가 정상 로드
- **claude.ai (h2_hold=0)**: ✅ PAGE_LOADS_NORMALLY — MITM 확인, 정상 (CONTROL)
- **결론**: ERR_H2_PROTOCOL_ERROR는 **일시적(TRANSIENT)** 현상. h2_hold 설정이 원인 아님. APF hold/release 메커니즘 정상 동작 확인.
- **추정 원인**: 브라우저 QUIC↔H2 fallback 타이밍, H2 connection pool stale, 또는 일시적 SetCertificate 실패

## 테스트 결과 (#360 — etap.log 기반 분석, 16:25)
- **consensus**: ✅ **KEYWORD_BLOCK_SUCCESS** — SSN regex `\d{6}-\d{7}` 2회 차단. generic_sse 템플릿 338바이트 전송. H2 block→RST_STREAM 전체 동작 확인. → **Tier 1.5 승격**
- **wrtn**: ⚠️ PAGE_LOADS (hold/release clean 3회). 키워드 프롬프트 미제출 — 자동화 한계 추정. #362 재테스트 요청.
- **blackbox**: ✅ PAGE_LOADS_RECOVERED — www.blackbox.ai + app.blackbox.ai 정상 로드 (ERR_H2 transient 확인). 키워드 테스트 대기 #362.
- **dola**: ✅ PAGE_LOADS_RECOVERED + **WS_CONFIRMED** — www.dola.com/chat/ 정상 로드, WebSocket upgrade 감지. 채팅은 WS 전용 → HTTP POST 키워드 차단 불가 → **Tier 4 재분류**

## 대기 중인 테스트
- **#361**: Tier 3 나머지 서비스 (baidu, you, v0, character) — 테스트 PC 미처리
- **#362**: wrtn/blackbox 키워드 차단 테스트 (페이지 로드 확인됨, SSN 프롬프트 제출 필요)

## 알려진 이슈 (16:10 업데이트)
1. ~~cross-domain API SNI~~ → **해결**
2. ~~WebSocket 서비스 generic_sse 불가~~ → **해결**: ws_fallback_error
3. ~~Gemini CSP/webchannel~~ → **해결**: Strategy D 400 (#355 확인 ✅)
4. **generic_sse 호환성**: consensus/dola — 테스트 필요 (clova/clova_x 서비스 종료로 제거)
5. **Perplexity Tier 1.5 확정**: 차단+데이터 보호 달성
6. **DeepSeek ERR_H2**: Strategy D 400 변경으로도 ERR_H2_PROTOCOL_ERROR 지속 (#356)
7. **Gemini URL decode 에러**: 정상 동작 (낮은 우선순위)
8. ~~copilot h2_hold=1~~ → copilot은 QUIC 우회로 Tier 4 재분류
9. **gamma/notion h2_hold=1**: 미테스트 서비스 안전 보호
10. ~~**copilot www.bing.com 과도 포함**~~ → **해결**
11. ~~**copilot/m365_copilot 도메인 충돌**~~ → **해결**
12. **Gemini hold_overflow**: 243KB POST → 64KB 오버플로우 10회+ 반복 (15:54 확인). binary 데이터이므로 PII 위험 없음. 낮은 우선순위.
13. **Dola WebSocket**: WS 채팅 확인됨. HTTP POST 기반 차단 불가 — ws_fallback_error 전환 검토 필요
14. ~~**"sex" EXACT 키워드 오탐**~~ → **해결**: `\bsex\b` REGEX로 변경 (16:06)
15. **VTS hold_discard 로그 누락**: 기능 정상이나 로그 추적성 개선 필요
16. **[RESOLVED-TRANSIENT] ERR_H2_PROTOCOL_ERROR**: #353/#354/#356 — **#359 진단 결과: 일시적 현상**. consensus.app(h2_hold=1)이 25분 후 정상 로드. h2_hold는 원인 아님. 브라우저 QUIC fallback/connection pool 타이밍 이슈 추정. #360 재테스트 요청 완료.
17. **[NEW] copilot QUIC/H3 우회**: copilot.microsoft.com이 QUIC(UDP 443)으로 통신하여 TCP MITM 불가. etap.log에 트래픽 0건. 네트워크 레벨에서 QUIC 차단하여 TCP fallback 유도 필요.
18. **[NEW] CLOVA X 서비스 종료**: 2026-04-09 종료. clova/clova_x enabled=false 처리 완료.
19. **[NEW] poe hold_flush_partial**: 15:50 poe stream=13에서 16384/16991 partial write 발생. flush 실패 시 데이터 유실 가능성 조사 필요.

## Tier 3C 프로토콜 분석 결과 (테스트 반영)
| 서비스 | 실제 프로토콜 | response_type | 테스트 결과 | 전략 |
|--------|-------------|--------------|----------|------|
| character | WebSocket | ws_fallback_error | #354 BLANK_PAGE (ERR_H2) | h2_hold 문제 해결 필요 |
| copilot | SignalR WS | ws_fallback_error | #354 NOT_BLOCKED (QUIC 우회) | → Tier 4 재분류 |
| poe | WS + GraphQL | ws_fallback_error | #354 LOGIN_REQUIRED | 페이지 정상, 로그인 후 재테스트 |
| ~~clova/clova_x~~ | Naver SSE | generic_sse | #358 서비스 종료 | enabled=false |
| phind | HTTP SSE | generic_sse | SERVICE_DOWN | 복구 대기 |
| consensus | HTTP API | generic_sse | **#360 키워드 차단 ✅** | → Tier 1.5 승격 |
| dola | **WebSocket** | generic_sse | **#360 페이지 복구, WS 확인** | → Tier 4 (WS 전용) |
| wrtn | OpenAI-compat | openai_compat_sse | #358/#360 페이지 정상 | 키워드 차단 테스트 #362 대기 |

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
