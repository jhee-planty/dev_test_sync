#!/usr/bin/env bash
# scan-results.sh [--since <id>] [--mode flat|pairs]
# - git pull (transport only)
# - filesystem scan: emit new result entries to stdout
# - exit 0 always (stdout empty = nothing new)
# - exit 2 fatal (git error etc.)
#
# Output formats (stdout):
#   --mode flat  (default, backward compat): one 3-digit ID per line.
#                Caller must enumerate per-PC result files separately.
#   --mode pairs: one entry per (id, pc) tuple, format "{ID3} {pc}".
#                pc ∈ {pc1, pc2, legacy}. "legacy" = pre-multi-PC file
#                ({id}_result.json or {id}_{svc}_result.json with no _pc suffix).
#
# Multi-PC: dev session iterates the output and reads
#   results/{id}_result_{pc}.json  (multi-PC)  or
#   results/{id}_result.json       (legacy single-PC fallback)
# per-PC verdict, then calls update-queue.sh with --pc {pc1|pc2}.

set -eu
# shellcheck disable=SC1091
source "$(dirname "$0")/common.sh"

SINCE=""
MODE="flat"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --since) SINCE="$2"; shift 2 ;;
        --mode) MODE="$2"; shift 2 ;;
        --mode=*) MODE="${1#*=}"; shift ;;
        *) cr_die "unknown arg: $1" ;;
    esac
done

case "$MODE" in
    flat|pairs) : ;;
    *) cr_die "invalid --mode: '$MODE' (must be flat|pairs)" ;;
esac

if [[ -z "$SINCE" ]]; then
    SINCE=$(cr_state_get "last_checked_result_id")
    [[ -z "$SINCE" ]] && SINCE=0
fi

# 1. Git pull (transport) — output suppressed unless error
if ! cr_git pull origin HEAD >/dev/null 2>&1; then
    cr_log "git pull failed — attempting fetch-only + reset heuristic"
    cr_git fetch origin >/dev/null 2>&1 || cr_log "git fetch also failed (continuing with local filesystem)"
fi

# 2. Filesystem scan
#    Three filename shapes accepted:
#      A) {id}_result.json                       → pc=legacy
#      B) {id}_{service}_result.json             → pc=legacy
#      C) {id}[_{service}]_result_{pc}.json      → pc ∈ {pc1, pc2, ...}
ENTRIES=""  # newline-separated "ID3 pc"
shopt -s nullglob
for f in "$RESULTS_DIR"/*_result*.json; do
    bn=$(basename "$f")
    id=""; pc="legacy"
    # Shape C first: _result_{pc}.json
    if [[ "$bn" =~ ^0*([0-9]+)(_[^_]+)?_result_([a-zA-Z0-9]+)\.json$ ]]; then
        id="${BASH_REMATCH[1]}"
        pc="${BASH_REMATCH[3]}"
    elif [[ "$bn" =~ ^0*([0-9]+)(_[^_]+)?_result\.json$ ]]; then
        id="${BASH_REMATCH[1]}"
        pc="legacy"
    else
        continue
    fi
    [[ -z "$id" ]] && continue
    ENTRIES+="$(printf '%03d %s' "$id" "$pc")"$'\n'
done
shopt -u nullglob

# Sort+dedup
ENTRIES=$(printf '%s' "$ENTRIES" | sort -u)

NEW_COUNT=0
EMITTED_IDS=""  # for flat mode dedup
while IFS=' ' read -r idz pc; do
    [[ -z "$idz" ]] && continue
    idn=$((10#$idz))
    if (( idn > SINCE )); then
        if [[ "$MODE" == "pairs" ]]; then
            printf '%s %s\n' "$idz" "$pc"
            NEW_COUNT=$((NEW_COUNT+1))
        else
            # flat mode: emit ID once per unique id
            if ! grep -qx "$idz" <<< "$EMITTED_IDS"; then
                printf '%s\n' "$idz"
                EMITTED_IDS+="$idz"$'\n'
                NEW_COUNT=$((NEW_COUNT+1))
            fi
        fi
    fi
done <<< "$ENTRIES"

cr_log "scan complete: SINCE=${SINCE}, mode=${MODE}, new=${NEW_COUNT}"
exit 0
