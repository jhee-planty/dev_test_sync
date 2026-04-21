# chrome-capture.ps1 -Url <url> -OutPath <png-path> [-WaitSec <n>]
# - Opens Chrome to URL, captures screenshot of primary monitor after wait
# - Deterministic portion of capture-screenshot command

param(
    [Parameter(Mandatory=$true)][string]$Url,
    [Parameter(Mandatory=$true)][string]$OutPath,
    [int]$WaitSec = 5
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$chrome = "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe"
if (-not (Test-Path $chrome)) {
    $chrome = "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
}
if (-not (Test-Path $chrome)) {
    Write-Error "Chrome not found"
    exit 2
}

# Launch (non-blocking)
Start-Process -FilePath $chrome -ArgumentList "--new-window", $Url
Start-Sleep -Seconds $WaitSec

# Capture primary screen
$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
$gfx = [System.Drawing.Graphics]::FromImage($bmp)
$gfx.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)

# Ensure parent dir
$parent = Split-Path -Parent $OutPath
if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }

$bmp.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
$gfx.Dispose()
$bmp.Dispose()

Write-Host "[chrome-capture] saved: $OutPath"
exit 0
