# common.ps1 — dot-sourced by test-pc-worker runtime scripts.
# Provides: $Base resolution, state file paths, logging, JSON helpers.

$ErrorActionPreference = 'Stop'

if (-not $Base) {
    # Default paths (override via -Base parameter)
    $candidates = @(
        'C:\workspace\dev_test_sync',
        "$env:USERPROFILE\Documents\dev_test_sync",
        "$env:USERPROFILE\workspace\dev_test_sync"
    )
    foreach ($c in $candidates) {
        if (Test-Path (Join-Path $c '.git')) { $Base = $c; break }
    }
}
if (-not $Base -or -not (Test-Path (Join-Path $Base '.git'))) {
    Write-Error "[test-pc-worker] Base git repo not found. Set -Base explicitly."
    exit 2
}

$script:RequestsDir = Join-Path $Base 'requests'
$script:ResultsDir  = Join-Path $Base 'results'
$script:QueueJson   = Join-Path $Base 'queue.json'
$script:LocalArchive = Join-Path $Base 'local_archive'
$script:StateJson   = Join-Path $LocalArchive 'state.json'

if (-not (Test-Path $LocalArchive)) { New-Item -ItemType Directory -Path $LocalArchive -Force | Out-Null }
if (-not (Test-Path $ResultsDir))   { New-Item -ItemType Directory -Path $ResultsDir -Force | Out-Null }

function Write-TpwLog {
    param([string]$Msg)
    $ts = Get-Date -Format 'HH:mm:ss'
    Write-Host "[$ts] $Msg"
}

function Initialize-State {
    if (-not (Test-Path $script:StateJson)) {
        $init = [ordered]@{
            last_processed_id = 0
            last_delivered_id = 0
            updated_at = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            schema_version = '1.0'
        }
        $init | ConvertTo-Json | Set-Content -Path $script:StateJson -Encoding UTF8
    }
}

function Get-State {
    Initialize-State
    return Get-Content $script:StateJson -Raw | ConvertFrom-Json
}

function Set-StateField {
    param([string]$Field, $Value)
    $state = Get-State
    $state.$Field = $Value
    $state.updated_at = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $state | ConvertTo-Json | Set-Content -Path $script:StateJson -Encoding UTF8
}

function Invoke-GitInRepo {
    param([string[]]$GitArgs)
    Push-Location $Base
    try {
        & git @GitArgs 2>&1
    } finally {
        Pop-Location
    }
}
