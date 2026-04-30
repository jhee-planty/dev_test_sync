---
name: genai-apf-pipeline
type: A
description: APF (ai_prompt_filter) pipeline 최상위 orchestrator. 7-phase lifecycle (HAR capture → analysis → block verify → frontend inspect → warning design → warning impl → release build) 을 서비스 하나에 대해 순차 수행. Use when user says "APF", "서비스 추가", "HAR", "capture", "차단", "block", "경고", "warning", "pipeline", "phase", "전체 현황", "다음 phase", "SQL", "C++", "registration", "{service} 처음부터". 결정론 runtime 이 pipeline_state.json + service_queue + status.md 관리 및 phase advance guard 를 담당. Claude 는 각 phase 내 분석·설계·verdict 담당. Phase 6 은 apf-warning-impl 위임, Phase 7 은 etap-build-deploy 위임. Cross-skill 호출 wrapper 는 runtime 이 제공. Hands-on C++ 디버깅은 apf-warning-impl.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Agent
---

# genai-apf-pipeline

## ★ APF Mission (canonical anchor, D20 26차)

**APF 의 본질 mission**: **모든 등록 AI 서비스에 대해 PII (민감 정보) 포함 프롬프트 입력 시 사용자 화면에 경고 문구 표시.**

> 사용자 원문 (2026-04-29): "이 세션의 목표는 APF 를 통해 프롬프트에 민감 정보 포함 시 사용자에게 경고 문구를 보여주는 것이 목표야"
> 사용자 원문 (2026-04-28): "APF 는 등록된 모든 AI 프롬프트를 검사할 수 있어야 해."

이 mission 이 본 skill 의 모든 sub-task (Phase 1-7) / mechanism (service_queue / next_action / status) / decision 의 **anchor**. 모든 means (lifecycle / phase / status transition / cycle cleanup) 는 본 mission 에 advance 해야 정당.

→ **Canonical**: `cowork-micro-skills/INTENTS.md §1.5 APF Project Mission` (D20 codify)
→ **Subordinate ref**: `apf-operation/docs/apf-technical-limitations.md` (D14b, 시도 catalog)

**최상위 orchestrator** — Phase 1-7 + policy enforcement + service queue 관리. 위 mission 의 operational implementation.

## 기본 인프라

| 항목 | 값 |
|------|-----|
| pipeline_state | `~/Documents/workspace/claude_work/projects/apf-operation/state/pipeline_state.json (fallback: ~/Documents/workspace/dev_test_sync/local_archive/pipeline_state.json)` (schema_version=1.0) |
| dashboard | `~/Documents/workspace/dev_test_sync/local_archive/pipeline_dashboard.md` (auto-regen) |
| status.md | `shared-skills/genai-apf-pipeline/services/status.md` (auto-regen, **직접 수정 금지**) |
| impl journal | `shared-skills/apf-warning-impl/services/{id}_impl.md` |
| design doc | `shared-skills/genai-apf-pipeline/services/{id}_design.md` |
| 등록 DB | etap MySQL @ `ogsvm` (see references/db-access-and-diagnosis.md) |

## Runtime 호출 규약

```bash
RT="$SKILL_DIR/runtime"
```

---

## 7 Phase (overview + decision point)

| # | Phase | Deterministic runtime 담당 | Claude decision |
|---|-------|-------------------------|----------------|
| 1 | har-capture | test PC 로 capture request push, scan, HAR 수신 | HAR 분석 (sub-agent dispatch), endpoint 식별 |
| 2 | analysis-registration | SQL draft 파일 생성, DB UPDATE 실행, reload_services, C++ hook 추가 | 분석 sub-agent 결과 리뷰, generator naming |
| 3 | block-verify | etap-build-deploy 호출, cowork-remote check-block 왕복 | 화면+로그 ground truth 판정, BLOCK_ONLY gate |
| 4 | frontend-inspect | cowork-remote 로 test PC 에서 DOM profile 수집 | delivery_method 결정 (http_api/websocket/sse/grpc) |
| 5 | warning-design | design sub-agent dispatch, design doc 초안 저장 | strategy A/B/C/D 선택, is_http2 값 결정 |
| 6 | warning-impl | **apf-warning-impl 위임** (iteration loop) | (apf-warning-impl 가 담당) |
| 7 | release-build | **etap-build-deploy 위임** | post-build verify 판정 |

