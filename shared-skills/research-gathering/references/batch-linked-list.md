# Batch Linked List — 내부 실행 구조 상세

본 문서는 research-gathering skill 의 내부 실행 구조를 정의. 2026-04-21 transcript (line 66-117) 의 원 설계를 본 skill 에 이식한 것.

---

## 구조 개요

```
HEAD
 → keyword_expand_loop       (serial, max 3 iter)
 → BATCH{ git_scan ∥ memory_scan ∥ filesystem_scan }    [barrier: all_done]
 → transcript_scan           (solo, long-running)
 → aggregate_dedup           (serial)
 → contradiction_check       (serial)
 → promotion_suggest         (serial)
TAIL
```

각 노드는 `kind` ("unit" | "batch") 와 `status` (PENDING | RUNNING | DONE | FAILED) 를 가진 이중 linked list 의 원소.

---

## 노드 유형

### Unit 노드 (단일 작업)

```json
{
  "kind": "unit",
  "node_id": "keyword_expand_loop",
  "status": "PENDING",
  "prev": null,
  "next": "main_batch",
  "command": "python3 nodes/keyword_expand.py --keyword '{keyword}'",
  "output_ref": ".research-run/{query_id}/outputs/keyword_expand_loop/"
}
```

### Batch 노드 (병렬 배치)

```json
{
  "kind": "batch",
  "node_id": "main_batch",
  "status": "RUNNING",
  "prev": "keyword_expand_loop",
  "next": "transcript_scan",
  "barrier_policy": "all_done",
  "children": [
    { "unit_id": "git_scan",        "status": "DONE",    "output_ref": ".../git_scan.json" },
    { "unit_id": "memory_scan",     "status": "DONE",    "output_ref": ".../memory_scan.json" },
    { "unit_id": "filesystem_scan", "status": "RUNNING", "output_ref": null }
  ]
}
```

---

## 배치 설계 불변식

### Homogeneous batch (동질 배치)

한 배치 안의 children 은 시간복잡도가 비슷해야 함.

- git_scan, memory_scan, filesystem_scan — 모두 수 초 이내, 동질 batch OK
- transcript_scan — 10MB+ jsonl, 수십 초 ~ 분. 동질 아님 → 별도 solo 노드

이 규칙을 위반하면 빠른 scanner 가 느린 scanner 완료를 barrier 에서 대기하며 낭비.

### Long-running solo (장시간 독점)

분 단위 이상 걸릴 수 있는 작업은 **단독 노드** 로 분리. transcript_scan 이 대표 예.

### One-level fanout only

배치 children 간 **의존성 없음** 이 불변식. children 중 하나가 다른 children 의 출력을 필요로 하면 batch 아닌 serial 로 분리.

이 불변식이 단일 커서 + O(1) 국소 편집을 지킴. "DAG 가 아닌 이유".

---

## Barrier 정책

### `all_done` (v1 기본값)

모든 child 의 status 가 DONE 또는 FAILED 될 때까지 대기. 이후:
- 하나라도 FAILED → batch status = FAILED, `failed_nodes` 에 기록
- 모두 DONE → batch status = DONE

### `first_failure_aborts_batch` (고속 실패 필요 시)

child 한 개가 FAILED 되는 즉시 진행 중 다른 children 중단, batch FAILED 전이.

v1 의 main_batch 는 `all_done` 사용 — scanner 하나 실패해도 다른 scanner 결과는 유효 (partial status 로 보고).

---

## 실행 루프 (pseudocode)

```
load plan.json
load stack.json  # resume cursor

while plan.has_pending():
    node = plan.peek_next_pending()
    push_stack(node)
    node.status = RUNNING

    if node.kind == "unit":
        run node.command
        save output to node.output_ref
        node.status = DONE | FAILED
    elif node.kind == "batch":
        dispatch_all_children_in_parallel()   # 한 turn 안에서 multiple tool calls
        wait_barrier(node.barrier_policy)
        aggregate children status → node.status

    save plan.json
    save stack.json

    if node.status == FAILED and node.kind != "batch_all_done":
        break  # to error handler

    pop_stack()
    plan.advance_cursor()
```

### Compact 이후 재개

세션 compact 시 execution 이 중단되면:
1. 새 Claude 가 `.research-run/{query_id}/plan.json` 을 Read
2. `stack.json` 에서 마지막 실행 중이던 명령 확인
3. plan 에서 non-DONE 노드만 찾아 재실행
4. 이전 DONE 노드 output 은 건드리지 않음

이 구조가 criterion "컨텍스트 손실 방지" 를 구조적으로 해결.

---

## 편집 연산 (Plan 수정)

> **v1 not exposed at runtime** — 아래 연산은 4/21 Batch Linked List 설계의 공식 interface 이며, 본 문서는 spec 정의 문서. v1 skill 은 이들을 runtime callable API 로 노출하지 않음. 실행 중 plan 수정 필요 사례는 `report.json` 의 `missing_actions` 로 후속 명령 제안 → 사용자 재호출. 2026-04-22 토론 consensus: `feedback.sh --report-incident` 가 `missing_actions` 방식으로 해결되지 않는 구체 사례를 기록할 때 v1.1 에서 runtime API 구현.

실행 중 또는 실행 전 plan.json 에 대해 허용된 diff-level 편집 (spec):

