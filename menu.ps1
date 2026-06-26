$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$accFile = Join-Path $scriptDir "accounts.txt"
$mainScript = Join-Path $scriptDir "InstallROKAuto.ps1"
$imapScript = Join-Path $scriptDir "fetch_code_imap.py"

function Read-Choice($prompt, $default, $valid) {
    while ($true) {
        $input = Read-Host $prompt
        if ([string]::IsNullOrWhiteSpace($input)) { if ($default) { return $default } else { continue } }
        if ($input -in $valid) { return $input }
    }
}

function Load-Accounts {
    if (-not (Test-Path $accFile)) { return @() }
    $result = @()
    Get-Content $accFile | ForEach-Object {
        $line = $_.Trim()
        if ([string]::IsNullOrWhiteSpace($line)) { return }
        try {
            $decoded = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($line))
            $parts = $decoded -split ':', 2
            if ($parts.Count -eq 2) {
                $email = $parts[0]; $pass = $parts[1]
                $at = $email.IndexOf('@')
                if ($at -gt 2) { $masked = $email[0] + ('*' * ($at - 2)) + $email[$at - 1] + $email.Substring($at) }
                else { $masked = $email }
                $result += [PSCustomObject]@{ Email = $email; Pass = $pass; Masked = $masked }
            }
        } catch {}
    }
    return $result
}

function Show-PasswordHelp($email) {
    if ($email -match '@gmail\.') {
        Write-Host "  Gmail: App password at https://myaccount.google.com/apppasswords" -ForegroundColor DarkGray
    } elseif ($email -match '@hotmail\.|@outlook\.|@live\.') {
        Write-Host "  Hotmail: Enable IMAP at https://outlook.live.com/mail/0/options/mail/accounts/popAndImap" -ForegroundColor DarkGray
        Write-Host "  App password: https://account.live.com/apppasswords" -ForegroundColor DarkGray
    } elseif ($email -match '@yahoo\.') {
        Write-Host "  Yahoo: App password at https://login.yahoo.com/account/security" -ForegroundColor DarkGray
    }
}

