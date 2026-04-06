# Workflow Retrospective — 2026-03-27

> 분석 기간: 2026-03-27 (08:40 ~ 13:30, 약 4.8시간)
> 분석 대상: 20건 테스트 (GitHub Copilot 5건, Gamma 15건) / 13 빌드 (#21~#33)
> 데이터 소스: results/ 20건, archive index 250건, lessons/, 이전 회고(3/25)
> 이전 회고: 2026-03-25 (개선안 6건 중 1건 적용, 2건 부분 적용, 3건 미적용)

## 요약

4.8시간 동안 13빌드를 수행하여 **Copilot은 3빌드 만에 PASS**, **Gamma는 13빌드 후 BLOCKED_ONLY 확정**.
Copilot은 효율적이었으나, Gamma는 **파이프라인 규칙(7빌드 상한)을 6빌드 초과**하여 약 3시간을 낭비했다.
이전 회고에서 제안한 "3회 연속 실패 시 전략 전환"이 적용되지 않아 동일 패턴이 반복되었다.


## 메트릭 요약

### 세션 통계

| 항목 | 수치 |
|------|------|
| 세션 시간 | 4.8시간 (08:40~13:30) |
| 총 빌드 수 | 13 (#21~#33) |
| 총 테스트 수 | 20 |
| 빌드당 평균 사이클 | ~22분 |
| PASS 달성 서비스 | 1 (Copilot) |
| BLOCKED_ONLY 확정 | 1 (Gamma) |
| 전체 성공률 | 5% (1/20) |

### 서비스별 성과

| 서비스 | 테스트 수 | 빌드 수 | 결과 | 효율 |
|--------|-----------|---------|------|------|
| GitHub Copilot | 5 | 3 (#21~#23) | **PASS** (403 Forbidden) | ✅ 효율적 (3빌드 만에 해결) |
| Gamma | 15 | 13 (#21~#33) | **BLOCKED_ONLY** | ❌ 과다 투자 (7빌드 상한 초과) |


### Gamma 빌드별 타임라인

| 결과 파일 | 간격 | 상태 | 빌드 설명 |
|-----------|------|------|-----------|
| 039 | (시작) | WARNING_NOT_DELIVERED | Build #21 — 422 JSON error |
| 041 | +24분 | PARTIAL_PASS | Build #21 REAL deploy |
| 043 | +43분 | PARTIAL_PASS | Build #22 — 200+text/plain |
| 045 | +16분 | APF_NOT_TRIGGERED | Build #23 — 403 Forbidden |
| 047~053 | (ts없음) | PARTIAL~REGRESSION | Build #23~#29 — 다양한 SSE/JSON/HTML |
| 054 | +122분 | FAIL | Build #30 — SSE single JSON |
| 055 | +60분 | PARTIAL_PASS | Build #31 — SSE multi-key JSON |
| 056 | +8분 | PARTIAL_PASS | Build #32 — SSE large JSON |
| 057 | +8분 | FAIL | Build #33 FINAL — SSE real format |

> Build #30에서 +122분 갭은 context break + test PC 대기로 추정.


## 이전 회고 개선안 추적 (3/25 → 3/27)

| # | 개선안 | 적용 상태 | 근거 |
|---|--------|-----------|------|
| 1 | 서버 로그 첫 빌드부터 포함 | ✅ **적용됨** | Build #21부터 `[APF_WARNING_TEST]` 일관 사용 |
| 2 | 관련 변경 한 빌드에 배치 | 🟡 **부분 적용** | Build #21은 copilot+gamma 동시였으나, 각 빌드는 여전히 단일 가설 |
| 3 | 3회 실패 시 전략 전환 트리거 | ❌ **미적용** | Gamma 13빌드 (7빌드 상한 6회 초과). 가장 큰 시간 낭비 원인 |
| 4 | test PC 자동 폴링 신뢰성 | 🟡 **부분 적용** | 대기 갭 여전히 존재 (Build #30: +122분) |
| 5 | context break 시 폴링 자동 재개 | 🟡 **부분 적용** | 사용자가 "멈추면 안되지..." 1회 지적 |
| 6 | 메트릭 수집 자동화 | ❌ **미적용** | results/metrics/ 여전히 비어있음 (.gitkeep만) |

**핵심 교훈:** 개선안 #3(3-Strike Rule)이 적용되었다면 Gamma는 Build #27(3회 연속 실패) 시점에서
전략 재검토에 들어갔을 것이며, Build #28~#33의 6빌드(약 3시간)를 절약할 수 있었다.


## 비효율 분석 (5차원)

### 1. 소요 시간

- **Gamma 과다 투자**: 13빌드 × ~22분 = ~4.8시간. 전체 세션(4.8h)의 대부분을 Gamma에 투입.
- **Build #30 대기 갭**: 054 결과 도착까지 +122분. context break + test PC 비활성으로 추정.
- **Build #31~#33 빠른 사이클**: 8~60분 간격. 이 구간은 효율적이었음.
- **Copilot 효율적**: 3빌드, ~1.5시간. 좋은 사례.

### 2. 실패 패턴

- **Gamma "모든 방식 실패" 패턴**: 13개 다른 접근법 모두 동일 증상(ERR_CONNECTION_CLOSED).
  근본 원인이 "Etap H2 DATA frame 전달 자체"에 있으므로, 응답 포맷 변경은 무의미했음.
  Build #26 1회성 성공이 "포맷이 핵심"이라는 오판을 유발.
- **APF_NOT_TRIGGERED (Build #23)**: 044, 045에서 APF 미동작 → 재테스트 046, 047 필요.
  이는 test PC의 브라우저 캐시 또는 기존 연결 재사용이 원인이었을 수 있음.
- **WARNING_NOT_DELIVERED (Build #21 첫 배포 실패)**: 038, 039에서 바이너리가 실제 배포되지
  않은 상태에서 테스트 수행 → 040, 041에서 REAL deploy 후 재테스트. 배포 검증 부재.

### 3. 불필요한 동작

- **Build #28~#33 (6빌드)**: Build #27에서 plaintext 실패, #26의 JSON object만 1회 성공이라는
  데이터가 있었음에도 6빌드 추가 투입. 7빌드 상한 규칙 무시.
- **Gamma 에러코드 순회 (#21~#25)**: 422→200→403→429→HTML — 5가지 HTTP 상태코드를 순차 시도.
  그러나 Gamma 프론트엔드가 모든 에러를 catch하는 구조이므로 에러코드 변경은 원천적으로 무효.
  Phase 2(design)에서 "프론트엔드 에러 핸들링 분석"이 선행되었다면 5빌드 절약 가능.

### 4. 워크플로우 병목

- **빌드 상한 미준수**: 파이프라인 스킬에 "서비스당 7빌드 상한"이 명시되어 있으나 강제되지 않았음.
  Cowork이 자율 판단으로 "사용자가 모든 방법 시도를 요청"을 우선시한 결과.
- **Phase 2 부재**: Gamma는 Phase 2(warning design)를 건너뛰고 바로 Phase 3(impl)에 진입.
  설계 단계에서 "Gamma EventSource가 에러를 어떻게 처리하는가"를 분석했으면 불필요한 빌드 감소.
- **context break 후 복구 지연**: Build #30 주변에서 +122분 갭. 폴링 재개 자동화 미비.

### 5. 자원 활용

- **test PC 가용성**: 대부분 응답했으나 간헐적 비활성 (Build #30 전후).
- **컴파일 서버**: 문제 없음. ninja 빌드 안정적.
- **메트릭 수집 공백**: test-pc-worker의 metrics 수집이 동작하지 않아 정밀 분석 불가.


## 긍정적 패턴

1. **Copilot 3빌드 완료**: Build #21→#22→#23, 403 Forbidden 전략으로 PASS. 효율적 에스컬레이션.
2. **서버 로그 일관 사용**: `[APF_WARNING_TEST]` 로그가 모든 빌드에 포함되어 서버측 진단 가능.
3. **순차 서비스 집중**: Copilot 완료 후 Gamma로 전환. 3/25 회고의 "한 서비스 집중" 교훈 적용.
4. **HAR 분석 중간 수행**: Build #29에서 HAR #029 캡처하여 Gamma 실제 SSE 포맷 확인. 데이터 기반 접근.
5. **체계적 접근법 테이블**: Gamma 13빌드 모두 문서화. 향후 참조용으로 가치 있음.
6. **빠른 후반 사이클**: Build #31~#33은 8분 간격. 효율적 빌드-배포-테스트 루프.


## 개선안

### [CRITICAL] 개선안 #1: 빌드 상한 강제 메커니즘

- **문제**: Gamma 13빌드 (7빌드 상한 6회 초과). 약 3시간 낭비.
- **근거**: 이전 회고 #3 미적용. "사용자가 모든 방법 시도 요청"과 "7빌드 상한" 충돌 시 상한이 무시됨.
- **제안**: apf-warning-impl 스킬에 **하드 카운터** 추가.
  빌드 카운트를 impl journal에 기록하고, 7회 도달 시 "BLOCKED_ONLY 판정 또는 사용자 명시 승인 필요" 게이트 삽입.
  사용자가 "계속해"라고 해도 "현재 N빌드 소진. 추가 빌드 승인?" 확인을 한 번 거침.
- **대상**: `apf-warning-impl/SKILL.md` — 3-Strike Rule 섹션 강화
- **기대**: 무의미한 반복 방지. 3시간/서비스 절약 가능.
- **우선순위**: CRITICAL (2회 연속 회고에서 동일 문제 반복)

### [HIGH] 개선안 #2: Phase 2(Design) 필수화 — 에러 핸들링 분석 선행

- **문제**: Gamma는 Phase 2 없이 Phase 3 진입. 프론트엔드 에러 핸들링 패턴을 모른 채 5가지 HTTP 상태코드 순차 시도.
- **근거**: Build #21~#25 (5빌드, ~2시간)가 "프론트엔드가 모든 에러를 catch" 사실을 발견하는 데 소모됨.
- **제안**: Phase 2 design에서 필수 분석 항목 추가:
  "① 프론트엔드 에러 핸들러 분석 (try-catch, error boundary, fallback UI)"
  "② EventSource/fetch/XHR의 에러 처리 흐름"
  "③ 에러 시 사용자에게 보이는 실제 UI (generic error? custom message?)"
- **대상**: `apf-warning-design/SKILL.md` — 필수 분석 항목 섹션
- **기대**: 무효한 접근법 조기 배제. 2~5빌드 절약.
- **우선순위**: HIGH

### [HIGH] 개선안 #3: 배포 검증 게이트

- **문제**: Build #21 첫 시도(#038, #039)에서 바이너리가 실제 배포되지 않은 상태로 테스트.
- **근거**: 2건 테스트 낭비 + 재배포 후 재테스트(#040, #041) 필요.
- **제안**: 빌드-배포 후 etapd restart 확인 + 로그에서 신규 바이너리 확인하는 스텝을 강제.
  `etap-build-deploy` 스킬에 "배포 후 검증" 체크리스트 추가:
  `ssh test-server "etapd --version"` 또는 `ls -la /usr/local/bin/etap` 타임스탬프 확인.
- **대상**: `etap-build-deploy/SKILL.md`
- **기대**: 미배포 상태 테스트 방지. 빌드당 20~40분 절약.
- **우선순위**: HIGH


### [MEDIUM] 개선안 #4: "1회성 성공" 오판 방지 프로토콜

- **문제**: Build #26의 1회성 SSE 성공이 이후 7빌드(#27~#33)의 "포맷 최적화" 시도를 유발.
- **근거**: Build #26 성공 → #27 실패 시점에서 "동일 H2 flags인데 결과가 다르다"는 사실이 이미 확인됨.
  이것은 "포맷 문제가 아니라 전송 계층 문제"를 의미하지만, 이 신호를 무시하고 포맷 변경을 계속 시도.
- **제안**: 성공 후 바로 다음 빌드에서 실패하면 "1회성 성공" 가능성을 먼저 검증:
  ① 동일 코드로 재테스트 (재현성 확인)
  ② 재현 실패 시 → "전송 계층 문제"로 분류, 포맷 변경 중단
  ③ impl journal에 "1회성 성공 경고" 플래그 기록
- **대상**: `apf-warning-impl/SKILL.md` — Test-Fix Cycle 섹션
- **기대**: 오판 기반 무의미한 빌드 방지. 3~5빌드 절약.
- **우선순위**: MEDIUM

### [MEDIUM] 개선안 #5: 메트릭 수집 실제 동작 확인

- **문제**: results/metrics/가 여전히 비어있음. 2회 연속 회고에서 지적.
- **근거**: test-pc-worker Step 4 메트릭 수집이 실행되지 않거나, 다른 경로에 저장 중.
- **제안**: test-pc-worker SKILL.md의 Step 4 로직을 실제 실행하여 검증.
  metrics_YYYY-MM-DD.jsonl이 생성되는지 확인. 미생성 시 코드 수정.
- **대상**: `test-pc-worker/SKILL.md` — Step 4
- **기대**: 다음 회고 시 정밀 시간 분석 가능.
- **우선순위**: MEDIUM

### [LOW] 개선안 #6: 전체 파이프라인 현황판 자동화

- **문제**: status.md 업데이트가 수동이며 종종 실제 상태와 불일치.
  오늘 Grok(WAITING→EXCLUDED), Notion(WAITING→BLOCKED_ONLY), Genspark(WARNING_SHOWN→FRONTEND_CHANGED) 3건 불일치 발견.
- **근거**: status.md와 impl journal의 상태가 다를 때 잘못된 의사결정 위험.
- **제안**: 서비스 상태 변경 시 impl journal과 status.md를 동시에 업데이트하는 체크리스트.
  또는 impl journal의 마지막 상태를 파싱하여 status.md를 자동 생성하는 스크립트.
- **대상**: `genai-warning-pipeline/SKILL.md`
- **기대**: 상태 불일치 제거.
- **우선순위**: LOW


## 전체 파이프라인 진행 현황 (누적)

| 서비스 | Block | Warning | 상태 | 테스트 수 (누적) |
|--------|-------|---------|------|-----------------|
| ChatGPT | ✅ | ✅ | **DONE** | 5 |
| Claude | ✅ | ✅ | **DONE** | 15 |
| Perplexity | ✅ | ⚠️ | **DONE** (SSE 제한) | 17 |
| GitHub Copilot | ✅ | ✅ | **PASS** (Build #23) | 35 |
| Gamma | ✅ | ❌ | **BLOCKED_ONLY** | 46 |
| Gemini | ❌ | ❌ | NEEDS_MANUAL_ACTION | 51 |
| Genspark | ✅ | ❌ | FRONTEND_CHANGED | 16 |
| Grok | ❌ | ❌ | EXCLUDED | 12 |
| Notion | ✅ | ❌ | BLOCKED_ONLY | 28 |
| M365 Copilot | ❌ | ❌ | EXCLUDED | 17 |

**누적 250건 테스트**, 4개 서비스 DONE/PASS, 2개 BLOCKED_ONLY, 4개 인프라/제외.

## 방안 2/3 전환 판단

- 메트릭 건수: ~20건 기존 + 0건 신규 = 20건 (30건 미만 → 방안 2 전환 시기상조)
- 반복 비효율 패턴: 6개 (3개 이상 → 조건 충족)
- 스킬 패치 이력: 0건 (2건 미만 → 방안 3 전환 시기상조)
- **전환 권장: 아직 아님.** 메트릭 수집(개선안 #5)이 해결되면 방안 2 전환 검토.

## 다음 회고 체크포인트

1. 개선안 #1(빌드 상한 강제)이 적용되었는가?
2. 다음 서비스에서 Phase 2가 선행되었는가?
3. metrics/ 디렉토리에 데이터가 생성되었는가?
4. status.md와 impl journal 상태가 일치하는가?

