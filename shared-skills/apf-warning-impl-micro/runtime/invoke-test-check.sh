#!/usr/bin/env bash
# invoke-test-check.sh --service <id> --expected "<text>" [--timeout-sec N]
# - Composes request JSON for check-warning
# - Calls cowork-remote-micro push-request.sh (dev side)
# - stdout: assigned request ID
# - exit: 0 success, 1 rate-limited/push-fail, 2 fatal
#
# Note: This only PUSHES. Subsequent result scan is the caller's responsibility
# (typically loops bash $CR_RT/scan-results.sh until the ID appears).

set -eu

SERVICE=""
EXPECTED=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --service) SERVICE="$2"; shift 2 ;;
        --expected) EXPECTED="$2"; shift 2 ;;
        --timeout-sec) shift 2 ;;  # informational only
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done
[[ -n "$SERVICE" ]] || { echo "--service required" >&2; exit 2; }
[[ -n "$EXPECTED" ]] || { echo "--expected required" >&2; exit 2; }

CR_PUSH="${APF_CR_PUSH:-/Users/jhee/Documents/workspace/claude_cowork/projects/cowork-micro-skills/runtime/cowork-remote/push-request.sh}"
[[ -x "$CR_PUSH" ]] || { echo "cowork-remote push-request not found at $CR_PUSH" >&2; exit 2; }

DRAFT=$(mktemp /tmp/awi-draft-XXXXXX.json)
cat > "$DRAFT" <<EOF
{
  "command": "check-warning",
  "params": {
    "service": "${SERVICE}",
    "expected_text": "${EXPECTED}",
    "expected_format": "readable warning in chat bubble",
    "capture_console": true
  },
  "notes": "apf-warning-impl-micro iteration check"
}
EOF

"$CR_PUSH" "$DRAFT"
EC=$?
rm -f "$DRAFT"
exit $EC
