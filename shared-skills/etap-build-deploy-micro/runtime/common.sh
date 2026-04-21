#!/usr/bin/env bash
# common.sh — Shared functions for pipeline scripts
# Source this file: source "$(dirname "$0")/../lib/common.sh"

set -euo pipefail

# ── Run ID ──
RUN_ID="$(date +%Y%m%d-%H%M%S)-$$"

# ── Servers ──
COMPILE_SERVER="solution@61.79.198.110"
TEST_SERVER="solution@218.232.120.58"
SSH_PORT="12222"

# ── Paths ──
LOCAL_ETAP="$HOME/Documents/workspace/Officeguard/EtapV3"
REMOTE_SRC="/home/solution/source/EtapV3"
REMOTE_BUILD="/home/solution/source/EtapV3/build/sv_x86_64_debug"
DEPLOY_PATH="/home/solution"

# ── Step tracking ──
_STEP_NUM=0
_TOTAL_STEPS=0
_COMPLETED=0
_FAILED=0
_SKIPPED=0
_SCRIPT_START=0
_STEP_START=0

# ── Log file ──
SCRIPT_NAME="${SCRIPT_NAME:-unknown}"
LOG_DIR="/tmp"
LOG_FILE="${LOG_DIR}/etap-${SCRIPT_NAME}-$(date +%Y%m%d-%H%M%S).log"

# Clean logs older than 24h
find "$LOG_DIR" -name "etap-${SCRIPT_NAME}-*.log" -mmin +1440 -delete 2>/dev/null || true

# ── JSONL output helpers ──
json_step_start() {
  local name="$1"
  _STEP_NUM=$((_STEP_NUM + 1))
  _STEP_START=$(date +%s)
  echo "{\"run_id\":\"${RUN_ID}\",\"step\":${_STEP_NUM},\"total\":${_TOTAL_STEPS},\"name\":\"${name}\",\"status\":\"start\"}"
}

json_step_ok() {
  local name="$1"
  local dur=$(( $(date +%s) - _STEP_START ))
  _COMPLETED=$((_COMPLETED + 1))
  echo "{\"run_id\":\"${RUN_ID}\",\"step\":${_STEP_NUM},\"total\":${_TOTAL_STEPS},\"name\":\"${name}\",\"status\":\"ok\",\"duration\":${dur}}"
}

json_step_fail() {
  local name="$1" exit_code="$2" error="$3"
  local dur=$(( $(date +%s) - _STEP_START ))
  _FAILED=$((_FAILED + 1))
  # Escape quotes in error message
  error="${error//\"/\\\"}"
  echo "{\"run_id\":\"${RUN_ID}\",\"step\":${_STEP_NUM},\"total\":${_TOTAL_STEPS},\"name\":\"${name}\",\"status\":\"fail\",\"exit_code\":${exit_code},\"error\":\"${error}\",\"duration\":${dur}}"
}

json_step_skip() {
  local name="$1" reason="$2"
  _STEP_NUM=$((_STEP_NUM + 1))
  _SKIPPED=$((_SKIPPED + 1))
  reason="${reason//\"/\\\"}"
  echo "{\"run_id\":\"${RUN_ID}\",\"step\":${_STEP_NUM},\"total\":${_TOTAL_STEPS},\"name\":\"${name}\",\"status\":\"skip\",\"reason\":\"${reason}\"}"
}

json_check() {
  local name="$1" passed="$2" error="${3:-}"
  if [ "$passed" = "true" ]; then
    echo "{\"run_id\":\"${RUN_ID}\",\"check\":true,\"name\":\"${name}\",\"passed\":true}"
  else
    error="${error//\"/\\\"}"
    echo "{\"run_id\":\"${RUN_ID}\",\"check\":true,\"name\":\"${name}\",\"passed\":false,\"error\":\"${error}\"}"
  fi
}

json_summary() {
  local total_dur=$(( $(date +%s) - _SCRIPT_START ))
  echo "{\"run_id\":\"${RUN_ID}\",\"summary\":true,\"completed\":${_COMPLETED},\"failed\":${_FAILED},\"skipped\":${_SKIPPED},\"total\":${_TOTAL_STEPS},\"duration\":${total_dur},\"log\":\"${LOG_FILE}\"}"
}

# ── SSH helper ──
ssh_cmd() {
  local server="$1"; shift
  ssh -p "$SSH_PORT" -o ConnectTimeout=10 -o BatchMode=yes "$server" "$@"
}

# ── Step runner ──
# Usage: run_step "step_name" command args...
# Captures output to log, emits JSONL to stdout
run_step() {
  local name="$1"; shift
  json_step_start "$name"
  
  local rc=0
  "$@" >> "$LOG_FILE" 2>&1 || rc=$?
  
  if [ $rc -eq 0 ]; then
    json_step_ok "$name"
  else
    local err_line
    err_line=$(tail -1 "$LOG_FILE" 2>/dev/null || echo "unknown error")
    json_step_fail "$name" "$rc" "$err_line"
    json_summary
    exit 1
  fi
}

# ── Init ──
init_script() {
  _TOTAL_STEPS="$1"
  _SCRIPT_START=$(date +%s)
  echo "=== ${SCRIPT_NAME} run_id=${RUN_ID} ===" > "$LOG_FILE"
  echo "Started at $(date)" >> "$LOG_FILE"
}
