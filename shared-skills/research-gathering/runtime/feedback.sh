#!/bin/bash
# feedback.sh — research-gathering skill learning loop
#
# 사용자·소비자·Claude 가 scan 결과의 누락을 발견했을 때 구조화 report.
# 본 스크립트는 incident_registry.jsonl 에 append-only 로 기록.
# 기존 record 수정 금지.
#
# 사용:
#   bash feedback.sh --report-incident "<description>" \
#        --missed-keyword "<what>" \
#        --expected-tier "<filesystem|git|memory|transcript>" \
#        --root-cause "<why>" \
#        [--session-id <id>] [--query-id <id>]

set -eu

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REGISTRY="$SKILL_DIR/runtime/incident_registry.jsonl"

DESCRIPTION=""
MISSED_KEYWORD=""
EXPECTED_TIER=""
ROOT_CAUSE=""
SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"
QUERY_ID=""

while [ $# -gt 0 ]; do
  case "$1" in
    --report-incident)  DESCRIPTION="$2"; shift 2 ;;
    --missed-keyword)   MISSED_KEYWORD="$2"; shift 2 ;;
    --expected-tier)    EXPECTED_TIER="$2"; shift 2 ;;
    --root-cause)       ROOT_CAUSE="$2"; shift 2 ;;
    --session-id)       SESSION_ID="$2"; shift 2 ;;
    --query-id)         QUERY_ID="$2"; shift 2 ;;
    --help|-h)
      cat <<USAGE
Usage: bash feedback.sh --report-incident "<desc>" \
   --missed-keyword "<what>" \
   --expected-tier "<tier>" \
   --root-cause "<why>" \
   [--session-id <id>] [--query-id <id>]

Required:
  --report-incident   incident 설명 (자유 텍스트)
  --missed-keyword    scan 이 놓친 키워드/개념
  --expected-tier     어느 tier 에서 발견됐어야 하는지 (filesystem|git|memory|transcript)
  --root-cause        근본 원인 (짧게)

Optional:
  --session-id        현재 세션 ID (default: env CLAUDE_SESSION_ID)
  --query-id          관련 research-run query_id

Output:
  incident_registry.jsonl 에 append
  stdout 에 incident_id + 다음 단계 안내
USAGE
      exit 0 ;;
    *) echo "[feedback] unknown arg: $1" >&2; exit 2 ;;
  esac
done

for v in DESCRIPTION MISSED_KEYWORD EXPECTED_TIER ROOT_CAUSE; do
  eval "val=\$$v"
  if [ -z "$val" ]; then
    echo "[feedback] --${v,,} required" >&2
    exit 2
  fi
done

case "$EXPECTED_TIER" in
  filesystem|git|memory|transcript) ;;
  *) echo "[feedback] --expected-tier must be one of: filesystem, git, memory, transcript" >&2
     exit 2 ;;
esac

# Append to registry (JSON line)
INCIDENT_ID=$(python3 -c 'import uuid; print(uuid.uuid4().hex[:12])')
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S+00:00")

python3 - <<PY
import json
record = {
    "incident_id": """$INCIDENT_ID""",
    "timestamp": """$TIMESTAMP""",
    "description": """$DESCRIPTION""",
    "missed_keyword": """$MISSED_KEYWORD""",
    "expected_tier": """$EXPECTED_TIER""",
    "root_cause": """$ROOT_CAUSE""",
    "session_id": """$SESSION_ID""",
    "query_id": """$QUERY_ID""" or None,
    "reviewed_by_user": False,
    "promoted_to_incident_log_md": False,
    "added_to_expand_dict": False,
    "added_to_scanner_paths": False
}
with open("""$REGISTRY""", "a") as f:
    f.write(json.dumps(record, ensure_ascii=False) + "\n")
PY

echo "[feedback] incident_id=$INCIDENT_ID appended to $REGISTRY"
echo ""
echo "다음 단계 (사용자 / 운영자 수동 처리):"
echo "  1. references/incident-log.md 에 'Incident N' 섹션 수동 작성 (append-only)"
echo "  2. 원인이 keyword 확장 누락이면 runtime/nodes/keyword_expand.py 의 seed dict 에 추가"
echo "  3. 원인이 scanner path 누락이면 해당 scanner node 의 path list 에 추가"
echo "  4. bash self-test.sh 재실행 (regression test 에 편입 확인)"
echo ""
echo "템플릿 (incident-log.md 에 복붙용):"
cat <<TMPL

---

## Incident $(date +%Y%m%d)-${INCIDENT_ID:0:4} — $DESCRIPTION

**발생**: $TIMESTAMP

**Missed keyword**: \`$MISSED_KEYWORD\`
**Expected tier**: $EXPECTED_TIER
**Root cause**: $ROOT_CAUSE

**본 skill 의 대응**:
(여기에 수정 사항 기입 — 예: "keyword_expand dict 에 X 추가", "filesystem_scan path 에 Y 추가")

TMPL
