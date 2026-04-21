#!/usr/bin/env bash
# queue-next.sh
# - Picks the pending_check service with lowest priority number (highest priority)
# - stdout: service id (empty if none)
# - exit 0 if found, exit 0 if empty (stdout empty = queue drained)

set -eu
# shellcheck disable=SC1091
source "$(dirname "$0")/common.sh"

gap_state_init_if_missing

NEXT=$(jq -r '
    [.service_queue[] | select(.status == "pending_check")] as $pc
    | if ($pc | length) == 0 then ""
      else ($pc | sort_by(.priority) | .[0].service)
      end
' "$PIPELINE_STATE")

echo "$NEXT"
exit 0
