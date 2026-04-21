#!/usr/bin/env bash
# push-request.sh <request-json-path>
# - Validates JSON
# - Assigns next ID (max requests/*+local_archive/**/* + 1)
# - Enforces rate limit (filesystem pending ≤ 2)
# - Writes requests/{id}_{command}.json
# - Appends to queue.json
# - git add/commit/push with 3-retry
# - stdout: assigned ID on success
# - exit 0 success / exit 1 recoverable (rate-limit / push-fail) / exit 2 fatal

set -eu
# shellcheck disable=SC1091
source "$(dirname "$0")/common.sh"

[[ $# -ge 1 ]] || cr_die "usage: push-request.sh <request-json-path>"
DRAFT="$1"
[[ -f "$DRAFT" ]] || cr_die "draft JSON not found: $DRAFT"

# 1. Validate JSON + required fields
command=$(jq -r '.command // empty' "$DRAFT")
[[ -n "$command" ]] || cr_die "missing .command in draft"
params=$(jq -c '.params // {}' "$DRAFT")
[[ -n "$params" ]] || cr_die "missing .params in draft"

# 2. Rate-limit gate
#    pending = (requests/{id}_*.json ids) - (results/{id}_result.json ids)
REQ_ID_LIST=$(ls "$REQUESTS_DIR"/*.json 2>/dev/null | xargs -n1 -I{} basename {} | sed -nE 's/^0*([0-9]+)_.*\.json$/\1/p' | sort -un)
RES_ID_LIST=$(ls "$RESULTS_DIR"/*_result.json 2>/dev/null | xargs -n1 -I{} basename {} | sed -nE 's/^0*([0-9]+)_.*_result\.json$/\1/p; s/^0*([0-9]+)_result\.json$/\1/p' | sort -un)

PENDING_IDS=""
PENDING_COUNT=0
while IFS= read -r rid; do
    [[ -z "$rid" ]] && continue
    if ! grep -qx "$rid" <<< "$RES_ID_LIST"; then
        PENDING_IDS+="${rid} "
        PENDING_COUNT=$((PENDING_COUNT+1))
    fi
done <<< "$REQ_ID_LIST"

MAX_PENDING="${CR_MAX_PENDING:-2}"
if (( PENDING_COUNT >= MAX_PENDING )); then
    cr_log "rate-limit-gate: pending=${PENDING_COUNT} (ids=${PENDING_IDS}), max=${MAX_PENDING}"
    echo "RATE_LIMIT_EXCEEDED pending=${PENDING_COUNT} ids=${PENDING_IDS}" >&2
    exit 1
fi

# 3. Assign next ID (3-digit zero-padded)
#    scan requests/ + local_archive/ deep
MAX_ID=0
while IFS= read -r f; do
    bn=$(basename "$f")
    id=$(echo "$bn" | sed -nE 's/^0*([0-9]+)_.*\.json$/\1/p')
    [[ -z "$id" ]] && continue
    if (( id > MAX_ID )); then MAX_ID=$id; fi
done < <(find "$REQUESTS_DIR" "$LOCAL_ARCHIVE" -maxdepth 3 -name '[0-9]*_*.json' 2>/dev/null)

NEXT_ID=$((MAX_ID + 1))
ID3=$(printf '%03d' "$NEXT_ID")

# 4. Write final request JSON
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TARGET="$REQUESTS_DIR/${ID3}_${command}.json"
jq --arg id "$ID3" --arg created "$NOW" \
   '.id = $id | .created = $created | .priority = (.priority // "normal") | .attachments = (.attachments // []) | .notes = (.notes // "")' \
   "$DRAFT" > "$TARGET"
cr_log "wrote $TARGET"

# 5. Append to queue.json
if [[ ! -f "$QUEUE_JSON" ]]; then
    echo '{"last_updated":"","tasks":[]}' > "$QUEUE_JSON"
fi
SUMMARY=$(jq -r '.notes // empty' "$DRAFT")
[[ -z "$SUMMARY" ]] && SUMMARY="${command} request"
tmpq=$(mktemp)
jq --arg id "$ID3" --arg cmd "$command" --arg created "$NOW" --arg sum "$SUMMARY" \
   '.tasks += [{id:$id, command:$cmd, to:"test", status:"pending", created:$created, updated:$created, summary:$sum}] | .last_updated = $created' \
   "$QUEUE_JSON" > "$tmpq"
mv "$tmpq" "$QUEUE_JSON"
cr_log "queue.json updated with pending ${ID3}"

# 6. state.json last_request_id
cr_state_set "last_request_id" "$NEXT_ID"

# 7. git add/commit/push (3-retry) — ALL git output → stderr (stdout reserved for ID)
push_attempt() {
    local attempt="$1"
    cr_git add "$TARGET" "$QUEUE_JSON" >&2 || return 1
    cr_git commit -m "cowork-remote: request ${ID3} (${command}) [attempt ${attempt}]" >&2 || return 1
    cr_git push origin HEAD >&2 || return 1
    return 0
}

RETRIES=3
for i in $(seq 1 "$RETRIES"); do
    if push_attempt "$i"; then
        cr_log "git push success (attempt $i)"
        echo "$ID3"  # ← SOLE stdout line
        exit 0
    fi
    cr_log "git push failed attempt $i — recovery"
    case "$i" in
        1) : ;;
        2) cr_git pull --rebase origin HEAD >&2 || true ;;
        3) cr_git stash push -u -m "push-request-retry-${ID3}" >&2 || true
           cr_git pull origin HEAD >&2 || true
           cr_git stash pop >&2 || true ;;
    esac
done

cr_log "git push failed after ${RETRIES} attempts"
exit 1
