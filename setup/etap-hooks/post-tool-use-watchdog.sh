#!/bin/bash
# PostToolUse hook — Idle Watchdog + Provenance Trail Audit
# Detects long-idle pattern (only ScheduleWakeup + Bash(git pull) repeating)
# AND tracks Edit/Write provenance trail for Goal Drift / Work Fabrication detection (D19, 25차).
#
# Per autonomous-execution-protocol.md §Hard Rule 7 (Idle Gate, 18차 D11/D12) +
#                                      §D19 Goal-Action Coupling (25차).
#
# State files:
# - /tmp/apf-watchdog-state.json — idle counter
# - /tmp/apf-provenance-trail.jsonl — Edit/Write/state-mutation provenance log (append-only, 25차 D19)
#
# Schema (apf-watchdog-state.json):
#   {"idle_tick_count": N, "last_action_ts": "ISO8601", "last_significant_action": "Bash|Edit|Write"}
# Schema (apf-provenance-trail.jsonl):
#   {"ts": "ISO8601", "tool": "Edit|Write", "file_path": "...", "claimed_provenance": "..."}

set -e

STATE_FILE="/tmp/apf-watchdog-state.json"
PROVENANCE_TRAIL="/tmp/apf-provenance-trail.jsonl"
PIPELINE_STATE="/Users/jhee/Documents/workspace/claude_work/projects/apf-operation/state/pipeline_state.json"
IDLE_THRESHOLD=3  # consecutive idle ticks before warn
PROVENANCE_AUDIT_WINDOW=5  # last N Edit/Write actions to audit for drift

# Read tool info from stdin (Claude Code passes JSON)
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null || echo "")

# Initialize state file if missing
if [ ! -f "$STATE_FILE" ]; then
  echo '{"idle_tick_count":0,"last_action_ts":"","last_significant_action":""}' > "$STATE_FILE"
fi

# Pre-classify NOW (provenance trail uses it)
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Classify tool call
IS_IDLE_PATTERN="false"
case "$TOOL_NAME" in
  "ScheduleWakeup")
    IS_IDLE_PATTERN="true"
    ;;
  "Bash")
    # Bash with only git-pull / git-status / ls = idle pattern
    CMD=$(echo "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")
    if echo "$CMD" | grep -qE '^(git -C [^ ]+ pull|git pull|ls /Users/jhee/Documents/workspace/dev_test_sync/results)' ; then
      IS_IDLE_PATTERN="true"
    fi
    ;;
  "TodoWrite"|"Read")
    # neutral — neither idle nor significant
    exit 0
    ;;
  "Edit"|"Write"|"NotebookEdit")
    IS_IDLE_PATTERN="false"
    # D19 25차: log to provenance trail (Edit/Write 모두)
    # 28차 R5 amendment: add inferred_service field for cross-validation drift detection
    FILE_PATH=$(echo "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path','UNKNOWN'))" 2>/dev/null || echo "UNKNOWN")
    # provenance 자체는 hook 이 직접 verify 불가 (claim 만 기록). audit 시 path 분포로 drift 추정.
    # 28차 R5 cross-validation: file_path 에서 service identifier 추출 → trail 에 inferred_service 기록.
    # AT 시나리오 ("claim mission:apf:warning_visibility:gemini3, edit unrelated path") drift 감지 데이터.
    python3 << PYEOF 2>/dev/null || true
import json, re
file_path = "$FILE_PATH"
# Service inference: known APF service names in file_path
services = ['gemini3','gemini','mistral','you','chatgpt','copilot','gamma','perplexity','claude','grok','anthropic','wrtn','jasper','phind','poe']
inferred = []
fp_lower = file_path.lower()
for s in services:
    # word-boundary-aware match
    if re.search(r'(^|[/_-])' + re.escape(s) + r'($|[/_.-])', fp_lower):
        inferred.append(s)
inferred_service = inferred[0] if inferred else 'cross-cutting'
entry = {'ts': '$NOW', 'tool': '$TOOL_NAME', 'file_path': file_path, 'inferred_service': inferred_service}
with open('$PROVENANCE_TRAIL', 'a') as f:
    f.write(json.dumps(entry) + '\n')

# Drift detection (28차 R5): last 5 entries — if 4+ same service then sudden switch to different service → warn
try:
    with open('$PROVENANCE_TRAIL') as f:
        lines = f.readlines()
    recent = lines[-6:-1]  # last 5 BEFORE current entry
    if len(recent) >= 4:
        prior_services = []
        for ln in recent:
            try:
                prior_services.append(json.loads(ln).get('inferred_service', 'cross-cutting'))
            except:
                pass
        # 4+ same prior + current is different + neither is cross-cutting
        if (prior_services.count(prior_services[0]) >= 4 and
            inferred_service != prior_services[0] and
            inferred_service != 'cross-cutting' and
            prior_services[0] != 'cross-cutting'):
            # Write drift warning to dedicated log (separate from /tmp/apf-watchdog-state.json)
            with open('/tmp/apf-provenance-drift.log', 'a') as df:
                df.write(json.dumps({
                    'ts': '$NOW',
                    'prior_service': prior_services[0],
                    'prior_count': prior_services.count(prior_services[0]),
                    'current_service': inferred_service,
                    'current_file_path': file_path,
                    'severity': 'drift_4plus_to_different'
                }) + '\n')
