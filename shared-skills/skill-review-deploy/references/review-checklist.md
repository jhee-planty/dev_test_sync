# Review Checklist — 자동 검증 명령어

SKILL.md의 8가지 품질 기준을 자동으로 검증하는 명령어 모음.
Phase 1에서 이 명령어들을 순서대로 실행하여 문제를 검출한다.

---

## 사전 설정

```bash
SKILLS_DIR="/Users/jhee/Documents/workspace/claude_cowork/skills"

# 동적 스킬 목록: SKILL.md가 있는 디렉토리를 자동 스캔
EXCLUDE="example"  # 제외할 패턴 (파이프로 구분: "example|temp|draft")
SKILL_LIST=$(ls -d "$SKILLS_DIR"/*/SKILL.md 2>/dev/null \
  | xargs -I{} dirname {} \
  | xargs -I{} basename {} \
  | grep -vE "$EXCLUDE")
echo "Detected skills: $SKILL_LIST"
```

> **왜 동적 스캔인가:** 하드코딩된 목록은 새 스킬 추가 시 갱신이 누락되어
> 리뷰 대상에서 빠지는 문제가 있었다. `*/SKILL.md` 기준 스캔으로 해결.

---

## 1. YAML Frontmatter 검증

```bash
for skill in $SKILL_LIST; do
  echo "=== $skill ==="
  head -1 "$SKILLS_DIR/$skill/SKILL.md" | grep -q "^---" && echo "  frontmatter: OK" || echo "  frontmatter: MISSING"
  grep -q "^name:" "$SKILLS_DIR/$skill/SKILL.md" && echo "  name: OK" || echo "  name: MISSING"
  grep -q "^description:" "$SKILLS_DIR/$skill/SKILL.md" && echo "  description: OK" || echo "  description: MISSING"
done
```


## 2. Line Count

```bash
echo "=== Line Count ==="
for skill in $SKILL_LIST; do
  lines=$(wc -l < "$SKILLS_DIR/$skill/SKILL.md")
  status="OK"
  [ "$lines" -gt 500 ] && status="CRITICAL (>500)"
  [ "$lines" -gt 300 ] && [ "$lines" -le 500 ] && status="WARNING (>300)"
  printf "  %-30s %4d lines  %s\n" "$skill" "$lines" "$status"
done
```

## 3. Encoding 깨짐 검출

알려진 garbled 한글 패턴을 grep으로 검색한다.
이 패턴들은 UTF-8/EUC-KR 변환 오류에서 빈번히 발생한다.

```bash
echo "=== Encoding Check ==="
GARBLED='읈\|쌬\|뤬\|칹\|캔\|즜\|즙\|욄\|랸\|쯭\|렀\|핼\|헐\|왈\|핌\|뾸\|턄\|닠\|돕릭\|행후'
grep -rn "$GARBLED" $SKILLS_DIR/*/SKILL.md $SKILLS_DIR/*/references/*.md 2>/dev/null
if [ $? -ne 0 ]; then echo "  No garbled characters found"; fi
```

## 4. Cross-Reference Integrity


`→ See` 참조가 가리키는 파일이 실제로 존재하는지 확인한다.

```bash
echo "=== Cross-Reference Integrity ==="
for skill in $SKILL_LIST; do
  grep -n 'references/' "$SKILLS_DIR/$skill/SKILL.md" | while IFS= read -r line; do
    ref=$(echo "$line" | grep -oP 'references/[a-z0-9_-]+\.md' | head -1)
    if [ -n "$ref" ]; then
      if [ ! -f "$SKILLS_DIR/$skill/$ref" ]; then
        echo "  BROKEN: $skill/SKILL.md → $ref"
      fi
    fi
  done
done
```

## 5. Orphan References

references/ 폴더에 있지만 SKILL.md에서 참조되지 않는 파일을 찾는다.
다른 스킬이나 다른 references 파일에서 참조할 수 있으므로 경고 수준.

```bash
echo "=== Orphan References ==="
for skill in $SKILL_LIST; do
  refdir="$SKILLS_DIR/$skill/references"
  [ -d "$refdir" ] || continue
  for f in "$refdir"/*.md; do
    [ -f "$f" ] || continue
    fname=$(basename "$f")
    if ! grep -q "$fname" "$SKILLS_DIR/$skill/SKILL.md" 2>/dev/null; then
      echo "  ORPHAN: $skill/references/$fname"
    fi
  done
done
```

## 6. Cleanup Targets

```bash
echo "=== Cleanup Targets ==="
find $SKILLS_DIR -name "*.bak" -o -name "*.part1" | while read f; do
  echo "  DELETE: $f"
done
```

## 7. Trigger Overlap Check (수동)

description 필드의 트리거 키워드를 추출하여 중복 확인한다.
이 단계는 자동화가 어려우므로 사람이 검토한다.

```bash
echo "=== Trigger Keywords ==="
for skill in $SKILL_LIST; do
  echo "--- $skill ---"
  sed -n '/^description:/,/^---/p' "$SKILLS_DIR/$skill/SKILL.md" | grep -oP '"[^"]*"' | sort
done
```
