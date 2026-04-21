#!/usr/bin/env bash
set -eu
# shellcheck disable=SC1091
source "$(dirname "$0")/common.sh"
[[ $# -eq 2 ]] || gap_die "usage: state-set.sh <field> <value>"
gap_state_set "$1" "$2"
gap_log "state: $1 = $2"
