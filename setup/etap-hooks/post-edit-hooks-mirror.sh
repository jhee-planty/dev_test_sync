#!/bin/bash
# PostToolUse hook — D17(b) ★★★ enforcement: auto-mirror EtapV3 hooks to dev_test_sync backup.
#
# Implements 28차 discussion-review consensus item #4:
#   D17(b) caller-discipline (★★) → architectural enforcement (★★★)
#
# Per D17 codify (23차) — EtapV3/.claude/hooks/ 가 active path,
# dev_test_sync/setup/etap-hooks/ 가 git-tracked backup. 양 path 동시 update 의무가 있었으나
# caller-discipline (★★, manual mirror) 였음. 28차 R5 PA enumeration 에서 promotable 확인 →
# 본 hook 으로 architectural mirror.
#
# Logic:
# 1. Receive Edit/Write/MultiEdit PostToolUse event
# 2. Extract file_path
# 3. If file_path matches /Users/jhee/Documents/workspace/Officeguard/EtapV3/.claude/hooks/*.sh
#    → cp to /Users/jhee/Documents/workspace/dev_test_sync/setup/etap-hooks/<basename>
#    → emit systemMessage confirming mirror
# 4. Otherwise → exit 0 silently
#
# Logging: /tmp/post-edit-hooks-mirror.log

set -e

LOG="/tmp/post-edit-hooks-mirror.log"
ACTIVE_DIR="/Users/jhee/Documents/workspace/Officeguard/EtapV3/.claude/hooks"
BACKUP_DIR="/Users/jhee/Documents/workspace/dev_test_sync/setup/etap-hooks"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Read stdin JSON
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

# Check if file_path is in active hooks dir AND ends with .sh
if [ -z "$FILE_PATH" ]; then
    exit 0
fi

case "$FILE_PATH" in
    "$ACTIVE_DIR"/*.sh)
        BASENAME=$(basename "$FILE_PATH")
        DEST="$BACKUP_DIR/$BASENAME"

        # Ensure backup dir exists
        mkdir -p "$BACKUP_DIR"

        # Copy preserving mode (executable bit important for hooks)
        if cp -p "$FILE_PATH" "$DEST" 2>/dev/null; then
            echo "$NOW [mirror OK] $BASENAME" >> "$LOG"
            cat <<HOOKJSON
{"systemMessage":"[D17(b) ★★★] Auto-mirrored hook to backup: $BASENAME → dev_test_sync/setup/etap-hooks/. Triple-Mirror sync 자동화 완료. Commit dev_test_sync 별도."}
HOOKJSON
        else
            echo "$NOW [mirror FAIL] $BASENAME" >> "$LOG"
            cat <<HOOKJSON
{"systemMessage":"[D17(b) WARNING] Auto-mirror FAILED for $BASENAME. Manual sync required: cp $FILE_PATH $DEST"}
HOOKJSON
        fi
        ;;
    *)
        # Not a hook file — exit silently
        exit 0
        ;;
esac

exit 0
