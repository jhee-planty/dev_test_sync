#!/usr/bin/env bash
# common.sh — sourced by all cowork-remote runtime scripts
# Provides: GIT_SYNC_REPO resolution, state file paths, logging helpers, jq dep check.

set -u  # strict mode (caller decides on -e based on context)

# Repo root resolution
if [[ -z "${GIT_SYNC_REPO:-}" ]]; then
    GIT_SYNC_REPO="$HOME/Documents/workspace/dev_test_sync"
fi
if [[ ! -d "$GIT_SYNC_REPO/.git" ]]; then
    echo "[cowork-remote] ERROR: GIT_SYNC_REPO '$GIT_SYNC_REPO' is not a git repo" >&2
    exit 2
fi

export GIT_SYNC_REPO
REQUESTS_DIR="$GIT_SYNC_REPO/requests"
RESULTS_DIR="$GIT_SYNC_REPO/results"
QUEUE_JSON="$GIT_SYNC_REPO/queue.json"
LOCAL_ARCHIVE="$GIT_SYNC_REPO/local_archive"
STATE_JSON="$LOCAL_ARCHIVE/state.json"

mkdir -p "$LOCAL_ARCHIVE"

# jq dependency
if ! command -v jq >/dev/null 2>&1; then
    echo "[cowork-remote] ERROR: 'jq' is required but not installed" >&2
    exit 2
fi

# Logging
cr_log() {
    # stderr timestamped
    printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2
}

cr_die() {
    # fatal error
    printf '[cowork-remote] FATAL: %s\n' "$*" >&2
    exit 2
}

# Initialize state.json if missing
cr_state_init_if_missing() {
    if [[ ! -f "$STATE_JSON" ]]; then
        cat > "$STATE_JSON" <<EOF
{
  "last_request_id": 0,
  "last_checked_result_id": 0,
  "updated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "schema_version": "1.0"
}
EOF
    fi
}

# Read state field
cr_state_get() {
    local field="$1"
    cr_state_init_if_missing
    jq -r ".${field} // empty" "$STATE_JSON"
}

# Write state field (non-atomic, single writer assumed)
cr_state_set() {
    local field="$1"
    local value="$2"
    cr_state_init_if_missing
    local tmp
    tmp="$(mktemp)"
    # Numeric vs string detection
    if [[ "$value" =~ ^[0-9]+$ ]]; then
        jq ".${field} = ${value} | .updated_at = \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"" "$STATE_JSON" > "$tmp"
    else
        jq ".${field} = \"${value}\" | .updated_at = \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"" "$STATE_JSON" > "$tmp"
    fi
    mv "$tmp" "$STATE_JSON"
}

# Git command wrapper (in repo, suppress color)
cr_git() {
    git -C "$GIT_SYNC_REPO" -c color.ui=false "$@"
}
