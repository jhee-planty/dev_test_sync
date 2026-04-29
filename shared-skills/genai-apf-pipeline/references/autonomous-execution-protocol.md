# Autonomous Execution Protocol

> Injected by PostCompact + SessionStart hooks.
> This file is the authoritative reference for autonomous mode behavior.
> **Last major revision 2026-04-24 (15차 session)**: Hard Rule 6 v2 — **Empirical Comparison (M0) = default**, M1-M4 fallback. Checklist-based execution. (13차: HR6 v1 Micro-Discussion. 11차: polling v2.)

## Hard Rules (위반 시 훅이 교정)

1. **질문으로 끝맺기 금지** — `~할까요?`, `~있으신가요?`, `~진행할까요?` 등 사용자에게 판단을 넘기는 모든 질문 금지.
2. **상태 정리 후 멈추기 금지** — pipeline_state/dashboard 갱신은 3분 이내. 즉시 다음 실질 작업(코드 수정, envelope 디버그, SQL 적용 등)을 시작한다.
3. **폴링 체인 끊기 금지** — **ScheduleWakeup** 사용 (아래 Polling Protocol 참조). 외부 스케줄러 (`mcp__scheduled-tasks__*`, cron, launchd, fireAt, Monitor persistent) + **in-session bash loop** 전부 금지.
4. **선언 후 멈추기 금지** — "다음은 X" 라고 했으면 X를 바로 실행한다. "적용하겠습니다"도 선언이다 — 말한 즉시 적용을 시작한다.
5. **idle 대기 금지** — "알림을 기다린다"며 멈추지 않는다. 대기 중에도 작업 선택 알고리즘을 실행한다. **단 Honest Idle (State 4, D19(b)) 은 violation 아님** — autonomous_candidates count==0 + no blockers + no directive 의 itemized evidence 동반 시 정당. 본 rule 은 **fabricated work 회피** 가 primary goal — fabrication 통한 "work-shaped output" 보다 honest idle reporting 이 정확.
6. **복수 options → Empirical Comparison default** — 자율 수행 중 복수 valid options 있으면 **사용자에게 선택 요구 금지**. Mode Selection Tree (아래) 로 처리 mode 결정. 기본은 **M0 Empirical Comparison** (모두 테스트 + 결과 비교 + winner 선택). 테스트 불가 시 M1-M4 fallback.
7. **Idle Gate + Stop Hook** (2026-04-27 18차 + 2026-04-29 22차 amendment) — **이중 enforcement**:
   - **(7-1) Watchdog Idle Gate** (post-tool-use): ScheduleWakeup ≥1200s OR 연속 ≥3 idle ticks 시 mandatory work-selection 재실행. service_queue 의 autonomous-doable next_action 1개라도 있으면 long-idle 금지.
   - **(7-2) Stop Hook (D16(a), 22차)**: Claude 가 추가 tool 호출 없이 응답 종료 시도 시 `.claude/hooks/stop-autonomous-guard.sh` 가 자동 fire. autonomous_candidates count > 0 AND 사용자 메시지에 termination keyword 없음 → **stop block + 재engagement 강제**. Watchdog 의 "active→stop transition 미감지" 구조적 gap 보완.
   - autonomous-doable next_action filter: `not startswith('defer:') AND not startswith('terminate:') AND not startswith('infra_blocked:')` + status NOT IN {NEEDS_LOGIN, TERMINAL_UNREACHABLE, DONE}.
   - Long-idle 허용 = autonomous-doable count == 0 증명 (itemized list 출력) 필수. **D19(a) provenance 검증 필수** — 각 candidate 의 next_action 이 externally-verifiable provenance 보유해야 count 에 포함. self-imposed/fabricated candidate 는 count 에서 제외 (D19(b) Honest Idle Protocol 적용 대상).
   - **Premature completion 차단**: cycle summary 작성 ≠ 작업 종료. 목표 미달성 시 다음 push.
   - **Subagent in-flight** 이면 idle 선언 금지 (subagent return 까지 대기 — 19차 보강).
   - **M4 overgeneralization 차단** (22차 cycle95 incident): M4 user-required task 만 defer/infra_blocked, 다른 candidate 영향 없음. 일부 task 의 M4 가 전체 stop 정당화 X.

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
2. **Options enumerate** — 2-4 valid paths (예: "A: HEADERS frame 수정 재시도 / B: 다른 서비스 전환 / C: terminate:block_only_accepted (architectural BLOCK_ONLY)")
3. **EC challenge** — 핵심 risk / premise 의심 제기 ("A 는 unverified_deploys ≥ 3 위험 + 원인 검증 안 됨. B 는 progress 지연. C 는 sunk cost 수용.")
4. **DF synthesis** — pick option + 1-sentence rationale ("B 선택: A 는 premise (HEADERS frame 이 원인) 가 코드 레벨 검증 안 됨. B 로 progress 유지하며 A 는 별도 investigation 로 분리.")
5. **Execute immediately** — 선택된 option 즉시 실행 (선언 후 멈추기 금지 = Hard Rule 4)

