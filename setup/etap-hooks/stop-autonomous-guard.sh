#!/bin/bash
# Stop hook — Mission-Goal Persistence Guard (41차 amendment)
#
# Fires when Claude finishes response without invoking another tool.
#
# 41차 amendment (사용자 directive: "count 개념 제거, 목표 달성까지 해법 탐색 반복"):
#   Logic shift: count-based ("autonomous_candidates count > 0") → mission-goal-based
#   Stop license = mission goal achieved (DONE / (TOTAL - TERMINAL_UNREACHABLE) = 1.0)
#
# Logic:
# 1. Read pipeline_state.json: count DONE vs TOTAL - TERMINAL_UNREACHABLE
# 2. If goal_ratio < 1.0 → mission incomplete → block stop (expansion search 의무 reminder)
# 3. If goal_ratio = 1.0 → allow stop (maintenance mode)
# 4. Termination keyword override: 사용자 explicit halt/stop/종료/그만 등 detected → allow stop
# 5. stop_hook_active loop prevention 유지
#
# Per autonomous-execution-protocol.md HR7 (41차 redefined as Mission-Goal Persistence)
#
# Hook event: Stop (Claude Code)
# Per autonomous-execution-protocol.md HR7 + 22차 D16(a) discussion-review consensus.
# 24차 refined: keyword list narrowed to genuine termination intent (incident 8 — 보고/summarize 가 status-update request 인데 termination 으로 misclassified).
#
# Termination keywords (case-insensitive substring match in last user message):
#   - Strong stop: stop / halt / quit / 정지 / 종료 / 그만 / 그만해 / 끝
#   - Pause (still allow stop): wait / pause / 잠시 / 잠깐
# REMOVED 24차 (status-update requests, not termination intent):
#   - 보고해 / 보고 / summarize / 검토 / 일단
# Rationale: "보고해" alone = status update request (사용자가 polling 중간 보고 받고 다시 진행 의도).
# 진짜 stop 은 "그만/stop/종료/끝" 등 명시적 keyword. Last-mile result scan 의무는 별도 (G1 below).

set -e

PIPELINE_STATE="/Users/jhee/Documents/workspace/claude_work/projects/apf-operation/state/pipeline_state.json"
LOG="/tmp/stop-autonomous-guard.log"

# Read input JSON from Claude Code (transcript_path + stop_hook_active)
INPUT=$(cat)

# Parse stop_hook_active to prevent infinite loops
STOP_HOOK_ACTIVE=$(echo "$INPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('stop_hook_active', False))" 2>/dev/null || echo "False")

if [ "$STOP_HOOK_ACTIVE" = "True" ]; then
    # Already in stop-hook re-engagement loop; don't recurse
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [skip — stop_hook_active=True]" >> "$LOG"
    exit 0
fi

# 43차: Skill-edit self-review marker check (★★★ architectural enforcement)
# Pre-edit-skill-self-review hook 가 skill 편집 시 marker 생성 → 본 stop hook 가 verify.
SKILL_MARKER_DIR="/tmp/claude-skill-edit-markers"
PENDING_REVIEW=$(python3 << PYEOF 2>/dev/null
import json, os, glob
import datetime
pending = []
now = datetime.datetime.utcnow()
try:
    for m in glob.glob("$SKILL_MARKER_DIR/*.json"):
        try:
            with open(m) as f:
                d = json.load(f)
            if d.get('self_review_done', False):
                continue
            # Marker 가 너무 오래되면 (>4 hours) skip — stale session 보호
            first = d.get('first_edit_at', '')
            try:
                t = datetime.datetime.strptime(first.replace('Z',''), '%Y-%m-%dT%H:%M:%S')
                if (now - t).total_seconds() > 14400:
                    continue
            except Exception:
                pass
            skills = d.get('edited_skills', [])
            count = d.get('edits_count', 0)
            pending.append((','.join(skills), count, os.path.basename(m)))
        except Exception:
            continue
except Exception:
    pass
if pending:
    print('|'.join(f"{sk}:{ct}:{f}" for sk, ct, f in pending))
PYEOF
)

