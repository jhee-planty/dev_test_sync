#!/usr/bin/env bash
# count-attempts.sh --service <id>
# Parses services/{id}_impl.md and emits JSON:
#   {
#     "service": "...",
#     "total_iterations": N,
#     "completed": N,
#     "builds_attempted": N,
#     "verdict_counts": {...},
#     "sub_category_counts": {...},
#     "last_verdicts": [...]
#   }

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

JOURNAL=$(awi_journal_path "$SERVICE")
if [[ ! -f "$JOURNAL" ]]; then
    printf '{"service":"%s","total_iterations":0,"completed":0,"builds_attempted":0,"verdict_counts":{},"sub_category_counts":{},"last_verdicts":[]}\n' "$SERVICE"
    exit 0
fi

TOTAL=$(grep -cE '^### Iteration [0-9]+' "$JOURNAL" || echo 0)
COMPLETED=$(grep -cE '^- Verdict:' "$JOURNAL" || echo 0)
BUILDS=$COMPLETED  # 1 build per iteration

# Counts via awk (bash-3.2 safe, no associative arrays)
VERDICT_COUNTS_JSON=$(grep '^- Verdict:' "$JOURNAL" 2>/dev/null | sed -nE 's/^- Verdict: *([A-Z_]+).*/\1/p' | awk '
    {counts[$0]++}
    END {
        printf "{";
        first=1
        for (k in counts) {
            if (!first) printf ",";
            printf "\"%s\":%d", k, counts[k]
            first=0
        }
        printf "}"
    }
')
[[ -z "$VERDICT_COUNTS_JSON" ]] && VERDICT_COUNTS_JSON="{}"

CAT_COUNTS_JSON=$(grep '^- Sub_category:' "$JOURNAL" 2>/dev/null | sed -nE 's/^- Sub_category: *([A-Z_]+).*/\1/p' | awk '
    {counts[$0]++}
    END {
        printf "{";
        first=1
        for (k in counts) {
            if (!first) printf ",";
            printf "\"%s\":%d", k, counts[k]
            first=0
        }
        printf "}"
    }
')
[[ -z "$CAT_COUNTS_JSON" ]] && CAT_COUNTS_JSON="{}"

# last 3 verdicts newest→oldest
LAST3=$(grep '^- Verdict:' "$JOURNAL" | sed -nE 's/^- Verdict: *([A-Z_]+).*/\1/p' | tail -3 | awk '{a[NR]=$0} END{for(i=NR;i>=1;i--)print a[i]}')

L3_JSON=$(echo "$LAST3" | awk 'NF {
    printf "%s\"%s\"", (NR>1 ? "," : ""), $0
}' | awk 'BEGIN{printf "["} {printf "%s", $0} END{printf "]"}')
[[ "$L3_JSON" == "[]" || -z "$L3_JSON" ]] && L3_JSON="[]"

printf '{"service":"%s","total_iterations":%s,"completed":%s,"builds_attempted":%s,"verdict_counts":%s,"sub_category_counts":%s,"last_verdicts":%s}\n' \
    "$SERVICE" "$TOTAL" "$COMPLETED" "$BUILDS" "$VERDICT_COUNTS_JSON" "$CAT_COUNTS_JSON" "$L3_JSON"
exit 0
