#!/bin/bash
# PostToolUse hook — Idle Watchdog
# Detects long-idle pattern (only ScheduleWakeup + Bash(git pull) repeating)
# and emits system-reminder if service_queue has autonomous-doable next_action items.
#
# Per autonomous-execution-protocol.md §Hard Rule 7 (Idle Gate, 2026-04-27 discussion-review consensus).
#
# State file: /tmp/apf-watchdog-state.json
# Schema: {"idle_tick_count": N, "last_action_ts": "ISO8601", "last_significant_action": "Bash|Edit|Write"}

set -e

STATE_FILE="/tmp/apf-watchdog-state.json"
PIPELINE_STATE="/Users/jhee/Documents/workspace/claude_work/projects/apf-operation/state/pipeline_state.json"
IDLE_THRESHOLD=3  # consecutive idle ticks before warn

# Read tool info from stdin (Claude Code passes JSON)
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null || echo "")

# Initialize state file if missing
if [ ! -f "$STATE_FILE" ]; then
  echo '{"idle_tick_count":0,"last_action_ts":"","last_significant_action":""}' > "$STATE_FILE"
fi

# Classify tool call
IS_IDLE_PATTERN="false"
case "$TOOL_NAME" in
  "ScheduleWakeup")
    IS_IDLE_PATTERN="true"
    ;;
  "Bash")
    # Bash with only git-pull / git-status / ls = idle pattern
    CMD=$(echo "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")
    if echo "$CMD" | grep -qE '^(git -C [^ ]+ pull|git pull|ls /Users/jhee/Documents/workspace/dev_test_sync/results)' ; then
      IS_IDLE_PATTERN="true"
    fi
    ;;
  "TodoWrite"|"Read")
    # neutral — neither idle nor significant
    exit 0
    ;;
  "Edit"|"Write"|"NotebookEdit")
    IS_IDLE_PATTERN="false"
    ;;
esac

# Update state
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
if [ "$IS_IDLE_PATTERN" = "true" ]; then
  # increment idle counter
  python3 -c "
import json
s = json.load(open('$STATE_FILE'))
s['idle_tick_count'] = s.get('idle_tick_count', 0) + 1
s['last_action_ts'] = '$NOW'
json.dump(s, open('$STATE_FILE','w'))
"
elif [ "$IS_IDLE_PATTERN" = "false" ] && [ -n "$TOOL_NAME" ]; then
  # significant action — reset counter
  python3 -c "
import json
s = json.load(open('$STATE_FILE'))
s['idle_tick_count'] = 0
s['last_action_ts'] = '$NOW'
s['last_significant_action'] = '$TOOL_NAME'
json.dump(s, open('$STATE_FILE','w'))
"
  exit 0
else
  exit 0
fi

# Read current idle count
IDLE_COUNT=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('idle_tick_count',0))")

# Threshold check
if [ "$IDLE_COUNT" -lt "$IDLE_THRESHOLD" ]; then
  exit 0
fi

# At threshold — check if service_queue has autonomous-doable next_action
if [ ! -f "$PIPELINE_STATE" ]; then
  exit 0
fi

AUTONOMOUS_CANDIDATES=$(python3 -c "
import json
try:
    s = json.load(open('$PIPELINE_STATE'))
    queue = s.get('service_queue', [])
    cands = [e for e in queue if not e.get('next_action','').startswith('defer:') and e.get('next_action')]
    print(len(cands))
    print('|'.join(f\"{e['service']}:{e['next_action']}\" for e in cands[:5]))
except Exception:
    print(0)
    print('')
")

CAND_COUNT=$(echo "$AUTONOMOUS_CANDIDATES" | head -1)
CAND_LIST=$(echo "$AUTONOMOUS_CANDIDATES" | tail -1)

if [ "$CAND_COUNT" -gt 0 ]; then
  # Emit system-reminder
  cat <<HOOKJSON
{
  "systemMessage": "[WATCHDOG] Idle Gate triggered: ${IDLE_COUNT} consecutive idle ticks (only polling/git-pull). service_queue has ${CAND_COUNT} autonomous-doable next_action(s): ${CAND_LIST}. Per Hard Rule 7: long-idle prohibited when autonomous candidates exist. Pop next_action and execute now, OR explicit per-candidate rejection rationale required."
}
HOOKJSON
  # Reset counter to avoid spamming
  python3 -c "
import json
s = json.load(open('$STATE_FILE'))
s['idle_tick_count'] = 0
json.dump(s, open('$STATE_FILE','w'))
"
fi

exit 0