if [ -n "$PENDING_REVIEW" ]; then
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [BLOCK STOP — pending skill self-review: $PENDING_REVIEW]" >> "$LOG"
    cat << EOF
{
  "decision": "block",
  "reason": "[SKILL EDIT GUARD ★★★ — 43차] Skill 편집 후 self-review 미수행. Pending: $PENDING_REVIEW.\n\n의무: 7-check 수행 (lessons.md §11 + feedback_skill_edit_self_review.md):\n1. 원칙/숫자 변경 = 전수 grep 검사\n2. cross-reference 일관성\n3. 의도 vs 실제 변경 일치\n4. forward references (다른 skill 영향)\n5. file path / line number 변경 시 모든 인용 갱신\n6. canonical anchor 영향 (Polling Policy / Termination Conditions / Mission anchor / HR / D-principle)\n7. lessons.md / incident-log codify 필요 여부\n\n완료 후: bash /Users/jhee/Documents/workspace/Officeguard/EtapV3/.claude/hooks/mark-skill-self-review-done.sh \"<요약>\"\n\nSkill 편집 = 전 Claude session 행동에 영향 — drift 방지 마지막 layer."
}
EOF
    exit 0
fi

# 41차: Mission-goal evaluation (count-based logic 폐지)
if [ ! -f "$PIPELINE_STATE" ]; then
    # No pipeline state file — not in APF context, skip
    exit 0
fi

GOAL_INFO=$(python3 << PYEOF
import json
try:
    with open("$PIPELINE_STATE") as f:
        s = json.load(f)
    queue = s.get('service_queue', [])
    done_services = s.get('done_services', [])
    total = len(done_services) + len(queue)
    terminal = sum(1 for e in queue if e.get('status') == 'TERMINAL_UNREACHABLE')
    reachable = total - terminal
    done = len(done_services)
    if reachable > 0:
        ratio = done / reachable
    else:
        ratio = 1.0  # nothing to do
    # Output: ratio + done count + reachable count + non-DONE services for context
    print(f"{ratio:.3f}")
    print(f"{done}")
    print(f"{reachable}")
    # Pending list (for context in block message)
    for e in queue[:5]:
        st = e.get('status', '?')
        na = e.get('next_action', '')
        svc = e.get('service', '?')
        print(f"  {svc}: status={st} next_action={na}")
except Exception as ex:
    print("1.0")
    print("0")
    print("0")
PYEOF
)

GOAL_RATIO=$(echo "$GOAL_INFO" | sed -n '1p')
DONE_COUNT=$(echo "$GOAL_INFO" | sed -n '2p')
REACHABLE_COUNT=$(echo "$GOAL_INFO" | sed -n '3p')
# JSON-safe: replace literal newlines with \\n escape so the final reason JSON is strict-valid
PENDING_LIST=$(echo "$GOAL_INFO" | tail -n +4 | python3 -c "import sys; print('\\\\n'.join(line for line in sys.stdin.read().splitlines() if line))")

# Mission goal achieved (ratio = 1.0) → allow stop (maintenance mode entry)
if [ "$GOAL_RATIO" = "1.000" ]; then
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [allow stop — mission goal achieved, ratio=$GOAL_RATIO done=$DONE_COUNT/$REACHABLE_COUNT]" >> "$LOG"
    exit 0
fi

# 51차 G2 amendment — Artifact-bounded stop-license:
#   ANY service entry has `last_artifact.timestamp > last_stop_attempt_at` → allow stop.
#   Mission criterion (DONE/REACHABLE = 1.0) 불변. Stop-license granularity 만 micro-task artifact 기준 분해.
#   Type-check: artifact pointer must match micro_task type per artifact_type_registry.json (anti-Stage-5 gaming).
LAST_STOP_FILE="/tmp/stop-hook-last-attempt.json"
LAST_STOP_AT=$(python3 -c "import json; print(json.load(open('$LAST_STOP_FILE')).get('timestamp',''))" 2>/dev/null || echo "")
NOW_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