각 phase 의 상세는 `references/phase{N}-*.md` 참조 (필요 시 on-demand load).

---

## Pipeline State (핵심 필드)

Schema canonical: `cowork-remote/references/pipeline-state-schema.md` (v2 enum + cause_pointer + terminal_reason + vocabulary v2 4 family + terminate:*).

핵심 필드 요약:
- `service_queue[]` — entry 마다 status (5-class enum) + next_action (vocabulary v2) + cause_pointer (BLOCKED_*) + terminal_reason (TERMINAL_UNREACHABLE)
- `done_services[]` — DONE 도달 service 목록
- `failure_history{}` — service 별 최근 실패 catalog (auto-classification 입력)
- `_next_action_vocabulary_v2` — 4 family verb 정의

상세 schema + entry 예시는 canonical doc 참조.

---

## Orchestration — Active = WSA v2

본 skill 의 active orchestration 은 **§Work Selection Algorithm v2** (아래 섹션 참조).

**Legacy V1 orchestration loop** (phase-based 순차 single-service) 은 archive 되어 있음. Rollback 필요 시: `references/legacy/v1-orchestration-loop.md` 참조.

V1 archive 의 trigger: 사용자 directive (2026-04-28 21차) — "V2 시도 + 문제 재발 시 롤백 가능". V1 archive 는 rollback path 보존 용이며 active operation 에서 따르지 않음 (context 낭비 방지).

---

## Cross-skill 호출 경로

| 호출 지점 | 대상 skill | runtime wrapper |
|----------|-----------|----------------|
| Phase 3, 4, 5 의 test PC 왕복 | cowork-remote | `runtime/cowork-remote/push-request.sh` 직접 호출 |
| Phase 3 빌드 | etap-build-deploy | `runtime/etap-build-deploy/etap-build-deploy.sh` 직접 호출 |
| Phase 6 전체 | apf-warning-impl | `runtime/apf-warning-impl/record-iteration.sh` + gate + Claude |
| Phase 7 전체 | etap-build-deploy | `runtime/etap-build-deploy/etap-build-deploy.sh` |

각 skill 의 runtime 은 독립 실행 가능. 본 skill 은 wrapper 호출만.

---

## Policy Enforcement (cross-cutting)

| policy | 판정자 | 동작 |
|--------|-------|------|
| 3-Strike auto-suspend | **폐기 (2026-04-28 21차)** | Claude 작업 정확도 부족 우려 — 자동 SUSPENDED 처리 X. 운영자가 cause_pointer 분석 후 결정. |
| BLOCK_ONLY gate (D14b) | Claude + per-service analysis doc | `apf-technical-limitations.md` 의 모든 listed 접근법 시도 + 결과 명시 + inapplicable 증명 후만 `terminate:block_only_accepted` 허용 |
| 총 빌드 상한 (apf-warning-impl 와 독립) | runtime `enforce-3strike.sh` | (vestigial — V1 path. V2 는 build count 추적 안 함) |
| 응답 대기 중 STALLED 자동 전환 | **없음** | 2026-04-21 정책 변경 — 결과 도착까지 반복 |

---

## Runtime scripts

| script | 역할 |
|--------|------|
| `common.sh` | pipeline_state 경로, schema_version, log, jq 의존 |
| `state-get.sh <field>` | pipeline_state.json 필드 조회 |
| `state-set.sh <field> <value>` | 필드 갱신 (auto updated_at) |
| `queue-next.sh` | service_queue 에서 다음 pending_check 반환 (priority asc) |
| `queue-advance.sh <service> <status>` | service status 전이 |
| `phase-advance.sh --check|--commit <N>` | phase guard / commit |
| `regen-status.sh` | status.md 재생성 (원본 스크립트 이식) |
| `enforce-3strike.sh <service>` | failure_history 3건 동일 → SUSPENDED `[OBSOLETE 2026-04-28 21차: 3-Strike auto-SUSPEND 폐기 — script vestigial. V1 rollback path 만 유지. references/legacy/v1-orchestration-loop.md 참조.]` |
| `enforce-block-only-gate.sh <service>` | BLOCK_ONLY 판정 가능 여부 |
| `invoke-subagent.sh <prompt-file> [--model=]` | Phase 1/2/5 의 sub-agent dispatch (Claude Code CLI) |

