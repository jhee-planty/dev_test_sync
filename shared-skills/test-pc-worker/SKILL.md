---
name: test-pc-worker
description: >
  Test PC 전용 작업 실행 스킬. dev PC가 Git 저장소(dev_test_sync)의 requests/에 보낸 요청을
  읽고, desktop-commander(Windows MCP)를 통해 PowerShell + 브라우저 자동화로
  웹 테스트를 수행하고, 결과를 보고한다.
  실망(실제 망) 환경에서 Etap 클라이언트로 동작하는 Windows PC에서 사용.
  AI 서비스 차단/경고 확인, 인증서 확인, 페이지 동작 확인 등 웹 테스트 전반을 담당.
  Use this skill whenever: "새 요청 확인", "작업 처리", "폴링 시작",
  "자동으로 확인", "dev에서 요청 왔어?", "check-block", "check-warning",
  "테스트 실행", or any request to process dev PC tasks.
---

# Test PC Worker Skill

## Purpose

dev PC가 Git 저장소(dev_test_sync)의 `requests/`에 보낸 작업 요청을 수신하여
desktop-commander(Windows MCP)를 통해 실행하고, 결과를 `results/`에 보고하는 스킬.

**왜 이 PC가 필요한가:**
dev PC는 실망(실제 망)에 연결되어 있지 않아 Etap 프록시를 통한
웹 서비스 접근이 불가능하다. 이 PC만이 실제 클라이언트 환경에서
AI 서비스 차단/경고, 인증서, 페이지 동작을 검증할 수 있다.

**왜 desktop-commander인가:**
test PC에서는 Chrome MCP를 사용할 수 없다. 대신 desktop-commander의
`start_process`로 PowerShell 스크립트를 실행하여 HTTP 요청, 브라우저 실행,
키보드 시뮬레이션, 스크린샷 캡처 등을 수행한다.
PowerShell + .NET API 조합으로 Chrome MCP의 핵심 기능을 대체한다.

**이 PC의 제한:**
Etap 서버에 직접 접근할 수 없다. 클라이언트 입장에서만 확인한다.

---

## Environment

| 항목 | 값 |
|------|-----|
| OS | Windows |
| MCP 도구 | desktop-commander (`start_process`, `read_file`, `write_file`, `list_directory`) |
| 파일 처리 | PowerShell (desktop-commander의 start_process로 실행) |
| 웹 테스트 | PowerShell `Invoke-WebRequest` + 브라우저 키보드 시뮬레이션 |
| 스크린샷 | PowerShell .NET `System.Drawing` API |
| Git 저장소 | `C:\Users\최장희\Documents\dev_test_sync` |
| 테스트 민감 키워드 | `한글날` (APF 차단 테스트용) |

**Cowork에서 사용 시:** Git 저장소 폴더를 Cowork에 마운트(폴더 선택)해야 한다.
마운트된 경로가 `$base`가 된다.
작업 시작 전 `git_sync.bat pull`로 최신 요청 수신.
**Git 방식:** HTTPS + cmd 셸 + `git_sync.bat` (저장소 루트에 위치). SSH/Git Bash 금지.

**desktop-commander 도구 매핑:**

| 작업 | desktop-commander 도구 | 비고 |
|------|----------------------|------|
| PowerShell 실행 | `start_process` | `powershell -Command "..."` |
| 파일 읽기 | `read_file` | 요청 JSON 읽기 |
| 파일 쓰기 | `write_file` | 결과 JSON 작성 |
| 폴더 목록 | `list_directory` | requests/ 스캔 |
| 폴더 생성 | `create_directory` | files/{id}/ 생성 |
| 프로세스 관리 | `start_process` + `kill_process` | Chrome 실행/종료 |

---

## Folder Structure

```
$base (dev_test_sync)/
├── requests/               ← dev가 보낸 요청. 읽기만 한다.
│   ├── {id}_{command}.json
│   └── files/{id}/
├── results/                ← 결과를 여기에 쓴다. 이 폴더만 쓰기 가능.
│   ├── {id}_result.json
│   ├── files/{id}/
│   └── metrics/
├── queue.json              ← 참고용. 수정하지 않는다.
├── shared-skills/          ← 스킬 공유. 읽기만 한다.
└── local_archive/         ← 로컬 전용 (gitignored)
```

**핵심 규칙:** `results/`에만 파일을 생성한다.
`requests/`, `queue.json`은 절대 수정하지 않는다.
쓰기 방향 분리가 Git 충돌을 방지하는 핵심이다.
작업 완료 후 `git_sync.bat push`로 dev에 전달 (add + commit + push 자동 처리).