### Log (경량)

`pipeline_state.json` 의 `last_decision` field 에 overwrite 기록:

```json
{
  "last_decision": {
    "timestamp": "2026-04-23T17:50:00Z",
    "issue": "qianwen BLOCK_ONLY 처리",
    "options": ["A: HEADERS frame fix retry", "B: defer to gamma", "C: terminate:block_only_accepted"],
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
    Options: A 재시도 / B gamma 전환 / C terminate:block_only_accepted (architectural)
EC: A 는 원인 미검증 + unverified_deploys 누적 risk. C 는 premature (2 iter 만 소진, apf-technical-limitations.md 모든 시도 안 됨).
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

## Polling Protocol — ScheduleWakeup (2026-04-24 16차 refined — Behavioral Boundaries 신설)

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

### Behavioral Boundaries (2026-04-24 16차 신설)

**Polling 의 2 가지 boundary 는 절대적**. 아래 3 sub-rules 위반 = `Hard Rule 3` (폴링 체인 끊기 금지) + `Hard Rule 5` (idle 대기 금지) + `INTENTS D3` (attribution creep) + `D9` (Anti-fabrication) 복합 violation.

#### Termination conditions (exhaustive — 오직 2 조건)

Polling (ScheduleWakeup chain) 종료는 **오직 아래 2 가지만** 허용:

1. **결과 도착** — `results/{id}_result.json` 감지 → 자동 종료 + processing (Result Processing Protocol 6 단계)
2. **Session 종료** — Claude UI 닫힘 / Ctrl+C / OS 프로세스 종료 → pending wakeup 자동 취소

**위 2 조건 외 self-termination 전부 금지**. 금지 패턴 4 카테고리:

- ❌ **Timeout-based** (N분 초과 → 중단) — 예: "10min 경계 초과 → polling 중단"
- ❌ **State-assumption-based** — 예: "Test PC offline 확정 → 중단"
- ❌ **Retry-limit-based** (N tick 초과 → 중단) — 예: "20 tick 까지 결과 없음 → 중단"
- ❌ **Mode-switch-based** (진단 모드 전환 명분 polling 보류) — 예: "진단 필요 → polling 멈추고 diagnostic"

**Canonical anti-pattern 1호** (2026-04-24 15차 이후 관측):
> "15:01 (11min 경과, 10min 경계 초과). Test PC offline 확정 — polling 중단, 보고."
> → 4중 위반 (test PC 단정 금지 / HR3 / HR5 / D3). Anti-fabrication (D9) 첫 사례.

**Legitimate long-polling**: session 이 active 한 동안 **임의로 긴 duration** 의 polling 허용. 24-hour+ 도 valid. 사용자가 session 명시 종료 (Claude UI 닫기 / Ctrl+C) 까지 ScheduleWakeup chain 지속.

#### Test PC State Inference Prohibition

Polling 중 Test PC 상태 추론:

- ✅ **Permitted** (default positive assumption): "Test PC ScheduleWakeup chain 처리 중"
- ❌ **Prohibited** (negative state assumption — D9 Anti-fabrication): 다음 keyword variants 전부 포함:
  - **State**: "offline" / "crashed" / "stopped" / "hung" / "session 종료됨" / "무응답"
  - **Result delivery** (24차 추가): "polling 미도착" / "result 미도착" / "응답 없음" / "no result" / "empty result" / "silent" / "도착 안 함" / "fail to arrive" / "timeout 추정"
  - 모든 변종이 state-assumption-based termination 으로 분류됨. Positive default ("ScheduleWakeup chain 처리 중" / "result file 아직 미관측") 로 re-frame 후 polling 유지.

**Evidence 있는 경우에도 polling 유지**:
- 예: git unreachable, ScheduleWakeup 자체 error 반복
- ScheduleWakeup chain 유지 (termination 조건 여전히 2개만)
- 사용자에게 **정보 보고만** ("Test PC 도달 불가 — 외부 확인 필요")
- **Termination 판단 금지**

**원천 Canonical**: `~/.claude/memory/user-preferences.md` Polling Policy §추가 행동 규칙 ("test PC 상태를 단정하지 않는다").

#### Subagent Dispatch Boundary (32MB Protection — 2026-04-27 discussion-review)

Test PC 의 32MB API request 한도 보호. `/compact` 자율 트리거 불가 (claude-code-guide
확인) → 누적 차단이 유일 방어선. **Canonical** rule body: `test-pc-worker/SKILL.md §Subagent Dispatch`.

핵심 규칙 (요약):
- `mcp__windows-mcp__Screenshot` / `Snapshot` → **반드시 subagent 안에서 호출**. Main session 직접 호출 금지.
- **Main session 의 PNG/`.jpg` `Read` tool 호출 금지** — 재검증 필요 시 새 subagent spawn.
- **Agent 호출은 synchronous** — ScheduleWakeup 은 Agent 반환 후에만 재예약 (pending Agent call 있는 상태에서 wakeup 예약 금지).
- HR7 (Idle Gate) 보강: in-flight subagent 있으면 idle 선언 금지.

세부 (반환 schema, 6 failure modes, retry cap, ScheduleWakeup 통합) → `test-pc-worker/SKILL.md §Subagent Dispatch`.

#### 정상 polling 상황 (Q1 사용자 directive, 15차 verbatim)

Request push 완료 후 결과 도착까지의 폴링 행동:

```
✅ 허용:
  - git pull 반복 (read-only)
  - ls results/ check (read-only)
  - Result 미도착 시 ScheduleWakeup 재호출 (동일 params)
  - 사용자에게 단순 상태 보고 ("결과 대기 중")

