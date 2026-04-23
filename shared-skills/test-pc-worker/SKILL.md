---
name: test-pc-worker
type: A
description: Test PC (Windows) 전용 worker. dev 가 push 한 requests/ 를 git pull 로 수신 → PowerShell + windows-mcp 로 Chrome 자동화 실행 → results/ 에 결과 push. Use when on test PC and user says "새 요청 확인", "요청 처리", "check-warning 실행", "check-block 실행", "dev 에서 요청 왔어?", "result push". 결정론 runtime 은 PowerShell script. Claude 는 DOM/Console 판독 + scenario decision 만 담당. 응답 대기 중 자동 에스컬레이션 없음 (cowork-remote 와 pair).
allowed-tools: mcp__windows-mcp__PowerShell, mcp__windows-mcp__FileSystem, mcp__windows-mcp__Click, mcp__windows-mcp__Type, mcp__windows-mcp__Screenshot, Bash, Read, Write
---

# test-pc-worker

Test PC (Windows) 전용 micro-control skill. Pair of `cowork-remote` (dev 쪽).

## 기본 인프라

- **Git repo**: `C:\workspace\dev_test_sync` (default)
- **Runtime 스크립트 위치**: `$BASE\skills\test-pc-worker\runtime\*.ps1` 또는 프로젝트 배포 시 동일 경로
- **쓰기 규칙**: `results/` 에만 write. `requests/`, `queue.json` 수정 금지.
- **State**: `local_archive/state.json` — `{last_processed_id, last_delivered_id, updated_at, schema_version}`

## Runtime 호출 규약

모든 결정론 작업은 PowerShell script via `windows-mcp` PowerShell tool (또는 Bash):

```
mcp__windows-mcp__PowerShell
  command: powershell -ExecutionPolicy Bypass -File $SKILL_DIR\runtime\{script}.ps1 {args}
  timeout_ms: 120000
```

File I/O 는 `mcp__windows-mcp__FileSystem` (read / write / list / create). Chrome 자동화용 GUI 상호작용은 `mcp__windows-mcp__Click` / `Type` / `Screenshot`.

**Legacy note**: 2026-04-23 11차 이전에는 `mcp__desktop-commander__*` 였음. Test PC 에 desktop-commander MCP 가 없는 환경에서는 windows-mcp 로 대체 (allowed-tools 참조).

---

## 3 기본 작업 흐름

### A. Scan new requests

**Trigger**: "새 요청 확인해줘", "폴링 한번".

**흐름**:
1. Runtime: `scan-requests.ps1` — git pull + requests/*.json 스캔 → state.last_processed_id 이후 IDs stdout
2. 결과 없음 → 짧게 보고 ("대기 중") 후 종료
3. 각 ID 마다 B 루프

### B. Execute command

**Per request flow**:
1. `read_file` 로 `requests/{id}_{command}.json` 읽음
2. `command` 분기:
   - `check-warning` / `check-block` → Chrome 실행 + Claude 가 DOM 판독 (browser-rules 참조)
   - `check-cert` → `test-ssl-cert.ps1` (결정론)
   - `capture-screenshot` → `chrome-capture.ps1` (결정론)
   - `report-status` → `collect-env.ps1` (결정론)
3. Claude 는 다음 **decision point** 에서만 판단:
   - 차단/경고 visible 여부 (스크린샷 + DOM + Console errors 종합)
   - overall_status enum 결정 : `SUCCESS | FAIL | PARTIAL | BLOCKED | TIMEOUT`
   - failure_category (5종) — INFRASTRUCTURE / PROTOCOL_MISMATCH / NOT_RENDERED / SERVICE_CHANGED / AUTH_REQUIRED
4. Runtime: `write-result.ps1 -reqId {id} -resultJson {literal_json}` → `results/{id}_result.json` + state.last_processed_id 갱신

### C. Push results

1. Runtime: `push-result.ps1` — git add/commit/push (3-retry)
2. state.last_delivered_id 갱신
3. 사용자 간단 보고 : 처리된 ID + verdict

---

## 필수 result schema

```json
{
  "id": "{id}",
  "status": "done" | "error",
  "result": {
    "overall_status": "SUCCESS|FAIL|PARTIAL|BLOCKED|TIMEOUT",
    "status_detail": "자유 텍스트 한 줄",
    "service_name": "gemini",
    "started_at": "ISO 8601",
    "completed_at": "ISO 8601",
    "duration_seconds": 123,
    "warning_visible": true,
    "screenshot": "files/{id}/step1.png",
    "console_errors": []
  },
  "notes": "..."
}
```

`write-result.ps1` 가 6 필수 필드 (`overall_status, status_detail, service_name, started_at, completed_at, duration_seconds`) 누락 시 에러 반환.

---

## 학습 (Lessons)

운영 중 발견된 use-case-specific lesson (Chrome quirk, Windows 특이사항, DOM selector 변경 등) 은 `references/lessons.md` 에 **append-only** 로 기록. 기존 entry 수정 금지. 새 lesson 은 `## Lesson YYYY-MM-DD-NN — {제목}` template (lessons.md 첫머리 참조) 으로 추가.

Cross-skill pattern (본 skill 외에도 반복되는 실수) 은 `research-gathering` 으로 scan 해 `promotion_proposal.md` 로 승격 검토 가능.

---

## 폴링 방식 (2026-04-23 v2 — 11차 session)

본 skill 이 호출되는 두 가지 패턴:

**(a) 수동 1회 호출**: 사용자 "새 요청 확인해줘" → scan-requests 1회 실행 → 결과 없으면 종료.

**(b) ScheduleWakeup 자율 폴링 (Option 3)**: 사용자가 세션 시작 시 1회 prompt 제공 → Claude 가 매 tick 마다 scan-requests 실행 + 신규 request 처리 + ScheduleWakeup 으로 다음 tick 예약. 세션 종료 = pending wakeup 자동 취소 (polling 종료).

```
# 예: tick cadence 60s (cache-warm)
ScheduleWakeup(
    delaySeconds=60,
    prompt="git pull. scan-requests.ps1 실행. 신규 ID 있으면 each ID 마다 B. Execute command 흐름 + C. Push results. 그 후 ScheduleWakeup 재예약 (동일 params). 신규 없으면 바로 ScheduleWakeup 재예약.",
    reason="test-pc-worker autonomous polling for new requests"
)
```

→ **Canonical**: `~/.claude/memory/user-preferences.md` Polling Policy (v2: ScheduleWakeup only). cron / Scheduled Task / fireAt / Monitor persistent / in-session bash loop 전부 금지.

## 제외된 기능 (의도적)

- ❌ Scheduled Task / fireAt / cron / launchd / Monitor persistent — session 외부 persistent trigger
- ❌ **In-session bash loop** (`while true; sleep N; done` in Claude bash turn) — 11차 제외. 이유: per-iteration Claude reasoning (Chrome DOM 판독 등) 불가능
- ❌ Adaptive polling 3-stage (단일 ScheduleWakeup delay 로 통일)
- ❌ Heartbeat.json (tick 자체가 liveness indicator)
- ❌ GitHub MCP (git CLI only, 단일 transport)

---

## Related micro-skills

- `cowork-remote` (dev 쪽 pair) — request/result 교환 프로토콜.
- `genai-apf-pipeline` — 최상위 orchestrator (dev 쪽).
- `research-gathering` — test-pc 자동화 중 "이전에 왜 이 대기 시간 / 재시도 수치로 정해졌나?" 같은 이력 조사 시 호출.
