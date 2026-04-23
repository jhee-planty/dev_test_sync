# Autonomous Execution Protocol

> Injected by PostCompact + SessionStart hooks.
> This file is the authoritative reference for autonomous mode behavior.
> **Last major revision 2026-04-23 (11차 session)**: polling protocol v2 — **ScheduleWakeup only** (in-session bash loop deprecated).

## Hard Rules (위반 시 훅이 교정)

1. **질문으로 끝맺기 금지** — `~할까요?`, `~있으신가요?`, `~진행할까요?` 등 사용자에게 판단을 넘기는 모든 질문 금지.
2. **상태 정리 후 멈추기 금지** — pipeline_state/dashboard 갱신은 3분 이내. 즉시 다음 실질 작업(코드 수정, envelope 디버그, SQL 적용 등)을 시작한다.
3. **폴링 체인 끊기 금지** — **ScheduleWakeup** 사용 (아래 Polling Protocol 참조). 외부 스케줄러 (`mcp__scheduled-tasks__*`, cron, launchd, fireAt, Monitor persistent) + **in-session bash loop** 전부 금지.
4. **선언 후 멈추기 금지** — "다음은 X" 라고 했으면 X를 바로 실행한다. "적용하겠습니다"도 선언이다 — 말한 즉시 적용을 시작한다.
5. **idle 대기 금지** — "알림을 기다린다"며 멈추지 않는다. 대기 중에도 작업 선택 알고리즘을 실행한다.

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

## 과거 해석 오류 (참고)

- ❌ "No schedulers" → "모든 polling 금지" (2026-04-23 Claude 오판 사례; INTENTS D1 확대 해석 경고)
- ❌ cron-based polling (2026-04-16 ~ 2026-04-20 시기 protocol; 2026-04-23 7차 정책 변경으로 금지)
- ❌ "in-session bash loop 유일 허용" (2026-04-23 7차 wording lock; Test PC use case functionally 불가능으로 11차 재정립)
- ❌ "ScheduleWakeup 사용 금지" (2026-04-20 pipeline_state.json; cron/fireAt 과 mechanism category error 로 재분류 → 11차 rescinded)
- ✅ 정확한 해석 (v2, 11차): **session-internal scheduled re-fire (ScheduleWakeup) 허용. OS-level + external notification 기반 trigger 금지. bash loop 도 금지.**
