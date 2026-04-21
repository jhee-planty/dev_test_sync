#!/usr/bin/env bash
# state-read.sh [field]
# Without field: prints full state.json
# With field: prints single field value (raw)

set -eu
# shellcheck disable=SC1091
source "$(dirname "$0")/common.sh"

cr_state_init_if_missing

if [[ $# -eq 0 ]]; then
    cat "$STATE_JSON"
else
    jq -r ".${1} // empty" "$STATE_JSON"
fi
