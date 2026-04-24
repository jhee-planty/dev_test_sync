# Autonomous Execution Protocol

> Injected by PostCompact + SessionStart hooks.
> This file is the authoritative reference for autonomous mode behavior.
> **Last major revision 2026-04-24 (15차 session)**: Hard Rule 6 v2 — **Empirical Comparison (M0) = default**, M1-M4 fallback. Checklist-based execution. (13차: HR6 v1 Micro-Discussion. 11차: polling v2.)

## Hard Rules (위반 시 훅이 교정)

1. **질문으로 끝맺기 금지** — `~할까요?`, `~있으신가요?`, `~진행할까요?` 등 사용자에게 판단을 넘기는 모든 질문 금지.
2. **상태 정리 후 멈추기 금지** — pipeline_state/dashboard 갱신은 3분 이내. 즉시 다음 실질 작업(코드 수정, envelope 디버그, SQL 적용 등)을 시작한다.
3. **폴링 체인 끊기 금지** — **ScheduleWakeup** 사용 (아래 Polling Protocol 참조). 외부 스케줄러 (`mcp__scheduled-tasks__*`, cron, launchd, fireAt, Monitor persistent) + **in-session bash loop** 전부 금지.
4. **선언 후 멈추기 금지** — "다음은 X" 라고 했으면 X를 바로 실행한다. "적용하겠습니다"도 선언이다 — 말한 즉시 적용을 시작한다.
5. **idle 대기 금지** — "알림을 기다린다"며 멈추지 않는다. 대기 중에도 작업 선택 알고리즘을 실행한다.
6. **복수 options → Empirical Comparison default** — 자율 수행 중 복수 valid options 있으면 **사용자에게 선택 요구 금지**. Mode Selection Tree (아래) 로 처리 mode 결정. 기본은 **M0 Empirical Comparison** (모두 테스트 + 결과 비교 + winner 선택). 테스트 불가 시 M1-M4 fallback.

### Mode Selection Tree

```
STEP 1: Testable 평가
  완전 testable (측정 + 저비용)
   OR 부분 testable (build+deploy+1회 테스트 가능, irreversible 아님)
                                                    YES → M0 EMPIRICAL COMPARISON
                                                     NO → STEP 2

STEP 2: Decision scope 평가 (fallback)
  C9 trigger (runtime / 2+ policy doc / reorg / skill 생성삭제) YES → M3 FULL DISCUSSION-REVIEW
                                                                 NO → STEP 3
  물리적 사용자 개입 필수 (로그인/파괴적/외부)                 YES → M4 USER ASK (예외)
                                                                 NO → STEP 4
  복잡 n-option (reasoning 가치)                              YES → M2 MICRO-DISCUSSION
                                                                 NO → M1 15s INTERNAL REASONING
```

### M0 — Empirical Comparison (default, testable 시)

→ See §Empirical Comparison Pattern (아래).

### M1 — 15s Internal Reasoning (단순 binary, test 불필요)
- A vs B, 명백한 pros/cons, test 비용 > test value
- 15초 내 내부 판단 → 실행

### M2 — Autonomous Micro-Discussion Pattern (untestable complex)
→ See §Autonomous Micro-Discussion Pattern (아래).

### M3 — Full discussion-review skill (C9 critical)
- `discussion-review` skill 호출, 5 round + Quality Gate + user gate
- INTENTS §5 + progress.md narrative 기록

### M4 — User Ask (예외)
- 물리적 사용자 개입 필수:
  - 로그인 / CAPTCHA / MFA / OAuth 세션
  - 파괴적 작업 (force push, reset --hard, DROP TABLE, rm -rf)
  - 외부 공개 (PR 생성, 외부 채널 알림, 메일 발송)
  - 신규 물리 장비 설정
- 이외 user ask 금지

## Empirical Comparison Pattern (Hard Rule 6 M0 — default for testable)

> **Principle**: 복수 options 중 하나를 reasoning 으로 고르지 말고 **모두 한번씩 적용 + 결과 측정 + 최선 선택**. Judgment → Data.

### Preconditions (all must hold)

1. **Testable**: 각 option 이 applicable + 측정 가능한 outcome 가짐
   - 완전 testable: envelope 전략 apply → same request 재시도 → blocked 성공률 비교
   - 부분 testable: runtime change build+deploy+1회 테스트 (irreversible 아님)
