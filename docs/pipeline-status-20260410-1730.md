# APF Pipeline Status — 2026-04-10 17:30

## 전체 현황
- **37개 등록** → **32개 enabled+block_mode=1**
- **DB 차단 통계**: **64건 / 13개 서비스** (v0 +3, qwen3 +1)
- **검증 서비스**: Tier 1(5) + Tier 1.5(5) + Tier 2(2) = **12개** (32개 중 37.5%)

## 핵심 발견 (이번 세션)

### 경고 미표시 근본 원인 분석
- **CL:0 fix 효과 없음** (예상대로): `recalculate_content_length()`가 이미 CL:0 자동 수정
- **v0 domain fix 성공**: DB 3건 블록, etap.log 확인 (h2_mode=2, 100% VTS delivery)
- **v0도 경고 미표시**: qwen3과 동일한 스피너 증상 (HTTP/2 keep-alive)
- **패턴 발견**: Tier 1 (경고 정상) = 전부 h2_mode=1 (GOAWAY) / Tier 1.5+ = h2_mode=2 (keep-alive)
- **가설**: `on_disconnected()` → TCP send buffer flush → 브라우저 수신 / keep-alive → flush 없음 → 데이터 체류
- **#367 실험 진행 중**: v0를 h2_mode=1로 변경하여 GOAWAY flush 가설 검증

### Phase3-B25 C++ 코드 변경 (미빌드)
- Fix 1: HTTP/1.1 hold 지원 (`on_http_request` + `on_http_request_content_data`)
- Fix 2: HTTP/1.1 block response에 `Connection: close` 치환

## 서비스별 검증 상태 (32개)

### ✅ Tier 1 — Warning 렌더링 검증 완료 (5개)
| 서비스 | h2_mode | DB 차단 | 비고 |
|--------|---------|---------|------|
| chatgpt | 1 (GOAWAY) | 2건 | 한국어 경고 채팅 버블 ✅ |
| claude | 1 (GOAWAY) | 11건 | sparkle 아이콘 + 경고 ✅ |
| duckduckgo | 1 (GOAWAY) | 1건 | 한국어 채팅 버블 ✅ |
| genspark | 1 (GOAWAY) | - | SSE 정상 ✅ |
| grok | 1 (GOAWAY) | 2건 | 한국어 경고 배너 ✅ |

### ✅ Tier 1.5 — 차단 동작 확인 (5개)
| 서비스 | h2_mode | DB 차단 | 비고 |
|--------|---------|---------|------|
| consensus | 2 (keep-alive) | 2건 | 키워드 차단 E2E 파이프라인 ✅ |
| mistral | 2 (keep-alive) | 8건 | Error 6002 표시 |
| perplexity | 2 (keep-alive) | 2건 | "스레드 없음" 표시 |
| perfle | 2 (keep-alive) | 2건 | perplexity 동일 |
| qwen3 | 2 (keep-alive) | **4건** | ⭐ 차단 확인, 경고 미표시 (HTTP/1.1 스피너) |

### ⚠️ Tier 2 — 부분 동작 (2개)
| 서비스 | 이슈 | DB 차단 |
|--------|------|---------|
| gemini3 | 페이지 OK, 프롬프트 미제출 | 21건 |
| deepseek | ERR_H2 지속 | 5건 |

### 🔶 Tier 3 — 키워드 차단 미검증 (13개)
| 서비스 | 상태 | DB | 다음 액션 |
|--------|------|-----|----------|
| **v0** | **#366 BLOCK_CONFIRMED**, 경고 미표시 | **3건** | ⭐ #367 h2_mode=1 실험 진행 중 |
| wrtn | LOGIN_REQUIRED | 0 | 인증 필요 |
| you | NOT_BLOCKED (GET bypass) | 0 | GET URL 파라미터 검사 기능 필요 |
| baidu | STILL_STUCK | 0 | 지역 제한 |
| blackbox | BLANK_PAGE | 0 | SPA 미렌더링 |
| character | BLANK_PAGE | 0 | ERR_H2 |
| huggingface | LOGIN_REQUIRED | 0 | 계정 필요 |
| cohere | LOGIN_REQUIRED | 0 | 계정 필요 |
| kimi | INPUT_FAILED | 0 | 자동화 한계 |
| poe | LOGIN_REQUIRED | 0 | 계정 필요 |
| qianwen | 트래픽 없음 | 0 | 중국 서비스 |
| chatglm | 트래픽 없음 | 0 | 중국 서비스 |
| phind | SERVICE_DOWN | 0 | 404 |

### 🔵 Tier 4 — 특수 환경 (7개)
dola(WS+SPA), github_copilot(IDE), m365_copilot(LOGIN), copilot(QUIC), gamma, notion(WS), meta(리전)

## 다음 우선순위
1. **#367 v0 h2_mode=1 결과 대기** — GOAWAY flush 가설 검증 (CRITICAL)
2. **Phase3-B25 빌드/배포** — HTTP/1.1 hold + Connection: close
3. **GOAWAY flush 이슈 대응** — #367 결과에 따라:
   - 확인 시: write_visible_data 후 명시적 TCP flush 구현 또는 h2_mode=2 서비스 GOAWAY 전환
   - 미확인 시: 프론트엔드 JavaScript 분석 필요
4. **v0 h2_mode 원복** — 실험 후 원래 값(h2_mode=2)으로 복원

## DB 차단 통계 (17:30)
| 서비스 | 건수 | 비고 |
|--------|------|------|
| gemini3 | 21 | Tier 2 |
| claude | 11 | Tier 1 ✅ |
| mistral | 8 | Tier 1.5 |
| deepseek | 5 | Tier 2 |
| qwen3 | **4** | Tier 1.5 (+1) |
| v0 | **3** | **NEW** — domain fix 후 첫 블록 |
| notion | 3 | Tier 4 |
| chatgpt | 2 | Tier 1 ✅ |
| perplexity | 2 | Tier 1.5 |
| perfle | 2 | Tier 1.5 |
| consensus | 2 | Tier 1.5 |
| grok | 2 | Tier 1 ✅ |
| duckduckgo | 1 | Tier 1 ✅ |
| **총계** | **64** | **13개 서비스** |
