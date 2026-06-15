$ErrorActionPreference = "Continue"
$adminDir = "C:\Program Files\KINGDOM CO MEmu Auto Installer RoK"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$updateRepoUrl = "https://github.com/MaleK11-glitch/KINGDOM-CO-MEmu-Auto-Installer-RoK-UPDATE.git"
$dllPath = Join-Path $adminDir "KingdomCo.Engine.dll"

Write-Host ""
Write-Host "  +--------------------------------------------+" -ForegroundColor Yellow
Write-Host "  |       Manual Update - by Developer         |" -ForegroundColor Yellow
Write-Host "  +--------------------------------------------+" -ForegroundColor Yellow
Write-Host ""

# === Phase 1: Extract all files from DLL ===
Write-Host ""
Write-Host "  >> Loading KingdomCo.Engine.dll..." -ForegroundColor Cyan
if (-not (Test-Path $dllPath)) {
    Write-Host "  [ERROR] DLL not found: $dllPath" -ForegroundColor Red
    exit
}
try {
    [System.Reflection.Assembly]::Load([System.IO.File]::ReadAllBytes($dllPath)) | Out-Null
} catch {
    Write-Host "  [ERROR] Cannot load DLL: $_" -ForegroundColor Red
    exit
}
try {
    $passphrase = [KingdomCo.Engine.Engine]::GetPassphrase()
    Write-Host "  [OK] Passphrase retrieved" -ForegroundColor Green
} catch {
    Write-Host "  [ERROR] Cannot get passphrase: $_" -ForegroundColor Red
    exit
}

$extractDir = Join-Path $env:TEMP "kr_manual_build"
if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
try {
    [KingdomCo.Engine.Engine]::ExtractAll($passphrase, $extractDir)
    Write-Host "  [OK] Extracted to: $extractDir" -ForegroundColor Green
} catch {
    Write-Host "  [ERROR] Extraction failed: $_" -ForegroundColor Red
    exit
}

# === Phase 2: Show files and select ===
$files = Get-ChildItem $extractDir -File

Write-Host ""
Write-Host "  Files inside KingdomCo.Engine.dll:" -ForegroundColor Cyan
for ($i = 0; $i -lt $files.Count; $i++) {
    Write-Host "  [$($i+1)] $($files[$i].Name) ($($files[$i].Length) bytes)" -ForegroundColor DarkGray
}

$selectedFiles = @()
Write-Host ""
Write-Host "  Enter file numbers to update on GitHub (e.g. 1,3,5 or A for all):" -ForegroundColor Cyan
Write-Host "  [A] All files" -ForegroundColor Green
Write-Host ""
$choice = Read-Host "  Numbers"
if ($choice -eq 'A' -or $choice -eq 'a') {
    $selectedFiles = $files
} else {
    $indices = $choice -split '[, ]+' | Where-Object { $_ -match '^\d+$' -and [int]$_ -ge 1 -and [int]$_ -le $files.Count }
    if ($indices.Count -eq 0) {
        Write-Host "  [ERROR] No valid numbers entered!" -ForegroundColor Red
        exit
    }
    foreach ($idx in $indices) {
        $selectedFiles += $files[[int]$idx - 1]
    }
}

# Auto-include version.txt
$hasVersion = $false
foreach ($f in $selectedFiles) { if ($f.Name -eq "version.txt") { $hasVersion = $true; break } }
if (-not $hasVersion) {
    $vf = Get-ChildItem $extractDir -Filter "version.txt" -File | Select-Object -First 1
    if ($vf) { $selectedFiles += $vf }
}

Write-Host ""
Write-Host "  Selected files for GitHub:" -ForegroundColor Cyan
foreach ($f in $selectedFiles) {
    Write-Host "    [$($f.Name)]" -ForegroundColor Green
}

Write-Host ""
$version = Read-Host "  Enter new version number (e.g. 2.10.6)"
if ([string]::IsNullOrWhiteSpace($version)) {
    Write-Host "  [ERROR] Version cannot be empty!" -ForegroundColor Red
    exit
}

$newVersion = $version

# Write new version to extracted version.txt (used for DLL rebuild)
$extractedVersionFile = Join-Path $extractDir "version.txt"
$newVersion | Out-File $extractedVersionFile -Encoding ASCII -NoNewline
Write-Host "  version.txt -> $newVersion" -ForegroundColor Green

# === Phase 3: Push to GitHub ===
Write-Host ""
Write-Host "  Publishing v$newVersion..." -ForegroundColor Yellow

$updateDir = Join-Path $env:TEMP "rok_publish_update"
if (Test-Path $updateDir) { Remove-Item $updateDir -Recurse -Force }

