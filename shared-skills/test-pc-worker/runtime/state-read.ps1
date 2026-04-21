# state-read.ps1 [-Field <name>] [-Base <path>]
# Without -Field: prints full state.json
# With -Field: prints single field value

param(
    [string]$Field = '',
    [string]$Base = ''
)

. (Join-Path $PSScriptRoot 'common.ps1')

Initialize-State

if ($Field) {
    $state = Get-State
    $state.$Field
} else {
    Get-Content $script:StateJson -Raw
}
