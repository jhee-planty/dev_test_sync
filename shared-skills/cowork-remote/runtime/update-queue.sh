#!/usr/bin/env bash
# update-queue.sh <id> <verdict> [summary] [--pc pc1|pc2]
# - Updates queue.json task[id] per-PC fields (multi-PC mode) or legacy fields.
# - --pc pc1|pc2  : writes pc{N}_status, pc{N}_verdict, pc{N}_summary; then
#                   recomputes aggregate .status via union-FAIL rule (Dual verify):
#                     - any pc{N}_status == "error" → aggregate "error"
#                     - any pc{N}_status == "pending" (and other not n/a) → "pending"
#                     - both done (or one done + one n/a) → "done"
#                     - both n/a → "pending"
# - No --pc       : legacy single-PC behavior (writes .status + .summary directly).
# - Updates state.json.last_checked_result_id to max(id, current)
# - exit 0 success / exit 2 fatal

set -eu
# shellcheck disable=SC1091
source "$(dirname "$0")/common.sh"

# --- arg parse ---
POS=()
PC=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --pc) PC="$2"; shift 2 ;;
        --pc=*) PC="${1#*=}"; shift ;;
        --) shift; while [[ $# -gt 0 ]]; do POS+=("$1"); shift; done ;;
        *) POS+=("$1"); shift ;;
    esac
done

[[ ${#POS[@]} -ge 2 ]] || cr_die "usage: update-queue.sh <id> <verdict> [summary] [--pc pc1|pc2]"
ID_RAW="${POS[0]}"
VERDICT="${POS[1]}"
SUMMARY="${POS[2]:-}"

# Normalize ID (3-digit zero-padded)
ID_NUM=$((10#$ID_RAW))
ID3=$(printf '%03d' "$ID_NUM")

# Validate PC
if [[ -n "$PC" ]]; then
    case "$PC" in
        pc1|pc2) : ;;
        *) cr_die "invalid --pc: '$PC' (must be pc1|pc2)" ;;
    esac
fi

# Map verdict → status
case "$VERDICT" in
    done) STATUS="done" ;;
    error_PROTOCOL_MISMATCH|error_NOT_RENDERED|error_SERVICE_CHANGED|error_AUTH_REQUIRED|error_INFRASTRUCTURE) STATUS="error" ;;
    *) cr_die "unknown verdict: $VERDICT" ;;
esac

[[ -f "$QUEUE_JSON" ]] || cr_die "queue.json not found at $QUEUE_JSON"

# Combined summary
FULL_SUMMARY="[${VERDICT}]"
[[ -n "$SUMMARY" ]] && FULL_SUMMARY+=" ${SUMMARY}"

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
tmp=$(mktemp)

# If task not in queue: append minimal entry
EXIST=$(jq --arg id "$ID3" '[.tasks[] | select(.id == $id)] | length' "$QUEUE_JSON")
if [[ "$EXIST" == "0" ]]; then
    cr_log "task $ID3 not in queue.json — appending"
    if [[ -n "$PC" ]]; then
        if [[ "$PC" == "pc1" ]]; then
            jq --arg id "$ID3" --arg status "$STATUS" --arg ver "$VERDICT" --arg sum "$FULL_SUMMARY" --arg now "$NOW" \
               '.tasks += [{
                    id:$id, command:"(unknown)", to:"test", status:$status,
                    created:$now, updated:$now, summary:$sum,
                    target_pc:"pc1",
                    pc1_status:$status, pc1_verdict:$ver, pc1_summary:$sum,
                    pc2_status:"n/a",   pc2_verdict:"",   pc2_summary:""
                }] | .last_updated = $now' \
               "$QUEUE_JSON" > "$tmp"
        else
            jq --arg id "$ID3" --arg status "$STATUS" --arg ver "$VERDICT" --arg sum "$FULL_SUMMARY" --arg now "$NOW" \
               '.tasks += [{
                    id:$id, command:"(unknown)", to:"test", status:$status,
                    created:$now, updated:$now, summary:$sum,
                    target_pc:"pc2",
                    pc1_status:"n/a", pc1_verdict:"", pc1_summary:"",
                    pc2_status:$status, pc2_verdict:$ver, pc2_summary:$sum
                }] | .last_updated = $now' \
               "$QUEUE_JSON" > "$tmp"
        fi
    else
        jq --arg id "$ID3" --arg status "$STATUS" --arg sum "$FULL_SUMMARY" --arg now "$NOW" \
           '.tasks += [{id:$id, command:"(unknown)", to:"test", status:$status, created:$now, updated:$now, summary:$sum}] | .last_updated = $now' \
           "$QUEUE_JSON" > "$tmp"
    fi
    mv "$tmp" "$QUEUE_JSON"
    cr_log "queue.json appended: $ID3 → $STATUS [$VERDICT] pc=${PC:-legacy}"
