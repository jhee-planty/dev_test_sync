#!/bin/bash
# PreToolUse hook — ScheduleWakeup [SKILL-RECALL] auto-prepend + D9 Stage 1-3 anti-pattern detection
#
# Implements 28차 discussion-review consensus item #2 + 29차 D9 sophistication evolution catch:
#   - 28차: D21 caller-discipline (★★) → architectural enforcement (★★★) [auto-prepend]
#   - 29차: D9 Stage 1-3 anti-pattern detection (timeout/state/math/deontic-citation regex)
#
# Per D21 codify (27차) — wakeup turn 은 SessionStart/PostCompact hook 의 자동 inject 영역 밖.
# 28차 PreToolUse hook 으로 ★★★ promote.
# 29차 discussion-review (R3) — hook 가 Stage 1-3 sophistication 추가 catch (regex 기반).
# Stage 4-5 source verification = phase 2 (next cycle). Stage 6-7 = verifier-agent (deferred).
#
# Logic:
# 1. Read tool_input from stdin
# 2. **NEW (29차)**: Stage 1-3 regex check on prompt — match 시 reject + system-reminder
# 3. If tool_input.prompt starts with `[SKILL-RECALL]` → allow unchanged
# 4. Otherwise → prepend APF context prefix, return updatedInput
#
# Output: JSON via Claude Code PreToolUse hook spec (hookSpecificOutput.updatedInput / deny)
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

# === 29차 D9 Stage 1-3 anti-pattern detection ===
# Stage 1-3 patterns (per discussion-review R3 RE spec):
#   Stage 1 (declarative termination): timeout phrasing + termination keyword
#   Stage 2 (state assumption inferential): state keyword + conclusion keyword
#   Stage 3 (deontic citation): canonical-cite + termination action
#
# Regex set kept conservative (R3 CA: false-positive <5% threshold).
# Only flag when termination INTENT clear, not legitimate timing language.

DETECTED_STAGE=""
DETECTED_PATTERN=""

# Run Python regex check via env var (stdin 충돌 회피)
DETECTION_OUTPUT=$(PROMPT_VAR="$PROMPT" python3 -c "
import os, re, sys
prompt = os.environ.get('PROMPT_VAR', '')
# Stage 1: timeout-based termination
s1 = re.search(r'(\d+\s*(?:분|min|minutes?))\s*(?:이상|초과|도달|넘으|이후|경과)[^\n]{0,80}?(중단|stop|terminate|종료|halt|확정|fail|user\s+report\s+종료|escalate.*?종료)', prompt, re.IGNORECASE)
if s1:
    print('STAGE1|' + s1.group(0)[:120])
    sys.exit(0)
# Stage 2: state assumption inferential
s2 = re.search(r'(offline|crash|hung|무응답|미도착|silent|timeout\s*추정|응답\s*없음|polling\s*미도착)[^\n]{0,40}?(확정|determine|infer|conclude|단정|판정)', prompt, re.IGNORECASE)
if s2:
    print('STAGE2|' + s2.group(0)[:120])
    sys.exit(0)
# Stage 3a: deontic citation
s3a = re.search(r'(canonical|guidelines?\.md|protocol\.md|\.md\s*[:#L]?\d+)[^\n]{0,60}?(\d+\s*(?:분|min))[^\n]{0,60}?(보고.*?종료|escalate.*?종료|user\s+report.*?(?:종료|중단)|중단)', prompt, re.IGNORECASE)
if s3a:
    print('STAGE3a|' + s3a.group(0)[:120])
    sys.exit(0)
# Stage 3b: mathematical framing
s3b = re.search(r'expected_result_at\s*[+\-*]\s*\d+\s*(?:min|분)?[^\n]{0,80}?(escalate|user\s+report|종료|중단|보고\s*종료|polling\s*(?:cap|중단|종료))', prompt, re.IGNORECASE)
if s3b:
    print('STAGE3b|' + s3b.group(0)[:120])
    sys.exit(0)
print('CLEAR')
" 2>/dev/null)

if [ -n "$DETECTION_OUTPUT" ] && [ "$DETECTION_OUTPUT" != "CLEAR" ]; then
    DETECTED_STAGE=$(echo "$DETECTION_OUTPUT" | cut -d'|' -f1)
    DETECTED_PATTERN=$(echo "$DETECTION_OUTPUT" | cut -d'|' -f2-)
    echo "$NOW [REJECT — D9 ${DETECTED_STAGE}] pattern=${DETECTED_PATTERN}" >> "$LOG"

    # Output: deny + system-reminder citing Termination Conditions
    python3 << REJECTEOF
import json
reason = (
    f"D9 anti-pattern Stage detected (${DETECTED_STAGE}). "
    f"ScheduleWakeup prompt contains timeout/state/citation-based self-termination phrasing — "
    f"violates Termination Conditions (autonomous-execution-protocol.md §Polling Protocol L316-321). "
    f"Polling chain termination = ONLY 2 conditions: (1) result arrival, (2) session end. "
    f"All timeout/retry/state/mode-switch self-termination forbidden (D9). "
    f"Pattern matched: ${DETECTED_PATTERN}. "
    f"Re-formulate prompt: remove termination action phrasing, replace with continuation "
    f"('check results/, if found: process, else: ScheduleWakeup again with same prefix'). "
    f"Information-only timing references (e.g., 'note: expected = X') are permitted, "
    f"action triggers from time are NOT."
)
out = {
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason
    }
}
print(json.dumps(out))
REJECTEOF
    exit 0
fi
# === END 29차 D9 detection ===

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
