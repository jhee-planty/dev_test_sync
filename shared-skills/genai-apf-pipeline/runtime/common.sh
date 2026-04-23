#!/usr/bin/env bash
# common.sh — genai-apf-pipeline runtime shared helpers
set -u

PIPELINE_STATE="${PIPELINE_STATE:-$HOME/Documents/workspace/claude_work/projects/apf-operation/state/pipeline_state.json}"
DASHBOARD="${DASHBOARD:-$HOME/Documents/workspace/dev_test_sync/local_archive/pipeline_dashboard.md}"
STATUS_MD="${STATUS_MD:-$HOME/Documents/workspace/dev_test_sync/shared-skills/genai-apf-pipeline/services/status.md}"
SCHEMA_VERSION="1.0"

# Dependencies
if ! command -v jq >/dev/null 2>&1; then
    echo "[gap] ERROR: jq required" >&2
    exit 2
fi

gap_log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
gap_die() { printf '[gap] FATAL: %s\n' "$*" >&2; exit 2; }

# Known phase IDs
PHASES=(
    "phase1-har-capture"
    "phase2-analysis-registration"
    "phase3-block-verify"
    "phase4-frontend-inspect"
    "phase5-warning-design"
    "phase6-warning-impl"
    "phase7-release-build"
)

gap_phase_index() {
    local name="$1"
    local i
    for i in "${!PHASES[@]}"; do
        if [[ "${PHASES[$i]}" == "$name" ]]; then
            echo "$i"
            return 0
        fi
    done
    return 1
}

gap_state_init_if_missing() {
    mkdir -p "$(dirname "$PIPELINE_STATE")"
    if [[ ! -f "$PIPELINE_STATE" ]]; then
        cat > "$PIPELINE_STATE" <<EOF
{
  "schema_version": "${SCHEMA_VERSION}",
  "current_service": "",
  "current_phase": "",
  "last_request_id": 0,
  "last_checked_result_id": 0,
  "service_queue": [],
  "done_services": [],
  "failure_history": {},
  "updated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    fi
}

gap_state_get() {
    gap_state_init_if_missing
    jq -r ".${1} // empty" "$PIPELINE_STATE"
}

gap_state_set() {
    gap_state_init_if_missing
    local field="$1" value="$2"
    local tmp; tmp=$(mktemp)
    if [[ "$value" =~ ^[0-9]+$ ]]; then
        jq ".${field} = ${value} | .schema_version = \"${SCHEMA_VERSION}\" | .updated_at = \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"" "$PIPELINE_STATE" > "$tmp"
    else
        jq ".${field} = \"${value}\" | .schema_version = \"${SCHEMA_VERSION}\" | .updated_at = \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"" "$PIPELINE_STATE" > "$tmp"
    fi
    mv "$tmp" "$PIPELINE_STATE"
}
