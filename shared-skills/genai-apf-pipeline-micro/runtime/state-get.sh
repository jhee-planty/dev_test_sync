#!/usr/bin/env bash
set -eu
# shellcheck disable=SC1091
source "$(dirname "$0")/common.sh"
[[ $# -ge 1 ]] || { cat "$PIPELINE_STATE"; exit 0; }
gap_state_get "$1"
