# APF Warning Pipeline — Cross-Skill Guidelines

Every skill and experience file in this pipeline follows these rules.
Read this document before creating or modifying any skill.

---

## 1. Language

All skills, experience files, and reference documents are written in **English**.
User-facing messages (AskUserQuestion prompts) may use Korean when the user
communicates in Korean, but file content stays in English.

---

## 2. Skill Writing Standards

These align with the `skill-creator` principles:

- **Explain why, not just what.** Provide reasoning so the agent can adapt
  to situations the instructions don't explicitly cover. Avoid heavy-handed
  MUST/NEVER directives — reframe as reasoning when possible.
- **Keep SKILL.md under 500 lines.** Move details to `references/` files
  with clear pointers about when to read them.
- **Progressive disclosure.** Three layers: (1) YAML description (~100 words),
  (2) SKILL.md body, (3) reference/service files loaded on demand.
- **Generalize.** Write for the common case. Service-specific facts belong in
  `services/{service_id}_*.md`, not in the main SKILL.md.
- **Lean prompts.** One clear pattern beats redundant DO NOT lists.
  Remove instructions that aren't pulling their weight.
- **Pushy descriptions.** Include trigger phrases in the YAML `description`
  so the skill activates reliably. List common user phrases.

---

## 3. Duplication Prevention

Duplicated content drifts apart over time, creating contradictions.

| Rule | Example |
|------|---------|
| **Never copy content that exists in another skill.** Reference it by path + section name. | `→ See etap-build-deploy/SKILL.md → Server Info` |
| **One source of truth per fact.** If a fact applies to multiple skills, pick one home and link from others. | Server addresses live in `etap-build-deploy` only. |
| **Shared infrastructure stays shared.** `service_config.py`, server info, build commands — reference, don't duplicate. | |
| **Cross-service patterns go in `references/`.** Per-service facts go in `services/`. | Design pattern confirmed in 2+ services → `references/design-patterns.md` |

**Before writing any new content, check if it already exists:**
1. Search `guidelines.md` (this file)
2. Search skill SKILL.md files
3. Search `references/` directories
4. Search `_backup_20260317/` for prior experience

---

## 4. Experience Management

### 4-1. Append Only

Never delete existing entries in any experience or service file.
When information becomes outdated, add a dated update entry — don't overwrite.

```markdown
### 2026-03-20 — Update
Previous: SSE event count was 6.
Current: SSE event count is now 8 (service added 2 new event types).
```

### 4-2. Storage Locations

| Experience type | Location |
|----------------|----------|
| Frontend structure per service | `genai-frontend-inspect/services/{service_id}_frontend.md` |
| Warning design per service | `genai-apf-pipeline/services/{service_id}_design.md` |
| Implementation journal per service | `apf-warning-impl/services/{service_id}_impl.md` |
| Cross-service design patterns | `genai-apf-pipeline/references/design-patterns.md` |
| Test log templates | `apf-warning-impl/references/test-log-templates.md` |
| Pipeline status | `genai-apf-pipeline/services/status.md` |
| Prior APF network-level experience | `_backup_20260317/apf-add-service/services/{service_id}.md` |

### 4-3. Promotion Rule

When the same pattern is confirmed in **2 or more services**, promote it
from a per-service file to the appropriate `references/` file.

### 4-4. Cross-Pipeline References

The prior APF pipeline's experience (network-level analysis) is preserved in
`_backup_20260317/`. New skills should reference it when relevant:

```markdown
→ Prior network-level analysis: _backup_20260317/apf-add-service/services/chatgpt.md
```

---

## 5. Naming Conventions

| Item | Convention | Example |
|------|-----------|---------|
| Skill directory | `lowercase-hyphen` | `apf-warning-impl` |
| Service experience file | `{service_id}_suffix.md` | `chatgpt_design.md` |
| service_id | lowercase + underscore, brand name | `chatgpt`, `clova_x` |
| Test log marker | `[APF_WARNING_TEST:{service_id}]` | `[APF_WARNING_TEST:chatgpt]` |
| Design pattern name | `UPPER_SNAKE_CASE` | `SSE_STREAM_WARNING` |
| C++ log function | `bo_mlog_*` family | `bo_mlog_info(...)` |
| Reference files | `lowercase-hyphen.md` | `design-patterns.md` |
| Phase N numbering | Reserved for pipeline 7-phase stages only | Other skills use descriptive names (e.g., "Implementation Entry Check") |

