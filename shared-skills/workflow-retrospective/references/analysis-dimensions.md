# Analysis Dimensions — 상세 분석 기준

회고 시 아래 차원들을 체계적으로 확인한다.
각 차원은 독립적으로 분석할 수도 있고, 전체 회고 시 한 번에 분석할 수도 있다.

---

## 1. 소요 시간 (Duration)

### 수집 필드
- `duration_seconds`: 전체 소요 시간
- `phase_timings`: 단계별 소요 시간 breakdown

### 분석 방법

**Command별 통계:**
```
command: check-block
  count: 12
  avg: 45.2s
  min: 18s  (id: 007 — Chrome 이미 열려있었음)
  max: 82s  (id: 003 — 첫 실행, 브라우저 cold start)
  stddev: 15.3s
```

**단계별 시간 비중:**
```
check-block 평균 45.2s 중:
  browser_start:  28.1s (62%)  ← 병목!
  page_load:       8.3s (18%)
  input_prompt:    3.2s  (7%)
  wait_response:   4.1s  (9%)
  screenshot:      1.5s  (3%)
```

**이상치 탐지:**
- 평균 대비 2배 이상 걸린 작업 → 원인 파악 (네트워크? 첫 실행? 에러 재시도?)
- 동일 command인데 편차가 큰 경우 → 환경 차이 또는 비결정적 동작

### 개선 신호
- 특정 phase가 전체의 50% 이상 → 해당 phase 최적화 검토
- cold start가 반복 → 브라우저 사전 실행, 세션 재사용 검토
- 동일 URL 반복 접속 → 탭 재사용 또는 세션 유지

---

## 2. 실패 패턴 (Failures)

### 수집 필드
- `success`: boolean
- `error_type`: 에러 분류
- `retry_count`: 재시도 횟수
- `error_detail`: 상세 원인 (result JSON에서)

### 분석 방법

**에러 유형별 빈도:**
```
timeout:          5회 (42%)
focus_lost:       3회 (25%)
login_required:   2회 (17%)
network_error:    2회 (17%)
```

**재시도 효과:**
- 재시도 후 성공률이 높으면 → 일시적 문제 (타이밍, 네트워크)
- 재시도 후에도 실패 → 근본 원인 해결 필요

**시간대별 실패:**
- 특정 시간대에 실패 집중 → 네트워크 혼잡, 서버 점검 등 외부 요인

### 개선 신호
- 동일 에러 3회 이상 연속 → 자동 대응 로직 추가 검토
- `focus_lost` 반복 → AppActivate 로직 보강, 또는 창 최소화 방지
- `timeout` 반복 → 대기 시간 조정, 또는 Invoke-WebRequest 사전 확인 추가

---

## 3. 불필요한 동작 (Waste)

### 분석 방법

**항상 성공하는데 느린 단계:**
- 100% 성공률인 phase 중 소요 시간 상위 → 단순화 가능성 검토
- 예: 매번 Chrome을 새로 시작 → 이미 열려있으면 재사용

**중복 작업:**
- 동일 URL에 대해 check-block + check-warning을 별도로 실행 → run-scenario로 합칠 수 있는지
- 동일 서비스에 대해 verify-access 후 check-block → verify-access를 check-block에 내장

**미사용 산출물:**
- 생성된 스크린샷 중 dev가 실제로 참조한 비율
- 모든 command에 스크린샷을 첨부하지만 dev가 텍스트 결과만 보는 경우 → 선택적 캡처

**과도한 대기:**
- Start-Sleep 값이 보수적으로 설정된 경우 → 실제 로딩 시간 기반으로 조정
- Git fetch/pull 대기가 과도한 경우 → 폴링 간격 조정

---

## 4. 워크플로우 병목 (Bottleneck)

### 분석 방법

이 차원은 개별 작업이 아니라 전체 파이프라인 흐름을 본다.

**요청-실행 지연:**
```
request created → test received: avg 3m12s (git push/pull 동기화)
test executed → dev confirmed: avg 5m47s (dev 확인 지연)
```

**작업 큐 대기:**
- 여러 요청이 쌓여있을 때 뒤쪽 작업의 대기 시간
- urgent 작업이 실제로 먼저 처리되고 있는지

**상호 의존성:**
- "빌드 후 테스트" 같은 순차 의존성에서 대기 시간
- 하나의 실패가 후속 작업들을 모두 블로킹하는 경우

### 개선 신호
- 동기화 지연이 실행 시간보다 긴 경우 → 배치 요청 검토 (한 번에 여러 작업 전송)
- dev 확인 지연이 길 경우 → dev쪽 자동 폴링 최적화
- 병렬 실행 가능한 작업이 순차 처리되는 경우 → 동시 실행 검토

---

## 5. 자원 활용 (Resources)

### 분석 방법

**브라우저 세션:**
- 새 브라우저 시작 횟수 vs 재사용 횟수
- 동시에 열려있는 Chrome 프로세스 수

**디스크 사용량:**
- results/files/ 누적 용량
- 오래된 스크린샷 정리 여부

**네트워크:**
- HTTP 요청 실패율
- 평균 응답 시간 변화 추이

---

## Cross-Analysis: 복합 패턴

개별 차원으로는 보이지 않는 패턴:

- **느리면서 자주 실패하는 command** → 최우선 개선 대상
- **빠르지만 불필요한 동작** → 제거하면 전체 시간 단축
- **성공률은 높지만 재시도가 잦은 command** → 안정성 개선
- **특정 서비스에서만 실패** → 서비스별 특화 로직 필요
