---
name: research-gathering
type: B
allowed-tools: Bash, Read, Write, Edit, Grep, Glob
description: 정보 수집·자료 조사 전용 utility skill. "충분히 확인했다" 같은 허위 완료 선언을 구조적으로 방지한다. Batch Linked List 실행 구조로 병렬 스캐너를 barrier 동기화, 정량 coverage 기준을 원자료와 함께 출력, primary/secondary source 구분, content hash dedup, `.research-run/` 디렉터리에 plan/stack 스냅샷 저장해 compact 이후 재개 가능. 토론·스킬 수정·원칙 변경·과거 기억 검증 등 "정보가 결정 근거가 되는 모든 상황"에서 발동.
---

# Research Gathering — v1.2

**생성**: 2026-04-22 토론 consensus, v1.1 2026-04-23 bug fix, v1.2 2026-04-23 구조 정돈 (토론 consensus 기반 간소화 + Type B frontmatter)
**Type**: B (일반적 utility skill — 원칙 8 Type B Architectural Discipline 적용: IoC + Stable Contract + Justification Threshold)

---

## 언제 이 스킬이 발동되는가

키워드 / 상황:
- "자료 조사", "사전 조사", "정보 수집", "Phase 0", "pre-collection"
- `discussion-review` 의 Phase 0 단계
- 스킬 수정 / 제안 작성 / 원칙 변경 **직전**
- 사용자가 "~ 기준을 세웠었는데 있어?", "내가 말했던 ~ 어디 있어?" 같은 **과거 기억 검증** 요청
- "모든 관련 자료를 확인했다" 라고 선언하려 할 때 (self-trigger — 자가 감시)

---

## 핵심 설계 원칙

1. **이진 "완료" 자가 선언 금지** — 정량 coverage 숫자만 출력, 소비자가 판정
2. **Batch Linked List 자기 적용** — 본 skill 이 자체가 micro-control 원칙을 따름
3. **`.research-run/` 스냅샷** — compact 이후 재개 가능한 형태로만 진행
4. **Self-test gate** — 첫 실행 전 자기 자신에 대한 test 통과 필수 (재귀 부트스트랩)

---

## 내부 실행 구조 — Batch Linked List

```
HEAD
 → keyword_expand_loop       (serial, max 3 iter)
 → BATCH{ git_scan ∥ memory_scan ∥ filesystem_scan }    (barrier: all_done)
 → transcript_scan           (solo, long-running)
 → aggregate_dedup           (serial)
 → contradiction_check       (serial)
 → disconfirmation_check     (serial, v1.1 추가)
 → promotion_suggest         (serial)
TAIL
```

**선택 이유**: keyword_expand 는 bounded iteration. 3 scanner 는 독립·동질 → batch. transcript 는 대용량 → solo. 나머지는 순차 의존.

**상세**: `references/batch-linked-list.md`

---

## 정보 소스 4-Scanner (+ expand loop)

| 노드 | 대상 | 기본 경로 |
|-----|-----|--------|
| keyword_expand_loop | 동의어·관련어 확장 (≤3 iter) | incident_registry 학습 + 휴리스틱 |
| git_scan | git log pickaxe | dev_test_sync, cowork-micro-skills, Officeguard/EtapV3 |
| memory_scan | MEMORY note | `~/.claude/projects/.../memory/*.md` |
| filesystem_scan | 현재 파일 + .bak/.disabled/archived/file-history | 프로젝트 + shared-skills + ~/.claude/skills |
| transcript_scan | 세션 jsonl (cross-session) | `~/.claude/projects/.../*.jsonl` |

각 scanner 가 `outputs/{node}.json` 으로 결과 저장.

---

## 완료 판정 (Exit Criteria)

**이진 self-declaration 금지.** 출력은 항상 정량 coverage:

```json
"coverage": {
  "filesystem": { "numerator": 95, "denominator": 100, "target": 0.95 },
  "git":        { "numerator": 10, "denominator": 10, "target": 10 },
  "transcript": { "numerator": 20, "denominator": 23, "target": "min(20, all)" },
  "memory":     { "numerator": 7,  "denominator": 7,  "target": "all" }
}
```

