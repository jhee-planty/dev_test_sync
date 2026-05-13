---
name: genai-apf-pipeline
type: A
execution_context: main_or_subagent
description: APF (ai_prompt_filter) pipeline 최상위 thin orchestrator. M6 (2026-05-11) sub-agent-first architecture — main agent 는 mission anchor + service_queue 진행 유지 + sub-agent verdict 판정 만 담당. Phase 1-7 실작업은 모두 invoke-subagent.sh 경유 sub-agent (claude-opus-4-7) dispatch. apf-warning-impl 의 iteration logic 은 Phase 6 sub-agent 가 흡수. Use when user says "APF", "서비스 추가", "HAR", "capture", "차단", "block", "경고", "warning", "pipeline", "phase", "전체 현황", "다음 phase", "SQL", "C++", "registration", "{service} 처음부터". 결정론 runtime 이 pipeline_state.json + service_queue + status.md 관리. Cross-skill 호출 (cowork-remote / etap-build-deploy) 도 sub-agent prompt 안에서 발생.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Agent
---

<!-- execution_context: main_or_subagent — M6 thin orchestrator 는 main 운영, Phase 1-7 실작업은 sub-agent dispatch. Agent 권한 보유 (sub-agent spawn). D32.b reference. -->


# genai-apf-pipeline (M6 thin orchestrator)

## ★ APF Mission (canonical anchor, immutable)

**모든 등록 AI 서비스에 대해 PII (민감 정보) 포함 프롬프트 입력 시 사용자 화면에 경고 문구 표시.**

> 사용자 원문 (2026-04-29): "이 세션의 목표는 APF 를 통해 프롬프트에 민감 정보 포함 시 사용자에게 경고 문구를 보여주는 것이 목표야"
> 사용자 원문 (2026-04-28): "APF 는 등록된 모든 AI 프롬프트를 검사할 수 있어야 해."

본 mission 이 모든 sub-task / mechanism / decision 의 anchor. 모든 means 는
mission 에 advance 해야 정당.

→ Canonical: `cowork-micro-skills/INTENTS.md §1.5 APF Project Mission`

## M6 Architecture (2026-05-11)

**Main = thin (mission anchor + queue + verdict) / Sub-agent = thick (phase 실작업, context isolation)**.

→ 상세 (Why / 책임 분할 / DoD): `cowork-micro-skills/master-plan.md §5.2`

## 기본 인프라

| 항목 | 값 |
|------|-----|
| pipeline_state | `~/Documents/workspace/claude_work/projects/apf-operation/state/pipeline_state.json` (schema_version=1.0) |
| dashboard | `~/Documents/workspace/dev_test_sync/local_archive/pipeline_dashboard.md` |
| status.md | `services/status.md` (auto-regen, **직접 수정 금지**) |
| service journals | `services/{service_id}_{design,frontend,impl}.md` (sub-agent 가 갱신) |
| 등록 DB | etap MySQL @ ogsvm |
| artifact_type_registry | `apf-operation/state/artifact_type_registry.json` (T1/T2/T3, 51차 G1) |

## 7 Phase × Sub-agent Dispatch

| # | Phase | Sub-agent prompt | 권한 | last_artifact type |
|---|-------|-----------------|------|-------------------|
| 1 | har-capture | `references/phase1-har-capture.md` | Bash, Read | T1_engine_fire |
| 2 | analysis-registration | `references/phase2-analysis-registration.md` | Bash, Read, Edit | T1_engine_fire |
| 3 | block-verify | `references/phase3-block-verify.md` | Bash, Read, Write, Edit | T1_engine_fire |
| 4 | frontend-inspect | `references/phase4-frontend-inspect.md` | Bash, Read, Write | T2_UI_render |
| 5 | warning-design | `references/phase5-warning-design.md` | Read, Write | T2_UI_render |
| 6 | warning-impl | `references/phase6-warning-impl.md` | Bash, Read, Write, Edit | T3_verify_path_established |
| 7 | release-build | `references/phase7-release-build.md` | Bash, Read, Write, Edit | T3_verify_path_established |

**모든 phase 가 동일 sub-agent invocation 패턴**:

```bash
SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"
RT="$SKILL_DIR/runtime"

bash "$RT/invoke-subagent.sh" \
  --prompt /tmp/phase{N}-{service}-prompt.txt \
  --model claude-opus-4-7 \
  --allowed-tools "Bash,Read,Write,Edit,Grep,Glob" \
  --add-dir <skills> --add-dir <etap_root> --add-dir <sync_dir> \
  --output /tmp/phase{N}-{service}-result.log
```

