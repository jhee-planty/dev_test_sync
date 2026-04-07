# Script Output Format Specification (JSONL)

## Overview

All pipeline scripts output structured JSONL (JSON Lines) to stdout.
Each line is a self-contained JSON object the AI agent can parse.
Verbose/debug output goes to a log file on disk, NOT stdout.

## Fields

### Step Event

```json
{"run_id":"<uuid>","step":<N>,"total":<T>,"name":"<step_name>","status":"start"}
{"run_id":"<uuid>","step":<N>,"total":<T>,"name":"<step_name>","status":"ok","duration":<seconds>}
{"run_id":"<uuid>","step":<N>,"total":<T>,"name":"<step_name>","status":"fail","exit_code":<N>,"error":"<message>","duration":<seconds>}
{"run_id":"<uuid>","step":<N>,"total":<T>,"name":"<step_name>","status":"skip","reason":"<why>"}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| run_id | string | yes | Unique per execution (date+PID: YYYYMMDD-HHMMSS-$$) |
| step | int | yes | 1-based step number |
| total | int | yes | Total steps in this script |
| name | string | yes | Step identifier (snake_case) |
| status | enum | yes | "start", "ok", "fail", "skip" |
| duration | float | on ok/fail | Seconds elapsed for this step |
| exit_code | int | on fail | Exit code of failed command |
| error | string | on fail | First line of stderr or error message |
| reason | string | on skip | Why this step was skipped |


### Summary Event (always last line)

```json
{"run_id":"<uuid>","summary":true,"completed":<N>,"failed":<N>,"skipped":<N>,"total":<T>,"duration":<total_seconds>,"log":"<path>"}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| summary | bool | yes | Always `true` — marks this as summary line |
| completed | int | yes | Steps that finished with status "ok" |
| failed | int | yes | Steps that finished with status "fail" |
| skipped | int | yes | Steps that were skipped |
| total | int | yes | Total steps |
| duration | float | yes | Total wall-clock seconds |
| log | string | yes | Absolute path to verbose log file |

### Check Mode Event (--check output)

```json
{"run_id":"<uuid>","check":true,"name":"<check_name>","passed":true}
{"run_id":"<uuid>","check":true,"name":"<check_name>","passed":false,"error":"<details>"}
```

## Log File Convention

- Path: `/tmp/etap-<script>-<YYYYMMDD-HHMMSS>.log`
- Contains: full command output, stderr, timestamps
- Auto-cleanup: each script deletes logs older than 24 hours at start

## Cross-Platform

`.sh` (Mac/Linux) and `.ps1` (Windows) scripts MUST produce identical
JSONL field names, types, and status values. Only the log file path
format differs by OS.

## Parsing Example (AI Agent)

```python
import json
for line in stdout.strip().split('\n'):
    event = json.loads(line)
    if event.get('summary'):
        if event['failed'] > 0:
            # read log file for diagnostics
            pass
    elif event['status'] == 'fail':
        print(f"Step {event['step']} failed: {event['error']}")
```