`status` 파생 enum: `complete | insufficient | partial | failed`.

**Disconfirmation quota**: 긍정 hit 마다 "Tier X/Y/Z 에서 반증 없음" 명시 필수 (`disconfirmation_check` 노드가 antonym-bounded pointed search 로 검증).

---

## Source 분류 + 검증 상태

- `source_class`: `primary` (사용자 원문 / 원본 문서 / raw tool output) vs `secondary` (Claude 의 이전 텍스트 / 의역)
- `verification_status`: `verified` (distinct_files≥2 OR distinct_scanners≥2), `single-source`, `secondary-only`, `contradicted`
- **시간 축**: 최신 primary 우선. INTENTS immutable annotation 은 override.

---

## Dedup (content hash)

같은 content hash 가 여러 scanner 에서 hit 시 `source identity` 로 merge. Hit count 인플레이션 방지.

---

## 소비 계약 — schema v1 (frozen)

`report.json` schema 완전 정의는 **`references/schema-v1.md`** 참조.

핵심 필드 요약:
- `schema_version: 1`
- `query`, `status`, `coverage`, `findings`, `contradictions`, `missing_actions`, `promotion_candidates`, `failed_nodes`

**계약된 consumer**: `discussion-review` Phase 0, `workflow-retrospective` Step 0.5, `cowork-micro-skills-guide` 세션 진입.

**Principle 8.1 IoC 준수**: caller (Type A skill) 목록은 유지하지 않음. Caller 측이 자기 dependency 로 참조.

---

## Persistence — `.research-run/`

```
.research-run/{query_id}/
├── query.json, plan.json, stack.json
├── outputs/{node_id}.json
├── report.json  +  report.md
└── promotion_proposal.md
```

**Compact 이후 재개**: plan.json 의 non-DONE 노드부터 재실행. stack.json 의 명령 재수행.

**Retention**: per-consumer 선언 필수 (`--retention session|30d|permanent`).

---

## Promotion Pipeline

`promotion_suggest` 노드가 생성하는 `promotion_proposal.md` 에 actionable diff 제시. 사용자 `promote X, Y` 명령으로 승인 → INTENTS / MEMORY / lessons 에 append.

템플릿 / 예시: `references/schema-v1.md` 의 `promotion_candidates` 섹션.

---

## Self-Test & Learning Loop

### Self-test gate
`.research-run/SELF_TEST_PASSED` marker 없으면 실행 거부. marker 갱신 절차:
1. 스킬 자기 이름 + 관련어로 스캔 실행
2. transcript + filesystem 에서 본 skill 흔적 발견 확인
3. promotion_proposal 생성 동작 확인
4. 모두 통과 → marker 에 timestamp + version

**Bootstrap 역설**: 최초는 `bash self-test.sh --bootstrap` 로 skeleton marker 생성. nodes/ 구현 완료 후 `bash self-test.sh` (without --bootstrap) 로 full marker 획득.

### Learning loop
`bash runtime/feedback.sh --report-incident "<desc>" --missed-keyword "<what>" --expected-tier "<tier>" --root-cause "<why>"` 로 `incident_registry.jsonl` append. 매 scan 이 registry 읽음 → missed pattern 이 keyword_expand dict / scanner path 에 자동 반영. 새 incident 는 regression test case.

---

## 사용자 대화 정책 (Interrogation)

Consumer 가 `autonomous=false` 선언 시에만, 3 category trigger 에서 질문:
1. Keyword ambiguity (orthogonal domain 에서 동시 hit)
2. Transcript hit count > 50 (batch-ask top-N)
3. Unresolved contradiction (primary ≥ 2 상충)

`autonomous=true` 시 conservative defaults + `report.json` 에 선택 logged.

---

## 실패 내성 (Graceful Degradation)

