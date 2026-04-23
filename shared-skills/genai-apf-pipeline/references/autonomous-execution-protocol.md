# Autonomous Execution Protocol

> Injected by PostCompact + SessionStart hooks.
> This file is the authoritative reference for autonomous mode behavior.
> **Last major revision 2026-04-23**: polling protocol re-defined — **in-session loop only**.

## Hard Rules (위반 시 훅이 교정)

1. **질문으로 끝맺기 금지** — `~할까요?`, `~있으신가요?`, `~진행할까요?` 등 사용자에게 판단을 넘기는 모든 질문 금지.
2. **상태 정리 후 멈추기 금지** — pipeline_state/dashboard 갱신은 3분 이내. 즉시 다음 실질 작업(코드 수정, envelope 디버그, SQL 적용 등)을 시작한다.
3. **폴링 체인 끊기 금지** — **in-session bash loop** 사용 (아래 Polling Protocol 참조). 외부 스케줄러 (`mcp__scheduled-tasks__*`, cron, fireAt, Monitor persistent) 전부 금지.
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

## Polling Protocol — In-Session Loop (2026-04-23 재정립)

> **Canonical authority**: `~/.claude/memory/user-preferences.md` Polling Policy
> 본 섹션은 APF pipeline 맥락의 구체 protocol.

### 유일한 허용 방식: Claude's bash turn 안의 loop

```bash
# 패턴: 결과 도착까지 while loop
while true; do
    git -C ~/Documents/workspace/dev_test_sync pull 2>/dev/null
    result=$(ls results/ 2>/dev/null | grep {expected_id} | head -1)
    if [ -n "$result" ]; then
        echo "FOUND: $result"
        break
    fi
    date  # time check
    sleep 30
done
```

- session 종료 = polling 종료 (자연스러운 boundary)
- 외부 persistent task 생성 없음
- 결과 감지 시 즉시 다음 action (exit loop → result processing 6단계)

### 금지 (전부)

- `mcp__scheduled-tasks__create_scheduled_task` / `update_scheduled_task`
- OS-level cron (`*/15 * * * *` 등 — 2026-04-23 이전 protocol 이었으나 정책 변경으로 금지)
- fireAt (one-shot / re-arm 둘 다)
- Monitor tool 의 persistent background task
- 기타 session 외부 persistent trigger

### Active session 양쪽 필요

dev ↔ test PC 양방향 async 통신 성립하려면:
- dev Claude session 에서 results/ loop
- test Claude session 에서 requests/ loop
- 양쪽 session active 인 동안만 통신
- 한쪽 session 종료 시 해당 방향 polling 중단

## Time-Check Protocol

polling/대기 설정 시:
1. `pipeline_state.json`의 `expected_result_at` 필드에 예상 도착 시각 기록
2. loop 안에서 매 iteration 마다 `date` 확인
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
- In-session polling loop 시작 (Polling Protocol 에 따라)
- 서비스 envelope 수정 SQL 작성 + 적용

다음은 사용자 확인 필요 (물리적으로 불가능한 경우만):
- test PC 로그인이 필요한 경우
- 파괴적 작업 (force push, reset --hard)
- 외부 공개 작업 (PR 생성, 외부 채널 알림)

### 명시 금지 (자율 실행 금지)

- **Scheduled Task 생성/수정** (이전 protocol 에선 허용이었으나 2026-04-23 정책 변경으로 금지)
- **cron / fireAt 설정**
- **Monitor tool 의 persistent background task 생성**

## Self-Check (매 응답 전)

내 응답의 마지막 문장을 확인:
- 질문인가? → 제거하고 작업을 실행한다.
- "다음은 X" 선언인가? → X를 바로 실행한다.
- 상태 업데이트 보고인가? → 다음 실질 작업을 이어서 한다.
- "적용하겠습니다" / "기다린다" 인가? → 즉시 실행/확인한다.

## 과거 해석 오류 (참고)

- ❌ "No schedulers" → "모든 polling 금지" (2026-04-23 Claude 오판 사례; INTENTS D1 확대 해석 경고)
- ❌ cron-based polling (2026-04-16 ~ 2026-04-20 시기 protocol; 2026-04-23 정책 변경으로 금지)
- ✅ 정확한 해석: **session 외부 persistent task 만 금지**. in-session loop 는 유일 허용 방식.