---

## 자율 수행 규칙 (MEMORY.md §11 + §13 준수)

- 질문으로 끝맺지 않음
- 결과 대기 중 STALLED 자동 전환 없음 (ScheduleWakeup chain 으로 scan 반복)
- Phase 전환 시 `references/phase{N}-*.md` 필수 Read
- Single-service focus 유지 (queue-next 결과 하나만)
- **선택지 제시 금지 (Hard Rule 6 v2)**: 복수 valid options → Mode Selection Tree:
  - **M0 Empirical Comparison (default)** — testable + revertible 이면 모두 테스트 + 비교 + winner (체크리스트 TodoWrite)
  - M1 reasoning (단순 binary) / M2 Micro-Discussion (untestable complex) / M3 full `discussion-review` (C9) / M4 user ask (물리적 예외만)
  - Per-case 기록: `apf-operation/state/decisions/`, all-fail 시 `empirical-fail-reports/`

→ See `references/autonomous-execution-protocol.md` for Hard Rules 1-7 v3 + Empirical Comparison Pattern + Micro-Discussion Pattern + Polling Policy v2 usage.

## Work Selection Algorithm v2 (2026-04-27 18차 + 2026-04-28 20차 consensus)

> Push-based decision making → Pull-based queue processing.
> Idle 가 자율 수행 의 자연 종료 신호가 아닌, **service_queue 가 autonomous-doable next_action 미보유** 시에만 허용되는 명시 상태.

### Loop (매 polling tick 또는 result 처리 후)

```
1. (Session start only) Run infra_unblock_check:smoke_test for any infra_blocked entries.
   If smoke test passes → re-classify infra_blocked → standard verbs.
2. Read pipeline_state.json service_queue
3. Filter entries where next_action does NOT start with 'defer:'
                                AND does NOT start with 'terminate:'
                                AND does NOT start with 'infra_blocked:'
                                AND status is NOT in {NEEDS_LOGIN, TERMINAL_UNREACHABLE, DONE}
   → autonomous_candidates list
4. If autonomous_candidates non-empty:
   - Sort by priority asc
   - Pop head
   - Pre-deploy check: if next_action starts with 'apply_engine_fix:' AND
     entry.unverified_deploys >= 3 → force entry.next_action = 'defer:awaiting_verification', loop
   - Execute next_action (한 step만)
   - On 'apply_engine_fix:*' deploy → entry.unverified_deploys += 1
   - On successful verify → entry.unverified_deploys = 0
   - Update entry next_action OR status as result dictates
   - Commit pipeline_state.json
   - Push request if next_action requires test PC, else return to loop
5. If autonomous_candidates empty (all defer: / terminate: / infra_blocked:):
   - Compose explicit "needs_user_input" status report
   - Report to user with itemized defer / terminate / infra_blocked reasons
   - Allow long-idle ScheduleWakeup
6. Empty queue (no entries at all):
   - Goal achieved OR user has not enqueued more services
   - Report to user
```

**Stop hook (D16(a), 22차 + 24차 D18(b) refinement)**: Claude 가 추가 tool 호출 없이 응답 종료 시도 시, `.claude/hooks/stop-autonomous-guard.sh` 가 자동 fire. autonomous_candidates count > 0 AND 사용자 마지막 메시지에 termination keyword 없음 → stop block + system-reminder emit. Cycle summary doc 작성 후 stop / premature completion / fatigue stop / M4 overgeneralization 모두 catch.