---

## 6. Test Log Protocol

### Injection (Phase 3 test builds)

All test logs use the `bo_mlog_info` function with a consistent marker prefix:

```cpp
bo_mlog_info("[APF_WARNING_TEST:%s] <message>", service_name.c_str(), ...);
```

The `[APF_WARNING_TEST:{service_id}]` prefix enables:
- **grep-based monitoring:** `grep APF_WARNING_TEST /var/log/etap.log`
- **per-service filtering:** `grep "APF_WARNING_TEST:chatgpt"`
- **automated removal:** search for the marker in source code

### Verification (during user test)

→ See `apf-warning-impl/references/test-log-templates.md` → Monitoring Commands

### Removal (before release build — hard gate)

```bash
# Verify all test logs removed before Phase 7 (release build)
grep -rn "APF_WARNING_TEST" functions/ai_prompt_filter/
# Expected: no output. If any match → STOP, remove before proceeding.
```

Phase 7 (release build via `etap-build-deploy`) **must not proceed** until
`grep -r "APF_WARNING_TEST"` returns zero matches.

→ See `apf-warning-impl/references/test-log-templates.md` for C++ templates.

---

## 7. Parallel Execution Rules

### Multiple services: Phase 1,2 → then Phase 3

Phase 1 (frontend inspect) and Phase 2 (warning design) can be completed
for multiple services before entering Phase 3. This allows:
- Batch code changes across services
- Single build instead of per-service builds
- Parallel testing of all services in one deployment

### Phase 3 batching strategy

```
Services A, B, C all designed (Phase 2 complete)
  → Implement A, B, C code changes (sequentially — same source file)
  → Single build (ninja) + single deploy
  → Test all services in parallel (user + Cowork log monitoring)
  → Record results per service
```

Code changes are sequential because they modify the same `ai_prompt_filter.cpp`.
Testing is parallel because each service uses a different endpoint.

---

## 8. Required Paths

```
SKILLS_SRC   = ~/Documents/workspace/claude_work/projects/cowork-micro-skills/skills/   # 5 APF skill 의 editable source (Triple-Mirror project 측)
SKILLS_DEPLOY = ~/Documents/workspace/dev_test_sync/shared-skills/                      # 12 skill canonical deploy (Git 에 push, .skill 번들 origin)
SKILLS_INSTALL = ~/.claude/skills/                                                      # ~/.claude/ 에 등록된 (symlink) installation view — Claude Code / Cowork 실제 load 경로
ETAP_ROOT    = ~/Documents/workspace/Officeguard/EtapV3/
CAPTURE_DIR  = ~/Documents/workspace/claude_work/projects/officeguard-etapv3/scripts/capture/
GIT_SYNC_REPO = ~/Documents/workspace/dev_test_sync/         # dev ↔ test PC 동기화 Git 저장소
```

These paths are defined once here. Skills reference this section
instead of repeating the paths.

**Environment note:** The paths above are the user's host machine paths.
In Cowork sessions, the skills folder is mounted at a session-specific path
(e.g., `/sessions/.../mnt/skills/`). When executing commands, resolve `~`
to the actual home directory of the target environment:
- **Host / SSH to servers:** Use `~` as-is (expands to `/home/solution/` on servers)
- **Cowork VM:** Use the mounted path shown in the session context
- **Sub agents (claude -p):** Use `--add-dir` to make paths accessible

---

## 9. Document Checklist

Before finalizing any new or modified document, verify:

