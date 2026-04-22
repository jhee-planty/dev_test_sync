# report.json Schema v1 — Consumer Contract

본 문서는 research-gathering skill 이 출력하는 `report.json` 의 **frozen schema** 정의. 소비자 (discussion-review, workflow-retrospective, cowork-micro-skills-guide 등) 가 의존할 수 있는 안정 계약.

**필드 삭제 금지**. 필드 추가는 v2 로 bump. Backward-incompatible 변경은 v2 로만.

---

## 최상위 구조

```json
{
  "schema_version": 1,
  "query": { ... },
  "status": "complete | insufficient | partial | failed",
  "coverage": { ... },
  "findings": [ ... ],
  "contradictions": [ ... ],
  "missing_actions": [ ... ],
  "promotion_candidates": [ ... ],
  "failed_nodes": [ ... ]
}
```

---

## `query` 객체

조사 요청 메타데이터.

```json
{
  "keyword": "링크드 리스트",
  "expanded_terms": ["batch linked list", "execution_mode", "barrier_policy"],
  "query_id": "<uuid v4>",
  "consumer": "discussion-review | workflow-retrospective | cowork-micro-skills-guide | interactive",
  "autonomous": true,
  "retention": "session | 30d | permanent",
  "invoked_at": "2026-04-22T14:50:00+09:00",
  "invoked_by_session": "<session_uuid>"
}
```

- `keyword` — 사용자/소비자 원본 키워드. 원문 그대로.
- `expanded_terms` — keyword_expand_loop 가 생성한 동의어·관련어. 빈 배열 가능.
- `consumer` — 소비자 식별자. retention 정책 결정 근거.
- `autonomous` — true 면 질문 없이 conservative defaults, false 면 category-gated 질문 허용.
- `retention` — `.research-run/{query_id}/` 보존 기간.

---

## `status` 필드 (파생, 자가 선언 아님)

네 개 enum 값만 허용:

| 값 | 의미 | 결정 조건 |
|------|------|----------|
| `complete` | 조사 목적 달성 | 모든 coverage target 충족 AND disconfirmation quota 만족 AND unresolved contradiction 없음 |
| `insufficient` | 추가 조사 필요 | coverage target 미달 또는 contradiction 해결 안 됨. `missing_actions` 에 후속 명령. |
| `partial` | 일부 scanner 실패 | `failed_nodes` 비어있지 않음. 나머지 scanner 결과는 유효. |
| `failed` | orchestrator 실패 | 치명적 오류 (plan.json 작성 불가 등). 결과 신뢰 불가. |

**중요**: `status: complete` 는 `coverage` 의 raw 숫자가 target 을 충족한 결과로만 파생. 스킬이 직접 "complete" 로 선언할 수 없음.

---

## `coverage` 객체

각 scanner 의 커버리지 수치.

```json
{
  "filesystem": { "numerator": 95, "denominator": 100, "target": 0.95, "met": true },
  "git":        { "numerator": 10, "denominator": 10, "target": 10,   "met": true },
  "transcript": { "numerator": 20, "denominator": 23, "target": "min(20, all)", "met": true },
  "memory":     { "numerator": 7,  "denominator": 7,  "target": "all", "met": true }
}
```

- `numerator` / `denominator` — 실제 조사된 양 / 조사 가능한 전체
- `target` — v1 기본값 (scanner 별 별도 문서화)
- `met` — 파생. `numerator / denominator >= target` 인지 여부

**raw 숫자가 primary 정보**. 소비자는 numerator/denominator 를 직접 읽고 자기 기준으로 판정 가능.

---

## `findings` 배열

조사 결과로 발견된 claim 목록.

```json
[
  {
    "claim": "Batch Linked List 방법론이 2026-04-21 에 설계되고 사용자 승인됨",
    "source_class": "primary",
    "verification_status": "verified",
    "evidence": [
      {
        "path": "~/.claude/projects/.../319f0faf-...jsonl",
        "line": 77,
        "timestamp": "2026-04-21T00:40:00+09:00",
        "quote": "Batch Linked List is Pareto optimal for our case ...",
        "source_identity": "sha256:abc123...",
        "jsonl_type": "assistant"
      },
      {
        "path": "~/.claude/projects/.../319f0faf-...jsonl",
        "line": 82,
        "timestamp": "2026-04-21T00:42:00+09:00",
        "quote": "반영해줘.",
        "source_identity": "sha256:def456...",
        "jsonl_type": "user"
      }
    ]
  }
]
```

### `source_class` enum

- `primary` — 사용자 원문 / 원본 문서 / raw tool output
- `secondary` — Claude 의 이전 turn 텍스트 / 의역 / 파생 문서

자동 할당:
- jsonl `type: user` → primary
- jsonl `type: assistant` → secondary
- jsonl tool_use Write/Edit content → 선행 user 승인 발언 있으면 primary, 없으면 secondary

### `verification_status` enum

- `verified` — 서로 독립적인 primary ≥ 2 개 일치 (content hash 다름)
- `single-source` — primary 1, 반증 검색 완료, 상충 없음
- `secondary-only` — Claude 자기 이전 발언만 — **수동 재검증 flag**
- `contradicted` — primary ≥ 2, 값 상충 — `contradictions` 배열에 상세

### `evidence` 필드

