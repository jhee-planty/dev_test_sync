---
name: workflow-retrospective
type: A
description: "APF 테스트 자동화 워크플로우 회고 및 최적화 스킬 (dev PC 전용). test-pc-worker가 수집한 메트릭 로그와 experience를 분석하여 비효율 패턴을 탐지하고, 스킬 개선안을 제시한다. Use this skill whenever: \"회고해줘\", \"비효율 분석\", \"워크플로우 개선\", \"어디가 느려?\", \"뭐가 불필요해?\", \"최적화\", \"retrospective\", \"메트릭 분석\", \"로그 분석\", \"작업 통계\", \"패턴 분석\", or any request to review and optimize the APF test automation workflow. Also trigger when the user says \"개선점 찾아줘\" or \"이거 왜 이렇게 오래 걸려?\""
---

# Workflow Retrospective Skill

## Purpose

APF 테스트 자동화 파이프라인(HAR 캡처 → 분석 → 등록 → 빌드 → 테스트) 전반의
실행 기록을 분석하여 비효율을 찾고 개선안을 제시하는 스킬.

**핵심 원칙:** 데이터 기반 판단. "느린 것 같다"가 아니라 "check-block 평균 47초,
이 중 브라우저 시작 대기가 30초를 차지"처럼 근거를 갖춘 분석을 한다.

**현재 단계 (방안 1 — 수동 회고):**
사용자가 "회고해줘"라고 하면 메트릭 로그를 읽어서 분석 리포트를 생성한다.
메트릭은 매 작업마다 test PC의 test-pc-worker 스킬(Step 4)이 자동 기록한다.

> **향후 발전 경로 (충분한 경험 축적 후):**
>
> **방안 2 — 자동 회고 스케줄:**
> schedule 스킬을 활용하여 일정 주기(매일 또는 N건 작업 완료 후)로
> 자동 회고 태스크를 실행. 사용자는 리포트만 확인하고 "적용해"로 승인.
> → 전환 조건: metrics 로그가 30건 이상 쌓이고, 반복되는 비효율 패턴이 3개 이상 확인될 때.
>
> **방안 3 — workflow-optimizer 전용 스킬:**
> 회고 + 패치 제안 + 적용까지 하나의 사이클로 캡슐화.
> 다른 스킬의 SKILL.md를 직접 읽고 개선 diff를 생성하여 사용자 승인 후 적용.
> experience에 "적용 전/후 비교"를 기록하여 개선 효과를 추적.
> → 전환 조건: 방안 2로 3회 이상 회고를 완료하고, 스킬 패치가 2건 이상 발생했을 때.

---

## Data Sources

회고 데이터는 **읽기**와 **쓰기** 경로가 분리되어 있다.
Git 충돌 방지를 위해 dev PC는 `requests/`에만, test PC는 `results/`에만 쓴다.

**읽기 (입력):**

| 데이터 | 경로 | 생성자 |
|--------|------|--------|
| 작업 메트릭 (신규) | `$GIT_SYNC_REPO/results/metrics/` | test-pc-worker가 신규 생성 |
| 작업 메트릭 (아카이브) | `workflow-retrospective/metrics/` | 2026-03-26 이전 데이터 |
| test 경험 로그 | `workflow-retrospective/metrics/retro_experience.jsonl` | dev가 관리 |
| 작업 결과 파일 | `$GIT_SYNC_REPO/results/{id}_result.json` | test-pc-worker |
| 작업 요청 파일 | `$GIT_SYNC_REPO/requests/{id}_{command}.json` | cowork-remote (dev) |
| 큐 히스토리 | `$GIT_SYNC_REPO/queue.json` | cowork-remote (dev) |
| 이전 회고 리포트 | `workflow-retrospective/metrics/` | 이 스킬 (dev) |
| 분류 인덱스 (archive) | `local_archive/archived/index.json` | archive-results |
| 서비스별 실패 lessons | `archive-results/lessons/{service}_failures.md` | archive-results |
| 아카이브 메트릭 | `archive-results/archive_metrics.jsonl` | archive-results |

**쓰기 (출력):**

| 산출물 | 경로 | 비고 |
|--------|------|------|
| 회고 리포트 | `workflow-retrospective/metrics/retrospective_{date}.md` | dev가 쓰기 |
| 회고 경험 로그 | `workflow-retrospective/metrics/retro_experience.jsonl` | dev가 쓰기 |

`$GIT_SYNC_REPO`는 Git 저장소(dev_test_sync)의 로컬 clone 경로.
직접 실행 시: `~/Documents/workspace/dev_test_sync/`

**Cowork에서 사용 시:** Git 저장소 폴더를 Cowork에 마운트(폴더 선택)해야 한다.
마운트된 경로가 `$GIT_SYNC_REPO`가 된다.

---

## Analysis Flow

### Step 0 — Archive 선행 실행

회고 전에 최신 결과를 먼저 정리해야 정확한 분석이 된다.
archive-results 스크립트를 실행하여 과거(local_archive) + 현재(results/)를 통합 처리한다.

```bash
python3 ~/.claude/skills/archive-results/archive_results.py \
  --input ~/Documents/workspace/dev_test_sync/local_archive \
  --output ~/Documents/workspace/dev_test_sync/local_archive/archived \
  --live ~/Documents/workspace/dev_test_sync
```

이 단계를 거치면 index.json, lessons/, archive_metrics.jsonl이 최신 상태가 된다.

### Step 0.5 — 이전 회고 adoption status 확인 (2026-04-22 추가)

새 제안을 생성하기 전 이전 회고 제안의 adoption 을 확인한다.
adoption gap 이 크면 단순 반복 제안 생성 대신 이전 unadopted 제안 재검토 우선.

