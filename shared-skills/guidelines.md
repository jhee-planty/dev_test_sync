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
| Warning design per service | `apf-warning-design/services/{service_id}_design.md` |
| Implementation journal per service | `apf-warning-impl/services/{service_id}_impl.md` |
| Cross-service design patterns | `apf-warning-design/references/design-patterns.md` |
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
| Skill directory | `lowercase-hyphen` | `apf-warning-design` |
| Service experience file | `{service_id}_suffix.md` | `chatgpt_design.md` |
| service_id | lowercase + underscore, brand name | `chatgpt`, `clova_x` |
| Test log marker | `[APF_WARNING_TEST:{service_id}]` | `[APF_WARNING_TEST:chatgpt]` |
| Design pattern name | `UPPER_SNAKE_CASE` | `SSE_STREAM_WARNING` |
| C++ log function | `bo_mlog_*` family | `bo_mlog_info(...)` |
| Reference files | `lowercase-hyphen.md` | `design-patterns.md` |

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
# Verify all test logs removed before Phase 4
grep -rn "APF_WARNING_TEST" functions/ai_prompt_filter/
# Expected: no output. If any match → STOP, remove before proceeding.
```

Phase 4 (release build via `etap-build-deploy`) **must not proceed** until
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
SKILLS_DIR   = ~/Documents/workspace/claude_cowork/skills/
ETAP_ROOT    = ~/Documents/workspace/Officeguard/EtapV3/
CAPTURE_DIR  = ~/Documents/workspace/claude_cowork/projects/officeguard-etapv3/scripts/capture/
BACKUP_DIR   = SKILLS_DIR/_backup_20260317/
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
Phase 1 complete → Read apf-warning-design/SKILL.md → begin Phase 2
Phase 2 complete → Read apf-warning-impl/SKILL.md → begin Phase 3
Phase 3 complete → Read etap-build-deploy/SKILL.md → begin Phase 4
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

## SSH 접근 규칙

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

## Claude Code 실행 규칙

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
