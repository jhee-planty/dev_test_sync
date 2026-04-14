---
name: etap-build-deploy
description: >
  EtapV3 build and test server deployment skill. Syncs locally modified source to the compile server, builds, and deploys to the test server. Used for all EtapV3 module changes, not just APF. Make sure to use this skill whenever the user mentions building, deploying, compiling, or pushing code to the test server. Even short requests like "build it", "deploy", "ninja", "scp to server", or "send to test" should trigger this skill. It contains the server addresses, path mappings, scp commands, build verification, and the incremental rebuild workflow for fixing failed services after testing.
---

# EtapV3 Build & Deploy Skill

> ⚠️ **내부 테스트 환경 전용** — 서버 주소·포트·계정 정보는 `references/server-config.md` 참조. 외부 공개 금지.

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

## Classifier-Safe File Handling

> 크래시 재현/퍼징/스트레스 테스트 스크립트는 Read 도구로 읽지 않는다. SSH로 원격 실행하고 결과만 수집.
> → See `../guidelines.md` → Section 10

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

## 작업 시작 전 스킬 로드 확인

이 스킬이 Skill 도구로 로드된 상태에서 빌드·배포를 시작한다.
서버 주소, 경로 매핑, 패키지 파일명 규칙 등을 기억에 의존하면
오래된 정보로 작업하게 된다. 특히 context break 후 재개 시 주의.

---

## 스크립트 사용법 (권장)

Pre-flight부터 배포·검증까지 전체 사이클을 스크립트 1회 실행으로 완료한다.
스크립트는 JSONL을 stdout에 출력하므로 AI agent가 결과를 자동 파싱할 수 있다.

스크립트 위치: `dev_test_sync/scripts/mac/`
공유 함수: `dev_test_sync/scripts/lib/common.sh`
출력 규격: `dev_test_sync/scripts/lib/output-format.md`

### Cowork에서 실행 (desktop-commander 경유)

```bash
SCRIPTS="/Users/jhee/Documents/workspace/dev_test_sync/scripts/mac"

# 사전 검증만 (SSH 연결 + 로컬 repo 확인)
mcp__desktop-commander__start_process:
  command: $SCRIPTS/etap-preflight.sh --check
  timeout_ms: 30000

# 사전 검증 full (branch 일치, symlink, changed files)
mcp__desktop-commander__start_process:
  command: $SCRIPTS/etap-preflight.sh
  timeout_ms: 60000

# 빌드-배포 전체 (git diff로 자동 감지)
mcp__desktop-commander__start_process:
  command: $SCRIPTS/etap-build-deploy.sh
  timeout_ms: 300000

# 특정 파일만 빌드-배포
mcp__desktop-commander__start_process:
  command: $SCRIPTS/etap-build-deploy.sh functions/ai_prompt_filter/ai_prompt_filter.cpp
  timeout_ms: 300000
```

### 스크립트가 하는 일 (8 steps)

1. **source_sync** — 변경 파일 scp 전송 (local → compile server)
2. **ninja_build** — `sudo ninja`
3. **ninja_install** — `sudo ninja install` + 패키지 생성 확인
4. **pkg_download** — 패키지 다운로드 (compile → local)
5. **pkg_upload** — 패키지 업로드 (local → test server)
6. **deploy_safety** — tarball 경로 검사 + symlink 확인
7. **install_restart** — 추출 + daemon-reload + 서비스 재시작
8. **post_verify** — 서비스 상태 + 바이너리 타임스탬프 확인

실패 시 해당 step에서 멈추고 JSONL summary에 log 파일 경로를 출력한다.

### 개별 명령어로 fallback하는 경우

스크립트 자체에 문제가 있거나, 특정 step만 재실행이 필요하면
아래 Pre-flight Checklist / Step 1~4의 개별 명령어를 사용한다.

---

## Pre-flight Checklist (개별 명령어 — fallback)

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

# 5. Verify system symlinks on BOTH servers
ssh -p 12222 solution@218.232.120.58 \
  "[ -L /bin ] && [ -L /lib ] && echo 'Test server OK' || echo 'Test server BROKEN'"
ssh -p 12222 solution@61.79.198.110 \
  "[ -L /bin ] && [ -L /lib ] && echo 'Compile server OK' || echo 'Compile server BROKEN'"
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

