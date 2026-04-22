---
name: research-gathering
description: 정보 수집·자료 조사 전용 skill. "충분히 확인했다" 같은 허위 완료 선언을 구조적으로 방지한다. Batch Linked List 실행 구조로 병렬 스캐너를 barrier 동기화, 정량 coverage 기준을 원자료와 함께 출력, primary/secondary source 구분, content hash dedup, `.research-run/` 디렉터리에 plan/stack 스냅샷 저장해 compact 이후 재개 가능. 토론·스킬 수정·원칙 변경·과거 기억 검증 등 "정보가 결정 근거가 되는 모든 상황"에서 발동.
---

# Research Gathering — v1

**생성**: 2026-04-22 토론 consensus 기반 (본 세션 transcript 에서 설계 원문 확인 가능).
**이전 버전**: 프로젝트 mirror 의 v0.1 초안은 flat 구조 + 문서 체크리스트만 있었고 13개 품질 기준 중 0개를 만족함. v1 은 토론에서 도출된 10개 consensus item 을 구조적으로 구현.

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

**이 스킬은 자기가 금지하는 패턴을 자기가 범하지 않는다.**

따라서:
1. 이진 "완료" 를 자가 선언하지 않는다. 정량 coverage 숫자만 내놓고 소비자가 판정한다.
2. Batch Linked List 구조로 실행한다 — 이 프로젝트의 micro-control 원칙을 자기 내부에 적용한다.
3. `.research-run/` 에 plan/stack 스냅샷을 남긴다 — compact 이후 재개 가능한 형태로만 진행한다.
4. 첫 실행 전 **자기 자신에 대한 self-test 를 통과** 해야 동작한다 (재귀적 부트스트랩 gate).

---

## 내부 실행 구조 — Batch Linked List

```
HEAD
 → keyword_expand_loop       (serial, max 3 iter)
 → BATCH{ git_scan ∥ memory_scan ∥ filesystem_scan }    (barrier: all_done)
 → transcript_scan           (solo, long-running)
 → aggregate_dedup           (serial)
 → contradiction_check       (serial)
 → promotion_suggest         (serial)
TAIL
```

### 왜 이 구조인가

- **keyword_expand_loop 가 serial/loop 인 이유**: 초기 scan 결과에서 동의어·관련어를 발견해 다시 확장해야 함. 순수 serial 이 아닌 bounded loop (최대 3 iter).
- **3 scanner 가 batch parallel 인 이유**: 서로 독립적, 실행 시간 비슷 (수 초 이내), 동질 배치 규칙 만족.
- **transcript_scan 이 solo 인 이유**: 10MB 이상 jsonl 을 처리하므로 실행 시간 분산 큼. Long-running solo 규칙에 따라 batch 에서 분리.
- **aggregate / contradiction / promotion 이 serial 인 이유**: 이전 노드 출력이 다음 입력. 의존 명확.

### 상태 저장

각 노드는 `.research-run/{query_id}/outputs/{node_id}/` 에 raw 출력. `plan.json` 이 노드 목록 + 상태 (PENDING/RUNNING/DONE/FAILED), `stack.json` 이 실행 커서 (현재 명령 + 인자 + cwd).

**Compact 이후 재개**: plan.json 읽고 non-DONE 노드부터 재실행. stack.json 의 명령을 그대로 재수행.

### 편집 연산 (plan 에 대한)

- `insert_after(anchor, new_node)` / `insert_before(anchor, new_node)` — 조사 중간 추가 노드 삽입
- `remove(node)` — DONE 노드 제거 불가
- `replace(old, new)` / `reorder(a, b)` (둘 다 PENDING 일 때만)
- `wrap_as_batch([n1, n2])` — 독립·동질 노드를 배치로 묶기
- `unwrap_batch(batch)` — 배치를 개별 serial 로 풀기

전체 재작성 금지. diff-level 편집만.

---

## 정보 소스 4-Scanner (+ expand loop)

### git_scan (batch)
- `git log --all --oneline -S "<keyword>"` (pickaxe) on registered repos
- 기본 repos: `dev_test_sync`, `cowork-micro-skills` (non-git 이면 skip + warning)
- 삭제된 파일 history 포함

### memory_scan (batch)
- `~/.claude/projects/.../memory/*.md` 전수 grep
- MEMORY.md, project_*.md, feedback_*.md 모두

### filesystem_scan (batch)
- 현재 파일 상태 + `.bak-*` / `.disabled-*` / `*archived*` 디렉터리
- `~/.claude/file-history/` 포함 (삭제된 파일 복원 가능)
- 프로젝트 디렉터리 + shared-skills + user-level skills

