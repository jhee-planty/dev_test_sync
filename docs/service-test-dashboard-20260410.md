# APF Service Test Dashboard — 2026-04-10 11:30

## 신규 기능 (이번 세션 배포)
- **페이지 로드 즉시 차단**: Accept: text/html GET 요청 → HTML 경고 페이지 반환 (키워드 없이)
- **WebSocket Upgrade 인터셉트**: on_upgraded() 콜백으로 WS 연결 차단
- **전 서비스 h2_mode=2 전환**: Group D 13개 포함 전체 서비스 keep-alive 모드

## 서비스별 테스트 결과 요약

### Group A — Warning 정상 동작 (5개)
| 서비스 | 결과 | 템플릿 | 비고 |
|--------|------|--------|------|
| chatgpt | ✅ WARNING | chatgpt_sse | SSE 스트리밍 정상 |
| claude | ✅ WARNING | claude | GOAWAY 방식 정상 |
| grok | ✅ WARNING | grok_ndjson | NDJSON 정상 |
| genspark | ✅ WARNING | genspark_sse | SSE 정상 |
| mistral | ✅ WARNING | mistral_trpc_sse | tRPC SSE 정상 |

### Group B — 차단 확인, 경고 개선 필요 (5개)
| 서비스 | 결과 | 이슈 | 조치 |
|--------|------|------|------|
| deepseek | ⚠️ PARTIAL | 한글 깨짐 (EUC-KR?) | ESCAPE2+CRLF 수정, #344 리테스트 대기 |
| gemini3 | ⚠️ SILENT | CSP가 webchannel 차단 | 페이지 로드 인터셉트로 대체 (배포 완료) |
| perplexity | ⚠️ PARTIAL | thread 아키텍처, SSE 미파싱 | BLOCK_ONLY → 페이지 로드 인터셉트 |
| notion | ⚠️ SILENT | NDJSON/JSON 모두 실패 | Notion 고유 포맷 리버스엔지니어링 필요 |
| duckduckgo | ✅ WARNING | duckduckgo_sse | SSE 정상 동작 |

### Group C — 차단 실패 (3개)
| 서비스 | 결과 | 이슈 | 조치 |
|--------|------|------|------|
| github_copilot | ❌ NO_BLOCK | API 도메인 다름 (api.individual.githubcopilot.com) | VT SNI 확인 필요 + 페이지 로드 인터셉트 |
| m365_copilot | ❌ NO_BLOCK | 비로그인 시 다른 API 사용 | HAR 캡처 필요 |
| meta | ❌ REGION_BLOCKED | 한국 접속 불가 | 테스트 환경에서 스킵 |

### Group D — 템플릿 없음, 페이지 로드 인터셉트 대상 (13개)
| 서비스 | h2_mode | hold | 페이지 로드 차단 | API 도메인 이슈 |
|--------|---------|------|-----------------|----------------|
| baidu | 2 | 1 | 🔄 테스트 대기 | - |
| character | 2 | 1 | 🔄 테스트 대기 | WebSocket 서비스 |
| chatglm | 2 | 1 | 🔄 테스트 대기 | - |
| cohere | 2 | 1 | 🔄 테스트 대기 | - |
| consensus | 2 | 1 | 🔄 테스트 대기 | - |
| dola | 2 | 1 | 🔄 테스트 대기 | - |
| huggingface | 2 | 1 | 🔄 테스트 대기 | path=/chat |
| kimi | 2 | 1 | 🔄 테스트 대기 | API: api.moonshot.cn |
| phind | 2 | 1 | 🔄 테스트 대기 | API: https.api.phind.com |
| poe | 2 | 1 | 🔄 테스트 대기 | GraphQL/WebSocket |
| qianwen | 2 | 1 | 🔄 테스트 대기 | - |
| v0 | 2 | 1 | 🔄 테스트 대기 | - |
| wrtn | 2 | 1 | 🔄 테스트 대기 | - |

### 신규 템플릿 생성 서비스 (#342 테스트 대기)
| 서비스 | response_type | 포맷 | 상태 |
|--------|--------------|------|------|
| qwen3 | qwen3_sse | SSE (OpenAI 호환) | 🔄 #342 대기 |
| you | you_json | JSON (Next.js) | 🔄 #342 대기 |
| blackbox | blackbox_page | 페이지 로드 인터셉트 | 🔄 #342 대기 |

### 비활성화 서비스 (5개)
| 서비스 | 사유 |
|--------|------|
| chatgpt2 | chatgpt와 중복 |
| clova_x | 서비스 종료 (2026-04-09) |
| clova | clova_x와 중복 |
| copilot | www.bing.com 전체 차단 문제 |
| gemini | gemini3와 중복 |

## 대기 중인 테스트
- **#342**: qwen3/you/blackbox 신규 템플릿
- **#343**: 페이지 로드 인터셉트 (wrtn, phind, v0, character, poe, huggingface)
- **#344**: deepseek ESCAPE2 수정 리테스트

## 핵심 기술적 발견
1. **페이지 로드 인터셉트가 범용 솔루션**: 모든 서비스에 템플릿 없이 동작
2. **많은 서비스가 프론트엔드/API 도메인 분리**: VT SNI 추가 필요 (blackbox, phind, kimi 등)
3. **CSP가 엄격한 서비스(Gemini)**: 템플릿 주입 불가 → 페이지 로드 인터셉트 필수
4. **WebSocket 서비스(character, poe)**: on_upgraded() + 페이지 로드 이중 차단
