---
name: etap-build-deploy
description: >
  EtapV3 build and test server deployment skill. Syncs locally modified source to the compile server, builds, and deploys to the test server. Used for all EtapV3 module changes, not just APF. Make sure to use this skill whenever the user mentions building, deploying, compiling, or pushing code to the test server. Even short requests like "build it", "deploy", "ninja", "scp to server", or "send to test" should trigger this skill. It contains the server addresses, path mappings, scp commands, build verification, and the incremental rebuild workflow for fixing failed services after testing.
---

# EtapV3 Build & Deploy Skill

## Purpose

Sync locally modified EtapV3 source to the compile server,
build, and deploy to the test server.

**Execution:** Cowork runs via Desktop Commander, or
Claude Code main agent runs SSH/scp commands in `-p` mode.
User can also execute directly from terminal.

---

## 터미널 사용 규칙

컴파일 서버와 테스트 서버의 원격 작업은 **하나의 터미널**만 사용한다.
여러 터미널을 열면 어디서 어떤 명령이 실행 중인지 추적이 어렵고,
사용자가 작업과정을 따라가기 어렵다.

```
원칙:
  - scp, ssh, ninja 등 모든 원격 명령은 동일한 터미널에서 순차 실행
  - 작업 과정이 사용자에게 자연스럽게 표시되도록 한다
  - 병렬 실행이 필요하면 하나의 SSH 세션 안에서 `&&`로 체이닝   - 로그 모니터링(tail -f)이 필요한 경우만 예외적으로 두 번째 터미널 허용
```

이 규칙은 사용자가 빌드-배포 진행 상황을 실시간으로 확인할 수 있게 하기 위함이다.

**터미널 누적 방지:** 작업이 반복되면서 열린 터미널이 계속 늘어나는 문제가 있다.
새 터미널을 열기 전에 기존 터미널이 유휴 상태인지 확인하고, 유휴 상태면 재사용한다.
불가피하게 새 터미널을 열었으면 작업 완료 후 정리한다.

---

## SSH 접근 규칙

**Cowork VM에서는 SSH가 불가능하다.** Cowork VM은 네트워크가 격리되어 있어
컴파일 서버/테스트 서버에 직접 SSH 접근이 안 된다.

| 실행 환경 | SSH 방법 | 비고 |
|-----------|---------|------|
| Cowork (Claude chat) | `mcp__desktop-commander__start_process` | 호스트 Mac을 경유하여 SSH 실행 |
| Claude Code (sub agent) | Bash tool에서 직접 `ssh` | 호스트에서 실행되므로 SSH 가능 |
| 사용자 터미널 | 직접 `ssh` | 가장 확실 |

**Cowork에서 SSH 실행 예시:**
```
mcp__desktop-commander__start_process:
  command: ssh -p 12222 solution@218.232.120.58 "명령어"
  timeout_ms: 30000
```

**절대 Cowork VM의 Bash tool에서 ssh/scp를 실행하지 않는다.** 반드시 desktop-commander를 사용한다.

---

## Server Info

| Item | Value |
|------|-------|
| Compile server | `solution@61.79.198.110` (port `12222`) |
| Test server | `solution@218.232.120.58` (port `12222`) |
| Test server etap log | `ssh -p 12222 solution@218.232.120.58 tail -f /var/log/etap.log` |

**Note:** Local public key is registered in the test server's `authorized_keys`. No password needed.

## Paths

```
Local source:
  LOCAL_ETAP = ~/Documents/workspace/Officeguard/EtapV3/

Compile server:
  REMOTE_SRC   = /home/solution/source_for_test/EtapV3/
  REMOTE_BUILD = /home/solution/source_for_test/EtapV3/build/sv_x86_64_debug/
  REMOTE_PKG   = /tmp/etap-root-{YYMMDD}.sv.debug.x86_64.el.tgz

Local temp:
  LOCAL_DL = ~/Downloads/

Test server:
  DEPLOY_PATH = /home/solution/
```

---

## Pre-flight Checklist

Verify before starting the build:

