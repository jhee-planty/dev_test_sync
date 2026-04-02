---
name: genai-apf-pipeline
description: >
  Master orchestrator for GenAI APF (ai_prompt_filter) **block** workflow. 3-phase pipeline: HAR capture → analysis + registration → build + deploy. Cowork orchestrates Claude Code sub agents (Opus) in parallel, reviews results (quality gate), then directs the main agent to apply file changes. Use this skill for: capturing AI service traffic, HAR analysis, adding new services to the block list, APF SQL/C++ code generation, build and deploy coordination, or role division questions. This is the entry point for all APF **blocking** work. Do NOT use for warning design, warning implementation, or frontend inspection — those belong to genai-warning-pipeline and its sub-skills.
---

# GenAI APF Pipeline — Master Orchestrator

## Goal

Analyze AI service prompt requests and response messages, then register per-service
sensitive-information warning responses in the EtapV3 `ai_prompt_filter` module.

Cover as many AI services as possible, accumulating analysis and development experience
toward a fully automated routine. Full automation is limited by user-dependent steps
(login/capture and testing).

---

## Required Paths (verify before starting)

```
COWORK_ROOT  = ~/Documents/workspace/claude_cowork/
SKILLS_DIR   = ~/Documents/workspace/claude_cowork/skills/
SCRIPTS_DIR  = ~/Documents/workspace/claude_cowork/projects/officeguard-etapv3/scripts/
CAPTURE_DIR  = ~/Documents/workspace/claude_cowork/projects/officeguard-etapv3/scripts/capture/
ETAP_ROOT    = ~/Documents/workspace/Officeguard/EtapV3/
ETAP_HAR_DIR = ~/Documents/workspace/Officeguard/EtapV3/genAI_har_files/
```

**Cowork usage**: Both root directories must be accessible.
  - `claude_cowork/` — skill files, capture scripts
  - `Officeguard/EtapV3/` — HAR files, C++ source code

**Claude Code usage**: Work from the EtapV3 project root.
  - `cd ~/Documents/workspace/Officeguard/EtapV3 && git branch --show-current`
  - Local branch and compile server branch must match.

---

## How to Use

Users interact with Cowork (this conversation) in natural language. No need to know specific commands.

**Phase 1 examples (User + Cowork collaboration):**
```
"Let's capture Gemini. I'll log in."
"Login done. Start the capture."
"I closed the popup. Check if the prompt input is visible."
```

**Phase 2 (automatic — triggers on successful capture):**
After a successful capture, Cowork automatically calls a Claude Code sub agent (Opus)
to start Phase 2 analysis. No user request needed.

**Phase 3 examples:**
```
"Build and deploy to the test server."
```

**Test result reporting (user tests, then reports to Cowork):**
```
"Gemini passed, Copilot blocking didn't work. Looks like the service isn't detected in etap logs."
"All services tested. Only Perplexity failed."
```

Cowork references skills to call sub agents, review results, and execute build/deploy.
**Testing is performed by the user.** Cowork waits for test result reports and updates status accordingly.

---

## Role Division — User vs Cowork vs Claude Code

| Role | Responsibilities | Details |
|------|-----------------|---------|
| **User** | Phase 1 collaboration, testing | Login, dismiss ads/popups, confirm prompt input. After Phase 3 deployment, verify blocking on test server and report results. |
| **Cowork** | Phase 1 assist, orchestration, quality review, status mgmt | Phase 1: Collaborate with user — run capture_v2.py + verify screen via Claude in Chrome. Phase 2–3: Call sub agents, review, direct file changes. Wait for test results, then update status. |
| **Claude Code (sub agent, Opus)** | HAR analysis, code generation (stdout only) | Analyze HAR raw files, determine response type (SSE/JSON/Chunked/etc.), generate SQL + C++ code. Read-only — no file modifications. |
| **Claude Code (main agent)** | File modification, build/deploy | Apply Cowork-approved results to files. Build + deploy to test server. |

**Flow:** User+Cowork capture → Cowork auto-triggers sub agent analysis → Cowork reviews → main agent applies → user tests → reports results.