Prompt 작성은 `references/phase{N}-*.md` 의 "Sub Agent Invocation" 섹션 참조.

## Main Agent Orchestration Loop

```
1. (Session start) Read INTENTS.md §1.5 + handoff.md §0 + 본 SKILL.md
   - mission anchor 확인
   - pipeline_state.json 의 service_queue 상태 확인

2. WSA v3 (autonomous-execution-protocol.md):
   - service_queue 에서 autonomous-doable next_action 후보 추출
   - filter: NOT defer:*, NOT terminate:*, NOT infra_blocked:*, status NOT IN {NEEDS_LOGIN, TERMINAL_UNREACHABLE, DONE}
   - sort by priority asc → pop head

3. Phase identification:
   - service entry 의 current phase 또는 next_action 으로 결정 → phase{N}

4. Sub-agent prompt 생성:
   - references/phase{N}-*.md 의 prompt template 에 placeholder 치환
   - state pointer (pipeline_state.json + relevant artifacts) 명시
   - mission anchor 명시

5. Sub-agent dispatch:
   - bash runtime/invoke-subagent.sh --prompt ... --model claude-opus-4-7 ...
   - return: sub-agent result.log path

6. Long-idle ScheduleWakeup (sub-agent 결과 대기):
   - delaySeconds: 1200-1800 (cache-miss tolerant, sub-agent 5-30 min runtime 예상)
   - prompt: "[SKILL-RECALL] guidelines.md §11/§13 + APF mission ... continue M6 phase{N} polling for service {service}"

7. Wakeup → result 확인:
   - cat /tmp/phase{N}-{service}-result.log
   - parse: VERDICT / NEXT_ACTION / LAST_ARTIFACT / CAUSE_POINTER

8. Verdict 판정 (Cowork Review Quality Gate, 각 phase 의 reference 참조):
   - PASS → state-set next_action, last_artifact → 다음 phase advance
   - RETRY → 같은 phase 재dispatch (prompt 에 review feedback append)
   - ESCALATE → defer + user report

9. pipeline_state.json 갱신:
   - bash runtime/state-set.sh service_queue[{idx}].next_action ...
   - bash runtime/state-set.sh service_queue[{idx}].last_artifact ...
   - regen-status.sh

10. Loop to step 2 (mission ratio < 1.0 시).
    Stop autonomously when: mission ratio = 1.0 OR user explicit halt keyword.
```

**Stop license** (stop-autonomous-guard.sh 41차 + 51차 G2):
- mission ratio = 1.0 (DONE / (TOTAL - TERMINAL_UNREACHABLE)) → allow stop
- artifact-bounded license: 새 last_artifact 발생 시 stop allow (다음 session 재진입)
- termination keyword: stop/정지/종료/그만/wait/pause/잠시/잠깐/끝/halt/quit
- **sub-agent in-flight 상태에서 stop 시도**: hook 가 allow (sub-agent 결과 도착 시 자동 재진입)

## Runtime scripts

| script | 역할 |
|--------|------|
| `common.sh` | pipeline_state 경로, schema_version, log, jq 의존 |
| `state-get.sh <field>` | pipeline_state.json 필드 조회 |
| `state-set.sh <field> <value>` | 필드 갱신 (auto updated_at) |
| `queue-next.sh` | service_queue 에서 다음 autonomous-doable 반환 (priority asc) |
| `queue-advance.sh <service> <status>` | service status 전이 |
| `phase-advance.sh --check\|--commit <N>` | phase guard / commit |
| `regen-status.sh` | status.md 재생성 |
| `invoke-subagent.sh` | **★ M6 핵심** — Phase 1-7 sub-agent dispatch (opus + full permissions) |
| `enforce-block-only-gate.sh <service>` | BLOCK_ONLY 판정 가능 여부 (D14b) |
| `enforce-3strike.sh <service>` | (V1 legacy, V2 미사용) |

## Cross-skill 호출 경로

**M6 변경**: cross-skill 호출은 모두 **sub-agent prompt 안에서** 발생 (main agent 가 직접 호출 안 함).

| 호출 지점 | 대상 skill | 호출 방식 |
|----------|-----------|----------|
| Phase 3 빌드/배포 | etap-build-deploy | sub-agent prompt 안에서 `bash runtime/etap-build-deploy.sh` 호출 |
| Phase 3, 4, 6 test PC 왕복 | cowork-remote | sub-agent prompt 안에서 `bash runtime/push-request.sh + scan-results.sh` 호출 |
| Phase 6 iteration (apf-warning-impl 흡수) | (없음, Phase 6 sub-agent 가 직접 수행) | iteration logic 이 phase6-warning-impl.md 안에 |
| Phase 7 빌드 | etap-build-deploy | sub-agent prompt 안에서 호출 |

