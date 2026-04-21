#!/usr/bin/env bash
# archive-completed.sh <id>
# - Moves requests/{id}_*.json + results/{id}_*_result.json (and files/{id}/) to local_archive/YYYY-MM-DD/
# - Also archives queue.json task (keeps in queue.json but marks archived=true)
# - exit 0 success / exit 2 fatal

set -eu
# shellcheck disable=SC1091
source "$(dirname "$0")/common.sh"

[[ $# -ge 1 ]] || cr_die "usage: archive-completed.sh <id>"
ID_RAW="$1"
ID_NUM=$((10#$ID_RAW))
ID3=$(printf '%03d' "$ID_NUM")

DATE_DIR="$LOCAL_ARCHIVE/$(date +%Y-%m-%d)"
mkdir -p "$DATE_DIR"

MOVED=0
# Requests
for f in "$REQUESTS_DIR/${ID3}"_*.json; do
    [[ -f "$f" ]] || continue
    mv "$f" "$DATE_DIR/"
    cr_log "archived: $(basename "$f")"
    MOVED=$((MOVED+1))
done
# Results (may be multiple: batch fan-out)
for f in "$RESULTS_DIR/${ID3}"_*_result.json "$RESULTS_DIR/${ID3}_result.json"; do
    [[ -f "$f" ]] || continue
    mv "$f" "$DATE_DIR/"
    cr_log "archived: $(basename "$f")"
    MOVED=$((MOVED+1))
done
# Attached files
for d in "$REQUESTS_DIR/files/${ID3}" "$RESULTS_DIR/files/${ID3}"; do
    [[ -d "$d" ]] || continue
    mv "$d" "$DATE_DIR/"
    cr_log "archived dir: $(basename "$d")"
    MOVED=$((MOVED+1))
done

if (( MOVED == 0 )); then
    cr_log "nothing to archive for id=$ID3"
fi

# Mark queue.json task archived (don't delete — audit trail)
if [[ -f "$QUEUE_JSON" ]]; then
    tmp=$(mktemp)
    NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    jq --arg id "$ID3" --arg now "$NOW" \
       '(.tasks[] | select(.id == $id)) |= (.archived = true | .archived_at = $now) | .last_updated = $now' \
       "$QUEUE_JSON" > "$tmp"
    mv "$tmp" "$QUEUE_JSON"
fi

exit 0
