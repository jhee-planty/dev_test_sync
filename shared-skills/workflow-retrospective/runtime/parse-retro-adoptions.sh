#!/bin/bash
# parse-retro-adoptions.sh
# E1 — workflow-retrospective 의 이전 회고 adoption status 파싱.
# 입력: 가장 최근 `retrospective_*.md` 의 "## 이전 회고 추적" 테이블
# 출력: stdout 에 JSON { status, file, counts, total, warning, items[] }
#
# 적용 위치: shared-skills/workflow-retrospective/runtime/parse-retro-adoptions.sh
#
# 사용:
#   bash parse-retro-adoptions.sh
#   bash parse-retro-adoptions.sh --dir /path/to/metrics    # 경로 override
#
# warning 필드 규칙:
#   - total=0 → null
#   - unadopted ratio ≥ 40% → "Unadopted ratio ... — review prior proposals first"
#   - 그 외 → null
#
# workflow-retrospective SKILL.md 의 새 Step 0.5 에서 호출 (E1-skill-step-addition.md 참조).

set -eu

# Canonical location (현재 운영) + fallback (구 경로)
RETRO_DIRS=(
  "$HOME/Documents/workspace/claude_work/docs/retrospectives"
  "$HOME/Documents/workspace/dev_test_sync/shared-skills/workflow-retrospective/metrics"
)
if [ "${1:-}" = "--dir" ] && [ -n "${2:-}" ]; then
  RETRO_DIRS=("$2")
fi

# Find most recent retrospective_YYYY-MM-DD.md by FILENAME date (not mtime — file copies shift mtime)
LATEST=""
LATEST_DATE="0000-00-00"
for d in "${RETRO_DIRS[@]}"; do
  [ ! -d "$d" ] && continue
  for f in "$d"/retrospective_*.md; do
    [ ! -f "$f" ] && continue
    BASE=$(basename "$f")
    # Extract YYYY-MM-DD from filename
    DATE=$(echo "$BASE" | sed -n 's/^retrospective_\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\)\.md$/\1/p')
    [ -z "$DATE" ] && continue
    if [ "$DATE" \> "$LATEST_DATE" ]; then
      LATEST_DATE=$DATE
      LATEST=$f
    fi
  done
done

if [ -z "$LATEST" ]; then
  echo '{"status":"no_retrospective_found","file":null}'
  exit 0
fi

python3 - "$LATEST" <<'PY'
import re, json, sys
path = sys.argv[1]
try:
    with open(path, encoding='utf-8') as f:
        content = f.read()
except Exception as e:
    print(json.dumps({"status":"read_error","error":str(e),"file":path}))
    sys.exit(0)

# Find "## 이전 회고 추적" section and capture the first markdown table under it
m = re.search(
    r'##\s*이전\s*회고\s*추적\s*(?:\n|[^\n#]+\n)+?'
    r'(\|[^\n]+\n\|[-:\| ]+\n(?:\|[^\n]+\n)+)',
    content, re.S)
if not m:
    print(json.dumps({"status":"no_adoption_table","file":path}, ensure_ascii=False))
    sys.exit(0)

table = m.group(1)
rows = [r for r in table.strip().split('\n') if r.startswith('|')]
if len(rows) < 3:
    print(json.dumps({"status":"empty_table","file":path}, ensure_ascii=False))
    sys.exit(0)

data_rows = rows[2:]  # skip header + separator

counts = {"적용":0, "부분 적용":0, "미적용":0, "other":0}
items = []
for r in data_rows:
    cells = [c.strip().strip('*').strip() for c in r.split('|')[1:-1]]
    if len(cells) < 3:
        continue
    date = cells[0]
    proposal = cells[1]
    status_raw = cells[2]
    compact = re.sub(r'[*\s]+', '', status_raw)
    if "부분적용" in compact:
        key = "부분 적용"
    elif "미적용" in compact:
        key = "미적용"
    elif "적용" in compact:
        key = "적용"
    else:
        key = "other"
    counts[key] += 1
    items.append({
        "date": date,
        "proposal": proposal[:80],
        "status": status_raw,
        "key": key
    })

total = sum(counts.values())
warning = None
if total > 0:
    unadopted_ratio = counts["미적용"] / total
    if unadopted_ratio >= 0.4:
        warning = (
            f"Unadopted ratio {unadopted_ratio:.0%} "
            f"({counts['미적용']}/{total}) — review prior proposals before generating new ones "
            f"(INTENTS §3 I3 adoption gap closure)"
        )

out = {
    "status": "ok",
    "file": path,
    "counts": counts,
    "total": total,
    "warning": warning,
    "items": items
}
print(json.dumps(out, ensure_ascii=False, indent=2))
PY
