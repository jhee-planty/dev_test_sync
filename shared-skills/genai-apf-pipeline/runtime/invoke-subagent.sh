#!/usr/bin/env bash
# invoke-subagent.sh --prompt <prompt-file> [--model sonnet|opus|haiku] [--output <json>]
# Dispatch a Claude Code sub-agent (claude -p) with the given prompt.
# Produces output log at --output (default /tmp/gap-subagent-XXXX.log).
# Only works when called from a context that has `claude` CLI on PATH
# (host Mac, not Cowork VM). In Cowork VM, caller must route via desktop-commander.

set -eu
# shellcheck disable=SC1091
source "$(dirname "$0")/common.sh"

PROMPT_FILE=""
MODEL="claude-sonnet-4-6"
OUT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prompt) PROMPT_FILE="$2"; shift 2 ;;
        --model) MODEL="$2"; shift 2 ;;
        --output) OUT="$2"; shift 2 ;;
        *) gap_die "unknown arg: $1" ;;
    esac
done

[[ -f "$PROMPT_FILE" ]] || gap_die "prompt file not found: $PROMPT_FILE"
[[ -z "$OUT" ]] && OUT=$(mktemp /tmp/gap-subagent-XXXXXX.log)

if ! command -v claude >/dev/null 2>&1; then
    gap_die "claude CLI not found on PATH. In Cowork VM, route via desktop-commander.start_process."
fi

PROMPT=$(cat "$PROMPT_FILE")

gap_log "dispatch sub-agent model=$MODEL → $OUT"
claude -p "$PROMPT" \
    --model "$MODEL" \
    --dangerously-skip-permissions \
    --allowedTools "Bash,Read,Grep,Glob" \
    < /dev/null > "$OUT" 2>&1

gap_log "sub-agent done: $OUT"
echo "$OUT"
