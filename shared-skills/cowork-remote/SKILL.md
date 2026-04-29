---
name: cowork-remote
type: A
description: Dev PC (Mac) ↔ Test PC (Windows) 간 Git 기반 비동기 협업. dev 가 request push, test 가 result push. 본 skill 은 dev 쪽 전담 (test 쪽은 test-pc-worker). Use when user says "test PC 에 요청 보내줘", "check-warning {서비스}", "check-block {서비스}", "큐 상태", "결과 확인", "원격 작업", "폴링", "result scan", or any cross-PC coordination. 결정론적 runtime (bash scripts) 으로 git/filesystem 작업 수행, Claude 는 자연어→command 추론 + 결과 성공/실패 판정만 담당. Auto STALLED 에스컬레이션 없음 (응답 도착까지 반복 scan). 3-Strike 는 genai-apf-pipeline 에서 판정.
allowed-tools: Bash, Read, Write, Edit
---

# cowork-remote

Dev PC 전용 micro-control skill. 결정론 runtime + Claude 판단 분리.

## 기본 인프라

- **Git repo**: `$GIT_SYNC_REPO` (default: `~/Documents/workspace/dev_test_sync`)
- **Remote**: `jhee-planty/dev_test_sync` (GitHub)
- **쓰기 분리**: dev → `requests/`, test → `results/` (위반 금지)
- **State**: `local_archive/state.json` (gitignored, dev 전용 필드)

## Runtime 호출 규약

본 skill 의 모든 결정론 작업은 `$SKILL_DIR/runtime/` 또는 프로젝트 루트의 `runtime/cowork-remote/` 의 bash script 를 통해 수행.

```bash
# SKILL_DIR 추정 (skill bundle 설치 위치)
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE:-$0}")" && pwd)"
# 개발 환경에서는 project runtime 경로 사용
RT_DIR="${RT_DIR:-$SKILL_DIR/runtime}"
```

---

## 3 기본 작업 (Claude 가 수행하는 흐름)

### A. Outbound — request 생성 및 push

**Trigger**: "check-warning {service}", "check-block {service}", "test PC 에 X 요청" 등.

**흐름**:
1. Claude: 자연어 → `command` + `params` 추론
2. 임시 JSON 파일 생성 (`/tmp/req-draft-XXX.json`) — schema 는 §Request Schema 참조
3. Runtime 실행: `bash $RT_DIR/push-request.sh /tmp/req-draft-XXX.json`
   - ID 자동 할당, rate limit gate (pending ≤ 2 확인), requests/ copy, queue.json append, git push (3-retry)
   - exit 0 = 성공 + 할당된 ID stdout / exit 1 = rate limit 초과 / exit 2 = fatal
4. 사용자에게 보고: "작업 #{id} 전송 완료"

**Claude 판단 부분** (자연어 → JSON):
- `service` 추출 (gemini/chatgpt/claude/deepseek/…)
- `command` 선택 (check-warning / check-block / check-cert / capture-screenshot)
- `params.expected_text` 등 task-type 별 필수 필드 채우기

**금지**: ID 를 Claude 가 직접 할당 금지. 반드시 push-request.sh 에 위임.

### B. Inbound — scan, 판정, 갱신

**Trigger**: "결과 확인해줘", "새 결과 왔어?", "폴링 한번 돌려줘" 등.

**흐름**:
1. Runtime: `bash $RT_DIR/scan-results.sh` — git pull + filesystem scan + 새 결과 ID 목록 stdout (newline separated)
2. 새 결과 없음 (stdout empty) → "대기 중" 짧게 보고 + 종료 (추가 polling 여부는 사용자 지시)
3. 새 결과 있음 → **각 ID 별로 아래 루프**:
   a. `cat $GIT_SYNC_REPO/results/{id}_result.json` 읽기
   b. **Claude 판단** (§Result Classification 가이드) — verdict ∈ `{done, error_PROTOCOL_MISMATCH, error_NOT_RENDERED, error_SERVICE_CHANGED, error_AUTH_REQUIRED, error_INFRASTRUCTURE}`
   c. Runtime: `bash $RT_DIR/update-queue.sh {id} {verdict} "{summary}"`
   d. Runtime: `bash $RT_DIR/archive-completed.sh {id}` (request+result → local_archive/YYYY-MM-DD/)
   e. (옵션) Runtime: `bash $RT_DIR/notify.sh "APF" "#{id} {verdict}"` — 핵심 이벤트만
4. 사용자에게 요약 보고 : 처리된 ID 들 + verdict 들

**중요**:
- 응답 대기 중 자동 STALLED 에스컬레이션 **없음**. 결과 안 오면 계속 scan 반복 (호출자 루프 책임).
- scan-results.sh 는 state.json.last_checked_result_id 이후만 반환 (filesystem authority).

### C. State 조회/갱신 (작업 중 보조)

- 읽기: `bash $RT_DIR/state-read.sh` → JSON stdout
- 필드 갱신: `bash $RT_DIR/state-update.sh <field> <value>`
- last_request_id / last_checked_result_id / updated_at 만 dev 권한

---

## Request Schema

```json
{
  "id": "{auto-assigned-by-runtime-do-not-set}",
  "command": "check-warning | check-block | check-cert | capture-screenshot | verify-access | run-scenario | report-status | verify-warning-quick",
  "priority": "normal | urgent",
  "params": {
    "service": "gemini",
    "expected_text": "보안 정책에 의해",
    "expected_format": "readable warning in chat bubble"
  },
  "attachments": [],
  "created": "{auto-filled}",
  "notes": "{Claude 가 맥락 설명 한 줄}"
}
```

