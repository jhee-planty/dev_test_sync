# Git Push Guide — Test PC 환경

Test PC(Windows)에서 `dev_test_sync` 저장소의 Git 동기화 표준 절차.
**유일한 허용 방식은 `git_sync.sh` 스크립트 호출이다.**

---

## 환경 정보

| 항목 | 값 |
|------|-----|
| Git 저장소 | `C:\Users\최장희\Documents\dev_test_sync` |
| Remote | `git@github.com:jhee-planty/dev_test_sync.git` (SSH) |
| 기본 브랜치 | **main** (master 아님) |
| SSH 키 | `~/.ssh/id_ed25519` (Git Bash 경로) |
| Git Bash | `C:\Program Files\Git\bin\bash.exe` |
| **통합 스크립트** | `C:\Users\최장희\Documents\git_sync.sh` |

---

## 통합 스크립트: git_sync.sh

`pull`과 `push`를 하나의 스크립트에서 인자로 분기한다.
**컨텍스트가 유실되어도 이 스크립트 외의 방식은 사용하지 않는다.**

### 스크립트 내용

```bash
#!/bin/bash
# git_sync.sh — 유일한 Git 동기화 방법
# Usage: bash git_sync.sh pull   (새 요청 수신)
#        bash git_sync.sh push   (결과 전달)

export GIT_SSH_COMMAND="ssh -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no"
cd "/c/Users/최장희/Documents/dev_test_sync" || { echo "FAILED: cd"; exit 1; }

ACTION="${1:-pull}"

case "$ACTION" in
  pull)
    echo "=== PULL ==="
    git fetch origin main 2>&1
    git pull --rebase origin main 2>&1
    echo "EXIT_CODE: $?"
    ;;
  push)
    echo "=== ADD + COMMIT ==="
    git add results/ 2>&1
    # 변경사항이 없으면 커밋 건너뛰기
    if git diff --cached --quiet; then
      echo "Nothing to commit"
      echo "EXIT_CODE: 0"
      exit 0
    fi
    git commit -m "Result: test-pc $(date +%Y%m%d-%H%M%S)" 2>&1
    echo "=== PULL (rebase) ==="
    git pull --rebase origin main 2>&1
    echo "=== PUSH ==="
    git push origin main 2>&1
    echo "EXIT_CODE: $?"
    ;;
  *)
    echo "Usage: git_sync.sh [pull|push]"
    exit 1
    ;;
esac
```

스크립트 위치: `C:\Users\최장희\Documents\git_sync.sh`

### PowerShell에서 호출 (pull)

```powershell
$gitBash = 'C:\Program Files\Git\bin\bash.exe'
$script  = 'C:\Users\최장희\Documents\git_sync.sh'
$outFile = "$base\results\files\git_pull_out.txt"
$errFile = "$base\results\files\git_pull_err.txt"

Start-Process -FilePath $gitBash `
  -ArgumentList @($script, 'pull') `
  -NoNewWindow -Wait `
  -RedirectStandardOutput $outFile `
  -RedirectStandardError $errFile

$output = Get-Content $outFile -Raw
Write-Output $output
Remove-Item $outFile, $errFile -ErrorAction SilentlyContinue
```

### PowerShell에서 호출 (push)

```powershell
Start-Process -FilePath $gitBash `
  -ArgumentList @($script, 'push') `
  -NoNewWindow -Wait `
  -RedirectStandardOutput $outFile `
  -RedirectStandardError $errFile

$output = Get-Content $outFile -Raw
$errors = Get-Content $errFile -Raw -ErrorAction SilentlyContinue
Write-Output $output
if ($errors) { Write-Output "STDERR: $errors" }
Remove-Item $outFile, $errFile -ErrorAction SilentlyContinue
```

### 성공 판별

출력에서 `EXIT_CODE: 0`이 있으면 성공.
`rejected`, `fatal`, `error` 키워드가 있으면 실패.

---

## 금지 패턴 (이유 포함)

**컨텍스트가 유실되어도 아래 방식은 절대 사용하지 않는다.**
과거에 컨텍스트 유실 후 이 금지 패턴으로 되돌아가는 문제가 반복되었다.

### 1. `&` 연산자로 git.exe 직접 실행 — 금지

```powershell
# ❌ 사용 금지
& 'C:\Program Files\Git\cmd\git.exe' push origin main 2>&1
```

Desktop Commander의 `start_process`에서 PowerShell `&` 연산자로 git.exe를
실행하면 stdout/stderr 출력이 전달되지 않고, exit code가 항상 0으로 반환된다.
push 성공/실패를 판별할 수 없어 거짓 성공이 발생한다.

### 2. `Start-Process` 단독으로 SSH git 명령 — 금지

```powershell
# ❌ SSH 인증 실패
Start-Process -FilePath $gitExe -ArgumentList @('push', 'origin', 'main') -NoNewWindow -Wait
```

`Start-Process`는 자식 프로세스를 생성하므로 `$env:GIT_SSH_COMMAND`가
상속되지 않는다. Windows SSH Agent(ssh-agent 서비스)가 Disabled 상태이면
자식 프로세스에서 SSH 키에 접근할 수 없어 인증이 실패한다.

### 3. `GIT_SSH_COMMAND`에 한글 경로 — 금지

```powershell
# ❌ 한글 경로 깨짐
$env:GIT_SSH_COMMAND = "ssh -i C:\Users\최장희\.ssh\id_ed25519"
```

Git의 SSH가 한글 경로를 해석하지 못한다:
`Warning: Identity file C:Users理쒖옣??sshid_ed25519 not accessible`

git_sync.sh 내에서 `~/.ssh/id_ed25519`로 참조하면 한글 경로 문제를 회피할 수 있다.

### 4. 스크립트 없이 인라인 bash 명령 — 금지

```powershell
# ❌ 인라인 bash도 금지 (출력 캡처 불안정)
Start-Process -FilePath $gitBash -ArgumentList @('-c', 'cd ... && git push ...') ...
```

인라인 `-c` 명령은 따옴표 이스케이핑과 한글 경로 문제가 결합되어 불안정하다.
반드시 파일로 저장된 git_sync.sh를 사용한다.

---

## 브랜치 확인

이 저장소의 기본 브랜치는 `main`이다 (`master` 아님).
git_sync.sh 스크립트에 하드코딩되어 있으므로 변경 시 스크립트도 수정해야 한다.

---

## Remote 충돌 처리

push가 `rejected (fetch first)`로 실패하면:
git_sync.sh의 push 명령에 `git pull --rebase origin main`이 이미 포함되어 있다.
정상적으로 git_sync.sh를 사용하면 대부분의 충돌이 자동 해결된다.

rebase 충돌이 발생하면 수동 개입이 필요하다 → 사용자에게 보고한다.
