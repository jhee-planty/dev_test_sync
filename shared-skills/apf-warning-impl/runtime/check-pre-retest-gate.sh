#!/usr/bin/env bash
# check-pre-retest-gate.sh --service <id>
# Reads count-attempts.sh output and enforces (38차 SOFT_WARN amendment):
#   - builds_attempted >= 7 → stderr BUILD_CAP (exit 2, terminal)
#   - completed >= 5 → stderr NEEDS_ALTERNATIVE (exit 2)
#   - builds_attempted >= 5 → stderr SOFT_WARN (exit 0 + advisory, autonomous STRATEGY_REVISIT trigger)
#   - same sub_category in last 3 verdicts (all error_*) → exit 1 (RETRY_BLOCKED, autonomous frontend-inspect 재진입)
#   - otherwise → exit 0 (PROCEED)

set -eu
# shellcheck disable=SC1091
source "$(dirname "$0")/common.sh"

SERVICE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --service) SERVICE="$2"; shift 2 ;;
        *) awi_die "unknown arg: $1" ;;
    esac
done
[[ -n "$SERVICE" ]] || awi_die "--service required"
awi_validate_service "$SERVICE"

RT_DIR="$(dirname "$0")"
STATE_JSON=$("$RT_DIR/count-attempts.sh" --service "$SERVICE")

if ! command -v jq >/dev/null 2>&1; then
    awi_die "jq required"
fi

BUILDS=$(echo "$STATE_JSON" | jq -r '.builds_attempted')
COMPLETED=$(echo "$STATE_JSON" | jq -r '.completed')
LAST3=$(echo "$STATE_JSON" | jq -r '.last_verdicts | join("|")')

# Build cap hard
if (( BUILDS >= 7 )); then
    echo "BUILD_CAP: builds_attempted=${BUILDS} >= 7" >&2
    exit 2
fi

# Total iterations cap
if (( COMPLETED >= 5 )); then
    echo "NEEDS_ALTERNATIVE: completed=${COMPLETED} >= 5" >&2
    exit 2
fi

# Build soft warn (38차: SUSPEND_GATE → SOFT_WARN, autonomous progression 유지)
if (( BUILDS >= 5 )); then
    echo "SOFT_WARN: builds=${BUILDS} >= 5 — STRATEGY_REVISIT autonomous trigger; 7회 도달 시에만 ESCALATE" >&2
    # exit 0 (advisory only) — autonomous loop continues with STRATEGY_REVISIT verdict
fi

# Same-category 3-Strike (checked via last 3 verdicts if all error_*)
# Extract categories from journal (same order as verdicts)
JOURNAL=$(awi_journal_path "$SERVICE")
if [[ -f "$JOURNAL" ]]; then
    # Collect sub_category values corresponding to recent completed iterations
    LAST_CATS=$(grep '^- Sub_category:' "$JOURNAL" | sed -nE 's/^- Sub_category: *([A-Z_]+).*/\1/p' | tail -3)
    if [[ -n "$LAST_CATS" ]]; then
        COUNT=$(echo "$LAST_CATS" | sort -u | wc -l | tr -d ' ')
        TOTAL_RECENT=$(echo "$LAST_CATS" | wc -l | tr -d ' ')
        if (( COUNT == 1 )) && (( TOTAL_RECENT >= 3 )); then
            CAT=$(echo "$LAST_CATS" | head -1)
            echo "RETRY_BLOCKED: same sub_category '${CAT}' in last 3 iterations" >&2
            exit 1
        fi
    fi
fi

echo "PROCEED: builds=${BUILDS} completed=${COMPLETED} last3=${LAST3}" >&2
exit 0
