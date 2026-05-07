#!/bin/bash
# PostCompact + SessionStart hook: inject autonomous mode reminder + pipeline goal/next_action
# Fires after context compaction — the moment when autonomous rules are most likely forgotten.
#
# Updated 2026-04-27 (discussion-review consensus): Goal injection [GOAL: N/M DONE — K services with autonomous next_action].
# Updated 2026-04-30 (45차 root cause fix): count-based wording → mission-goal-based (41차 directive 누락 layer 보완).
#   문제: post-compact systemMessage 가 "autonomous_doable count==0 증명" + "All defer: needs_user_input report"
#         + "Work Selection v2" 등 41차 폐지 wording 을 SessionStart/PostCompact 마다 재inject 하여
#         skill 의 v3 mission-goal-based 정의를 override. → 자율 모드 중단 반복 (5번 BLOCK 로그 증거).
#   조치: GOAL line ratio 표기, HR7 Mission-Goal Persistence, WSA v3 reference, defer→expansion search 안내.

PIPELINE_STATE_PRIMARY="/Users/jhee/Documents/workspace/claude_work/projects/apf-operation/state/pipeline_state.json"
PIPELINE_STATE_FALLBACK="/Users/jhee/Documents/workspace/dev_test_sync/local_archive/pipeline_state.json"

# Choose primary if exists, fallback else
if [ -f "$PIPELINE_STATE_PRIMARY" ]; then
  PIPELINE_STATE="$PIPELINE_STATE_PRIMARY"
elif [ -f "$PIPELINE_STATE_FALLBACK" ]; then
  PIPELINE_STATE="$PIPELINE_STATE_FALLBACK"
else
  PIPELINE_STATE=""
fi

GOAL_LINE=""
NEXT_ACTION_LINE=""
CURRENT_SERVICE=""

if [ -n "$PIPELINE_STATE" ] && [ -f "$PIPELINE_STATE" ]; then
  PS_PATH="$PIPELINE_STATE" GOAL_LINE=$(PS_PATH="$PIPELINE_STATE" python3 <<'PYEOF' 2>/dev/null
import json, os
path = os.environ.get('PS_PATH')
try:
    s = json.load(open(path))
    done_services = s.get('done_services', [])
    queue = s.get('service_queue', [])
    done = len(done_services)
    total_reg = s.get('classification_summary', {}).get('total_registered', 37)
    # Mission ratio = DONE / (TOTAL - TERMINAL_UNREACHABLE)  (stop-autonomous-guard.sh 와 동일 정의)
    total_q = done + len(queue)
    terminal = sum(1 for e in queue if e.get('status') == 'TERMINAL_UNREACHABLE')
    reachable = max(total_q - terminal, 1)
    ratio = done / reachable
    if ratio >= 1.0:
        print(f"[GOAL: {done}/{reachable} reachable DONE — mission ACHIEVED (maintenance mode allowed)]")
    else:
        print(f"[GOAL: {done}/{reachable} reachable DONE | ratio={ratio:.3f} — mission INCOMPLETE → expansion search 의무]")
except Exception:
    print("[GOAL: unavailable]")
PYEOF
)
  NEXT_ACTION_LINE=$(PS_PATH="$PIPELINE_STATE" python3 <<'PYEOF' 2>/dev/null
import json, os
path = os.environ.get('PS_PATH')
try:
    s = json.load(open(path))
    queue = s.get('service_queue', [])
    primary = [e for e in queue if not str(e.get('next_action','')).startswith('defer:') and e.get('next_action')]
    if primary:
        top3 = primary[:3]
        print("NEXT primary (top 3): " + "; ".join(f"{e['service']}=>{e['next_action']}" for e in top3))
    else:
        # 41차/45차: all-defer 는 user ask trigger 가 아니라 expansion search trigger.
        print("All next_action 'defer:' — WSA v3 step 5 expansion search 의무 (5-A diagnosis revisit / 5-B strategy revisit / 5-C sub-agent / 5-D paper / 5-E lessons / 5-F D20(b) UI verify rotation). NEVER terminate as 'needs_user_input'.")
except Exception:
    print("")
PYEOF
)
fi

