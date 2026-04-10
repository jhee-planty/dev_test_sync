# Workflow Retrospective — 2026-04-10

> 분석 기간: 2026-04-09 09:00 ~ 2026-04-10 10:00 (약 25시간, 활성 작업 ~12시간)
> 분석 대상: 40건 테스트 (#288~#327) / 1회 빌드 (B26 path_matcher fix)
> 데이터 소스: results/ 40건, test PC 회고 보고(#327), pipeline-status doc, 이전 회고(4/01)
> 이전 회고: 2026-04-01 (개선안 5건 중 적용 현황 아래)

## 요약

25시간 세션에서 **7개 서비스에 대해 40건 테스트**를 수행했다.
**5개 서비스에서 경고 표시 성공** (ChatGPT, Claude, Genspark, DuckDuckGo, Grok) — 이전 4개에서 1개 증가.
**5개 서비스가 기능적 차단 확인** (Perplexity, Gamma, Gemini, DeepSeek, Mistral).

Mistral에 10회 반복 테스트(#317~#326)를 투자하여 NDJSON 배열 형식 + h2_mode=2가 유일하게
Error 6002를 재현하는 조합임을 확인했다. DuckDuckGo와 Grok는 각각 1~2회 만에 성공.

**핵심 비효율**: 폴링 대기 시간(test PC 결과 미도착)이 전체 시간의 **65%+** 를 차지.
context break 2회 발생. Mistral 10회 반복은 3-Strike Rule 적용 시 5회로 줄일 수 있었음.

## 메트릭 요약

### 세션 통계

| 항목 | 수치 |
|------|------|
| 세션 활성 시간 | ~12시간 |
| 총 테스트 수 | 40 (#288~#327) |
| 빌드 수 | 1회 (B26: path_matcher trailing slash fix) |
| 서비스 수 | 7개 |
| 경고 표시 성공 | 5 (ChatGPT, Claude, Genspark, DuckDuckGo, Grok) |
| 기능적 차단 | 5 (Perplexity, Gamma, Gemini, DeepSeek, Mistral) |
| test PC 회고 수신 | 1 (#327) |

### 서비스별 성과

| 서비스 | 테스트 수 | 최종 결과 | 반복 효율 | 비고 |
|--------|-----------|-----------|-----------|------|
| DuckDuckGo | 2 (#308,#310) | ✅ WARNING VISIBLE | 1빌드/2테스트 | B26 path fix 후 성공 |
| Grok | 1 (#316) | ✅ WARNING VISIBLE | 0빌드/1테스트 | NDJSON redirect 즉시 성공 |
| DeepSeek | 6 (#305~#315) | 🔶 403 Visible | 0빌드/6테스트 | SSE 4연속 실패 → 403 전환 |
| Perplexity | 5 (#288~#292) | 🔶 Functional Block | 0빌드/5테스트 | H2 프로토콜 변형 테스트 |
| Gemini | 5 (#293~#304) | 🔶 Functional Block | 1빌드/5테스트 | B24 RST_STREAM fix 포함 |
| Mistral | 10 (#317~#326) | 🔶 Visible Error 6002 | 0빌드/10테스트 | DB-only 변경, 10회 반복 |
| 기타 | 11 | 기존 확인/HAR/스킵 | — | ChatGPT, Claude 재확인 등 |

### 타임라인 분석

| 구간 | 시간 | 테스트 | 속도 | 비고 |
|------|------|--------|------|------|
| H2 프로토콜 (#288~#304) | 09:00~16:00 (7h) | 17건 | 25분/건 | Perplexity/Gemini + B24/B25 빌드 |
| DeepSeek (#305~#315) | 16:00~17:30 (1.5h) | 11건 | 8분/건 | HAR → SSE → 403 성공 |
| Grok/DuckDuckGo (#306~#316) | 17:30~18:00 (30분) | 3건 | 10분/건 | 빠른 성공 |
| Mistral (#317~#326) | 18:00~08:44+1 (14.7h) | 10건 | 88분/건 | **폴링 대기 포함, 극단적 비효율** |
| 회고 (#327) | 08:44~10:00 | 1건 | — | test PC 보고 |

## 이전 회고 개선안 추적 (4/01 → 4/10)

| # | 개선안 | 적용 상태 | 근거 |
|---|--------|-----------|------|
| 1 | 폴링 타임아웃 + 비동기 전환 | ❌ **미적용** | Mistral 100+회 무한 폴링. **2회 연속 미적용** |
| 2 | HAR 캡처 선행 규칙 | ✅ **적용됨** | Mistral #320 HAR 선행 → tRPC/NDJSON 구조 파악 |
| 3 | 예측 가능한 실패에 빌드 쓰지 않기 | ⚠️ **부분** | DB-only로 빌드 절약, 그러나 10회 반복 과다 |
| 4 | 메트릭 수집 | ⚠️ **부분** | metrics_2026-04-06.jsonl 존재, 4/9~4/10 미수집 |
| 5 | Escalation ②③ 문서화 | ❌ **미적용** | 문서 미작성 |

**변화**: 1/5 완전 적용, 2/5 부분, 2/5 미적용 (40%). 이전 67%에서 하락.

## 비효율 분석 (5차원)

### 1. 소요 시간
- **Mistral 폴링 14시간**: #322→#323 사이 test PC 오프라인. 90%가 폴링 대기.
- **Mistral 88분/테스트**: 10건에 14.7시간. 실제 dev 작업 ~2시간.
- **DeepSeek/Grok/DuckDuckGo 효율적**: 15건을 2.5시간 (10분/건).
- **B26 빌드 ROI 최고**: 1빌드 → DuckDuckGo 즉시 성공.

### 2. 실패 패턴
- Mistral 10회 중 예측 가능 실패 3건 (#318, #324, #325) — 45분 절약 가능
- DeepSeek SSE 4연속 0 bytes — 3회 후 전략 전환이 올바른 판단 (1회 초과)
- 동일 패턴: HTTP 상태코드 변경은 tRPC/SPA 서비스에서 무효

### 3. 불필요한 동작
- #318 (HTTP 429): #317과 동일 메커니즘 반복 — 1테스트 낭비
- #325 (tRPC error): #317~#319 결론 무시한 유사 시도 — 1테스트 낭비
- 폴링 100+회: 15분 타임아웃이면 14시간→15분

### 4. 워크플로우 병목
- test PC 가용성 (최대 병목): 가용 시 5건/23분, 비가용 시 0건/14시간
- 폴링 중 생산성 제로: 다른 작업 불가 규칙
- SSH→MySQL JSON 이스케이핑: 시행착오 15분

### 5. 자원 활용
- 컴파일 서버: B26 1회 빌드, 정상
- test PC: 08:21~08:44에 5건 연속 처리 (매우 효율적 가용 구간)
- 메트릭: 4/6 데이터만 존재, 4/9~4/10 미수집

## test PC 측 발견사항 (#327 보고)

| 문제 | 빈도 | 해결법 | 개선 방향 |
|------|------|--------|-----------|
| DPI 125% 좌표 오차 | 매 스크린샷 | logical=physical/1.25 | DPI-aware 헬퍼 |
| Add-Type 네임스페이스 충돌 | 매 .ps1 | 수동 W_N 증분 | auto-increment 템플릿 |
| Responsive 모드 토글 | 3~4회/세션 | F12 재시작 | Snapshot label 클릭 |
| Git push 충돌 | dev-test 동시 push | stash/pull/pop | send-request.sh |
| DC 60s timeout | 구조적 | 55s sleep | hard limit, 대안 없음 |

## 긍정적 패턴

1. **HAR 선행 적용**: Mistral #320 → tRPC/NDJSON 구조 파악 → #322 돌파구
2. **DB-only 반복으로 빌드 절약**: Mistral 10회 모두 빌드 0회
3. **B26 빌드 ROI 최고**: 1빌드 → DuckDuckGo 즉시 성공
4. **DeepSeek 전략 전환**: SSE 4실패 → 403 부분 성공
5. **test PC 회고 수집**: #327로 양쪽 관점 데이터 확보
6. **체계적 비교 테이블**: Mistral #317~#326 비교로 근거 기반 의사결정

## 신규 개선안

### [CRITICAL] #1: 폴링 타임아웃 (3회 연속 미적용!)
- **문제**: 14시간 무한 폴링. 이전 회고 2회 지적 미적용.
- **제안**: cowork-remote에 하드코딩 — 20회(~20분) 초과 시 다음 작업 이동
- **기대**: 유휴 14시간 → 20분 (98% 감소)

### [HIGH] #2: 3-Strike 조기 종료
- **문제**: Mistral 10회 중 3건 예측 가능 실패
- **제안**: 동일 실패 3회 → 접근법 포기, 5회 초과 → 현재 최선으로 확정
- **기대**: 서비스당 10회 → 5회

### [HIGH] #3: test PC 자동 시작/감시
- **문제**: test PC 14시간 비가용, 수동 시작 필요
- **제안**: Windows Task Scheduler + heartbeat.json + L3 시각 진단
- **기대**: 비가용 14시간 → 30분 이하

### [MEDIUM] #4: SSH→MySQL JSON 이스케이핑 표준화
- **문제**: 쌍따옴표 누락 시행착오 15분
- **제안**: "SQL 파일 scp 전송 → mysql < file.sql" 표준 문서화
- **기대**: 15분 → 2분

### [MEDIUM] #5: test PC DPI/Add-Type 자동화
- **문제**: DPI 좌표 오차, 네임스페이스 충돌 반복
- **제안**: DPI 헬퍼 + auto-increment 템플릿
- **기대**: 좌표/충돌 에러 제거

## 전체 파이프라인 현황 (4/10 기준)

| 서비스 | Block | Warning | 상태 | 누적 테스트 |
|--------|-------|---------|------|------------|
| ChatGPT | ✅ | ✅ | DONE | ~8 |
| Claude | ✅ | ✅ | DONE | ~18 |
| Genspark | ✅ | ✅ | DONE | ~20 |
| DuckDuckGo | ✅ | ✅ | **DONE (신규)** | ~4 |
| Grok | ✅ | ✅ | **DONE (신규)** | ~2 |
| Perplexity | ✅ | 🔶 | Functional Block | ~23 |
| Gamma | ✅ | 🔶 | BLOCKED_ONLY | ~52 |
| Gemini | ✅ | 🔶 | Functional Block | ~61 |
| DeepSeek | ✅ | 🔶 | **403 Visible (신규)** | ~6 |
| Mistral | ✅ | 🔶 | **Error 6002 (신규)** | ~10 |

**경고 성공**: 5/10 (50%) ← 이전 4/10 (40%). **전체 차단**: 10/10 (100%).

## 다음 회고 체크포인트

1. 폴링 타임아웃이 cowork-remote에 반영? (**3회 연속 — CRITICAL**)
2. 3-Strike 조기 종료가 스킬에 반영?
3. test PC 자동 시작/heartbeat 구현?
4. SSH→MySQL 표준 문서 작성?
5. metrics/ 4/10 이후 데이터 수집? (5회째 체크)
