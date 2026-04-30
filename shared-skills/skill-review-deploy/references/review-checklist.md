# Review Checklist — 자동 검증 명령어

SKILL.md의 11 검증 항목 (§1-§7 static + §8-§11 library-wide sweep) 을 자동으로 검증하는 명령어 모음.
Phase 1에서 이 명령어들을 순서대로 실행하여 문제를 검출한다.

---

## 사전 설정

```bash
SKILLS_DIR="/Users/jhee/Documents/workspace/dev_test_sync/shared-skills"   # canonical deploy (12 skills 전체 audit 시)
# 5 APF project source 만 보려면: SKILLS_DIR="/Users/jhee/Documents/workspace/claude_work/projects/cowork-micro-skills/skills"

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

---

## Library-wide Runtime / Meta-data Sweep (C9-C12 보조)

SKILL.md Quality Criteria 9-12 는 **per-change** 검증 (edit-self-review-checklist §8-§11 에서 실행). 본 리뷰 단계 (library-wide batch) 에서는 **health sweep** 만 수행.

### 8. Side-effect Profile Header Audit (C11 보조)

runtime script 중 `side-effect-profile` 헤더 미선언 식별:

```bash
echo "=== Side-effect Profile Audit ==="
RUNTIME_DIRS="$SHARED/*/runtime /Users/jhee/Documents/workspace/claude_work/projects/apf-operation/scripts"
for d in $RUNTIME_DIRS; do
  [ -d "$d" ] || continue
  for f in "$d"/*.sh; do
    [ -f "$f" ] || continue
    profile=$(head -5 "$f" | grep -oE "side-effect-profile:\s*S[0-3]" | awk '{print $NF}')
    if [ -z "$profile" ]; then
      echo "  UNCLASSIFIED: $f"
    fi
  done
done
```

UNCLASSIFIED 는 retrofit debt — 다음 touch 시 헤더 추가. 급한 수정 아님.

### 9. Runtime Script Destructive-Pattern Audit (C11 misclassification)

S0/S1 선언된 script 에 destructive / network 패턴 있으면 misclassification 의심:

```bash
for d in $RUNTIME_DIRS; do
  [ -d "$d" ] || continue
  for f in "$d"/*.sh; do
    [ -f "$f" ] || continue
    profile=$(head -5 "$f" | grep -oE "side-effect-profile:\s*S[0-3]" | awk '{print $NF}')
    if [[ "$profile" == "S0" || "$profile" == "S1" ]]; then
      grep -lE "curl|wget|git push|scp|ssh|rm |DELETE|DROP" "$f" && \
        echo "  CAUTION: $f profile=$profile contains potentially destructive pattern"
    fi
  done
done
```

### 10. Installation Integrity (C12)

```bash
bash ~/.claude/hooks/check-installation.sh
echo "RC=$?"
```

기대: `3/3 checks passed` + RC=0. 1+ failure 시 stderr 경고 확인 후 수정.

### 11. Discussion-review Invocation Audit (C9, 선택)

지난 30일 review 리포트에 "External Review Decision" 섹션 부재 여부 (monthly audit item):

```bash
# review 리포트 디렉터리 (outputs 또는 archived)
find ~/Library/Application\ Support/Claude/local-agent-mode-sessions -name "skill-review-report-*.md" -mtime -30 2>/dev/null | while read f; do
  grep -q "External Review Decision" "$f" || echo "  MISSING §8: $f"
done
```

**해당 sweep 들은 Phase 1 리뷰 시 수행**. 상세 per-change 검증은 `edit-self-review-checklist.md` §8-§11 참조.
