# APF Pipeline Status — 2026-04-10 17:45

## 전체 현황
- **37개 등록** → **33개 enabled** → **32개 block_mode=1**
- **DB 차단 통계**: **79건 / 13개 서비스** (v0 +12, qwen3 +1)
- **검증 서비스**: Tier 1(5) + Tier 1.5(5) + Tier 2(2) = **12개** (32개 중 37.5%)

## 핵심 진전 (이번 세션 — 17:30~17:45)

### Phase3-B25 빌드/배포 완료 ✅
- **3가지 C++ 수정사항 프로덕션 배포됨** (17:38 KST)
  - Fix 1: HTTP/1.1 POST hold (`on_http_request` + `on_http_request_content_data`)
  - Fix 2: HTTP/1.1 block response에 `Connection: close` 치환
  - Fix 3: HTTP/1.1 hold release + VTS hold_flush 
- **실시간 검증 성공**: qwen3 17:41:44 차단에서 전체 파이프라인 동작 확인
  - `hold_set_h1` → `block` → `hold_discard(1416B)` → `vts_post(written=565)` ✅
  - 응답 크기 570B → 565B (Connection: keep-alive→close 치환으로 5B 감소) ✅

### h2_goaway 발견 (CRITICAL) 
- **Tier 1 성공 서비스 공통점**: `h2_mode=1` + `h2_goaway=1` (chatgpt, claude, duckduckgo, grok)
- **#367 v0 실험의 누락**: `h2_mode=1`만 설정, `h2_goaway=0` — GOAWAY frame이 response 데이터에 미포함
- **h2_mode vs h2_goaway**:
  - `h2_mode=1`: VTS가 write 후 GOAWAY 전송 + disconnect (연결 수준)
  - `h2_goaway=1`: APF가 response 데이터에 GOAWAY frame 포함 (응답 데이터 수준)
  - **둘 다 필요할 수 있음** — VTS disconnect만으로는 부족, 응답 데이터에 GOAWAY frame도 필요
- **v0 수정**: h2_goaway=1 추가 (17:43) → 이제 Tier 1과 동일한 설정
- **genspark 예외**: h2_mode=2, h2_goaway=0인데 경고 정상 — SSE 스트리밍은 별도 메커니즘

### v0 실사용자 차단 활발
- 17:31~17:36 사이 **12건 추가 차단** (총 15건, 이전 3건에서)
- IP 1.214.24.181에서 연속 SSN 패턴 시도 — 실사용자
- 모든 차단에서 VTS delivery 100% (`written=331 expected=331`)

## 서비스별 검증 상태 (32개)

### ✅ Tier 1 — Warning 렌더링 검증 완료 (5개)
| 서비스 | h2_mode | h2_goaway | DB 차단 | 비고 |
|--------|---------|-----------|---------|------|
| chatgpt | 1 (GOAWAY) | 1 | 2건 | 한국어 경고 채팅 버블 ✅ |
| claude | 1 (GOAWAY) | 1 | 11건 | sparkle 아이콘 + 경고 ✅ |
| duckduckgo | 1 (GOAWAY) | 1 | 1건 | 한국어 채팅 버블 ✅ |
| genspark | 2 (keep-alive) | 0 | - | SSE 정상 ✅ (예외: h2_goaway 불필요) |
| grok | 1 (GOAWAY) | 1 | 2건 | 한국어 경고 배너 ✅ |

### ✅ Tier 1.5 — 차단 동작 확인 (5개)
| 서비스 | h2_mode | h2_goaway | DB 차단 | 비고 |
|--------|---------|-----------|---------|------|
| consensus | 2 | 0 | 2건 | 키워드 차단 E2E 파이프라인 ✅ |
| mistral | 2 | 0 | 8건 | Error 6002 표시 |
| perplexity | 2 | 0 | 2건 | "스레드 없음" 표시 |
| perfle | 2 | 0 | 2건 | perplexity 동일 |
| qwen3 | 2 | 0 | **5건** | ⭐ Phase3-B25 차단 확인 (hold_set→block→hold_discard→vts_post ✅) |

### ⚠️ Tier 2 — 부분 동작 (2개)
| 서비스 | 이슈 | DB 차단 |
|--------|------|---------|
| gemini3 | 페이지 OK, 프롬프트 미제출 | 21건 |
| deepseek | ERR_H2 지속 | 5건 |

### 🔶 Tier 3 — 키워드 차단 미검증 (13개)
| 서비스 | 상태 | DB | 다음 액션 |
|--------|------|-----|----------|
| **v0** | ⭐ **#369 FULL TIER 1 TEST** (h2_mode=1+h2_goaway=1) | **15건** | test PC 결과 대기 |
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

## DB 차단 통계 (17:45)
| 서비스 | 건수 | 변동 | 비고 |
|--------|------|------|------|
| gemini3 | 21 | - | Tier 2 |
| **v0** | **15** | **+12** | h2_mode=1 실험 중 — 실사용자 차단 활발 |
| claude | 11 | - | Tier 1 ✅ |
| mistral | 8 | - | Tier 1.5 |
| deepseek | 5 | - | Tier 2 |
| **qwen3** | **5** | **+1** | Phase3-B25 첫 차단 (17:41) |
| notion | 3 | - | Tier 4 |
| consensus | 2 | - | Tier 1.5 |
| perplexity | 2 | - | Tier 1.5 |
| perfle | 2 | - | Tier 1.5 |
| grok | 2 | - | Tier 1 ✅ |
| chatgpt | 2 | - | Tier 1 ✅ |
| duckduckgo | 1 | - | Tier 1 ✅ |
| **총계** | **79** | **+15** | **13개 서비스** |

## 다음 우선순위
1. **#369 v0 full Tier 1 결과 대기** — h2_goaway=1 추가 후 첫 테스트
2. **#368 qwen3 Phase3-B25 결과 대기** — HTTP/1.1 hold + Connection: close 효과 확인
3. **결과에 따라**:
   - v0 경고 표시 성공 → h2_goaway=1이 핵심. 다른 h2_mode=2 서비스에도 h2_goaway=1+h2_mode=1 적용 검토
   - v0 여전히 실패 → v0 전용 프론트엔드 JS 분석 필요
   - qwen3 스피너 해소 → Phase3-B25 HTTP/1.1 수정 성공
   - qwen3 여전히 스피너 → HTTP/1.1 추가 분석 필요 (브라우저 버퍼링?)
4. **v0 h2_mode 원복** — 실험 완료 후 h2_mode=2, h2_hold_request=1, h2_goaway=0으로 복원
5. **SQL 기록** — 이번 세션의 모든 DB 변경사항 기록
