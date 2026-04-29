#!/bin/bash
# Stop hook — Autonomous-Doable Guard
#
# Fires when Claude finishes response without invoking another tool.
# Detects "stop with pending autonomous-doable tasks" pattern (cycle95 incident, 2026-04-28).
#
# Logic:
# 1. Read pipeline_state.json service_queue
# 2. Count entries where next_action does NOT start with: defer:, terminate:, infra_blocked:
#    + status NOT IN: NEEDS_LOGIN, TERMINAL_UNREACHABLE, DONE
#    → autonomous_candidates count
# 3. Read input JSON for transcript_path; scan last user message for termination keywords
# 4. If candidates > 0 AND no termination keyword AND not stop_hook_active (avoid loop):
#    Emit JSON with decision="block" + reason → forces Claude to continue
#
# Hook event: Stop (Claude Code)
# Per autonomous-execution-protocol.md HR7 + 22차 D16(a) discussion-review consensus.
# 24차 refined: keyword list narrowed to genuine termination intent (incident 8 — 보고/summarize 가 status-update request 인데 termination 으로 misclassified).
#
# Termination keywords (case-insensitive substring match in last user message):
#   - Strong stop: stop / halt / quit / 정지 / 종료 / 그만 / 그만해 / 끝
#   - Pause (still allow stop): wait / pause / 잠시 / 잠깐
# REMOVED 24차 (status-update requests, not termination intent):
#   - 보고해 / 보고 / summarize / 검토 / 일단
# Rationale: "보고해" alone = status update request (사용자가 polling 중간 보고 받고 다시 진행 의도).
# 진짜 stop 은 "그만/stop/종료/끝" 등 명시적 keyword. Last-mile result scan 의무는 별도 (G1 below).

set -e

PIPELINE_STATE="/Users/jhee/Documents/workspace/claude_work/projects/apf-operation/state/pipeline_state.json"
LOG="/tmp/stop-autonomous-guard.log"

# Read input JSON from Claude Code (transcript_path + stop_hook_active)
INPUT=$(cat)

# Parse stop_hook_active to prevent infinite loops
STOP_HOOK_ACTIVE=$(echo "$INPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('stop_hook_active', False))" 2>/dev/null || echo "False")

if [ "$STOP_HOOK_ACTIVE" = "True" ]; then
    # Already in stop-hook re-engagement loop; don't recurse
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [skip — stop_hook_active=True]" >> "$LOG"
    exit 0
fi

# Count autonomous_candidates
if [ ! -f "$PIPELINE_STATE" ]; then
    # No pipeline state file — not in APF context, skip
    exit 0
fi

CANDIDATES=$(python3 << PYEOF
import json
try:
    with open("$PIPELINE_STATE") as f:
        s = json.load(f)
    queue = s.get('service_queue', [])
    autonomous = []
    for e in queue:
        st = e.get('status', '')
        na = e.get('next_action', '')
        # Skip terminal/login states
        if st in ('NEEDS_LOGIN', 'TERMINAL_UNREACHABLE', 'DONE'):
            continue
        # Skip explicit defer/terminate/infra_blocked
        if not isinstance(na, str):
            continue
        if na.startswith(('defer:', 'terminate:', 'infra_blocked:')):
            continue
        autonomous.append((e.get('service', '?'), na))
    # Output count + first 5 service:next_action pairs
    print(len(autonomous))
    for svc, na in autonomous[:5]:
        print(f"  {svc}: {na}")
except Exception as ex:
    print(0)
PYEOF
)

COUNT=$(echo "$CANDIDATES" | head -1)
TASKS=$(echo "$CANDIDATES" | tail -n +2)

# If no candidates, allow stop
if [ "$COUNT" = "0" ]; then
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [allow stop — no autonomous candidates]" >> "$LOG"
    exit 0
fi

# Check last user message for termination keywords
TRANSCRIPT_PATH=$(echo "$INPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('transcript_path',''))" 2>/dev/null || echo "")

LAST_USER_MSG=""
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    # Read last user message from transcript (JSONL format)
    LAST_USER_MSG=$(python3 << PYEOF
import json
last = ""
try:
    with open("$TRANSCRIPT_PATH") as f:
        for line in f:
            try:
                obj = json.loads(line)
                # Find last user message (role=user, type=message)
                if obj.get('type') == 'user' or obj.get('role') == 'user':
                    msg = obj.get('message', {})
                    if isinstance(msg, dict):
                        content = msg.get('content', '')
                    else:
                        content = msg
                    if isinstance(content, list):
                        for c in content:
                            if isinstance(c, dict) and c.get('type') == 'text':
                                last = c.get('text', '')
                    elif isinstance(content, str):
                        last = content
            except json.JSONDecodeError:
                continue
except Exception as ex:
    pass
print(last[:500])
PYEOF
)
fi

# Check termination keywords (case-insensitive)
TERMINATION_FOUND="false"
if [ -n "$LAST_USER_MSG" ]; then
    LOWER_MSG=$(echo "$LAST_USER_MSG" | tr '[:upper:]' '[:lower:]')
    for kw in "stop" "정지" "종료" "그만" "그만해" "wait" "pause" "잠시" "잠깐" "끝" "halt" "quit"; do
        if echo "$LOWER_MSG" | grep -qF "$kw"; then
            TERMINATION_FOUND="true"
            break
        fi
    done
fi

if [ "$TERMINATION_FOUND" = "true" ]; then
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [allow stop — termination keyword in user msg]" >> "$LOG"
    exit 0
fi

# Block stop — emit system-reminder via JSON output
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "$TS [BLOCK STOP — $COUNT autonomous candidates, no termination keyword]" >> "$LOG"
echo "$TASKS" >> "$LOG"

# Output JSON to block stop and force re-engagement
cat << EOF
{
  "decision": "block",
  "reason": "AUTONOMOUS GUARD: $COUNT pending autonomous-doable tasks. No termination keyword in user message. HR7 + D16(a) enforcement — cycle summary doc / premature completion / fatigue stop is BLOCKED. Continue with highest-priority next_action OR explicitly itemize blockers.\n\nPending tasks:\n$TASKS\n\nIf you want to genuinely stop, the user must say a termination keyword (stop/정지/종료/그만/wait/pause/잠시/잠깐/보고해/summarize/검토/일단/끝/halt). Otherwise: pop the highest-priority next_action and execute one step."
}
EOF
exit 0
