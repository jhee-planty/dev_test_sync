#!/usr/bin/env bash
# notify.sh <title> <message>
# macOS notification via osascript. Best-effort — never fails the caller.
# Exit 0 always (notification is informational).

set -u
# shellcheck disable=SC1091
source "$(dirname "$0")/common.sh"

TITLE="${1:-cowork-remote}"
MSG="${2:-event}"

if command -v osascript >/dev/null 2>&1; then
    osascript -e "display notification \"${MSG//\"/\\\"}\" with title \"${TITLE//\"/\\\"}\"" >/dev/null 2>&1 || true
else
    cr_log "osascript unavailable — notification skipped: $TITLE / $MSG"
fi

exit 0
