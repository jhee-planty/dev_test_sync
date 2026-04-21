# state-update.ps1 -Field <name> -Value <value> [-Base <path>]

param(
    [Parameter(Mandatory=$true)][string]$Field,
    [Parameter(Mandatory=$true)]$Value,
    [string]$Base = ''
)

. (Join-Path $PSScriptRoot 'common.ps1')

# Convert numeric strings to int for known numeric fields
if ($Field -in @('last_processed_id','last_delivered_id')) {
    $Value = [int]$Value
}

Set-StateField -Field $Field -Value $Value
Write-TpwLog "state.json: $Field = $Value"
