# Phase 6 — Warning Implementation (Orchestration View)

> **Skill scope**: 본 파일은 **`genai-apf-pipeline` 의 Phase 6 orchestration view** 다.
> Phase 6 internal iteration detail (engine source 수정 / build / deploy / verify loop 의
> 구체적 파일 / 함수 / verify protocol) 은 **`apf-warning-impl/SKILL.md`** 가 canonical.
> 본 파일은 위임 boundary + sub-loop 진입/종료 조건 + cross-skill 호출 wrapper.
>
> **출처**: 31차 discussion-review (`cowork-micro-skills/discussions/2026-04-30_apf-pipeline-workflow-normalization.md`) — empirical mining 결과 (mistral 36 reqs / gamma 29 / gemini3 13 / deepseek 12 → 모두 Phase 6 iteration 중심).

---

## Goal

Phase 5 design doc (services/{svc}_design.md) 를 입력으로 받아, engine 의 warning emit code 를 작성/수정하고 build → deploy → check-warning 을 반복하여 **사용자 화면에 경고 문구가 렌더되는 상태 (DONE)** 도달.

APF Mission anchor: 모든 등록 AI 서비스에 대해 PII 포함 프롬프트 입력 시 사용자 화면에 경고 문구 표시.

---

## 위임 boundary (genai-apf-pipeline ↔ apf-warning-impl)

| 책임 | Skill | Detail |
|------|-------|--------|
| **Strategy 결정** (Phase 6 진입 시) | genai-apf-pipeline | services/{svc}_design.md 의 strategy A-E 채택 |
| **Engine source 수정** (구체적 함수 / 파일) | apf-warning-impl | C++ generator 수정, envelope code 작성 |
| **Build orchestration** | etap-build-deploy (apf-warning-impl 가 호출) | ninja build + symbol verify |
| **Deploy** | etap-build-deploy (호출 chain) | test-PC 로 binary 배포 + reload_services |
| **check-warning request emit** | cowork-remote (apf-warning-impl 가 호출) | request push, scan-results |
| **Verdict 판정** | apf-warning-impl + Claude | warning_rendered + envelope match + no fallback error |
| **Failure-class 분류** | genai-apf-pipeline (orchestration view) | result.failure_class auto-classify (P3) |
| **next_action mutation** | apf-warning-impl | failure-class default → next_action set |
| **Mission-critical regression detection** | genai-apf-pipeline | P4 trigger condition (3 consec same / previously-passing regression / mission evidence) |
| **cause_pointer revise (M2/M3)** | genai-apf-pipeline | T2/T5 termination → cause_pointer 재진단 |
| **D20b verify-warning-quick** | cowork-remote (cheap) + apf-warning-impl §Verify-Done Periodic | 7-item rotation, DONE_candidate → DONE 승급 |

> **Boundary 원칙**: genai-apf-pipeline = "어느 service 가 다음? 어떤 strategy / decision? 종료 조건 충족?" — orchestration view. apf-warning-impl = "현재 service 의 engine code 어떻게 수정? build verify 어떻게? envelope sequence 어떻게 emit?" — execution view.

---

## Phase 6 Retry Sub-loop (P2 canonical)

```
loop until termination (T1-T5, see SKILL.md §Phase 6 Termination Conditions):
  next_action = apply_engine_fix:* | debug_envelope:* | debug_decoder:* | debug_http_layer:*
   ↓
  apf-warning-impl: engine source modify (Mac dev / source_for_test/EtapV3 path)
   ↓
  apf-warning-impl → etap-build-deploy: ninja build + symbol verify
   ↓
  etap-build-deploy: deploy binary to test-PC + reload_services (or reload_templates)
   ↓
  apf-warning-impl → cowork-remote: push check-warning request
   ↓
  test-pc-worker subagent: navigate URL → inject prompt → capture DOM/network/console → emit result.json
   ↓
  cowork-remote scan-results → archive → forward to apf-warning-impl + genai-apf-pipeline
   ↓
  IF result.overall_status = SUCCESS AND warning_rendered AND envelope_match AND no_fallback_error:
       → apf-warning-impl marks DONE_candidate
       → cowork-remote: D20b verify-warning-quick rotation entry
       → IF D20b PASS: genai-apf-pipeline marks DONE (T1)
  ELIF result.overall_status IN {FAIL, PARTIAL}:
       → apf-warning-impl appends failure_history
       → genai-apf-pipeline auto-classifies failure_class (P3)
       → IF latest 3 entries same category: T2 termination (cause_pointer revise via M2/M3)
       → ELIF previously-passing regression detected: T2 + P4 mission-critical bump
       → ELSE: apf-warning-impl mutates next_action per P3 default mapping
  ELIF AUTH_REQUIRED: T3 — defer:user_login_provisioning, status → NEEDS_LOGIN
  ELIF INFRASTRUCTURE: T4 — infra_blocked:test_pc, resume next session
  ELIF M3 architectural decision (BLOCK_ONLY accepted): T5 — terminal_reason set, status → TERMINAL_UNREACHABLE
   ↓
  pipeline_state.json commit + (if test-PC required) push request
   ↓
  loop
```

