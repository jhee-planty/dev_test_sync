# scan-requests.ps1 [-Base <path>] [-Since <id>]
# - git pull (transport only, output to stderr)
# - scan requests/ for *.json, filter > last_processed_id
# - stdout: 3-digit zero-padded IDs, one per line
# - exit 0 always (stdout empty = nothing new)

param(
    [string]$Base = '',
    [int]$Since = -1
)

. (Join-Path $PSScriptRoot 'common.ps1')

if ($Since -lt 0) {
    $state = Get-State
    $Since = [int]$state.last_processed_id
}

# Git pull (transport)
try {
    $null = Invoke-GitInRepo @('pull','origin','HEAD')
} catch {
    Write-TpwLog "git pull failed — continuing with local filesystem"
}

# Filesystem scan
$ids = @()
Get-ChildItem -Path $script:RequestsDir -Filter '*.json' -File -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.Name -match '^(\d+)_') {
        $ids += [int]$Matches[1]
    }
}
$ids = $ids | Sort-Object -Unique
$newIds = $ids | Where-Object { $_ -gt $Since }

foreach ($id in $newIds) {
    '{0:D3}' -f $id
}

Write-TpwLog "scan complete: since=$Since, new=$($newIds.Count)"
exit 0
