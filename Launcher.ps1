[System.Threading.Thread]::CurrentThread.CurrentUICulture = [System.Globalization.CultureInfo]::InvariantCulture
[System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::InvariantCulture
$ErrorActionPreference = "Stop"

# Branding
Write-Host "`n`n"
Write-Host "  K K III N N GGG DDD OOO M M" -Fore Yellow
Write-Host "  K K I NN N G G D D O O MM MM" -Fore Yellow
Write-Host "  KKK I N N G G D D O O M M" -Fore Yellow
Write-Host "  K K I N NN G GG D D O O M M" -Fore Yellow
Write-Host "  K K III N N GGG DDD OOO M M" -Fore Yellow
Write-Host "`n"
Write-Host "    CCC OOO" -Fore Cyan
Write-Host "    C O O" -Fore Cyan
Write-Host "    C O O" -Fore Cyan
Write-Host "    C O O" -Fore Cyan
Write-Host "    CCC OOO" -Fore Cyan
Write-Host "`n"
Write-Host "    KINGDOM & CO" -Fore White
Write-Host "    MEmu Auto Installer v2.10.4" -Fore Green
Write-Host "    Multi-Emulator Batch Support" -Fore Green
Write-Host "`n" + ("-" * 50) + "`n"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:Passphrase = $global:KR_PASSPHRASE
$script:DllPath = Join-Path $scriptDir "KingdomCo.Engine.dll"

# ============================================================
# MEmu Detection & Installation (from UpdateFiles.ps1)
# ============================================================
function Find-MEmu {
    $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { (Test-Path ($_.Root + "Program Files")) -or (Test-Path ($_.Root + "Program Files (x86)")) }
    foreach ($drive in $drives) {
        $root = $drive.Root
        $paths = @(
            "$root\Program Files\Microvirt\MEmu\MEmu.exe",
            "$root\Program Files (x86)\Microvirt\MEmu\MEmu.exe",
            "$root\Program Files\Microvirt\MEmuHyperv\MEmuHyperv.exe",
            "$root\Program Files (x86)\Microvirt\MEmuHyperv\MEmuHyperv.exe"
        )
        foreach ($p in $paths) {
            if (Test-Path $p) { return (Get-Item $p).Directory.FullName }
        }
    }
    try {
        $key = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match "MEmu|Microvirt" } | Select-Object -First 1
        if ($key -and $key.InstallLocation -and (Test-Path $key.InstallLocation)) { return $key.InstallLocation }
        $key = Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match "MEmu|Microvirt" } | Select-Object -First 1
        if ($key -and $key.InstallLocation -and (Test-Path $key.InstallLocation)) { return $key.InstallLocation }
    } catch {}
    return $null
}

function Ensure-MEmuLink {
    param([string]$memuPath)
    $cMEmu = "C:\Program Files\Microvirt\MEmu"
    if ($memuPath -ne $cMEmu) {
        $cParent = "C:\Program Files\Microvirt"
        if (Test-Path $cMEmu) { Remove-Item -LiteralPath $cMEmu -Recurse -Force -ErrorAction SilentlyContinue }
        if (-not (Test-Path $cParent)) { New-Item -ItemType Directory -Path $cParent -Force -ErrorAction SilentlyContinue | Out-Null }
        if (Test-Path $cParent) {
            cmd /c mklink /D "$cMEmu" "$memuPath" | Out-Null
            if (Test-Path "$cMEmu\memuc.exe") { Write-Host "  [OK] Symlink: C: -> $memuPath" -ForegroundColor Cyan }
        }
    }
}

$memuPath = Find-MEmu
if ($memuPath) {
    Write-Host "  [OK] MEmu: $memuPath" -ForegroundColor Green
    $env:MEMU_PATH = $memuPath
    Ensure-MEmuLink $memuPath
} else {
    Write-Host "  MEmu not found." -ForegroundColor Yellow
    Write-Host "  Available drives:" -ForegroundColor Cyan
    $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match '^[A-Z]:\\$' } | ForEach-Object { $_.Root[0] }
    $i = 1; $driveList = @()
    foreach ($d in $drives) { Write-Host "  $i. Drive $d" -ForegroundColor White; $driveList += $d; $i++ }
    $choice = Read-Host "  Choose drive"
    $selectedDrive = $null; $parsed = 0
    if ([int]::TryParse($choice, [ref]$parsed)) { if ($parsed -ge 1 -and $parsed -le $driveList.Count) { $selectedDrive = $driveList[$parsed - 1] } }
    else { $upper = $choice.ToUpper().Trim(); if ($upper -match '^[A-Z]$' -and $driveList -contains $upper) { $selectedDrive = $upper } }
    if (-not $selectedDrive) { $selectedDrive = "C" }
    $installPath = "${selectedDrive}:\Program Files\Microvirt\MEmu"
    $installerUrl = "https://dl.memuplay.net/download/MEmu-setup-abroad-643b34e8.exe"
    $installerPath = Join-Path $env:TEMP "MEmu_Installer.exe"
    Write-Host "  Downloading MEmu..." -ForegroundColor Yellow
    try {
        $req = [System.Net.HttpWebRequest]::Create($installerUrl)
        $req.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
        $req.Timeout = 300000
        $resp = $req.GetResponse()
        $totalBytes = $resp.ContentLength
        $respStream = $resp.GetResponseStream()
        $fs = [System.IO.File]::Create($installerPath)
        $buffer = New-Object byte[] 8192; $read = 0; $downloaded = 0; $pct = 0
        while (($read = $respStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $fs.Write($buffer, 0, $read); $downloaded += $read
            $newPct = [math]::Round(($downloaded / $totalBytes) * 100)
            if ($newPct -ne $pct) { $pct = $newPct; $rec = [math]::Round($downloaded / 1MB, 1); $tot = [math]::Round($totalBytes / 1MB, 1); Write-Progress -Activity "Downloading MEmu" -Status "$rec MB / $tot MB ($pct%)" -PercentComplete $pct }
        }
        $respStream.Close(); $fs.Close(); $resp.Close()
        Write-Progress -Activity "Downloading MEmu" -Completed
        Write-Host "  [OK] Downloaded." -ForegroundColor Green
        Write-Host "  Installing..." -ForegroundColor Yellow
        $proc = Start-Process -FilePath $installerPath -ArgumentList "/D=$installPath" -PassThru
        $proc.WaitForExit(600000)
        Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
        $memuPath = Find-MEmu
        if ($memuPath) { Write-Host "  [OK] MEmu installed." -ForegroundColor Green; $env:MEMU_PATH = $memuPath; Ensure-MEmuLink $memuPath }
        else { Write-Host "  [XX] MEmu install failed." -ForegroundColor Red }
    } catch { Write-Host "  [XX] MEmu install error: $($_.Exception.Message)" -ForegroundColor Red }
}

# ============================================================
# DLL Engine Initialization & Extraction
# ============================================================
$script:EngineDir = $scriptDir

# ============================================================
# Run main menu
# ============================================================
$menuScript = Join-Path $script:EngineDir "menu.ps1"
if (-not (Test-Path $menuScript)) { $menuScript = Join-Path $scriptDir "menu.ps1" }
if (Test-Path $menuScript) {
    . $menuScript
} else {
    Write-Host "menu.ps1 not found!" -ForegroundColor Red
    Read-Host "Press ENTER"
}