**Termination keyword list** (D18(b) refined — incident 8 root cause 였던 status-update keywords 제거):
- **Allow stop** (12): `stop` / `정지` / `종료` / `그만` / `그만해` / `wait` / `pause` / `잠시` / `잠깐` / `끝` / `halt` / `quit`
- **NOT termination** (D18(b)): `보고해` / `보고` / `summarize` / `검토` / `일단` — status-update request (사용자 보고 받고 다시 진행 의도). polling chain 유지.

### Idle Gate (Hard Rule 7 enforcement)

ScheduleWakeup ≥1200s OR 연속 ≥3 idle ticks (no Edit/Write/non-trivial Bash):
- **Mandatory work-selection re-run**
- Output: itemized list of service_queue with next_action + autonomous_doable count
- Long-idle 허용 = autonomous_doable count == 0 증명

## Service Status & Goal Accounting (2026-04-28 20차)

### Status enum (canonical schema: `cowork-remote/references/pipeline-state-schema.md`)

```
DONE | BLOCKED_diagnosed | BLOCKED_undiagnosed | NEEDS_LOGIN | TERMINAL_UNREACHABLE
```

**핵심 원칙 (D14 a/b/c)**:
- **(a) 디버깅 = 작업 출력** — `BLOCKED_undiagnosed → BLOCKED_diagnosed` transition 이 진전 (DONE 만 진전 아님).
- **(b) Architectural 한계 → engine extension / etap 기능 우회** — H3/QUIC 같은 한계는 force_h2 로 우회. 영구 EXCEPTION 금지.
- **(c) Service characterization = 모든 발견 통합** — `cause_pointer` 가 가리키는 single per-service analysis doc 에 envelope/content-type/decoder/transport/auth 모든 발견 통합. secondary 분리 금지.

### Goal accounting (single ratio)

```
Reachable progress = DONE / (TOTAL - TERMINAL_UNREACHABLE)
```

EXCEPTION subtraction 없음. H3 services 는 reachable (force_h2 적용 후 정상 inspect path).

### next_action Vocabulary v2 (4 families)

`apf-operation/state/pipeline_state.json` 의 `_next_action_vocabulary_v2` 필드 참조.

```
debug_envelope:*    — har_capture | envelope_diff | etap_log_diagnose | content_type_probe
                    | schema_revise | server_log_inspect (/var/log/ai_prompt/ 분석)

debug_decoder:*     — wrb_fr_layer | ws_body_layer | h2_streaming_body

debug_http_layer:*  — transport_probe | force_h2 (etap visible_tls._block_quic
                                                  / DPDK-level QUIC drop)

apply_engine_fix:*  — wrb_fr_decoder | ws_body_inspector | (other engine work)
                      [unverified_deploys ≥ 3 → defer:awaiting_verification 강제]

defer:*             — *_user_har / user_login_provisioning / vpn_or_region_change /
                      awaiting_verification / ...

terminate:*         — block_only_accepted (architectural BLOCK_ONLY, all approaches in
                      apf-technical-limitations.md tried/rejected per cause_pointer doc)
                    | user_decommissioned | replaced_by:{service}

infra_blocked:*     — test_pc (windows-mcp Snapshot/Chrome focus/CDP) | (extensible)
                      [WSA filter excludes; infra_unblock_check:* re-classifies on recovery]

infra_unblock_check:* — smoke_test (session start probe; on success → infra_blocked re-classify)
```

새 verb 도입 시 vocabulary v2 에 정의 추가. v1 verbs 는 `[deprecated]` 표기.
→ **Canonical** (Polling Policy authoritative source): `~/.claude/memory/user-preferences.md` Polling Policy section. INV-6 Rule-of-3 준수.

## Service Iteration Workflow (31차 normalized — empirical)