→ See `references/git-push-guide.md` for Git push 표준 절차 및 금지 패턴.

**세션 상태 파일:** `local_archive/state.json`
세션이 끊겨도 마지막 처리 ID를 기억하여 이전 요청을 다시 읽지 않는다.
```json
{ "last_processed_id": 15, "updated_at": "2026-03-24T14:30:00" }
```
이 파일은 gitignored(local_archive/)라 Git 충돌이 없다.

---

## Operation Modes

### Mode 1 — 사용자 지시 (기본)

사용자가 "새 요청 확인해줘" 하면 `git pull` 후 `requests/`를 스캔하고 처리한다.

### Mode 2 — 자동 폴링

사용자가 "자동으로 확인해줘", "폴링 시작" 하면 활성화.

**폴링 시작 전 스킬 재확인:**
세션이 새로 시작되었거나 작업이 끊긴 후 재개하는 경우,
폴링을 시작하기 전에 반드시 이 스킬(test-pc-worker)을 다시 읽는다.
스킬이 업데이트되었을 수 있고, 절차를 기억에 의존하면 단계를 빠뜨린다.
```
폴링 시작 체크리스트:
  1. Skill 도구로 test-pc-worker 스킬 로드 (최신 절차 확인)
  2. state.json 읽어서 last_processed_id 확인
  3. git_sync.bat pull로 최신 요청 수신
  4. 폴링 루프 시작
```

**핵심 원칙: 폴링 모드에서는 사용자 동의 없이 자율 실행한다.**
새 요청을 발견하면 사용자에게 확인을 구하지 않고 바로 실행하고,
완료 후 결과만 보고한다. 사용자가 폴링을 시작한 시점에 이미 동의한 것이다.

**적응형 폴링 (Adaptive Polling):**
```
Stage 1: 1분 간격 × 10회 (10분)
  → 새 요청 없으면 Stage 2로 전환
Stage 2: 10분 간격 × 6회 (1시간)
  → 새 요청 없으면 Stage 3으로 전환
Stage 3: 1시간 간격
  → 새 요청 도착 시 Stage 1로 복귀
```

  새 요청 있으면 → 사용자 확인 없이 즉시 실행 → 결과 작성 → 완료 보고
  없으면 → 무음 대기 (불필요한 "없음" 보고 생략)

종료 조건:
  - 사용자가 "멈춰", "중단" → 즉시 종료
  - 에러 3회 연속 → 일시 중지 후 보고

---

## Execution Flow

### Step 1 — 세션 상태 로드 + 새 요청 스캔

```powershell
# 1) 마지막 처리 ID 로드 (세션 재시작 시 핵심)
$stateFile = "$base\local_archive\state.json"
$lastId = 0
if (Test-Path $stateFile) {
    $state = Get-Content $stateFile | ConvertFrom-Json
    $lastId = $state.last_processed_id
    Write-Output "Resuming from last_processed_id: $lastId"
}

# 2) lastId보다 큰 요청만 스캔 (이전 요청 재읽기 방지)
$requests = Get-ChildItem "$base\requests\*_*.json" -ErrorAction SilentlyContinue
$newRequests = @()
foreach ($req in $requests | Sort-Object Name) {
    $reqId = [int]($req.Name.Split('_')[0])
    if ($reqId -gt $lastId) {
        # result가 이미 있는지도 확인 (중복 처리 방지)
        $resultExists = Test-Path "$base\results\${reqId}_result.json"
        if (-not $resultExists) {
            $newRequests += Get-Content $req.FullName | ConvertFrom-Json
        }
    }
}
```

새 요청이 여러 건이면 `priority: "urgent"`를 먼저 처리한다.

### Step 2 — 요청 읽기 + 명령 실행

요청 JSON의 `command` 필드에 따라 desktop-commander + PowerShell로 작업을 수행한다.

**[필수] 매 작업 시작 시 표준 화면 배열:**
브라우저 작업 전에 반드시 Ensure-ChromeMaximized를 실행한다.
"최초 1회"가 아니라 "매 작업마다" 실행해야 한다.
탭 전환, AnyDesk 접속, 이전 세션 복원 등으로 창이 축소되는 문제를 방지한다.
```
매 작업 시작 시 (이 Step 진입 시점):
  1. Ensure-ChromeMaximized 실행 (→ windows-commands.md § 공통 유틸리티)
  2. Chrome이 실행되지 않았으면: Chrome 실행 + 최대화
  3. F12로 DevTools 열기 (Chrome 내부 하단 도킹 유지)
```

→ See `references/windows-commands.md` for per-command execution details.
→ See `references/browser-rules.md` for 브라우저 설정 및 DevTools 검증 규칙.

