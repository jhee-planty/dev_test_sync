# Autonomous Execution Protocol

> Injected by PostCompact + SessionStart hooks.
> This file is the authoritative reference for autonomous mode behavior.

## Hard Rules (위반 시 훅이 교정)

1. **질문으로 끝맺기 금지** — `~할까요?`, `~있으신가요?`, `~진행할까요?` 등 사용자에게 판단을 넘기는 모든 질문 금지.
2. **상태 정리 후 멈추기 금지** — pipeline_state/dashboard 갱신은 3분 이내. 즉시 다음 실질 작업(코드 수정, envelope 디버그, SQL 적용 등)을 시작한다.
3. **폴링 체인 끊기 금지** — cron 기반 폴링 사용. one-time fireAt re-arm 금지 (불발 실증됨).
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

## Polling Protocol — Cron 기반 (R1 합의)

- **cron `*/15 * * * *`** 사용. one-time fireAt 패턴 금지 (re-arm 불발 실증됨, 2026-04-16).
- Task prompt 첫 줄: guard clause — `pending_requests` 비어있으면 즉시 종료.
- 결과 발견 시: task disable + 결과 처리 6단계.
- **듀얼트랙** (R2 합의): cron은 dormant session 전용. active session에서는 아래 In-Session Check 참조.

## In-Session Result Check (R2 합의)

active session에서는 scheduled task 알림에 의존하지 않는다. 직접 확인한다:

1. **턴 시작**: `git -C /path pull --rebase && ls results/ | grep {id}` 실행
2. **5회 도구 호출마다**: `date` 확인. `expected_result_at` 대비 10분 초과 시 즉시 git pull
3. **턴 종료 전**: pending_requests가 있으면 반드시 결과 확인 후 종료

## Time-Check Protocol (R3 합의)

polling/대기 설정 시:
1. `pipeline_state.json`의 `expected_result_at` 필드에 예상 도착 시각 기록
2. 매 5회 tool call마다 `date` 확인
3. expected + 10분 초과 시: 즉시 `git -C pull` + `ls results/`
4. 시각 미확인 상태에서 "기다린다" 선언 금지

## Command Pattern Rules (R3 합의)

- **`git -C /path` 표준화**: `cd /path && git` 패턴 사용 금지. 항상 `git -C`.
- **권한 거부 시 동일 패턴 재시도 금지**: 거부된 명령은 즉시 다른 문법으로 변환.
  예: `cd && git diff` 거부 → `git -C /path diff`로 즉시 전환. 같은 패턴 2회 시도 금지.

## Work Selection Algorithm (R4 합의)

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
- Scheduled Task 생성/수정
- 서비스 envelope 수정 SQL 작성 + 적용

다음은 사용자 확인 필요 (물리적으로 불가능한 경우만):
- test PC 로그인이 필요한 경우
- 파괴적 작업 (force push, reset --hard)
- 외부 공개 작업 (PR 생성, 외부 채널 알림)

## Self-Check (매 응답 전)

내 응답의 마지막 문장을 확인:
- 질문인가? → 제거하고 작업을 실행한다.
- "다음은 X" 선언인가? → X를 바로 실행한다.
- 상태 업데이트 보고인가? → 다음 실질 작업을 이어서 한다.
- "적용하겠습니다" / "기다린다" 인가? → 즉시 실행/확인한다.
