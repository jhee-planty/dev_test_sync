#!/bin/bash
# PreToolUse Edit|Write|MultiEdit hook — Skill Edit Self-Review Guard (43차)
#
# 사용자 directive (43차): "작업 세션이 스킬을 수정했어. 대책을 마련해줘."
# Trigger: 다른 session 들이 ad-hoc skill 편집 (skill-review-deploy procedure +
#          feedback_skill_edit_self_review.md self-review 의무 우회).
#
# Logic:
# 1. Detect skill path: shared-skills/{skill}/(SKILL.md | references/*.md | runtime/*.{sh,py})
#    Exclude: handoff.md / progress.md / INTENTS.md / lessons.md / discussions/ / status.md (auto-gen)
# 2. First skill edit in this session → create marker + emit strong system-reminder
# 3. Subsequent edits → silent count update
# 4. Stop hook (별도) verifies self_review_done=true before allowing stop
#
# Marker: /tmp/claude-skill-edit-markers/{session_or_date}.json
# Mark-done script: bash /Users/jhee/Documents/workspace/Officeguard/EtapV3/.claude/hooks/mark-skill-self-review-done.sh

set -e

LOG="/tmp/pre-edit-skill-self-review.log"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
MARKER_DIR="/tmp/claude-skill-edit-markers"
mkdir -p "$MARKER_DIR"

INPUT=$(cat)

# Extract session id (transcript_path basename) + file_path
META=$(echo "$INPUT" | python3 -c "
import json, sys, os
try:
    d = json.load(sys.stdin)
    tp = d.get('transcript_path', '') or ''
    sid = os.path.basename(tp).replace('.jsonl','') if tp else ''
    if not sid:
        # Fallback: date-based (per-day scope)
        import datetime
        sid = 'fallback-' + datetime.datetime.utcnow().strftime('%Y%m%d')
    ti = d.get('tool_input', {}) or {}
    fp = ti.get('file_path', '')
    print(sid)
    print(fp)
except Exception:
    print('')
    print('')
" 2>/dev/null)

SESSION_ID=$(echo "$META" | sed -n '1p')
FILE_PATH=$(echo "$META" | sed -n '2p')

[ -z "$SESSION_ID" ] && SESSION_ID="fallback-$(date +%Y%m%d)"
MARKER="$MARKER_DIR/${SESSION_ID}.json"

# Skill path detection (target = SKILL.md / references/*.md / runtime/*.{sh,py})
# Exclude governance logs + auto-gen
SKILL_NAME=$(echo "$FILE_PATH" | python3 -c "
import sys, re
fp = sys.stdin.read().strip()
# Match shared-skills/{skill}/SKILL.md or references/*.md or runtime/*.{sh,py}
m = re.search(r'/shared-skills/([^/]+)/(SKILL\.md|references/[^/]+\.md|runtime/[^/]+\.(?:sh|py))$', fp)
if not m:
    sys.exit(0)
skill = m.group(1)
sub = m.group(2)
# Exclude auto-gen status.md within services/
if 'services/status.md' in fp:
    sys.exit(0)
print(skill)
" 2>/dev/null)

# Not a guard-target skill file → allow silently
if [ -z "$SKILL_NAME" ]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
    exit 0
fi

# First skill edit in this session?
if [ ! -f "$MARKER" ]; then
    python3 -c "
import json
m = {
    'session_id': '$SESSION_ID',
    'first_edit_at': '$NOW',
    'first_file': '$FILE_PATH',
    'first_skill': '$SKILL_NAME',
    'edits_count': 1,
    'edited_skills': ['$SKILL_NAME'],
    'self_review_done': False,
    'mark_done_script': '/Users/jhee/Documents/workspace/Officeguard/EtapV3/.claude/hooks/mark-skill-self-review-done.sh'
}
with open('$MARKER', 'w') as f:
    json.dump(m, f, indent=2)
"
    echo "$NOW [MARKER_CREATED] session=$SESSION_ID skill=$SKILL_NAME file=$FILE_PATH" >> "$LOG"

    # Emit strong system-reminder (first edit only, avoid spam)
    python3 << REMEOF
import json
out = {
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "allow"
    },
    "systemMessage": (
        "[SKILL EDIT GUARD ★★★] 첫 skill 편집 감지 — skill='$SKILL_NAME', file='$FILE_PATH'.\n\n"
        "**의무**: 편집 종료 전 self-review checklist 수행 (canonical: ~/.claude/memory/feedback_skill_edit_self_review.md).\n\n"
        "7-check (lessons.md §11 + skill-review-deploy/references/edit-self-review-checklist.md 패턴):\n"
        "1. 원칙/숫자 변경 = 전수 grep 검사 (다른 file 의 인용 일관)\n"
        "2. cross-reference 일관성 (SKILL.md ↔ references/, ↔ 다른 skills)\n"
        "3. 의도 vs 실제 변경 일치 (drift 없음)\n"
        "4. forward references (다른 skill 영향 평가)\n"
        "5. file path / line number 변경 시 모든 인용 갱신\n"
        "6. canonical anchor (Polling Policy / Termination Conditions / Mission anchor / HR / D-principle) 영향\n"
        "7. lessons.md / incident-log codify 필요 여부\n\n"
        "**완료 표시 의무**: self-review 완료 후 `bash /Users/jhee/Documents/workspace/Officeguard/EtapV3/.claude/hooks/mark-skill-self-review-done.sh` 실행.\n\n"
        "Stop hook 가 marker 의 self_review_done=true 검증. 미실행 시 stop 차단.\n\n"
        "Skill 편집은 전 Claude session 의 행동에 영향 — ad-hoc 편집 = drift risk. skill-review-deploy 절차 가능 시 우선."
    )
}
print(json.dumps(out))
REMEOF
    exit 0
fi

# Subsequent edit — increment count, silent
python3 -c "
import json
with open('$MARKER') as f:
    m = json.load(f)
m['edits_count'] = m.get('edits_count', 0) + 1
m['last_edit_at'] = '$NOW'
m['last_file'] = '$FILE_PATH'
edited = m.get('edited_skills', [])
if '$SKILL_NAME' not in edited:
    edited.append('$SKILL_NAME')
m['edited_skills'] = edited
with open('$MARKER', 'w') as f:
    json.dump(m, f, indent=2)
"
echo "$NOW [MARKER_UPDATED] session=$SESSION_ID skill=$SKILL_NAME file=$FILE_PATH" >> "$LOG"
echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
exit 0