> **출처**: 31차 discussion-review (`cowork-micro-skills/discussions/2026-04-30_apf-pipeline-workflow-normalization.md`) — 422 archived result.json (343 successfully parsed, 79 parse errors) + service iteration history (mistral 36 reqs / gamma 29 / gemini3 13 / deepseek 12) mining 결과.
> **32차 amendment**: P5 Mission Lifecycle Pattern 추가 (cycle concept narrow codify) — `cowork-micro-skills/discussions/2026-04-30_cycle-concept-appropriateness.md`.
> **Canonical scope**: 본 섹션 = orchestration view. Phase 6 internal iteration detail = `apf-warning-impl/SKILL.md` + `references/phase6-warning-impl-orchestration.md`.

### Pattern P1 — Service Iteration Macro-cycle

한 서비스의 NEW → DONE/BLOCKED/TERMINAL 까지 reproducible flow:

```
NEW (DB UPDATE + reload_services)
 → Phase 1 har-capture       (run-scenario request, HAR endpoint 식별)
 → Phase 2 analysis-registration  (sub-agent dispatch on HAR + DB envelope_template UPDATE + C++ hook)
 → Phase 3 block-verify      (check-block: etap log [APF:block_response] + UI screenshot, BLOCK_ONLY gate)
 → Phase 4 frontend-inspect  (DOM profile via run-scenario or check-warning, delivery_method 결정)
 → Phase 5 warning-design    (design sub-agent, strategy A/B/C/D/E + is_http2 결정)
 → Phase 6 warning-impl       (apf-warning-impl 위임, retry sub-loop — Pattern P2 참조)
 → Phase 7 release-build     (etap-build-deploy 위임, 모든 비-deferred service DONE 후)
```

각 Phase 의 decision checklist (3 items per phase × 7 phases = 21 decision points) → `references/phase{N}-*.md` (Phase 6 = `phase6-warning-impl-orchestration.md`).

### Pattern P2 — Phase 6 Retry Sub-loop (most-frequent activity)

Phase 6 = current active iteration 의 대다수 (mistral 36회, gamma 29회, gemini3 13회).

```
loop until termination (T1-T5):
  next_action = apply_engine_fix:* | debug_envelope:* | debug_decoder:* | debug_http_layer:*
   ↓
  engine source modify (Mac dev) → ninja build → deploy to test-PC → reload_services
   ↓
  cowork-remote push-request (check-warning)
   ↓
  test-PC subagent: navigate URL → inject prompt → capture DOM/network/console → emit result.json
   ↓
  cowork-remote scan-results → archive → verdict
   ↓
  IF SUCCESS:        status → DONE_candidate, then D20b verify-warning-quick rotation → DONE
  ELIF FAIL/PARTIAL: failure_history.append + auto-classify failure_class → next_action mutate (P3)
  ELIF 3 consecutive same failure_class: cause_pointer revise (M2/M3) — see P4
  ELIF AUTH/INFRA:   T3/T4 termination — see termination conditions
   ↓
  pipeline_state.json commit + (if test-PC required) push request
   ↓
  loop
```

`unverified_deploys` counter (per-service) +1 per `apply_engine_fix:*` deploy without verify, reset on SUCCESS verify. ≥3 → forced `defer:awaiting_verification` (already enforced in WSA v2 step 4).

### Pattern P3 — Failure-class → next_action Default Mapping

`failure_history[service]` entry 의 `category` enum 별 default `next_action`:

| failure_class | Default next_action (1st-2nd) | After 3 consecutive same |
|---------------|------------------------------|--------------------------|
| `PROTOCOL_MISMATCH` (envelope structure mismatch) | `debug_envelope:schema_revise` OR `apply_engine_fix:envelope_emit_fix` | M2 cause revise: alternative envelope schema OR `defer:user_har` |
| `NOT_RENDERED` (warning element absent despite engine fire) | `debug_envelope:har_capture` (re-baseline) OR `apply_engine_fix:render_layer_fix` | M3: render dispatcher refactor OR `defer:user_har_for_native_envelope` |
| `SERVICE_CHANGED` (URL/endpoint/handshake changed) | `debug_envelope:har_capture` | `defer:user_har` (architectural shift) |
| `AUTH_REQUIRED` (login wall) | status mutate to `NEEDS_LOGIN`, `defer:user_login_provisioning` | (terminal until user input) |
| `INFRASTRUCTURE` (test-PC issue: CDP timeout, focus-steal, etc.) | next_action keep, retry next session | `infra_blocked:test_pc` |