ARTIFACT_OBSERVED=$(python3 << PYEOF 2>/dev/null
import json
try:
    with open("$PIPELINE_STATE") as f:
        s = json.load(f)
    queue = s.get('service_queue', [])
    last_stop = "$LAST_STOP_AT"
    for e in queue:
        la = e.get('last_artifact')
        if la and isinstance(la, dict):
            ts = la.get('timestamp', '')
            ptr = la.get('pointer', '')
            ty = la.get('type', '')
            svc = e.get('service', '?')
            mt = e.get('current_micro_task', '?')
            # Type-check: artifact type must match a known T1/T2/T3 enum (anti-trivial-artifact)
            if ts and ts > last_stop and ty in ('T1_engine_fire', 'T2_UI_render', 'T3_verify_path_established'):
                # Additional: type 와 current_micro_task progression 일관성 (T1 artifact 가 T2/T3 micro_task 에 등록 가능 — engine evidence 가 UI render task 에 inject)
                print(f"OBSERVED|{svc}|{ty}|{mt}|{ts}|{ptr[:80]}")
                break
except Exception:
    pass
PYEOF
)

# Always update last_stop_at for next attempt comparison
echo "{\"timestamp\":\"$NOW_TS\"}" > "$LAST_STOP_FILE"

if [ -n "$ARTIFACT_OBSERVED" ]; then
    SVC=$(echo "$ARTIFACT_OBSERVED" | cut -d'|' -f2)
    TY=$(echo "$ARTIFACT_OBSERVED" | cut -d'|' -f3)
    MT=$(echo "$ARTIFACT_OBSERVED" | cut -d'|' -f4)
    TS_OBS=$(echo "$ARTIFACT_OBSERVED" | cut -d'|' -f5)
    echo "$NOW_TS [allow stop — 51차 G2 artifact-bounded license: svc=$SVC type=$TY micro_task=$MT artifact_ts=$TS_OBS > last_stop=$LAST_STOP_AT]" >> "$LOG"
    cat <<HOOKJSON
{"systemMessage":"[51차 G2 ALLOW STOP] Artifact-bounded stop-license: $SVC ($TY observed $TS_OBS, current_micro_task=$MT). Mission ratio=$GOAL_RATIO incomplete; this stop attempt allowed because micro-task artifact observed since last attempt. Next session: continue mission via standard expansion search."}
HOOKJSON
    exit 0
fi

# 52차 C amendment REVERTED (사용자 directive 2026-05-07): backoff logic 제거.
# Mission-goal persistence (HR7) 의 immediate BLOCK 동작 복원.
# 51차 G2 artifact-bounded license 는 유지.

# 41차: COUNT 변수는 backward-compat용 (주의 messaging 에서 사용); 실제 stop license 는 GOAL_RATIO 기반
COUNT="${REACHABLE_COUNT:-0}"
TASKS="$PENDING_LIST"

# Check last user message for termination keywords
TRANSCRIPT_PATH=$(echo "$INPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('transcript_path',''))" 2>/dev/null || echo "")

LAST_USER_MSG=""
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    # Read last user message from transcript (JSONL format)
    LAST_USER_MSG=$(python3 << PYEOF
import json
last = ""
try:
    with open("$TRANSCRIPT_PATH") as f:
        for line in f:
            try:
                obj = json.loads(line)
                # Find last user message (role=user, type=message)
                if obj.get('type') == 'user' or obj.get('role') == 'user':
                    msg = obj.get('message', {})
                    if isinstance(msg, dict):
                        content = msg.get('content', '')
                    else:
                        content = msg
                    if isinstance(content, list):
                        for c in content:
                            if isinstance(c, dict) and c.get('type') == 'text':
                                last = c.get('text', '')
                    elif isinstance(content, str):
                        last = content
            except json.JSONDecodeError:
                continue
except Exception as ex:
    pass
print(last[:500])
PYEOF
)
fi