```
[ ] Written in English
[ ] No content duplicated from another skill (references used instead)
[ ] Experience entries are append-only (nothing deleted)
[ ] Service-specific facts in services/ (not in SKILL.md)
[ ] Cross-service patterns in references/ (confirmed in 2+ services)
[ ] Test log markers use [APF_WARNING_TEST:{service_id}] format
[ ] Log functions use bo_mlog_* family
[ ] SKILL.md under 500 lines
[ ] YAML description includes trigger phrases
[ ] Cross-references use path + section name format
[ ] Phase 내 불필요한 확인 요청 없음 (§10 자율 실행 원칙)
[ ] TodoList 첫 항목에 ★ 스킬 refresh 포함 (§11-5)
```

---

## 10. Autonomous Execution Principle

The pipeline is designed for continuous execution. Once a user initiates a workflow
(e.g., "Gemini check-warning 진행해줘"), Cowork proceeds through all steps
of the current Phase without pausing for confirmation at each step.

### When NOT to ask the user

- Between steps within the same Phase (Step 1 → 2 → 3 ... → done)
- Before proceeding to the next service in a batch
- Before running grep, reading logs, or other diagnostic actions
- Before applying a fix that follows directly from a diagnosis
- When the next action is already defined in the SKILL.md flow

### When to pause and ask

- Phase transition (Phase 2 → Phase 3): the user may want to review
- Ambiguous failure: multiple possible causes, user judgment needed
- Destructive action not covered by the workflow (e.g., DB schema change)
- The user explicitly said "확인 후 진행" or similar

### Anti-patterns (do NOT do these)

```
❌ "다음 단계를 진행할까요?"          — Phase 내 Step 전환에서 묻지 않는다
❌ "이 서비스를 먼저 할까요?"         — 배치 순서가 이미 정해져 있으면 묻지 않는다
❌ "로그를 확인해볼까요?"             — 진단은 묻지 않고 바로 한다
❌ "어떤 방향으로 진행할까요?"        — SKILL.md에 flow가 정의되어 있으면 따른다
✅ "Phase 2 완료. Phase 3 진입 전 설계 문서를 검토하시겠습니까?" — Phase 전환은 묻는다
✅ "DB 패턴 불일치와 generator 버그 두 가지 가능성. 어느 쪽부터?" — 모호한 실패는 묻는다
```

This principle applies to all skills in the pipeline. Individual skills
(like `test-pc-worker`) may have additional autonomy rules that extend this.

---

## 11. Context Continuity Protocol

Long sessions cause context window pressure. When skill instructions get pushed
out of context, Cowork loses track of procedures and starts asking unnecessary
questions. This protocol prevents that.

### 11-1. Proactive Compact

When a session reaches approximately 50-100 conversation turns or Cowork notices
degraded adherence to skill procedures, trigger `/compact` proactively.
Do NOT wait for the user to request it. Do NOT ask "compact 할까요?" — just do it.

**Test PC 32MB API limit (자율 모드)**: `/compact` 자율 트리거 불가. Subagent dispatch 로
누적 차단 → see `test-pc-worker/SKILL.md §Subagent Dispatch` (canonical).

### 11-2. State Snapshot Before Compact

Before compacting, save the current work state to a file so it survives
context compression. Write to the Git sync repo (dev_test_sync) or the session's
working directory:

```markdown
## Pipeline State Snapshot — {datetime}

### Current Phase & Step
- Service: {service_id}
- Phase: {phase_number}
- Step: {step_number} of {skill_name}
- Status: {what just completed / what's next}

### Pending Actions
- {next action 1}
- {next action 2}

### Key Context (compact-safe)
- {critical fact that must survive compact, e.g., "Strategy D selected for Gemini"}
- {recent test result summary}
- {any file paths being worked on}

### Resume Instructions
After compact, read this file and the relevant Phase skill:
- Pipeline status: genai-apf-pipeline/SKILL.md → Service Status
- Current skill: {skill_path}/SKILL.md
- This snapshot: {this_file_path}
```

### 11-3. Post-Compact Recovery

After `/compact` completes:
1. Read the state snapshot file
2. Re-read the SKILL.md for the current Phase
3. Continue from the recorded step — do NOT restart the Phase
4. Do NOT ask the user "어디까지 했었죠?" — the snapshot has the answer

