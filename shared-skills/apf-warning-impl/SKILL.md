---
name: apf-warning-impl
type: A
execution_context: main_only
description: "[LEGACY — M6 (2026-05-11) 이후 Phase 6 sub-agent 로 흡수됨, 방식 A]. iteration logic 은 genai-apf-pipeline/references/phase6-warning-impl.md 가 흡수. 본 skill 폴더는 phase6 sub-agent prompt 가 참조하는 reference repository (references/, runtime/, services/{N}_impl.md). 직접 trigger 하지 말 것 — main agent 는 genai-apf-pipeline 만 트리거하고 Phase 6 진입 시 sub-agent 가 본 references/ 를 자동 cite."
allowed-tools: Bash, Read, Write, Edit, Grep, Glob
---

<!-- execution_context: main_only — LEGACY skill, sub-agent dispatch 부적합 (references/runtime/services/ repository 역할만). D32.b reference. -->


# apf-warning-impl (LEGACY — M6 deprecated)

> **★ Parent Mission Anchor (59차 Q1 Gap D fix, M3 합의)**: 본 skill (LEGACY, Phase 6 sub-agent 흡수) 은 `genai-apf-pipeline ## ★ APF Mission` (D20 26차 canonical) 의 **warning 구현 layer** reference. APF Mission = "모든 등록 AI 서비스에 대해 PII 포함 프롬프트 입력 시 사용자 화면에 경고 문구 표시" (사용자 verbatim 2026-04-29). C++ generator strategy 선택 / iteration / verdict 의 anchor. ratio 측정 분모/분자 = 사용자 directive 영역 — 자율 재정의 금지 (D9 Stage 6 sub-form).
> **Canonical**: `cowork-micro-skills/INTENTS.md §1.5 APF Project Mission` + `genai-apf-pipeline/SKILL.md ## ★ APF Mission (canonical anchor, D20 26차)`.

> **★ DEPRECATION NOTE (2026-05-11, M6 architectural shift)**
>
> 본 skill 의 iteration logic (Pre-iteration gate / 5-verdict / sub_category pivot /
> impl journal append) 은 **Phase 6 sub-agent 가 흡수**했다 (방식 A,
> `cowork-micro-skills/master-plan.md §5.2.5`).
>
> 본 skill 폴더는 **reference repository** 로 보존된다:

| 보존 항목 | 역할 | Phase 6 sub-agent 에서 |
|----------|------|---------------------|
| `references/http2-strategies.md` | Strategy A/B/C/D/E 정의 | cite |
| `references/cpp-templates.md` | generator 함수 템플릿 | cite |
| `references/test-fix-diagnosis.md` | verdict 매핑 | cite |
| `references/escalation-protocol.md` | cause-based pivot | cite |
| `references/test-log-templates.md` | APF_WARNING_TEST 로그 포맷 | cite |
| `references/db-and-generators.md` | DB ↔ generator 매핑 | cite |
| `references/escalation-architecture-limits.md` | architectural limits | cite |
| `runtime/check-pre-retest-gate.sh` | gate 판정 | 호출 |
| `runtime/record-iteration.sh` | journal append | 호출 |
| `runtime/count-attempts.sh` | iteration count | 호출 |
| `runtime/invoke-build-deploy.sh` | etap-build-deploy wrapper | 호출 |
| `runtime/invoke-test-check.sh` | cowork-remote wrapper | 호출 |
| `runtime/common.sh` | 공통 utility | 호출 |
| `services/{service_id}_impl.md` | per-service iteration journal | append |

**직접 trigger 금지**: Main agent 는 `genai-apf-pipeline` 만 트리거. Phase 6 진입 시
sub-agent (claude-opus-4-7) 가 자동으로 본 references/ 를 cite + runtime/ 을 호출.

→ **새 진입점**: `cowork-micro-skills/skills/genai-apf-pipeline/references/phase6-warning-impl.md`

## Reference 수정 시 (sync 의무)

본 skill 의 references/* 수정 시, `phase6-warning-impl.md` 의 cite 가 여전히 유효한지
확인 의무 (file path / section heading 변경 시 phase6 prompt 동기 갱신).

## Related

- **`genai-apf-pipeline`** (Phase 6 sub-agent prompt 가 본 reference repository 참조)
- **`etap-build-deploy`** (runtime/invoke-build-deploy.sh 가 호출)
- **`cowork-remote`** (runtime/invoke-test-check.sh 가 호출)
