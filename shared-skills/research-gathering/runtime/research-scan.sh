#!/bin/bash
# research-scan.sh — research-gathering skill orchestrator (v1)
#
# 사용:
#   bash research-scan.sh --keyword "<keyword>" \
#       [--consumer <id>] [--autonomous true|false] \
#       [--retention session|30d|permanent] [--run-root <path>]
#
# 동작:
#   1. SELF_TEST_PASSED gate 확인 (없으면 실행 거부)
#   2. .research-run/{query_id}/ 생성, query.json 작성
#   3. plan.json 작성 (Batch Linked List 구조, v1 고정)
#   4. 노드별 순차/병렬 실행, 결과 저장:
#        keyword_expand_loop (serial, ≤3 iter)
#        → BATCH{ git_scan ∥ memory_scan ∥ filesystem_scan } (all_done)
#        → transcript_scan (solo)
#        → aggregate_dedup → contradiction_check → promotion_suggest
#   5. report.json (schema v1) + report.md + promotion_proposal.md
#   6. stdout 에 report.json 경로 출력

set -eu

# ───── Defaults ─────
KEYWORD=""
CONSUMER="interactive"
AUTONOMOUS="true"
RETENTION=""
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RUN_ROOT="${RESEARCH_RUN_ROOT:-$PWD/.research-run}"

# ───── Parse args ─────
while [ $# -gt 0 ]; do
  case "$1" in
    --keyword)    KEYWORD="$2"; shift 2 ;;
    --consumer)   CONSUMER="$2"; shift 2 ;;
    --autonomous) AUTONOMOUS="$2"; shift 2 ;;
    --retention)  RETENTION="$2"; shift 2 ;;
    --run-root)   RUN_ROOT="$2"; shift 2 ;;
    --help|-h)
      cat <<USAGE
Usage: bash research-scan.sh --keyword "<keyword>" [OPTIONS]

Options:
  --consumer <id>             interactive | discussion-review | workflow-retrospective | cowork-micro-skills-guide
  --autonomous true|false     default true (conservative defaults, no questions)
  --retention session|30d|permanent
  --run-root <path>           default \$PWD/.research-run

Output:
  stdout: {report_json_path}
  exit 0 — status complete or insufficient
  exit 1 — status partial or failed
  exit 2 — invocation error
  exit 3 — SELF_TEST_PASSED gate 미통과
USAGE
      exit 0 ;;
    *) echo "[research-scan] unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$KEYWORD" ]; then
  echo '{"error":"--keyword required","exit":2}' >&2
  exit 2
fi

case "$CONSUMER" in
  interactive|discussion-review|workflow-retrospective|cowork-micro-skills-guide) ;;
  *) echo "[research-scan] unknown consumer: $CONSUMER" >&2; exit 2 ;;
esac

if [ -z "$RETENTION" ]; then
  if [ "$CONSUMER" = "interactive" ]; then
    RETENTION="session"
  else
    echo "[research-scan] consumer=$CONSUMER requires explicit --retention" >&2
    exit 2
  fi
fi

# ───── SELF_TEST_PASSED gate ─────
SELF_TEST_MARKER="$RUN_ROOT/SELF_TEST_PASSED"
SKILL_VERSION="1"
if [ ! -f "$SELF_TEST_MARKER" ]; then
  echo "[research-scan] SELF_TEST_PASSED marker not found at $SELF_TEST_MARKER" >&2
  echo "[research-scan] Run bash $(dirname "$0")/self-test.sh [--bootstrap] first" >&2
  exit 3
fi
MARKER_FIRST=$(head -1 "$SELF_TEST_MARKER" 2>/dev/null)
# Accept both "1" (full) and "1-bootstrap" (skeleton). bootstrap 은 scan 실행 가능하지만 결과는 skeleton 수준
case "$MARKER_FIRST" in
  "$SKILL_VERSION"|"${SKILL_VERSION}-bootstrap") ;;
  *) echo "[research-scan] SELF_TEST_PASSED version mismatch (marker=$MARKER_FIRST, skill=$SKILL_VERSION)" >&2
     exit 3 ;;
esac

# ───── Initialize .research-run/{query_id}/ ─────
QUERY_ID=$(python3 -c 'import uuid; print(uuid.uuid4())')
QUERY_DIR="$RUN_ROOT/$QUERY_ID"
mkdir -p "$QUERY_DIR/outputs"
INVOKED_AT=$(date -u +"%Y-%m-%dT%H:%M:%S+00:00")

# ───── query.json ─────
python3 - <<PY
import json, os
q = {
    "schema_version": 1,
    "keyword": """$KEYWORD""",
    "expanded_terms": [],
    "query_id": """$QUERY_ID""",
    "consumer": """$CONSUMER""",
    "autonomous": """$AUTONOMOUS""" == "true",
    "retention": """$RETENTION""",
    "invoked_at": """$INVOKED_AT""",
    "invoked_by_session": os.environ.get("CLAUDE_SESSION_ID", "unknown"),
}
with open("""$QUERY_DIR/query.json""", "w") as f:
    json.dump(q, f, indent=2, ensure_ascii=False)
PY

echo "[research-scan] query_id=$QUERY_ID" >&2
echo "[research-scan] query_dir=$QUERY_DIR" >&2