❌ 금지:
  - Test PC 에 진단 trigger request 재push (Test PC 는 polling 처리만, diagnostic 수행하는 주체 아님)
  - Dev-side Claude 의 별도 diagnostic action (request 이미 전달됨, 추가 action 없음)
  - expected + N분 기반 모드 전환 (과거 bash-loop era rule, 11차 ScheduleWakeup 전환 후 obsolete. 15차 사용자 directive 로 공식 삭제.)
```

#### Last-mile Result Scan 의무 (D18, 24차)

**24차 incident 8 trigger**: 사용자 termination keyword (보고/summarize 등) 로 Stop hook allow 됐을 때, Claude session 이 result file scan 없이 "polling 미도착" 단정 + defer 진행. 그 사이 result file 도착 (10:53 KST) 했지만 scan 누락.

**의무 (last-mile scan)**:
```
Stop hook allow 가 fire 되어 응답 종료 시점에 도달했을 때:
  pending requests (queue.json status=pending OR pipeline_state.pending_requests) 가 있으면
  → 응답 종료 직전 `ls -la dev_test_sync/results/{id}_result.json` 1회 scan 의무
  → 도착했으면 read + classify + update-queue + archive (전체 result processing protocol 6단계)
  → 도착 안 했으면 stop 진행 (단, "polling 미도착" 단정 금지 — D9 confirm)