- 개별 scanner 실패 → `status: partial`, `failed_nodes` 에 사유
- python3/git/jq 등 의존성 부재 → scanner skip, `missing_actions` 에 명시
- 부분 실패 은폐 금지 — "모두 확인" 선언 시 실제 부분 실패면 반드시 `status: partial`

---

## 스킬 호출 방법

### 기본 (interactive)
```bash
bash ~/Documents/workspace/dev_test_sync/shared-skills/research-gathering/runtime/research-scan.sh \
     --keyword "<원본 키워드>" --consumer interactive --retention session
```

### Consumer 연동 (예: discussion-review Phase 0)
```bash
bash .../research-scan.sh --keyword "<topic>" --consumer discussion-review \
     --retention 30d --autonomous true --scope filesystem,git,memory,transcript
```

### Scope narrowing (v1.1)
`--scope filesystem,git,memory,transcript` 중 subset 선택. 미선택 scanner skip + `coverage.skipped=true`.

### Self-test
```bash
bash .../runtime/self-test.sh [--bootstrap]
```

---

## 제외된 기능 (의도적)

아래는 현재 **제외** (speculative 구현 금지, trigger 충족 시 재검토):

- **Edit operations runtime API** (wrap_as_batch, insert_after 등) — `missing_actions` 방식으로 대체. v1.1 defer. Trigger: `feedback.sh` 가 missing_actions 방식으로 해결 안 되는 사례 기록 시.
- **자동 tier 분류기** — `--scope` 사용자 declare 로 대체. premature optimization. Trigger: user overkill 불만 발생 시.
- **웹 검색** — 로컬 scan 만 v1 지원. Trigger: 외부 업계 표준 / 선행 사례 조사가 반복적으로 필요할 때.
- **Cross-session lesson pattern extraction** — 자동 pattern mining. Trigger: incident_registry 가 유사 pattern 3+ 누적 시.
- **동시 invocation 안전성** — 단일 사용 가정. Trigger: concurrent consumer 실제 필요 시.

---

## 원칙 준수 증거 (Type B)

- **원칙 7**: `type: B` frontmatter 선언 (위)
- **원칙 8.1 IoC**: 본 문서 어디에도 "cowork-remote 는 ~, apf-warning-impl 은 ~" 식 caller 목록 없음. consumer 는 generic type (`discussion-review`, `workflow-retrospective` 등) 으로만 contract 정의
- **원칙 8.2 Stable Contract**: schema v1 frozen (`references/schema-v1.md`), 변경 정책 명시
- **원칙 8.3 Justification Threshold**: 도입 근거 문서 `references/justification.md` 참조 (2026-04-23 보강)

---

## 13 품질 기준 대응

13 기준 전체 대응 상세는 `cowork-micro-skills/skill-design-tiers.md` (Tier 0/1/2/3) + 본 skill 의 `references/` 참조. 요약: Tier 1 Must 5 범주 ✅, Tier 2 Should 5 범주 ✅ (Type B 기준), Tier 3 은 domain-dependent.

---

## References

- `references/incident-log.md` — 본 skill 존재 근거 실증 사례 (append-only)
- `references/schema-v1.md` — `report.json` frozen schema 완전 사양
- `references/batch-linked-list.md` — 내부 실행 구조 상세 (2026-04-21 설계 이식)
- `references/justification.md` — Type B Justification Threshold 증거 (원칙 8.3)

---

## Change Log

- **v1 (2026-04-22)** — 최초. 토론 Phase 3 consensus 10 항목 반영.
- **v1.1 (2026-04-23)** — 토론 consensus 4 방안: bug fix (verified/contradicted), edit-ops 문서 정직화, disconfirmation_check 노드, --scope flag.
- **v1.2 (2026-04-23)** — `cowork-micro-skills/skill-design-tiers.md` 의 Tier 0 + 원칙 7-8 적용: Type B 선언, allowed-tools 추가, SKILL.md 간소화 (406→약 220 줄), references/justification.md 신규, 제외된 기능 섹션 추가.
