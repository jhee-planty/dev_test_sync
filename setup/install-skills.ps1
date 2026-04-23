# install-skills.ps1 — Test PC ~/.claude/skills/ junction installer
#
# Creates junctions from %USERPROFILE%\.claude\skills\<skill> →
#                        <dev_test_sync>\shared-skills\<skill>
#
# Re-runnable: safely removes existing junction OR plain directory before
#              re-creating the junction.
#
# Why junctions:
#   - Works without admin / Developer Mode (Windows 11 default)
#   - NTFS-native, rock-solid
#   - `git pull` in dev_test_sync instantly reflects in ~/.claude/skills/
#   - No ongoing sync script to maintain or forget
#
# Usage (from dev_test_sync/setup/):
#   powershell -ExecutionPolicy Bypass -File .\install-skills.ps1
#
# Source of truth: dev_test_sync/shared-skills/<skill>/

$ErrorActionPreference = "Stop"

# Locate paths
$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$DevTestSync = (Resolve-Path (Join-Path $ScriptDir "..")).Path
$SharedSkills = Join-Path $DevTestSync "shared-skills"
$ClaudeSkills = Join-Path $env:USERPROFILE ".claude\skills"

Write-Host "=== install-skills.ps1 — junction setup ==="
Write-Host "Source: $SharedSkills"
Write-Host "Target: $ClaudeSkills"
Write-Host ""

# Sanity check source
if (-not (Test-Path $SharedSkills)) {
    Write-Error "ERROR: shared-skills not found at $SharedSkills"
    exit 1
}

# Ensure target parent exists
if (-not (Test-Path $ClaudeSkills)) {
    Write-Host "Creating $ClaudeSkills"
    New-Item -ItemType Directory -Path $ClaudeSkills -Force | Out-Null
}

# Counters
$installed = 0
$replaced  = 0
$skipped   = 0
$failed    = 0
$details   = @()

# Iterate all skill directories in shared-skills/
Get-ChildItem -Path $SharedSkills -Directory | ForEach-Object {
    $skill    = $_.Name
    $src      = $_.FullName
    $dst      = Join-Path $ClaudeSkills $skill
    $skillmd  = Join-Path $src "SKILL.md"

    # Skip directories without SKILL.md (not a skill)
    if (-not (Test-Path $skillmd)) {
        Write-Host "SKIP: $skill (no SKILL.md)"
        $details += [PSCustomObject]@{ Name = $skill; Action = "SKIP"; Reason = "no SKILL.md" }
        $skipped++
        return
    }

    $existed = Test-Path $dst
    $wasJunction = $false

    if ($existed) {
        $item = Get-Item $dst -Force
        if ($item.LinkType -eq "Junction") {
            $wasJunction = $true
            # Unlink the junction only (does NOT follow to source)
            cmd /c rmdir "$dst" 2>&1 | Out-Null
        } else {
            # Plain directory — recursive remove
            try {
                Remove-Item -Path $dst -Recurse -Force
            } catch {
                Write-Host ("FAIL: {0} (cannot remove existing plain dir: {1})" -f $skill, $_)
                $details += [PSCustomObject]@{ Name = $skill; Action = "FAIL"; Reason = "cannot remove plain dir" }
                $failed++
                return
            }
        }
    }

    # Create junction
    $mklinkOut = cmd /c mklink /J "$dst" "$src" 2>&1

    if ((Test-Path $dst) -and ((Get-Item $dst -Force).LinkType -eq "Junction")) {
        if ($existed) {
            if ($wasJunction) {
                Write-Host "OK (re-junction): $skill"
                $action = "RE-JUNCTION"
            } else {
                Write-Host "OK (plain→junction): $skill"
                $action = "REPLACED"
            }
            $replaced++
        } else {
            Write-Host "OK (new junction): $skill"
            $action = "NEW"
        }
        $installed++
        $details += [PSCustomObject]@{ Name = $skill; Action = $action; Reason = "" }
    } else {
        Write-Host ("FAIL: {0} ({1})" -f $skill, $mklinkOut)
        $details += [PSCustomObject]@{ Name = $skill; Action = "FAIL"; Reason = "mklink failed" }
        $failed++
    }
}

# Summary
Write-Host ""
Write-Host "=== Summary ==="
Write-Host ("Installed:  {0} junctions" -f $installed)
Write-Host ("  - Replaced plain dirs: {0}" -f $replaced)
Write-Host ("Skipped:    {0} (no SKILL.md)" -f $skipped)
Write-Host ("Failed:     {0}" -f $failed)
Write-Host ""

# Verification
Write-Host "=== Verification (LinkType per entry) ==="
Get-ChildItem -Path $ClaudeSkills | Select-Object Name, LinkType, Target | Format-Table -AutoSize

Write-Host ""
if ($failed -gt 0) {
    Write-Host "Install completed with FAILURES. See above."
    exit 1
} else {
    Write-Host "Install OK. After this, ``git pull`` in dev_test_sync keeps ~/.claude/skills live."
    exit 0
}
