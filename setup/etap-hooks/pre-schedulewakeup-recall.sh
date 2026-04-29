#!/bin/bash
# PreToolUse hook — ScheduleWakeup [SKILL-RECALL] auto-prepend (D21 ★★★ enforcement)
#
# Implements 28차 discussion-review consensus item #2:
#   D21 caller-discipline (★★) → architectural enforcement (★★★)
#
# Per D21 codify (27차) — wakeup turn 은 SessionStart/PostCompact hook 의 자동 inject
# 영역 밖이라 caller 가 prompt 첫 줄에 [SKILL-RECALL] prefix 의무. 27차에는 caller-discipline
# (★★ tier) 으로 codify, "기능의 한계" 인정. 28차 discussion-review (R5) 결과 PreToolUse hook
# 으로 architectural enforcement (★★★) 가능 확인 → 본 hook 으로 promote.
#
# Logic:
# 1. Read tool_input from stdin
# 2. If tool_input.prompt starts with `[SKILL-RECALL]` → allow unchanged
# 3. Otherwise → prepend APF context prefix, return updatedInput
#
# Output: JSON via Claude Code PreToolUse hook spec (hookSpecificOutput.updatedInput)
# Logging: /tmp/pre-schedulewakeup-recall.log (append-only)

set -e

LOG="/tmp/pre-schedulewakeup-recall.log"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Read stdin JSON
INPUT=$(cat)

# Extract tool_input
PROMPT=$(echo "$INPUT" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    ti = d.get('tool_input', {})
    print(ti.get('prompt', ''))
except Exception:
    print('')
" 2>/dev/null || echo "")

# Check if prefix already present
if echo "$PROMPT" | head -c 16 | grep -qF '[SKILL-RECALL]'; then
    # Already prefixed — allow unchanged
    echo "$NOW [allow — prefix present] prompt_len=${#PROMPT}" >> "$LOG"
    cat <<HOOKJSON
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}
HOOKJSON
    exit 0
fi

# Missing prefix — auto-prepend
PREFIX='[SKILL-RECALL] guidelines.md §11/§13 + APF mission (PII 포함 프롬프트 → 사용자 화면 경고 표시) + Hard Rules 1-7 + Self-Check Categories A-J. Then: '

NEW_PROMPT="${PREFIX}${PROMPT}"

# Build updatedInput preserving all original fields
UPDATED_INPUT=$(echo "$INPUT" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    ti = dict(d.get('tool_input', {}))
    ti['prompt'] = '''$NEW_PROMPT'''
    print(json.dumps(ti))
except Exception as e:
    print('{}')
" 2>/dev/null)

echo "$NOW [auto-prepend] orig_len=${#PROMPT} new_len=${#NEW_PROMPT}" >> "$LOG"

# Output modified input via hookSpecificOutput
python3 -c "
import json, sys
out = {
    'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'allow',
        'updatedInput': $UPDATED_INPUT
    },
    'systemMessage': '[D21 ★★★] ScheduleWakeup auto-prepended [SKILL-RECALL] prefix (caller forgot manual prefix per D21). Wakeup turn will receive skill anchor inject regardless.'
}
print(json.dumps(out))
"

exit 0