- `path` — 파일 경로 (절대 또는 repo 상대). transcript 의 경우 jsonl 파일 경로.
- `line` — 라인 번호 (파일) 또는 jsonl line (transcript)
- `timestamp` — iso8601. jsonl 라인의 timestamp 또는 파일 mtime (raw)
- `quote` — 원문 발췌 (최대 500자, 잘린 경우 `...` 로 표시)
- `source_identity` — content hash (SHA-256). 동일 내용의 dedup 키.
- `jsonl_type` (optional) — transcript hit 시 `user | assistant | tool_use`

---

## `contradictions` 배열

primary ≥ 2 상충 시 기록.

```json
[
  {
    "topic": "stall_count 필드 존재 여부",
    "values": [
      {
        "value": "필드 존재",
        "source": { "path": "pipeline-state-schema.md (2026-04-15)",
                    "line": 42, "timestamp": "2026-04-15T10:00:00+09:00" }
      },
      {
        "value": "필드 제거",
        "source": { "path": "pipeline-state-schema.md (2026-04-22)",
                    "line": null, "timestamp": "2026-04-22T09:00:00+09:00" }
      }
    ],
    "resolution": "most_recent_primary",
    "resolution_note": "최신 primary 기준 '제거' 채택. 2026-04-15 버전은 historical."
  }
]
```

### `resolution` enum

- `most_recent_primary` — 시간 축 최신 primary 채택. 대부분의 경우.
- `immutable_override` — INTENTS.md 에 immutable annotation 된 것이 최신 아니어도 override.
- `user_required` — 자동 해결 불가, 사용자 judgment 필요. `autonomous: false` 시 질문 발생.
- `deferred` — 해결 불가 + autonomous=true, 상태 `insufficient` 로 노출.

---

## `missing_actions` 배열

`status: insufficient` 시 추가 수행 필요 명령.

```json
[
  "bash research-scan.sh --keyword '링크드 리스트' --expand-seed 'DAG,barrier,execution_mode'",
  "Ask user for disambiguation: '스택' in context of data-structure vs TLS-stack",
  "Retry git_scan with alternative repo: ~/Documents/workspace/Officeguard/EtapV3"
]
```

소비자 / 사용자가 이 명령을 실행하면 coverage 가 올라가도록 설계.

---

## `promotion_candidates` 배열

조사 결과 중 **미반영** 발견 — 원칙 문서로 승격 후보.

```json
[
  {
    "text": "Batch Linked List methodology: 이중 링크드 리스트 + parallel batch + barrier sync. execution_mode (serial|parallel), barrier_policy (all_done|first_failure_aborts_batch), wrap_as_batch/unwrap_batch edit ops.",
    "target": "INTENTS.md",
    "target_section": "Derived Principles",
    "rationale": "2026-04-21 사용자 승인됨 (transcript line 82 '반영해줘'). 이후 원본 archive + 삭제로 소실. 현재 INTENTS/MEMORY/lessons 어디에도 없음.",
    "strength": "strong",
    "source_evidence": [ { "path": "...", "line": 77, "timestamp": "..." } ]
  }
]
```

### `target` enum

- `INTENTS.md` — 프로젝트 immutable 원칙
- `MEMORY/feedback_*.md` — 사용자 피드백 영구 메모리
- `MEMORY/project_*.md` — 프로젝트 진입 규약
- `lessons.md` — 재발 방지 체크리스트

### `strength` enum

- `strong` — 사용자 명시 승인 있음. 자동 promote 후보.
- `weak` — 사용자 추론된 선호. 명시 확인 필요.

---

## `failed_nodes` 배열

Partial scan 의 상세.

```json
[
  {
    "node_id": "git_scan",
    "reason": "non-git repository",
    "target_path": "~/Documents/workspace/claude_cowork",
    "fallback": "skipped, included as missing_action",
    "severity": "low"
  }
]
```

### `severity` enum

- `low` — 해당 scanner 건너뛰어도 다른 scanner 로 보완 가능
- `medium` — 일부 결과 누락 가능성 있음
- `high` — 핵심 scanner 실패, 결과 신뢰도 저하. `status: partial` 강제.

---

## Schema 진화 정책

- **v1 → v1.x** — 필드 추가만 허용. 기존 필드 의미 변경 금지. 소비자는 모르는 필드 무시.
- **v2** — Backward-incompatible 변경 필요 시. 소비자가 `schema_version` 체크해 자기가 지원하는 버전인지 확인.
- 각 스키마 버전은 독립 문서 유지 (`schema-v1.md`, `schema-v2.md` 등).

---

## 소비자별 활용 예시

### discussion-review Phase 0

```
1. discussion-review 가 research-scan.sh 호출 (consumer=discussion-review)
2. report.json 수령
3. findings 중 verification_status: verified 만 "사전 브리핑" 섹션에 포함
4. contradictions 가 있으면 토론 라운드 논점에 추가
5. promotion_candidates 는 토론 후 참여자 합의로 승격 여부 결정
```

### workflow-retrospective Step 0.5

```
1. 최신 retrospective 파일 키워드로 research-scan.sh 호출
2. findings 중 "이전 제안" 관련 claim 추출
3. coverage 로 adoption 비율 보강 (parse-retro-adoptions.sh 와 crossed)
4. promotion_candidates 에서 회고 주기 간 놓친 승격 식별
```

### cowork-micro-skills-guide 세션 진입

```
1. 세션 시작 시 "last_session_user_directives" 키워드로 scan
2. findings 중 Incident 3 유형 (단일 문서 의존 구두 지시) 자동 검출
3. promotion_candidates 상위 3개를 사용자에게 "promote 확인" 프롬프트로 제시
```
