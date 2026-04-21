#!/usr/bin/env bash
# state-update.sh <field> <value>
# Sets state.json field (single field at a time). Auto-stamps updated_at.

set -eu
# shellcheck disable=SC1091
source "$(dirname "$0")/common.sh"

[[ $# -eq 2 ]] || cr_die "usage: state-update.sh <field> <value>"
cr_state_set "$1" "$2"
cr_log "state.json: $1 = $2"