function Add-Account {
    Write-Host ""; $newEmail = Read-Host "Email"
    if ([string]::IsNullOrWhiteSpace($newEmail)) { return }
    Show-PasswordHelp $newEmail
    $newPass = Read-Host "Password"
    if ([string]::IsNullOrWhiteSpace($newPass)) { return }
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$newEmail`:$newPass"))
    $encoded | Out-File $accFile -Append -Encoding ASCII
    Write-Host "Account added!" -ForegroundColor Green; Start-Sleep 1
}

function Show-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "    +==============================================+" -ForegroundColor DarkYellow
    Write-Host "    |                                              |" -ForegroundColor DarkYellow
    Write-Host "    |   K   K  III  N   N  GGG   DDD   OOO   M   M |" -ForegroundColor Yellow
    Write-Host "    |   K  K    I   NN  N G   G  D  D O   O MM MM  |" -ForegroundColor Yellow
    Write-Host "    |   KKK     I   N N N G      D  D O   O M M M  |" -ForegroundColor Yellow
    Write-Host "    |   K  K    I   N  NN G  GG  D  D O   O M   M  |" -ForegroundColor Yellow
    Write-Host "    |   K   K  III  N   N  GGG   DDD   OOO   M   M |" -ForegroundColor Yellow
    Write-Host "    |                                              |" -ForegroundColor DarkYellow
    Write-Host "    |          CCC   OOO                           |" -ForegroundColor Cyan
    Write-Host "    |         C    O   O                           |" -ForegroundColor Cyan
    Write-Host "    |         C    O   O                           |" -ForegroundColor Cyan
    Write-Host "    |         C    O   O                           |" -ForegroundColor Cyan
    Write-Host "    |          CCC   OOO                           |" -ForegroundColor Cyan
    Write-Host "    |                                              |" -ForegroundColor DarkYellow
    Write-Host "    |          KINGDOM & CO                        |" -ForegroundColor White
    Write-Host "    |       MEmu Auto Installer v2.10.4            |" -ForegroundColor Green
    Write-Host "    |     Multi-Emulator Batch Support             |" -ForegroundColor Green
    Write-Host "    |                                              |" -ForegroundColor DarkYellow
    Write-Host "    +==============================================+" -ForegroundColor DarkYellow
    Write-Host ""
}

function Show-StepHeader($step, $title) {
    Write-Host ""
    Write-Host "  +--------------------------------------------+" -ForegroundColor DarkYellow
    Write-Host "  |  Step $step : $title" -ForegroundColor Yellow
    Write-Host "  +--------------------------------------------+" -ForegroundColor DarkYellow
    Write-Host ""
}

function Show-Status($msg, $color) {
    $color = if ($color) { $color } else { "Cyan" }
    Write-Host "  >> $msg" -ForegroundColor $color
}

function Show-Done {
    Write-Host ""
    Write-Host "  +--------------------------------------------+" -ForegroundColor Green
    Write-Host "  |            COMPLETE!                        |" -ForegroundColor Green
    Write-Host "  +--------------------------------------------+" -ForegroundColor Green
    Write-Host ""
}

$GitHubOwner = "MaleK11-glitch"
$GitHubRepo = "KINGDOM-CO-MEmu-Auto-Installer-RoK-UPDATE"
$GitHubBranch = "main"
$GitHubBase = "https://raw.githubusercontent.com/$GitHubOwner/$GitHubRepo/$GitHubBranch"

# Encrypted version DLL settings
$VersionPassphrase = "K1ngd0m&C0_M3mu_Aut0!2026#Rok"
$VersionSalt = [Text.Encoding]::UTF8.GetBytes("RokSalt2026!")
$UpdateDir = Join-Path $env:LOCALAPPDATA "KINGDOM-CO_UPDATE"
$script:EngineDir = $null

function Initialize-Engine {
    $dllPath = Join-Path $UpdateDir "KingdomCo.Engine.dll"
    if (-not (Test-Path $dllPath)) {
        $script:EngineDir = $scriptDir; return $false
    }
    try {
        [Reflection.Assembly]::LoadFile($dllPath) | Out-Null
        $passphrase = [KingdomCo.Engine.Engine]::GetPassphrase()
        if (-not [KingdomCo.Engine.Engine]::VerifyPassphrase($passphrase)) { throw "Key mismatch" }
        $tempEngine = Join-Path $env:TEMP "rok_engine_$([DateTime]::Now.Ticks)"
        New-Item -ItemType Directory -Path $tempEngine -Force | Out-Null
        [KingdomCo.Engine.Engine]::ExtractAll($passphrase, $tempEngine)
        $script:EngineDir = $tempEngine
        return $true
    } catch {
        $script:EngineDir = $scriptDir; return $false
    }
}

function Get-VersionDll {
    $dllFile = Join-Path $UpdateDir "version.dll"
    if (-not (Test-Path $dllFile)) { return $null }
    try {
        $dllBytes = [IO.File]::ReadAllBytes($dllFile)
        if ($dllBytes.Length -le 16) { return $null }
        $keyGen = New-Object Security.Cryptography.Rfc2898DeriveBytes($VersionPassphrase, $VersionSalt, 10000, [Security.Cryptography.HashAlgorithmName]::SHA256)
        $aes = [Security.Cryptography.Aes]::Create()
        $aes.Key = $keyGen.GetBytes(32)
        $aes.IV = $dllBytes[0..15]
        $decryptor = $aes.CreateDecryptor()
        $cipher = $dllBytes[16..($dllBytes.Length - 1)]
        $plainText = $decryptor.TransformFinalBlock($cipher, 0, $cipher.Length)
        return [Text.Encoding]::UTF8.GetString($plainText).Trim()
    } catch { return $null }
}

function Write-VersionDll {
    param($Version)
    if (-not (Test-Path $UpdateDir)) { New-Item -ItemType Directory -Path $UpdateDir -Force | Out-Null }
    try {
        $keyGen = New-Object Security.Cryptography.Rfc2898DeriveBytes($VersionPassphrase, $VersionSalt, 10000, [Security.Cryptography.HashAlgorithmName]::SHA256)
        $aes = [Security.Cryptography.Aes]::Create()
        $aes.Key = $keyGen.GetBytes(32)
        $aes.GenerateIV()
        $encryptor = $aes.CreateEncryptor()
        $plainBytes = [Text.Encoding]::UTF8.GetBytes($Version)
        $cipherBytes = $encryptor.TransformFinalBlock($plainBytes, 0, $plainBytes.Length)
        $dllBytes = $aes.IV + $cipherBytes
        $dllFile = Join-Path $UpdateDir "version.dll"
        [IO.File]::WriteAllBytes($dllFile, $dllBytes)
        return $true
    } catch { return $false }
}

$UpdateFiles = @(
    "version.txt",
    "menu.ps1",
    "InstallROKAuto.ps1",
    "find_image.py",
    "check_alive.py",
    "fetch_code_imap.py"
)

$UpdateIgnoreFiles = @(
    "accounts.txt",
    "*.log",
    "*_VM*.txt"
)

function Get-LocalVersion {
    # Try encrypted DLL first
    $dllVer = Get-VersionDll
    if ($dllVer) { return $dllVer }
    # Fallback to version.txt
    $vFile = Join-Path $scriptDir "version.txt"
    if (Test-Path $vFile) {
        return (Get-Content $vFile -Raw).Trim()
    }
    return "0.0"
}

function Check-GitHubUpdate {
    param([switch]$Silent)

    if (-not $Silent) {
        Write-Host "  >> Checking for updates..." -ForegroundColor Cyan -NoNewline
    }

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $remoteVersion = (Invoke-WebRequest -Uri "$GitHubBase/version.txt" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop).Content.Trim()
        $localVersion = Get-LocalVersion

        if ($remoteVersion -ne $localVersion) {
            if (-not $Silent) { Write-Host "" }
            Write-Host ""
            Write-Host "  +--------------------------------------------+" -ForegroundColor Yellow
            Write-Host "  |  UPDATE AVAILABLE: $localVersion -> $remoteVersion" -ForegroundColor Yellow
            Write-Host "  +--------------------------------------------+" -ForegroundColor Yellow
            Write-Host ""
            return @{ Available = $true; RemoteVersion = $remoteVersion; LocalVersion = $localVersion }
        } else {
            if (-not $Silent) {
                Write-Host " OK (v$localVersion)" -ForegroundColor Green
            }
            return @{ Available = $false; RemoteVersion = $remoteVersion; LocalVersion = $localVersion }
        }
    } catch {
        if (-not $Silent) {
            Write-Host " SKIP (no connection)" -ForegroundColor DarkGray
        }
        return @{ Available = $false; Error = $_.Exception.Message }
    }
}

function Install-GitHubUpdate {
    param($RemoteVersion)

    Write-Host ""
    Write-Host "  Downloading update v$RemoteVersion from GitHub..." -ForegroundColor Cyan
    Write-Host ""

    $successCount = 0
    $failCount = 0
    $skipCount = 0

    foreach ($file in $UpdateFiles) {
        $url = "$GitHubBase/$file"
        $dest = Join-Path $scriptDir $file

        Write-Host "  [$file] " -ForegroundColor White -NoNewline

        try {
            $tempFile = Join-Path $env:TEMP "rok_update_$file"
            Invoke-WebRequest -Uri $url -OutFile $tempFile -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop

            $remoteSize = (Get-Item $tempFile).Length
            $localSize = 0
            if (Test-Path $dest) { $localSize = (Get-Item $dest).Length }

            if ($remoteSize -ne $localSize) {
                Copy-Item $tempFile $dest -Force
                Write-Host "UPDATED" -ForegroundColor Green
                $successCount++
            } else {
                Write-Host "OK (same size)" -ForegroundColor DarkGray
                $skipCount++
            }
        } catch {
            Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
            $failCount++
        }
    }

    # Update ref_images
    Write-Host ""
    Write-Host "  Updating ref_images/..." -ForegroundColor Cyan

    $refDir = Join-Path $scriptDir "ref_images"
    if (-not (Test-Path $refDir)) { New-Item -ItemType Directory -Path $refDir -Force | Out-Null }

    try {
        $apiUrl = "https://api.github.com/repos/$GitHubOwner/$GitHubRepo/contents/ref_images?ref=$GitHubBranch"
        $apiResponse = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop

        foreach ($item in $apiResponse) {
            if ($item.type -eq "file" -and $item.name -match "\.(png|jpg|jpeg)$") {
                $imgDest = Join-Path $refDir $item.name
                Write-Host "  [$($item.name)] " -ForegroundColor White -NoNewline

                try {
                    $tempImg = Join-Path $env:TEMP "rok_update_$($item.name)"
                    Invoke-WebRequest -Uri $item.download_url -OutFile $tempImg -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
                    Copy-Item $tempImg $imgDest -Force
                    Write-Host "OK" -ForegroundColor Green
                    $successCount++
                } catch {
                    Write-Host "FAILED" -ForegroundColor Red
                    $failCount++
                }
            }
        }
    } catch {
        Write-Host "  Could not list ref_images (API error)" -ForegroundColor Yellow
    }

    # Update version.txt
    $versionFile = Join-Path $scriptDir "version.txt"
    $RemoteVersion | Out-File $versionFile -Encoding ASCII -NoNewline

    # Update encrypted version DLL
    $dllOk = Write-VersionDll -Version $RemoteVersion
    if ($dllOk) { Write-Host "  [version.dll] ENCRYPTED" -ForegroundColor Green }
    else { Write-Host "  [version.dll] WARN: could not encrypt" -ForegroundColor Yellow }

    Write-Host ""
    Write-Host "  +--------------------------------------------+" -ForegroundColor Green
    Write-Host "  |  Updated: $successCount files" -ForegroundColor Green
    Write-Host "  |  Skipped: $skipCount | Failed: $failCount" -ForegroundColor Green
    Write-Host "  |  Version: $RemoteVersion" -ForegroundColor Green
    Write-Host "  +--------------------------------------------+" -ForegroundColor Green
    Write-Host ""
}

function Show-AccountsMenu($accounts, $vmLabel) {
    while ($true) {
        Show-Banner
        Show-StepHeader "" "Account selection: $vmLabel"
        if ($accounts.Count -eq 0) { Write-Host "  No accounts saved yet." -ForegroundColor Red; Write-Host "" }
        else { for ($i = 0; $i -lt $accounts.Count; $i++) { Write-Host ("  [{0}] {1}" -f ($i + 1), $accounts[$i].Masked) } }
        Write-Host ""; Write-Host "  [A] Add new account"; Write-Host "  [B] Back"; Write-Host ""
        $choice = Read-Host "Choose"
        if ($choice -eq 'A' -or $choice -eq 'a') { Add-Account; return "RELOAD" }
        if ($choice -eq 'B' -or $choice -eq 'b') { return "BACK" }
        $num = 0
        if ([int]::TryParse($choice, [ref]$num) -and $num -ge 1 -and $num -le $accounts.Count) { return $accounts[$num - 1] }
    }
}

function Get-SystemCapability {
    $cpuCores = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
    $ramBytes = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
    $ramGB = [math]::Round($ramBytes / 1GB)
    $maxByCPU = [math]::Max(1, [math]::Floor($cpuCores / 2))
    $maxByRAM = [math]::Max(1, [math]::Floor($ramGB / 2))
    $maxVMs = [math]::Min($maxByCPU, $maxByRAM)
    return @{ Cores = $cpuCores; RAM = $ramGB; MaxVMs = $maxVMs }
}

function Confirm-Quit {
    Write-Host ""; Read-Host "Press ENTER to continue"; exit
}

# ============================================================
# AUTO-UPDATE CHECK
# ============================================================
Show-Banner
$updateResult = Check-GitHubUpdate
if ($updateResult.Available) {
    Write-Host "  Apply update now? (Y/n) " -ForegroundColor Yellow -NoNewline
    $confirm = Read-Host
    if ($confirm -notin @('n','N','no')) {
        Install-GitHubUpdate -RemoteVersion $updateResult.RemoteVersion
        Write-Host "  Restarting..." -ForegroundColor Green
        Start-Sleep 2
        & $PSCommandPath
        exit
    }
    Write-Host "  Skipping update." -ForegroundColor DarkGray
    Start-Sleep 1
}

# ============================================================
# ENGINE INITIALIZATION
# ============================================================
Write-Host "  >> Initializing engine..." -ForegroundColor Cyan -NoNewline
$engineOk = Initialize-Engine
if ($engineOk) { Write-Host " OK" -ForegroundColor Green }
else { Write-Host " using local files" -ForegroundColor DarkGray }
# Main script runs from engine dir or current dir
$script:mainScript = Join-Path $scriptDir "InstallROKAuto.ps1"
if (-not (Test-Path $script:mainScript)) { $script:mainScript = Join-Path $script:EngineDir "InstallROKAuto.ps1" }
$script:imapScript = Join-Path $script:EngineDir "fetch_code_imap.py"
# Default OriginalDir: if no XAPK here, use desktop backup
$script:originalDir = $scriptDir
$xapkTest = Get-ChildItem $scriptDir -Filter "*.xapk" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $xapkTest) {
    $desktopBackup = "C:\Users\MaleK\OneDrive\سطح المكتب\New folder 2(2)"
    if (Test-Path $desktopBackup) { $script:originalDir = $desktopBackup }
}

# ============================================================
# STEP 0: MODE SELECTION
# ============================================================
$mode = "Login"
$startVM = 1

while ($true) {
    Show-Banner
    Show-StepHeader "0" "Select Mode"
    Write-Host "  [1] Install only (download game + update)" -ForegroundColor White
    Write-Host "  [2] Install + Login (download then register)" -ForegroundColor White
    Write-Host "  [3] Login only (already installed)" -ForegroundColor White
    Write-Host ""
    Write-Host "  [Q] Quit" -ForegroundColor DarkGray
    Write-Host ""
    $input = Read-Host "  Choice (1-3, Q) [3]"
    if ($input -in @('Q','q')) { exit }
    if ([string]::IsNullOrWhiteSpace($input) -or $input -eq "3") { $mode = "Login"; break }
    if ($input -eq "1") { $mode = "Install"; break }
    if ($input -eq "2") { $mode = "InstallLogin"; break }
}

# ============================================================
# STEP 1: VM COUNT
# ============================================================
$sysCap = Get-SystemCapability
$maxVM = 100
$vmCount = 1

while ($true) {
    Show-Banner
    Show-StepHeader "1" "VM Details"
    Write-Host "  System: $($sysCap.Cores) cores, $($sysCap.RAM) GB RAM" -ForegroundColor Cyan
    Write-Host "  Mode: " -ForegroundColor Cyan -NoNewline; Write-Host $mode -ForegroundColor Green
    Write-Host ""
    $input = Read-Host "  Total emulators? (1-$maxVM) [1]"
    if ([string]::IsNullOrWhiteSpace($input)) { break }
    if ($input -in @('B','b','Q','q')) { exit }
    if ([int]::TryParse($input, [ref]$vmCount) -and $vmCount -ge 1 -and $vmCount -le $maxVM) { break }
}
while ($true) {
    Write-Host ""
    $input = Read-Host "  Start from which emulator? (MEmu_1 to MEmu_$($maxVM - $vmCount + 1)) [1]"
    if ([string]::IsNullOrWhiteSpace($input)) { $startVM = 1; break }
    if ($input -in @('B','b','Q','q')) { exit }
    if ([int]::TryParse($input, [ref]$startVM) -and $startVM -ge 1 -and $startVM + $vmCount -le 101) { break }
}

# ============================================================
# STEP 2-3: ACCOUNT (only for login modes)
# ============================================================
$modeChoice = "1"
$masterEmail = ""
$masterPass = ""
$masterProvider = "gmail"
$accDomain = "gmail.com"
$accountsPerVM = @()
if ($mode -ne "Install") {

if ($vmCount -gt 1) {
    while ($true) {
        Show-Banner
        Show-StepHeader "2" "Account Mode"
        Write-Host "  [1] Same email on all VMs" -ForegroundColor White
        Write-Host "  [2] Different email per VM" -ForegroundColor White
        Write-Host "  [3] Alias Email / Plus addressing" -ForegroundColor Green
        Write-Host "       One master email, each VM uses email+1, email+2, etc." -ForegroundColor DarkGray
        Write-Host "       All codes arrive at the master inbox" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  [B] Back to step 1" -ForegroundColor DarkGray
        Write-Host ""
        $input = Read-Host "  Choice (1-3) [1]"

        # Handle Back
        if ($input -in @('B','b')) {
            Clear-Host; Write-Host "Restarting..." -ForegroundColor Yellow; Start-Sleep 1
            & $PSCommandPath; exit
        }
        if ([string]::IsNullOrWhiteSpace($input)) { $modeChoice = "1"; break }
        if ($input -in @('1','2','3')) { $modeChoice = $input; break }
    }
}

if ($modeChoice -eq "3") {
    while ($true) {
        Show-Banner
        Show-StepHeader "2a" "Alias Email Setup"
        Write-Host "  Master email receives all verification codes." -ForegroundColor Cyan
        Write-Host "  Each VM uses: master+1@domain, master+2@domain, etc." -ForegroundColor DarkGray
        Write-Host ""
        $masterEmail = Read-Host "  Master email"
        if ([string]::IsNullOrWhiteSpace($masterEmail)) { continue }
        if ($masterEmail -in @('B','b')) { $modeChoice = "1"; break }
        Show-PasswordHelp $masterEmail
        $masterPass = Read-Host "Password / App password"
        if ([string]::IsNullOrWhiteSpace($masterPass)) { continue }
        if ($masterEmail -match '@hotmail\.') { $masterProvider = "hotmail"; $accDomain = "hotmail.com" }
        elseif ($masterEmail -match '@outlook\.') { $masterProvider = "hotmail"; $accDomain = "outlook.com" }
        elseif ($masterEmail -match '@live\.') { $masterProvider = "hotmail"; $accDomain = "live.com" }
        else { $masterProvider = "gmail"; $accDomain = "gmail.com" }
        Write-Host "Detected provider: $masterProvider" -ForegroundColor Cyan
        Write-Host ""
        $ok = Read-Host "Confirm (Y/n)"
        if ($ok -ne 'n' -and $ok -ne 'N') { break }
    }
}

# ============================================================
# STEP 3: PICK / ADD ACCOUNTS (Mode 1 or 2 only)
# ============================================================
$accountsPerVM = @()

if ($modeChoice -eq "3") {
    $atIdx = $masterEmail.IndexOf('@')
    $prefix = $masterEmail.Substring(0, $atIdx)
    $domain = $masterEmail.Substring($atIdx)

    # Choose alias generation method
    $aliasMethod = "1"
    $customFirstAlias = ""
    while ($true) {
        Show-Banner
        Show-StepHeader "" "Alias Generation Method"
        Write-Host "  Master: $masterEmail" -ForegroundColor Cyan
        Write-Host "  VMs: $vmCount" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  [1] Auto-increment (1, 2, 3...)" -ForegroundColor Green
        Write-Host "      → ${prefix}+1${domain}, ${prefix}+2${domain}, ..."
        Write-Host ""
        Write-Host "  [2] Custom pattern" -ForegroundColor Green
        Write-Host "      You type the first alias (e.g. example+v5@hotmail.com)"
        Write-Host "      Script auto-increments: +v5, +v6, +v7..."
        Write-Host ""
        Write-Host "  [3] Manual per VM" -ForegroundColor Green
        Write-Host "      Generate defaults, then change any VM"
        Write-Host ""
        Write-Host "  [B] Back"
        Write-Host ""
        $input = Read-Host "Choice (1-3) [1]"
        if ($input -in @('B','b')) { $modeChoice = ""; & $PSCommandPath; exit }
        if ([string]::IsNullOrWhiteSpace($input) -or $input -eq "1") { $aliasMethod = "1"; break }
        if ($input -eq "2") {
            Write-Host ""
            $customFirstAlias = Read-Host "First alias email (e.g. example+v5@hotmail.com)"
            if ([string]::IsNullOrWhiteSpace($customFirstAlias)) { continue }
            if ($customFirstAlias -in @('B','b')) { continue }
            if ($customFirstAlias -notmatch '@') { Write-Host "Invalid email!" -ForegroundColor Red; Start-Sleep 2; continue }
            $aliasMethod = "2"; break
        }
        if ($input -eq "3") { $aliasMethod = "3"; break }
    }

    # Generate alias list
    $aliasList = @()
    if ($aliasMethod -eq "1") {
        for ($v = 1; $v -le $vmCount; $v++) {
            $aliasList += "${prefix}+${v}${domain}"
        }
    } elseif ($aliasMethod -eq "2") {
        # Parse the first alias to extract pattern
        $firstLocal = $customFirstAlias.Split('@')[0]
        $firstDomain = "@" + $customFirstAlias.Split('@')[1]
        # Find the last number in the local part
        if ($firstLocal -match '(\d+)$') {
            $startNum = [int]$Matches[1]
            $basePrefix = $firstLocal.Substring(0, $firstLocal.Length - $Matches[1].Length)
            for ($v = 1; $v -le $vmCount; $v++) {
                $aliasList += "${basePrefix}$($startNum + $v - 1)${firstDomain}"
            }
        } else {
            # No number found, fall back to method 1
            for ($v = 1; $v -le $vmCount; $v++) {
                $aliasList += "${prefix}+${v}${domain}"
            }
        }
    } else {
        # Method 3: generate defaults first
        for ($v = 1; $v -le $vmCount; $v++) {
            $aliasList += "${prefix}+${v}${domain}"
        }
    }

    # Method 3: allow manual overrides
    if ($aliasMethod -eq "3") {
        while ($true) {
            Show-Banner
            Show-StepHeader "" "Manual Alias Setup"
            for ($v = 0; $v -lt $vmCount; $v++) {
                Write-Host ("  [{0}] VM {1}: {2}" -f ($v + 1), ($v + 1), $aliasList[$v])
            }
            Write-Host ""
            Write-Host "  [1-$vmCount] Change VM email"
            Write-Host "  [C] Continue with current list"
            Write-Host "  [B] Back"
            Write-Host ""
            $input = Read-Host "Choice"
            if ($input -in @('C','c')) { break }
            if ($input -in @('B','b')) { $modeChoice = ""; & $PSCommandPath; exit }
            $num = 0
            if ([int]::TryParse($input, [ref]$num) -and $num -ge 1 -and $num -le $vmCount) {
                $newEmail = Read-Host ("New email for VM $num [$($aliasList[$num-1])]")
                if (-not [string]::IsNullOrWhiteSpace($newEmail)) {
                    $aliasList[$num - 1] = $newEmail
                }
            }
        }
    }

    # Create account objects
    for ($v = 0; $v -lt $vmCount; $v++) {
        $aliasEmail = $aliasList[$v]
        $at = $aliasEmail.IndexOf('@')
        if ($at -gt 2) { $masked = $aliasEmail[0] + ('*' * ($at - 2)) + $aliasEmail[$at - 1] + $aliasEmail.Substring($at) }
        else { $masked = $aliasEmail }
        $accountsPerVM += [PSCustomObject]@{
            Email = $aliasEmail
            Pass = $masterPass
            Masked = $masked
            MasterEmail = $masterEmail
            MasterPass = $masterPass
            Provider = $masterProvider
        }
    }
} else {
    $accounts = Load-Accounts

    if ($modeChoice -eq "1") {
        $selected = $null
        while ($null -eq $selected) {
            $result = Show-AccountsMenu $accounts "all VMs"
            if ($result -eq "RELOAD") { $accounts = Load-Accounts; continue }
            if ($result -eq "BACK") { Clear-Host; & $PSCommandPath; exit }
            $selected = $result
        }
        for ($v = 0; $v -lt $vmCount; $v++) { $accountsPerVM += $selected }
    } else {
        $available = $accounts
        for ($v = 1; $v -le $vmCount; $v++) {
            $selected = $null
            while ($null -eq $selected) {
                Show-Banner
                Show-StepHeader "" "Account for VM $v / $vmCount"
                if ($available.Count -eq 0) { Write-Host "  No accounts left." -ForegroundColor Red; Add-Account; $available = Load-Accounts; continue }
                for ($i = 0; $i -lt $available.Count; $i++) { Write-Host ("  [{0}] {1}" -f ($i + 1), $available[$i].Masked) }
                Write-Host ""; Write-Host "  [A] Add new account"; Write-Host "  [B] Back"; Write-Host ""
                $choice = Read-Host "Choose for VM $v"
                if ($choice -in @('A','a')) { Add-Account; $available = Load-Accounts; continue }
                if ($choice -in @('B','b')) { Clear-Host; & $PSCommandPath; exit }
                $num = 0
                if ([int]::TryParse($choice, [ref]$num) -and $num -ge 1 -and $num -le $available.Count) {
                    $selected = $available[$num - 1]; $available = @($available | Where-Object { $_.Email -ne $selected.Email })
                }
            }
            $accountsPerVM += $selected
        }
    }
}

# ============================================================
# FORWARDING SETUP (optional: read codes from different email)
# ============================================================
$forwardingEnabled = $false
$fetchEmail = ""
$fetchPass = ""
$fetchProvider = "gmail"

while ($true) {
    Show-Banner
    Show-StepHeader "" "Email Forwarding (Hotmail → Gmail)"
    Write-Host "  If Hotmail IMAP doesn't work, you can forward"
    Write-Host "  emails from Hotmail to Gmail, and read codes"
    Write-Host "  from Gmail instead."
    Write-Host ""
    Write-Host "  The GAME gets the original email (Hotmail)"
    Write-Host "  The CODE is read from a different email (Gmail)"
    Write-Host ""
    Write-Host "  [Y] Yes, I enabled forwarding"
    Write-Host "  [N] No, use same email for both"
    Write-Host "  [B] Back"
    Write-Host ""
    $fc = Read-Host "Did you enable forwarding? (Y/N) [N]"
    if ($fc -in @('B','b')) { Clear-Host; & $PSCommandPath; exit }
    if ([string]::IsNullOrWhiteSpace($fc) -or $fc -in @('N','n')) { break }
    if ($fc -in @('Y','y')) {
        $forwardingEnabled = $true
        Write-Host ""
        Write-Host "The verification codes will be read from this email:"
        $fetchEmail = Read-Host "Fetch email (e.g. example@gmail.com)"
        if ([string]::IsNullOrWhiteSpace($fetchEmail)) { continue }
        Show-PasswordHelp $fetchEmail
        $fetchPass = Read-Host "Password / App password"
        if ([string]::IsNullOrWhiteSpace($fetchPass)) { continue }
        if ($fetchEmail -match '@hotmail\.|@outlook\.|@live\.') { $fetchProvider = "hotmail" }
        else { $fetchProvider = "gmail" }
        Write-Host "Provider: $fetchProvider" -ForegroundColor Cyan
        Write-Host ""
        $ok = Read-Host "Confirm (Y/n)"
        if ($ok -ne 'n' -and $ok -ne 'N') { break }
    }
}

if ($forwardingEnabled) {
    foreach ($acc in $accountsPerVM) {
        $acc | Add-Member -NotePropertyName FetchEmail -NotePropertyValue $fetchEmail -Force
        $acc | Add-Member -NotePropertyName FetchPass -NotePropertyValue $fetchPass -Force
        $acc | Add-Member -NotePropertyName FetchProvider -NotePropertyValue $fetchProvider -Force
    }
}
}  # end-if ($mode -ne "Install")

# ============================================================
# STEP 4: EMULATOR SETTINGS
# ============================================================
$emulResW = 640; $emulResH = 480; $emulDPI = 120; $emulCPU = 2; $emulRAM = 2048

while ($true) {
    Show-Banner
    Show-StepHeader "4" "Emulator Settings"
    Write-Host "  Resolution: $emulResW x $emulResH" -ForegroundColor Cyan
    Write-Host "  DPI: $emulDPI" -ForegroundColor Cyan
    Write-Host "  CPU cores: $emulCPU" -ForegroundColor Cyan
    Write-Host "  RAM: $emulRAM MB" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  [1] Use these settings"
    Write-Host "  [2] Change settings"
    Write-Host "  [B] Back to account selection"
    Write-Host ""
    $input = Read-Host "Choice [1]"
    if ($input -in @('B','b')) { $modeChoice = ""; Clear-Host; & $PSCommandPath; exit }
    if ([string]::IsNullOrWhiteSpace($input) -or $input -eq "1") { break }
    if ($input -eq "2") {
        $rw = Read-Host "Resolution width [$emulResW]"
        if (-not [string]::IsNullOrWhiteSpace($rw) -and $rw -notin @('B','b')) { $emulResW = [int]$rw }
        $rh = Read-Host "Resolution height [$emulResH]"
        if (-not [string]::IsNullOrWhiteSpace($rh) -and $rh -notin @('B','b')) { $emulResH = [int]$rh }
        $rd = Read-Host "DPI [$emulDPI]"
        if (-not [string]::IsNullOrWhiteSpace($rd) -and $rd -notin @('B','b')) { $emulDPI = [int]$rd }
        $rc = Read-Host "CPU cores [$emulCPU]"
        if (-not [string]::IsNullOrWhiteSpace($rc) -and $rc -notin @('B','b')) { $emulCPU = [int]$rc }
        $rm = Read-Host "RAM MB [$emulRAM]"
        if (-not [string]::IsNullOrWhiteSpace($rm) -and $rm -notin @('B','b')) { $emulRAM = [int]$rm }
    }
}

# ============================================================
# STEP 5: BATCH PROCESSING
# ============================================================
$batchManual = $false
$batchSize = $sysCap.MaxVMs
$maxBatch = $sysCap.MaxVMs

while ($true) {
    Show-Banner
    Show-StepHeader "5" "How many to run at the same time?"
    $detected = $sysCap.MaxVMs
    Write-Host "  You have: $vmCount emulators" -ForegroundColor Cyan
    Write-Host "  System can handle: $detected at a time" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  [1] Auto ($detected at a time)" -ForegroundColor Green
    Write-Host "  [2] Manual"
    Write-Host ""
    Write-Host "  [B] Back"
    Write-Host ""
    $input = Read-Host "  How many to run simultaneously? [1]"
    if ($input -in @('B','b')) { Clear-Host; & $PSCommandPath; exit }
    if ([string]::IsNullOrWhiteSpace($input) -or $input -eq "1") { $batchSize = $detected; break }
    if ($input -eq "2") {
        $m = Read-Host "  Run how many at a time? (1-$vmCount) [$vmCount]"
        if ([string]::IsNullOrWhiteSpace($m)) { $batchSize = $vmCount; break }
        if ($m -in @('B','b')) { Clear-Host; & $PSCommandPath; exit }
        if ([int]::TryParse($m, [ref]$batchSize) -and $batchSize -ge 1 -and $batchSize -le $vmCount) { break }
    }
}

# ============================================================
# STEP 6: FETCH MODE (only for login modes)
# ============================================================
$fetchMode = "imap"
if ($mode -ne "Install") {
    while ($true) {
        Show-Banner
        Show-StepHeader "6" "Code fetch mode"
        Write-Host "  [1] IMAP auto"
        Write-Host "  [2] Manual"
        Write-Host ""
        Write-Host "  [B] Back"
        Write-Host ""
        $fc = Read-Host "Choice (1-2) [1]"
        if ($fc -in @('B','b')) { continue }
        if ([string]::IsNullOrWhiteSpace($fc)) { break }
        if ($fc -eq "2") { $fetchMode = "sms"; break }
        if ($fc -eq "1") { break }
    }
}

# ============================================================
# SUMMARY
# ============================================================
Show-Banner
Show-StepHeader "" "Ready to Start?"
Write-Host "  Mode: " -NoNewline
if ($mode -eq "Install") { Write-Host "INSTALL ONLY" -ForegroundColor Magenta }
elseif ($mode -eq "InstallLogin") { Write-Host "INSTALL + LOGIN" -ForegroundColor Magenta }
else { Write-Host "LOGIN ONLY" -ForegroundColor Green }
Write-Host "  VMs: $vmCount (MEmu_$startVM to MEmu_$($startVM + $vmCount - 1))" -ForegroundColor Cyan
Write-Host ""
if ($mode -ne "Install") {
    Write-Host "  Account mode: " -NoNewline
    if ($modeChoice -eq "3") { Write-Host "Alias Email (Plus addressing)" -ForegroundColor Green; Write-Host "  Master: $masterEmail ($masterProvider)" -ForegroundColor Cyan }
    elseif ($modeChoice -eq "2") { Write-Host "Different email per VM" -ForegroundColor Green }
    else { Write-Host "Same email on all VMs" -ForegroundColor Green }
    for ($v = 0; $v -lt $vmCount; $v++) {
        Write-Host "  VM $($startVM + $v): $($accountsPerVM[$v].Masked)" -ForegroundColor Green
    }
    Write-Host "  Fetch: $fetchMode" -ForegroundColor Cyan
    if ($forwardingEnabled) { Write-Host "  Forwarding: Yes → fetch from $fetchEmail ($fetchProvider)" -ForegroundColor Green }
    Write-Host ""
}
Write-Host "  Emulator settings:" -ForegroundColor Cyan
Write-Host "    Resolution: ${emulResW}x${emulResH} @ ${emulDPI}dpi" -ForegroundColor Cyan
Write-Host "    CPU: $emulCPU cores, RAM: ${emulRAM}MB" -ForegroundColor Cyan
Write-Host "  Batch: $batchSize VMs at a time" -ForegroundColor Cyan
Write-Host ""
Write-Host "  [R] Run"
Write-Host "  [B] Back to start"
Write-Host "  [Q] Quit" -ForegroundColor DarkGray
Write-Host ""
$confirm = Read-Host "Choice (R/B/Q)"
if ($confirm -in @('B','b')) { Clear-Host; & $PSCommandPath; exit }
if ($confirm -in @('Q','q')) { exit }

# ============================================================
# RUN
# ============================================================
# --- SEARCH MEmu location FIRST ---
$memu = ""; $memuDir = ""
$searchPaths = @(
    "C:\Program Files\Microvirt\MEmu\memuc.exe",
    "D:\Program Files\Microvirt\MEmu\memuc.exe",
    "E:\Program Files\Microvirt\MEmu\memuc.exe",
    "C:\Program Files (x86)\Microvirt\MEmu\memuc.exe",
    "D:\Program Files (x86)\Microvirt\MEmu\memuc.exe"
)
foreach ($path in $searchPaths) {
    if (Test-Path $path) { $memu = $path; $memuDir = Split-Path $path; break }
}
if (-not $memu) {
    $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -ne $null } | Select-Object -ExpandProperty Root
    foreach ($drive in $drives) {
        foreach ($sub in @("Program Files\Microvirt\MEmu\memuc.exe", "Program Files (x86)\Microvirt\MEmu\memuc.exe")) {
            $p = Join-Path $drive.TrimEnd('\') $sub
            if (Test-Path $p) { $memu = $p; $memuDir = Split-Path $p; break }
        }
        if ($memu) { break }
    }
}
$adb = if ($memuDir) { Join-Path $memuDir "adb.exe" } else { "" }

# --- KILL ALL EXISTING EMULATORS ---
Show-Banner
Show-StepHeader "" "Killing existing emulators..."
Get-Process -Name "MEmuConsole","MemuService","MEmuSVC","MEmuHeadless","MuMuPlayer","memuc" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep 3
Write-Host "  All emulators stopped." -ForegroundColor Green
Start-Sleep 2

# --- PRE-EXTRACT XAPK (once, only for install modes) ---
function Test-XapkValid {
    param([string]$path)
    try {
        $item = Get-Item $path -ErrorAction Stop
        if ($item.Length -lt 100MB) { Write-Host "  [CHECK] File too small: $($item.Length) bytes" -ForegroundColor Yellow; return $false }
        $bytes = [byte[]]::new(4)
        $fs = [System.IO.File]::OpenRead($path)
        $fs.Read($bytes, 0, 4) | Out-Null
        $fs.Close()
        $magic = [Text.Encoding]::ASCII.GetString($bytes)
        if (-not $magic.StartsWith("PK")) { Write-Host "  [CHECK] Not a ZIP file (magic: $magic)" -ForegroundColor Yellow; return $false }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [System.IO.Compression.ZipFile]::OpenRead($path)
        $archive.Dispose()
        return $true
    } catch { Write-Host "  [CHECK] Validation error: $_" -ForegroundColor Yellow; return $false }
}

$xapkUrl = "https://www.dropbox.com/scl/fi/8rmru6kpri5lypp6siwjg/Rise-of-Kingdoms_-Lost-Crusade_1.1.8.22_APKPure.xapk.xapk?rlkey=85412k9v9k9eeokqximiqj71e&st=ibcmkh2r&e=1&dl=1"
$xapkName = "Rise+of+Kingdoms%3A+Lost+Crusade_1.1.8.26_APKPure.xapk"
$xapkLocal = "Rise+of+Kingdoms_Lost+Crusade_1.1.8.26_APKPure.xapk"
$apkBase = ""; $apkRaw = ""; $apkConfig = ""
if ($mode -eq "Install" -or $mode -eq "InstallLogin") {
    function Get-ShortPath($p) { return cmd /c "for %A in (`"$p`") do @echo %~sA" 2>$null | Select-Object -First 1 }
    Write-Host "  Preparing XAPK installation files..." -ForegroundColor Cyan
    $xapk = Get-ChildItem -Path $scriptDir -Filter "*.xapk" | Select-Object -First 1
    if (-not $xapk) {
        # Check cached location in ProgramData
        $permDir = "C:\ProgramData\KingdomCo"
        if (Test-Path $permDir) { $xapk = Get-ChildItem -Path $permDir -Filter "*.xapk" | Select-Object -First 1 }
    }
    if (-not $xapk) {
        # Check install directory
        $installDir = "C:\Program Files\KINGDOM ♠ CO  MEmu Auto Installer RoK"
        if (Test-Path $installDir) { $xapk = Get-ChildItem -Path $installDir -Filter "*.xapk" | Select-Object -First 1 }
    }
    if (-not $xapk) {
        $altDir = "C:\Users\MaleK\Downloads\Compressed\KINGDOM ♠ CO  MEmu Auto Installer RoK\KINGDOM ♠ CO  MEmu Auto Installer RoK"
        if (Test-Path $altDir) { $xapk = Get-ChildItem -Path $altDir -Filter "*.xapk" | Select-Object -First 1 }
    }
    if (-not $xapk) {
        $desktopDir = "C:\Users\MaleK\OneDrive\سطح المكتب\New folder 2(2)"
        if (Test-Path $desktopDir) { $xapk = Get-ChildItem -Path $desktopDir -Filter "*.xapk" | Select-Object -First 1 }
    }
    if (-not $xapk) {
        Write-Host "  [!] XAPK not found locally." -ForegroundColor Yellow
        $xapkTemp = Join-Path $env:TEMP "Rise+of+Kingdoms_Lost+Crusade_1.1.8.26_APKPure.xapk"
        $xapkPerm = "C:\ProgramData\KingdomCo\Rise+of+Kingdoms_Lost+Crusade_1.1.8.26_APKPure.xapk"
        $xapkPath = $xapkTemp
        
        if (Test-Path $xapkPerm) {
            $xapk = Get-Item $xapkPerm
            Write-Host "  Found cached XAPK!" -ForegroundColor Green
        } else {
            # Try default download first
            $dlSuccess = $false
            try {
                Write-Host "  [!] XAPK not found locally. Downloading from default link..." -ForegroundColor Yellow
                $totalSize = 1461687213
                try {
                    $hReq = [System.Net.HttpWebRequest]::Create($xapkUrl)
                    $hReq.Method = "HEAD"; $hReq.UserAgent = "Mozilla/5.0"; $hReq.Timeout = 10000
                    $hResp = $hReq.GetResponse()
                    if ($hResp.ContentLength -gt 0) { $totalSize = $hResp.ContentLength }
                    $hResp.Close()
                } catch {}
                $totalMb = [math]::Round($totalSize / 1MB, 1)
                $sw = [System.Diagnostics.Stopwatch]::StartNew()
                $lastPct = 0
                
                $job = Start-Job -ScriptBlock {
                    param($url, $out)
                    $req = [System.Net.HttpWebRequest]::Create($url)
                    $req.Timeout = -1; $req.ReadWriteTimeout = -1
                    $req.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
                    $resp = $req.GetResponse()
                    $stream = $resp.GetResponseStream()
                    $fs = [System.IO.File]::Create($out)
                    $buf = New-Object byte[] 81920
                    while (($r = $stream.Read($buf, 0, $buf.Length)) -gt 0) { $fs.Write($buf, 0, $r) }
                    $fs.Close(); $stream.Close(); $resp.Close()
                } -ArgumentList $xapkUrl, $xapkTemp
                
                while ($job.State -eq 'Running') {
                    Start-Sleep -Milliseconds 300
                    if (Test-Path $xapkTemp) {
                        $mb = [math]::Round((Get-Item $xapkTemp).Length / 1MB, 1)
                        $pct = [math]::Round($mb / $totalMb * 100, 1)
                        if ($pct -gt $lastPct) {
                            $lastPct = $pct
                            $filled = [math]::Floor($pct / 2)
                            $empty = 50 - $filled
                            $bar = "[" + ("#" * $filled) + ("-" * $empty) + "]"
                            $speed = [math]::Round($mb / ($sw.Elapsed.TotalSeconds + 0.1), 1)
                            Write-Host "`r  $bar $pct% ($mb / $totalMb MB) - ${speed} MB/s    " -NoNewline -ForegroundColor Cyan
                        }
                    }
                }
                
                Receive-Job $job -ErrorAction Stop
                Remove-Job $job -Force -ErrorAction SilentlyContinue
                $sw.Stop()
                Write-Host ""
                Write-Host "  Download complete! ($totalMb MB in $([math]::Round($sw.Elapsed.TotalSeconds))s)" -ForegroundColor Green
                
                $permDir = "C:\ProgramData\KingdomCo"
                if (-not (Test-Path $permDir)) { New-Item -ItemType Directory -Path $permDir -Force | Out-Null }
                Copy-Item $xapkTemp $xapkPerm -Force
                Write-Host "  Cached to: $permDir" -ForegroundColor Green
                $xapk = Get-Item $xapkPerm
                if (Test-XapkValid $xapkPerm) {
                    $dlSuccess = $true
                } else {
                    Write-Host ""
                    Write-Host "  [ERROR] Downloaded file is not a valid XAPK." -ForegroundColor Red
                    Remove-Item $xapkTemp -Force -ErrorAction SilentlyContinue
                    Remove-Item $xapkPerm -Force -ErrorAction SilentlyContinue
                    $xapk = $null
                }
            } catch {
                Write-Host ""
                Write-Host "  [ERROR] Download failed: $($_.Exception.Message)" -ForegroundColor Red
                if (Test-Path $xapkTemp) { Remove-Item $xapkTemp -Force -ErrorAction SilentlyContinue }
                if (Test-Path $xapkPerm) { Remove-Item $xapkPerm -Force -ErrorAction SilentlyContinue }
            }
            
            # If default failed, show fallback options
            while (-not $dlSuccess) {
                Write-Host ""
                Write-Host "  Choose another method:" -ForegroundColor Cyan
                Write-Host "  [1] Paste a custom download URL" -ForegroundColor Yellow
                Write-Host "  [2] Specify local file path" -ForegroundColor Yellow
                Write-Host ""
                $dlChoice = Read-Host "  Choice"
                
                if ($dlChoice -eq '1') {
                    $dlUrl = Read-Host "  Enter download URL"
                    if ([string]::IsNullOrWhiteSpace($dlUrl)) { Write-Host "  [ERROR] URL cannot be empty" -ForegroundColor Red; continue }
                    try {
                        Write-Host "  Downloading..." -ForegroundColor Yellow
                        $totalSize = 1461687213
                        try {
                            $hReq = [System.Net.HttpWebRequest]::Create($dlUrl)
                            $hReq.Method = "HEAD"; $hReq.UserAgent = "Mozilla/5.0"; $hReq.Timeout = 10000
                            $hResp = $hReq.GetResponse()
                            if ($hResp.ContentLength -gt 0) { $totalSize = $hResp.ContentLength }
                            $hResp.Close()
                        } catch {}
                        $totalMb = [math]::Round($totalSize / 1MB, 1)
                        $sw = [System.Diagnostics.Stopwatch]::StartNew()
                        $lastPct = 0
                        
                        $job = Start-Job -ScriptBlock {
                            param($url, $out)
                            $req = [System.Net.HttpWebRequest]::Create($url)
                            $req.Timeout = -1; $req.ReadWriteTimeout = -1
                            $req.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
                            $resp = $req.GetResponse()
                            $stream = $resp.GetResponseStream()
                            $fs = [System.IO.File]::Create($out)
                            $buf = New-Object byte[] 81920
                            while (($r = $stream.Read($buf, 0, $buf.Length)) -gt 0) { $fs.Write($buf, 0, $r) }
                            $fs.Close(); $stream.Close(); $resp.Close()
                        } -ArgumentList $dlUrl, $xapkTemp
                        
                        while ($job.State -eq 'Running') {
                            Start-Sleep -Milliseconds 300
                            if (Test-Path $xapkTemp) {
                                $mb = [math]::Round((Get-Item $xapkTemp).Length / 1MB, 1)
                                $pct = [math]::Round($mb / $totalMb * 100, 1)
                                if ($pct -gt $lastPct) {
                                    $lastPct = $pct
                                    $filled = [math]::Floor($pct / 2)
                                    $empty = 50 - $filled
                                    $bar = "[" + ("#" * $filled) + ("-" * $empty) + "]"
                                    $speed = [math]::Round($mb / ($sw.Elapsed.TotalSeconds + 0.1), 1)
                                    Write-Host "`r  $bar $pct% ($mb / $totalMb MB) - ${speed} MB/s    " -NoNewline -ForegroundColor Cyan
                                }
                            }
                        }
                        
                        Receive-Job $job -ErrorAction Stop
                        Remove-Job $job -Force -ErrorAction SilentlyContinue
                        $sw.Stop()
                        Write-Host ""
                        Write-Host "  Download complete! ($totalMb MB in $([math]::Round($sw.Elapsed.TotalSeconds))s)" -ForegroundColor Green
                        
                        $permDir = "C:\ProgramData\KingdomCo"
                        if (-not (Test-Path $permDir)) { New-Item -ItemType Directory -Path $permDir -Force | Out-Null }
                        Copy-Item $xapkTemp $xapkPerm -Force
                        Write-Host "  Cached to: $permDir" -ForegroundColor Green
                        $xapk = Get-Item $xapkPerm
                        if (Test-XapkValid $xapkPerm) {
                            $dlSuccess = $true
                        } else {
                            Write-Host ""
                            Write-Host "  [ERROR] Downloaded file is not a valid XAPK." -ForegroundColor Red
                            Remove-Item $xapkTemp -Force -ErrorAction SilentlyContinue
                            Remove-Item $xapkPerm -Force -ErrorAction SilentlyContinue
                            $xapk = $null
                        }
                    } catch {
                        Write-Host ""
                        Write-Host "  [ERROR] Download failed: $($_.Exception.Message)" -ForegroundColor Red
                        if (Test-Path $xapkTemp) { Remove-Item $xapkTemp -Force -ErrorAction SilentlyContinue }
                        if (Test-Path $xapkPerm) { Remove-Item $xapkPerm -Force -ErrorAction SilentlyContinue }
                    }
                } elseif ($dlChoice -eq '2') {
                    $dlLocal = Read-Host "  Enter full path to .xapk file"
                    if ([string]::IsNullOrWhiteSpace($dlLocal)) { Write-Host "  [ERROR] Path cannot be empty" -ForegroundColor Red; continue }
                    if (-not (Test-Path $dlLocal)) { Write-Host "  [ERROR] File not found: $dlLocal" -ForegroundColor Red; continue }
                    if (-not (Test-XapkValid $dlLocal)) { Write-Host "  [ERROR] File is not a valid XAPK: $dlLocal" -ForegroundColor Red; continue }
                    Copy-Item $dlLocal $xapkTemp -Force
                    Copy-Item $dlLocal $xapkPerm -Force
                    $xapk = Get-Item $xapkPerm
                    $dlSuccess = $true
                    Write-Host "  [OK] XAPK copied from local path" -ForegroundColor Green
                } else {
                    Write-Host "  [ERROR] Invalid choice" -ForegroundColor Red
                }
            }
        }
    }
    if (-not $xapk) { Write-Host "  [ERROR] No .xapk file found!" -ForegroundColor Red; exit 1 }
    Write-Host "  XAPK found: $($xapk.Name)" -ForegroundColor Green
    $installTemp = Join-Path $env:TEMP "rok_install_$([System.IO.Path]::GetRandomFileName())"
    New-Item -ItemType Directory -Path $installTemp -Force | Out-Null
    Write-Host "  Extracting XAPK (this may take a moment)..." -ForegroundColor Cyan
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($xapk.FullName, $installTemp)
    Write-Host "  Extraction complete, finding APKs..." -ForegroundColor Green
    $items = Get-ChildItem -Path $installTemp -Filter "*.apk" | Sort-Object Length -Descending
    if ($items.Count -lt 3) { Write-Host "  [ERROR] Not enough APKs in XAPK!" -ForegroundColor Red; exit 1 }
    $rawAsset = $items | Where-Object { $_.Length -gt 1GB } | Select-Object -First 1
    $base = $items | Where-Object { $_.Length -gt 100MB -and $_.Length -lt 200MB } | Select-Object -First 1
    $config = $items | Where-Object { $_.Length -gt 30MB -and $_.Length -lt 100MB } | Select-Object -First 1
    if (-not $base -or -not $rawAsset -or -not $config) {
        $sorted = $items | Sort-Object Length -Descending
        $rawAsset = $sorted[0]; $base = $sorted[1]; $config = $sorted[2]
    }
    $apkBase = Get-ShortPath $base.FullName
    $apkRaw = Get-ShortPath $rawAsset.FullName
    $apkConfig = Get-ShortPath $config.FullName
    Write-Host "  APKs ready: base=$($base.Name) / raw=$($rawAsset.Name) / config=$($config.Name)" -ForegroundColor Green
}

