# Incident Log — research-gathering skill 존재 근거

본 skill 이 존재해야 하는 이유는 **추측이 아닌 실증** 이다. 아래 6건 모두 2026-04-21 ~ 2026-04-22 세션 transcript (`~/.claude/projects/-Users-jhee-Documents-workspace-Officeguard-EtapV3/319f0faf-e0b1-4fba-a31a-383013927b28.jsonl`) 에서 line 번호와 함께 재현 가능.

이 파일은 **append-only**. 새로운 incident 발견 시 `runtime/feedback.sh --report-incident` 로 append. 기존 항목 수정 금지.

---

## Incident 1 — Batch Linked List 방법론 소실 (가장 큰 사례)

**발생 기간**: 2026-04-21 ~ 2026-04-22

**사실 관계 (transcript verified)**:
- 2026-04-21 00:33 (line 66) — 사용자: "Directed Acyclic Graph 와 링크드 리스트의 장단점을 비교해줘."
- 2026-04-21 00:36 (line 75) — 사용자: "내가 생각하는 링크드 리스트의 작업에는 병렬성이 포함되어 있어. 그룹화된 단위 스킬들이 병렬로 수행 가능한 작업들로 모아놓아 진행하면 된다고 생각했어. 다시 비교해줘."
- 2026-04-21 00:40 (line 77) — Claude: Batch Linked List 설계 완성 (`execution_mode: serial | parallel`, `barrier_policy`, homogeneous-batch 규칙, long-running-solo 규칙, `wrap_as_batch` / `unwrap_batch` 편집 연산)
- 2026-04-21 00:42 (line 82) — 사용자: "반영해줘."
- Claude 는 line 93, 95, 98, 103, 106, 108, 110, 113, 115, 117 의 Edit 도구 호출로 `architecture.md`, `workflow.md`, `orchestration-group-template.md`, `orchestrator/SKILL.md` 4개 파일에 반영.

**소실 경로**:
1. 2026-04-21 중반 — `micro-unit-skill-creator` 프로젝트가 "use-case first 위반" 사유로 `.archived-2026-04-21` 로 archive
2. 2026-04-21 후반 — 새 프로젝트 `cowork-micro-skills` 시작 시 원 설계 방법론 미이식
3. 2026-04-22 — 디렉터리 정리 과정에서 `.archived-2026-04-21` 디렉터리 자체가 disk 에서 **삭제**
4. 2026-04-22 후반 — 사용자 "스택 구조나 링크드 리스트 구조를 이용해달라는 기준을 세웠는데 그 내용이 있어?" 질문에 Claude 가 "기록되어 있지 않습니다" 오답. transcript 미검색이 원인.

**수행된 조사**: 4개 문서 소스 grep (cowork-micro-skills, shared-skills, ~/.claude/skills, memory notes).
**수행되지 않은 조사**: transcript jsonl 직접 읽기, archived 디렉터리 확인, git log 로 삭제 파일 history, file-history 확인.

**Root cause**: Transcript 가 first-class 소스임에도 조사 범위에 미포함.

**본 skill 의 대응**: `transcript_scan` 노드를 독립 solo long-running 노드로 고정. `filesystem_scan` 에 `~/.claude/file-history/` + archived 디렉터리 포함.

---

## Incident 2 — "Phase 0 충분히 선행" 허위 주장

**발생**: 2026-04-22 세션 — 토론 #45 디렉터리 관리 리뷰 단계

**사실 관계**:
- 사용자가 `discussion-review` skill arguments 로 "Phase 0 사전 정보 수집 충분히 선행" 명시
- Claude 는 "Phase 0 complete" 선언 후 discussion 진행
- 실제 확인: 현재 디렉터리 구조 + 프로젝트 문서 일부 + PHASE0-AUDIT.md
- 미확인: 이전 세션 transcript, 사용자 구두 지시 이력, archived 프로젝트 잔존물

**증거**: 세션 내내 "충분히 수집" 주장. 사용자가 "당신이 직접 설계했던 초기 설계안도 무시하는데 어떻게 한다는거야?" 지적한 시점에 비로소 transcript 조사 시작. 이전 주장 모두 허위로 판명.

