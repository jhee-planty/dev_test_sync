#!/usr/bin/env bash
# list-workers.sh [--stale-seconds N]
# - Reads results/heartbeat_*.json (one per active Test PC)
# - Optionally falls back to legacy results/heartbeat.json (single-PC, pre-multipc)
# - stdout: one line per worker:
#     {worker_id}  {age_seconds}  {last_processed_id}  {stale|live}
# - Threshold for "stale" = --stale-seconds (default 900 = 15min)
# - exit 0 always
#
# Used by dev session to gauge which Test PCs are live before dispatching
# target_pc=both. If only PC1 has a fresh heartbeat, prefer --target-pc pc1.

set -u
# shellcheck disable=SC1091
source "$(dirname "$0")/common.sh"

STALE=900
while [[ $# -gt 0 ]]; do
    case "$1" in
        --stale-seconds) STALE="$2"; shift 2 ;;
        --stale-seconds=*) STALE="${1#*=}"; shift ;;
        *) cr_die "unknown arg: $1" ;;
    esac
done

NOW_EPOCH=$(date +%s)

shopt -s nullglob
FOUND=0
for f in "$RESULTS_DIR"/heartbeat_*.json; do
    [[ -f "$f" ]] || continue
    bn=$(basename "$f")
    wid=$(echo "$bn" | sed -nE 's/^heartbeat_([a-z0-9]+)\.json$/\1/p')
    [[ -z "$wid" ]] && continue
    ts=$(jq -r '.timestamp // empty' "$f" 2>/dev/null || true)
    lpid=$(jq -r '.last_processed_id // 0' "$f" 2>/dev/null || echo 0)
    if [[ -n "$ts" ]]; then
        # Convert ISO 8601 (UTC, trailing Z) to epoch.
        # BSD: TZ=UTC date -j -f ... (parser treats input as UTC).
        # GNU: date -d "$ts" handles Z natively.
        if date -j -f '%Y-%m-%dT%H:%M:%SZ' "$ts" +%s >/dev/null 2>&1; then
            ts_epoch=$(TZ=UTC date -j -f '%Y-%m-%dT%H:%M:%SZ' "$ts" +%s)
        else
            ts_epoch=$(date -d "$ts" +%s 2>/dev/null || echo 0)
        fi
        age=$(( NOW_EPOCH - ts_epoch ))
    else
        age=-1
    fi
    if (( age >= 0 && age <= STALE )); then state="live"; else state="stale"; fi
    printf '%s\t%d\t%s\t%s\n' "$wid" "$age" "$lpid" "$state"
    FOUND=$((FOUND+1))
done
shopt -u nullglob

# Legacy fallback
if (( FOUND == 0 )) && [[ -f "$RESULTS_DIR/heartbeat.json" ]]; then
    ts=$(jq -r '.timestamp // empty' "$RESULTS_DIR/heartbeat.json" 2>/dev/null || true)
    lpid=$(jq -r '.last_processed_id // 0' "$RESULTS_DIR/heartbeat.json" 2>/dev/null || echo 0)
    printf 'legacy\t-1\t%s\tunknown\n' "$lpid"
fi

cr_log "list-workers: found=${FOUND}, stale_threshold=${STALE}s"
exit 0