# --- CHECK MEmu INSTALLATION (fallback if not found earlier) ---
if (-not $memu) {
    $searchPaths = @(
        "C:\Program Files\Microvirt\MEmu\memuc.exe",
        "D:\Program Files\Microvirt\MEmu\memuc.exe",
        "E:\Program Files\Microvirt\MEmu\memuc.exe",
        "C:\Program Files (x86)\Microvirt\MEmu\memuc.exe",
        "D:\Program Files (x86)\Microvirt\MEmu\memuc.exe"
    )
    foreach ($path in $searchPaths) {
        if (Test-Path $path) { $memu = $path; $memuDir = Split-Path $path; break }
    }
    if (-not $memu) {
        $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -ne $null } | Select-Object -ExpandProperty Root
        foreach ($drive in $drives) {
            foreach ($sub in @("Program Files\Microvirt\MEmu\memuc.exe", "Program Files (x86)\Microvirt\MEmu\memuc.exe")) {
                $p = Join-Path $drive.TrimEnd('\') $sub
                if (Test-Path $p) { $memu = $p; $memuDir = Split-Path $p; break }
            }
            if ($memu) { break }
        }
    }
}

if (-not $memu) {
    Write-Host ""
    Write-Host "  [!] MEmu not found. Downloading MEmu installer..." -ForegroundColor Yellow
    $memuUrl = "https://dl.memuplay.net/download/MEmu-setup-abroad-643b34e8.exe"
    $memuSetup = Join-Path $env:TEMP "MEmu-setup.exe"
    try {
        $totalSize = 650000000
        $totalMb = [math]::Round($totalSize / 1MB, 1)
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $lastPct = 0
        
        $job = Start-Job -ScriptBlock {
            param($url, $out)
            $wc = New-Object System.Net.WebClient
            $wc.DownloadFile($url, $out)
        } -ArgumentList $memuUrl, $memuSetup
        
        while ($job.State -eq 'Running') {
            Start-Sleep -Milliseconds 300
            if (Test-Path $memuSetup) {
                $mb = [math]::Round((Get-Item $memuSetup).Length / 1MB, 1)
                $pct = [math]::Round($mb / $totalMb * 100, 1)
                if ($pct -gt $lastPct) {
                    $lastPct = $pct
                    $filled = [math]::Floor($pct / 2)
                    $empty = 50 - $filled
                    $bar = "[" + ("#" * $filled) + ("-" * $empty) + "]"
                    $speed = [math]::Round($mb / ($sw.Elapsed.TotalSeconds + 0.1), 1)
                    Write-Host "`r  $bar $pct% ($mb / $totalMb MB) - ${speed} MB/s    " -NoNewline -ForegroundColor Cyan
                }
            }
        }
        Receive-Job $job -ErrorAction SilentlyContinue
        Remove-Job $job -Force -ErrorAction SilentlyContinue
        $sw.Stop()
        Write-Host ""
        Write-Host "  Download complete! Installing MEmu..." -ForegroundColor Green
        
        # Install MEmu silently
        $null = & $memuSetup /S 2>&1
        Start-Sleep -Seconds 30
        
        # Search again after install
        foreach ($path in $searchPaths) {
            if (Test-Path $path) {
                $memu = $path
                $memuDir = Split-Path $path
                break
            }
        }
        if (-not $memu) {
            foreach ($drive in $drives) {
                $found = Get-ChildItem -Path $drive -Filter "memuc.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($found) {
                    $memu = $found.FullName
                    $memuDir = Split-Path $memu
                    break
                }
            }
        }
        
        if ($memu) {
            Write-Host "  MEmu installed successfully at: $memuDir" -ForegroundColor Green
        } else {
            Write-Host "  [ERROR] MEmu installation failed!" -ForegroundColor Red
            Write-Host "  Please install manually from: https://www.memuplay.com/" -ForegroundColor Yellow
            exit 1
        }
    } catch {
        Write-Host ""
        Write-Host "  [ERROR] Download failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  Please install MEmu from: https://www.memuplay.com/" -ForegroundColor Yellow
        exit 1
    }
}
$adb = Join-Path $memuDir "adb.exe"