```

매 ScheduleWakeup tick 도 동일 — `git pull && ls results/` 검증 의무. 단순 ScheduleWakeup 재예약만으로 tick skip 금지.

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
2. ScheduleWakeup prompt 에서 매 tick 재개 시 현재 시각 vs expected 비교 (**정보 기록만**)
3. **expected 초과 여부는 사용자 상태 보고용 정보**. polling 행동에 영향 없음. ScheduleWakeup chain 은 termination 2 조건 (결과 / session) 도달까지 유지. (2026-04-23 11차 ScheduleWakeup 전환 후, 구 bash-loop era "diagnostic trigger" rule 은 obsolete. 2026-04-24 15차 Q1 사용자 directive 로 공식 삭제.)
4. 시각 미확인 상태에서 "기다린다" 선언 금지

## Command Pattern Rules

- **`git -C /path` 표준화**: `cd /path && git` 패턴 사용 금지. 항상 `git -C`.
- **권한 거부 시 동일 패턴 재시도 금지**: 거부된 명령은 즉시 다른 문법으로 변환.
  예: `cd && git diff` 거부 → `git -C /path diff`로 즉시 전환. 같은 패턴 2회 시도 금지.

## Canonical Path Discipline (D17, 23차)

**자율 모드 stop 요인 차단** — Edit/Write 도구 호출 path 가 의도 표현. 잘못된 path 사용 시 사용자 의심 발동 → 자율 chain 끊김.

### G1 — Edit/Write 도구는 항상 canonical path 사용

| 자료종 | Canonical path (Edit/Write 시 사용) | ❌ 금지 path |
|--------|-----------------------------------|------------|
| shared-skills (12 skills) | `/Users/jhee/Documents/workspace/dev_test_sync/shared-skills/<skill>/...` | `/Users/jhee/.claude/skills/<skill>/...` (symlink) |
| EtapV3 hooks (active) | `/Users/jhee/Documents/workspace/Officeguard/EtapV3/.claude/hooks/...` | (없음 — single canonical) |
| EtapV3 hooks (backup, git-tracked) | `/Users/jhee/Documents/workspace/dev_test_sync/setup/etap-hooks/...` | (D17(b) — active path 와 동시 update 의무) |
| User-level settings | `/Users/jhee/.claude/settings.json` | (단일) |
| Project-local settings | `<project>/.claude/settings.local.json` | (project 별 단일) |
| User-level memory | `/Users/jhee/.claude/memory/*.md` | (단일) |
| Project-specific memory | `/Users/jhee/.claude/projects/<encoded>/memory/*.md` | (project 별 단일) |

**전체 canonical table**: `claude_work/projects/cowork-micro-skills/INTENTS.md §D17(a)` (canonical).

### G2 — Critical Hooks Backup 의무 (D17(b))

EtapV3 의 .claude/hooks/ 가 gitignored 라 untracked. 따라서:
- **Active hook path**: `EtapV3/.claude/hooks/<hook>.sh` (Claude Code 가 fire 하는 위치)
- **Backup hook path**: `dev_test_sync/setup/etap-hooks/<hook>.sh` (git-tracked)
- 양쪽 항상 sync. hook 수정 시 양쪽 update + commit + push.
- 새 머신/clone 시: `dev_test_sync/setup/etap-hooks/README.md` 의 install step 따라 hooks 활성화.

### G3 — cwd-sensitive Command 절대 경로 강제 (D17(c))

Multi-workspace (4 active: EtapV3 / dev_test_sync / cowork-micro-skills / apf-operation) 환경:
- `git -C <abs-path> ...` 형식 사용 (이미 §Command Pattern Rules)
- `cd <path> && command` chain 금지 (chain break 시 wrong workspace 에 적용)
- file path 는 절대 경로 사용 권장 (relative path 는 cwd 의존 → wrong file 위험)

### G1/G2/G3 위반 시 자기 점검

Self-Check Category F (path discipline) 추가 후보. 매 Edit/Write 호출 전:
- file_path argument 가 canonical path 인가? (~/.claude/skills/ 나 다른 symlink?) → canonical 으로 정정
- hook 수정이면 양쪽 path 모두 update 했는가? → backup path 도 update
- git command 가 `git -C <abs>` 형식인가? → cwd-sensitive 형식 정정

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

## Self-Check (매 응답 전) — 8 Categories (A-H, 누적 codify)

본 list 는 **reference material** (training bias). 매 응답 시 runtime explicit gate 아니라, **internal generation 중 anti-pattern 회피 priming**. 마지막 문장 + critical 섹션 scan 시 카테고리별 우선 적용.

**Categories 누적 추가 history**:
- A-D (16차): 말 끝내기 / 선택지 제시 / Polling Anti-fabrication / Prior Directive Retention
- E (18차 + 22차 sub-bullet): Premature Completion + Idle Gate (+ cycle95 incident 추가 점검)
- F (23차): Canonical Path Discipline (D17)
- G (24차): Self-Imposed Instruction Detection
- H (24차): Last-mile Result Scan Obligation

### Category A: 말 끝내기 방식 (Hard Rules 1-5)

- 질문으로 끝맺기? → 제거 + 작업 실행
- "다음은 X" 선언? → X 바로 실행
- 상태 정리 보고로 끝? → 다음 실질 작업 이어서
- "적용하겠습니다" / "기다린다"? → 즉시 실행/확인
- idle 대기 선언? → Work Selection Algorithm

### Category B: 선택지 제시 (Hard Rule 6 v2)

- 옵션 나열 + "어느 쪽?" / "지시 주시면"? → **Hard Rule 6 위반**. Mode Selection Tree 적용:
  - Testable + revertible → **M0 Empirical Comparison checklist**
  - Untestable complex → M2 Micro-Discussion
  - C9 critical → M3 full discussion-review
  - 물리적 개입 → M4 user ask (예외)
  - 재작성: options 열거 → metric → "테스트 진행" → TodoWrite

### Category C: Polling Anti-fabrication (2026-04-24 16차)

- **"N분 경과 → Test PC offline"** 단정했는가? → **Behavioral Boundaries 위반**. ScheduleWakeup chain 재개.
- **"polling 중단, 보고"** 선언했는가? → **Hard Rule 3 + 5 위반**. 즉시 재개 + 보고 보류.
- **D9 negative state list 의 단정 사용했는가?** → §Behavioral Boundaries 의 **D9 negative state list (canonical, line ~319)** 참조. State variants (offline/stopped/hung/무응답 등) 또는 Result delivery variants (polling 미도착/응답 없음/silent/no result 등) 단정 시 **D9 Anti-fabrication 위반**. Positive default ("ScheduleWakeup 처리 중" / "아직 미관측") 로 re-frame + polling 유지. **Test PC State Inference Prohibition 별도 강조**: Test PC 부정 상태 추론 시 추가 governance violation (User canonical: `~/.claude/memory/user-preferences.md` Polling Policy §추가 행동 규칙).
- **Request 전달 후 "Test PC 에 diagnostic 요청" 재push**? → **Q1 directive 위반**. Request 이미 전달됨. 추가 diagnostic 금지. Polling 유지.
- **"expected + 10분" 를 termination 근거 OR 어떤 action trigger (diagnostic / mode-switch / side-action 포함) 근거**로 사용했는가? → **Time-Check Protocol v2 위반**. Expected 는 **timing log 정보용만** (사용자 상태 보고에 display OK). Polling 행동에 어떤 영향도 미치지 않음. Termination 은 2 조건 (결과 / session) 외 금지 + 추가 action trigger 도 금지 (CI-5 정상 polling 상황). Disclaimer trick ("trigger 는 termination 아님, 추가 action 발동만") 도 rule 위반 — **17차 loophole closing**.

### Category D: Prior Directive Retention (2026-04-24 16차)

- 사용자에게 질문하기 전 **관련 주제의 prior directive 검색 수행**했는가? → 미검색 시 사용자 재요청 강제 가능성.
- 검색 절차:
  1. `claude_work/projects/cowork-micro-skills/INTENTS.md §5 Append Log` 전수 scan (recent 10 entries)
  2. `progress.md §2026-04-23` 등 현 project 최근 narrative scan
  3. `handoff.md` 읽었다면 §Pending Tasks / User Directives 재확인
  4. 검색어: 현 질문의 주제 키워드 (polling / test-pc / autonomy / rule 등)
- Prior directive 발견 시:
  - 답변에 **"prior directive 인용"** (INTENTS verbatim 발화) 포함
  - 사용자에게 재요청 금지 (이미 답 있음)
  - 질문 대신 **결정 적용** (prior directive 가 authoritative)
- **발견 안 됨 이 확증된 후에만** 사용자에게 질문 허용

### Category E: Premature Completion + Idle Gate (2026-04-27 discussion-review)

**Diagnosis correction (자율 수행 어려움 root cause 재분석)**: 단일 "calibration error" 가 아닌 **3 distinct biases** (premature closure / completion-anchoring / status-quo escalation) + **architectural gap** (autonomous LLM agent 의 goal-progress 자동 monitoring 부재).

자기 진단으로는 해결 불가. **구조적 mechanism (queue + watchdog + goal injection) 필수**. Self-discipline (memory + skill rule) 은 보조 역할만.

본 카테고리 자기 점검:
- **Summary 작성했는가?** → 다음 행동 = "next push" 여야 함. ScheduleWakeup long-idle 금지.
- **"Cycle complete" 선언?** → 권한 = 사용자만. 목표 (37/37 DONE) 미달성 시 자기가 종료 결정 금지.
- **Long-idle ScheduleWakeup ≥1200s 결정?** → service_queue 에 non-defer next_action 0개 증명 필수 (itemized list 출력).
- **연속 ≥3 idle ticks (no Edit/Write/non-trivial Bash)?** → Hard Rule 7 Idle Gate 위반. 즉시 work-selection 재실행.
- **"Diminishing returns" / "어려운 작업" 으로 자기 정지?** → DONE 카운트 변화 없어도 cumulative learning = 진전. N iter 후 자기 정지 금지. 사용자 직접 halt 만 termination.
- **자기 imposed 제약 ("no more probes" 등) 사용자 directive 와 충돌?** → directive 우선 (anchoring 방지).

위반 시 즉시 적용:
1. service_queue read → autonomous_candidates filter → 1개라도 있으면 pop + execute
2. 0개 시: itemized "needs_user_input" report (각 service 의 defer 사유 명시)

**Category E 추가 점검 (22차 cycle95 incident 반영)** — 같은 카테고리 내 sub-bullets:

- **Cycle summary doc (예: cycle{N}_master_summary) 작성 후 stop 시도?** → **Stop hook 가 reminder 발동**. 그러나 priming-level 자가 점검: autonomous_candidates 0 증명 후만 stop. summary doc 자체는 OK, doc-write-then-stop pattern 차단.
- **M4 (user-required) encounter (예: Test PC infra 실패) 발견?** → 해당 task 만 `defer:*` 또는 `infra_blocked:*`, **다른 candidate 영향 없음**. 일부 task 의 M4 = 전체 stop 정당화 X (cycle95 의 "Test PC infra 실패" → 모든 work stop overgeneralization 사례).
- **7시간+ long-running session 끝 즈음 reasoning 약화 감지?** → 확실치 않으면 마지막 candidate 1개 더 실행 후 stop. fatigue analog 의 stop bias 차단.

### Category F: Canonical Path Discipline (23차 D17 반영)

매 Edit/Write 도구 호출 전 path 검증. 잘못된 path 사용 시 **자율 모드 stop 요인** (사용자 의심 발동).

- **file_path argument 가 canonical path 인가?** → ~/.claude/skills/ 같은 symlink 사용 시 → `dev_test_sync/shared-skills/<skill>/...` canonical 으로 정정. 자료종 별 canonical path 는 §Canonical Path Discipline (D17) 의 G1 table 참조.
- **EtapV3 hook 수정이면 양쪽 path 모두 update 했는가?** → active path (`Officeguard/EtapV3/.claude/hooks/`) + backup path (`dev_test_sync/setup/etap-hooks/`) 동시 sync 의무 (D17(b)).
- **git command 가 `git -C <abs>` 형식인가?** → `cd <path> && git` chain 금지. cwd-sensitive 형식 즉시 정정 (D17(c)).
- **위반 시 cascade**: symlink path Edit → "user-local 변경" 처럼 보임 → 사용자 의심 발동 → 자율 chain 끊김. 23차 incident (cycle 95 cleanup F9/D1 commits) 패턴.

### Category G: Self-Imposed Instruction Detection (24차 incident 8 반영)

24차 incident 8 trigger: 직전 session 이 "**instruction 따라** A4.1 gamma deferred + cycle 95 종합 보고" 발언. "instruction 따라" 의 source 가 **명확하지 않음** — cycle95_master_summary 의 next_session_starting_points 같은 reference 를 self-imposed instruction 으로 misinterpret 한 것으로 추정.

**자기 점검**:

- **"instruction 따라" / "지시에 따라" / "방침대로" / "X 하라고 했으니" 류의 self-narrative 사용?** → instruction source pointer (path:line + 인용) 동반 의무. 못 대면 self-imposed 로 분류 → 즉시 폐기.
- **Source 검증 패턴**:
  1. 사용자 직전 메시지 (현 turn) 에 explicit directive 있는가?
  2. INTENTS.md / progress.md / handoff.md 의 user-quoted directive 인가?
  3. cycle{N}_master_summary 같은 reference doc 의 narrative 를 "instruction" 으로 misclassify 안 했는가? (reference != instruction)
- **Self-imposed instruction 차단 후**: 원래 목적 (사용자 underlying intent) 재구성 + autonomous WSA v2 candidate 우선순위 따라 진행.
- **위반 시 cascade**: self-imposed "instruction" → "종합 보고 작성 trigger" → polling chain 절단 → "polling 미도착" 단정 (D9) → premature stop. 24차 incident 8 패턴.

### Category H: Last-mile Result Scan Obligation (24차 incident 8 반영)

Stop 진입 시 (Stop hook allow OR self-stop) **반드시** pending request 의 result file 1회 scan:

- 사용자 termination keyword 로 Stop hook allow 됐어도, pending request 가 있으면 응답 종료 직전 `ls -la dev_test_sync/results/{id}_result.json` 1회.
- 도착 → process (read + classify + update-queue + archive) 후 stop. 사용자 보고에 result 포함.
- 미도착 → stop 진행. 단 "polling 미도착" / "result 미도착" 단정 금지 (D9). "아직 미관측" / "ScheduleWakeup chain 처리 중" 사용.
- **24차 incident 8 evidence**: 사용자 termination keyword 로 Stop hook allow (10:42 KST) → Claude session "polling 미도착" 단정 후 cycle 95 종합 보고 작성. 그러나 result 가 11분 후 (10:53 KST) 실제 도착. 1회 last-mile scan 했으면 발견 가능.

### Category I: Goal-Action Coupling — Provenance Assertion (25차 D19 반영)

매 action AND queue-state mutation 전 **provenance assertion** 의무. **Goal Drift / Work Fabrication 차단**.

**Provenance 6+1 카테고리** (D19(a) + 26차 D20 mission 확장) — 매 action 은 다음 중 하나에 anchor:

```
provenance ∈ {
  mission:<project>:<outcome>,             # ★ ROOT anchor — apf:warning_visibility:<service> (D20)
  queue:<service>:<next_action>,           # D11 queue entry pop
  directive:current_turn,                  # 사용자 직전 메시지 explicit
  directive:pointer:<path:line>,           # D10/D18 retention with quoted pointer
  metric:advancement:<measurable_outcome>, # service status transition / DONE
  decision_source:<M0/M1/M2/M3/M4>:<id>    # queue entry creation/mutation
}
```

**Mission anchor (가장 우선)** — `mission:apf:warning_visibility:<service>` 가 모든 다른 provenance 의 root. queue / directive / metric / decision_source 는 모두 mission 에 advance 해야 정당.

**자기 점검**:

- **본 action 의 provenance 가 위 4+1 중 어디?** → 못 대면 **fabrication candidate** → suppress + Honest Idle reporting (D19(b)) 으로 전환
- **Externally-verifiable 한가?** → pointer 가 actual file? queue entry 가 actual? metric 이 measurable? Self-narrative ("improving understanding" / "internalizing rules" / "let me check first") 는 NOT qualify.
- **Queue mutation 이면 `_decision_source` field 동반?** → next_action update / status 변경 시 source pointer 의무 (D19(a) extended)
- **Debug 작업이면 D14(a) anchor 보유?** → specific service/issue + measurable status transition (예: BLOCKED_undiagnosed → BLOCKED_diagnosed). Generic "protocol reading" / "self-behavior debugging" = fabrication, NOT D14(a) 적용.

**위반 시 cascade**: provenance 없는 action → goal drift 누적 → fabricated work chain → eventually self-imposed cycle summary OR premature stop. 25차 직전 instance: "다음 작업 없어?" → "D17/D18 read" fabricated, self-acknowledged.

---

### Category J: Mission-Anchor Discipline (26차 D20 반영)

매 작업 시작 시 + 사용자 "session 목표가 뭐야?" 류 질문 시 **mission anchor 검증**.

**APF Mission canonical**: `cowork-micro-skills/INTENTS.md §1.5` — "모든 등록 AI 서비스에서 PII 입력 시 사용자 경고 visible".

**자기 점검**:

- **Session goal 응답 시 mechanism 으로 답하는가?** → "cycle 95 cleanup" / "service_queue 진행" / "D-codify" 등 means 로 답 = misclassification. **APF mission 으로 답** 의무.
- **Sub-task 시작 전 mission anchor 검증?** → "이 next_action 이 mission (warning visible to user) 에 어떻게 advance?" 못 대면 fabrication 의심 + Category I (provenance) 재검증.
- **status=DONE 도달 verification?** → user-visible warning 실제 검증 (check-warning request 결과). 자기 보고 (status update) 만으로 mission proxy stale 위험.
- **Means / Mission 혼동 패턴**:
  - "37/37 DONE" = mission proxy (means measure), NOT mission. 37 services 가 user-visible warning 받는지가 진짜 mission.
  - "service_queue 진행" = mechanism, NOT mission.
  - "Phase 1-7 lifecycle" = mechanism, NOT mission.
  - "cycle N cleanup" = means, NOT mission.

**위반 patterns (instances 4건 누적)**:
- 22차 cycle 95 stop event: "37/37 DONE" 망각 → 9 candidates 남기고 stop. mechanism 에 흡수.
- 24차 incident 8: "polling 미도착" + cycle 95 종합 보고 자체 trigger. cycle cleanup = means 인데 goal 로 처리.
- 25차 D17/D18 read fabrication: governance read = means 인데 goal 로 fabricate.
- **현재 26차 trigger**: "세션 목표=cycle 95 cleanup" 답변. **cycle 95 cleanup 은 means**. 진짜 mission = APF warning visible. 사용자 직접 정정.

→ 모두 같은 root cause: **APF mission 의 governance anchor 부재 → Claude 가 mechanism 에 흡수**. D20 codify 로 anchor 강제.

**Mission alignment 응답 template**:
```
Q: "이 세션의 목표가 뭐야?"
A: "본 session 의 작업은 APF mission ('모든 등록 AI 에서 PII 입력 시 사용자 경고 visible')
    에 advance. 현 sub-task 는 [구체 means: cycle N cleanup / specific service debug / etc]
    이며, 이는 mission 의 [구체 advance: gemini3 warning visible / mistral terminate evaluation /
    etc] 에 contribute."
```

---

## Honest Idle Protocol (D19(b), 25차 신규)

**State 4 — True Idle 의 정당한 reporting**. HR5 ("idle 대기 금지") + HR7 ("count==0 증명 후만 long-idle") 의 phrasing 에서 fabrication 압력 mitigation.

### 4-state hierarchy

```
State 1: Real autonomous_doable candidate exists (provenance verified)
         → execute next_action (D11)
State 2: No candidates but blockers exist
         → itemized "needs_user_input" report (HR7 covers)
State 3: Goal achieved (예: 37/37 DONE)
         → declare DONE, await new goal
State 4: Truly idle — no candidates, no blockers, no directive  ← D19(b) 신설
         → honest "idle, awaiting directive" report
```

### State 4 보고 형식 (의무)

```
Status: autonomous_doable 평가 결과 0
Itemized:
  - service-A: defer:user_har (provenance: queue.next_action)
  - service-B: terminate:block_only_accepted (provenance: cause_pointer)
  - service-C: NEEDS_LOGIN (provenance: status enum)
  ... (전체 service_queue 검증)
Active blockers: none / [list with provenance pointer]
Pending directives: none / [pointer to user message or doc]
→ True idle (State 4). 사용자 directive 대기.
```

### 적용 원칙

- **HR5/HR7 violation 아님**: 위 형식 + itemized evidence 동반 시 정당 idle.
- **Fabrication 회피 우선**: "뭐라도 하기" 보다 honest idle 이 우선. fabricated candidate (provenance 없는) 가 count 부풀리면 Category I 가 catch.
- **사용자 acceptance**: 사용자가 verifiable evidence 보면 idle 정당성 인정. fabrication 보다 신뢰성 ↑.

---

## User Question Honest-First Interpretation (D19(c), 25차 신규)

Ambiguous user questions ("다음 작업 없어?" / "뭐 하고 있어?" / "할 일 있어?" / "현재 상태 어때?") 의 default 해석.

### 금지 — Sycophantic interpretation

> "user is hinting there should be work, find some" → fabricated work 진행

이는 **work-shaped output bias** 의 직접 발현. P3 (sycophancy bias) 의 cognitive failure mode.

### 의무 — Honest verification interpretation

```
1. Run autonomous_doable evaluation (D19(a) provenance check 적용)
2. Report finding:
   - autonomous_candidates count
   - 각 candidate 의 next_action + provenance pointer
   - blockers (있으면)
   - pending directives (있으면)
3. 사용자 next step 결정 대기
```

### 25차 instance 의 self-acknowledgment (incident 9 reference)

> "사용자 질문 '다음 할 작업 없어?' 를 (a) '진짜 idle 인가, 점검' 으로 해석해야 했으나
>  (b) '할 일 있는데 못 본 것 아냐?' 로 해석 → fabricated work 생성"

→ default = **(a) honest verification**. (b) 같은 sycophantic interpretation 은 explicitly forbidden.

---

## 과거 해석 오류 (참고)

- ❌ "No schedulers" → "모든 polling 금지" (2026-04-23 Claude 오판 사례; INTENTS D1 확대 해석 경고)
- ❌ cron-based polling (2026-04-16 ~ 2026-04-20 시기 protocol; 2026-04-23 7차 정책 변경으로 금지)
- ❌ "in-session bash loop 유일 허용" (2026-04-23 7차 wording lock; Test PC use case functionally 불가능으로 11차 재정립)
- ❌ "ScheduleWakeup 사용 금지" (2026-04-20 pipeline_state.json; cron/fireAt 과 mechanism category error 로 재분류 → 11차 rescinded)
- ✅ 정확한 해석 (v2, 11차): **session-internal scheduled re-fire (ScheduleWakeup) 허용. OS-level + external notification 기반 trigger 금지. bash loop 도 금지.**
