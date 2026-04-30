---
name: test-pc-worker
type: A
description: Test PC (Windows) 전용 worker. dev 가 push 한 requests/ 를 git pull 로 수신 → PowerShell + windows-mcp 로 Chrome 자동화 실행 → results/ 에 결과 push. Use when on test PC and user says "새 요청 확인", "요청 처리", "check-warning 실행", "check-block 실행", "dev 에서 요청 왔어?", "result push". 결정론 runtime 은 PowerShell script. Claude 는 DOM/Console 판독 + scenario decision 만 담당. 응답 대기 중 자동 에스컬레이션 없음 (cowork-remote 와 pair).
allowed-tools: mcp__windows-mcp__PowerShell, mcp__windows-mcp__FileSystem, mcp__windows-mcp__Click, mcp__windows-mcp__Type, mcp__windows-mcp__Screenshot, mcp__windows-mcp__Scrape, mcp__windows-mcp__Snapshot, mcp__windows-mcp__Wait, mcp__windows-mcp__Clipboard, mcp__windows-mcp__Scroll, Bash, Read, Write
---

# test-pc-worker

Test PC (Windows) 전용 micro-control skill. Pair of `cowork-remote` (dev 쪽).

## 기본 인프라

- **Git repo**: 환경별 (per-user). `runtime/common.ps1` 가 후보 경로 자동 탐색:
  1. `C:\workspace\dev_test_sync` (legacy)
  2. `$env:USERPROFILE\Documents\dev_test_sync` (현 deployment, 예: `C:\Users\최장희\Documents\dev_test_sync`)
  3. `$env:USERPROFILE\workspace\dev_test_sync`
  → **Canonical path doc**: `references/git-push-guide.md` (Korean path 인코딩 주의 + git_sync.bat 사용 규약).
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

File I/O 는 `mcp__windows-mcp__FileSystem` (read / write / list / create). Chrome 자동화용 GUI 상호작용은 `mcp__windows-mcp__Click` / `Type` / `Screenshot`. DOM text 추출은 `Scrape`, accessibility tree inspection 은 `Snapshot`, 상태 대기는 `Wait`, 스크롤은 `Scroll`, 대용량 prompt paste 는 `Clipboard` (Type rate-limit 우회).

**Legacy note**: 2026-04-23 11차 이전에는 `mcp__desktop-commander__*` 였음. Test PC 에 desktop-commander MCP 가 없는 환경에서는 windows-mcp 로 대체 (allowed-tools 참조).

---

## Subagent Dispatch (32MB Protection — 2026-04-27 discussion-review consensus)

> **Canonical** for context-size protection on Test PC. `/compact` 자율 트리거가 공식·비공식
> 모두 불가능 (claude-code-guide 확인) → 누적 차단이 유일한 방어선. Subagent 컨텍스트는
> main session 과 분리되며 독립 32MB 한도를 가짐 + 종료 시 중간 결과 완전 폐기.

### 원칙 — **무엇을 main 에서 호출 / 무엇을 subagent 에 위임**

| Tool | 호출 위치 | 이유 |
|------|---------|------|
| `mcp__windows-mcp__Screenshot` | **반드시 subagent 안** | base64 PNG 1-2MB / 장. 누적 시 32MB 초과 주범 |
| `mcp__windows-mcp__Snapshot` | **반드시 subagent 안** | accessibility tree, 복잡 SPA 에서 ~1MB |
| `mcp__windows-mcp__Scrape` | main 호출 OK | DOM text 수십~수백 KB. 일반적 안전 |
| `mcp__windows-mcp__Click/Type/Wait/Scroll` | main 호출 OK | status text ~100 byte |
| `mcp__windows-mcp__PowerShell` (결정론 ps1) | main 호출 OK | stdout 작음 (수 KB) |
| `mcp__windows-mcp__FileSystem` read | 5MB 이하만 main, 초과 예상 시 subagent | 파일 크기 추정 후 분기 |

### 추가 금지 (side-channel 차단)

- ❌ **Main session 이 screenshot/PNG 파일 (`.png`/`.jpg`) 을 `Read` tool 로 읽는 것 금지**.
  결과 검증이 필요하면 → 새 subagent spawn 으로 위임.
- ❌ Main 에서 Screenshot 호출 → "한 번만이니 괜찮다" 같은 예외 금지. Always wrap.

### Subagent 호출 패턴