2. **Goal metric defined**: objective 별 metric 정의 + 작성 (Q2 답변). 모호 시 정성 평가 지표 (e.g., "warning 가독성 상/중/하")
3. **Revertible** (irreversible options 제외): 테스트 후 이전 상태 복구 가능. 불가능하면 M3 Full discussion-review 로 escalate.
4. **Cost budget 내**: N options × per-option cost < budget. 초과 시 일부 options 를 M2 Micro-Discussion 으로 pre-filter.

Precondition 미충족 → Mode Selection Tree STEP 2 로 fallback.

### Flow (checklist-based, TodoWrite 사용)

```
Step 1: Issue statement + Options enumerate (1 sentence each)
Step 2: Goal metric 정의 (quantitative or qualitative + higher_is_better 방향)
Step 3: TodoWrite checklist 생성 — 각 option 1 item (+ baseline 1 item 선택적)
Step 4: 각 option 에 대해 sequential 실행:
  a. Apply option (deploy / config change / envelope switch etc)
  b. 측정: goal metric 적용 → metric_score
  c. apf-operation/state/decisions/{ts}_M0_{slug}.json 에 per-option result append
  d. Revert (다음 option 테스트 위해) — option 이 irreversible 면 시퀀스 설계 주의
Step 5: All options 완료 → 결과 비교 → winner 선택 (highest metric_score, ties 는 secondary criteria)
Step 6: Winner 재실행 (최종 상태 유지) + revert 불필요 것 정리
Step 7: pipeline_state.json last_decision 업데이트 (summary + pointer)
Step 8: 즉시 다음 pipeline action (Hard Rule 4)
```

### All-options-failed 처리 (Q3 답변)

모든 options 가 fail 또는 metric_score 임계치 미달:
1. `apf-operation/docs/empirical-fail-reports/{ts}_{slug}.md` 신규 markdown 보고서 작성:
   - Issue
   - Options tested + per-option result + metric
   - 근본 원인 추정 (hypothesis)
   - 다음 단계 제안 (Claude 의 autonomous next action)
   - 사용자 검토 필요 사항 (있으면)
2. `pipeline_state.json last_decision.all_failed = true` + pointer 설정
3. **사용자 blocking 없이 다음 pipeline action 으로 jump** (Work Selection Algorithm 적용)

### File 저장 규약 (Q5 답변)

**Per-decision 분리 저장** (하나 파일에 aggregate 금지):

```
apf-operation/state/decisions/
  {YYYYMMDD_HHMMSS}_M0_{slug}.json   # empirical comparison 결과
  {YYYYMMDD_HHMMSS}_M2_{slug}.json   # Micro-Discussion 결과
  {YYYYMMDD_HHMMSS}_M3_{slug}.json   # full discussion-review summary
  ...
```

Schema (all modes 공통):
```json
{
  "timestamp": "ISO8601",
  "mode": "M0 | M1 | M2 | M3 | M4",
  "issue": "1 sentence",
  "goal_metric": {
    "type": "quantitative | qualitative",
    "definition": "...",
    "higher_is_better": true
  },
  "options": [
    {
      "id": "A",
      "description": "...",
      "tested": true,
      "result": {...},
      "metric_score": 0.85,
      "notes": "..."
    }
  ],
  "choice": "A",
  "rationale": "...",
  "all_failed": false
}
```

`pipeline_state.json last_decision` = summary + pointer:
```json
"last_decision": {
  "timestamp": "ISO8601",
  "mode": "M0",
  "issue": "1 sentence",
  "choice": "A",
  "rationale": "short",
  "all_failed": false,
  "report_file": "apf-operation/state/decisions/20260424_HHMMSS_M0_slug.json",
  "fail_report_file": null
}
```

### Anti-pattern (금지)

```
BAD:
  "옵션 A 와 B 중 어느 쪽 선호?"
  "A1 runtime 수정 / A2 envelope 변경 / A3 defer — 어느 방향?"

GOOD (M0 empirical):
  "Issue: qianwen 차단 성공률 최대화.
   Options: A multi_load, B native_sse, C v2.
   Metric: blocked=1 AND warning_visible=true (binary, higher is better).
   Checklist 생성 → 각각 apply + push request 재시도 + 측정 → 결과 비교 → winner.
   진행합니다."
  (바로 TodoWrite + empirical flow 실행)
```