```bash
# 1. Check local branch
cd ~/Documents/workspace/Officeguard/EtapV3 && git branch --show-current

# 2. Check compile server branch (must match local)
ssh -p 12222 solution@61.79.198.110 \
  "cd /home/solution/source_for_test/EtapV3 && git branch --show-current"

# 3. If branches differ, checkout on compile server
ssh -p 12222 solution@61.79.198.110 \
  "cd /home/solution/source_for_test/EtapV3 && git checkout {branch_name}"

# 4. Check changed files
cd ~/Documents/workspace/Officeguard/EtapV3 && git diff --name-only
```

---

## Step 1 — Source Sync (Local → Compile Server)

Transfer only changed files via `scp`.

```bash
# Extract changed file list
cd ~/Documents/workspace/Officeguard/EtapV3
CHANGED=$(git diff --name-only)

# Transfer each file to the same path on compile server
# Example: functions/ai_prompt_filter/ai_prompt_filter.cpp
scp -P 12222 \
  functions/ai_prompt_filter/ai_prompt_filter.cpp \
  solution@61.79.198.110:/home/solution/source_for_test/EtapV3/functions/ai_prompt_filter/ai_prompt_filter.cpp
```

**Path mapping rule:**
Local `LOCAL_ETAP/{relative_path}` → Compile server `REMOTE_SRC/{relative_path}`
Relative paths are preserved as-is.

**Post-transfer verification:**
```bash
ssh -p 12222 solution@61.79.198.110 \
  "ls -la /home/solution/source_for_test/EtapV3/{relative_path}"
```

---

## Step 2 — Build + Install (Compile Server)

빌드와 설치를 한 번에 실행한다.
반복 테스트 시 빌드-배포 사이클 시간을 단축하기 위해
`ninja`와 `ninja install`을 한 명령어로 묶는다.

```bash
ssh -p 12222 solution@61.79.198.110 << 'EOF'
cd /home/solution/source_for_test/EtapV3/build/sv_x86_64_debug
sudo ninja && sudo ninja install
EOF
```

### Success indicators

| Output | Meaning |
|--------|---------|
| `ninja: no work to do.` | No changes (verify source sync) |
| `[N/M] Building CXX object ...` → `[N/N] Linking ...` | Build in progress → complete |
| `[0/1] Installing files.` | Installation successful |
| `/tmp/etap-root-{YYMMDD}.sv.debug.x86_64.el.tgz` | Package created successfully |

### Failure indicators

| Output | Cause | Action |
|--------|-------|--------|
| `FAILED:` | Compile error | Check error message, fix source, retry from Step 1 |
| `error:` | Syntax/linker error | Check line number, fix source |
| `ninja: error: ...` | Build system error | May need CMake reconfiguration |

---

## Step 3 — Deploy (Compile Server → Local → Test Server)

Download the package from compile server to local, then upload to test server.

```bash
# Package filename format: etap-root-{YYMMDD}.sv.debug.x86_64.el.tgz
# Example: etap-root-260319.sv.debug.x86_64.el.tgz

# 3-1. Compile server → Local
scp -P 12222 \
  solution@61.79.198.110:/tmp/etap-root-{YYMMDD}.sv.debug.x86_64.el.tgz \
  ~/Downloads/

# 3-2. Local → Test server
scp -P 12222 \
  ~/Downloads/etap-root-{YYMMDD}.sv.debug.x86_64.el.tgz \
  solution@218.232.120.58:/home/solution/
```

### Package filename convention

`etap-root-{YYMMDD}.sv.debug.x86_64.el.tgz`

- `{YYMMDD}`: Build date (e.g., `260319` = March 19, 2026)
- `sv`: Server build
- `debug`: Debug build
- `x86_64`: Architecture
- `el`: Enterprise Linux (Rocky OS)

**같은 날 여러 번 빌드하면 패키지 파일이 덮어써진다.**
이전 빌드로 롤백해야 할 경우를 대비해 Deploy 전에 수동으로 백업한다:
`cp /tmp/etap-root-{YYMMDD}.* ~/Downloads/backup_`

---

## Step 4 — Install & Restart (Test Server)

Extract the package and restart the service on the test server.

```bash
# 4-1. Extract package to /usr/local
ssh -p 12222 solution@218.232.120.58 \
  "sudo tar xzf /home/solution/etap-root-{YYMMDD}.sv.debug.x86_64.el.tgz -C /usr/local"

# 4-2. Restart etapd service
ssh -p 12222 solution@218.232.120.58 \
  "sudo systemctl restart etapd.service"

# 4-3. Verify service is running
ssh -p 12222 solution@218.232.120.58 \
  "systemctl status etapd.service | head -5"
```