except Exception:
    pass
PYEOF
    ;;
esac

# Update state (NOW already set above for provenance trail)
if [ "$IS_IDLE_PATTERN" = "true" ]; then
  # increment idle counter
  python3 -c "
import json
s = json.load(open('$STATE_FILE'))
s['idle_tick_count'] = s.get('idle_tick_count', 0) + 1
s['last_action_ts'] = '$NOW'
json.dump(s, open('$STATE_FILE','w'))
"
elif [ "$IS_IDLE_PATTERN" = "false" ] && [ -n "$TOOL_NAME" ]; then
  # significant action — reset counter
  python3 -c "
import json
s = json.load(open('$STATE_FILE'))
s['idle_tick_count'] = 0
s['last_action_ts'] = '$NOW'
s['last_significant_action'] = '$TOOL_NAME'
json.dump(s, open('$STATE_FILE','w'))
"
  exit 0
else
  exit 0
fi

# Read current idle count
IDLE_COUNT=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('idle_tick_count',0))")

# Threshold check
if [ "$IDLE_COUNT" -lt "$IDLE_THRESHOLD" ]; then
  exit 0
fi

# At threshold — check if service_queue has autonomous-doable next_action
if [ ! -f "$PIPELINE_STATE" ]; then
  exit 0
fi

AUTONOMOUS_CANDIDATES=$(python3 -c "
import json
try:
    s = json.load(open('$PIPELINE_STATE'))
    queue = s.get('service_queue', [])
    cands = [e for e in queue if not e.get('next_action','').startswith('defer:') and e.get('next_action')]
    print(len(cands))
    print('|'.join(f\"{e['service']}:{e['next_action']}\" for e in cands[:5]))
except Exception:
    print(0)
    print('')
")

CAND_COUNT=$(echo "$AUTONOMOUS_CANDIDATES" | head -1)
CAND_LIST=$(echo "$AUTONOMOUS_CANDIDATES" | tail -1)

# 45차 amendment: CAND_COUNT 와 무관하게 systemMessage emit (mission-goal persistence).
#   기존: CAND_COUNT>0 일 때만 fire → primary 모두 defer 시 silent → idle 허용 결과 (41차 directive 와 conflict).
#   변경: 항상 fire (primary>0 vs primary==0 별도 분기) — expansion search 의무를 explicit 으로 inject.
if [ "$CAND_COUNT" -gt 0 ]; then
  cat <<HOOKJSON
{
  "systemMessage": "[WATCHDOG] Idle Gate triggered: ${IDLE_COUNT} consecutive idle ticks (only polling/git-pull). Mission-Goal Persistence (HR7 41차): mission goal 미달성 시 expansion search 의무. Primary candidates ${CAND_COUNT} 개 (${CAND_LIST}) — 즉시 pop + execute."
}
HOOKJSON
else
  cat <<HOOKJSON
{
  "systemMessage": "[WATCHDOG] Idle Gate triggered: ${IDLE_COUNT} consecutive idle ticks. Primary candidates 모두 'defer:' 상태. ★ ANTI-PATTERN BLOCKED: D9 Stage 1-3 (count==0 / needs_user_input / canonical-cite) 41차 폐지 + Stage 4 (별개 dedicated session / 추후 검증 / 외부 의존성 대기 / separate engine cycle / declare-then-stop) 46차 + Stage 5 (paper for paper's sake / sequentially cycle 후 'evaluation 완료' / artifact 없는 reasoning / 1 tool call 형식적 만족 후 stop) 47차 prophylactic + Stage 6 (cumulative metric 'N breakthroughs' / '~X min runtime' / 'Y hypotheses disproven' / 'NN차 status:' session summary / Mission Criterion Self-Adjustment 'criterion needs X, not Y') 48차 + Stage 7 (defer string Abuse: 'architecturally_exhausted' / 'X_OR_Y_engine_work' Multi-OR composition / 'cycleNN_*' or 'iteration N-M' or '5-X redo' = 39차 cycle 폐지 위반) 49차 prophylactic + Stage 8 (Authority Inversion: producer dev 가 consumer test capability inventorying / internal reasoning simulation / 사전 가능 판단 / workaround pre-design = async request-response pattern violation. Boundary: skill command name 인용 OK / capability internal reasoning simulation X) 54차 §3 codify. WSA v3 step 5 expansion search 의무 (각 시도 = concrete artifact + cause-based decision evidence + cumulative metric ≠ stop license + defer string clean): 5-A diagnosis revisit / 5-B strategy revisit / 5-C sub-agent dispatch / 5-D paper work (sub-agent prompt / spec design / verify path) / 5-E lesson harvest / 5-F D20(b) verify rotation. Mission criterion 자율 재정의 = 사용자 권한 침해, 차단. user ask 는 M4 물리적 예외만."
}
HOOKJSON
fi
# Reset counter to avoid spamming
python3 -c "
import json
s = json.load(open('$STATE_FILE'))
s['idle_tick_count'] = 0
json.dump(s, open('$STATE_FILE','w'))
"

exit 0
