# pipeline_state.json — Full Schema Reference

> Extracted from cowork-remote SKILL.md (2026-04-07)
> 인라인에는 핵심 필드만 유지. 전체 스키마는 이 문서를 참조한다.

## 전체 스키마

```json
{
  "current_service": "{service_id}",
  "current_phase": "waiting_result",
  "last_request_id": 17,
  "last_checked_result_id": 16,
  "last_delivered_id": 16,
  "last_poll_at": "2026-03-26T14:30:00",
  "consecutive_empty_polls": 3,
  "poll_stage": 1,
  "poll_stage_count": 1,
  "updated_at": "2026-03-26T14:30:05",
  "service_queue": [
    {"service": "{service_id}", "priority": 1, "status": "BLOCKED_diagnosed",
     "next_action": "apply_engine_fix:wrb_fr_decoder",
     "cause_pointer": "apf-operation/services/{service_id}_analysis.md",
     "terminal_reason": null, "unverified_deploys": 0, "task_id": 194},
    {"service": "{service_id}", "priority": 2, "status": "BLOCKED_undiagnosed",
     "next_action": "debug_envelope:har_capture",
     "cause_pointer": null, "terminal_reason": null, "task_id": null}
  ],
  "done_services": ["{service_id}", "{service_id}"],
  "failure_history": {
    "service_id": [
      {"category": "PROTOCOL_MISMATCH", "result_status": "error_6002", "request_id": 317, "build": "B25"},
      {"category": "PROTOCOL_MISMATCH", "result_status": "http_429", "request_id": 318, "build": "B25"}
    ]
  },
  "monitoring": {
    "visual_needed": false,
    "visual_trigger": "30min_no_result",
    "_visual_trigger_intent": "L3 (visual diagnosis) escalation 의 trigger field. **Non-applicability (29차 D9 Stage 3 catch)**: polling chain termination trigger 아님. visual_trigger fire 되어도 ScheduleWakeup chain 은 termination 2 조건 (결과 / session) 도달까지 유지. canonical: autonomous-execution-protocol.md §Termination Conditions.",
    "last_visual_check": null,
    "last_visual_result": null
  },
  "work_context": {
    "strategy": "D_END_STREAM",
    "last_build": "2026-04-01T14:30:00",
    "last_iteration": 3,
    "last_action": "modified generate_gemini_block_response",
    "next_step": "build and deploy to test server"
  },
  "notes": "free-form text"
}
```

## 필드 설명

**중요:** State를 갱신할 때 기존 필드(service_queue, done_services, failure_history 등)를
누락하지 않는다. 읽은 JSON을 기반으로 필요한 필드만 수정하고 전체를 다시 쓴다.

> **Note (2026-04-22 policy α)**: `stall_count`, `poll_stage`, `poll_stage_count` 필드는
> canonical state.json schema 에 잔존하지만 **skill 은 사용하지 않는다**.
> "결과 도착까지 반복 scan" 모델로 변경됨 (사용자 의도 1 "수행 중인 작업을 유지"). 
> hook 의 stall_count monitor 는 historical artifact 로 유지 (state 값 상시 0 이므로 경고 미발동).

### failure_history (실패 패턴 추적 — §BEHAVIORAL RULES Auto-SUSPEND)

서비스별 최근 실패 이력. 각 항목은 `{category, result_status, request_id, build}`.
최근 3건이 동일 category이면 Auto-SUSPEND 트리거.
새 빌드 배포 시 해당 서비스의 failure_history를 리셋한다.

**category enum:**
`PROTOCOL_MISMATCH` | `NOT_RENDERED` | `SERVICE_CHANGED` | `AUTH_REQUIRED` | `INFRASTRUCTURE`

### work_context (컨텍스트 유실 대비)

compact나 세션 재시작으로 대화 컨텍스트가 소실되어도, 이 필드에서 "마지막으로 뭘 했고
다음에 뭘 해야 하는지" 복구할 수 있다. Phase 3 iteration 시작/완료 시 갱신한다.

### service_queue status 값 (2026-04-28 v2 — 20차 discussion-review consensus)

| status | 의미 | next_action 패밀리 |
|--------|------|-------------------|
| `DONE` | 완료 (사용자 화면에 경고 visible + envelope match). done_services 로 이동 | — |
| `BLOCKED_diagnosed` | 진단 완료, fix path 정의됨. `cause_pointer` 필수 (per-service analysis doc 경로) | `apply_engine_fix:*` / `debug_envelope:schema_revise` / `debug_http_layer:force_h2` |
| `BLOCKED_undiagnosed` | 진단 미완. 디버깅 verbs 큐잉 | `debug_envelope:*` / `debug_decoder:*` / `debug_http_layer:transport_probe` |
| `NEEDS_LOGIN` | 로그인/인증 필요 (M4 user-required). 자율 진행 불가 | `defer:user_login_provisioning` |
| `TERMINAL_UNREACHABLE` | 영구 도달 불가. `terminal_reason` 필수 ("possible reachable" 에서 제외) | — |