`unverified_deploys` counter (per-service entry, vocabulary v2): +1 per `apply_engine_fix:*` deploy without verify, reset to 0 on SUCCESS verify. ≥3 → forced `defer:awaiting_verification` (WSA v2 step 4 enforce).

---

## Phase 6 Decision Checklist (31차 normalized)

> orchestration view 의 decision points (apf-warning-impl 의 internal decision 은 별도).

| ID | Decision Point | Criteria | Source of Truth |
|----|---------------|----------|-----------------|
| **D6.1** | Engine fix verb 선택 | failure_class → next_action default (P3 mapping) — `apply_engine_fix:*` (코드 수정 단계) / `debug_envelope:*` (분석 단계) / `debug_decoder:*` (디코더 분석) / `debug_http_layer:*` (transport 분석) | failure_history latest + cause_pointer |
| **D6.2** | Build verify | ninja success + symbol exists per `feedback_verify_before_commit`. apf-warning-impl 가 etap-build-deploy 호출, 결과 받아 verdict | etap-build-deploy 결과 |
| **D6.3** | D20b verify rotation entry | 첫 SUCCESS 시 즉시 D20b rotation 등록 (cheap 30s/service, 7-item rotation) | apf-warning-impl §Verify-Done Periodic |

**FAIL handling**:
- D6.1 verb mismatch (debug 가 필요한데 apply_engine_fix 호출) → cause_pointer 명시화 후 재선택
- D6.2 build fail → engine source 수정 retry (apf-warning-impl internal)
- D6.3 D20b miss → DONE_candidate 상태 유지, 다음 cycle 에서 D20b 자동 trigger (rotation)

---

## Failure-class auto-classification (P3, orchestration view)

genai-apf-pipeline 가 result.json 받자마자 다음 evidence 로 failure_class 결정:

| failure_class | Detection evidence (result.json fields) | Default next_action |
|---------------|----------------------------------------|---------------------|
| `PROTOCOL_MISMATCH` | `engine_intercept_fired=True` + `warning_rendered=False` + envelope structure 비교 시 mismatch (e.g., wrong frame_type, missing field) | `debug_envelope:schema_revise` OR `apply_engine_fix:envelope_emit_fix` |
| `NOT_RENDERED` | `engine_intercept_fired=True` + `bytes_received>0` + `warning_rendered=False` + `fallback_error_present=True` (chrome dispatcher 거부) | `debug_envelope:har_capture` (re-baseline) OR `apply_engine_fix:render_layer_fix` |
| `SERVICE_CHANGED` | URL 변경 / endpoint 404 / handshake mismatch / response body 구조 변화 | `debug_envelope:har_capture` |
| `AUTH_REQUIRED` | `auth_state` non-authenticated AND endpoint requires login / login redirect 감지 | status mutate `NEEDS_LOGIN`, `defer:user_login_provisioning` |
| `INFRASTRUCTURE` | `test_infra_findings` 에 CDP timeout, focus-steal, ClientWebSocket cancel 등 test-PC issue | next_action keep, retry next session OR `infra_blocked:test_pc` |

> Failure-class 결정 근거는 result.json Tier-2 evidence 만 사용 (D9 안전 — event_arrival 의 evidence field 만, timer 무관).

---

## Mission-critical regression detection (P4, orchestration view)