# --- CHECK EMULATOR COUNT AND CREATE IF NEEDED ---
$existingVMs = @()
try { $existingVMs = & $memu listvms 2>$null } catch {}
$existingCount = 0
if ($existingVMs) { $existingCount = ($existingVMs | Measure-Object).Count }

Write-Host ""
Write-Host "  You have $existingCount emulator(s) installed." -ForegroundColor Cyan
Write-Host ""
Write-Host "  How many emulators do you want?" -ForegroundColor Yellow
Write-Host "  [1] 3 emulators" -ForegroundColor White
Write-Host "  [2] 5 emulators" -ForegroundColor White
Write-Host "  [3] 10 emulators" -ForegroundColor White
Write-Host "  [4] Custom number" -ForegroundColor White
Write-Host "  [5] Skip (use existing)" -ForegroundColor DarkGray
Write-Host ""
$maxDesired = 10
$skipCreate = $false
$vmChoice = Read-Host "  Choice [3]"
if ([string]::IsNullOrWhiteSpace($vmChoice) -or $vmChoice -eq "3") { $maxDesired = 10 }
elseif ($vmChoice -eq "1") { $maxDesired = 3 }
elseif ($vmChoice -eq "2") { $maxDesired = 5 }
elseif ($vmChoice -eq "5") { $skipCreate = $true }
elseif ($vmChoice -eq "4") {
    $custom = Read-Host "  Enter number of emulators (1-100)"
    if ([int]::TryParse($custom, [ref]$maxDesired) -and $maxDesired -ge 1 -and $maxDesired -le 100) { }
    else { $maxDesired = 10 }
}