# Check termination keywords (case-insensitive)
TERMINATION_FOUND="false"
if [ -n "$LAST_USER_MSG" ]; then
    LOWER_MSG=$(echo "$LAST_USER_MSG" | tr '[:upper:]' '[:lower:]')
    for kw in "stop" "정지" "종료" "그만" "그만해" "wait" "pause" "잠시" "잠깐" "끝" "halt" "quit"; do
        if echo "$LOWER_MSG" | grep -qF "$kw"; then
            TERMINATION_FOUND="true"
            break
        fi
    done
fi

if [ "$TERMINATION_FOUND" = "true" ]; then
    # 28차 R2 amendment: keyword found + candidates > 0 → allow but inform user of pending candidates
    # Redirection scenarios ("그만 만들고 다른 거 해") leave candidates orphaned silently in current logic.
    # State-based supplement: surface pending count so user can decide redirect vs genuine stop.
    if [ "$COUNT" != "0" ]; then
        echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [allow stop — termination keyword + $COUNT pending candidates surfaced]" >> "$LOG"
        cat <<HOOKJSON
{"systemMessage":"[D16(a) 41차 mission-goal] Termination keyword detected — stop allowed. Mission goal status: ${DONE_COUNT}/${REACHABLE_COUNT} (ratio=${GOAL_RATIO}). Mission incomplete; expansion search would have been the autonomous default. Genuine session-end: tasks resume next session via D11 pull-based pop."}
HOOKJSON
        exit 0
    fi
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [allow stop — termination keyword, mission ratio=$GOAL_RATIO]" >> "$LOG"
    exit 0
fi

# Block stop — Mission goal incomplete + no termination keyword
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "$TS [BLOCK STOP — mission ratio=$GOAL_RATIO done=$DONE_COUNT/$REACHABLE_COUNT, no termination keyword]" >> "$LOG"
echo "$TASKS" >> "$LOG"

