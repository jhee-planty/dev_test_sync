# Metrics Collection — 작업 메트릭 자동 수집

매 작업 실행 후 소요 시간, 단계별 타이밍, 성공/실패, 재시도 횟수를
`results/metrics/`에 자동 기록한다.
dev PC의 workflow-retrospective 스킬이 이 데이터를 분석하여 비효율을 찾는다.

**핵심 원칙: 작업 흐름을 방해하지 않는다.**
메트릭 수집 실패가 작업 실패를 일으키면 안 된다.
기록에 실패하면 경고만 남기고 작업은 정상 진행한다.

> **향후 확장 (방안 2/3 전환 시):**
>
> **방안 2:** 메트릭이 N건 쌓이면 experience.jsonl에 "회고 시점 도래" 알림 기록.
> dev의 schedule 스킬이 이를 감지하여 자동 회고 실행.
>
> **방안 3:** 이상 탐지 — 이전 평균 대비 2배 이상 소요되거나 새 에러 유형 등장 시
> 즉시 experience에 경고 기록. workflow-optimizer가 즉각 대응안 생성.

---

## Folder Structure

```
$base/results/metrics/
├── metrics_{YYYY-MM-DD}.jsonl   ← 일별 메트릭 로그
├── experience.jsonl              ← 축적 관찰 (append-only)
└── summary_latest.json           ← 최근 실행 요약 (덮어쓰기)
```

최초 사용 시 `metrics/` 폴더가 없으면 `create_directory`로 생성한다.

---

## Metric Record Schema

매 작업 실행 후 `metrics_{date}.jsonl`에 한 줄 append:

```json
{
  "id": "007",
  "command": "check-block",
  "service": "chatgpt",
  "timestamp": "2026-03-18T14:30:00",
  "success": true,
  "duration_seconds": 45,
  "phase_timings": {
    "browser_start": 28,
    "page_load": 8,
    "input_prompt": 3,
    "wait_response": 4,
    "screenshot": 2
  },
  "retry_count": 0,
  "error_type": null,
  "prompt_used": "한글날",
  "notes": ""
}
```

### Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| id | string | yes | 작업 요청 ID (result의 id와 동일) |
| command | string | yes | 실행한 command |
| service | string | no | 대상 서비스명 (APF 작업일 때) |
| timestamp | ISO 8601 | yes | 실행 완료 시점 |
| success | boolean | yes | 성공 여부 |
| duration_seconds | number | yes | 전체 소요 시간 (초) |
| phase_timings | object | yes | 단계별 소요 시간. 아래 참조 |
| retry_count | number | yes | 재시도 횟수 (0 = 첫 시도에 성공) |
| error_type | string | no | 실패 시 에러 분류 |
| prompt_used | string | no | 사용한 테스트 프롬프트 |
| notes | string | no | 특이사항 |

### Phase Timings

command마다 phase 구성이 다르다. 정확한 측정이 어려운 경우 추정치를 기록하고
notes에 "estimated"라고 표시한다.

→ See `references/phase-definitions.md` for command별 phase 정의.

---

## Collection Flow

```
작업 시작
  ├── [시작 시각 기록]
  ├── [각 phase 시작/종료 시각 기록]
  ├── 작업 실행 (기존 Step 2 flow 그대로)
  ├── [종료 시각 기록]
  ├── result.json 작성 (Step 3)
  └── 메트릭 기록 (Step 4)
       ├── duration 계산
       ├── phase_timings 계산
       ├── metrics_{date}.jsonl에 append
       └── summary_latest.json 갱신
```

**타이밍 측정 방법:**

PowerShell 실행 시 각 주요 단계의 전후에 시각을 기록한다.
Cowork이 각 desktop-commander 호출의 소요 시간을 관찰하고,
이를 phase별로 매핑한다.

정밀 측정이 어려운 경우(하나의 PowerShell 스크립트가 여러 phase를 포함)
전체 duration만 기록하고 phase_timings는 `{"total": N}`으로 단순화.

### Append 방법 (desktop-commander)

```
1. read_file로 기존 내용 읽기
2. 새 줄 추가
3. write_file로 전체 내용 쓰기
```

파일이 없으면 새로 생성한다.

---

## Experience Recording

메트릭 외에 정성적 관찰도 `experience.jsonl`에 기록한다.

### 자동 기록 조건

| 조건 | experience type | 기록 내용 |
|------|-----------------|---------|
| 작업 실패 | `failure` | 에러 유형, 원인, 우회 방법 |
| 재시도 후 성공 | `retry_success` | 몇 회 재시도, 어떤 조정이 효과적이었는지 |
| 이상 소요 시간 | `slow_execution` | 평균 대비 2배 이상 → 원인 기록 |
| 새로운 에러 유형 | `new_error` | 기존에 없던 에러 → 상세 기록 |

### Experience Record 형식

```json
{
  "type": "failure",
  "date": "2026-03-18",
  "task_id": "007",
  "command": "check-block",
  "detail": "Chrome 포커스 상실로 SendKeys 입력 안됨. AppActivate 재시도로 해결.",
  "action_taken": "AppActivate 후 500ms 대기 추가",
  "suggestion": "check-block 시작 전 항상 AppActivate 먼저 실행하면 예방 가능"
}
```

### 이상 소요 시간 판단

최근 10건 동일 command의 평균 대비 2배 이상이면 `slow_execution` 기록.
10건 미만이면 판단하지 않는다 (데이터 부족).

---

## Summary Latest

매 작업 후 `summary_latest.json`을 갱신한다. 가장 최근 실행의 스냅샷.

```json
{
  "last_task": {
    "id": "007",
    "command": "check-block",
    "success": true,
    "duration_seconds": 45,
    "timestamp": "2026-03-18T14:30:00"
  },
  "today_stats": {
    "total": 5,
    "success": 4,
    "failed": 1,
    "avg_duration": 38
  },
  "all_time_stats": {
    "total": 42,
    "success": 38,
    "failed": 4,
    "avg_duration": 41
  }
}
```

**누적 계산 방법:**
1. 이전 `summary_latest.json`을 읽는다 (없으면 초기값 `{total:0, success:0, failed:0}`)
2. `all_time_stats`에 현재 작업 결과를 누적: total+1, success/failed 갱신
3. `avg_duration`은 `(이전_avg * (total-1) + 현재_duration) / total`로 근사 계산
4. `today_stats`는 오늘 날짜가 바뀌면 리셋

이 파일은 dev PC에서 "현재 상태 궁금하다"고 할 때 빠르게 확인하는 용도.
상세 분석은 metrics JSONL에서 수행한다.

---

## Error Handling

| 상황 | 대응 |
|------|------|
| metrics 폴더 없음 | 폴더 생성 후 기록 |
| write_file 실패 | 대화 메시지로 경고, 작업 결과는 정상 반환 |
| read_file 실패 (append 시) | 새 파일로 생성 |
| 타이밍 측정 누락 | duration만 기록, phase_timings는 `{"total": N}` |