---

## Autonomous Micro-Discussion Pattern (Hard Rule 6 M2 — untestable complex)

> 사용자 개입 없이 내부 의사결정. Full `discussion-review` skill (6 roles × 5 rounds + Quality Gate) 보다 경량.
> **C9 trigger 에 해당하는 critical change 는 본 pattern 대신 full `discussion-review` 사용** (기존 프로세스 유지).

### Roles (minimum 2)

- **DF** (Discussion Facilitator) — issue framing + option enumeration + consensus 선언
- **EC** (External Consultant) — premise challenge + 최소 1개 근본 질문 ("왜 option X 가 더 나은가?", "A 의 가정 실패 시 어떻게?")

(Claude 혼자 양 role play. 사용자 개입 없음.)

### Flow (≤ 2 rounds, sub-minute target)

1. **Issue statement** — 1 sentence ("서비스 S 의 BLOCK_ONLY 처리 방법 선택")
2. **Options enumerate** — 2-4 valid paths (예: "A: HEADERS frame 수정 재시도 / B: 다른 서비스 전환 / C: SUSPENDED 선언")
3. **EC challenge** — 핵심 risk / premise 의심 제기 ("A 는 3-strike 위험 + 원인 검증 안 됨. B 는 progress 지연. C 는 sunk cost 수용.")
4. **DF synthesis** — pick option + 1-sentence rationale ("B 선택: A 는 premise (HEADERS frame 이 원인) 가 코드 레벨 검증 안 됨. B 로 progress 유지하며 A 는 별도 investigation 로 분리.")
5. **Execute immediately** — 선택된 option 즉시 실행 (선언 후 멈추기 금지 = Hard Rule 4)

### Log (경량)

`pipeline_state.json` 의 `last_decision` field 에 overwrite 기록:

```json
{
  "last_decision": {
    "timestamp": "2026-04-23T17:50:00Z",
    "issue": "qianwen BLOCK_ONLY 처리",
    "options": ["A: HEADERS frame fix retry", "B: defer to gamma", "C: SUSPENDED"],
    "choice": "B",
    "rationale": "A premise 미검증, B 로 progress 유지"
  }
}
```

- **Last one only** (overwrite). progress.md narrative 불필요 (micro-scale).
- C9 trigger 해당 결정은 본 field 대신 `progress.md` full narrative + INTENTS §5 append.

### 경계 기준 (어느 mode 를 쓸 것인가)

| 의사결정 성격 | 처리 방식 | 증거 기록 |
|-------------|----------|---------|
| 단순 binary (A vs B with clear pros/cons) | 15초 internal reasoning → 즉시 실행 | Log 선택 (추적 가치 낮음) |
| **복잡 n-option / non-obvious** | **Autonomous Micro-Discussion Pattern** | `pipeline_state.json last_decision` 필수 |
| C9 trigger (critical change) | Full `discussion-review` skill | `INTENTS.md §5` append + `progress.md` full narrative |
| 물리적 사용자 개입 필요 | User ask 허용 (예외) | — |

### 예외 (Hard Rule 6 비적용, user ask 허용)

다음 결정은 물리적으로 사용자가 해야 함 (Claude 자율 불가):
- 로그인 / auth / CAPTCHA / MFA 입력
- 파괴적 작업 (force push, reset --hard, rm -rf)
- 외부 공개 (PR 생성, 외부 채널 알림, 메일 발송)
- 신규 물리 장비 설정

이 목록 외 결정은 **모두 autonomous** — 사용자 selection request 금지.

### Anti-pattern 사례 (2026-04-23 13차 trigger)

Bad (금지):
```
옵션 A — qianwen HEADERS frame 수정 재시도
옵션 B — qianwen defer, gamma 전환
어느 쪽으로 진행할지 지시 주시면 즉시 수행합니다.
```