### Success indicators

| Output | Meaning |
|--------|---------|
| `Active: active (running)` | Service restarted successfully |
| No error from `tar xzf` | Package extracted correctly |

### Failure indicators

| Output | Cause | Action |
|--------|-------|--------|
| `Active: failed` | Service crash on startup | Check `journalctl -u etapd.service -n 50` for details |
| `tar: Error ...` | Corrupted or missing package | Re-run Step 3 deploy |
| `Permission denied` | sudo required | Ensure `sudo` is used |

---

## Post-Deploy: User Testing

배포 완료 후 test PC에서 차단/경고 동작을 검증한다.
→ See `genai-warning-pipeline/SKILL.md` § Test-Fix Cycle
→ See `apf-warning-impl/SKILL.md` § Step 5 (test PC에 check-warning 요청)

---

## Incremental Rebuild (test failure → fix → rebuild)

When multiple services are added and only some fail, fix only the failed services' code and rebuild.

### Partial fix + rebuild flow

```
Test results: A passed, B failed, C compile error

1. Fix C code (local)
2. Fix B code (local)
3. Step 1: scp only modified files (B, C related files)
4. Step 2: sudo ninja && sudo ninja install (incremental — only changed files recompiled)
5. Step 3: Deploy package
6. Repeat testing
```

### ninja incremental build

ninja는 파일 타임스탬프로 변경을 감지하여 변경된 파일만 재컴파일한다.
`scp` 전송이 타임스탬프를 업데이트하므로 전송된 파일만 리빌드 대상이 된다.
전체 빌드가 10분 이상 거리는 것에 비해 단일 파일 변경은 1분 이내로 완료된다.

### Build failure analysis

Identify the service from compile error message:
```
FAILED: functions/ai_prompt_filter/CMakeFiles/...
.../ai_prompt_filter.cpp:1234:5: error: ...
```
→ Use line number to identify the generator function
→ Fix only that function → retry from Step 1

---

## Error Handling

### SSH connection failure
```
ssh: connect to host ... port 12222: Connection refused
```
→ Check server status. May be a network/firewall issue.

### scp transfer failure
```
scp: /home/solution/source_for_test/EtapV3/...: No such file or directory
```
→ Verify compile server directory structure. Check path mapping.

### Build failure retry
Fix source → Step 1 (sync) → Step 2 (build) repeat.
Extract filename and line number from build error messages to locate the source to fix.

---

## 검증 된 명령어 참조

이전 세션에서 성공했던 명령어를 재사용 시 실패하는 경우가 있다.
검증된 명령어는 아래에 기록하고, 실패 시 이 목록을 우선 참조한다.

### SSH + MySQL (test 서버 → DB 서버)

```bash
# test 서버에서 DB 접근 (ogsvm = 172.30.10.72)
ssh -p 12222 solution@218.232.120.58 \
  "mysql -h ogsvm -u root -pPlantynet1! etap -e \"SELECT * FROM ai_prompt_filter WHERE service_name='서비스명';\""
```

컴파일 서버(61.79.198.110)에서는 DB 타임아웃이 발생하므로 반드시 test 서버 경유.

### 서비스 리로드 (2026-03-20 검증)

```bash
ssh -p 12222 solution@218.232.120.58 'etapcomm ai_prompt_filter.reload_services'
```

DB 패턴 변경후 반드시 실행. 리로드 없이 테스트하메 이전 패턴으로 동작한다.

### detect 확인 (2026-03-20 검증)

```bash
ssh -p 12222 solution@218.232.120.58 'tail -50 /var/log/etap.log | grep detect_and_mark'
```

리로드 후 detect_and_mark 로그가 찍히는지 확인. 찍히면 DB 패턴 매칭 성공.

### 새로운 성공 명령어 발견 시

이 세션에 추가한다. 형식: 명령어 + 실행 위치 + 확인 날짜.

---

## Related Skills

- **`genai-warning-pipeline`**: Uses this skill as Phase 4 (release build). See Test-Fix Cycle for post-deploy workflow.
- **`apf-warning-impl`**: Phase 3 testing triggers test builds via this skill; Phase 4 release build after test log removal.
- Prior pipeline (backed up): `_backup_20260317/genai-apf-pipeline/SKILL.md`
