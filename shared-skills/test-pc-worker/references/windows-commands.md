# Windows Commands Reference

각 command별 desktop-commander + PowerShell 실행법.
요청 JSON의 `command`를 확인하고 아래 절차대로 실행한다.

**핵심 도구:** desktop-commander의 `start_process`로 PowerShell 명령을 실행한다.
파일 읽기/쓰기는 `read_file`/`write_file`을, 폴더 스캔은 `list_directory`를 사용한다.

**테스트 민감 키워드:** `한글날` — `params.prompt`가 없으면 이 키워드를 기본값으로 사용한다.

### Table of Contents

1. [새 요청 스캔](#새-요청-스캔) — requests/ 미처리 요청 탐색
2. [공통 유틸리티](#공통-유틸리티) — Take-Screenshot, Send-ToBrowser
3. [check-block](#check-block) — AI 서비스 차단 동작 확인
4. [check-warning](#check-warning) — 경고 메시지 표시/내용 확인
5. [check-cert](#check-cert) — SSL 인증서 상태 확인
6. [check-page](#check-page) — 페이지 로딩/동작 확인
7. [capture-screenshot](#capture-screenshot) — 스크린샷 캡처
8. [verify-access](#verify-access) — 서비스 접근 가능 여부
9. [run-scenario](#run-scenario) — 복합 시나리오 순차 실행
10. [report-status](#report-status) — 환경 상태 보고
11. [MCP 호출 최적화](#mcp-호출-최적화) — 처리 속도 향상 지침

---

## 새 요청 스캔

`requests/`에서 아직 처리되지 않은 요청을 찾는다.
`results/`에 `{id}_result.json`이 없는 요청이 새 요청이다.

```powershell
$requests = Get-ChildItem "$base\\requests\\*_*.json" -ErrorAction SilentlyContinue
$results = Get-ChildItem "$base\\results\\*_result.json" -ErrorAction SilentlyContinue |
    ForEach-Object { $_.Name.Split('_')[0] }

$newRequests = @()
foreach ($req in $requests | Sort-Object Name) {
    $reqId = $req.Name.Split('_')[0]
    if ($reqId -notin $results) {
        $newRequests += Get-Content $req.FullName | ConvertFrom-Json
    }
}
```

`desktop-commander`로 실행: `list_directory`로 폴더를 스캔하고, `read_file`로 각 JSON을 읽는다.
PowerShell 스크립트를 직접 `start_process`로 실행해도 된다.

---

## 공통 유틸리티

### 스크린샷 캡처 (PowerShell)

모든 command에서 공통으로 사용하는 스크린샷 함수:

```powershell
function Take-Screenshot($savePath) {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen
    $bitmap = New-Object System.Drawing.Bitmap($screen.Bounds.Width, $screen.Bounds.Height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($screen.Bounds.Location, [System.Drawing.Point]::Empty, $screen.Bounds.Size)
    $bitmap.Save($savePath, [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()
    $bitmap.Dispose()
}
```

**실행 방법:** `start_process`로 위 함수를 포함한 PowerShell 스크립트를 실행한다.

### Chrome 최대화 + 전면 배치 (PowerShell)

**매 작업 시작 시 호출 필수.** 창이 축소된 상태에서 작업하면 스크린샷에 정보가 잘린다.

```powershell
function Ensure-ChromeMaximized {
    Add-Type -Name NativeMethods -Namespace Win32 -MemberDefinition '
      [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
      [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    '
    $chrome = Get-Process chrome -ErrorAction SilentlyContinue |
              Where-Object { $_.MainWindowTitle -ne "" } | Select-Object -First 1
    if ($chrome) {
        [Win32.NativeMethods]::ShowWindow($chrome.MainWindowHandle, 3)  # SW_MAXIMIZE
        [Win32.NativeMethods]::SetForegroundWindow($chrome.MainWindowHandle)
    }
}
```

### 브라우저 키보드 입력 (PowerShell)

Chrome에 텍스트를 입력하고 전송하는 함수:

```powershell
function Send-ToBrowser($text) {
    Add-Type -AssemblyName Microsoft.VisualBasic
    Start-Sleep -Milliseconds 500
    # Chrome 창에 포커스
    $chrome = Get-Process chrome -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -ne "" } | Select-Object -First 1
    if ($chrome) {
        [Microsoft.VisualBasic.Interaction]::AppActivate($chrome.Id)
        Start-Sleep -Milliseconds 300
        [System.Windows.Forms.SendKeys]::SendWait($text)
        Start-Sleep -Milliseconds 300
        [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
    }
}
```

**주의:** `SendKeys`는 Chrome 창이 포커스된 상태에서만 동작한다.
다른 창이 앞에 있으면 `AppActivate`로 포커스를 먼저 가져와야 한다.

---

## check-block

AI 서비스에서 Etap 차단이 작동하는지 확인.

**입력:** `params.service`, `params.prompt` (없으면 `"한글날"` 사용)

**실행 순서:**

1. **브라우저 열기** — `start_process`:
   ```powershell
   $url = switch ($service) {
       "chatgpt" { "https://chat.openai.com" }
       "gemini"  { "https://gemini.google.com" }
       "claude"  { "https://claude.ai" }
       default   { $params.url }
   }
   Start-Process chrome $url
   ```
2. **페이지 로딩 대기** — `Start-Sleep -Seconds 3` (→ See "MCP 호출 최적화" § 원칙 2)
3. **로그인 확인** — 스크린샷으로 로그인 필요 여부 판단. 필요시 사용자에게 알림.
4. **프롬프트 입력** — `Send-ToBrowser` 함수로 키워드 입력:
   ```powershell
   $prompt = if ($params.prompt) { $params.prompt } else { "한글날" }
   Send-ToBrowser $prompt
   ```
5. **응답 대기** — `Start-Sleep -Seconds 3` (차단 테스트는 응답이 빠름. 서비스에 따라 조정)
6. **DevTools 검증** — 스크린샷 전에 반드시 DevTools로 교차 확인:
   - Network 탭: 프롬프트 POST 요청이 실제로 나갔는지 확인 (요청 없으면 입력 실패)
   - Console 탭: 에러 확인 (`ERR_HTTP2_PROTOCOL_ERROR` 등은 진단 핵심 정보)
   - 화면 변화 없는 서비스: Console/Network에 변화가 있으면 작업 완료로 판단
   → See `browser-rules.md` § "DevTools 활용 — 동작 검증"
7. **스크린샷 캡처** — `Take-Screenshot`으로 결과 화면 저장
8. **판단** — 스크린샷 + DevTools 결과를 종합하여:
   - 정상 AI 응답 → `blocked: false`
   - 응답 없이 멈추거나 에러 화면 → `blocked: true`
   - 경고 메시지 표시 → `blocked: true` + 텍스트 기록

**HTTP 레벨 사전 확인 (선택):**
브라우저 테스트 전에 `Invoke-WebRequest`로 빠르게 확인할 수 있다:
```powershell
try {
    $resp = Invoke-WebRequest -Uri $url -TimeoutSec 10 -UseBasicParsing
    # 200이면 접근은 가능 → 브라우저에서 프롬프트 입력 테스트 진행
} catch {
    # 연결 자체가 차단되면 → blocked: true (프록시 레벨 차단)
}
```

---

## check-warning

경고 메시지가 올바르게 표시되는지 확인. check-block의 확장.

**입력:** `params.service`, `params.expected_text`, `params.expected_format`

**실행 순서:**

1~5: check-block과 동일 (프롬프트: `"한글날"` 또는 `params.prompt`)
6. **DevTools 검증** — check-block과 동일한 DevTools 교차 확인 수행:
   - Network 탭: 프롬프트 요청 확인 + 응답 상태 코드
   - Console 탭: 에러/경고 수집 (result JSON의 `console_errors`에 기록)
   - Elements 탭: 경고 텍스트 노드가 DOM에 존재하는지 확인
7. **스크린샷 캡처** — 경고 메시지가 표시된 화면 저장
8. **페이지 텍스트 추출 (선택)** — `start_process`로 PowerShell 실행:
   ```powershell
   # Chrome의 페이지 내용을 직접 읽을 수 없으므로
   # 스크린샷 기반으로 Cowork가 시각적 판단을 수행한다.
   # 필요시 Ctrl+A → Ctrl+C로 텍스트 복사 시도:
   [System.Windows.Forms.SendKeys]::SendWait("^a")
   Start-Sleep -Milliseconds 200
   [System.Windows.Forms.SendKeys]::SendWait("^c")
   $clipText = Get-Clipboard
   ```

**판정 순서 (Network 최우선 — browser-rules.md § "프롬프트 전송 후 판정" 참조):**
```
1. Network에서 프롬프트 포함 POST 요청 확인
   → 요청 없음 → blocked: false, 입력 미전송 (입력 방식 재시도)
   → 요청 있음 → 2로
2. 화면 상태:
   → 경고 보임 → warning_visible: true, SUCCESS
   → 에러 보임 → warning_visible: false, BLOCKED_WITH_ERROR
   → 초기 화면 복귀 → silent_reset: true, BLOCKED_SILENT_RESET
   → 변화 없음 → Console 확인 → BLOCKED_NO_RENDER 또는 추가 대기
3. 텍스트 매칭: expected_text 포함 여부
4. 포맷 판단: "markdown" | "text" | "error"
```

**입력 자동화 실패 시 HTTP fallback:**
모든 입력 전략(6순위)이 실패한 경우, 서비스 API에 직접 HTTP 요청을 보내
차단 여부만 확인한다 → result에 `automation_failed_http_fallback: true` 기록.
→ See `browser-rules.md` § "입력 자동화 실패 시 대응 전략"

**시각적 판단의 이유:**
Chrome MCP 없이는 DOM에 직접 접근할 수 없다.
대신 Cowork가 스크린샷을 읽고 멀티모달로 내용을 판단한다.
이 방식이 실제로 사용자가 보는 화면과 동일하므로 UX 검증에 더 적합하다.

---

## check-cert

SSL 인증서 상태 확인.

**입력:** `params.url`, `params.checks[]` (optional)

**실행 순서:**

1. **PowerShell로 인증서 확인** — `start_process`:
   ```powershell
   $url = $params.url
   try {
       $request = [System.Net.HttpWebRequest]::Create($url)
       $request.Timeout = 10000
       $response = $request.GetResponse()
       $cert = $request.ServicePoint.Certificate
       $cert2 = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($cert)

       $result = @{
           valid = $true
           issuer = $cert2.Issuer
           subject = $cert2.Subject
           not_before = $cert2.NotBefore.ToString("o")
           not_after = $cert2.NotAfter.ToString("o")
           days_remaining = ($cert2.NotAfter - (Get-Date)).Days
           thumbprint = $cert2.Thumbprint
       }
       $response.Close()
   } catch {
       $result = @{
           valid = $false
           error = $_.Exception.Message
       }
   }
   $result | ConvertTo-Json
   ```
2. **브라우저 확인 (선택)** — 인증서 경고 페이지가 뜨는지 시각적으로 확인:
   ```powershell
   Start-Process chrome $url
   Start-Sleep -Seconds 3
   Take-Screenshot "$screenshotPath"
   ```

**Chrome MCP 대비 장점:**
PowerShell의 `X509Certificate2` API로 인증서 상세 정보(발급자, 만료일, 잔여일수)에
직접 접근할 수 있다. Chrome JS API에서는 불가능했던 정보를 정확히 얻을 수 있다.

---

## check-page

페이지 로딩/동작 정상 여부 확인.

**입력:** `params.url`, `params.checks[]`

**실행 순서:**

1. **HTTP 상태 확인** — `start_process`:
   ```powershell
   $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
   $resp = Invoke-WebRequest -Uri $params.url -TimeoutSec 30 -UseBasicParsing
   $stopwatch.Stop()
   $loadTimeMs = $stopwatch.ElapsedMilliseconds
   $statusCode = $resp.StatusCode
   $bodyText = $resp.Content
   ```

2. **check 항목별 검증:**

   | check type | 구현 |
   |-----------|---------|
   | `status_ok` | `$statusCode -eq 200` |
   | `load_time_under` | `$loadTimeMs -lt $params.ms` |
   | `text_contains` | `$bodyText -match $params.text` |
   | `no_redirect` | `$resp.BaseResponse.ResponseUri -eq $params.url` |

3. **브라우저 시각 확인 (선택)** — HTTP로 확인이 어려운 경우:
   ```powershell
   Start-Process chrome $params.url
   Start-Sleep -Seconds 3
   Take-Screenshot "$screenshotPath"
   ```

**참고:** `element_exists` (CSS selector)는 HTTP 레벨에서 확인 불가.
필요하면 `$bodyText`에서 정규식으로 HTML 태그를 검색하거나,
브라우저 + 스크린샷으로 시각적 확인한다.

---

## capture-screenshot

지정된 페이지의 스크린샷 캡처.

**입력:** `params.url`, `params.steps[]` (optional), `params.description`

**실행 순서:**

1. **브라우저 열기** — `start_process`:
   ```powershell
   Start-Process chrome $params.url
   Start-Sleep -Seconds 3
   ```
2. **steps가 있으면** 각 단계 순차 실행:
   - `"login"` → 사용자에게 로그인 요청, 완료 대기
   - `"send test prompt"` → `Send-ToBrowser "한글날"` (또는 params.text)
   - `"wait"` → `Start-Sleep -Seconds $step.seconds`
   - `"capture result"` → `Take-Screenshot`
3. **steps가 없으면** 현재 페이지 바로 캡처
4. `create_directory`로 `results/files/{id}/` 생성 후 스크린샷 저장

---

## verify-access

서비스 접근 가능 여부 확인.

**입력:** `params.url` (또는 `params.service`에서 URL 유추)

**실행 순서:**

1. **HTTP 접근 확인** — `start_process`:
   ```powershell
   try {
       $resp = Invoke-WebRequest -Uri $url -TimeoutSec 15 -UseBasicParsing -MaximumRedirection 0
       $accessible = $true
       $loginRequired = $false
   } catch {
       if ($_.Exception.Response.StatusCode -eq 302 -or $_.Exception.Response.StatusCode -eq 301) {
           $accessible = $true
           $loginRequired = $true  # 리다이렉트 → 로그인 페이지 가능성
       } else {
           $accessible = $false
       }
   }
   ```
2. **브라우저 확인 (보조)** — 시각적으로 접근 상태 확인:
   ```powershell
   Start-Process chrome $url
   Start-Sleep -Seconds 3
   Take-Screenshot "$screenshotPath"
   ```
3. **판단:**
   - 정상 로드 → `accessible: true`
   - 로그인 리다이렉트 → `accessible: true, login_required: true`
   - 타임아웃/차단 → `accessible: false`

---

## run-scenario

여러 단계를 순차 실행하는 복합 시나리오.

**입력:** `params.steps[]`, `params.description`

**steps 배열의 각 action:**

| action | 구현 |
|--------|---------|
| `open` | `Start-Process chrome $step.url` |
| `send-prompt` | `Send-ToBrowser $step.text` (기본값: `"한글날"`) |
| `observe` | 스크린샷 캡처 후 Cowork가 시각적 판단 |
| `screenshot` | `Take-Screenshot "$path\\$step.name.png"` |
| `click` | `SendKeys` TAB/ENTER 조합 또는 좌표 클릭 |
| `wait` | `Start-Sleep -Seconds $step.seconds` |
| `check-text` | 클립보드 복사(`Ctrl+A, Ctrl+C`) 후 텍스트 검색 |
| `run-ps` | `start_process`로 임의의 PowerShell 명령 실행 |
| `http-check` | `Invoke-WebRequest`로 HTTP 레벨 확인 |

각 단계의 결과를 배열로 기록한다.
한 단계가 실패해도 나머지 단계는 계속 실행하고, 실패한 단계를 표시한다.

**참고:** Chrome MCP의 `click` (CSS selector 기반)은 사용할 수 없다.
대신 TAB 키로 포커스를 이동하거나, PowerShell의 마우스 좌표 클릭을 사용한다.

---

## report-status

현재 test PC 환경 상태 보고.

**입력:** params 없음 (또는 빈 객체)

**실행 순서:**

1. **시스템 정보 수집** — `start_process`:
   ```powershell
   $info = @{
       os = (Get-CimInstance Win32_OperatingSystem).Caption
       hostname = $env:COMPUTERNAME
       chrome_version = (Get-Item "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe").VersionInfo.FileVersion
       online = (Test-Connection -ComputerName 8.8.8.8 -Count 1 -Quiet)
   }
   ```
2. **Etap 프록시 확인** — AI 서비스에 접근 시도:
   ```powershell
   try {
       $resp = Invoke-WebRequest -Uri "https://chat.openai.com" -TimeoutSec 10 -UseBasicParsing
       $info.etap_proxy = "unknown"  # 응답 헤더에서 프록시 흔적 확인
   } catch {
       $info.etap_proxy = "blocked_or_error"
       $info.error = $_.Exception.Message
   }
   ```
3. **네트워크 설정 확인:**
   ```powershell
   $proxy = [System.Net.WebRequest]::GetSystemWebProxy()
   $info.system_proxy = $proxy.GetProxy("https://chat.openai.com").AbsoluteUri
   ```
4. **결과 종합 보고**

---

## MCP 호출 최적화

desktop-commander 호출마다 네트워크 왕복이 발생한다. 호출 횟수를 줄이면 전체 처리 속도가 크게 향상된다.

### 원칙 1 — 하나의 PowerShell 스크립트로 병합

여러 단계를 개별 `start_process`로 나누지 않고, 하나의 스크립트에 병합한다.

**나쁜 예 (3회 MCP 호출):**
```
start_process: powershell -Command "Start-Process chrome $url"
start_process: powershell -Command "Start-Sleep -Seconds 5"
start_process: powershell -Command "Take-Screenshot $path"
```

**좋은 예 (1회 MCP 호출):**
```
start_process: powershell -Command "
  Start-Process chrome $url
  Start-Sleep -Seconds 3
  Add-Type -AssemblyName System.Windows.Forms, System.Drawing
  $screen = [System.Windows.Forms.Screen]::PrimaryScreen
  $bmp = New-Object System.Drawing.Bitmap($screen.Bounds.Width, $screen.Bounds.Height)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($screen.Bounds.Location, [System.Drawing.Point]::Empty, $screen.Bounds.Size)
  $bmp.Save('$path', [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose()
"
```

### 원칙 2 — Start-Sleep 최소화

| 기존 값 | 최적화 값 | 비고 |
|---------|-----------|------|
| `Start-Sleep -Seconds 5` (페이지 로딩) | `Start-Sleep -Seconds 3` | 3초로 시작, 실패 시만 증가 |
| `Start-Sleep -Seconds 2` (포커스 대기) | `Start-Sleep -Milliseconds 500` | 포커스 전환은 빠름 |
| `Start-Sleep -Milliseconds 500` (SendKeys 전) | `Start-Sleep -Milliseconds 300` | 300ms면 충분 |
| `Start-Sleep -Seconds 5` (응답 대기) | `Start-Sleep -Seconds 3` | 차단 테스트는 응답이 빠름 |

### 원칙 3 — 파일 읽기/쓰기 병합

결과 JSON 작성과 메트릭 기록을 하나의 PowerShell 스크립트로 처리할 수 있다:
```powershell
# result + metrics를 한 번에 쓰기
$result | ConvertTo-Json | Set-Content "$base\results\${id}_result.json"
$metric | ConvertTo-Json -Compress | Add-Content "$base\results\metrics\metrics_$(Get-Date -Format 'yyyy-MM-dd').jsonl"
```

### 원칙 4 — list_directory + read_file 최소화

폴링 스캔 시 `list_directory` 한 번으로 새 요청 유무를 판단한다.
새 요청이 없으면 추가 MCP 호출을 하지 않는다.
새 요청이 있을 때만 `read_file`로 상세 내용을 읽는다.