### 11-4. Phase Transition Re-Read

When transitioning between Phases (not just steps within a Phase),
re-read the incoming Phase's SKILL.md before starting work.
This is a structural safeguard against context decay, not optional behavior.

```
Phase 1 complete → Read genai-apf-pipeline/references/phase5-warning-design.md → begin Phase 2
Phase 2 complete → Read apf-warning-impl/SKILL.md → begin Phase 3
Phase 6 complete → Read etap-build-deploy/SKILL.md → begin Phase 7 (release build)
```

### 11-5. TodoList Skill Refresh Pattern

Every time Cowork creates a new TodoList for a pipeline task, the **first item**
must be re-reading the relevant skill. This is the most reliable refresh mechanism
because: (1) TodoList is a persistent UI widget that survives context pressure,
(2) the item must transition from `in_progress` to `completed`, which requires
actually calling the Read tool, (3) it happens at the start of every task,
not just at phase transitions.

```
Always:
  □ ★ Read {current_phase_skill}/SKILL.md + guidelines.md §10,11
  □ {actual task 1}
  □ {actual task 2}
  □ ...

For long batches (5+ services), insert a mid-point refresh:
  □ ★ Read apf-warning-impl/SKILL.md + guidelines.md §10,11
  □ Service A check-warning
  □ Service B check-warning
  □ ★ Re-read apf-warning-impl/SKILL.md (mid-batch refresh)
  □ Service C check-warning
  □ Service D check-warning
  □ ...
```

The ★ marker distinguishes refresh items from task items at a glance.
Do NOT skip or auto-complete refresh items — the Read tool call is the point.

**VM mount staleness 대응:** Cowork VM의 `.claude/skills/` 마운트는 세션 시작 시
고정된 스냅샷이며, Mac의 원본과 줄 수가 다를 수 있다 (known limitation).
guidelines.md 등 critical file 읽기 시 반드시 `wc -l`로 줄 수를 확인하고,
VM 마운트가 불완전하면 `desktop-commander`로 Mac 원본을 읽는다.
```
# 줄 수 비교 (Bash tool)
wc -l /mnt/.claude/skills/guidelines.md
# Mac 원본 읽기 (desktop-commander, VM 불완전 시)
mcp__desktop-commander__start_process: cat /Users/jhee/.../shared-skills/guidelines.md
```

### 11-6. SSH 접근 규칙

Cowork VM은 네트워크가 격리되어 있어 외부 서버에 직접 SSH 접근이 안 된다.
SSH/scp가 필요한 작업은 반드시 `mcp__desktop-commander__start_process`를 통해 호스트 Mac에서 실행한다.

```
# Cowork에서 SSH 실행 (desktop-commander 경유)
mcp__desktop-commander__start_process:
  command: ssh -p 12222 solution@서버주소 "명령어"
  timeout_ms: 30000
```

**Cowork VM의 Bash tool에서 ssh/scp를 절대 사용하지 않는다.**

---

### 11-7. Claude Code 실행 규칙

Cowork VM에는 `claude` CLI가 없다. Sub agent(`claude -p`)는 desktop-commander로 호스트에서 실행한다.

**3-Step 실행 패턴:**

```
# Step 1 — 실행 (파일 리다이렉트 필수, timeout은 짧게)
mcp__desktop-commander__start_process:
  command: claude -p "프롬프트" --model claude-sonnet-4-6 \
    --dangerously-skip-permissions --allowedTools "Bash,Read" \
    --add-dir /절대/경로1 --add-dir /절대/경로2 \
    < /dev/null > /tmp/cc_output.txt 2>&1
  timeout_ms: 10000

# Step 2 — 완료 폴링 (자식 PID를 ps aux | grep claude로 확인)
command: ps -p {자식PID} > /dev/null 2>&1 && echo "RUNNING" || echo "DONE"

# Step 3 — 결과 읽기
command: cat /tmp/cc_output.txt
```