---

## SSH/원격 접근 규칙

**Cowork VM에서는 SSH/scp가 불가능하다.**
컴파일 서버, 테스트 서버 접근이 필요한 작업은 반드시 `mcp__desktop-commander__start_process`를 사용한다.
Cowork VM의 Bash tool에서 직접 ssh/scp를 실행하면 네트워크 격리로 인해 실패한다.

→ See `etap-build-deploy/SKILL.md` § SSH 접근 규칙 for 상세

---

## Pipeline Overview

```
Phase 1 — HAR Capture [User + Cowork collaboration]
  User: Login, dismiss ads/popups, verify page state
  Cowork: Assist capture_v2.py execution, verify screen via Claude in Chrome
  → Only successfully captured services advance to Phase 2
  → Failed/pending services remain in queue
  Skill: genai-har-capture/SKILL.md
  Script: CAPTURE_DIR/capture_v2.py

Phase 2 — HAR Analysis + APF Registration [Cowork → Claude Code sub agent (Opus), automatic]
  Auto-triggers on successful capture (condition: metadata.json total_requests > 0)
  2a. Cowork calls per-service sub agents in parallel
      (claude -p --model claude-opus-4-6, Read only)
      → HAR analysis + SQL + C++ generation → stdout output
  2b. Cowork reviews each result (quality gate)
      → Failures: re-run only the affected service
  2c. Cowork calls main agent (claude -p, Edit included)
      → Apply approved results to files + update handoff.md
  Skill: apf-add-service/SKILL.md
  Experience: apf-add-service/services/{service}.md

Phase 3 — Build & Deploy [Claude Code]
  scp changed files → compile server build → deploy package to test server
  Skill: etap-build-deploy/SKILL.md

Test — Verify Blocking [User]
  User verifies blocking behavior on the test server.
  Cowork waits for the user's test result report, then updates status.
```

For parallel processing details and sub agent invocation commands,
see `apf-add-service/SKILL.md` Parallel Execution section.

### Quality Gate: Two Modes

**Primary mode (Cowork-orchestrated):**
Sub agents output structured text (`=== ANALYSIS === / === SQL === / ...`) to **stdout**.
Cowork captures stdout, reviews each section, then calls the main agent to apply approved results.
This is the normal flow described in the Pipeline Overview above and in `apf-add-service/SKILL.md`.

**토론 에스컬레이션:** Quality Gate에서 판단이 불확실한 경우(프로토콜 모호, 코드 구조 이질, 경험 부재)
`skill-discussion-review`로 다자간 토론을 진행하여 승인/거부를 결정한다.
→ See `references/discussion-integration.md` for 트리거 조건 및 절차.

**Fallback mode (Standalone — Claude Code without Cowork):**
If Claude Code is invoked directly without Cowork orchestration, the sub agent
cannot output to Cowork. Instead, it writes results to `services/{service_id}_pending.md`
and stops — no source file modifications.

```
Standalone fallback:
  Claude Code reads skill → detects no Cowork orchestration
    → writes analysis to services/{service_id}_pending.md
    → prints warning: "Cowork review required"
    → STOPS (no .h/.cpp/.sql/handoff.md changes)

Later, Cowork reviews _pending.md:
  ├─ ✅ Approved → rename to {service_id}.md + call main agent to apply
  └─ ❌ Rejected → delete _pending.md + re-run with feedback
```

See `apf-add-service/SKILL.md` → Standalone Execution Guard for detection logic.

---

## Test-Fix Cycle

Not all services succeed on the first attempt.
After Phase 3, **the user tests directly** on the test server and reports results to Cowork.
Cowork routes each service to the appropriate re-entry path.

