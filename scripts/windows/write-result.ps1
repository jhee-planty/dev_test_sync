# write-result.ps1 v1 (matches test-pc-worker SKILL.md 2026-04-07)
# Write result JSON + update state.json (last_processed_id)
# Usage: called after task execution, before git push
# Input: $base, $reqId, $result (hashtable)

param(
    [Parameter(Mandatory=$true)][string]$base,
    [Parameter(Mandatory=$true)][int]$reqId,
    [Parameter(Mandatory=$true)][hashtable]$result
)

# ── result JSON 저장 ──
$resultPath = "$base\results\${reqId}_result.json"
$result | ConvertTo-Json -Depth 10 | Set-Content $resultPath -Encoding UTF8
Write-Output "Result written: $resultPath"

# ── state.json 갱신 (last_processed_id만, delivered는 push 후) ──
$stateFile = "$base\local_archive\state.json"
$state = @{}
if (Test-Path $stateFile) {
    $state = Get-Content $stateFile | ConvertFrom-Json -AsHashtable
}
$state.last_processed_id = $reqId
$state.updated_at = (Get-Date -Format o)
$state | ConvertTo-Json | Set-Content $stateFile -Encoding UTF8
Write-Output "State updated: last_processed_id = $reqId"