### transcript_scan (solo)
- `~/.claude/projects/-Users-jhee-.../*.jsonl` 전수 (현재 세션 한정 아님)
- python json line parser 로 `type: user | assistant | tool_use` 별 분류
- user 메시지 → primary, assistant → secondary, tool_use Write/Edit content → primary-if-user-approved-else-secondary

### keyword_expand_loop (serial, ≤3 iter)
- 입력 키워드에 대해 동의어·관련어 후보 생성
- 초기: 사용자 원문 키워드 + 직역/의역
- iter 2~3: scan 결과 히트의 주변 용어 추출 → 새 키워드로 추가

**확장 dictionary 초기 seed**: incident-log 에서 학습한 패턴 (v1 에서는 incident 유래 + 휴리스틱, v1.1 에서 체계적 seed).

---

## 완료 판정 (Exit Criteria)

**이진 self-declaration 금지.** 출력은 항상 정량:

```json
"coverage": {
  "filesystem": { "numerator": 95, "denominator": 100, "target": 0.95 },
  "git":        { "numerator": 10, "denominator": 10, "target": 10 },
  "transcript": { "numerator": 20, "denominator": 23, "target": "min(20, all)" },
  "memory":     { "numerator": 7,  "denominator": 7,  "target": "all" }
}
```

`status` 필드는 파생:
- `complete` — 모든 target 충족 AND disconfirmation quota 만족 AND unresolved contradiction 없음
- `insufficient` — target 미달 또는 contradiction 해결 안 됨. `missing_actions` 에 다음 수행 명령 명시
- `partial` — 일부 scanner 실패. `failed_nodes` 에 사유 포함
- `failed` — orchestrator 레벨 실패

### Disconfirmation quota

긍정 히트 1개당 반증 확인 필수. 출력에 명시:
> "Claim X: found 3 primary sources. Disconfirmation checked in tiers {git, memory} — no contradicting evidence."

반증 확인 없이는 `verification_status: verified` 부여 금지.

---

## Source 분류 + 검증 상태

매 finding 마다:

### source_class
- `primary` — 사용자 원문 / 원본 문서 / raw tool output
- `secondary` — Claude 의 이전 turn 텍스트 / 파생 문서 / 의역

자동 할당 규칙 (transcript 에 대해):
- jsonl `type: user` → primary
- jsonl `type: assistant` → secondary
- jsonl `tool_use` Write/Edit content → 사용자가 이전에 승인 발언 (반영해줘, 적용해줘 등) 이 선행했으면 primary, 아니면 secondary

### verification_status
- `verified` — 서로 독립적인 primary ≥ 2 개 일치
- `single-source` — primary 1, 반증 없음
- `secondary-only` — Claude 자기 이전 발언만 — **수동 재검증 flag**
- `contradicted` — primary ≥ 2, 값 상충 — 해결 필요

### 시간 축 + immutability

동일 주제 2 primary 상충 시 **최신 primary 우선**. 단, INTENTS.md 에 "immutable" annotation 된 것은 최신 여부 무관 override.

---

## Dedup (content hash)

같은 파일이 여러 scanner 에서 hit 되면 content hash 계산 후 `source identity` 로 merge. 출력:
> "found in 3 scanners via 1 identity (path=X, content_hash=abc123)"

Hit count inflation 방지.

---

## 소비 계약 — schema v1 (frozen)

`report.json` 은 아래 schema v1 을 따른다. 필드 삭제 금지, 추가는 v2 로 bump.

```json
{
  "schema_version": 1,
  "query": {
    "keyword": "<user original>",
    "expanded_terms": ["<syn1>", "<syn2>"],
    "query_id": "<uuid>",
    "consumer": "<consumer_id or 'interactive'>",
    "invoked_at": "<iso8601>"
  },
  "status": "complete | insufficient | partial | failed",
  "coverage": { "filesystem": {...}, "git": {...}, "transcript": {...}, "memory": {...} },
  "findings": [
    {
      "claim": "<concise statement>",
      "source_class": "primary | secondary",
      "verification_status": "verified | single-source | secondary-only | contradicted",
      "evidence": [
        { "path": "<file or transcript>", "line": 77, "timestamp": "<iso8601>",
          "quote": "<exact text>", "source_identity": "<content_hash>" }
      ]
    }
  ],
  "contradictions": [
    { "topic": "...", "values": [ {...}, {...} ], "resolution": "most_recent_primary | user_required | deferred" }
  ],
  "missing_actions": [
    "<command or step to reach 'complete'>"
  ],
  "promotion_candidates": [
    { "text": "...", "target": "INTENTS.md | MEMORY/feedback_*.md | lessons.md",
      "rationale": "...", "strength": "strong | weak" }
  ],
  "failed_nodes": [
    { "node_id": "git_scan", "reason": "non-git repo", "fallback": "skipped" }
  ]
}
```