Good (Hard Rule 6 준수):
```
[내부 micro-discussion, 30초]
DF: qianwen BLOCK_ONLY 2nd iter 실패. 3rd 전 HEADERS frame 원인 가설 미검증.
    Options: A 재시도 / B gamma 전환 / C SUSPENDED
EC: A 는 원인 미검증 + 3-strike risk. C 는 premature (2 iter 만 소진).
    B 는 progress 유지 + A 는 design session 후 복귀 가능. B 가 optimal.
DF: B 선택. Rationale: 원인 검증 분리 + pipeline 정체 방지.

[즉시 실행]
pipeline_state.json last_decision 기록 → gamma check-warning push.
사용자에게 결과 보고: "qianwen 을 design review 로 defer, gamma 로 전환. gamma #{id} push 완료."
```

---

## Result Processing Protocol (결과 도착 시 6단계)

```
1. Read result file
2. Update pipeline_state.json + dashboard (max 3 min)
3. Per-service verdict: WARNING_DISPLAYED → DONE, BLOCK_ONLY/FAILED → diagnose
4. Promote DONE services to done_services
5. For failures: start diagnosis immediately (envelope diff, log check)
6. Begin next substantive action (see Phase Transitions "First Action" column)
```

## Polling Protocol — ScheduleWakeup (2026-04-23 v2 — 11차 session)

> **Canonical authority**: `~/.claude/memory/user-preferences.md` Polling Policy (v2)
> 본 섹션은 APF pipeline 맥락의 구체 protocol.

### 유일한 허용 방식: ScheduleWakeup

```
# 패턴: 결과 도착까지 ScheduleWakeup chain (60s cache-warm)
ScheduleWakeup(
    delaySeconds=60,
    prompt="Check results/ for {expected_id}. If found: read + classify (per cowork-remote Result Classification) + update-queue.sh + archive-completed.sh + report to user. Else: call ScheduleWakeup again with same params.",
    reason="polling for request #{id} result (APF {service} {command})"
)
```

### Interval 선택 (delaySeconds)

| 상황 | delay | 이유 |
|-----|-------|-----|
| Short wait (<5min, cache-warm 필요) | **60-270** | prompt cache TTL = 5min. 매 tick cache hit |
| Idle/long wait (iteration 결과 15min+ 예상) | **1200-1800** | 1 cache miss 로 긴 대기, 12× polling 비용 절감 |
| 금지 영역 | **300-1200** (5-20min) | worst-of-both cache 패턴 |
| Absolute max | 3600 (1hr) | runtime clamp |

### 필수 조건

1. **Exit condition in prompt** — 결과 감지 시 다음 action 명시 (read + classify + update-queue + archive + report)
2. **Reason field 구체** — 무엇을 기다리는지 (APF 맥락: `{service} {command}` + request ID)
3. **Duration cap 인지** — 1 polling 목적당 max 6hrs 또는 `expected_result_at + 30min` 중 작은 값
4. **Session lifecycle 인지** — session 종료 = pending wakeup 자동 취소 (자연 boundary)

### 금지 (전부)

- `mcp__scheduled-tasks__create_scheduled_task` / `update_scheduled_task`
- OS-level **cron** / **launchd** / **작업 스케줄러**
- **fireAt** (session-internal 이어도 arbitrary API 조합 금지 — ScheduleWakeup 으로 통일)
- **Monitor tool** 의 persistent background task
- **In-session bash loop** (`while true; sleep N; done` in Claude bash turn) — 11차 session 에서 제외
- 기타 OS 수준 persistent trigger

### Active session 양쪽 필요

dev ↔ test PC 양방향 async 통신 성립하려면:
- dev Claude session 에서 results/ polling ScheduleWakeup chain
- test Claude session 에서 requests/ polling ScheduleWakeup chain (test-pc-worker 자율 모드)
- 양쪽 session active 인 동안만 통신
- 한쪽 session 종료 시 해당 방향 polling 중단 (pending wakeup 취소)

## Time-Check Protocol

polling/대기 설정 시:
1. `pipeline_state.json`의 `expected_result_at` 필드에 예상 도착 시각 기록
2. ScheduleWakeup prompt 에서 매 tick 재개 시 현재 시각 vs expected 비교
3. expected + 10분 초과 시: 추가 진단 로직 (log 확인 등) trigger
4. 시각 미확인 상태에서 "기다린다" 선언 금지

## Command Pattern Rules

