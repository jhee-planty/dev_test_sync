# Windows Quirks — DPI 좌표 & Add-Type 충돌 해결

> test PC에서 반복 발생하는 Windows 환경 문제와 해결 패턴.
> 4/10 회고: DPI 좌표 오차 매 스크린샷, Add-Type 충돌 매 .ps1 실행.

---

## 1. DPI 125% 좌표 보정

### 문제

Windows 디스플레이 배율이 125%일 때, `System.Drawing` 스크린샷의 **물리적 좌표**와
`SendKeys`/클릭의 **논리적 좌표**가 불일치한다.
스크린샷에서 측정한 좌표로 클릭하면 엉뚱한 위치를 클릭하게 된다.

### 공식

```
논리적 좌표 = 물리적 좌표 / DPI_SCALE
```

현재 test PC DPI_SCALE = **1.25**

### 헬퍼 함수

```powershell
function Get-LogicalCoordinate {
    param(
        [int]$PhysicalX,
        [int]$PhysicalY,
        [double]$DpiScale = 1.25
    )
    return @{
        X = [math]::Round($PhysicalX / $DpiScale)
        Y = [math]::Round($PhysicalY / $DpiScale)
    }
}

# 사용 예시
$pos = Get-LogicalCoordinate -PhysicalX 960 -PhysicalY 540
[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($pos.X, $pos.Y)
```

### DPI 자동 감지 (선택)

```powershell
Add-Type -TypeDefinition @"
using System.Runtime.InteropServices;
public class DpiHelper {
    [DllImport("user32.dll")] public static extern int GetDpiForSystem();
}
"@
$dpi = [DpiHelper]::GetDpiForSystem()
$scale = $dpi / 96.0  # 96 DPI = 100%, 120 DPI = 125%
```

---

## 2. Add-Type 네임스페이스 충돌

### 문제

PowerShell에서 `Add-Type`으로 같은 클래스명을 다시 정의하면 에러 발생:
```
Cannot add type. The type name 'Win32' already exists.
```

이전 세션에서 정의한 타입이 프로세스 내에 남아 있어서 발생한다.

### 해결: 자동 증분 네임스페이스

```powershell
# 전역 카운터로 매번 고유한 네임스페이스 생성
if (-not $Global:W_N) { $Global:W_N = 0 }
$Global:W_N++

$typeDef = @"
using System;
using System.Runtime.InteropServices;
namespace W$($Global:W_N) {
    public class Win32 {
        [DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(IntPtr hWnd);
        [DllImport("user32.dll")]
        public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
    }
}
"@

Add-Type -TypeDefinition $typeDef
# 사용: [W$($Global:W_N).Win32]::SetForegroundWindow($hwnd)
```

### 대안: 에러 무시 패턴

타입이 이미 존재하면 기존 것을 재사용:
```powershell
try {
    Add-Type -TypeDefinition $typeDef
} catch [System.Exception] {
    # 이미 존재하면 무시 — 기존 타입 사용
}
```

---

## 3. Responsive 모드 토글 (DevTools)

### 문제

F12 DevTools의 Responsive 모드가 세션 중 3-4회 의도치 않게 해제된다.
모바일 뷰포트 테스트 시 결과가 달라진다.

### 해결

DevTools에서 Responsive 모드 재활성화보다 **Snapshot label 클릭**이 빠르다:
1. F12로 DevTools 열기
2. Device Toolbar (Ctrl+Shift+M) 활성화
3. 뷰포트 상단의 Snapshot label (예: "iPhone 14 Pro") 클릭으로 복원

자동화가 필요하면:
```powershell
# F12 열기 + Ctrl+Shift+M으로 Device Mode 토글
Start-Sleep -Milliseconds 500
[void][W1.Win32]::keybd_event(0x7B, 0, 0, [UIntPtr]::Zero)  # F12
Start-Sleep -Milliseconds 1000
# Ctrl+Shift+M
[void][W1.Win32]::keybd_event(0x11, 0, 0, [UIntPtr]::Zero)  # Ctrl down
[void][W1.Win32]::keybd_event(0x10, 0, 0, [UIntPtr]::Zero)  # Shift down
[void][W1.Win32]::keybd_event(0x4D, 0, 0, [UIntPtr]::Zero)  # M
[void][W1.Win32]::keybd_event(0x4D, 0, 2, [UIntPtr]::Zero)  # M up
[void][W1.Win32]::keybd_event(0x10, 0, 2, [UIntPtr]::Zero)  # Shift up
[void][W1.Win32]::keybd_event(0x11, 0, 2, [UIntPtr]::Zero)  # Ctrl up
```