else
    # Existing task
    if [[ -n "$PC" ]]; then
        # 1) Per-PC fields write
        jq --arg id "$ID3" --arg pc "$PC" --arg s "$STATUS" --arg v "$VERDICT" --arg sum "$FULL_SUMMARY" --arg now "$NOW" \
           '(.tasks[] | select(.id == $id)) |= (
                .updated = $now
                | if $pc == "pc1" then
                    .pc1_status = $s | .pc1_verdict = $v | .pc1_summary = $sum
                  else
                    .pc2_status = $s | .pc2_verdict = $v | .pc2_summary = $sum
                  end
            ) | .last_updated = $now' \
           "$QUEUE_JSON" > "$tmp"
        mv "$tmp" "$QUEUE_JSON"

        # 2) Aggregate recompute (union-FAIL)
        tmp2=$(mktemp)
        jq --arg id "$ID3" --arg now "$NOW" '
            (.tasks[] | select(.id == $id)) |= (
                . as $t
                | (
                    if ($t.pc1_status == "n/a") and ($t.pc2_status == "n/a") then "pending"
                    elif ($t.pc1_status == "error") or ($t.pc2_status == "error") then "error"
                    elif ($t.pc1_status == "pending") or ($t.pc2_status == "pending") then "pending"
                    elif ($t.pc1_status == "done") and (($t.pc2_status == "done") or ($t.pc2_status == "n/a")) then "done"
                    elif ($t.pc2_status == "done") and ($t.pc1_status == "n/a") then "done"
                    else "pending"
                    end
                  ) as $agg
                | .status = $agg
                | .summary = (
                    [
                      (if ($t.pc1_summary // "") != "" then "pc1:" + $t.pc1_summary else empty end),
                      (if ($t.pc2_summary // "") != "" then "pc2:" + $t.pc2_summary else empty end)
                    ] | join(" | ")
                  )
                | .updated = $now
            ) | .last_updated = $now
        ' "$QUEUE_JSON" > "$tmp2"
        mv "$tmp2" "$QUEUE_JSON"

        AGG=$(jq -r --arg id "$ID3" '.tasks[] | select(.id == $id) | .status' "$QUEUE_JSON")
        cr_log "queue.json updated: $ID3 ${PC}→$STATUS [$VERDICT] aggregate=$AGG"
    else
        # Legacy single-PC update
        jq --arg id "$ID3" --arg status "$STATUS" --arg sum "$FULL_SUMMARY" --arg now "$NOW" \
           '(.tasks[] | select(.id == $id)) |= (.status = $status | .updated = $now | .summary = $sum) | .last_updated = $now' \
           "$QUEUE_JSON" > "$tmp"
        mv "$tmp" "$QUEUE_JSON"
        cr_log "queue.json updated (legacy): $ID3 → $STATUS [$VERDICT]"
    fi
fi

# Update last_checked_result_id if higher
CUR=$(cr_state_get "last_checked_result_id")
[[ -z "$CUR" ]] && CUR=0
if (( ID_NUM > CUR )); then
    cr_state_set "last_checked_result_id" "$ID_NUM"
fi

exit 0
