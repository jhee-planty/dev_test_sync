#!/usr/bin/env bash
# update-queue.sh <id> <verdict> [summary]
# - Updates queue.json task[id].status to done|error mapping:
#   done → "done"
#   error_* → "error"  (preserves full verdict in summary)
# - Updates state.json.last_checked_result_id to max(id, current)
# - exit 0 success / exit 2 fatal

set -eu
# shellcheck disable=SC1091
source "$(dirname "$0")/common.sh"

[[ $# -ge 2 ]] || cr_die "usage: update-queue.sh <id> <verdict> [summary]"
ID_RAW="$1"
VERDICT="$2"
SUMMARY="${3:-}"

# Normalize ID (strip leading zeros but keep 3-digit in queue)
ID_NUM=$((10#$ID_RAW))
ID3=$(printf '%03d' "$ID_NUM")

# Map verdict → status
case "$VERDICT" in
    done) STATUS="done" ;;
    error_PROTOCOL_MISMATCH|error_NOT_RENDERED|error_SERVICE_CHANGED|error_AUTH_REQUIRED|error_INFRASTRUCTURE) STATUS="error" ;;
    *) cr_die "unknown verdict: $VERDICT" ;;
esac

[[ -f "$QUEUE_JSON" ]] || cr_die "queue.json not found at $QUEUE_JSON"

# Combined summary: verdict + user summary
FULL_SUMMARY="[${VERDICT}]"
[[ -n "$SUMMARY" ]] && FULL_SUMMARY+=" ${SUMMARY}"

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
tmp=$(mktemp)

# If task exists, update it; else append
EXIST=$(jq --arg id "$ID3" '[.tasks[] | select(.id == $id)] | length' "$QUEUE_JSON")
if [[ "$EXIST" == "0" ]]; then
    cr_log "task $ID3 not in queue.json — appending"
    jq --arg id "$ID3" --arg status "$STATUS" --arg sum "$FULL_SUMMARY" --arg now "$NOW" \
       '.tasks += [{id:$id, command:"(unknown)", to:"test", status:$status, created:$now, updated:$now, summary:$sum}] | .last_updated = $now' \
       "$QUEUE_JSON" > "$tmp"
else
    jq --arg id "$ID3" --arg status "$STATUS" --arg sum "$FULL_SUMMARY" --arg now "$NOW" \
       '(.tasks[] | select(.id == $id)) |= (.status = $status | .updated = $now | .summary = $sum) | .last_updated = $now' \
       "$QUEUE_JSON" > "$tmp"
fi
mv "$tmp" "$QUEUE_JSON"
cr_log "queue.json updated: $ID3 → $STATUS [$VERDICT]"

# Update last_checked_result_id if higher
CUR=$(cr_state_get "last_checked_result_id")
[[ -z "$CUR" ]] && CUR=0
if (( ID_NUM > CUR )); then
    cr_state_set "last_checked_result_id" "$ID_NUM"
fi

exit 0
