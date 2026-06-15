$ErrorActionPreference = "Stop"
$adminDir = "C:\Program Files\Admin"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$updateRepoUrl = "https://github.com/MaleK11-glitch/KINGDOM-CO-MEmu-Auto-Installer-RoK-UPDATE.git"

Write-Host ""
Write-Host "  +--------------------------------------------+" -ForegroundColor Yellow
Write-Host "  |         Manual Update Publisher              |" -ForegroundColor Yellow
Write-Host "  +--------------------------------------------+" -ForegroundColor Yellow
Write-Host ""

$files = @()
if (Test-Path $adminDir) {
    $files += Get-ChildItem $adminDir -Recurse -File
}

if ($files.Count -eq 0) {
    Write-Host "  [WARN] No files in $adminDir, using files from current directory." -ForegroundColor Yellow
    $files += Get-ChildItem $scriptDir -Filter "*.txt" -Recurse -File
    $files += Get-ChildItem $scriptDir -Filter "*.py" -Recurse -File
    try {
        $files += Get-ChildItem (Join-Path $scriptDir "ref_images") -Recurse -File -ErrorAction SilentlyContinue
    } catch {}
}

$newVersion = "2.10.4"
Write-Host ""
Write-Host "  Files to upload:" -ForegroundColor Cyan
foreach ($f in $files) {
    $rel = ""
    try {
        $rel = $f.FullName.Substring($adminDir.Length + 1)
    } catch {
        $rel = $f.Name
    }
    Write-Host "    $rel ($($f.Length) bytes)" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "  Publishing v$newVersion with $($files.Count) files..." -ForegroundColor Green

$updateDir = Join-Path $env:TEMP "rok_publish_update"
Write-Host ""
Write-Host "  >> Cloning UPDATE repo..." -ForegroundColor Cyan
if (Test-Path $updateDir) { Remove-Item $updateDir -Recurse -Force }
try {
    git clone $updateRepoUrl $updateDir 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
} catch {
    Write-Host "  [ERROR] Failed to clone UPDATE repo: $_" -ForegroundColor Red
    Write-Host "  Manual updates may require git authentication." -ForegroundColor Yellow
    exit
}

Write-Host ""
Write-Host "  >> Copying files from Admin..." -ForegroundColor Cyan
foreach ($f in $files) {
    $rel = ""
    try {
        $rel = $f.FullName.Substring($adminDir.Length + 1)
    } catch {
        $rel = $f.Name
    }
    $dest = Join-Path $updateDir $rel
    $parent = Split-Path $dest -Parent
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    Copy-Item $f.FullName $dest -Force
    Write-Host "    $rel -> OK" -ForegroundColor Green
}

$versionFile = Join-Path $updateDir "version.txt"
$newVersion | Out-File $versionFile -Encoding ASCII -NoNewline
Write-Host "  version.txt -> $newVersion" -ForegroundColor Green

Write-Host ""
Write-Host "  >> Staging and committing..." -ForegroundColor Cyan
Set-Location $updateDir
git add -A 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
$commitMsg = "v$newVersion - manual update"
Write-Host "  Commit message: $commitMsg" -ForegroundColor Cyan
try {
    git commit -m $commitMsg 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
    git push origin main 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
    Write-Host ""
    Write-Host "  +--------------------------------------------+" -ForegroundColor Green
    Write-Host "  |  PUBLISHED: v$newVersion" -ForegroundColor Green
    Write-Host "  |   $($files.Count) files uploaded to GitHub" -ForegroundColor Green
    Write-Host "  +--------------------------------------------+" -ForegroundColor Green
} catch {
    Write-Host "  [ERROR] git commit/push failed: $_" -ForegroundColor Red
}

Remove-Item $updateDir -Recurse -Force
Write-Host ""
Write-Host "  Complete." -ForegroundColor Green