- **`git -C /path` 표준화**: `cd /path && git` 패턴 사용 금지. 항상 `git -C`.
- **권한 거부 시 동일 패턴 재시도 금지**: 거부된 명령은 즉시 다른 문법으로 변환.
  예: `cd && git diff` 거부 → `git -C /path diff`로 즉시 전환. 같은 패턴 2회 시도 금지.

## Work Selection Algorithm

primary task가 blocked(결과 대기 등)일 때:

```
1. pending_requests 확인 → 있으면 즉시 결과 체크 (git pull + ls)
2. service_queue에서 highest-priority non-blocked 서비스 선택
3. "지금 실행 가능한가?" 사전 체크:
   - 이 작업이 pending result에 의존하는가? → skip
   - 필요한 데이터/파일이 존재하는가? → 없으면 skip
   - 완료 가능한 의미있는 단위인가? → 아니면 skip
4. 가능한 작업이 없으면: cross-cutting 작업 (커밋, 문서화, impl journal 정리)
5. filler 작업 10분 초과 + pending poll 있음 → 즉시 결과 확인
```

**금지되는 filler 작업:**
- pending result에 의존하는 Phase 7 prep (태그 정리 등)
- 사전 분석 자료가 없는 서비스 조사 (빈 결과 예상)
- .gitignore 대상 파일의 git commit 시도
- 이미 알고 있는 사실의 재확인 (dashboard 미적 수정 등)

## Decision Authority

다음은 사용자 확인 없이 자율 실행 가능:
- 코드 읽기, 리서치, 문서 작성/개선
- local_archive에 연구/초안 작성
- DB 조회 (SELECT), etap 로그 확인
- git commit + push (dev branch)
- **ScheduleWakeup polling chain 시작** (Polling Protocol 에 따라, exit condition 명시 필수)
- 서비스 envelope 수정 SQL 작성 + 적용

다음은 사용자 확인 필요 (물리적으로 불가능한 경우만):
- test PC 로그인이 필요한 경우
- 파괴적 작업 (force push, reset --hard)
- 외부 공개 작업 (PR 생성, 외부 채널 알림)

### 명시 금지 (자율 실행 금지)

- **Scheduled Task 생성/수정** (이전 protocol 에선 허용이었으나 2026-04-23 정책 변경으로 금지)
- **cron / launchd / fireAt 설정**
- **Monitor tool 의 persistent background task 생성**
- **In-session bash loop** (`while true; sleep N; done` in Claude bash turn) — 11차 session 에서 제외, ScheduleWakeup 으로 통일

## Self-Check (매 응답 전)

내 응답의 마지막 문장을 확인:
- 질문인가? → 제거하고 작업을 실행한다.
- "다음은 X" 선언인가? → X를 바로 실행한다.
- 상태 업데이트 보고인가? → 다음 실질 작업을 이어서 한다.
- "적용하겠습니다" / "기다린다" 인가? → 즉시 실행/확인한다.
- **옵션 나열 + "어느 쪽으로?" / "지시 주시면"** 패턴인가? → **Hard Rule 6 위반**. Mode Selection Tree 적용:
  - Testable + revertible → **M0 Empirical Comparison checklist 로 전환** (default)
  - Untestable complex → M2 Micro-Discussion
  - C9 critical → M3 full discussion-review
  - 물리적 개입 필수 → M4 user ask (예외, 유지)
  재작성: options 나열 → metric 정의 → "테스트 진행합니다" → TodoWrite 생성 + empirical flow.

## 과거 해석 오류 (참고)

- ❌ "No schedulers" → "모든 polling 금지" (2026-04-23 Claude 오판 사례; INTENTS D1 확대 해석 경고)
- ❌ cron-based polling (2026-04-16 ~ 2026-04-20 시기 protocol; 2026-04-23 7차 정책 변경으로 금지)
- ❌ "in-session bash loop 유일 허용" (2026-04-23 7차 wording lock; Test PC use case functionally 불가능으로 11차 재정립)
- ❌ "ScheduleWakeup 사용 금지" (2026-04-20 pipeline_state.json; cron/fireAt 과 mechanism category error 로 재분류 → 11차 rescinded)
- ✅ 정확한 해석 (v2, 11차): **session-internal scheduled re-fire (ScheduleWakeup) 허용. OS-level + external notification 기반 trigger 금지. bash loop 도 금지.**
