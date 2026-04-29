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

## 제외 기능

- ❌ Scheduled Task / cron / launchd / fireAt / Monitor persistent (Polling Policy v2)
- ❌ In-session bash loop (11차 제외, Polling Policy v2)
- ❌ 자동 STALLED escalation
- ❌ monolithic SKILL.md 의존 (본 skill 이 truth)
- ❌ 사용자에게 선택지 제시 + 지시 대기 패턴 (Hard Rule 6, 13차 추가)

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
- `references/phase3-block-verify.md`
- `references/phase4-frontend-inspect.md`
- `references/phase5-warning-design.md`
- `references/phase7-release-build.md`

## Related

- `cowork-remote`, `test-pc-worker`, `etap-build-deploy`, `apf-warning-impl` — 본 skill 이 wrapper 경유 호출.
- `research-gathering` : Phase 진입 전 "이 서비스에 대한 과거 설계 / 사용자 구두 결정" 을 수집. Phase 0 (정보 수집) 단계의 공식 도구. workflow-retrospective 의 Step 0.5 와 상호 보완.
