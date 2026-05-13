# scan-requests.ps1 [-Base <path>] [-Since <id>]
# - git pull (transport only, output to stderr)
# - scan requests/ for *.json, filter > last_processed_id
# - Multi-PC filter: only emit IDs whose .target_pc matches $script:WorkerId or "both",
#                    or omits .target_pc (legacy, assumed pc1 → only pc1 picks up).
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

# Filesystem scan with per-PC filter
$me = $script:WorkerId
$matched = @()
Get-ChildItem -Path $script:RequestsDir -Filter '*.json' -File -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.Name -match '^(\d+)_') {
        $rid = [int]$Matches[1]
        if ($rid -le $Since) { return }
        # Read target_pc field; default to "pc1" (legacy single-PC)
        try {
            $raw = Get-Content $_.FullName -Raw
            $obj = $raw | ConvertFrom-Json
        } catch {
            Write-TpwLog "skip $($_.Name): JSON parse failed"
            return
        }
        $tpc = $null
        if ($obj.PSObject.Properties.Name -contains 'target_pc') { $tpc = $obj.target_pc }
        if (-not $tpc) { $tpc = 'pc1' }  # legacy backward-compat
        $tpc = $tpc.ToString().ToLower()
        if ($tpc -eq $me -or $tpc -eq 'both') {
            $matched += $rid
        }
    }
}
$matched = $matched | Sort-Object -Unique

foreach ($id in $matched) {
    '{0:D3}' -f $id
}

Write-TpwLog "scan complete: worker=$me, since=$Since, new=$($matched.Count)"
exit 0
