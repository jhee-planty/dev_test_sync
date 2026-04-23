#!/usr/bin/env bash
# invoke-build-deploy.sh [file1 file2 ...]
# Wrapper around etap-build-deploy-micro runtime.
# - Resolves runtime path (project-relative or env override)
# - Pipes through args
# - stdout: JSONL from sub-runtime (caller parses)
# - exit: same as sub-runtime

set -eu

BD_RUNTIME="${APF_BD_RUNTIME:-/Users/jhee/Documents/workspace/claude_work/projects/cowork-micro-skills/runtime/etap-build-deploy/etap-build-deploy.sh}"

if [[ ! -x "$BD_RUNTIME" ]]; then
    echo "[apf-warning-impl] FATAL: etap-build-deploy runtime not executable at $BD_RUNTIME" >&2
    exit 2
fi

"$BD_RUNTIME" "$@"