runtime 이 `id` / `created` 를 채움. Claude 는 **id 를 절대 채우지 않는다**.

### verify-warning-quick command (28차 R3 #1, cheap D20b)

> **Purpose**: D20(b) DONE Verification 의 lightweight form. 30s/service target (vs check-warning ~5min).
> **Spec source**: `apf-warning-impl/SKILL.md §Verify-Done Periodic`.

**Request payload**:
```json
{
  "command": "verify-warning-quick",
  "params": {
    "service": "<service_id>",
    "test_prompt": "<rotation item — apf-warning-impl §Verify-Done Periodic 의 7-item rotation set 에서>",
    "timeout_seconds": 30
  }
}
```

**Result classification (verify-warning-quick 전용)**:

| 조건 | verdict |
|------|---------|
| `dom_assertion == "pass"` | `done_verified` (status=DONE 유지) |
| `dom_assertion == "fail_no_warning"` | `done_drift` (status DONE → BLOCKED_diagnosed regression, cause_pointer 갱신) |
| `dom_assertion == "fail_wrong_content"` | `done_drift_partial` (warning element 있지만 content mismatch — render-layer schema gap, mistral F-5 분류) |
| `dom_assertion == "unable_offline"` | `error_INFRASTRUCTURE` (test PC unreachable) |
| `dom_assertion == "unable_no_login"` | `error_AUTH_REQUIRED` (NEEDS_LOGIN 으로 status mutation) |

**Test PC worker 구현 시 핵심 제약**:
- 단일 prompt push + DOM 조회 1회만 (timing 최적화)
- Subagent dispatch 패턴 따름 (test-pc-worker §Subagent Dispatch canonical)
- Result 의 `raw_dom_excerpt` field 에 warning element outerHTML 1개 포함 (size cap: 2KB)

**아직 미구현**: 본 spec 은 28차 codify 만. test-pc-worker side 의 verify-warning-quick handler 는 future implementation session 에서 추가.

## Result Classification 가이드 (Claude 판단)

Result JSON 의 `status` 와 `result` 필드를 읽고 다음 분기:

| 조건 | verdict |
|------|---------|
| `status == "done"` && warning_visible=true (또는 blocked=true) | `done` |
| `status == "error"` && notes 에 "HTTP 2XX but blocked" / SSE/WebSocket mismatch | `error_PROTOCOL_MISMATCH` |
| `status == "done"` && warning_visible=false (DOM 삽입 but 보이지 않음) | `error_NOT_RENDERED` |
| `status == "error"` && notes 에 "endpoint changed" / "structure differs" | `error_SERVICE_CHANGED` |
| `status == "error"` && notes 에 "login" / "session" / "CAPTCHA" | `error_AUTH_REQUIRED` |
| `status == "error"` && notes 에 "timeout" / "crash" / "desktop-commander" | `error_INFRASTRUCTURE` |
| 분류 불확실 | `error_INFRASTRUCTURE` + notes 에 "CATEGORIZATION_UNCERTAIN" 명시 |

**summary** 한 줄 (60자 이내) 필수. 예: "gemini warning visible + text match"

**Dev-side context-size 보호** (2026-04-27 discussion-review): Result JSON 의 `screenshot` 필드 (예: `files/{id}/step1.png`) 가 가리키는 PNG 파일을 **Dev 세션이 직접 `Read` 하지 않는다**. 재검증 필요 시 새 `check-*` request 를 push (또는 Test PC 측에서 새 subagent spawn). → Canonical: `test-pc-worker/SKILL.md §Subagent Dispatch`.

---

## Rate Limit Gate

runtime 의 `push-request.sh` 가 자동 적용 (filesystem pending count ≤ 2). 초과 시 exit 1 + stderr 에 현재 pending ID 목록 출력. Claude 는 사용자에게 "대기 후 재시도" 안내.

## Git Sync 단일 경로

- transport : `git pull` / `git push` (CLI only, GitHub MCP 미사용)
- detect : `scan-results.sh` (filesystem authority, "Already up to date" 무시)

## 제외된 기능 (의도적)

- ❌ Scheduled Task / cron / fireAt / Monitor persistent / in-session bash loop — **Canonical**: see `~/.claude/memory/user-preferences.md` Polling Policy (v2: ScheduleWakeup only)
- ❌ STALLED 자동 에스컬레이션 (2026-04-21 사용자 지시)
- ❌ GitHub MCP connector (단일 transport 경로 유지)
- ❌ L3 visual diagnosis (별도 skill 로 분리 예정)

## 에러 복구

- `git push` 실패 : runtime 이 자동 3-retry (즉시 / `pull --rebase` / `stash+pull+pop`). 그래도 실패면 exit 2.
- `scan_results.sh` 실패 : exit 2 → Claude 는 사용자에게 "scan runtime error" 보고 + 원인 전달.

---

## Related micro-skills

- `test-pc-worker` : test PC 쪽 pair.
- `etap-build-deploy` : 빌드/배포 완료 후 본 skill 로 검증 요청 push.
- `apf-warning-impl` : warning impl 세션 중 본 skill 통해 test 왕복.
- `genai-apf-pipeline` : 최상위 orchestrator. 본 skill 을 반복 호출.
- `research-gathering` : 본 skill 에 영향 주는 과거 설계 / 사용자 구두 지시를 찾을 때 — "왜 request schema 가 이렇게 정해졌는가" 같은 이력 조사 시 6-Tier scan.
