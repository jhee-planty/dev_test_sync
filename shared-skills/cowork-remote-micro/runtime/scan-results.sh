#!/usr/bin/env bash
# scan-results.sh [--since <id>]
# - git pull (transport only)
# - filesystem scan: last_checked_result_id 이후의 새 result ID 목록 stdout
# - exit 0 if new results found, exit 0 if none (no failure distinction; stdout empty = none)
# - exit 2 fatal (git error etc.)
#
# Output format (stdout): one ID per line, newline-terminated.

set -eu
# shellcheck disable=SC1091
source "$(dirname "$0")/common.sh"

SINCE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --since) SINCE="$2"; shift 2 ;;
        *) cr_die "unknown arg: $1" ;;
    esac
done

if [[ -z "$SINCE" ]]; then
    SINCE=$(cr_state_get "last_checked_result_id")
    [[ -z "$SINCE" ]] && SINCE=0
fi

# 1. Git pull (transport) — output suppressed unless error
if ! cr_git pull origin HEAD >/dev/null 2>&1; then
    cr_log "git pull failed — attempting fetch-only + reset heuristic"
    # try fetch, continue — filesystem may still have local truth
    cr_git fetch origin >/dev/null 2>&1 || cr_log "git fetch also failed (continuing with local filesystem)"
fi

# 2. Filesystem scan
#    Matches: {id}_result.json  or  {id}_{service}_result.json
FOUND_IDS=$(
    ls "$RESULTS_DIR"/*_result.json 2>/dev/null \
    | xargs -n1 -I{} basename {} \
    | sed -nE 's/^0*([0-9]+)_.*_result\.json$/\1/p; s/^0*([0-9]+)_result\.json$/\1/p' \
    | sort -un
)

NEW_COUNT=0
while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    if (( id > SINCE )); then
        printf '%03d\n' "$id"
        NEW_COUNT=$((NEW_COUNT+1))
    fi
done <<< "$FOUND_IDS"

cr_log "scan complete: SINCE=${SINCE}, new=${NEW_COUNT}"
exit 0