**주의사항:**
- 프롬프트 내 경로는 §8 Required Paths의 **절대 경로로 직접 치환** — 환경 변수(`$VAR`, `~`) 사용 불가
- `< /dev/null` 필수 (stdin 경고 방지)
- `start_process`가 반환하는 PID는 zsh 래퍼이며, 실제 claude 프로세스는 자식 — `ps aux | grep claude`로 추적

> 검증: 2026-04-03, gemini warning design (sonnet), 252줄 출력, ~3분 소요

---

## 12. File Management Policy

모든 작업 산출물은 아래 정의된 정본 위치에 저장한다.
git 저장소(dev_test_sync)는 dev↔test PC 교환 전용으로만 사용하며,
작업 산출물의 관리 저장소로 사용하지 않는다.

### 12.1 Canonical Locations

| Category | Mac Path | Cowork VM Path |
|----------|----------|----------------|
| Skill runtime (SKILL.md, references/, services/) | `~/.claude/skills/{skill}/` (plugin managed) | `/mnt/.claude/skills/{skill}/` |
| Guidelines (single source of truth) | `~/Documents/workspace/dev_test_sync/shared-skills/guidelines.md` | `/mnt/workspace/dev_test_sync/shared-skills/guidelines.md` |
| Working artifacts (analysis, reports, experiments) | `~/Documents/workspace/claude_work/projects/apf-operation/docs/` | `/mnt/workspace/claude_work/projects/apf-operation/docs/` |
| OS release test histories & methods | `~/Documents/workspace/claude_work/projects/os-release-tests/` | `/mnt/workspace/claude_work/projects/os-release-tests/` |
| Project-scoped work (non-release) | `~/Documents/workspace/claude_work/projects/{project}/` | `/mnt/workspace/claude_work/projects/{project}/` |
| SQL migrations | `~/Documents/workspace/claude_work/projects/apf-operation/sql/` | `/mnt/workspace/claude_work/projects/apf-operation/sql/` |
| Pipeline state (handoff, dashboard, state JSON) | `~/Documents/workspace/claude_work/projects/apf-operation/state/` | `/mnt/workspace/claude_work/projects/apf-operation/state/` |
| Archive (completed artifacts) | `~/Documents/workspace/claude_work/archive/` | `/mnt/workspace/claude_work/archive/` |
| Hook scripts | `~/Documents/workspace/claude_work/projects/apf-operation/hooks/` | `/mnt/workspace/claude_work/projects/apf-operation/hooks/` |
| Dev↔Test exchange ONLY | `~/Documents/workspace/dev_test_sync/` | `/mnt/workspace/dev_test_sync/` |
| C++ source | `~/Documents/workspace/Officeguard/EtapV3/` | `/mnt/Officeguard/` |

### 12.2 Write Authority & Methods

**Cowork VM filesystem constraints:**
- `/mnt/.claude/skills/` — **EROFS (read-only)**. Plugin managed. Cannot use Edit/Write tools.
- `/mnt/workspace/` — writable (claude_work/, dev_test_sync/)
- `/mnt/Officeguard/`, `/mnt/functions/`, `/mnt/apf-db-driven-service/` — **chmod read-only** (SessionStart hook enforced)

