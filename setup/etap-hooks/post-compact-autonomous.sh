#!/bin/bash
# PostCompact + SessionStart hook: inject autonomous mode reminder + pipeline goal/next_action
# Fires after context compaction — the moment when autonomous rules are most likely forgotten.
#
# Updated 2026-04-27 (discussion-review consensus): Goal injection [GOAL: N/M DONE — K services with autonomous next_action].

PIPELINE_STATE_PRIMARY="/Users/jhee/Documents/workspace/claude_work/projects/apf-operation/state/pipeline_state.json"
PIPELINE_STATE_FALLBACK="/Users/jhee/Documents/workspace/dev_test_sync/local_archive/pipeline_state.json"

# Choose primary if exists, fallback else
if [ -f "$PIPELINE_STATE_PRIMARY" ]; then
  PIPELINE_STATE="$PIPELINE_STATE_PRIMARY"
elif [ -f "$PIPELINE_STATE_FALLBACK" ]; then
  PIPELINE_STATE="$PIPELINE_STATE_FALLBACK"
else
  PIPELINE_STATE=""
fi

GOAL_LINE=""
NEXT_ACTION_LINE=""
CURRENT_SERVICE=""

if [ -n "$PIPELINE_STATE" ] && [ -f "$PIPELINE_STATE" ]; then
  GOAL_INFO=$(python3 <<'PYEOF' 2>/dev/null
import json, os
path = os.environ.get('PS_PATH')
try:
    s = json.load(open(path))
    done = len(s.get('done_services', []))
    total = s.get('classification_summary', {}).get('total_registered', 37)
    queue = s.get('service_queue', [])
    autonomous = [e for e in queue if not str(e.get('next_action','')).startswith('defer:') and e.get('next_action')]
    cur = s.get('current_service', '')

    print(f"[GOAL: {done}/{total} services DONE | {len(autonomous)} autonomous-doable next_action(s) in queue]")
    if autonomous:
        top3 = autonomous[:3]
        line = "; ".join(f"{e['service']}:{e['next_action']}" for e in top3)
        print(f"NEXT autonomous candidates (top 3): {line}")
    else:
        print("NO autonomous-doable next_action — long-idle permitted with itemized defer report")
    print(f"current_service={cur}")
except Exception as e:
    print(f"[GOAL: unavailable - {e}]")
    print("")
    print("")
PYEOF
)
  PS_PATH="$PIPELINE_STATE" GOAL_LINE=$(PS_PATH="$PIPELINE_STATE" python3 <<'PYEOF' 2>/dev/null
import json, os
path = os.environ.get('PS_PATH')
try:
    s = json.load(open(path))
    done = len(s.get('done_services', []))
    total = s.get('classification_summary', {}).get('total_registered', 37)
    queue = s.get('service_queue', [])
    autonomous = [e for e in queue if not str(e.get('next_action','')).startswith('defer:') and e.get('next_action')]
    print(f"[GOAL: {done}/{total} DONE | {len(autonomous)} autonomous-doable next_action]")
except Exception:
    print("[GOAL: unavailable]")
PYEOF
)
  NEXT_ACTION_LINE=$(PS_PATH="$PIPELINE_STATE" python3 <<'PYEOF' 2>/dev/null
import json, os
path = os.environ.get('PS_PATH')
try:
    s = json.load(open(path))
    queue = s.get('service_queue', [])
    autonomous = [e for e in queue if not str(e.get('next_action','')).startswith('defer:') and e.get('next_action')]
    if autonomous:
        top3 = autonomous[:3]
        print("NEXT (top 3): " + "; ".join(f"{e['service']}=>{e['next_action']}" for e in top3))
    else:
        print("Queue has no autonomous-doable next_action — itemized defer report required before long-idle")
except Exception:
    print("")
PYEOF
)
fi

cat <<HOOKJSON
{
  "systemMessage": "AUTONOMOUS MODE ACTIVE. ${GOAL_LINE} ${NEXT_ACTION_LINE}\n\nHARD RULES: (1) 질문으로 끝맺기 금지 (2) 상태 정리만 하고 멈추기 금지 (3) 폴링 체인 끊기 금지 (4) 선언 후 멈추기 금지 (5) idle 대기 금지 (6) 선택지 제시 금지→Empirical (7) Idle Gate: long-idle = autonomous_doable count==0 증명 후만. Premature completion 차단: cycle summary 작성 ≠ 종료, 목표 미달성 시 다음 push.\n\nWork Selection v2: pop autonomous next_action → execute → update queue. Empty next_action with non-defer = bug, audit. All defer: = explicit 'needs_user_input' itemized report."
}
HOOKJSON