> **`terminate:*` next_action family** (2026-04-28 21차 추가) — 자율 loop 관점 terminal 상태. Service profile (cause_pointer) 가 full evidence 보유. 사례:
> - `terminate:block_only_accepted` (BLOCK_ONLY architectural — apf-technical-limitations.md 모든 시도 후)
> - `terminate:user_decommissioned` (사용자 명시 제거)
> - `terminate:replaced_by:{service}` (다른 서비스로 대체)
>
> 위 case 들의 status 는 `BLOCKED_diagnosed` 유지 (enum 5-class). `terminate:*` 가 작업 의지 표현, status 가 이해 표현. Goal accounting display 시 terminate:* 별도 카운트 (DONE 아님, reachable 미차감).

> **`infra_blocked:*` + `infra_unblock_check:*` families** (2026-04-29 22차 추가) — task-level 인프라 의존성. session-level stop 와 분리.
> - `infra_blocked:test_pc` — Test PC 인프라 (desktop-commander / Windows MCP — Snapshot / Chrome focus / CDP) 미가용. 인프라 복구까지 대기.
> - `infra_unblock_check:smoke_test` — session 시작 시 infra 복구 probe. 성공 시 infra_blocked entries 재분류.
>
> WSA v2 filter (full): `not startswith('defer:') AND not startswith('terminate:') AND not startswith('infra_blocked:')`. infra_unblock_check:* 는 session 시작 시 자동 실행 후 일반 verb 로 전환.

> **`unverified_deploys` counter field** (2026-04-29 22차 추가, per-service entry) — `apply_engine_fix:*` deploy 가 verify 없이 누적된 횟수. 매 deploy 시 +1, 성공적 verify 시 reset to 0. **≥3 도달 시** 자동으로 `defer:awaiting_verification` 으로 전환. D14(a) 호환 — `debug_*:*` 작업은 counter 영향 없음 (debug = output 인정).

> **`_decision_source` field** (2026-04-29 25차 D19(a) 추가, per-service entry, optional but recommended) — `next_action` mutation 시 decision provenance 동반. Goal Drift / Work Fabrication 차단 (D19). Format:
> - `M0:apf-operation/state/decisions/{ts}_M0_{slug}.json` (Empirical Comparison result)
> - `M1:internal_reasoning_summary` (15s reasoning, 짧은 rationale 동반)
> - `M2:apf-operation/state/decisions/{ts}_M2_{slug}.json` (Micro-Discussion result)
> - `M3:cowork-micro-skills/INTENTS.md§{N}차` (full discussion-review)
> - `M4:user_directive_pointer` (사용자 명시 지시)
> - `phase_transition:phase{N}_to_phase{M}` (자동 phase advance)
>
> Source 없는 next_action mutation = fabrication risk. Layer C of D19 3-tier defense (Layer A = Self-Check Category I priming, Layer B = watchdog provenance trail audit).

`terminal_reason` enum (TERMINAL_UNREACHABLE 시):
- `service_dead` (서비스 종료 / 호스트 deadkey)
- `region_blocked_KR` (한국 region 접근 불가)
- `decommissioned_replaced_by:{name}` (다른 서비스로 대체됨)
- `mobile_only_no_web_endpoint` (web 엔드포인트 부재)
- `out_of_scope_explicit` (사용자 명시 제외)

**필드 schema (status entry)**:
```json
{
  "service": "{service_id}",
  "priority": 5,
  "status": "BLOCKED_diagnosed",
  "next_action": "debug_http_layer:force_h2",
  "cause_pointer": "apf-operation/services/{service_id}_analysis.md",
  "terminal_reason": null,
  "task_id": null
}
```

> **Out-of-scope D14 (a/b/c) 원칙** (INTENTS §5 2026-04-28 20차):
> (a) 디버깅 활동 = 작업 출력. status transition (undiagnosed → diagnosed) 가 진전.
> (b) Architectural 한계 → engine extension / etap 기능 우회 (영구 EXCEPTION 금지).
> (c) Service characterization = 모든 발견 통합 (secondary 분리 금지).
> 본 enum 이 (a)(b) 를 schema 에서 강제. (c) 는 cause_pointer 가 가리키는 single doc 으로 강제.

**Goal accounting**: `DONE / (TOTAL - TERMINAL_UNREACHABLE)`. Single ratio. EXCEPTION 미사용.

> 과거 9-status enum (`pending_check`, `waiting_result`, `test_fail`, `needs_manual_action`, `strike_3_review`, `warning_shown_artifact_issue`, `excluded`, `suspended`, `done`) 은 2026-04-28 v2 로 위 5-enum 에 통합됨. `done` → `DONE`. 나머지는 BLOCKED_* / NEEDS_LOGIN / TERMINAL_UNREACHABLE 로 매핑. `pending_check` / `waiting_result` 는 request lifecycle (pending_requests 필드) 로 분리됨.

> `stalled` status 는 2026-04-22 policy α 로 제거됨 (skill 이 "결과 도착까지 반복" 로 대체).