**Root cause**: "완료" 자가 선언이 허용되는 구조. 정량 기준 없음.

**본 skill 의 대응**: 이진 `complete` 자가 선언 금지. 반드시 `coverage` 필드의 raw `{numerator, denominator, target}` 과 함께 출력. `status` 는 파생 필드.

---

## Incident 3 — 구두 지시 단일 문서 의존

**발생**: 2026-04-22 Session 1'

**사실 관계**:
- 사용자 구두 지시: "stall count는 필요 없어 보여" (decision α)
- Claude 는 `pipeline-state-schema.md` 수정 (A1 action)
- 원문은 handoff.md Q2 에만 기록. INTENTS.md / lessons.md / MEMORY note 어디에도 미반영.
- 다음 세션에서 "왜 stall_count 제거됐나?" 질문 시 handoff.md 못 읽으면 추론 불가

**Root cause**: 사용자 구두 결정이 최소 3곳 (원칙 immutable + 세션 handoff + 영구 memory) 에 동시 기록되지 않음. 승격 경로 부재.

**본 skill 의 대응**: `promotion_suggest` 노드가 구두 지시 미반영 검출. `promotion_proposal.md` 에 INTENTS/MEMORY/lessons 각각에 대한 actionable diff 생성. 사용자 "promote X" 구두 승인으로 자동 반영.

---

## Incident 4 — 허구 파일 기록 (session-recovery.ps1 등)

**발생**: 2026-04-21 Session 0 (cowork-micro-skills 초기 설계)

**사실 관계**:
- handoff.md 에 "session-recovery.ps1, write-heartbeat.ps1, adjust-polling-stage.ps1 을 제거했다" 기록
- 실제로는 shared-skills 에 해당 파일이 **애초에 존재한 적이 없음** (git history 확인으로 실증)
- Claude 가 "test-pc-worker 에는 이런 파일이 있을 법하다" plausibility 추론으로 "제거된 파일 목록" 생성

**Root cause**: plausibility 기반 추론과 사실 기반 기록이 구분되지 않음. source_class 개념 부재.

**본 skill 의 대응**: 모든 finding 에 `source_class` tag 필수. primary (사용자 원문 / 원본 문서 / raw tool output) 와 secondary (Claude 의 이전 text) 자동 구분. secondary-only 는 `verification_status` 에 flag → 수동 재검증 요구.

---

## Incident 5 — "No match found" 단일 소스 결론

**발생**: 2026-04-22 세션 후반 — 사용자 "스택/링크드 리스트 기준 있어?" 질문

**사실 관계**:
- Claude 가 4개 소스 (project, shared-skills, ~/.claude/skills, memory) 에서 `grep -i "스택|링크드|LIFO|FIFO"` 수행
- 모두 "No match found" → "해당 기준은 기록되어 있지 않습니다" 결론
- 실제로는 transcript line 66/75/77 에 **사용자 원문과 Claude 응답이 모두 존재**

**Root cause**: 4개 소스 == 조사 전체 라는 오인. Transcript 미조사.

**본 skill 의 대응**: 4 scanner (filesystem + git + memory + transcript) + keyword_expand_loop 구조 강제. 특정 scanner hit 0 시에도 `disconfirmation` 명시 필수. "찾지 못했다" 결론은 4 scanner 모두 스캔 완료 후에만 가능.

---

## Incident 6 — 조사 생략 후 약속

**발생**: 2026-04-22 세션 — 사용자 "당신은 스킬을 수정할 능력이 없나봐" 지적 직후

**사실 관계**:
- Claude 응답: "다시 말씀해 주시면 원문 그대로 INTENTS/MEMORY/lessons 세 곳에 동시 기록하겠습니다."
- 사용자 재지적: "충분한 정보를 수집했다고 했지만 당신이 직접 설계했던 초기 설계안도 무시하는데 어떻게 한다는거야?"
- 문제: 조사 실행 없이 약속만 함. 약속은 조사 대체 불가.