**브라우저 작업 시 반드시 DevTools를 활용한다.**
스크린샷만으로는 타이밍 문제로 오판할 수 있다. DevTools 기반 검증이 정확도를 높인다.

핵심 규칙:
- Chrome 최초 실행 시 F12로 DevTools 열기 (하단 도킹, 별도 창 분리 금지)
- 키 입력 후 → Elements에서 input value 확인
- 전송 후 → Network 탭에서 요청이 나갔는지 확인
- 응답 후 → Console 에러 확인 (ERR_HTTP2_PROTOCOL_ERROR 등 진단 핵심)
- 화면 변화 없는 서비스(Gemini 등) → Console/Network으로 작업 완료 판단

→ See `references/browser-rules.md` § "DevTools 활용 — 동작 검증" for 전체 체크리스트.

**스크린샷 표준 규칙 (dev 측 L3 시각 진단 보완):**
dev PC는 결과 파일 도착 전에 AnyDesk로 이 PC 화면을 볼 수 있다.
dev 측 판독 정확도를 높이기 위해, 작업 중 화면 상태를 예측 가능하게 유지한다.
```
  작업 시작 시: 브라우저를 전면에 배치 (최대화)
  작업 완료 시: 결과 화면을 유지한 채 스크린샷 캡처 → results/files/{id}/에 저장
  실패 시: 에러 상태 화면 + DevTools Console 스크린샷 모두 캡처
```
스크린샷은 result JSON의 `screenshots` 배열에 파일 경로를 기록한다.

### Step 3 — 결과 작성 + 상태 갱신

`results/{id}_result.json`에 결과를 저장한다.
스크린샷 등 첨부파일은 `results/files/{id}/`에 저장한다.

**결과 저장 후 즉시 state.json을 갱신한다:**
```powershell
# state.json 갱신 (세션이 끊겨도 여기까지 처리했음을 기록)
$stateFile = "$base\local_archive\state.json"
$newState = @{ last_processed_id = $reqId; updated_at = (Get-Date -Format o) }
$newState | ConvertTo-Json | Set-Content $stateFile -Encoding UTF8
```
result 작성과 state 갱신은 git push 전에 수행한다.
세션이 push 중 끊겨도 state가 이미 갱신되어 있으므로 재시작 시 중복 처리를 방지한다.

→ See `references/result-templates.md` for JSON templates.

### Step 3.5 — 메트릭 수집

작업 완료 후 result 작성과 함께 `results/metrics/metrics_{date}.jsonl`에 메트릭을 기록한다.
메트릭 파일이 없으면 새로 생성하고, 있으면 append한다.

```powershell
$metricsFile = "$base\results\metrics\metrics_$(Get-Date -Format 'yyyy-MM-dd').jsonl"
$metric = @{
    id = $reqId
    command = $command
    service = $params.service
    timestamp = (Get-Date -Format o)
    duration_seconds = $stopwatch.Elapsed.TotalSeconds
    success = ($result.status -eq "success")
    phase_timings = @{
        browser_focus = $timing.browser_focus
        prompt_input = $timing.prompt_input
        wait_response = $timing.wait_response
        screenshot = $timing.screenshot
        analysis = $timing.analysis
    }
}
$metric | ConvertTo-Json -Compress | Add-Content $metricsFile -Encoding UTF8
```

**필수 필드:** id, command, service, timestamp, duration_seconds, success, phase_timings
**phase_timings 최소 단계:** browser_focus, prompt_input, wait_response, screenshot, analysis

→ See `references/metrics-collection.md` for 메트릭 수집 상세 및 분석 연동.
→ See `references/phase-definitions.md` for command별 측정 단계 정의.

오늘(3/25) 29건 check-warning에 대한 메트릭이 누락되어 정밀 분석이 불가능했다.
"어디가 느린지"를 수치로 파악하려면 단계별 시간 데이터가 필수이다.

**타이밍 수집 방법:**
각 단계 시작 전에 `$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()`으로 측정하고,
단계 종료 시 `$stopwatch.Elapsed.TotalSeconds`를 기록한다.

### Step 4 — Git Push (git_sync.bat 단일 호출)

결과를 dev에 전달하기 위해 **반드시 `git_sync.bat push`를 사용한다.**
다른 방식은 **모두 금지**한다. 컨텍스트가 유실되어도 이 규칙은 변하지 않는다.

```
git_sync.bat push
```

Desktop Commander의 cmd 셸(`shell: cmd`)에서 실행한다.
저장소 디렉토리 안에서 실행하면 된다 (bat 파일이 `%~dp0`으로 자동 위치 판별).