```bash
bash $SKILL_DIR/runtime/parse-retro-adoptions.sh
```

**출력 JSON 해석**:

| 필드 | 의미 | 후속 동작 |
|------|------|---------|
| `status == "ok"` | 가장 최근 retrospective 의 adoption 표 파싱 성공 | `warning` 필드 확인 |
| `status == "no_adoption_table"` | 이전 회고에 adoption 표 없음 | 첫 회고 — 건너뛰고 Step 1 |
| `status == "no_retrospective_found"` | retrospective 없음 | 건너뛰고 Step 1 |
| `warning != null` | unadopted 비율 ≥ 40% | **자동 pivot** — items 중 key=="미적용" 우선 재검토 모드 전환 후 신규 제안 작성 진행 |
| `counts.미적용` | unadopted 제안 수 | 우선 조사 대상 |
| `counts.적용` | 적용 완료 제안 수 | 참고 (반복 제안 금지) |

**원칙 (INTENTS §3 I3)**:
- 같은 카테고리의 제안이 2회 연속 "미적용" 이면 Step 3 개선안 도출에서 해당 제안을 **삭제 후보** 로 별도 분류
- unadopted → 적용 전환을 위한 **사용자 대화 항목** 으로 리포트 상단에 포함

**참조**: `runtime/parse-retro-adoptions.sh`

### Step 1 — 데이터 수집

```
1. $GIT_SYNC_REPO/results/metrics/ 스캔 (Cowork: `mcp__github__get_file_contents`로 최신 데이터 수신)
2. metrics_{date}.jsonl 파일들을 읽어서 전체 메트릭 로드
3. archive-results 출력 로드: index.json (서비스별 성공/실패 분포), lessons/ (실패 패턴)
4. experience.jsonl 에서 축적된 관찰 사항 로드
5. 기간 필터링 (사용자가 기간 지정 시 적용)
```

사용자 미지정 시 자동: metrics 30건 미만이면 전체, 30건 이상이면 최근 7일.

### Step 2 — 패턴 분석

5가지 차원에서 데이터를 분석한다:
소요 시간, 실패 패턴, 불필요한 동작, 워크플로우 병목, 자원 활용.

→ See `references/analysis-dimensions.md` for 각 차원의 분석 방법, 개선 신호, 복합 패턴 교차 분석.

### Step 3 — 개선안 도출

분석 결과를 바탕으로 구체적인 개선안을 제시한다.

개선안의 형식:
```
[개선안 #{N}]
- 문제: {데이터에서 발견된 비효율}
- 근거: {메트릭 수치}
- 제안: {구체적 변경 내용}
- 대상 스킬: {수정할 스킬/파일}
- 기대 효과: {예상 개선 수치}
- 우선순위 (자동 산정): HIGH (병목 phase ≥ 50% 시간 OR 동일 에러 ≥ 3회) / MEDIUM (10-50% / 1-2회) / LOW (그 외)
```

### Step 4 — 리포트 생성

분석 결과를 마크다운 리포트로 생성한다.

→ See `references/report-template.md` for 리포트 구조.

리포트 저장 위치: `workflow-retrospective/metrics/retrospective_{date}.md`

**아카이브 정책:** 새 리포트 생성 시 이전 리포트는 `workflow-retrospective/metrics/`에 날짜별로 보관.
Git에는 최신 리포트만 유지한다.

---

## Commands

사용자 트리거에 따른 동작:

| 트리거 | 동작 |
|--------|------|
| "회고해줘" / "retrospective" | 전체 분석 + 리포트 생성 |
| "어디가 느려?" / "병목 분석" | 소요 시간 분석만 집중 |
| "실패 패턴" / "에러 분석" | 실패/재시도 패턴만 집중 |
| "통계 보여줘" / "메트릭 요약" | 수치 요약만 (분석 없이) |
| "이전 회고 확인" | 이전 회고 리포트 읽기 + 미적용 개선안 목록 |

**참고:** "개선안 적용"은 사용자가 리포트를 보고 직접 지시한다.
자동 적용은 방안 3(workflow-optimizer) 전환 후 가능해진다.

---

## Experience Tracking

회고 결과 자체도 경험으로 기록한다.

회고를 수행할 때마다 `workflow-retrospective/metrics/retro_experience.jsonl`에 append:
```json
{
  "type": "retrospective",
  "date": "2026-03-18",
  "period": "2026-03-11 ~ 2026-03-18",
  "tasks_analyzed": 15,
  "issues_found": 3,
  "improvements_proposed": 2,
  "improvements_applied": 0,
  "summary": "check-block 브라우저 시작 대기 30초 → Chrome 사전 실행으로 5초로 단축 가능"
}
```

이 기록은 다음 회고 시 "이전에 제안했지만 아직 적용하지 않은 개선안"을 추적하는 데 사용한다.

---

## Outbound Dependencies

본 skill (Type A) 이 **참조하는** 것들. Inbound caller 는 IoC (원칙 8.1) 에 따라 명시하지 않음 — 2026-04-23 skill-atomicity 재토론 R3.

- **`archive-results`** (dev, Type B): Step 0 에서 선행 실행하여 서비스별 성공/실패 분류, lessons, 메트릭을 확보. 회고 분석의 **데이터 기반**.
- **`research-gathering`** (dev, Type B): Step 0.5 에서 사용. 회고에서 발견된 개선 제안 중 공식 원칙 문서 (INTENTS / lessons / MEMORY) 미반영 항목을 cross-skill scan 해 promotion_proposal 생성.

본 skill 의 출력은 dev PC 측에서 수동 검토되며, 다른 skill 이 직접 소비하지 않는다 (사용자가 적절한 skill 로 연결).
