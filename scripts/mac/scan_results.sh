#!/usr/bin/env bash
# scan_results.sh — Filesystem-based result detection (sync ≠ detect)
# Scans results/ for new result files that haven't been processed yet.
# Decoupled from git pull output — "Already up to date" does NOT mean "no results".
#
# Usage:
#   ./scan_results.sh                    # Scan using queue.json last_checked_result_id
#   ./scan_results.sh --after <id>       # Scan for results after specific ID
#   ./scan_results.sh --repo <path>      # Override repo path
#   ./scan_results.sh --list             # Just list new result files (no JSON output)
#
# Output: JSONL to stdout (see lib/output-format.md)
# Exit codes: 0 = success (new results found), 1 = no new results, 2 = error

SCRIPT_NAME="scan-results"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# lib/common.sh 로드 — 없으면 standalone 모드 (no-op fallback)
if [ -f "${SCRIPT_DIR}/../lib/common.sh" ]; then
  source "${SCRIPT_DIR}/../lib/common.sh"
else
  # Minimal fallback: JSONL helper functions as no-ops
  json_step_start() { :; }
  json_summary() { :; }
  RUN_ID="standalone-$$"
fi

# ── Defaults ──
REPO="${GIT_SYNC_REPO:-$HOME/Documents/workspace/dev_test_sync}"
AFTER_ID=""
LIST_ONLY=false

# ── Parse arguments ──
while [ $# -gt 0 ]; do
  case "$1" in
    --after) AFTER_ID="$2"; shift 2 ;;
    --repo)  REPO="$2"; shift 2 ;;
    --list)  LIST_ONLY=true; shift ;;
    *)       echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

RESULTS_DIR="${REPO}/results"
QUEUE_FILE="${REPO}/queue.json"

# ── Determine baseline ID ──
if [ -z "$AFTER_ID" ]; then
  # Try queue.json → last_checked_result_id
  if [ -f "$QUEUE_FILE" ]; then
    AFTER_ID=$(python3 -c "
import json, sys
try:
    q = json.load(open('${QUEUE_FILE}'))
    val = q.get('last_checked_result_id', '')
    print(val if val else '')
except:
    print('')
" 2>/dev/null)
  fi

  # Fallback: try pipeline_state.json → last_delivered_id
  if [ -z "$AFTER_ID" ]; then
    STATE_FILE="${REPO}/local_archive/pipeline_state.json"
    if [ -f "$STATE_FILE" ]; then
      AFTER_ID=$(python3 -c "
import json
try:
    s = json.load(open('${STATE_FILE}'))
    val = s.get('last_delivered_id', s.get('last_request_id', ''))
    print(val if val else '')
except:
    print('')
" 2>/dev/null)
    fi
  fi

  # Final fallback: 0 (scan all)
  if [ -z "$AFTER_ID" ]; then
    AFTER_ID="0"
  fi
fi

# Normalize to integer
AFTER_ID=$(echo "$AFTER_ID" | grep -oE '[0-9]+' | head -1)
AFTER_ID="${AFTER_ID:-0}"

# ── Scan results/ directory ──
if [ ! -d "$RESULTS_DIR" ]; then
  echo "{\"error\":\"results directory not found: ${RESULTS_DIR}\"}" >&2
  exit 2
fi

# Find all result files, extract IDs, filter those > AFTER_ID
NEW_RESULTS=()
for f in "${RESULTS_DIR}"/*_result.json; do
  [ -f "$f" ] || continue
  basename=$(basename "$f")
  id=$(echo "$basename" | grep -oE '^[0-9]+')
  [ -z "$id" ] && continue
  id_num=$((10#$id))  # Remove leading zeros for comparison
  if [ "$id_num" -gt "$AFTER_ID" ]; then
    NEW_RESULTS+=("$basename")
  fi
done

# ── Output ──
COUNT=${#NEW_RESULTS[@]}

if $LIST_ONLY; then
  if [ "$COUNT" -eq 0 ]; then
    echo "No new results after ID ${AFTER_ID}"
    exit 1
  fi
  for r in "${NEW_RESULTS[@]}"; do
    echo "$r"
  done
  exit 0
fi

# JSONL output
_TOTAL_STEPS=1
json_step_start "scan_results"

if [ "$COUNT" -eq 0 ]; then
  echo "{\"run_id\":\"${RUN_ID}\",\"step\":1,\"total\":1,\"name\":\"scan_results\",\"status\":\"ok\",\"duration\":0,\"detail\":\"no_new_results\",\"after_id\":${AFTER_ID},\"found\":0}"
  json_summary
  exit 1
fi

# Build file list as JSON array
FILES_JSON="["
first=true
for r in "${NEW_RESULTS[@]}"; do
  if $first; then first=false; else FILES_JSON+=","; fi
  FILES_JSON+="\"${r}\""
done
FILES_JSON+="]"

echo "{\"run_id\":\"${RUN_ID}\",\"step\":1,\"total\":1,\"name\":\"scan_results\",\"status\":\"ok\",\"duration\":0,\"detail\":\"new_results_found\",\"after_id\":${AFTER_ID},\"found\":${COUNT},\"files\":${FILES_JSON}}"
json_summary

exit 0
