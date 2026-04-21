# write-result.ps1 -ReqId <id> -ResultJsonPath <path> [-Service <service>]
# - Validates required fields (6 MUST fields in result.* nested)
# - Writes results/{id}_result.json  (or results/{id}_{service}_result.json for batch)
# - Updates state.json.last_processed_id
# - Exit 0 success / exit 1 validation failure / exit 2 fatal

param(
    [Parameter(Mandatory=$true)][string]$ReqId,
    [Parameter(Mandatory=$true)][string]$ResultJsonPath,
    [string]$Service = '',
    [string]$Base = ''
)

. (Join-Path $PSScriptRoot 'common.ps1')

if (-not (Test-Path $ResultJsonPath)) {
    Write-Error "Result JSON not found: $ResultJsonPath"
    exit 2
}

$raw = Get-Content $ResultJsonPath -Raw
try {
    $obj = $raw | ConvertFrom-Json
} catch {
    Write-Error "Invalid JSON: $_"
    exit 2
}

# Validate required fields in .result
$required = @('overall_status','status_detail','service_name','started_at','completed_at','duration_seconds')
$missing = @()
foreach ($f in $required) {
    if (-not $obj.result -or -not $obj.result.$f) { $missing += $f }
}
if ($missing.Count -gt 0) {
    Write-Error "Missing required result fields: $($missing -join ', ')"
    exit 1
}

# Normalize ID
$idNum = [int]$ReqId
$id3 = '{0:D3}' -f $idNum
$obj.id = $id3

# Compute filename
if ($Service) {
    $fname = "${id3}_${Service}_result.json"
} else {
    $fname = "${id3}_result.json"
}
$target = Join-Path $script:ResultsDir $fname

# Atomic write (tmp → rename)
$tmp = "$target.tmp"
$obj | ConvertTo-Json -Depth 16 | Set-Content -Path $tmp -Encoding UTF8
Move-Item -Path $tmp -Destination $target -Force

Write-TpwLog "wrote $target"

# Update state.last_processed_id if higher
$state = Get-State
if ($idNum -gt [int]$state.last_processed_id) {
    Set-StateField -Field 'last_processed_id' -Value $idNum
}

exit 0
