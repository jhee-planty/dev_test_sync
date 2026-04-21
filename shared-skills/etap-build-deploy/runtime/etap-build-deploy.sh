#!/usr/bin/env bash
# etap-build-deploy.sh — Full build-deploy cycle for EtapV3
# Source sync → Build → Package download → Deploy → Install → Verify
#
# Usage:
#   ./etap-build-deploy.sh [file1 file2 ...]   # Sync specific files
#   ./etap-build-deploy.sh                      # Auto-detect changed files (git diff)
#   ./etap-build-deploy.sh --check              # Prerequisite check only
#   ./etap-build-deploy.sh --date YYMMDD        # Override package date
#
# Output: JSONL to stdout (see lib/output-format.md)

SCRIPT_NAME="build-deploy"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/./common.sh"

# ── Parse arguments ──
PKG_DATE=$(date +%y%m%d)
FILES=()
CHECK_MODE=false

while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK_MODE=true; shift ;;
    --date)  PKG_DATE="$2"; shift 2 ;;
    *)       FILES+=("$1"); shift ;;
  esac
done

PKG_NAME="etap-root-${PKG_DATE}.sv.debug.x86_64.el.tgz"

# ── Check mode ──
if $CHECK_MODE; then
  # Run preflight as check
  bash "${SCRIPT_DIR}/etap-preflight.sh" --check
  exit $?
fi

