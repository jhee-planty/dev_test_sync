# APF Pipeline Status — 2026-04-10 16:36

## 전체 현황
- **37개 등록** → **32개 enabled+block_mode=1** (+ amazon block_mode=0, clova/clova_x/chatgpt2/gemini disabled)
- **DB 차단 통계**: 60건 / 12개 서비스 (오늘)
- **키워드**: 5개 (SSN regex, \bsex\b, 한글날, phone regex, email regex)

## 서비스별 검증 상태 (32개 enabled+block_mode=1)

### ✅ Tier 1 — Warning 렌더링 검증 완료 (5개)
| 서비스 | 테스트 | DB 차단 | 비고 |
|--------|--------|---------|------|
| chatgpt | #349 ✅ | 2건 | 한국어 경고 채팅 버블 |
| claude | #349 ✅ | 11건 | sparkle 아이콘 + 경고 |
| duckduckgo | #348 ✅ | 1건 | 한국어 채팅 버블 |
| genspark | 확인 ✅ | - | SSE 정상 |
| grok | #349 ✅ | 2건 | 한국어 경고 배너 (redirect) |

### ✅ Tier 1.5 — 차단 동작 확인 (4개)
| 서비스 | 테스트 | DB 차단 | 비고 |
|--------|--------|---------|------|
| consensus | #360 ✅ | 2건 | SSN regex 차단, generic_sse 338B |
| mistral | #322,#326 | 8건 | Error 6002 표시 |
| perplexity | #332,#348 | 2건 | "스레드 없음" 표시 |
| perfle | 로그 확인 | 2건 | perplexity 동일 |

### ⚠️ Tier 2 — 부분 동작 (2개)
| 서비스 | 이슈 | DB 차단 | 비고 |
|--------|------|---------|------|
| gemini3 | 페이지 OK, 프롬프트 미제출 | 21건 | Strategy D 400, React state 자동화 한계 |
| deepseek | ERR_H2 지속 | 5건 | SetCertificate 간헐 실패 추정 |

### 🔶 Tier 3 — 키워드 차단 미검증 (14개)

**A. 테스트 가능성 높음 (우선순위):**
| 서비스 | 상태 | DB 차단 | 다음 액션 |
|--------|------|---------|----------|
| **wrtn** | 페이지 로드 OK, SUBMIT_FAILED | 0건 | #362 재시도 (keyboard sim, 로그인 시도) |
| **qwen3** | 미테스트 | **1건** (11:20) | ⭐ 이미 프로덕션 차단! warning 렌더링 확인만 필요 |
| **you** | 미테스트 | 0건 | #361 대기. 트래픽 6건 관찰됨 |
| **baidu** | #353 LOADING_STUCK | 0건 | #361 대기. ERR_H2 transient 후 복구 가능성 |

**B. 접근 제한:**
| 서비스 | 이슈 | 다음 액션 |
|--------|------|----------|
| huggingface | LOGIN_REQUIRED | 로그인 계정 필요 |
| cohere | LOGIN_REQUIRED | 로그인 계정 필요 |
| kimi | INPUT_FAILED (자동화 한계) | DPI 좌표 조정 또는 수동 테스트 |
| poe | LOGIN_REQUIRED | 로그인 후 재테스트 |
| qianwen | 트래픽 없음 | 중국 서비스, 접근성 확인 필요 |
| chatglm | 트래픽 없음 | 중국 서비스, 접근성 확인 필요 |

**C. SPA 렌더링 실패 (MITM 한계):**
| 서비스 | 이슈 | 다음 액션 |
|--------|------|----------|
| blackbox | BLANK_PAGE (JS SPA 미렌더링) | MITM proxy SRI/CSP 이슈. 수동 테스트 필요 |
| v0 | BLANK_PAGE | 동일 |
| character | BLANK_PAGE (ERR_H2) | ERR_H2 transient 후 복구 가능, 이후 SPA 확인 |

**D. 서비스 다운:**
| 서비스 | 이슈 |
|--------|------|
| phind | SERVICE_DOWN (404) |

### 🔵 Tier 4 — 특수 환경 필요 (7개)
| 서비스 | 제약 | 비고 |
|--------|------|------|
| dola | WS + SPA 미렌더링 | HTTP POST 차단 불가 |
| github_copilot | IDE 전용 | VS Code/JetBrains 테스트 필요 |
| m365_copilot | Microsoft 로그인 | 계정 필요 |
| copilot | QUIC/H3 우회 | UDP 443 차단으로 TCP fallback 유도 필요 |
| gamma | EventSource 실패 | Strategy D 400 적용 검토 |
| notion | WS 전용 | HTTP 차단은 동작 (3건 DB) |
| meta | 한국 리전 차단 | 접근 불가 |

## 핵심 성과 (오늘 세션)
1. **consensus 키워드 차단 E2E 검증** — hold→keyword match→block→generic_sse template→H2 response→RST_STREAM 전체 파이프라인 동작
2. **ERR_H2_PROTOCOL_ERROR 원인 규명** — transient SetCertificate 실패, APF 버그 아님
3. **12개 서비스 DB 차단 확인** — gemini3(21), claude(11), mistral(8), deepseek(5), notion(3), chatgpt/perplexity/perfle/consensus/grok(각 2), qwen3/duckduckgo(각 1)
4. **sex 키워드 FP 수정** — EXACT→REGEX \bsex\b
5. **CLOVA X 서비스 종료 대응** — disabled 처리
6. **copilot QUIC 우회 발견** — Tier 4 재분류

## 다음 우선순위
1. **wrtn 키워드 테스트** (#362) — 가장 유망, 페이지 로드 확인됨
2. **qwen3 warning 렌더링 확인** — 이미 프로덕션 차단 중!
3. **you/baidu 페이지 로드 + 키워드 테스트** (#361)
4. **SPA 렌더링 이슈 조사** — blackbox/v0/character 공통 원인 분석
5. **로그인 필요 서비스** — huggingface/cohere/poe 계정 확보 후 테스트
