#!/usr/bin/env bash
# queue-advance.sh <service> <status> [--priority N]
# Transitions a service_queue entry:
#   status in: pending_check | in_progress | done | suspended | stalled
# If status == done → also appends to done_services and removes from service_queue.
# If service not in queue: append (priority defaults to current max+1).

set -eu
# shellcheck disable=SC1091
source "$(dirname "$0")/common.sh"

[[ $# -ge 2 ]] || gap_die "usage: queue-advance.sh <service> <status> [--priority N]"
SVC="$1"
STATUS="$2"
shift 2
PRIORITY=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --priority) PRIORITY="$2"; shift 2 ;;
        *) gap_die "unknown arg: $1" ;;
    esac
done

case "$STATUS" in
    pending_check|in_progress|done|suspended|stalled) ;;
    *) gap_die "invalid status: $STATUS" ;;
esac

gap_state_init_if_missing

tmp=$(mktemp)
if [[ "$STATUS" == "done" ]]; then
    jq --arg s "$SVC" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
        .service_queue = (.service_queue | map(select(.service != $s)))
        | .done_services = ((.done_services // []) + [$s] | unique)
        | .updated_at = $now
    ' "$PIPELINE_STATE" > "$tmp"
else
    # Exists? update : append
    EXISTS=$(jq --arg s "$SVC" '[.service_queue[] | select(.service == $s)] | length' "$PIPELINE_STATE")
    if [[ "$EXISTS" == "0" ]]; then
        # Determine next priority
        if [[ -z "$PRIORITY" ]]; then
            CURMAX=$(jq '[.service_queue[].priority] | max // 0' "$PIPELINE_STATE")
            PRIORITY=$((CURMAX + 1))
        fi
        jq --arg s "$SVC" --arg st "$STATUS" --argjson p "$PRIORITY" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
            .service_queue += [{service:$s, priority:$p, status:$st}]
            | .updated_at = $now
        ' "$PIPELINE_STATE" > "$tmp"
    else
        jq --arg s "$SVC" --arg st "$STATUS" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
            (.service_queue[] | select(.service == $s)) |= (.status = $st)
            | .updated_at = $now
        ' "$PIPELINE_STATE" > "$tmp"
    fi
fi
mv "$tmp" "$PIPELINE_STATE"
gap_log "queue: $SVC → $STATUS"