if (-not $skipCreate -and $existingCount -lt $maxDesired) {
    $toCreate = $maxDesired - $existingCount
    Write-Host ""
    Write-Host "  [!] Only $existingCount emulator(s) found. Creating $toCreate new emulator(s)..." -ForegroundColor Yellow
    
    for ($i = 0; $i -lt $toCreate; $i++) {
        $vmNum = $existingCount + $i + 1
        $vmName = "MEmu_$vmNum"
        Write-Host "  Creating $vmName..." -ForegroundColor Cyan
        
        # Create new VM
        try { $null = & $memu clone -i 0 -r $vmName 2>&1 } catch {}
        Start-Sleep -Seconds 8
        
        # Set config (resolution, DPI, CPU, RAM)
        try { $null = & $memu setconfigex -n $vmName custom_resolution "$emulResW $emulResH $emulDPI" 2>&1 } catch {}
        Start-Sleep -Seconds 2
        try { $null = & $memu setconfigex -n $vmName cpus $emulCPU 2>&1 } catch {}
        Start-Sleep -Seconds 2
        try { $null = & $memu setconfigex -n $vmName memory $emulRAM 2>&1 } catch {}
        Start-Sleep -Seconds 2
        
        Write-Host "  $vmName created: ${emulResW}x${emulResH}, DPI=$emulDPI, CPU=$emulCPU, RAM=${emulRAM}MB" -ForegroundColor Green
    }
    
    # Update VM count
    try { $existingVMs = & $memu listvms 2>$null } catch {}
    $existingCount = 0
    if ($existingVMs) { $existingCount = ($existingVMs | Measure-Object).Count }
    Write-Host "  Total emulators: $existingCount" -ForegroundColor Green
}

