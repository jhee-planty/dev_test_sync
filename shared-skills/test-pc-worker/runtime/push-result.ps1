# push-result.ps1 [-Base <path>]
# - Writes per-PC heartbeat (results/heartbeat_{WorkerId}.json)
# - git add results/ + commit + push (3-retry)
# - Update state.json.last_delivered_id to last_processed_id on success
# - Exit 0 success / exit 1 recoverable / exit 2 fatal

param(
    [string]$Base = ''
)

. (Join-Path $PSScriptRoot 'common.ps1')

$state = Get-State
$processed = [int]$state.last_processed_id
$me = $script:WorkerId

# Write per-PC heartbeat (Phase 4: separate heartbeat per worker)
$hbFile = Join-Path $script:ResultsDir "heartbeat_$me.json"
$hb = [ordered]@{
    worker_id          = $me
    mode               = 'in_session_only'
    timestamp          = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    last_processed_id  = $processed
    last_delivered_id  = [int]$state.last_delivered_id
    stage              = 'claude_direct'
}
$hb | ConvertTo-Json | Set-Content -Path $hbFile -Encoding UTF8
Write-TpwLog "heartbeat written: $hbFile (last_processed_id=$processed)"

function Invoke-PushAttempt {
    param([int]$Attempt)
    Invoke-GitInRepo @('add','results') | Out-Null
    Invoke-GitInRepo @('commit','-m',"test-pc-worker[$me]: results through $processed [attempt $Attempt]") | Out-Null
    Invoke-GitInRepo @('push','origin','HEAD') | Out-Null
    return $LASTEXITCODE -eq 0
}

$retries = 3
for ($i = 1; $i -le $retries; $i++) {
    try {
        if (Invoke-PushAttempt -Attempt $i) {
            Set-StateField -Field 'last_delivered_id' -Value $processed
            Write-TpwLog "git push success (attempt $i) worker=$me, last_delivered_id=$processed"
            exit 0
        }
    } catch {
        Write-TpwLog "git push attempt $i error: $_"
    }
    # Recovery
    switch ($i) {
        1 { } # plain retry
        2 { Invoke-GitInRepo @('pull','--rebase','origin','HEAD') | Out-Null }
        3 {
            Invoke-GitInRepo @('stash','push','-u','-m',"push-result-retry") | Out-Null
            Invoke-GitInRepo @('pull','origin','HEAD') | Out-Null
            Invoke-GitInRepo @('stash','pop') | Out-Null
        }
    }
}

Write-TpwLog "git push failed after $retries attempts"
exit 1
