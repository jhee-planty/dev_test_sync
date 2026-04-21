#!/usr/bin/env bash
# record-iteration.sh --service <id> --event started|completed [options]
#
# Appends an iteration block to services/{service}_impl.md.
# For `started`: creates "Iteration N — STARTED" block with strategy/plan/hypotheses/files.
# For `completed`: appends verdict/sub_category/notes to the most recent STARTED block.
#
# Options:
#   --strategy A|B|C|D        (started only)
#   --hypotheses "H1,H2"      (started only)
#   --files "f1,f2"           (started only)
#   --plan "short summary"    (started only)
#   --verdict VERDICT         (completed only)
#   --sub_category CAT        (completed only)
#   --notes "text"            (completed only)

set -eu
# shellcheck disable=SC1091
source "$(dirname "$0")/common.sh"

SERVICE=""
EVENT=""
STRATEGY=""
HYPOTHESES=""
FILES=""
PLAN=""
VERDICT=""
SUB_CATEGORY=""
NOTES=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --service) SERVICE="$2"; shift 2 ;;
        --event) EVENT="$2"; shift 2 ;;
        --strategy) STRATEGY="$2"; shift 2 ;;
        --hypotheses) HYPOTHESES="$2"; shift 2 ;;
        --files) FILES="$2"; shift 2 ;;
        --plan) PLAN="$2"; shift 2 ;;
        --verdict) VERDICT="$2"; shift 2 ;;
        --sub_category) SUB_CATEGORY="$2"; shift 2 ;;
        --notes) NOTES="$2"; shift 2 ;;
        *) awi_die "unknown arg: $1" ;;
    esac
done

[[ -n "$SERVICE" ]] || awi_die "--service required"
[[ -n "$EVENT" ]]   || awi_die "--event required"
awi_validate_service "$SERVICE"

JOURNAL=$(awi_journal_path "$SERVICE")
mkdir -p "$(dirname "$JOURNAL")"

case "$EVENT" in
started)
    # Compute next N
    LAST_N=0
    if [[ -f "$JOURNAL" ]]; then
        LAST_N=$(grep -oE '^### Iteration [0-9]+' "$JOURNAL" 2>/dev/null | awk '{print $3}' | sort -n | tail -1)
        [[ -z "$LAST_N" ]] && LAST_N=0
    fi
    NEXT_N=$((LAST_N + 1))
    {
        echo ""
        echo "### Iteration ${NEXT_N} ($(awi_now_iso)) — STARTED"
        [[ -n "$STRATEGY" ]]   && echo "- Strategy: ${STRATEGY}"
        [[ -n "$PLAN" ]]       && echo "- Plan: ${PLAN}"
        [[ -n "$HYPOTHESES" ]] && echo "- Hypotheses: [${HYPOTHESES}]"
        [[ -n "$FILES" ]]      && echo "- Files: ${FILES}"
    } >> "$JOURNAL"
    awi_log "iteration ${NEXT_N} STARTED logged → $JOURNAL"
    echo "$NEXT_N"  # stdout
    ;;
completed)
    [[ -f "$JOURNAL" ]] || awi_die "no journal at $JOURNAL — cannot complete"
    # Find last STARTED line number — simply append at EOF tagged with verdict
    LAST_N=$(grep -oE '^### Iteration [0-9]+' "$JOURNAL" | awk '{print $3}' | sort -n | tail -1)
    [[ -z "$LAST_N" ]] && awi_die "no STARTED iteration in journal"
    {
        echo "- Verdict: ${VERDICT}"
        [[ -n "$SUB_CATEGORY" ]] && echo "- Sub_category: ${SUB_CATEGORY}"
        [[ -n "$NOTES" ]]        && echo "- Notes: ${NOTES}"
        echo "- Completed: $(awi_now_iso)"
    } >> "$JOURNAL"
    awi_log "iteration ${LAST_N} COMPLETED (verdict=${VERDICT}) → $JOURNAL"
    ;;
*)
    awi_die "--event must be started|completed"
    ;;
esac

exit 0