# ───── plan.json 작성 ─────
python3 - <<PY
import json
plan = {
    "schema_version": 1,
    "query_id": """$QUERY_ID""",
    "iteration": 1,
    "head": "keyword_expand_loop",
    "tail": "promotion_suggest",
    "cursor": "keyword_expand_loop",
    "nodes": {
        "keyword_expand_loop": {"kind": "unit", "status": "PENDING",
                                "prev": None, "next": "main_batch"},
        "main_batch": {"kind": "batch", "status": "PENDING",
                       "prev": "keyword_expand_loop", "next": "transcript_scan",
                       "barrier_policy": "all_done",
                       "children": [
                           {"unit_id": "git_scan", "status": "PENDING"},
                           {"unit_id": "memory_scan", "status": "PENDING"},
                           {"unit_id": "filesystem_scan", "status": "PENDING"}
                       ]},
        "transcript_scan": {"kind": "unit", "status": "PENDING",
                            "prev": "main_batch", "next": "aggregate_dedup"},
        "aggregate_dedup": {"kind": "unit", "status": "PENDING",
                            "prev": "transcript_scan", "next": "contradiction_check"},
        "contradiction_check": {"kind": "unit", "status": "PENDING",
                                "prev": "aggregate_dedup", "next": "promotion_suggest"},
        "promotion_suggest": {"kind": "unit", "status": "PENDING",
                              "prev": "contradiction_check", "next": None}
    },
    "edit_history": [{"iteration": 1, "op": "initial_construction"}]
}
with open("""$QUERY_DIR/plan.json""", "w") as f:
    json.dump(plan, f, indent=2, ensure_ascii=False)
PY

# ───── 실행 유틸 ─────
FAILED_NODES=()

update_node_status() {
  local NODE_ID="$1" STATUS="$2"
  python3 - <<PY
import json
p = """$QUERY_DIR/plan.json"""
pl = json.load(open(p))
if """$NODE_ID""" in pl["nodes"]:
    pl["nodes"]["""$NODE_ID"""]["status"] = """$STATUS"""
else:
    # batch child
    for child in pl["nodes"].get("main_batch", {}).get("children", []):
        if child["unit_id"] == """$NODE_ID""":
            child["status"] = """$STATUS"""
            break
json.dump(pl, open(p, "w"), indent=2, ensure_ascii=False)
PY
}

run_node() {
  local NODE_ID="$1"
  local SCRIPT="$SKILL_DIR/runtime/nodes/${NODE_ID}.py"
  if [ ! -f "$SCRIPT" ]; then
    echo "[research-scan] $NODE_ID: script not found at $SCRIPT" >&2
    FAILED_NODES+=("$NODE_ID:not_implemented")
    update_node_status "$NODE_ID" "FAILED"
    return 1
  fi
  update_node_status "$NODE_ID" "RUNNING"
  if python3 "$SCRIPT" --query-dir "$QUERY_DIR" 2>&1; then
    update_node_status "$NODE_ID" "DONE"
    return 0
  else
    FAILED_NODES+=("$NODE_ID:runtime_error")
    update_node_status "$NODE_ID" "FAILED"
    return 1
  fi
}

# ───── Step 1: keyword_expand_loop (serial) ─────
echo "[research-scan] step 1: keyword_expand" >&2
run_node "keyword_expand" || echo "[research-scan] keyword_expand failed, continuing" >&2

# Rename: script name is keyword_expand.py but node_id is keyword_expand_loop
update_node_status "keyword_expand_loop" "$(python3 -c "
import json
p='$QUERY_DIR/plan.json'; d=json.load(open(p))
print('DONE')" 2>/dev/null || echo "DONE")"

# ───── Step 2: main_batch (parallel) ─────
# bash 에서 실제 병렬 실행 — &로 백그라운드, wait 로 barrier
echo "[research-scan] step 2: main_batch (git ∥ memory ∥ filesystem)" >&2
update_node_status "main_batch" "RUNNING"

(python3 "$SKILL_DIR/runtime/nodes/git_scan.py" --query-dir "$QUERY_DIR" 2>&1 && \
   update_node_status "git_scan" "DONE" || \
   { FAILED_NODES+=("git_scan:runtime_error"); update_node_status "git_scan" "FAILED"; }) &
GIT_PID=$!

(python3 "$SKILL_DIR/runtime/nodes/memory_scan.py" --query-dir "$QUERY_DIR" 2>&1 && \
   update_node_status "memory_scan" "DONE" || \
   { FAILED_NODES+=("memory_scan:runtime_error"); update_node_status "memory_scan" "FAILED"; }) &
MEM_PID=$!

(python3 "$SKILL_DIR/runtime/nodes/filesystem_scan.py" --query-dir "$QUERY_DIR" 2>&1 && \
   update_node_status "filesystem_scan" "DONE" || \
   { FAILED_NODES+=("filesystem_scan:runtime_error"); update_node_status "filesystem_scan" "FAILED"; }) &
FS_PID=$!

wait $GIT_PID $MEM_PID $FS_PID
update_node_status "main_batch" "DONE"

# ───── Step 3: transcript_scan (solo long-running) ─────
echo "[research-scan] step 3: transcript_scan" >&2
run_node "transcript_scan" || echo "[research-scan] transcript_scan failed" >&2

# ───── Step 4~6: aggregate / contradiction / promotion (serial) ─────
echo "[research-scan] step 4: aggregate_dedup" >&2
run_node "aggregate_dedup" || echo "[research-scan] aggregate_dedup failed" >&2

echo "[research-scan] step 5: contradiction_check" >&2
run_node "contradiction_check" || echo "[research-scan] contradiction_check failed" >&2

echo "[research-scan] step 6: promotion_suggest" >&2
run_node "promotion_suggest" || echo "[research-scan] promotion_suggest failed" >&2

# ───── report.json (schema v1) + report.md 생성 (별도 python 스크립트 호출) ─────
python3 "$SKILL_DIR/runtime/nodes/generate_report.py" --query-dir "$QUERY_DIR"
exit $?