```
Phase 2 (analysis+impl) → Phase 3 (build+deploy) → User tests → Reports to Cowork
  │
  ├─ Compile error (BUILD_FAIL)
  │   → Identify affected service from error log
  │   → Fix code → retry Phase 3 (affected service only)
  │
  ├─ Blocking failure (TEST_FAIL)
  │   → User uploads fail HAR (+ optional console log)
  │   → Cowork invokes apf-test-diagnosis skill
  │   → Diagnosis report: pattern ID + root cause + recommended fix
  │   ├─ Known pattern → targeted code fix → retry Phase 3
  │   └─ Unknown pattern → full analysis (may re-enter Phase 2 with fail_har)
  │      → TEST_FAIL 2연속 또는 Unknown pattern 시 skill-discussion-review 토론 활용 권장
  │         See references/discussion-integration.md
  │
  └─ Success → services/status.md state → 🟢 DONE
```

### Managing multiple services concurrently

```
Service A: 🟢 DONE (test passed)
Service B: 🔴 TEST_FAIL → fixing code
Service C: 🟠 BUILD_FAIL → fixing compile error

→ Fix only B, C then retry Phase 3 (A untouched)
→ scp only modified files → build → deploy
→ Update each service status individually
```

### Information to collect on test failure

| Info | Collection method | Purpose |
|------|------------------|---------|
| **fail HAR** (required) | DevTools > Network > Export HAR (from page load to error) | Primary diagnosis input |
| Console log (optional) | DevTools > Console > Save as | ERR_ patterns, JS errors |
| etap log | SSH → `tail -f /var/log/etap/...` | Verify detection, generator invocation |
| block_response bytes | etap log or Wireshark | Verify actual transmitted data |

→ **See `apf-test-diagnosis/SKILL.md`** for the structured diagnosis procedure.
  Cowork runs the diagnosis locally using the bundled HAR parser script.

### Status update rules

Always update `services/status.md` based on test results:
- Change state (e.g., TESTING → TEST_FAIL)
- Add row to re-entry history table (date, cause, action, result)

### Periodic Test Cycle

Even completed (🟢 DONE) services can break when the AI service updates its frontend.
Periodically run Phase 3 (build + deploy), then **the user re-verifies all registered services**.

```
Periodic test flow:

1. Cowork: Execute Phase 3 (build + deploy to test server)
2. User: Verify blocking for all registered services on test server
3. User: Report results to Cowork
   e.g., "ChatGPT, Claude OK. Perplexity blocking failed."
4. Cowork: Set failed services to 🔴 TEST_FAIL
5. Cowork: Enter Test-Fix Cycle for failed services
   → If needed, collect fail_har (User + Cowork collaboration) → re-enter Phase 2
```

**Cowork cannot perform testing directly.** It waits for the user's result report.
Based on reported symptoms, Cowork identifies the appropriate re-entry path.

---

## New Service Checklist

```
Phase 1 — HAR Capture [User + Cowork collaboration]
  User:
  [ ] Log in to the target service (if required)
  [ ] Dismiss ads/popups/cookie banners
  [ ] Confirm prompt input field is visible, then notify Cowork
  Cowork:
  [ ] Register service in service_config.py
  [ ] Verify screen via Claude in Chrome (optional — use when user reports uncertainty or for debugging)
  [ ] Run: python3 capture_v2.py --id {id} --copy-to-etap
  [ ] Check metadata.json: total_requests > 0
  [ ] Classify response type from traffic.json resp_content_type field
      (sse | json | chunked | websocket | other)
      → Continue regardless of type. If sse_streams == 0, check traffic.json resp_content_type
      → ⚠️ Known bug: --copy-to-etap fails for non-SSE (SSE=0). Manual copy required.
         See genai-har-capture/SKILL_debug.md → Known Bugs
  [ ] Capture success → auto-enter Phase 2
  [ ] Capture failure → set status to 🔘 CAPTURE_FAIL → investigate with user → retry or mark ❌ NOT_FEASIBLE

Phase 2 — HAR Analysis + APF Registration [Cowork → Claude Code sub agent (Opus), automatic]
  (Auto-triggers on successful capture — no user request needed)
  [ ] Call per-service sub agents in parallel (claude -p --model claude-opus-4-6, Read only)
  [ ] Review each sub agent result (Cowork quality gate)
  [ ] Re-run problematic services
  [ ] Request main agent to apply approved results (claude -p, Edit included)
  [ ] Update services/{service_id}.md experience + status.md

Phase 3 — Build & Deploy [Claude Code]
  [ ] Verify local/compile server branch match
  [ ] scp changed files
  [ ] Compile server build (ninja && ninja install)
  [ ] Package → local → deploy to test server

Test — Verify Blocking [User]
  (User performs testing. Cowork waits for result report.)
  [ ] User: Verify blocking for each service on test server
  [ ] User: Report results to Cowork (success/failure + symptoms)
  [ ] Cowork: Record symptoms in services/{service}.md for failures
  [ ] Cowork: Update status.md + add re-entry history row
  [ ] Cowork: Fix code → retry Phase 3 (failed services only)
  [ ] If needed: collect fail_har (User + Cowork collaboration) → re-enter Phase 2

Experience accumulation:
  [ ] Capture experience → genai-har-capture/SKILL_debug.md Known Service Notes
  [ ] Analysis/implementation experience → apf-add-service/services/{service}.md
  [ ] Common patterns (2+ services) → apf-add-service/SKILL.md Common Pitfalls
```