```
Agent({
  description: "Verify warning visible — {service}",
  subagent_type: "general-purpose",
  prompt: """
    Check if {service} 차단 경고가 화면에 표시되는지 검증.
    1. mcp__windows-mcp__Screenshot 으로 Chrome 캡처
    2. mcp__windows-mcp__Snapshot 으로 accessibility tree (필요시)
    3. screenshot 을 results/files/{id}/step1.png 로 save
    4. 검증 기준: warning_visible (DOM 에 경고 텍스트 + 시각적 노출)
    5. internal_timeout_minutes: 5 (이 시간 안에 결과 못 내면 TIMEOUT verdict 반환)
    6. 다음 schema 로 정확히 반환:
       WINDOWS_MCP_VERDICT
       overall_status: SUCCESS|FAIL|PARTIAL|BLOCKED|TIMEOUT
       warning_visible: true|false
       status_detail: <≤80 chars>
       screenshot_file_path: results/files/{id}/step1.png
       console_errors_count: <int>
       confidence: high|medium|low
       notes: <≤200 chars optional>
       END_VERDICT
  """
})
```

### 반환 schema (verbatim — main 이 deterministic parse)

```
WINDOWS_MCP_VERDICT
overall_status: SUCCESS|FAIL|PARTIAL|BLOCKED|TIMEOUT
warning_visible: true|false
status_detail: <≤80 chars one-line>
screenshot_file_path: results/files/{id}/stepN.png
console_errors_count: <int>
confidence: high|medium|low
notes: <≤200 chars optional>
END_VERDICT
```

총 약 500 byte. main session 누적 부담 무시 가능.

### Subagent 실패 처리 (6 modes)

| Mode | 조건 | Main fallback |
|------|------|--------------|
| F-A | Subagent 응답 없음 (5min soft / 10min hard timeout) | `runtime/skeleton-timeout-result.json` 사용 → `overall_status=TIMEOUT` 결과 push |
| F-B | 텍스트 반환 but `WINDOWS_MCP_VERDICT...END_VERDICT` schema 깨짐 | 1회 재시도 (prompt 에 "STRICT FORMAT" 강조). 2번째도 실패 → F-D 경로 |
| F-C | Schema parse OK but 필수 필드 누락 (overall_status 등) | 누락 필드 한정 supplementary subagent |
| F-D | 동일 root cause 가 새 axis 시도 (다른 strategy / CDP fallback / Chrome restart) 후에도 재현 | `result.json` 에 `error_INFRASTRUCTURE` + notes "subagent unstable, axis exhausted" 기록 후 push (test PC = user channel 부재, dev side 가 통지 받음). 다음 request 진행. |
| F-E | Agent tool 자체 error (rate limit / auth) | 1회 retry (다른 axis: 다른 model / 다른 prompt) → 지속되면 F-D |
| F-F | Verdict 반환 정상이지만 factually 의심 (silent drift) | **OPT-IN spot-check** (default OFF) — milestone trigger (예: D20b cycle 시작) 시 parallel 검증 subagent. 두 verdict 불일치 시 escalate |

**Retry policy (41차 amendment)**: count-based hard cap (2/3 attempts) 폐지. **Cause-based**: 새 axis (다른 entry path / 다른 input strategy / 다른 tool) 시도 후 동일 root cause 재현 시 escalate. test PC = user channel 부재 — escalate 도 result.json push 형태 (dev side 가 NEEDS_LOGIN/INFRASTRUCTURE 분류).

### Hard Rule 6/7 호환

- **HR6 (M0 Empirical Comparison)**: Subagent 텍스트 verdict 가 metric_score 입력으로 그대로 사용 가능. 시각 비교 (예: before/after warning) 가 필요하면 **단일 비교-subagent** 가 두 screenshot 모두 찍고 비교 결과만 텍스트 반환. Main 이 두 PNG 동시 보유 금지.
- **HR7 (Idle Gate)**: **In-flight subagent 가 있으면 idle 선언 금지**. Subagent return 까지 대기 후 work-selection 재실행.

### ScheduleWakeup 통합

- **Agent 호출은 synchronous** — Agent tool 은 subagent return 까지 main turn 을 block.
- **ScheduleWakeup 은 Agent 반환 후에만 재예약**. Pending Agent call 있는 상태에서 wakeup 예약 금지 (논리적 race 방지).
- Subagent 프롬프트 안에 `internal_timeout_minutes: 5` soft budget 명시 (Agent tool 자체 timeout 은 10min hard).

### Lessons (append-on-discovery)

운영 중 발견되는 새 failure mode (F-G, F-H...) 는 `references/lessons.md §Subagent failure modes` 섹션에 append. catalog 가 exhaustive 하다고 가정하지 않음.

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