| 연산 | 의미 | 제약 |
|------|------|------|
| `insert_after(anchor, new_node)` | anchor 뒤에 새 노드 삽입 | anchor 가 TAIL 아닐 것 |
| `insert_before(anchor, new_node)` | anchor 앞에 새 노드 삽입 | anchor 가 HEAD 아닐 것 |
| `remove(node)` | 노드 제거 | status=DONE 인 노드는 제거 불가 |
| `replace(old, new)` | old 를 new 로 교체 | old 가 PENDING 이어야 함 |
| `reorder(a, b)` | a, b 순서 교환 | 둘 다 PENDING 이어야 함 |
| `reset_to_pending(node)` | FAILED/DONE → PENDING | output 파일은 유지 (재실행 시 overwrite) |
| `wrap_as_batch([n1, n2, ...])` | 독립 · 동질 unit 들을 batch 로 묶기 | nodes 간 dependency 없음 확인 필요 |
| `unwrap_batch(batch)` | batch → 개별 unit serial | 배치 내 children 이 완료 전이어야 |
| `add_to_batch(batch, unit)` | 기존 batch 에 child 추가 | batch status = PENDING |
| `remove_from_batch(batch, unit)` | batch 에서 child 제거 | child status = PENDING |

**전체 재작성 금지**. 항상 diff-level 편집.

---

## 언제 plan 을 편집하나 (운영 예시)

### 예시 1 — keyword expand 가 새 키워드 발견
```
keyword_expand_loop iter 1 결과: ['batch linked list', 'execution_mode']
→ main_batch 의 git_scan 재실행 필요 (새 키워드로)
→ reset_to_pending(git_scan)
→ iter 2 실행
```

### 예시 2 — transcript_scan 에서 새 경로 발견
```
transcript_scan 결과: 다른 프로젝트 경로 `/Users/jhee/Documents/workspace/Officeguard/EtapV3/` 언급 확인
→ insert_after(transcript_scan, { "kind": "unit", "node_id": "etap_scan", "command": "grep -r ... etap_v3_root" })
→ 새 노드 실행
```

### 예시 3 — 부분 실패 복구
```
filesystem_scan FAILED (permission denied)
→ 즉시 전체 실패 아님 (barrier_policy: all_done, 다른 children 완료 대기)
→ insert_after(main_batch, { "kind": "unit", "node_id": "filesystem_scan_sudo_retry", "command": "...sudo..." })
→ 단, sudo 사용은 사용자 승인 필요 (missing_actions 에 추가만, 자동 실행 아님)
```

---

## State 파일 구조

### plan.json

```json
{
  "schema_version": 1,
  "query_id": "<uuid>",
  "iteration": 2,
  "head": "keyword_expand_loop",
  "tail": "promotion_suggest",
  "cursor": "transcript_scan",
  "nodes": {
    "keyword_expand_loop": { "kind": "unit", ..., "status": "DONE", ... },
    "main_batch":          { "kind": "batch", ..., "status": "DONE", ... },
    "transcript_scan":     { "kind": "unit", ..., "status": "RUNNING", ... },
    "aggregate_dedup":     { "kind": "unit", ..., "status": "PENDING", ... },
    "contradiction_check": { "kind": "unit", ..., "status": "PENDING", ... },
    "promotion_suggest":   { "kind": "unit", ..., "status": "PENDING", ... }
  },
  "edit_history": [
    { "iteration": 1, "op": "insert_after",
      "anchor": "keyword_expand_loop", "new": "main_batch",
      "reason": "initial plan construction" }
  ]
}
```

### stack.json

```json
{
  "schema_version": 1,
  "query_id": "<uuid>",
  "current_node": "transcript_scan",
  "command": "python3 nodes/transcript_scan.py --keyword '링크드 리스트' --expanded 'batch linked list,execution_mode'",
  "cwd": "/Users/jhee/Documents/workspace/dev_test_sync/shared-skills/research-gathering",
  "started_at": "2026-04-22T14:55:00+09:00",
  "pid": 12345
}
```

**pid 기록**: compact 이후 재개 시 이 pid 가 살아있는지 확인 → 살아있으면 기다림, 죽었으면 재실행.

---

## 왜 이 구조인가 (설계 근거)

**대안 검토** (2026-04-21 transcript line 71 의 DAG vs Linked List 비교):

| 차원 | Linked List (+ batch) | Full DAG |
|------|---------------------|----------|
| 병렬성 | ✓ (배치 내) | ✓ (의존성 충족 즉시) |
| 편집 비용 | O(1) 국소 | 엣지 재계산 |
| 단일 커서 | ✓ | ✗ (노드별 상태 맵) |
| Resumability | ✓ (커서 + 배치 부분완료) | △ (부분 상태 복원 복잡) |
| Claude turn 구조 정합 | ✓ ("한 turn = 배치") | △ (tool call 경계와 DAG 경계 불일치) |
| 사이클 안전성 | 구조적 불가 | 별도 감지 필요 |

결론: 본 skill 은 **Claude 단일 세션 + compact 대응 + 편집 단순성** 이 핵심. Linked List + batch 가 파레토 최적.

**전체 DAG 가 필요한 경우 없음**: 본 skill 의 scanner 들은 독립이므로 복잡한 fan-in 불필요. barrier 하나로 충분.