# Output JSON to block stop and force re-engagement
cat << EOF
{
  "decision": "block",
  "reason": "MISSION-GOAL PERSISTENCE GUARD (41차 amendment): mission ratio = $GOAL_RATIO (DONE=$DONE_COUNT / REACHABLE=$REACHABLE_COUNT). Goal not yet achieved (ratio < 1.0). Stop is BLOCKED.\n\n41차 사용자 directive: '목표를 달성하기 전까지 계속 해법을 찾고 시도하는 작업을 반복'. Count-based stop license 폐지.\n\n★★★ ANTI-PATTERN BLOCKED — D9 Stage 4 (46차 codify) — Implicit Defer Cascade:\n다음 reasoning 으로 mission gap 을 다른 곳으로 push 시 = 자율 모드 회피 (anti-pattern):\n - '별개 dedicated session 에서 진단/처리'\n - '별개 task (...의 inverse direction)'\n - '추후 검증' / 'login/HAR 도착 시 즉시 검증'\n - '외부 의존성 대기'\n - 'F5 step X-Y 영향 범위 밖' (scope narrowing)\n - '잔여 autonomous-doable 검토 + 진행' 으로 declare 후 tool 호출 없이 종료\n\n위 reasoning = expansion search 직접 시도 회피. **본 session 즉시 expansion search routes 5-A~5-F 중 1개 직접 시도 의무**:\n - 5-A: Diagnosis revisit (cause_pointer 재검토, 새 hypothesis brainstorm)\n - 5-B: Strategy revisit (A/B/C/D/E 다른 strategy, envelope schema rev)\n - 5-C: Sub-agent dispatch (HAR audit, log mining, code review — 본 session 가능)\n - 5-D: Paper work (spec design, schema extension, sub-agent prompt 작성, tooling)\n - 5-E: Lesson harvest (failure_history pattern → INTENTS / lessons)\n - 5-F: D20(b) verification rotation (DONE services L1 canary + L2-2A UI verify)\n\n외부 의존성 대기 candidate 라도 그 dependency 의 **paper work 준비** (sub-agent prompt 작성 / spec design / verify path 설계) 는 5-D 로 본 session 가능.\n\n★ ANTI-PATTERN BLOCKED — D9 Stage 5 prophylactic (47차 codify) — Performative Compliance:\n5-A~5-F 시도 시 각 시도 = **concrete artifact + cause-based decision evidence** 수반 의무:\n - artifact: 새 file path / 수정 file path / sub-agent dispatch ID / INTENTS 추가 entry / commit hash\n - cause-based decision: hypothesis 결론 / cause analysis 결과 / next axis pivot 결정\n다음 형태 = performative compliance (차단 대상):\n - paper for paper's sake (의미 없는 spec 만 산출)\n - 5-A~5-F sequentially 빠르게 거치고 'evaluation 완료' 결론 후 stop\n - 1 tool call 형식적 만족 후 stop\n - artifact 없는 reasoning summary 만 산출 후 stop\n\n★★ ANTI-PATTERN BLOCKED — D9 Stage 6 (48차 incident-driven codify) — Cumulative Progress Theatrics:\nStage 5 의 turn-level artifact 의무를 형식적으로 만족하면서 cumulative metric 누적으로 stop 정당화 = 차단:\n - 'N breakthroughs across N services' cumulative count\n - '~X min cumulative runtime' 시간 누적\n - 'Y hypotheses disproven' 진척 metric\n - 'NN차 status: ...' session-level summary\n - 'Polling continues — wakeup already scheduled' polling chain 으로 stop 정당화\n\n★★★ ANTI-PATTERN BLOCKED — D9 Stage 6 sub-form — Mission Criterion Self-Adjustment (사용자 권한 침해):\n - 'Mission criterion adjustment identified'\n - 'Mission criterion needs X, not Y'\n - 'expected_text check WILL FAIL since UI shows ...' (mission criterion 재정의 시도)\n→ Mission 정의 = 사용자 명시 directive 만 변경 가능. LLM 자율 mission 재정의 = 41차 mission-goal-based 의 ratio 측정 분모/분자 변경 = directive 핵심 변수 침해. mission criterion adjustment 가 필요하다고 판단 시 → 사용자에게 명시 confirm (M4 물리적 예외) 후 변경. 자율 변경 금지.\n\nStage 4 잔존 변종도 차단:\n - 'Wire-up requires X (deferred for separate engine cycle)' 형태 명시적 separate cycle defer = Stage 4 변종\n\n★ ANTI-PATTERN BLOCKED — D9 Stage 7 prophylactic (49차 codify) — defer string Abuse:\ndefer:* next_action string 내 다음 wording 차단:\n - 'architecturally_exhausted' / 'exhaustion_confirmed' / 'all_paths_tried' 등 architectural exhaustion claim → D14(b) 위반 (영구 EXCEPTION 금지). expansion search route 사전 차단 시도, 차단.\n - 'X_OR_Y_engine_work' / 'A_OR_B_OR_C' 등 Multi-OR defer composition → 각 path 별 expansion search 의무 회피. 각 path 분해 후 별도 평가 의무.\n - 'cycleNN_*' / 'cycle95-97' / 'v2-v11' / 'iteration N-M' 등 cycle/iteration wording → 39차 cycle 폐지 directive 위반. defer string + status text 모두 cycle wording 정정.\n - '5-X redo' / 'Phase X redo' 등 cycle-like 재시도 표현 → 39차 directive 와 conflict. cause-based decision 으로 표현.\n\n다음 stop 시도 시 직전 expansion search 의 **progress evidence** 명시 의무 (없으면 본 hook 가 또 BLOCK).\n\nExpansion search target candidates (모두 5-A~5-F routes 가능, 'evaluated' 표시 아님):\n$TASKS\n\nGenuine stop only via user termination keyword (stop/정지/종료/그만/wait/pause/잠시/잠깐/끝/halt/quit). 'dedicated session' / 'separate task' / 'separate engine cycle' / 'NN차 status complete' / cumulative metric 'enough done' = stop 의 disguised form, 모두 차단. Mission criterion 자율 재정의 = 사용자 권한 침해, 차단."
}
EOF
exit 0
