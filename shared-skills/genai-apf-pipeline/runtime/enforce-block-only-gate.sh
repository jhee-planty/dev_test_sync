#!/usr/bin/env bash
# enforce-block-only-gate.sh <service>
# Reads apf-technical-limitations.md alternatives (if present) and current impl journal
# attempts. Verdict:
#   exit 0  → VALIDATED (BLOCK_ONLY 허용)
#   exit 1  → ALTERNATIVES_PENDING (대안 시도 남음)
#   exit 2  → no limitations doc / indeterminate (block by default)
#
# Claude 가 최종 판정자 — 이 gate 는 "완전 전수 시도 여부" 만 확인.

set -eu
# shellcheck disable=SC1091
source "$(dirname "$0")/common.sh"

[[ $# -ge 1 ]] || gap_die "usage: enforce-block-only-gate.sh <service>"
SVC="$1"

LIMIT_DOC="${APF_LIMITATIONS_DOC:-$HOME/Documents/workspace/dev_test_sync/shared-skills/genai-apf-pipeline/references/apf-technical-limitations.md}"

if [[ ! -f "$LIMIT_DOC" ]]; then
    echo "INDETERMINATE: $LIMIT_DOC missing" >&2
    exit 2
fi

# Count alternatives listed (lines starting with '- ' within a section headed 'alternatives' or '대안')
ALTS=$(grep -cE '^(- |\* )' "$LIMIT_DOC" 2>/dev/null || echo 0)

# Count attempts in impl journal
JOURNAL="$HOME/Documents/workspace/dev_test_sync/shared-skills/apf-warning-impl/services/${SVC}_impl.md"
if [[ -f "$JOURNAL" ]]; then
    TRIED=$(grep -cE '^### Iteration [0-9]+' "$JOURNAL" || echo 0)
else
    TRIED=0
fi

gap_log "block-only gate: $SVC alts=$ALTS tried=$TRIED"

if (( TRIED >= ALTS )); then
    echo VALIDATED
    exit 0
else
    echo "ALTERNATIVES_PENDING: tried=$TRIED < alternatives=$ALTS" >&2
    exit 1
fi
