#!/bin/bash
# test-context.sh v1 (test PC SessionStart hook)
#
# Purpose: compact/resume 후 test PC의 태스크 상태를 AI에게 주입 (인지적 복구)
# Trigger: SessionStart (resume|compact)
# Behavior: non-blocking (exit 0 always)
#
# session-recovery.ps1 = 절차적 복구 (파일시스템 상태 복원)
# 이 훅 = 인지적 복구 (AI에게 상태 주입)

# --- 경로 탐색 (Cowork 세션 동적 경로 대응) ---
# mnt/Documents가 마운트된 경로에서 dev_test_sync를 찾는다
for candidate in /sessions/*/mnt/Documents/dev_test_sync /sessions/*/mnt/dev_test_sync; do
  if [ -d "$candidate" ]; then
    BASE="$candidate"
    break
  fi
done

# fallback: 환경변수 또는 기본 경로
if [ -z "$BASE" ]; then
  BASE="${GIT_SYNC_REPO:-/sessions/lucid-ecstatic-noether/mnt/Documents/dev_test_sync}"
fi

STATE_FILE="$BASE/local_archive/state.json"

# state.json이 없으면 작업 환경이 아님 → 출력 없이 종료
if [ ! -f "$STATE_FILE" ]; then
  exit 0
fi

# --- 상태 읽기 ---
LAST_PROCESSED=$(jq -r '.last_processed_id // 0' "$STATE_FILE" 2>/dev/null)
LAST_DELIVERED=$(jq -r '.last_delivered_id // 0' "$STATE_FILE" 2>/dev/null)
POLLING_ACTIVE=$(jq -r '.polling_active // false' "$STATE_FILE" 2>/dev/null)
UPDATED_AT=$(jq -r '.updated_at // "unknown"' "$STATE_FILE" 2>/dev/null)

# 미push 결과 계산
UNPUSHED=0
if [ "$LAST_PROCESSED" -gt "$LAST_DELIVERED" ] 2>/dev/null; then
  UNPUSHED=$((LAST_PROCESSED - LAST_DELIVERED))
fi

# --- 새 요청 스캔 ---
NEW_REQUESTS=0
if [ -d "$BASE/requests" ]; then
  for f in "$BASE/requests/"*_*.json; do
    [ -f "$f" ] || continue
    ID=$(basename "$f" | grep -oE '^[0-9]+')
    [ -z "$ID" ] && continue
    if [ "$((10#$ID))" -gt "$LAST_PROCESSED" ] 2>/dev/null; then
      NEW_REQUESTS=$((NEW_REQUESTS + 1))
    fi
  done
fi

# 상태가 모두 0이고 폴링도 아니면 출력 생략
if [ "$LAST_PROCESSED" = "0" ] && [ "$UNPUSHED" = "0" ] && [ "$POLLING_ACTIVE" = "false" ] && [ "$NEW_REQUESTS" = "0" ]; then
  exit 0
fi

# --- 액션 결정 ---
ACTION=""
if [ "$UNPUSHED" -gt 0 ]; then
  ACTION="⚠ $UNPUSHED unpushed results exist! Run git_sync.bat push first."
elif [ "$NEW_REQUESTS" -gt 0 ]; then
  ACTION="$NEW_REQUESTS new request(s) waiting. Process them."
elif [ "$POLLING_ACTIVE" = "true" ]; then
  ACTION="Resume polling — was active before session break."
else
  ACTION="No pending work. Await user instruction."
fi

# --- additionalContext 출력 ---
CONTEXT="[Test PC Recovery] last_processed: $LAST_PROCESSED | last_delivered: $LAST_DELIVERED | unpushed: $UNPUSHED | new_requests: $NEW_REQUESTS | polling: $POLLING_ACTIVE | Action: $ACTION"

echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"$CONTEXT\"}}"
exit 0
