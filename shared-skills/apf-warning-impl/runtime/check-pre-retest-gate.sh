#!/usr/bin/env bash
# check-pre-retest-gate.sh --service <id>
# 41차 amendment: count-based hard caps 폐지, cause-based axis-exhaustion only.
# Build/total counts = ADVISORY logging (no exit 2 terminal).
# Stop license = mission goal achieved (HR7) — runtime 은 axis pivot signal 만 emit.
#
# Exit codes:
#   - same sub_category recurrence in last 3 verdicts (all error_*) → exit 1 (axis pivot signal)
#   - otherwise → exit 0 (PROCEED + optional ADVISORY logging)

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

# 41차: count-based hard cap 폐지 → cause-based axis-exhaustion gate
# Build/iteration count 자체는 stop trigger 아님 — sub_category recurrence + axis pivot 만 trigger.
# Numbers below = ADVISORY logging only (operational visibility), no exit non-zero.
if (( BUILDS >= 5 )); then
    echo "ADVISORY: builds=${BUILDS} (mission goal persistence — axis pivot 권장 시 STRATEGY_REVISIT verdict 사용)" >&2
fi
if (( COMPLETED >= 5 )); then
    echo "ADVISORY: completed=${COMPLETED} (axis pivot 권장 시 STRATEGY_REVISIT)" >&2
fi
if (( BUILDS >= 7 )); then
    echo "ADVISORY: builds=${BUILDS} >= 7 (mission still incomplete? continue expansion search per HR7 41차)" >&2
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