**계약된 소비자**:
- `discussion-review` Phase 0 사전 브리핑 입력
- `workflow-retrospective` Step 0.5 adoption 확인 보조
- `cowork-micro-skills-guide` 세션 진입 시 "놓친 과거 설계" 감지

각 소비자는 자기 Read loop 에서 `report.json` 을 파싱해 자기 작업에 통합.

**Human-readable 대응**: `report.md` 가 report.json 에서 자동 생성. 사용자 직접 검토용.

---

## Persistence — `.research-run/` 구조

```
.research-run/{query_id}/
├── query.json                    ← 키워드, expanded, consumer, 시각
├── plan.json                     ← 노드 목록 + 상태
├── stack.json                    ← 현재 커서 (명령 + 인자 + cwd)
├── outputs/
│   ├── keyword_expand_loop/iter_{1,2,3}.json
│   ├── git_scan.json
│   ├── memory_scan.json
│   ├── filesystem_scan.json
│   ├── transcript_scan.json
│   ├── aggregate_dedup.json
│   └── contradiction_check.json
├── report.json                   ← schema v1
├── report.md                     ← human-readable
└── promotion_proposal.md         ← findings → INTENTS/MEMORY/lessons diff 제안
```

**위치**: 기본 프로젝트별 (`{project_root}/.research-run/`). v1 결정은 per-project, 3개 실제 조사 수행 후 재평가.

**Retention policy**: per-consumer 선언 필수, 기본값 없음. 호출 시 consumer 가 `retention: "session" | "30d" | "permanent"` 명시.

---

## Promotion Pipeline (승격 경로)

조사 결과 중 **미반영 발견** (Claude 가 이전에 설계했으나 현재 문서에 없는 것, 사용자 구두 지시가 원칙 문서에 승격 안 된 것) 은 `promotion_proposal.md` 로 출력:

```markdown
## Promotion Candidate 1 — {topic}

**Source**: transcript line 77, 2026-04-21 00:40, `type: assistant` — user approved at line 82 ("반영해줘")
**Current state**: not present in INTENTS.md, master-plan.md, lessons.md, MEMORY note
**Proposed**: Add to INTENTS.md under "Derived Principles":
  > {verbatim text}
**Strength**: strong (user explicitly approved)

---
## Promotion Candidate 2 — ...
```

사용자가 `"promote 1, 3"` 같은 구두 명령으로 승인하면 해당 candidate 를 실제 문서에 append. `workflow-retrospective` Step 0.5 가 닫으려던 adoption gap 을 본 skill 이 구조적으로 닫는다.

---

## 자가 일관성 Gate (Self-Test)

`.research-run/SELF_TEST_PASSED` marker 가 현재 version 과 일치하지 않으면 스킬은 **실행 거부**.

### Self-test 절차

1. 스킬 자기 이름 + 관련어 ("research-gathering", "자료 조사", "batch linked list") 로 스캔 실행
2. transcript scanner 에서 본 skill 설계 토론 발견 확인 (본 세션 기준)
3. filesystem scanner 에서 본 SKILL.md 발견 확인
4. known test case 에서 `promotion_proposal.md` 생성 동작 확인
5. 모두 통과 → marker 에 timestamp + version 기록

### Bootstrap 역설 해결

최초 invocation 은 self-test 자체이므로 gate 가 자기 자신을 막는 역설. 해결: 초기 marker 는 **사용자 수동 승인으로 1회 생성**. 이후 version bump 마다 자동 재수행.

---

## 학습 루프 (Learning Loop)

### Incident 보고
```bash
bash runtime/feedback.sh --report-incident "<description>" \
   --missed-keyword "<what was missed>" \
   --expected-tier "<tier>" \
   --root-cause "<why>"
```

`incident_registry.jsonl` 에 append (append-only, never rewrite).

### Registry 소비
매 scan invocation 시 incident_registry.jsonl 읽기:
- Missed keyword 패턴 → keyword_expand dictionary 에 추가
- Missed path → filesystem scanner 의 path list 에 추가
- Missed tier → 신 tier 추가 여부 검토 (사용자 승인 필요)

### Regression test
새 incident 는 자동으로 self-test case 로 등재. 다음 invocation 에서 동일 누락 재발 시 self-test 실패 → 스킬 거부 → 개선 강제.

---

## 사용자 대화 정책 (Interrogation)

Consumer 가 `autonomous=false` 선언한 경우에만, 아래 **3 category 의 trigger** 에서 질문 허용:

1. **Keyword ambiguity** — 여러 orthogonal domain 에서 hit (예: "stack" → 자료구조 vs TLS stack vs 콜스택). 사용자에게 맥락 확인.
2. **High-hit batching** — transcript hit count > 50. "상위 10/20/전체 중 선택" batch 질문.
3. **Unresolved contradiction** — primary ≥ 2 상충 + 시간 축 해결 실패. 사용자 judgment 요청.

`autonomous=true` 일 때는 conservative defaults 적용 + `report.json` 에 선택 logged. **그 외 상황에서 질문 금지** (autonomous mode HARD RULES 준수).

---

## 실패 내성 (Graceful Degradation)

### Partial scan
개별 scanner 실패 시 전체 fail 금지. `status: "partial"`, `failed_nodes: [...]` 에 사유 명시. 사용자 / consumer 가 partial 인지 complete 인지 즉시 구분 가능.

### 의존성 부재
- `python3` 없으면 → filesystem_scan / git_scan 만 bash native 로 실행, 나머지 skip + missing_actions 에 "install python3" 추가
- `git` 없거나 non-git repo → git_scan skip, report 에 명시
- jsonl 파일 권한 거부 / 없음 → transcript_scan skip, 이유 명시
- 개별 jsonl 라인 파싱 실패 → continue but total parsed count 노출 (은폐 금지)

**원칙**: "모두 확인했다" 선언이 실제 부분 실패인 경우 반드시 `status: partial`. 은폐는 incident 유발.

---

## 스킬 호출 방법

### 기본 (interactive)
```bash
bash ~/Documents/workspace/dev_test_sync/shared-skills/research-gathering/runtime/research-scan.sh \
     --keyword "<원본 키워드>" \
     --consumer interactive \
     --retention session
```

### Consumer 연동 (discussion-review Phase 0 예시)
```bash
bash .../research-scan.sh \
     --keyword "<topic>" \
     --consumer discussion-review \
     --retention 30d \
     --autonomous true
```

출력: `.research-run/{query_id}/report.json` 경로를 stdout 에 노출. Consumer 는 그 경로를 읽어 소비.

### Self-test
```bash
bash .../runtime/self-test.sh
```

---

## 알려진 한계 (v1)

- 웹 검색 미포함 (v1 은 로컬 스캔만)
- 다른 Mac 계정 / 원격 리포지토리 접근 불가
- 키워드 expand dictionary 의 초기 seed 는 휴리스틱 기반 (v1.1 에서 체계적 seed)
- `promotion_proposal.md` 의 diff 는 제안 수준. 사용자 승인 후 실제 반영은 다른 skill / 수동
- 동시 invocation 안전성 미검증 (v1 은 단일 사용 가정)

---

## 13 품질 기준 대응

| # | 기준 | 대응 방법 |
|---|------|---------|
| 1 | 마이크로 컨트롤 요구사항 수행 확률 | Batch Linked List 내부 구조 + edit operations |
| 2 | 편향 방지 | keyword_expand_loop + disconfirmation quota + coverage ratio |
| 3 | 수집 범위 충분성 | 4 scanner + cross-session transcript + file-history |
| 4 | 사실 기반 검증 | source_class + verification_status + 시간 축 ordering |
| 5 | 중복 수집 방지 | content hash dedup |
| 6 | 컨텍스트 손실 방지 | `.research-run/` plan.json/stack.json + resume |
| 7 | 자기 일관성 / 재귀 검증 | SELF_TEST_PASSED gate |
| 8 | 완료 판정 정량 기준 | coverage ratio + raw numbers + derived status |
| 9 | 결과 소비 경로 | schema v1 frozen + 3 계약 consumer |
| 10 | 사용자 대화 정책 | category-gated + autonomous flag |
| 11 | 실패 내성 | partial status + 은폐 방지 |
| 12 | 타 스킬 연동 API | schema v1 + retention policy |
| 13 | 학습 루프 | feedback.sh + incident_registry.jsonl + regression test |

---

## References

- `references/incident-log.md` — 본 skill 존재 근거 6 + 실증 사례 (transcript 인용)
- `references/schema-v1.md` — `report.json` schema 완전 사양
- `references/batch-linked-list.md` — 내부 실행 구조 상세 (4/21 설계 기반)

---

## Change Log

- **v1 (2026-04-22)** — 토론 Phase 3 consensus 10 항목 전량 반영. Draft v0.1 의 13개 품질 기준 전체 미충족을 구조적 대응으로 해소. 4/21 Batch Linked List 방법론 내재화. proposal-only 모드 준수.
- **v0.1 (2026-04-22, deprecated)** — Flat 체크리스트 초안. 프로젝트 mirror (cowork-micro-skills/skills/research-gathering/) 에 존재. v1 출시로 deprecated.
