# Test PC Hook 검증 프롬프트

## 목적
Windows Cowork 환경에서 Claude Code Hook이 동작하는지 검증한다.
검증 항목: (1) 실행 환경 확인 (Linux VM vs Windows native), (2) SessionStart 훅 동작, (3) PostToolUse 훅 동작

## Test PC Cowork에 아래 프롬프트를 붙여넣기

---

아래 3단계 작업을 순서대로 진행해줘.

### 1단계: 실행 환경 확인

먼저 현재 Cowork의 실행 환경을 확인해줘:

```bash
echo "=== OS ===" && uname -a && echo "" && echo "=== Shell ===" && echo $SHELL && echo "" && echo "=== Which bash ===" && which bash && echo "" && echo "=== Which jq ===" && which jq 2>/dev/null || echo "jq not found" && echo "" && echo "=== Home ===" && echo $HOME && echo "" && echo "=== .claude dir ===" && ls -la ~/.claude/ 2>/dev/null || echo "no .claude in home" && echo "" && echo "=== Mount points ===" && mount | grep -E 'mnt|Documents|trusting' | head -10
```

결과를 보고 알려줘:
- Linux VM인지 Windows native인지
- bash와 jq가 사용 가능한지
- .claude 디렉토리 경로가 어디인지

### 2단계: 테스트 훅 스크립트 생성

1단계 결과에 따라 적절한 테스트 훅을 생성해줘.

**Linux VM인 경우 (bash 사용 가능):**

```bash
# 훅 디렉토리 생성
mkdir -p /sessions/*/mnt/.claude/hooks 2>/dev/null || mkdir -p ~/.claude/hooks

# SessionStart 테스트 훅
cat > ~/.claude/hooks/test-session-hook.sh << 'HOOKEOF'
#!/bin/bash
echo '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"[TEST HOOK] SessionStart hook is working on test PC! Timestamp: '"$(date +%H:%M:%S)"'"}}'
exit 0
HOOKEOF
chmod +x ~/.claude/hooks/test-session-hook.sh

# PostToolUse 테스트 훅
cat > ~/.claude/hooks/test-posttool-hook.sh << 'HOOKEOF'
#!/bin/bash
INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // "unknown"' 2>/dev/null)
echo "[TEST HOOK] PostToolUse fired for tool: $TOOL" >&2
exit 0
HOOKEOF
chmod +x ~/.claude/hooks/test-posttool-hook.sh
```

**Windows native인 경우 (PowerShell 필요):**

PowerShell 훅 스크립트를 생성:
```powershell
# SessionStart 테스트 훅
$hookDir = "$env:USERPROFILE\.claude\hooks"
New-Item -ItemType Directory -Force -Path $hookDir

$sessionHook = @'
$timestamp = Get-Date -Format "HH:mm:ss"
$output = @{ hookSpecificOutput = @{ hookEventName = "SessionStart"; additionalContext = "[TEST HOOK] SessionStart hook working on test PC! Time: $timestamp" } } | ConvertTo-Json -Compress
Write-Output $output
exit 0
'@
Set-Content -Path "$hookDir\test-session-hook.ps1" -Value $sessionHook
```

### 3단계: settings.json에 훅 등록

**Linux VM인 경우:**

```bash
# settings.json 경로 확인 (세션 디렉토리 내)
SETTINGS=$(find /sessions -name "settings.json" -path "*/.claude/*" 2>/dev/null | head -1)
echo "Found settings: $SETTINGS"

# 없으면 생성
if [ -z "$SETTINGS" ]; then
  SETTINGS="$HOME/.claude/settings.json"
fi

# 현재 내용 백업
cp "$SETTINGS" "${SETTINGS}.bak" 2>/dev/null

# 훅이 있는 디렉토리 확인
HOOK_DIR=$(dirname "$SETTINGS")/hooks
echo "Hook dir: $HOOK_DIR"
ls -la "$HOOK_DIR/"

# settings.json 작성
cat > "$SETTINGS" << SETEOF
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume|compact",
        "hooks": [
          {
            "type": "command",
            "command": "$HOOK_DIR/test-session-hook.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": ".*",
        "hooks": [
          {
            "type": "command",
            "command": "$HOOK_DIR/test-posttool-hook.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
SETEOF

echo "settings.json written:"
cat "$SETTINGS"
```

### 검증 방법

설정 완료 후:
1. **앱 재시작** — SessionStart(startup) 훅이 발동하면 "[TEST HOOK] SessionStart hook is working" 메시지가 보일 것
2. **아무 Bash 명령 실행** (예: `echo hello`) — PostToolUse 훅이 발동하면 stderr에 "[TEST HOOK] PostToolUse fired" 메시지가 보일 것
3. 결과를 dev PC에 알려줘:
   - SessionStart 훅: 동작함 / 안 함
   - PostToolUse 훅: 동작함 / 안 함
   - 실행 환경: Linux VM / Windows native
   - jq 사용 가능: 예 / 아니오

---

## 결과 보고 (dev PC에서 확인)

test PC에서 검증이 끝나면 결과를 `results/` 에 다음 형식으로 저장:

```json
{
  "type": "hook-verification",
  "timestamp": "2026-04-08T...",
  "environment": {
    "os": "Linux VM 또는 Windows",
    "bash_available": true/false,
    "jq_available": true/false,
    "claude_dir": "경로",
    "settings_json_path": "경로"
  },
  "results": {
    "session_start_hook": "pass/fail/not_tested",
    "post_tool_use_hook": "pass/fail/not_tested",
    "notes": "추가 관찰 사항"
  }
}
```
