#!/usr/bin/env bash
# migrate-queue-multi-pc.sh — one-shot migration adding multi-PC fields to queue.json
#
# Backs up queue.json → queue.json.pre-multipc-bak, then adds for each task:
#   target_pc       = "pc1"           (legacy entries assumed pc1)
#   pc1_status      = .status         (inherits aggregate)
#   pc1_verdict     = ""              (parsed from existing summary tag like [done])
#   pc1_summary     = .summary
#   pc2_status      = "n/a"
#   pc2_verdict     = ""
#   pc2_summary     = ""
#
# Idempotent: if .target_pc already set, the task is skipped.
# exit 0 success / exit 2 fatal.

set -eu
# shellcheck disable=SC1091
source "$(dirname "$0")/common.sh"

[[ -f "$QUEUE_JSON" ]] || cr_die "queue.json not found at $QUEUE_JSON"

BAK="${QUEUE_JSON}.pre-multipc-bak"
if [[ -f "$BAK" ]]; then
    cr_log "backup already exists at $BAK — will overwrite"
fi
cp "$QUEUE_JSON" "$BAK"
cr_log "backup written: $BAK"

TOTAL=$(jq '.tasks | length' "$QUEUE_JSON")
cr_log "tasks total=${TOTAL}"

tmp=$(mktemp)
jq '
  .tasks |= map(
    if has("target_pc") then .
    else
      . + {
        target_pc: "pc1",
        pc1_status: (.status // "pending"),
        pc1_verdict: (
          (.summary // "") as $s
          | if ($s | test("^\\[[a-z_A-Z]+\\]"))
            then ($s | capture("^\\[(?<v>[a-z_A-Z]+)\\]").v)
            else ""
            end
        ),
        pc1_summary: (.summary // ""),
        pc2_status: "n/a",
        pc2_verdict: "",
        pc2_summary: ""
      }
    end
  )
  | .schema_version = "2.0-multi-pc"
' "$QUEUE_JSON" > "$tmp"

mv "$tmp" "$QUEUE_JSON"

MIGRATED=$(jq '[.tasks[] | select(.target_pc == "pc1")] | length' "$QUEUE_JSON")
cr_log "migration complete: target_pc=pc1 count=${MIGRATED} / total=${TOTAL}"
echo "migrated=${MIGRATED}/${TOTAL}"
echo "backup=${BAK}"
exit 0
