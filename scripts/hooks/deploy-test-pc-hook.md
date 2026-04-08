# Test PC Hook 배포 프롬프트

## Test PC Cowork에 아래 프롬프트를 붙여넣기

---

test PC에 SessionStart 훅을 배포해줘. 아래 단계를 순서대로 진행해.

### 1. 테스트 훅 제거 + 훅 디렉토리 준비

```bash
# 이전 테스트 훅 정리
rm -f /sessions/*/mnt/.claude/hooks/test-session-hook.sh 2>/dev/null
rm -f /sessions/*/mnt/.claude/hooks/test-posttool-hook.sh 2>/dev/null

# 훅 디렉토리 확인
CLAUDE_DIR=$(find /sessions -maxdepth 3 -name ".claude" -type d 2>/dev/null | grep mnt | head -1)
echo "Claude dir: $CLAUDE_DIR"
mkdir -p "$CLAUDE_DIR/hooks"
```

### 2. test-context.sh 복사

dev_test_sync Git 저장소에 훅 스크립트가 이미 있어. 복사해줘:

```bash
BASE=$(find /sessions -maxdepth 4 -name "dev_test_sync" -type d 2>/dev/null | head -1)
CLAUDE_DIR=$(find /sessions -maxdepth 3 -name ".claude" -type d 2>/dev/null | grep mnt | head -1)

echo "Base: $BASE"
echo "Claude dir: $CLAUDE_DIR"

# 최신 동기화
cd "$BASE" && git pull

# 훅 스크립트 복사
cp "$BASE/scripts/hooks/test-context.sh" "$CLAUDE_DIR/hooks/test-context.sh"
chmod +x "$CLAUDE_DIR/hooks/test-context.sh"

echo "Copied:"
ls -la "$CLAUDE_DIR/hooks/test-context.sh"
```

### 3. settings.json 설정

```bash
CLAUDE_DIR=$(find /sessions -maxdepth 3 -name ".claude" -type d 2>/dev/null | grep mnt | head -1)
HOOK_PATH="$CLAUDE_DIR/hooks/test-context.sh"

# 기존 settings.json 백업
cp "$CLAUDE_DIR/settings.json" "$CLAUDE_DIR/settings.json.bak" 2>/dev/null

# 운영용 settings.json 작성
cat > "$CLAUDE_DIR/settings.json" << SETEOF
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "resume|compact",
        "hooks": [
          {
            "type": "command",
            "command": "$HOOK_PATH",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
SETEOF

echo "settings.json written:"
cat "$CLAUDE_DIR/settings.json"
```

### 4. state.json에 polling_active 필드 추가

```bash
BASE=$(find /sessions -maxdepth 4 -name "dev_test_sync" -type d 2>/dev/null | head -1)
STATE="$BASE/local_archive/state.json"

if [ -f "$STATE" ]; then
  # polling_active 필드가 없으면 추가
  if ! jq -e '.polling_active' "$STATE" >/dev/null 2>&1; then
    jq '. + {"polling_active": false}' "$STATE" > "${STATE}.tmp" && mv "${STATE}.tmp" "$STATE"
    echo "Added polling_active field:"
  else
    echo "polling_active already exists:"
  fi
  cat "$STATE"
else
  echo "state.json not found at $STATE"
fi
```

### 5. 검증

앱을 재시작하지 않고 현재 세션에서 훅 스크립트를 직접 테스트:

```bash
CLAUDE_DIR=$(find /sessions -maxdepth 3 -name ".claude" -type d 2>/dev/null | grep mnt | head -1)

echo "=== Dry run test ==="
bash "$CLAUDE_DIR/hooks/test-context.sh"
echo ""
echo "=== Hook exit code ==="
echo $?
```

출력이 `[Test PC Recovery] last_processed: ... | unpushed: ...` 형태면 정상.

**앱 재시작 후 SessionStart 훅이 자동 실행되는지 확인해줘.**
재시작 후 첫 화면에 `[Test PC Recovery]` 메시지가 보이면 배포 성공.

결과를 알려줘.
