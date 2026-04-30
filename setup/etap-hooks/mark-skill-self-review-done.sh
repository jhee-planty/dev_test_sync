#!/bin/bash
# mark-skill-self-review-done.sh
#
# Claude 가 skill 편집 후 self-review 7-check 완료 시 실행.
# Marker 의 self_review_done=true + checklist_results 기록.
#
# Usage:
#   bash mark-skill-self-review-done.sh "<one-line summary of self-review result>"
#
# 결과: /tmp/claude-skill-edit-markers/{session_id}.json self_review_done=true 갱신
# Stop hook 이 검증.

set -e

MARKER_DIR="/tmp/claude-skill-edit-markers"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
SUMMARY="${1:-self-review 7-check 완료}"

LATEST=$(ls -t "$MARKER_DIR"/*.json 2>/dev/null | head -1)

if [ -z "$LATEST" ] || [ ! -f "$LATEST" ]; then
    echo "ERROR: no skill-edit marker found in $MARKER_DIR — hook 미작동 또는 skill 편집 0건"
    exit 1
fi

python3 -c "
import json
with open('$LATEST') as f:
    m = json.load(f)
m['self_review_done'] = True
m['self_review_at'] = '$NOW'
m['self_review_summary'] = '''$SUMMARY'''
with open('$LATEST', 'w') as f:
    json.dump(m, f, indent=2)
print('Marker updated:', '$LATEST')
print('  edits_count:', m.get('edits_count', 0))
print('  edited_skills:', m.get('edited_skills', []))
print('  self_review_done: True')
"