**Root cause**: 문제 지적 시 조사 재개 대신 promise 생성. 구조적 강제 부재.

**본 skill 의 대응**: SELF_TEST_PASSED gate. 스킬이 자기 자신에 대해 통과하지 못하면 실행 거부. "약속" 은 gate 통과 조건이 아님.

---

## 공통 패턴 (6 incident 의 분석)

1. **검색 범위 단편화** — 한두 곳만 확인하고 전체 결론
2. **transcript 비사용** — first-class 소스임에도 검색 범위에 미포함
3. **증거 없는 단정** — "없다 / 있었다" 를 복수 소스 교차 없이 선언
4. **약속으로 조사 대체** — 문제 지적 시 조사 대신 promise

본 skill 의 10개 consensus item 은 위 4개 패턴을 각각 구조적으로 차단하는 것이 목표.

---

## Incident 추가 방법 (append-only)

새 incident 발견 시:

```bash
bash runtime/feedback.sh --report-incident "<description>" \
   --missed-keyword "<what was missed>" \
   --expected-tier "<tier>" \
   --root-cause "<why>" \
   --session-id "<current>"
```

이 스크립트는 `incident_registry.jsonl` 에 구조화 record 를 append 하고, 본 파일에도 "Incident N" 섹션을 수동 작성하도록 템플릿을 출력. 본 파일의 기존 섹션은 절대 수정하지 않는다.

---

## Incident 7 — Doc-source drift: skill 인용 명령이 실제 환경에 미존재

**발생**: 2026-04-29 cycle 95 cleanup, Phase 5 L7 부하 측정 중

**사실 관계**:
- `etap-bench/SKILL.md` §Step 4 와 memory `feedback_etap_dpdk_unavailable.md` 가 `etapcomm etap.total_traffic` 명령을 monitoring 도구로 권고
- 실제 etap v2.x 환경 호출 결과: `FAILED : Unknown function total_traffic`
- 영향: 자율 모드에서 부하 측정 시 monitoring metric 수집 실패 → trial-and-error 로 대체 명령 (`ai_prompt_filter.show_stats`, `etap.port_info`, `/proc/PID/status`) 발견
- 이외 동일 cleanup 에서 발견된 drift:
    - `etap-testbed/references/module-toggle.md` regex `[^/]*?` 가 path 안 `/` 때문에 매칭 실패 (8일 전 메모 작성 시점에는 검증된 듯하나 환경/규약 변경으로 broken)
    - `etap-testbed/references/step1-deploy-restart.md` 가 testbed Etap 별도 install 단계 누락 — `etap-build-deploy.sh` 가 테스트 서버만 deploy 하는 구조 변경 미반영

**Root cause**: Skill reference 의 명령/regex/절차가 작성 시점에 정확했어도 (a) etap minor version 변경, (b) 빌드 스크립트 동작 변경, (c) DB 컬럼 schema 변경으로 stale. 검증 metadata 부재.

**본 skill 의 대응 (제안 단계 — 토론 consensus 필요)**:
- Skill reference 인용 명령에 `<!-- verified: YYYY-MM-DD env=etap-v{X} -->` annotation
- 6개월 또는 etap minor version bump 시 자동 stale flag → 재검증 trigger
- Skill 편집 종료 전 `feedback_skill_edit_self_review.md` §"How to apply" 의 7-point grep 의무화 (cycle 95 self-review 누락 사례에서 잔존 2건 추가 발견 — `88ac6c9`)

**Recovery**: `dev_test_sync@3875f08` (drift fix 3 files) + `88ac6c9` (self-review recovery 2 files). 총 5 files 정정.

---

## 재현 명령 (검증용)

모든 incident 는 동일 transcript 에서 재현 가능:

```bash
bash runtime/research-scan.sh --keyword "링크드 리스트" --consumer interactive
# → Incident 1 의 transcript line 66/75/77 를 Tier 3 에서 발견

bash runtime/research-scan.sh --keyword "session-recovery.ps1" --consumer interactive
# → Incident 4 의 허구 기록을 secondary-only 로 분류
```

self-test 도 이 재현을 포함한다.