Write-Host ""
Write-Host "  >> Cloning UPDATE repo..." -ForegroundColor Cyan
& git clone $updateRepoUrl $updateDir 2>&1 | ForEach-Object { 
    if ($_ -is [System.Management.Automation.ErrorRecord]) {
        Write-Host "    $($_.Exception.Message)" -ForegroundColor Yellow
    } else { Write-Host "    $_" -ForegroundColor Yellow }
}
if ($LASTEXITCODE -ne 0) {
    Write-Host "  [ERROR] git clone failed!" -ForegroundColor Red
    exit
}

Write-Host ""
Write-Host "  >> Copying files to update repo..." -ForegroundColor Cyan
foreach ($f in $selectedFiles) {
    $dest = Join-Path $updateDir $f.Name
    $parent = Split-Path $dest -Parent
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    Copy-Item $f.FullName $dest -Force
    Write-Host "    $($f.Name) -> OK" -ForegroundColor Green
}

# Write version.txt to clone
$versionFile = Join-Path $updateDir "version.txt"
$newVersion | Out-File $versionFile -Encoding ASCII -NoNewline
Write-Host "  version.txt -> $newVersion" -ForegroundColor Green

Write-Host ""
Write-Host "  >> Staging and committing..." -ForegroundColor Cyan
Push-Location $updateDir
& git add -A 2>&1 | ForEach-Object { 
    if ($_ -is [System.Management.Automation.ErrorRecord]) {
        Write-Host "    $($_.Exception.Message)" -ForegroundColor Yellow
    } else { Write-Host "    $_" -ForegroundColor Yellow }
}

$commitMsg = "v$newVersion - manual update"
Write-Host ""
Write-Host "  Commit message: $commitMsg" -ForegroundColor Cyan

$confirmPush = Read-Host "  Push to GitHub? (Y/N)"
if ($confirmPush -in @('Y','y')) {
    try {
        & git commit -m $commitMsg 2>&1 | ForEach-Object { 
            if ($_ -is [System.Management.Automation.ErrorRecord]) {
                Write-Host "    $($_.Exception.Message)" -ForegroundColor Green
            } else { Write-Host "    $_" -ForegroundColor Green }
        }
        & git push origin main 2>&1 | ForEach-Object { 
            if ($_ -is [System.Management.Automation.ErrorRecord]) {
                Write-Host "    $($_.Exception.Message)" -ForegroundColor Green
            } else { Write-Host "    $_" -ForegroundColor Green }
        }
        Write-Host ""
        Write-Host "  +--------------------------------------------+" -ForegroundColor Green
        Write-Host "  |  PUBLISHED: v$newVersion" -ForegroundColor Green
        Write-Host "  |   $($selectedFiles.Count) files uploaded to GitHub" -ForegroundColor Green
        Write-Host "  +--------------------------------------------+" -ForegroundColor Green
    } catch {
        Write-Host "  [ERROR] git commit/push failed: $_" -ForegroundColor Red
    }
} else {
    Write-Host "  Committed locally but not pushed." -ForegroundColor Yellow
}
Pop-Location

# Clean up clone dir
Remove-Item $updateDir -Recurse -Force

# === Phase 4: Rebuild DLL ===
Write-Host ""
Write-Host "  >> Rebuilding KingdomCo.Engine.dll..." -ForegroundColor Yellow

$buildOutDir = Join-Path $env:TEMP "kr_dll_output"
if (Test-Path $buildOutDir) { Remove-Item $buildOutDir -Recurse -Force }
New-Item -ItemType Directory -Path $buildOutDir -Force | Out-Null

try {
    & powershell -ExecutionPolicy Bypass -NoProfile -File "$extractDir\Build-Engine.ps1" -OutputDir $buildOutDir
    if ($LASTEXITCODE -eq 0) {
        $newDll = Join-Path $buildOutDir "KingdomCo.Engine.dll"
        if (Test-Path $newDll) {
            Copy-Item $newDll $dllPath -Force
            Write-Host ""
            Write-Host "  +--------------------------------------------+" -ForegroundColor Green
            Write-Host "  |  DLL REBUILT + DEPLOYED                    |" -ForegroundColor Green
            Write-Host "  |  v$newVersion" -ForegroundColor Green
            Write-Host "  +--------------------------------------------+" -ForegroundColor Green
        } else {
            Write-Host "  [ERROR] Build output not found!" -ForegroundColor Red
        }
    } else {
        Write-Host "  [ERROR] DLL build failed!" -ForegroundColor Red
    }
} catch {
    Write-Host "  [ERROR] Build error: $_" -ForegroundColor Red
}

# Clean up
Remove-Item $extractDir -Recurse -Force
Remove-Item $buildOutDir -Recurse -Force

Write-Host ""
Write-Host "  Complete." -ForegroundColor Green
Write-Host ""
Write-Host "  Press Enter to exit..."
Read-Host