## Step 3.5 — Deploy Safety Check (MANDATORY)

패키지 추출 전, tarball이 시스템 디렉토리를 파괴하지 않는지 검증한다.
**이 단계를 건너뛰지 않는다.**

```bash
# 3.5-1. Tarball 내부 경로 검사
ssh -p 12222 solution@218.232.120.58 \
  "tar tzf /home/solution/etap-root-{YYMMDD}.sv.debug.x86_64.el.tgz | head -30"

# STOP 조건: 아래 패턴이 보이면 추출하지 않는다
#   bin/       → /bin 심볼릭 링크를 파괴
#   lib/       → /lib 심볼릭 링크를 파괴
#   sbin/      → /sbin 심볼릭 링크를 파괴
#   etc/       → 시스템 설정 덮어쓰기
# SAFE 패턴: usr/local/bin/, usr/local/lib/ 등 전체 경로

# 3.5-2. 서버 심볼릭 링크 사전 확인
ssh -p 12222 solution@218.232.120.58 \
  "[ -L /bin ] && [ -L /lib ] && echo 'System symlinks OK' || echo 'CRITICAL: System symlinks already broken — run recovery before deploy'"
```

**위험한 tarball이 발견되면:**
1. 추출 중단
2. 사용자에게 보고: "tarball에 bin/ 또는 lib/ 최상위 엔트리가 있어 시스템 심볼릭 링크를 파괴할 수 있습니다"
3. 컴파일 서버의 CMakeLists.txt 또는 패키징 스크립트의 install 경로를 확인/수정 필요

---

## Step 4 — Install & Restart (Test Server)

Extract the package and restart the service on the test server.

```bash
# 4-1. Extract package to /usr/local
ssh -p 12222 solution@218.232.120.58 \
  "sudo tar xzf /home/solution/etap-root-{YYMMDD}.sv.debug.x86_64.el.tgz -C /usr/local"

# 4-2. Post-deploy 심볼릭 링크 검증 (서비스 재시작 전 필수)
ssh -p 12222 solution@218.232.120.58 \
  "[ -L /bin ] && [ -L /lib ] && echo 'System symlinks OK' || echo 'CRITICAL: System symlinks destroyed — DO NOT restart, run recovery first'"

# 4-3. Restart etapd service (심볼릭 링크 OK 확인 후에만)
ssh -p 12222 solution@218.232.120.58 \
  "sudo systemctl restart etapd.service"

# 4-4. Verify service is running
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

## Post-Deploy: 배포 검증 게이트

테스트 요청 전에 배포가 실제로 반영되었는지 확인한다.
미확인 상태에서 테스트를 실행하면 이전 바이너리로 테스트하게 되어 빌드를 낭비한다.

**필수 검증 (자동):**
```bash
# etapd 재시작 확인
ssh -p 12222 solution@218.232.120.58 \
  "systemctl status etapd.service | grep 'Active:'"
# → "Active: active (running)" + 최근 시작 시각이 배포 후여야 함

# 바이너리 타임스탬프 확인
ssh -p 12222 solution@218.232.120.58 \
  "ls -la /usr/local/bin/etapd | awk '{print \$6, \$7, \$8}'"
# → 오늘 날짜 + 배포 시각 이후여야 함
```

검증 실패 시 테스트를 진행하지 않고 배포를 재시도한다.

> **왜 이 게이트가 필요한가:** 2026-03-27 Build #21에서 바이너리 미배포 상태로
> 2건 테스트를 실행하여 낭비. 재배포 후 재테스트가 필요했다.

## Post-Deploy: User Testing

배포 검증 통과 후 test PC에서 차단/경고 동작을 검증한다.
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
→ Note: REMOTE_SRC is /home/solution/source_for_test/EtapV3 (confirmed 2026-04-07)

### Build failure retry
Fix source → Step 1 (sync) → Step 2 (build) repeat.
Extract filename and line number from build error messages to locate the source to fix.

### System Symlink Recovery (심볼릭 링크 복구 런북)

→ See `references/symlink-recovery.md` for 전체 복구 절차 (2026-04-06 실제 사고 검증, 원인 분석 포함).

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

DB 패턴 변경후 반드시 실행. 리로드 없이 테스트하면 이전 패턴으로 동작한다.

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
