#!/usr/bin/env bash
# send-request.sh — Push a test request to dev_test_sync via git
# Creates/copies the request JSON to requests/, commits, and pushes.
# Verifies push reached origin (filesystem-as-authority principle).
#
# Usage:
#   ./send-request.sh <json_file>           # Push existing JSON file
#   ./send-request.sh --check               # Verify repo access + remote
#   ./send-request.sh --repo <path> <file>  # Override repo path
#
# Output: JSONL to stdout (see lib/output-format.md)

SCRIPT_NAME="send-request"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

# ── Defaults ──
REPO="${GIT_SYNC_REPO:-$HOME/Documents/workspace/dev_test_sync}"
JSON_FILE=""
CHECK_MODE=false

# ── Parse arguments ──
while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK_MODE=true; shift ;;
    --repo)  REPO="$2"; shift 2 ;;
    *)       JSON_FILE="$1"; shift ;;
  esac
done

# ── Check mode ──
if $CHECK_MODE; then
  # Verify repo exists and has remote
  if [ -d "$REPO/.git" ]; then
    json_check "repo_exists" "true"
  else
    json_check "repo_exists" "false" "Git repo not found at ${REPO}"
    exit 1
  fi

  if [ -d "$REPO/requests" ]; then
    json_check "requests_dir" "true"
  else
    json_check "requests_dir" "false" "requests/ directory not found"
  fi

  REMOTE_URL=$(git -C "$REPO" remote get-url origin 2>/dev/null)
  if [ -n "$REMOTE_URL" ]; then
    json_check "remote_url" "true"
  else
    json_check "remote_url" "false" "No remote origin configured"
  fi

  # Check HTTPS (SSH may be blocked)
  if echo "$REMOTE_URL" | grep -q "^https://"; then
    json_check "remote_https" "true"
  else
    json_check "remote_https" "false" "Remote uses SSH — may fail in restricted networks"
  fi
  exit 0
fi

# ── Validate input ──
if [ -z "$JSON_FILE" ]; then
  echo '{"error":"No JSON file specified. Usage: send-request.sh <json_file>"}' >&2
  exit 1
fi

if [ ! -f "$JSON_FILE" ]; then
  echo "{\"error\":\"File not found: ${JSON_FILE}\"}" >&2
  exit 1
fi

# Validate JSON syntax
if ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$JSON_FILE" 2>/dev/null; then
  echo "{\"error\":\"Invalid JSON: ${JSON_FILE}\"}" >&2
  exit 1
fi

# Extract request ID from filename (e.g., 217_check-warning.json → 217)
BASENAME=$(basename "$JSON_FILE")
REQUEST_ID=$(echo "$BASENAME" | grep -oE '^[0-9]+' || echo "unknown")

# ── Main execution (4 steps) ──
init_script 4

echo "Repo: $REPO" >> "$LOG_FILE"
echo "File: $JSON_FILE" >> "$LOG_FILE"
echo "Request ID: $REQUEST_ID" >> "$LOG_FILE"

# Step 1: Copy to requests/
json_step_start "copy_request"
DEST="$REPO/requests/$BASENAME"
if [ "$(realpath "$JSON_FILE" 2>/dev/null)" != "$(realpath "$DEST" 2>/dev/null)" ]; then
  cp "$JSON_FILE" "$DEST" >> "$LOG_FILE" 2>&1 || {
    json_step_fail "copy_request" $? "Failed to copy to requests/"
    json_summary; exit 1
  }
fi
json_step_ok "copy_request"

# Step 2: Git add + commit
json_step_start "git_commit"
git -C "$REPO" add "requests/$BASENAME" >> "$LOG_FILE" 2>&1 || {
  json_step_fail "git_commit" $? "git add failed"
  json_summary; exit 1
}
COMMIT_MSG="Request: ${BASENAME%.json}"
git -C "$REPO" commit -m "$COMMIT_MSG" >> "$LOG_FILE" 2>&1 || {
  # Check if "nothing to commit" (file already committed)
  if git -C "$REPO" status --porcelain "requests/$BASENAME" 2>/dev/null | grep -q .; then
    json_step_fail "git_commit" $? "git commit failed"
    json_summary; exit 1
  fi
  echo "Already committed, skipping" >> "$LOG_FILE"
}
COMMIT_HASH=$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null)
echo "Commit: $COMMIT_HASH" >> "$LOG_FILE"
json_step_ok "git_commit"

# Step 3: Git push (with one retry on conflict)
json_step_start "git_push"
PUSH_OK=false
for attempt in 1 2; do
  if git -C "$REPO" push >> "$LOG_FILE" 2>&1; then
    PUSH_OK=true
    break
  fi
  if [ "$attempt" -eq 1 ]; then
    echo "Push failed, attempting pull --rebase + retry" >> "$LOG_FILE"
    git -C "$REPO" pull --rebase >> "$LOG_FILE" 2>&1 || {
      json_step_fail "git_push" $? "pull --rebase failed"
      json_summary; exit 1
    }
  fi
done
if $PUSH_OK; then
  json_step_ok "git_push"
else
  json_step_fail "git_push" 1 "PUSH_FAILED after 2 attempts"
  json_summary; exit 1
fi

# Step 4: Verify push reached origin (last_delivered_id principle)
json_step_start "push_verify"
UNPUSHED=$(git -C "$REPO" log origin/main..HEAD --oneline 2>/dev/null)
if [ -z "$UNPUSHED" ]; then
  echo "Push verified: no unpushed commits" >> "$LOG_FILE"
  json_step_ok "push_verify"
else
  echo "Unpushed commits remain: $UNPUSHED" >> "$LOG_FILE"
  json_step_fail "push_verify" 1 "Unpushed commits remain after push"
  json_summary; exit 1
fi

# ── Summary (with request_id) ──
_TOTAL_DUR=$(( $(date +%s) - _SCRIPT_START ))
echo "{\"run_id\":\"${RUN_ID}\",\"summary\":true,\"completed\":${_COMPLETED},\"failed\":${_FAILED},\"skipped\":${_SKIPPED},\"total\":${_TOTAL_STEPS},\"duration\":${_TOTAL_DUR},\"log\":\"${LOG_FILE}\",\"request_id\":\"${REQUEST_ID}\",\"commit\":\"${COMMIT_HASH}\"}"
