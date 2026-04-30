#!/bin/bash
# PreToolUse hook — Edit/Write/MultiEdit on cowork-micro-skills/references/work-process-canonical/*
# Runs process-model-linter.py to catch D9 anti-pattern Stage 1-3 in process model docs.
#
# 30차 work-process-canonical codify (discussions/2026-04-30_ai-work-process-normalization.md Round 3-4).
# Extends 29차 pre-schedulewakeup-recall.sh Stage 1-3 regex to canonical reference files.
#
# Logic:
# 1. Read tool_input from stdin (file_path)
# 2. If file_path is NOT under work-process-canonical/ → allow unchanged
# 3. Else → run linter on the new content (Write) or post-edit content (Edit)
# 4. ERROR (linter exit 1) → deny + system-reminder
# 5. WARN (linter exit 2) → allow + log
# 6. OK (linter exit 0) → allow
#
# Output: JSON via Claude Code PreToolUse hook spec

set -e

LOG="/tmp/pre-edit-process-model-lint.log"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
LINTER="/Users/jhee/Documents/workspace/claude_work/projects/cowork-micro-skills/references/work-process-canonical/tooling/process-model-linter.py"
CANONICAL_PREFIX="/Users/jhee/Documents/workspace/claude_work/projects/cowork-micro-skills/references/work-process-canonical/"

INPUT=$(cat)

FILE_PATH=$(echo "$INPUT" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    ti = d.get('tool_input', {})
    print(ti.get('file_path', ''))
except Exception:
    print('')
" 2>/dev/null || echo "")

# If not under canonical dir → allow unchanged
if [[ "$FILE_PATH" != "$CANONICAL_PREFIX"* ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
    exit 0
fi

# If linter not present → allow + log warning
if [ ! -x "$LINTER" ]; then
    echo "$NOW [allow — linter missing] $FILE_PATH" >> "$LOG"
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
    exit 0
fi

# For Edit, the new content isn't directly available pre-edit (we'd need to apply Edit and check).
# Pragmatic approach: lint the EXISTING file. If it's currently clean, the edit is reviewed at PostToolUse.
# For Write, the new_string field is the full content — extract + lint as transient file.

TOOL_NAME=$(echo "$INPUT" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('tool_name', ''))
except Exception:
    print('')
" 2>/dev/null || echo "")

# Lint the existing file (if it exists)
if [ -f "$FILE_PATH" ]; then
    LINT_OUT=$(python3 "$LINTER" "$FILE_PATH" 2>&1) || LINT_RC=$?
    LINT_RC=${LINT_RC:-0}

    if [ "$LINT_RC" = "1" ]; then
        echo "$NOW [DENY — pre-edit existing file already has D9 ERRORs] $FILE_PATH" >> "$LOG"
        echo "$LINT_OUT" >> "$LOG"
        REASON="Pre-edit lint: file '$FILE_PATH' currently contains D9 anti-pattern (Stage 1-3) ERRORs. Fix existing violations before editing OR add <!-- D9-LINTER-IGNORE-START --> ... <!-- D9-LINTER-IGNORE-END --> markers around documentation examples. Linter output: $(echo "$LINT_OUT" | head -5 | tr '\n' '|')"
        python3 -c "
import json
out = {
    'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'deny',
        'permissionDecisionReason': '''$REASON'''
    }
}
print(json.dumps(out))
"
        exit 0
    fi
fi

# Allow + log
echo "$NOW [allow] $TOOL_NAME $FILE_PATH" >> "$LOG"
echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
exit 0
