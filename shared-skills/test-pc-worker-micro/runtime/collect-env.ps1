# collect-env.ps1 -OutJson <path>
# - Collects test PC environment snapshot: OS, Chrome version, network state, disk, etap proxy hint
# - Deterministic portion of report-status command

param(
    [Parameter(Mandatory=$true)][string]$OutJson
)

function Get-ChromeVersion {
    $paths = @(
        "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
    )
    foreach ($p in $paths) {
        if (Test-Path $p) {
            return (Get-Item $p).VersionInfo.FileVersion
        }
    }
    return ''
}

$net = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
       Where-Object { $_.InterfaceAlias -notlike '*Loopback*' -and $_.IPAddress -ne '127.0.0.1' } |
       Select-Object IPAddress, InterfaceAlias

$disk = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
        Select-Object Name, @{N='UsedGB';E={[int]($_.Used/1GB)}}, @{N='FreeGB';E={[int]($_.Free/1GB)}}

$result = [ordered]@{
    collected_at = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    os = [System.Environment]::OSVersion.VersionString
    chrome_version = (Get-ChromeVersion)
    user = $env:USERNAME
    computer = $env:COMPUTERNAME
    network = $net
    disk = $disk
    etap_proxy_hint = (Test-Connection -ComputerName '218.232.120.58' -Count 1 -Quiet -ErrorAction SilentlyContinue)
}

$parent = Split-Path -Parent $OutJson
if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
$result | ConvertTo-Json -Depth 5 | Set-Content -Path $OutJson -Encoding UTF8

Write-Host "[collect-env] wrote $OutJson"
exit 0