Override mechanism: `service_queue[].failure_threshold` (optional, default=3). Service-specific via `cause_pointer` analysis doc (e.g., mistral envelope iteration = expected multi-iteration, threshold higher).

### Pattern P4 — Mission-critical Regression Detection

**Trigger** (event_arrival family — D9-safe):
1. **3 consecutive same failure_class**: `failure_history[service][-3:]` 모두 동일 category → cause_pointer stale 판정, M2/M3 revise.
2. **Previously-passing regression**: 직전 iteration 이 SUCCESS 였으나 latest 가 FAIL → `failure_class = "MISSION_CRITICAL_REGRESSION_PERSISTS"` (gemini3 #652 사례 reference).
3. **Mission-relevant evidence**: `result.real_llm_pii_text_present_in_dom == True` AND `engine_intercept_fired == False` → mission goal direct violation, urgent priority bump.

**Effect**:
- `cause_pointer` revise mandatory (existing diagnosis stale)
- `apf-operation/docs/cycle{N}-followup-tasks.md` 에 entry 추가
- M3 discussion-review trigger (mission-critical) OR M2 micro-discussion (envelope iteration)

> **D9 안전성**: 본 P4 의 모든 trigger 는 event_arrival (3-event count, regression event detection, evidence field check). 시간/timer/elapsed 기반 termination 일체 없음. 29차 D9 amendment + Termination Conditions canonical 준수.

### Verdict Transition Matrix (orchestration view)

`result.overall_status` × `current state` → `(new state, next_action, trigger family)`:

| overall_status | current state | new state | next_action | trigger family |
|----------------|--------------|-----------|-------------|---------------|
| SUCCESS | AWAITING_RESULT | DONE_candidate | `verify_user_visible_warning_rendered` (D20b) | event_arrival |
| SUCCESS (D20b PASS) | DONE_candidate | DONE | (queue done_services) | event_arrival |
| FAIL (1st) | AWAITING_RESULT | BLOCKED_diagnosed | failure_history.append + auto-classify; debug_*:* OR apply_engine_fix:* | event_arrival |
| FAIL (2nd same class) | BLOCKED_diagnosed | BLOCKED_diagnosed | cause_pointer revise hint; alternative debug verb (P3 다른 default) | event_arrival |
| FAIL (3rd same class) | BLOCKED_diagnosed | BLOCKED_undiagnosed | M2/M3 cause_pointer revise (P4 trigger) | event_arrival (count=3) |
| PARTIAL | AWAITING_RESULT | BLOCKED_diagnosed | retry with parent_request_id; envelope rev | event_arrival |
| BLOCKED (auth) | AWAITING_RESULT | NEEDS_LOGIN | `defer:user_login_provisioning` | event_arrival |
| BLOCKED (infra) | AWAITING_RESULT | BLOCKED_diagnosed (keep) | `infra_blocked:test_pc`; `infra_unblock_check:smoke_test` next session | event_arrival |
| TERMINAL | any | TERMINAL_UNREACHABLE | terminal_reason set | explicit_user_action / M3 |
| (regression detected, P4) | DONE | BLOCKED_diagnosed | cause_pointer revise + cycle{N}-followup entry | event_arrival |

> Trigger family canonical: `cowork-remote/references/pipeline-state-schema.md` + 29차 D9 amendment.

### Phase 6 Termination Conditions (T1-T5, D9-safe)

Phase 6 retry sub-loop 의 termination condition. **All triggers = event_arrival / explicit_user_action / infra_signal family** (D9 forbidden = 시간/timer/elapsed-based).

| ID | Condition | Effect | Trigger family |
|----|-----------|--------|---------------|
| **T1** | result.overall_status=SUCCESS + warning_rendered=true + envelope match + no fallback error + D20b PASS | status → DONE | event_arrival |
| **T2** | failure_history latest 3 entries 동일 category | status → BLOCKED_undiagnosed; M2/M3 cause revise | event_arrival (count=3) |
| **T3** | failure_class=AUTH_REQUIRED OR explicit_user_action (need HAR) | next_action prefix `defer:*`; status maintain | explicit_user_action |
| **T4** | infra_signal = test-PC unreachable OR CDP timeout | next_action = `infra_blocked:test_pc`; resume next session via `infra_unblock_check:smoke_test` | infra_signal |
| **T5** | explicit_user_action OR M3 architectural decision (e.g., BLOCK_ONLY accepted) | status → TERMINAL_UNREACHABLE; terminal_reason set | explicit_user_action / M3 |

**FORBIDDEN (D9 anti-pattern)**:
- 시간 elapsed → 종료 (예: "iteration 30분 초과 → defer")
- timeout 추정 → state 변경
- expected_result_at + N → escalate

본 Phase 6 의 모든 retry chain 은 result_received OR user_directive OR infra_signal 만으로 advance/terminate.

### Phase Decision Checklist (21 items)

각 Phase 의 진입 → execution → 완료 결정점. 자세한 sub-action 은 references/{phase}-*.md.

| Phase | D{N}.1 | D{N}.2 | D{N}.3 |
|-------|--------|--------|--------|
| 1 har-capture | HAR scope 결정 (single-prompt / multi-thread / login flow) | HAR validity (status 200 + body + endpoint) | Phase 2 진입 = envelope structure 확인 |
| 2 analysis-registration | SQL draft naming `apf_db_driven_{service}_{ts}.sql` | Generator naming canonical (synonym 금지) | reload_templates vs reload_services 구분 |
| 3 block-verify | Block evidence = test-PC UI + etap log 둘 다 | BLOCK_ONLY gate (architectural) | 200 OK + bytes + RST_STREAM = engine fire 확정 |
| 4 frontend-inspect | delivery_method enum (http_api/websocket/sse/grpc/webtransport) | streaming-vs-block + is_http2 frame_type | Native vs custom envelope (services/{svc}_analysis.md) |
| 5 warning-design | Strategy A/B/C/D/E 선택 | is_http2=0/1/2 결정 | sub-agent dispatch design doc (sonnet) |
| 6 warning-impl (orchestration view) | Engine fix verb 선택 (apply_engine_fix:* / debug_*:*) | Build verify (ninja + symbol) | D20b verify rotation entry on first SUCCESS |
| 7 release-build | 모든 비-deferred service DONE | Tag canonical `cycle{N}-{milestone}-{date}` | Verified-state commit + smoke test PASS |

상세: `references/phase{N}-*.md` (Phase 6 = `phase6-warning-impl-orchestration.md`).

### Pattern P5 — Mission Lifecycle Pattern (32차 추가)

> Service-level (P1-P4) 보완 — mission-level unit (cycle) 의 적정 사용 form.
> 출처: 32차 discussion `cowork-micro-skills/discussions/2026-04-30_cycle-concept-appropriateness.md`.

#### Cycle 정의

`cycle{N}` = numbered hypothesis batch. session 보다 길고 mission 보다 짧은 mid-level work-batch unit. multi-service hypothesis matrix tracking 의 unique value 단위.

#### 4 Purposes 차등 채택 (empirical evidence-based)

| Purpose | 채택 form |
|---------|----------|
| #1 Cross-session continuity | `session-snapshot-{date}.md` 보조 + `cycle{N}-record.md` 의 Open/Closing section |
| #2 Hypothesis lifecycle | `cycle{N}-record.md` Hypothesis matrix section + INTENTS §5 citation |
| #3 Forced bookkeeping | `cycle{N}-record.md` write 의무 (single doc, summary/followup separate 의무 폐지) |
| #4 Decision provenance | decisions standalone (ts+subject) + `cycle_id` field optional |

#### Cycle Lifecycle States

| State | Trigger | Artifact |
|-------|--------|----------|
| **Active mission** (현재) | mission completion_ratio < 1.0 | `apf-operation/docs/cycle{N}-record.md` (live + final archive) |
| **Late / Maintenance** | completion_ratio = 1.0 + 30-day D20b PASS 누적 | `quarterly{Q}-d20b-record.md` 전환 |
| **Terminal** | mission closure (사용자 explicit) | all docs archive, 새 cycle 생성 X |

#### cycle{N}-record.md template

→ `apf-operation/docs/cycle{N}-record-TEMPLATE.md` (5 sections: Open / Hypothesis matrix / Decisions log / Followup / Closing)

#### Bookkeeping discipline

- **의무**: `cycle{N}-record.md` 1 doc per cycle
- **Optional**: separate summary doc / separate followup doc / Git tag / decisions `cycle_id` field
- **폐지**: summary AND followup 동시 작성 의무 — empirical 0 cycles 충족, practice 가 either-or → 의무 해제

#### Provenance 통합

- decisions/ 의 ts+subject = standalone provenance (cycle 미인용 valid)
- cycle 인용 시 cycle_id field 사용 (optional)
- INTENTS §5 의 `{N}차 / cycle {M}` cross-citation = governance narrative

---

## Out-of-scope (대신 사용할 패턴)

| 영역 | 본 skill 외부 | 대신 사용 |
|------|-------------|----------|
| Polling | OS-level scheduler / bash loop / cron | `ScheduleWakeup(delaySeconds, prompt, reason)` (session-internal) — Polling Policy v2 |
| 응답 대기 | 자동 STALLED escalation | 결과 도착까지 scan 반복 (cowork-remote `scan-results.sh`) |
| Truth source | monolithic SKILL.md 추정 | 본 skill 이 truth — references 는 on-demand |
| 복수 옵션 | 사용자에게 선택지 제시 | Mode Selection Tree (M0 Empirical → M1 reasoning → M2 Micro-Discussion → M3 full review → M4 user ask) |

## Service Journals (operational artifact)

본 skill 의 아래 하위 디렉터리는 **APF pipeline 실행 중 생성되는 per-service artifact** (Dev PC writes, Test PC ignores):

| 디렉터리 | 성격 | Test PC 영향 |
|---------|------|---------|
| `services/*_design.md` | per-service 설계 문서 (warning strategy, is_http2 등) | 무시됨 |
| `services/*_frontend.md` | per-service frontend 분석 결과 | 무시됨 |
| `services/status.md` | 자동 생성 (regen-status 결과) | 무시됨 |
| `evals/` | Dev 측 skill 평가 결과 | 무시됨 |

**Current location**: 본 skill bundle 내.
**Planned migration**: 위 journal 들은 APF pipeline **operational artifact** 이므로, 장기적으로 `~/Documents/workspace/claude_work/projects/apf-operation/service-journals/{service}/{impl,design,frontend}.md` 로 이전 예정 (별도 project: `apf-operation/proposals/services-migration-*.md` 참조).

이전을 지금 수행하지 않는 이유:
1. in-flight pipeline (active service) 실행 중 이동 시 journal append 충돌 위험
2. runtime common.sh 의 `STATUS_MD` 등 env var atomic 변경 별도 설계 필요 (symlink bridge 등)

---

## References (on-demand)

- `references/phase1-har-capture.md`
- `references/phase2-analysis-registration.md`
- `references/phase2-apf-analysis.md` (sub-agent prompt)
- `references/phase3-block-verify.md`
- `references/phase4-frontend-inspect.md`
- `references/phase5-warning-design.md`
- `references/phase6-warning-impl-orchestration.md` (31차 신설 — genai-apf-pipeline orchestration view of Phase 6, apf-warning-impl 위임 boundary)
- `references/phase7-release-build.md`

## Related

- `cowork-remote`, `test-pc-worker`, `etap-build-deploy`, `apf-warning-impl` — 본 skill 이 wrapper 경유 호출.
- `research-gathering` : Phase 진입 전 "이 서비스에 대한 과거 설계 / 사용자 구두 결정" 을 수집. Phase 0 (정보 수집) 단계의 공식 도구. workflow-retrospective 의 Step 0.5 와 상호 보완.
