#!/usr/bin/env bash
# common.sh — apf-warning-impl runtime shared helpers
set -u

# Repo locations
IMPL_JOURNAL_DIR="${IMPL_JOURNAL_DIR:-$HOME/Documents/workspace/dev_test_sync/shared-skills/apf-warning-impl/services}"

if [[ ! -d "$IMPL_JOURNAL_DIR" ]]; then
    # Fallback: create under dev_test_sync/shared-skills/.../services or tmp for testing
    mkdir -p "$IMPL_JOURNAL_DIR" 2>/dev/null || true
fi

awi_log() {
    printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2
}
awi_die() {
    printf '[apf-warning-impl] FATAL: %s\n' "$*" >&2
    exit 2
}

awi_journal_path() {
    local service="$1"
    echo "${IMPL_JOURNAL_DIR}/${service}_impl.md"
}

awi_validate_service() {
    local s="$1"
    [[ "$s" =~ ^[a-z][a-z0-9_-]+$ ]] || awi_die "invalid service_id: $s"
}

awi_now_iso() {
    date -u +%Y-%m-%dT%H:%M:%SZ
}