**Skill files (services/*_impl.md, *_design.md, *_frontend.md):**
Canonical location: `~/.claude/skills/{skill}/services/` (Mac side, writable).
Cowork VM에서는 Read-only이므로 **반드시 `desktop-commander`로 편집**한다:
```
mcp__desktop-commander__edit_block:
  file_path: /Users/jhee/.claude/skills/{skill}/services/{file}
  old_string: "..."
  new_string: "..."
```
Edit/Write 도구로 `/mnt/.claude/skills/` 경로를 사용하면 EROFS 에러가 발생한다.
Officeguard 경로(`/mnt/Officeguard/`)를 사용하면 EACCES 에러가 발생한다.
**desktop-commander가 유일한 편집 수단이다.**

**Working artifacts (Cowork Edit/Write 사용 가능):**
- claude_work/projects/apf-operation/state/ — handoff.md, pipeline_state.json
- claude_work/projects/apf-operation/docs/ — analysis, reports, experiments
- claude_work/projects/apf-operation/sql/ — migrations
- claude_work/projects/os-release-tests/releases/*/ — 릴리스별 런타임 기록 (autonomous)
- claude_work/projects/os-release-tests/lessons-learned.md — **append-only** 누적 교훈

**User-approval required:**
- SKILL.md (skill behavior changes)
- guidelines.md (operational rules)
- Procedural references (phase*-*.md, protocol files)
- claude_work/projects/os-release-tests/README.md (진입점 + Release Start Checklist)
- claude_work/projects/os-release-tests/test-catalog.md (테스트 ID 추가/변경)

### 12.3 No Duplicate Masters

Each file has exactly one canonical location. The flow is:
```
~/.claude/skills/ (master, Mac writable) → shared-skills/ (deploy snapshot) → .skill (package)
```
Never treat dev_test_sync/docs/ as the master for documents that belong in claude_work/projects/apf-operation/docs/.
guidelines.md는 예외: canonical location은 `dev_test_sync/shared-skills/guidelines.md` (단일 원본).
claude_work/skills/guidelines.md는 삭제됨 (2026-04-20).

**Officeguard/EtapV3/.claude/skills/ — 삭제됨 (2026-04-20 토론 합의).**
중복 사본이 존재하면 Cowork이 잘못된 경로를 편집하므로, .gitignore로 재생성을 방지한다.

### 12.4 Read-only Enforcement (SessionStart Hook)

`pipeline-context.sh`가 세션 시작 시 read-only 디렉토리에 `chmod -R a-w`를 적용한다.
이 보호는 OS 레벨이므로 Edit/Write/Bash 모두에서 강제된다.

Protected directories:
- `/mnt/Officeguard/` — C++ source (편집은 Claude Code 또는 SSH로)
- `/mnt/functions/` — C++ modules
- `/mnt/apf-db-driven-service/` — SQL archive
- `/mnt/workspace/Officeguard/` — same physical dir as above

### 12.5 Migration from dev_test_sync

- New artifacts → claude_work/projects/apf-operation/docs/ (immediately)
- Active artifacts → move to claude_work/ at next use
- Historical artifacts → remain in dev_test_sync/docs/ (read-only)

---

## 13. Operational Rules (User Preferences)

These rules are permanent user preferences. They apply to all skills and sessions.

### 13.1 All work runs on the Mac (dev PC)

All commands — SSH, DB queries, git operations, file editing — execute on the
user's Mac via `desktop-commander` or Mac terminal. The Cowork sandbox has no
network access to internal servers. Never attempt SSH, mysql, or other network
commands from the sandbox; always route through the Mac.

- SSH to servers: `mcp__desktop-commander__start_process` with `ssh -p 12222 ...`
- DB queries: same SSH tunnel → `sudo mysql etap -e "..."`
- git push/pull: `mcp__desktop-commander__start_process` with `cd ~/Documents/workspace/dev_test_sync && git ...`

### 13.2 Follow genai-apf-pipeline skill

APF 관련 작업 시 반드시 `genai-apf-pipeline` 스킬을 로드하고 그 절차를 준수한다.
기억에 의존하지 않고, 매 Phase 진입 시 해당 reference 파일을 Read 도구로 로드한다.

- **Pipeline skill path:** `genai-apf-pipeline/SKILL.md`
- **Phase별 reference:** `genai-apf-pipeline/references/phase{N}-*.md`
- **서비스 상태:** `genai-apf-pipeline/services/status.md`
- **DB 접근:** `genai-apf-pipeline/references/db-access-and-diagnosis.md`
- **로그 진단:** `genai-apf-pipeline/references/etap-log-diagnostics.md`

Key rules from the skill:
- 한 번에 한 서비스만 작업 (Single-Service Focus)
- Phase 전환 시 해당 스킬/reference 반드시 재로드
- blocked=1만으로 성공 판단 금지 — test PC 화면이 ground truth
- 자율 수행 규칙: 질문으로 끝맺지 않고, 결과 도착 시 즉시 판정 + 다음 작업 시작
- DB 변경 후 4단계: UPDATE → reload_services → detect grep → check-warning

이 규칙은 H2 ceiling 실험, 서비스 등록, 경고 구현 등 모든 APF 작업에 적용된다.

### 13.3 Autonomous execution on pending tasks

현재 작업이 완료되면 다음 작업이 있는지 확인하고, 있으면 사용자의 요청 없이
즉시 자율 수행한다. `genai-apf-pipeline` 스킬의 Phase Transitions 테이블과
`services/status.md`를 참조하여 다음 작업을 결정한다.

- 작업 완료 → handoff.md / status.md에서 다음 할 일 확인 → 즉시 시작
- Phase 완료 → Phase Transitions 테이블의 "First Action" 실행
- 서비스 완료(DONE) → 다음 우선순위 서비스로 전환
- 사용자에게 "다음 뭐 할까요?" 묻지 않는다 — 할 일이 있으면 바로 한다
- 할 일이 없을 때만 사용자에게 보고하고 대기한다
- **복수 valid options → 사용자 선택 요구 금지 (Hard Rule 6 v2)**. Mode Selection Tree 적용:
  - **M0 Empirical Comparison (default)** — testable + revertible options 모두 테스트 + metric 비교 + winner. TodoWrite 체크리스트.
  - Fallback: M1 15s reasoning / M2 Micro-Discussion / M3 full discussion-review / M4 user ask (물리적 예외)
  - Per-case 기록: `apf-operation/state/decisions/{ts}_{mode}_{slug}.json` (all-fail 시 `apf-operation/docs/empirical-fail-reports/` 추가)
  - 세부: `genai-apf-pipeline/references/autonomous-execution-protocol.md §Hard Rule 6` + §Empirical Comparison Pattern

### 13.4 Polling Policy (2026-04-23 v2 — 11차 session)

→ **Canonical**: `~/.claude/memory/user-preferences.md` 의 "Polling Policy" 섹션 (v2)

**핵심 요약**:
- **허용 방식**: `ScheduleWakeup(delaySeconds, prompt, reason)` only — session-internal scheduled re-fire
- **금지 (모두)**: `mcp__scheduled-tasks__*`, OS-level **cron** / **launchd**, **fireAt**, **Monitor** persistent, **in-session bash loop** (`while true; sleep N; done` in bash turn), 기타 OS 수준 persistent trigger
- **delay 선택**: 60-270s (short/cache-warm) 또는 1200-1800s (long/idle). **300-1200s 금지 영역** (prompt cache 5min TTL worst-of-both)
- **필수 조건**: prompt 에 exit condition 명시, reason field 구체, duration cap (expected + 30min) 인지, session lifecycle 인지
- **Duration cap 의 Non-applicability (29차 D9 Stage 3 catch)**: "expected + 30min" 은 **사용자 정보 보고 시점** 산출용. **termination trigger 로 사용 금지**. cap 도달 시 polling chain 유지 + 보고 (보고 = continuation, 종료 아님). canonical-cite 형태로 "L553 에 따르면 30min 초과 시 escalate user report 종료" 도출 = D9 anti-pattern Stage 3 (deontic citation).
- **Termination = ONLY 2 조건** (autonomous-execution-protocol.md §Termination Conditions L316-321): (1) 결과 도착, (2) session 종료. 그 외 모든 self-termination 금지.

**세부 protocol**: `genai-apf-pipeline/references/autonomous-execution-protocol.md`

**과거 확대/축소 해석 주의** (INTENTS D1 사례):
- ❌ "No schedulers" → "모든 polling 금지"
- ❌ "수동 폴링만" → "in-session loop 도 금지"
- ❌ "bash loop 만 허용" → "ScheduleWakeup = scheduler = 금지" (7차 wording lock)
- ✅ 정확한 경계: **session-internal scheduled re-fire (ScheduleWakeup) 허용. OS-level + external notification 기반 trigger 금지.**