genai-apf-pipeline 가 result.json 받은 직후 다음 trigger 평가:

```python
# Trigger 1: 3 consecutive same failure_class
if len(failure_history[svc]) >= 3 and \
   all(e.category == failure_history[svc][-1].category for e in failure_history[svc][-3:]):
    cause_pointer_revise_required = True
    escalation_mode = "M2" if envelope_iteration_class else "M3"

# Trigger 2: Previously-passing regression
if status == DONE and latest_result.overall_status == FAIL:
    failure_class = "MISSION_CRITICAL_REGRESSION_PERSISTS"
    priority_bump = True
    cycle_followup_entry = True

# Trigger 3: Mission evidence direct violation
if latest_result.real_llm_pii_text_present_in_dom == True and \
   latest_result.engine_intercept_fired == False:
    priority = 0  # urgent
    M3_trigger = True  # mission-critical, full discussion-review
```

**Effect** (T2 또는 P4 trigger):
- `cause_pointer` revise mandatory (existing diagnosis stale)
- `apf-operation/docs/cycle{N}-followup-tasks.md` 에 entry 추가
- M2 (envelope iteration) OR M3 (mission-critical) trigger

> **D9 안전**: 모든 trigger = event_arrival family (failure_history count, regression event, evidence field check). 시간/timer/elapsed 무관.

---

## Cross-skill 호출 경로 (Phase 6)

| 단계 | 호출 source | 호출 target | wrapper / runtime |
|------|------------|------------|-------------------|
| Source modify | apf-warning-impl | (Mac dev source) | direct edit |
| Build | apf-warning-impl | etap-build-deploy | `runtime/etap-build-deploy/etap-build-deploy.sh` |
| Deploy + reload | etap-build-deploy | test-PC | scp + ssh + etapcomm reload |
| Request emit | apf-warning-impl | cowork-remote | `runtime/cowork-remote/push-request.sh` |
| Result poll | cowork-remote | (loop) | `runtime/cowork-remote/scan-results.sh` |
| Result archive | cowork-remote | local_archive/{date}/ | `runtime/cowork-remote/archive-completed.sh` |
| Failure-class auto-classify | genai-apf-pipeline (本 file orchestration) | (internal) | result.json field inspection |
| State mutation | apf-warning-impl | apf-operation/state/pipeline_state.json | `runtime/apf-warning-impl/record-iteration.sh` (gated) |
| D20b verify | apf-warning-impl | cowork-remote verify-warning-quick | request push (28차 spec) |
| cause_pointer revise | genai-apf-pipeline (M2/M3) | discussion-review skill | `claude -p` 또는 manual |

---

## Cross-cycle hypothesis batch (P5 reference, 32차)

Phase 6 retry sub-loop 가 multi-service 동시 진행 시, 각 service iteration 의 결과는 cycle{N} 의 hypothesis matrix 에 누적. 예: cycle 97 = mistral v9 (a) + gemini3 Step A revert + huggingface re-login → 한 cycle 안의 가설 batch.

- cycle{N} 의 batch 단위 진행: 단일 service 의 P1-P4 가 cycle 안에서 여러 iteration 거침
- 가설 exhaustion tracking: 같은 cycle 내 가설 disprove 시 다음 cycle 으로 followup
- canonical reference: SKILL.md §Service Iteration Workflow > Pattern P5
- artifact: `apf-operation/docs/cycle{N}-record.md` (Hypothesis matrix section)

---

## 관련 references

- SKILL.md §Service Iteration Workflow — P1-P4 patterns canonical
- SKILL.md §Phase 6 Termination Conditions — T1-T5
- SKILL.md §Verdict Transition Matrix — overall_status × current state
- `apf-warning-impl/SKILL.md` — Phase 6 internal iteration canonical (engine source modify detail, generator naming, build verify protocol)
- `cowork-remote/SKILL.md` — request emit + scan + archive
- `etap-build-deploy/SKILL.md` — build + deploy + reload
- `apf-technical-limitations.md` — BLOCK_ONLY architectural cases (T5 trigger source)
- `services/{svc}_design.md` — Phase 5 output, Phase 6 input
- `apf-operation/services/{svc}_analysis.md` — cause_pointer canonical doc
