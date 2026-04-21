#!/usr/bin/env bash
# phase-advance.sh --check|--commit <phase-id>
# --check : 진입 가능한지 가드 (이전 phase done 상태 or 초기)
# --commit: current_phase 필드를 해당 phase 로 설정

set -eu
# shellcheck disable=SC1091
source "$(dirname "$0")/common.sh"

MODE=""
PHASE_ARG=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --check) MODE=check; shift ;;
        --commit) MODE=commit; shift ;;
        --*) gap_die "unknown flag $1" ;;
        *) PHASE_ARG="$1"; shift ;;
    esac
done
[[ -n "$MODE" ]] || gap_die "must specify --check or --commit"
[[ -n "$PHASE_ARG" ]] || gap_die "phase id required"

# Accept either short index (1..7) or full name (phase1-har-capture)
if [[ "$PHASE_ARG" =~ ^[1-7]$ ]]; then
    IDX=$((PHASE_ARG - 1))
    NAME="${PHASES[$IDX]}"
else
    NAME="$PHASE_ARG"
    if ! IDX=$(gap_phase_index "$NAME"); then
        gap_die "unknown phase: $PHASE_ARG"
    fi
fi

CURRENT=$(gap_state_get current_phase)

case "$MODE" in
check)
    # Pass if current is empty (first phase) OR exactly the expected predecessor
    if [[ "$IDX" == "0" ]]; then
        # Phase 1: allow if current is empty or phase7 (new service restart)
        gap_log "check: phase1 entry (current=$CURRENT)"
        exit 0
    fi
    PREV="${PHASES[$((IDX - 1))]}"
    if [[ "$CURRENT" == "$PREV" ]] || [[ "$CURRENT" == "$NAME" ]]; then
        gap_log "check: OK (current=$CURRENT → advance to $NAME)"
        exit 0
    fi
    echo "BLOCKED: cannot enter $NAME (current=$CURRENT, expected predecessor=$PREV)" >&2
    exit 1
    ;;
commit)
    gap_state_set current_phase "$NAME"
    gap_log "committed current_phase=$NAME"
    ;;
esac