---

## Sub-Skills (absolute paths)

| Skill | File path | Role | Owner |
|-------|-----------|------|-------|
| genai-har-capture | `SKILLS_DIR/genai-har-capture/SKILL.md` | Phase 1: capture, format spec, session mgmt | User + Cowork |
| genai-har-capture debug | `SKILLS_DIR/genai-har-capture/SKILL_debug.md` | Capture debugging, per-service notes | Shared |
| apf-add-service | `SKILLS_DIR/apf-add-service/SKILL.md` | Phase 2: HAR analysis + SQL + C++ + registration | Claude Code sub agent (Opus): analyze, main agent: apply |
| apf-add-service services | `SKILLS_DIR/apf-add-service/services/{service}.md` | Per-service analysis/implementation experience | Claude Code (sub agent) |
| etap-build-deploy | `SKILLS_DIR/etap-build-deploy/SKILL.md` | Phase 3: source sync + build + test server deploy | Claude Code (main agent) |
| apf-test-diagnosis | `SKILLS_DIR/apf-test-diagnosis/SKILL.md` | Test failure diagnosis (HAR/console analysis) | Cowork |
| apf-test-diagnosis patterns | `SKILLS_DIR/apf-test-diagnosis/references/error_patterns.md` | Known error pattern dictionary | Cowork |
| skill-discussion-review | `SKILLS_DIR/skill-discussion-review/SKILL.md` | Quality Gate 불확실 시 토론, 정기 점검 토론 | Cowork |

**Read only the skills needed for the current phase.**
- Phase 1 → `genai-har-capture/SKILL.md` only
- Phase 2 → `apf-add-service/SKILL.md` + relevant `services/{service}.md`
- Phase 3 → `etap-build-deploy/SKILL.md` only
- Test failure → `apf-test-diagnosis/SKILL.md` + relevant `services/{service}.md`
- Capture error → `SKILL_debug.md` only

---

## Experience Storage (single source of truth)

| Experience type | Storage location | Example |
|----------------|-----------------|---------|
| Capture-related (selector, login, bot detection) | `genai-har-capture/SKILL_debug.md` Known Service Notes | "Perplexity: Lexical editor → use_keyboard_type: True" |
| Per-service analysis/impl/debugging | `apf-add-service/services/{service}.md` | "Genspark: SSE separator \n\n only" / "ServiceX: JSON, body.message" |
| Common patterns (2+ services confirmed) | `apf-add-service/SKILL.md` Common Pitfalls | "Some services only accept \n\n separator" |
| Test failure diagnosis results | `apf-add-service/services/{service}.md` → Diagnosis History | "P001: WRITE_THEN_DISCONNECT, body_size=0" |
| Test-time error patterns (HAR signatures) | `apf-test-diagnosis/references/error_patterns.md` | "P001: status=200, body=0, receive<100ms" |

**Rules:**
- Per-service files: concrete facts about that service.
- Common Pitfalls: generalized lessons only.
- **Promotion**: Same pattern confirmed in 2+ services → promote to Common Pitfalls.
- **Append only**: Never delete existing entries.