# --- BATCH LOOP ---
# Clean up old code files first
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Remove-Item (Join-Path $scriptDir "code_need_*.txt") -ErrorAction SilentlyContinue
Remove-Item (Join-Path $scriptDir "code_ready_*.txt") -ErrorAction SilentlyContinue

for ($batchStart = 0; $batchStart -lt $vmCount; $batchStart += $batchSize) {
    $batchEnd = [math]::Min($batchStart + $batchSize, $vmCount)
    $batchVMs = @()
    for ($v = $batchStart; $v -lt $batchEnd; $v++) { $batchVMs += $v }
    $script:submittedCodes = @{}

    Show-Banner
    Show-StepHeader "" "BATCH $([math]::Floor($batchStart / $batchSize) + 1)"
    Write-Host "  VMs: $($batchStart + 1) to $batchEnd" -ForegroundColor Cyan
    Write-Host ""

    # --- Start all VMs in batch ---
    foreach ($vIdx in $batchVMs) {
        $realIdx = $startVM - 1 + $vIdx
        $vmName = "MEmu_$($realIdx + 1)"
        Write-Host "  Starting $vmName..." -ForegroundColor Cyan
        try { $null = & $memu start -n $vmName 2>&1 } catch {}
        Start-Sleep 3
    }

    # --- Wait for ADB for all VMs ---
    Write-Host "  Waiting 20s for emulators to boot..." -ForegroundColor Cyan
    Start-Sleep 20
    foreach ($vIdx in $batchVMs) {
        $realIdx = $startVM - 1 + $vIdx
        $port = 21513 + $realIdx * 10
        $serial = "127.0.0.1:$port"
        Write-Host "  Connecting ADB to $serial..." -ForegroundColor Cyan
        $adOk = $false
        for ($a = 0; $a -lt 30; $a++) {
            try { $null = & $adb disconnect $serial 2>&1 } catch {} ; Start-Sleep -Milliseconds 200
            try { $connect = & $adb connect $serial 2>&1 } catch { $connect = "" }
            Start-Sleep -Milliseconds 500
            try { $state = & $adb -s $serial get-state 2>&1 } catch { $state = "" }
            if ($state -match "device") {
                try { $echo = & $adb -s $serial shell echo OK 2>&1 } catch { $echo = "" }
                if ($echo -match "OK") { $adOk = $true; break }
            }
            Write-Host "." -ForegroundColor DarkGray -NoNewline
            Start-Sleep 5
        }
        if ($adOk) { Write-Host " ADB ready: $serial" -ForegroundColor Green }
        else { Write-Host " ADB FAILED for $serial!" -ForegroundColor Red }
    }

    # --- Process all VMs in batch (IN PARALLEL) ---
    Write-Host "Starting all VMs in parallel..." -ForegroundColor Green
    Write-Host ""

    $jobs = @()
    foreach ($vIdx in $batchVMs) {
        $realIdx = $startVM - 1 + $vIdx
        $acc = $accountsPerVM[$vIdx]
        if ($acc) {
            $escEmail = $acc.Email -replace "'", "''"
            $escPass = $acc.Pass -replace "'", "''"
        } else {
            $escEmail = ""; $escPass = ""
        }
        $escEngineDir = $script:EngineDir -replace "'", "''"
        $escOriginalDir = $script:originalDir -replace "'", "''"
        $escApkBase = $apkBase -replace "'", "''"
        $escApkRaw = $apkRaw -replace "'", "''"
        $escApkConfig = $apkConfig -replace "'", "''"
        $escMemuDir = $memuDir -replace "'", "''"
        $cmd = "& '$mainScript' -Mode '$mode' -VMCount 1 -FetchMode '$fetchMode' -Email '$escEmail' -AppPassword '$escPass' -VMIndex $realIdx -StartVM $startVM -EmulResW $emulResW -EmulResH $emulResH -EmulDPI $emulDPI -SkipVMStart -EngineDir '$escEngineDir' -OriginalDir '$escOriginalDir' -ApkBase '$escApkBase' -ApkRaw '$escApkRaw' -ApkConfig '$escApkConfig' -MemuDir '$escMemuDir'"
        if ($acc -and $modeChoice -eq "3") {
            $escMaster = $acc.MasterEmail -replace "'", "''"
            $escMasterP = $acc.MasterPass -replace "'", "''"
            $cmd += " -MasterEmail '$escMaster' -MasterPass '$escMasterP' -Provider '$($acc.Provider)' -AliasSuffix $($vIdx + 1)"
        }

        if ($acc -and $acc.FetchEmail -and $acc.FetchEmail -ne "") {
            $escFetch = $acc.FetchEmail -replace "'", "''"
            $escFetchP = $acc.FetchPass -replace "'", "''"
            $cmd += " -FetchEmail '$escFetch' -FetchPass '$escFetchP' -FetchProvider '$($acc.FetchProvider)'"
        }

        $sb = [scriptblock]::Create($cmd)
        $job = Start-Job -Name "MEmu_$($realIdx + 1)" -ScriptBlock $sb
        $jobs += $job
        Write-Host "  MEmu_$($realIdx + 1) started in background" -ForegroundColor Cyan
    }

    Write-Host "Waiting for all VMs to finish..." -ForegroundColor Yellow
    Write-Host "(Live output will appear below)" -ForegroundColor DarkGray

    $allDone = $false
    $minWaitSeconds = 30
    $elapsedBatch = 0
    while (-not $allDone) {
        Start-Sleep 5
        $elapsedBatch += 5
        $allDone = $true
        
        # FIRST: Show logs from background jobs
        foreach ($j in $jobs) {
            if ($j.State -eq 'Running' -or $j.State -eq 'NotStarted') { $allDone = $false }
            $msg = Receive-Job $j 2>&1
            if ($msg) {
                foreach ($line in ($msg | Out-String).Trim() -split "`n") {
                    $t = $line.Trim()
                    if ($t) { Write-Host "[$($j.Name)] $t" }
                }
            }
            if ($j.State -eq 'Failed') {
                Write-Host "  [$($j.Name)] JOB FAILED!" -ForegroundColor Red
                if ($msg) { Write-Host "  [$($j.Name)] $($msg | Out-String)" -ForegroundColor Red }
            }
        }
        
        # THEN: Check for code_need files (manual code entry)
        # Track which VMs already had codes submitted to avoid asking again
        if (-not $script:submittedCodes) { $script:submittedCodes = @{} }
        $codeNeedFiles = Get-ChildItem (Join-Path $scriptDir "code_need_*.txt") -ErrorAction SilentlyContinue
        foreach ($cf in $codeNeedFiles) {
            $cfName = $cf.Name
            $vmIdx = ($cfName -replace 'code_need_VM', '') -replace '\.txt$', ''
            # Skip if already submitted for this VM
            if ($script:submittedCodes[$vmIdx]) { continue }
            $vmNum = [int]$vmIdx + 1
            Write-Host ""
            Write-Host "  +--------------------------------------------+" -ForegroundColor Yellow
            Write-Host "  |  VM${vmNum}: Code sent! Check your email" -ForegroundColor Yellow
            Write-Host "  |  Enter the 6-digit code below" -ForegroundColor Cyan
            Write-Host "  +--------------------------------------------+" -ForegroundColor Yellow
            Write-Host ""
            $manualCode = Read-Host "  Code for VM${vmNum}"
            if ($manualCode -match '^\d{6}$') {
                $readyFile = Join-Path $scriptDir "code_ready_VM${vmIdx}.txt"
                $manualCode | Out-File $readyFile -Encoding ASCII
                $script:submittedCodes[$vmIdx] = $true
                Write-Host "  Code submitted for VM${vmNum}" -ForegroundColor Green
            } else {
                Write-Host "  Invalid! Must be 6 digits" -ForegroundColor Red
            }
        }

        if ($allDone -and $elapsedBatch -lt $minWaitSeconds) {
            # Don't exit too fast - wait minimum time for slow jobs
            $allDone = $false
        } elseif (-not $allDone) {
            $running = ($jobs | Where-Object { $_.State -eq 'Running' }).Count
            Write-Host "  ($running VM(s) still running...)" -ForegroundColor DarkGray
        }
    }

    Write-Host ""
    foreach ($j in $jobs) {
        $out = Receive-Job $j 2>&1 | Out-String
        if ($out.Trim()) {
            Write-Host "--- $($j.Name) Final ---" -ForegroundColor Cyan
            Write-Host $out
        }
        Remove-Job $j -ErrorAction SilentlyContinue
    }

    Write-Host "All VMs in batch completed!" -ForegroundColor Green

    # --- Kill batch VMs ---
    Write-Host "Killing batch VMs..." -ForegroundColor Yellow
    foreach ($vIdx in $batchVMs) {
        $realIdx = $startVM - 1 + $vIdx
        $vmName = "MEmu_$($realIdx + 1)"
        try { $null = & $memu stop -n $vmName 2>&1 } catch {}
        Write-Host "  $vmName stopped." -ForegroundColor Cyan
        Start-Sleep 1
    }

    if ($batchEnd -lt $vmCount) {
        Write-Host ""; Write-Host "Batch complete. Starting next batch..." -ForegroundColor Yellow; Start-Sleep 5
    }
}

Show-Banner
Write-Host "  +--------------------------------------------+" -ForegroundColor Green
Write-Host "  |            ALL DONE!                        |" -ForegroundColor Green
Write-Host "  |        $vmCount VM(s) completed              |" -ForegroundColor Green
Write-Host "  +--------------------------------------------+" -ForegroundColor Green
Write-Host ""
Read-Host "`nPress ENTER"