Sub-agent 는 `--add-dir` 로 각 skill 의 runtime 경로 접근 가능.

## Policy Enforcement (cross-cutting)

| policy | 판정자 | 동작 |
|--------|-------|------|
| 3-Strike auto-suspend | **폐기 (2026-04-28 21차)** | 자동 SUSPENDED X. cause-based axis pivot. |
| BLOCK_ONLY gate (D14b) | sub-agent + per-service analysis doc | 모든 listed 접근법 시도 + 결과 명시 + inapplicable 증명 후만 `terminate:block_only_accepted` 허용 |
| 응답 대기 중 STALLED 자동 전환 | **없음** | 결과 도착까지 반복 (ScheduleWakeup chain) |
| Mission-goal persistence (HR7, 41차) | stop-autonomous-guard.sh | ratio < 1.0 시 stop block |

## 자율 수행 규칙 (보존, 사용자 directive immutable)

- 질문으로 끝맺지 않음
- 결과 대기 중 STALLED 자동 전환 없음 (ScheduleWakeup chain 으로 scan 반복)
- Phase 전환 시 `references/phase{N}-*.md` 필수 Read (sub-agent prompt 작성 위해)
- Single-service focus 유지 (queue-next 결과 하나만)
- **선택지 제시 금지 (Hard Rule 6 v2)**: 복수 valid options → Mode Selection Tree:
  - **M0 Empirical Comparison (default)** — testable + revertible 이면 모두 테스트 + 비교 + winner
  - M1 reasoning / M2 Micro-Discussion / M3 full `discussion-review` / M4 user ask (물리적 예외만)

→ See `references/autonomous-execution-protocol.md` for Hard Rules 1-7 v3 + Polling Policy v2.

## Service Status & Goal Accounting (2026-04-28 20차)

Status enum (canonical schema: `cowork-remote/references/pipeline-state-schema.md`):
```
DONE | BLOCKED_diagnosed | BLOCKED_undiagnosed | NEEDS_LOGIN | TERMINAL_UNREACHABLE
```

**핵심 원칙 (D14 a/b/c)**:
- **(a) 디버깅 = 작업 출력** — `BLOCKED_undiagnosed → BLOCKED_diagnosed` transition 도 진전
- **(b) Architectural 한계 → engine extension / etap 기능 우회** — H3/QUIC 는 force_h2. 영구 EXCEPTION 금지.
- **(c) Service characterization = 모든 발견 통합** — `cause_pointer` 가 single per-service analysis doc 가리킴

Goal accounting:
```
Reachable progress = DONE / (TOTAL - TERMINAL_UNREACHABLE)
```

## next_action Vocabulary v2

Canonical: `apf-operation/state/pipeline_state.json` 의 `_next_action_vocabulary_v2` field
(4 families: `debug_*` / `apply_engine_fix:*` / `defer:*` / `terminate:*` / `infra_blocked:*` / `infra_unblock_check:*`).

**M6 추가 verb** (phase advance): `phase{N}_{name}` — 예: `phase4_frontend_inspect`, `phase6_warning_impl`.

## 제외 기능

- ❌ Scheduled Task / cron / launchd / fireAt / Monitor persistent (Polling Policy v2)
- ❌ In-session bash loop
- ❌ 자동 STALLED escalation
- ❌ 사용자에게 선택지 제시 + 지시 대기 (Hard Rule 6)
- ❌ Main agent 가 phase 실작업 직접 수행 (M6 — sub-agent 로 위임)

## References (on-demand)

**Main agent 가 phase dispatch 시 Read** (sub-agent prompt source):
- `references/phase{1,2,3,4,5,6,7}-*.md`

**Main agent 가 cite (필요 시 일부 Read)**:
- `references/autonomous-execution-protocol.md` (HR1-7, Polling Policy v2, Self-Check A-J)
- `references/apf-technical-limitations.md` (D14b BLOCK_ONLY gate)

**Sub-agent 가 --add-dir 로 자동 접근** (main 읽기 불필요): 나머지 references.

**Legacy archive**: `references/legacy/` (V1 orchestration loop 등).

## Related

- `cowork-remote`, `test-pc-worker`, `etap-build-deploy` — sub-agent prompt 안에서 호출
- `apf-warning-impl` — **legacy reference 보존** (Phase 6 sub-agent 가 iteration logic 흡수, A 방식)
- `research-gathering` — Phase 진입 전 historical context 수집 (sub-agent prompt 안에서 호출 가능)
