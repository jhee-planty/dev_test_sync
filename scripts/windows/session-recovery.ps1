# session-recovery.ps1 v1 (matches test-pc-worker SKILL.md 2026-04-07)
# Session Start Recovery + Git Pull + New Request Scan
# Usage: called at every session start and each polling cycle
# Input: $base (dev_test_sync root path)
# Output: $recoveryRequests, $newRequests arrays; updated state.json

param(
    [Parameter(Mandatory=$true)]
    [string]$base
)

# ── 0-1) state.json 로드 ──
$stateFile = "$base\local_archive\state.json"
$lastDeliveredId = 0
$lastProcessedId = 0
if (Test-Path $stateFile) {
    $state = Get-Content $stateFile | ConvertFrom-Json
    $lastProcessedId = if ($state.last_processed_id) { $state.last_processed_id } else { 0 }
    $lastDeliveredId = if ($state.last_delivered_id) { $state.last_delivered_id } else { $lastProcessedId }
}

# ── 0-2) 미push 결과 확인 및 재전송 ──
$unpushed = & cmd /c "cd $base && git log origin/main..HEAD --name-only --oneline 2>&1"
if ($unpushed -and $unpushed -notmatch "^$") {
    Write-Output "Recovery: found unpushed commits. Pushing..."
    & cmd /c "cd $base && git_sync.bat push"
    # push 성공 검증
    $verify = & cmd /c "cd $base && git log origin/main..HEAD --oneline 2>&1"
    if (-not $verify -or $verify -match "^$") {
        $lastDeliveredId = $lastProcessedId
        Write-Output "Recovery: push verified. last_delivered_id updated to $lastDeliveredId"
    }
}

# ── 0-3) 미처리 요청 복구 스캔 ──
$scanFrom = [Math]::Max(0, $lastDeliveredId - 10)
$requests = Get-ChildItem "$base\requests\*_*.json" -ErrorAction SilentlyContinue
$recoveryRequests = @()
foreach ($req in $requests | Sort-Object Name) {
    $reqId = [int]($req.Name.Split('_')[0])
    if ($reqId -gt $scanFrom) {
        $resultExists = Test-Path "$base\results\${reqId}_result.json"
        if (-not $resultExists) {
            $recoveryRequests += Get-Content $req.FullName | ConvertFrom-Json
        }
    }
}

if ($recoveryRequests.Count -gt 0) {
    Write-Output "Recovery scan: $($recoveryRequests.Count) unprocessed requests found (from prior session)"
} else {
    Write-Output "Recovery scan: all requests up to date"
}

# ── 1-1) git pull ──
& cmd /c "cd $base && git_sync.bat pull"

# ── 1-2) filesystem 스캔 (새 요청) ──
$requests = Get-ChildItem "$base\requests\*_*.json" -ErrorAction SilentlyContinue
$newRequests = @()
foreach ($req in $requests | Sort-Object Name) {
    $reqId = [int]($req.Name.Split('_')[0])
    if ($reqId -gt $lastDeliveredId) {
        $resultExists = Test-Path "$base\results\${reqId}_result.json"
        if (-not $resultExists) {
            $newRequests += Get-Content $req.FullName | ConvertFrom-Json
        }
    }
}

if ($newRequests.Count -gt 0) {
    Write-Output "New requests: $($newRequests.Count) to process"
}

# ── 출력 ──
# $recoveryRequests: 이전 세션에서 미처리된 요청
# $newRequests: git pull로 새로 도착한 요청
# $lastProcessedId, $lastDeliveredId: 현재 상태
