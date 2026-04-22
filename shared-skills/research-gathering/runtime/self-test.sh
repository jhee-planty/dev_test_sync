#!/bin/bash
# self-test.sh — research-gathering skill SELF_TEST_PASSED gate
#
# 사용: bash self-test.sh [--bootstrap]
#
# 동작:
#   1. 스킬 구성 파일 존재 확인
#   2. (all nodes 구현된 경우) 자기 이름/관련어로 실제 스캔 수행
#   3. 결과 검증: Tier 3 에서 본 skill 설계 토론 발견, Tier 1 에서 SKILL.md 발견
#   4. 모두 통과 → .research-run/SELF_TEST_PASSED 마커 작성 (version + timestamp)
#
# Bootstrap 역설:
#   최초 invocation 은 nodes/ 가 skeleton 이므로 실제 scan 불가.
#   --bootstrap flag 로 "skeleton 상태를 인지하고 승인" 하는 초기 marker 생성.
#   이 marker 는 version=1-bootstrap 으로 기록되어 실제 scan 은 여전히 거부.
#   nodes/ 구현 완료 후 --bootstrap 없이 재실행하여 version=1 marker 로 upgrade.

set -eu

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RUN_ROOT="${RESEARCH_RUN_ROOT:-$PWD/.research-run}"
MARKER="$RUN_ROOT/SELF_TEST_PASSED"
BOOTSTRAP=false
SKILL_VERSION="1"

for arg in "$@"; do
  case "$arg" in
    --bootstrap) BOOTSTRAP=true ;;
    --help|-h)
      cat <<USAGE
Usage: bash self-test.sh [--bootstrap]

Options:
  --bootstrap       Skeleton 상태에서 bootstrap marker 작성.
                    실제 scan 은 여전히 거부됨. nodes/ 구현 후 재실행 필요.

동작:
  1. 스킬 파일 구조 검증 (SKILL.md, references/, runtime/)
  2. --bootstrap 아니면: 실제 scan 수행 + 결과 검증
  3. 통과 시 $MARKER 작성
USAGE
      exit 0 ;;
  esac
done

mkdir -p "$RUN_ROOT"

echo "[self-test] skill_dir=$SKILL_DIR"
echo "[self-test] run_root=$RUN_ROOT"
echo "[self-test] bootstrap=$BOOTSTRAP"

# ───── Check 1: 스킬 파일 구조 ─────
echo ""
echo "[check 1] 스킬 파일 구조 검증"

REQUIRED_FILES=(
  "$SKILL_DIR/SKILL.md"
  "$SKILL_DIR/references/incident-log.md"
  "$SKILL_DIR/references/schema-v1.md"
  "$SKILL_DIR/references/batch-linked-list.md"
  "$SKILL_DIR/runtime/research-scan.sh"
  "$SKILL_DIR/runtime/self-test.sh"
)

MISSING=0
for f in "${REQUIRED_FILES[@]}"; do
  if [ -f "$f" ]; then
    echo "  ✓ $f"
  else
    echo "  ✗ $f (missing)"
    MISSING=$((MISSING+1))
  fi
done

if [ "$MISSING" -gt 0 ]; then
  echo ""
  echo "[self-test] FAILED — $MISSING 파일 누락"
  exit 1
fi

# ───── Check 2: SKILL.md frontmatter ─────
echo ""
echo "[check 2] SKILL.md frontmatter"

if head -20 "$SKILL_DIR/SKILL.md" | grep -q "^name: research-gathering$"; then
  echo "  ✓ name: research-gathering"
else
  echo "  ✗ name 필드 없음/잘못됨"
  exit 1
fi

if head -20 "$SKILL_DIR/SKILL.md" | grep -q "^description:"; then
  echo "  ✓ description 필드 존재"
else
  echo "  ✗ description 필드 없음"
  exit 1
fi

# ───── Check 3: runtime/nodes 구현 상태 ─────
echo ""
echo "[check 3] runtime/nodes 구현 상태"

NODE_NAMES=(keyword_expand git_scan memory_scan filesystem_scan transcript_scan aggregate_dedup contradiction_check promotion_suggest)
IMPLEMENTED=0
TOTAL=${#NODE_NAMES[@]}

for n in "${NODE_NAMES[@]}"; do
  if [ -f "$SKILL_DIR/runtime/nodes/${n}.py" ]; then
    echo "  ✓ nodes/${n}.py"
    IMPLEMENTED=$((IMPLEMENTED+1))
  else
    echo "  ✗ nodes/${n}.py (not implemented)"
  fi
done

echo ""
echo "[check 3] implementation status: $IMPLEMENTED / $TOTAL"

# ───── Check 4 (bootstrap 제외): 실제 self-scan ─────
if [ "$BOOTSTRAP" = false ]; then
  if [ "$IMPLEMENTED" -lt "$TOTAL" ]; then
    echo ""
    echo "[self-test] FAILED — nodes 미구현 ($IMPLEMENTED/$TOTAL). --bootstrap 으로 skeleton marker 작성 가능."
    exit 1
  fi

  echo ""
  echo "[check 4] self-scan 수행 (키워드: research-gathering)"
  # 실제 scan 호출 — v1.0.1 이후 활성화. v1 skeleton 에서는 도달 불가.
  RESULT=$(bash "$SKILL_DIR/runtime/research-scan.sh" --keyword "research-gathering" --consumer interactive --retention session 2>&1) || {
    echo "  ✗ self-scan failed"
    echo "$RESULT" | head -20
    exit 1
  }
  echo "  ✓ self-scan completed"
  # TODO v1.0.1: report.json 파싱해 findings 검증
fi

# ───── Marker 작성 ─────
echo ""
if [ "$BOOTSTRAP" = true ]; then
  MARKER_VERSION="1-bootstrap"
  echo "[self-test] writing bootstrap marker (scan 은 여전히 거부됨)"
else
  MARKER_VERSION="$SKILL_VERSION"
  echo "[self-test] writing full marker"
fi

cat > "$MARKER" <<MARKER
$MARKER_VERSION
timestamp: $(date -u +"%Y-%m-%dT%H:%M:%S+00:00")
skill_dir: $SKILL_DIR
implemented_nodes: $IMPLEMENTED / $TOTAL
bootstrap: $BOOTSTRAP
MARKER

echo ""
echo "[self-test] marker written to $MARKER"
echo "[self-test] PASSED ($MARKER_VERSION)"

if [ "$BOOTSTRAP" = true ]; then
  echo ""
  echo "[self-test] ⚠️  Bootstrap marker — research-scan.sh 는 여전히 gate 에서 거부됨."
  echo "[self-test]    nodes/ 구현 후 bash self-test.sh (without --bootstrap) 재실행 필요."
fi

exit 0