**금지 패턴 (컨텍스트 유실 시에도 절대 사용하지 않는다):**
- ❌ `& 'C:\Program Files\Git\cmd\git.exe' push ...` → PowerShell 출력 캡처 불가
- ❌ `Start-Process -FilePath $gitExe` 단독 → SSH 인증 실패
- ❌ SSH URL (`git@github.com:`) → 사내망 포트 22 차단
- ❌ Git Bash (`bash.exe`) 경유 → cmd 방식이 유일한 안정적 방법
- ❌ `-C "한글경로"` 옵션 → 인코딩 깨짐 (`理쒖옣??`)
- ❌ `git_sync.sh` → 폐기됨. `.bat`만 사용

→ See `references/git-push-guide.md` for git_sync.bat 상세 및 금지 패턴 이유.

**[마이그레이션]** 기존 `git_sync.sh`가 남아있을 수 있다. 무시하고 `git_sync.bat`만 사용.

### Step 5 — 완료 보고

```
"작업 #{id} ({command}) 완료.
결과: {brief summary}
git push 완료. dev PC에서 git pull로 확인 가능합니다."
```

push 과정에서 생성된 임시 파일(`git_push_out.txt`, `git_push_err.txt` 등)은
보고 후 삭제한다.

---

## Test Sensitive Keyword

APF 차단/경고 테스트에 사용하는 민감 키워드: **`한글날`**

이 키워드를 AI 서비스에 입력하면 Etap이 차단 또는 경고를 표시해야 한다.
요청 JSON에 `params.prompt`가 없으면 이 키워드를 기본값으로 사용한다.

---

## Error Handling

작업 실행 중 문제 발생 시:

1. `status: "error"`로 result 작성, `error_detail`에 원인 기록
2. 가능하면 에러 상태 스크린샷 첨부
3. 사용자에게 보고

흔한 에러 패턴:

| 증상 | 원인 | 대응 |
|------|------|------|
| 페이지 로딩 실패 | 네트워크/프록시 문제 | 재시도, report-status로 환경 확인 |
| 로그인 필요 | 세션 만료 | 사용자에게 로그인 요청 |
| Invoke-WebRequest 타임아웃 | 프록시/방화벽 | 타임아웃 값 증가, 프록시 설정 확인 |
| SendKeys 미입력 | Chrome 포커스 상실 | `AppActivate`로 포커스 재확보 |
| 스크린샷 빈 화면 | 캡처 타이밍 | `Start-Sleep` 대기 시간 증가 |
| 차단이 발생하지 않음 | Etap 설정 미적용 | 정확히 기록, dev가 서버 설정 확인 |

→ See `references/error-patterns.md` for 에러 패턴별 상세 원인 및 대응 방법.

---

## Command Overview

### APF 관련 (주 작업)

| Command | 설명 |
|---------|------|
| `check-block` | AI 서비스에서 차단 동작 확인 |
| `check-warning` | 경고 메시지 표시/내용 확인 |

### 범용 웹 테스트

| Command | 설명 |
|---------|------|
| `check-cert` | SSL 인증서 상태 확인 |
| `check-page` | 페이지 로딩/동작 정상 여부 확인 |
| `capture-screenshot` | 스크린샷 캡처 |
| `verify-access` | 서비스 접근 가능 여부 확인 |
| `run-scenario` | 복합 시나리오 순차 실행 |
| `report-status` | 현재 환경 상태 보고 |

→ See `references/windows-commands.md` for desktop-commander tool mapping and execution steps.

---

## Batch Processing

여러 요청이 동시에 도착했을 때:

**Mode 1 (사용자 지시):** 요청 목록을 표시하고 사용자 확인 후 처리.
**Mode 2 (자동 폴링):** 확인 없이 바로 순차 처리. 완료 후 종합 보고만.

1. `urgent` 우선, 나머지 순차 처리
2. 각 작업 완료 시 즉시 result 작성 (전체 완료를 기다리지 않음)
3. 모든 작업 완료 후 종합 보고 (대화 메시지로, 별도 파일 아님)

→ result를 즉시 쓰는 이유: dev PC가 폴링 중이면 하나씩 도착하는 것이 유리하다.

---

## Related Skills

- **`cowork-remote`** (dev PC): 이 스킬의 상대방. dev가 요청을 생성하고 결과를 읽는다.
- **`genai-warning-pipeline`** (dev PC): Phase 1, 3에서 이 PC에 작업을 보낸다.
- **`desktop-commander`** (MCP): 이 스킬의 핵심 실행 도구. PowerShell 실행, 파일 I/O, 프로세스 관리.