cat <<HOOKJSON
{
  "systemMessage": "AUTONOMOUS MODE ACTIVE. ${GOAL_LINE} ${NEXT_ACTION_LINE}\n\nHARD RULES (v3, 41차 mission-goal-based): (1) 질문으로 끝맺기 금지 (2) 상태 정리만 하고 멈추기 금지 (3) 폴링 체인 끊기 금지 (4) 선언 후 멈추기 금지 (5) idle 대기 금지 (6) 선택지 제시 금지→Empirical (7) Mission-Goal Persistence: ratio<1.0 = expansion search 의무 (WSA v3 step 5-A~5-F). Premature completion 차단: cycle summary 작성 ≠ 종료, 목표 미달성 시 다음 push.\n\nWork Selection v3 (mission-goal-based): pop primary next_action → execute → update queue. Primary 고갈 (all 'defer:') ≠ stop license. WSA v3 step 5 expansion search (cause-based pivot) 의무. user ask 는 M4 물리적 예외만.\n\n★★★ ANTI-PATTERN BLOCKED:\n[D9 Stage 1-3 (41차 폐지)]: '잔여 autonomous-doable count==0 평가' / 'all defer → needs_user_input report' / 'count-based stop license' / 'L553 30분 escalate'.\n[D9 Stage 4 (46차 codify) — Implicit Defer Cascade]: '별개 dedicated session 에서 진단/처리' / '별개 task (inverse direction)' / '추후 검증' / 'login/HAR 도착 시 즉시 검증' / '외부 의존성 대기' / 'F5 step X 영향 범위 밖' (scope narrowing) / '자율 모드 계속. 잔여 autonomous-doable 검토 + 진행' declare 후 tool 호출 없이 종료. → 모두 expansion search 직접 시도 회피. 본 session 즉시 5-A~5-F 중 1개 시도 의무.\n[D9 Stage 5 prophylactic (47차 codify) — Performative Compliance]: paper for paper's sake / 5-A~5-F sequentially 빠르게 cycle 후 'evaluation 완료' / artifact 없는 reasoning summary 만 / 1 tool call 형식적 만족 후 stop. → 각 expansion search 시도 = concrete artifact (file/commit/INTENTS entry/sub-agent ID) + cause-based decision evidence (hypothesis 결론 / cause analysis / axis pivot) 수반 의무.\n[D9 Stage 6 (48차 incident-driven codify) — Cumulative Progress Theatrics]: turn-level artifact 의무 형식적 만족하면서 cumulative metric 으로 stop 정당화. Telltale: 'N breakthroughs across N services' / '~X min cumulative runtime' / 'Y hypotheses disproven' / 'NN차 status:' session-level summary / 'Polling continues — wakeup already scheduled'. → cumulative summary ≠ stop license. Mission ratio < 1.0 면 expansion search 계속.\n[D9 Stage 6 sub-form — Mission Criterion Self-Adjustment]: 'Mission criterion adjustment identified' / 'Mission criterion needs X, not Y'. → Mission 정의 = 사용자 명시 directive 만 변경 가능. LLM 자율 mission 재정의 = ratio 측정 분모/분자 변경 = 41차 directive 핵심 변수 침해. 변경 필요 판단 시 사용자에게 명시 confirm (M4 물리적 예외) 후 변경. 자율 변경 금지.\n[D9 Stage 7 prophylactic (49차 codify) — defer string Abuse]: defer:* next_action string 내 (a) 'architecturally_exhausted' / 'exhaustion_confirmed' / 'all_paths_tried' = D14(b) 영구 EXCEPTION 위반 + expansion search route 사전 차단; (b) 'X_OR_Y_engine_work' Multi-OR composition = 각 path 별 expansion search 의무 회피, 각 path 분해 후 별도 평가; (c) 'cycleNN_*' / 'iteration N-M' / '5-X redo' = 39차 cycle 폐지 directive 위반, cause-based decision 으로 표현. defer string + status text 모두 정정.\n[D9 Stage 8 (54차 §3 codify) — Authority Inversion (Capability Pre-judgment)]: producer (dev PC) 가 consumer (test PC) capability internal reasoning simulate + 사전 판단 + workaround pre-design = async request-response pattern violation. Telltale: 'test PC 의 사용 가능한 command 확인 완료' / 'X command 가 없으니 Y로 시도' / 'subagent ... 가능 / explicit instruction'. → Boundary: command name 인용 (public interface) OK / capability inventorying / internal reasoning simulation X. 가능 여부 = test PC 권한.\n외부 의존성 대기 candidate 라도 sub-agent prompt 작성 / spec design 등 paper work (5-D) 본 session 가능. 근거: autonomous-execution-protocol.md HR7 Mission-Goal Persistence + D9 anti-pattern list (Stage 1-8)."
}
HOOKJSON
