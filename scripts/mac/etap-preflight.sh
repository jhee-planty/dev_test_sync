#!/usr/bin/env bash
# etap-preflight.sh — Pre-build verification for EtapV3
# Checks branch match, symlinks, and changed files before build.
#
# Usage:
#   ./etap-preflight.sh              # Normal run
#   ./etap-preflight.sh --check      # Prerequisite check only (no side effects)
#
# Output: JSONL to stdout (see lib/output-format.md)

SCRIPT_NAME="preflight"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

# ── Check mode ──
if [ "${1:-}" = "--check" ]; then
  # Verify SSH connectivity only
  rc=0
  ssh_cmd "$COMPILE_SERVER" "echo ok" >/dev/null 2>&1 || rc=1
  if [ $rc -eq 0 ]; then
    json_check "compile_server_ssh" "true"
  else
    json_check "compile_server_ssh" "false" "SSH connection to compile server failed"
  fi

  rc=0
  ssh_cmd "$TEST_SERVER" "echo ok" >/dev/null 2>&1 || rc=1
  if [ $rc -eq 0 ]; then
    json_check "test_server_ssh" "true"
  else
    json_check "test_server_ssh" "false" "SSH connection to test server failed"
  fi

  # Verify local repo exists
  if [ -d "$LOCAL_ETAP/.git" ]; then
    json_check "local_repo" "true"
  else
    json_check "local_repo" "false" "Local EtapV3 repo not found at ${LOCAL_ETAP}"
  fi
  exit 0
fi

# ── Normal run ──
init_script 4

# Step 1: Check local branch
json_step_start "local_branch"
LOCAL_BRANCH=$(cd "$LOCAL_ETAP" && git branch --show-current 2>>"$LOG_FILE")
if [ -n "$LOCAL_BRANCH" ]; then
  echo "Local branch: $LOCAL_BRANCH" >> "$LOG_FILE"
  json_step_ok "local_branch"
else
  json_step_fail "local_branch" 1 "Cannot determine local branch"
  json_summary
  exit 1
fi

# Step 2: Check compile server branch (must match local)
json_step_start "branch_match"
REMOTE_BRANCH=$(ssh_cmd "$COMPILE_SERVER" \
  "cd ${REMOTE_SRC} && git branch --show-current" 2>>"$LOG_FILE") || {
  json_step_fail "branch_match" $? "SSH to compile server failed"
  json_summary; exit 1
}
echo "Compile server branch: $REMOTE_BRANCH" >> "$LOG_FILE"
if [ "$LOCAL_BRANCH" = "$REMOTE_BRANCH" ]; then
  json_step_ok "branch_match"
else
  json_step_fail "branch_match" 1 "Branch mismatch: local=${LOCAL_BRANCH} remote=${REMOTE_BRANCH}"
  json_summary; exit 1
fi

# Step 3: Check symlinks on both servers
json_step_start "symlink_check"
COMPILE_SYM=$(ssh_cmd "$COMPILE_SERVER" \
  '[ -L /bin ] && [ -L /lib ] && echo OK || echo BROKEN' 2>>"$LOG_FILE")
TEST_SYM=$(ssh_cmd "$TEST_SERVER" \
  '[ -L /bin ] && [ -L /lib ] && echo OK || echo BROKEN' 2>>"$LOG_FILE")
echo "Compile symlinks: $COMPILE_SYM, Test symlinks: $TEST_SYM" >> "$LOG_FILE"
if [ "$COMPILE_SYM" = "OK" ] && [ "$TEST_SYM" = "OK" ]; then
  json_step_ok "symlink_check"
else
  json_step_fail "symlink_check" 1 "Symlinks broken: compile=${COMPILE_SYM} test=${TEST_SYM}"
  json_summary; exit 1
fi

# Step 4: List changed files
json_step_start "changed_files"
CHANGED=$(cd "$LOCAL_ETAP" && git diff --name-only 2>>"$LOG_FILE")
echo "Changed files:" >> "$LOG_FILE"
echo "$CHANGED" >> "$LOG_FILE"
CHANGE_COUNT=$(echo "$CHANGED" | grep -c . 2>/dev/null || echo 0)
if [ "$CHANGE_COUNT" -gt 0 ]; then
  json_step_ok "changed_files"
else
  # No changes is not a failure, but worth reporting
  json_step_ok "changed_files"
  echo "WARNING: No changed files detected" >> "$LOG_FILE"
fi

# ── Summary ──
json_summary
