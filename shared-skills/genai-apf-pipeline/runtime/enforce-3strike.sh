#!/usr/bin/env bash
# enforce-3strike.sh <service>
#
# !!! VESTIGIAL — 3-Strike auto-SUSPEND policy was DROPPED 2026-04-28 21차 !!!
# !!! User directive: Claude 작업 정확도 부족으로 자동 SUSPENDED 처리 부적합 !!!
# !!! Do NOT invoke. Kept on disk only for V1 rollback path. !!!
# !!! See references/legacy/v1-orchestration-loop.md !!!
#
# (V1 behavior, kept for rollback path only):
# Reads failure_history[service] last 3 entries. If all same category → mark SUSPENDED.
# stdout: resulting status (unchanged|SUSPENDED)
# exit 0

set -eu
# shellcheck disable=SC1091
source "$(dirname "$0")/common.sh"

[[ $# -ge 1 ]] || gap_die "usage: enforce-3strike.sh <service>"
SVC="$1"

gap_state_init_if_missing

LAST3=$(jq -r --arg s "$SVC" '
    (.failure_history[$s] // []) | .[length-3:] | map(.category) | join("|")
' "$PIPELINE_STATE")

COUNT=$(echo "$LAST3" | tr '|' '\n' | sort -u | grep -vE '^$' | wc -l | tr -d ' ')
TOTAL=$(echo "$LAST3" | tr '|' '\n' | grep -vE '^$' | wc -l | tr -d ' ')

if (( TOTAL >= 3 )) && (( COUNT == 1 )); then
    CAT=$(echo "$LAST3" | cut -d'|' -f1)
    gap_log "3-strike: $SVC same category $CAT × 3 → SUSPENDED"
    # update queue
    "$(dirname "$0")/queue-advance.sh" "$SVC" suspended
    echo SUSPENDED
else
    echo unchanged
fi
exit 0