# ── Resolve file list ──
if [ ${#FILES[@]} -eq 0 ]; then
  while IFS= read -r line; do FILES+=("$line"); done < <(cd "$LOCAL_ETAP" && git diff --name-only 2>/dev/null)
fi

if [ ${#FILES[@]} -eq 0 ]; then
  echo "{\"run_id\":\"${RUN_ID}\",\"summary\":true,\"completed\":0,\"failed\":0,\"skipped\":0,\"total\":0,\"duration\":0,\"log\":\"\",\"error\":\"No changed files to deploy\"}"
  exit 0
fi

# ── Main execution (8 steps) ──
init_script 8

echo "Files to sync: ${FILES[*]}" >> "$LOG_FILE"
echo "Package date: ${PKG_DATE}" >> "$LOG_FILE"
echo "Package name: ${PKG_NAME}" >> "$LOG_FILE"

# Step 1: Source sync (local → compile server)
json_step_start "source_sync"
SYNC_OK=true
for f in "${FILES[@]}"; do
  echo "Syncing: $f" >> "$LOG_FILE"
  scp -P "$SSH_PORT" \
    "${LOCAL_ETAP}/${f}" \
    "${COMPILE_SERVER}:${REMOTE_SRC}/${f}" >> "$LOG_FILE" 2>&1 || {
    echo "FAILED to sync: $f" >> "$LOG_FILE"
    SYNC_OK=false
    break
  }
done
if $SYNC_OK; then
  json_step_ok "source_sync"
else
  json_step_fail "source_sync" 1 "scp transfer failed for: $f"
  json_summary; exit 1
fi

# Step 2: Build (ninja)
json_step_start "ninja_build"
BUILD_OUT=$(ssh_cmd "$COMPILE_SERVER" \
  "cd ${REMOTE_BUILD} && sudo ninja" 2>&1) || {
  echo "$BUILD_OUT" >> "$LOG_FILE"
  FIRST_ERR=$(echo "$BUILD_OUT" | grep -m1 "FAILED\|error:" || echo "build failed")
  json_step_fail "ninja_build" 1 "$FIRST_ERR"
  json_summary; exit 1
}
echo "$BUILD_OUT" >> "$LOG_FILE"
json_step_ok "ninja_build"

# Step 3: Install (ninja install — creates package)
json_step_start "ninja_install"
INSTALL_OUT=$(ssh_cmd "$COMPILE_SERVER" \
  "cd ${REMOTE_BUILD} && sudo ninja install" 2>&1) || {
  echo "$INSTALL_OUT" >> "$LOG_FILE"
  json_step_fail "ninja_install" 1 "ninja install failed"
  json_summary; exit 1
}
echo "$INSTALL_OUT" >> "$LOG_FILE"
# Verify package exists
PKG_EXISTS=$(ssh_cmd "$COMPILE_SERVER" \
  "[ -f /tmp/${PKG_NAME} ] && echo YES || echo NO" 2>>"$LOG_FILE")
if [ "$PKG_EXISTS" != "YES" ]; then
  json_step_fail "ninja_install" 1 "Package /tmp/${PKG_NAME} not found after install"
  json_summary; exit 1
fi
json_step_ok "ninja_install"

# Step 4: Download package (compile → local)
json_step_start "pkg_download"
scp -P "$SSH_PORT" \
  "${COMPILE_SERVER}:/tmp/${PKG_NAME}" \
  "$HOME/Downloads/" >> "$LOG_FILE" 2>&1 || {
  json_step_fail "pkg_download" $? "scp download failed"
  json_summary; exit 1
}
json_step_ok "pkg_download"

# Step 5: Upload package (local → test server)
json_step_start "pkg_upload"
scp -P "$SSH_PORT" \
  "$HOME/Downloads/${PKG_NAME}" \
  "${TEST_SERVER}:${DEPLOY_PATH}/" >> "$LOG_FILE" 2>&1 || {
  json_step_fail "pkg_upload" $? "scp upload to test server failed"
  json_summary; exit 1
}
json_step_ok "pkg_upload"

# Step 6: Deploy safety check (tarball + symlinks)
json_step_start "deploy_safety"
# Check tarball contents for dangerous paths
TAR_CHECK=$(ssh_cmd "$TEST_SERVER" \
  "tar tzf ${DEPLOY_PATH}/${PKG_NAME} | head -30" 2>>"$LOG_FILE")
echo "Tarball contents:" >> "$LOG_FILE"
echo "$TAR_CHECK" >> "$LOG_FILE"
# Look for dangerous top-level entries
if echo "$TAR_CHECK" | grep -qE '^(bin/|lib/|sbin/|etc/)'; then
  json_step_fail "deploy_safety" 1 "DANGEROUS: tarball contains top-level bin/ or lib/ entries"
  json_summary; exit 1
fi
# Check symlinks
SYM_STATUS=$(ssh_cmd "$TEST_SERVER" \
  '[ -L /bin ] && [ -L /lib ] && echo OK || echo BROKEN' 2>>"$LOG_FILE")
if [ "$SYM_STATUS" != "OK" ]; then
  json_step_fail "deploy_safety" 1 "System symlinks BROKEN on test server"
  json_summary; exit 1
fi
json_step_ok "deploy_safety"

# Step 7: Extract + restart
json_step_start "install_restart"
# Extract
ssh_cmd "$TEST_SERVER" \
  "sudo tar xzf ${DEPLOY_PATH}/${PKG_NAME} -C /usr/local" >> "$LOG_FILE" 2>&1 || {
  json_step_fail "install_restart" $? "tar extract failed"
  json_summary; exit 1
}
# Post-extract symlink check
POST_SYM=$(ssh_cmd "$TEST_SERVER" \
  '[ -L /bin ] && [ -L /lib ] && echo OK || echo BROKEN' 2>>"$LOG_FILE")
if [ "$POST_SYM" != "OK" ]; then
  json_step_fail "install_restart" 1 "CRITICAL: symlinks destroyed after extract — DO NOT restart"
  json_summary; exit 1
fi
# Restart (daemon-reload first in case unit file changed)
ssh_cmd "$TEST_SERVER" \
  "sudo systemctl daemon-reload && sudo systemctl restart etapd.service" >> "$LOG_FILE" 2>&1 || {
  json_step_fail "install_restart" $? "systemctl restart failed"
  json_summary; exit 1
}
json_step_ok "install_restart"

# Step 8: Post-deploy verify
json_step_start "post_verify"
SVC_STATUS=$(ssh_cmd "$TEST_SERVER" \
  "systemctl status etapd.service | head -5" 2>>"$LOG_FILE")
echo "$SVC_STATUS" >> "$LOG_FILE"
if echo "$SVC_STATUS" | grep -q "active (running)"; then
  # Check binary timestamp
  BIN_TS=$(ssh_cmd "$TEST_SERVER" \
    "ls -la /usr/local/bin/etapd 2>/dev/null | awk '{print \$6, \$7, \$8}'" 2>>"$LOG_FILE")
  echo "Binary timestamp: $BIN_TS" >> "$LOG_FILE"
  json_step_ok "post_verify"
else
  json_step_fail "post_verify" 1 "DEPLOYED_BUT_UNHEALTHY: etapd not running after restart"
  json_summary; exit 1
fi

# ── Summary ──
json_summary
