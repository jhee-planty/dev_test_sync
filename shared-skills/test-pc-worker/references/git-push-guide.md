# Git Push Guide — Test PC 환경

Test PC(Windows)에서 `dev_test_sync` 저장소의 Git 동기화 표준 절차.
**유일한 허용 방식은 `git_sync.bat` 스크립트 호출이다.**

---

## 환경 정보

| 항목 | 값 |
|------|-----|
| Git 저장소 | `C:\Users\최장희\Documents\dev_test_sync` |
| Remote | `https://github.com/jhee-planty/dev_test_sync.git` (**HTTPS**) |
| 기본 브랜치 | **main** (master 아님) |
| 인증 | `.git-credentials` (HTTPS token 저장) |
| Git 실행파일 | `C:\PROGRA~1\Git\bin\git.exe` |
| **통합 스크립트** | `git_sync.bat` (저장소 루트) |

**[중요] SSH → HTTPS 전환 완료 (2026-04-02)**
사내 네트워크에서 SSH 포트 22가 차단되어 HTTPS로 영구 전환.
`git@github.com:` URL은 더 이상 사용하지 않는다.

---

## 통합 스크립트: git_sync.bat

`pull`과 `push`를 하나의 스크립트에서 인자로 분기한다.
**컨텍스트가 유실되어도 이 스크립트 외의 방식은 사용하지 않는다.**

### 사용법

```
git_sync.bat pull     ← 새 요청 수신
git_sync.bat push     ← 결과 전달 (add + commit + rebase + push)
```

저장소 디렉토리 안에서 실행. Desktop Commander `shell: cmd`로 실행한다.

### 핵심 설계

- `%~dp0` — bat 파일 자신의 경로를 사용. 한글 경로 하드코딩 불필요.
- `pushd "%~dp0"` — 저장소 디렉토리로 이동. `-C` 옵션의 한글 인코딩 문제 회피.
- `setlocal EnableDelayedExpansion` — if 블록 내 `!ERRORLEVEL!` 정상 작동.
- 변경사항 없으면 `Nothing to commit` + `EXIT_CODE: 0`으로 조기 종료.

### 성공 판별

출력에서 `EXIT_CODE: 0`이 있으면 성공.
`rejected`, `fatal`, `error` 키워드가 있으면 실패.

---

## Desktop Commander에서 호출

### pull (새 요청 수신)

```
# shell: cmd 로 실행
git_sync.bat pull
```

### push (결과 전달)

```
# shell: cmd 로 실행
git_sync.bat push
```

### 인라인 폴백 (bat 파일 실행 자체가 실패하는 극히 예외적 상황)

```cmd
C:\PROGRA~1\Git\bin\git.exe -C . add results/
C:\PROGRA~1\Git\bin\git.exe -C . commit -m "Result: test-pc fallback"
C:\PROGRA~1\Git\bin\git.exe -C . pull --rebase origin main
C:\PROGRA~1\Git\bin\git.exe -C . push origin main
```

**주의:** 인라인 폴백은 저장소 디렉토리에 이미 cd된 상태에서만 `-C .`이 작동한다.
한글 절대 경로를 `-C` 인자로 넣으면 인코딩이 깨진다.

---

## 금지 패턴 (이유 포함)

**컨텍스트가 유실되어도 아래 방식은 절대 사용하지 않는다.**
과거에 컨텍스트 유실 후 이 금지 패턴으로 되돌아가는 문제가 반복되었다.

### 1. SSH URL — 금지 (사내망 포트 22 차단)

```
# ❌ 사용 금지
git@github.com:jhee-planty/dev_test_sync.git
```

사내 네트워크에서 SSH(포트 22) 아웃바운드가 차단. remote URL은 HTTPS로 설정 완료.
SSH URL로 되돌리지 않는다.

### 2. Git Bash 경유 — 금지

```powershell
# ❌ 사용 금지
Start-Process -FilePath 'C:\Program Files\Git\bin\bash.exe' ...
```

Git Bash 스크립트(.sh)는 폐기됨. cmd 셸 + .bat 방식이 유일한 안정적 방법.
`git_sync.sh`가 남아있어도 무시하고 `git_sync.bat`만 사용한다.

### 3. PowerShell `&` 연산자로 git.exe 직접 실행 — 금지

```powershell
# ❌ 사용 금지
& 'C:\Program Files\Git\cmd\git.exe' push origin main 2>&1
```

Desktop Commander의 `start_process`에서 PowerShell `&` 연산자로 git.exe를
실행하면 stdout/stderr 출력이 전달되지 않고, exit code가 항상 0으로 반환.
push 성공/실패를 판별할 수 없어 거짓 성공이 발생한다.

### 4. Start-Process 단독으로 git 명령 — 금지

```powershell
# ❌ SSH 인증 실패 (HTTPS에서도 credential 상속 문제 가능)
Start-Process -FilePath $gitExe -ArgumentList @('push', 'origin', 'main') -NoNewWindow -Wait
```

### 5. `-C "한글경로"` 옵션 — 금지

```cmd
# ❌ 인코딩 깨짐
C:\PROGRA~1\Git\bin\git.exe -C C:\Users\최장희\Documents\dev_test_sync status
```

git.exe의 `-C` 옵션이 cmd의 한글 인코딩을 해석하지 못한다:
`fatal: cannot change to 'C:\Users\理쒖옣??Documents\dev_test_sync'`

git_sync.bat은 `pushd %~dp0`으로 이 문제를 회피한다.

### 6. cmd에서 `cd /d` + 한글 절대 경로 — 금지

```cmd
# ❌ 인코딩 깨짐 가능
cd /d C:\Users\최장희\Documents\dev_test_sync
```

`pushd`는 UNC 경로도 처리하고 `popd`로 원복 가능하여 더 안전.

---

## 브랜치 확인

이 저장소의 기본 브랜치는 `main`이다 (`master` 아님).
git_sync.bat 스크립트에 하드코딩되어 있으므로 변경 시 스크립트도 수정해야 한다.

---

## Remote 충돌 처리

push가 `rejected (fetch first)`로 실패하면:
git_sync.bat의 push에 `git pull --rebase origin main`이 이미 포함되어 있다.
정상적으로 git_sync.bat를 사용하면 대부분의 충돌이 자동 해결된다.

rebase 충돌이 발생하면 수동 개입이 필요 → 사용자에게 보고한다.

---

## HTTPS 인증

- `.git-credentials` 파일에 토큰이 저장되어 있어 push 시 인증 프롬프트 없이 작동.
- 토큰 만료 시 cmd에서 `git push`를 수동으로 한 번 실행하면 credential이 갱신됨.
- credential 문제가 의심되면: `C:\PROGRA~1\Git\bin\git.exe -C . config credential.helper`로 확인.
