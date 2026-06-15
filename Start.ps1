$ErrorActionPreference = "Stop"
$runDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $runDir

# Fallback original directory (backup for missing files)
$origDir = "C:\Users\MaleK\OneDrive\سطح المكتب\New folder 2(2)"

# Files that should be in this folder
$neededFiles = @(
    "menu.ps1", "InstallROKAuto.ps1", "accounts.txt",
    "KingdomCo.Engine.dll", "key.bin", "version.dll"
)

# Check and copy missing files from original dir
$missing = $false
foreach ($f in $neededFiles) {
    $fp = Join-Path $runDir $f
    if (-not (Test-Path $fp)) {
        $src = Join-Path $origDir $f
        if (Test-Path $src) {
            Copy-Item $src $fp -Force
            Write-Host "  Restored: $f" -ForegroundColor Green
            $missing = $true
        } else {
            Write-Host "  MISSING: $f (not found in backup)" -ForegroundColor Red
        }
    }
}

# Run menu
$menuScript = Join-Path $runDir "menu.ps1"
if (Test-Path $menuScript) {
    & $menuScript
} else {
    Write-Host "menu.ps1 not found!" -ForegroundColor Red
    Read-Host "Press ENTER"
}