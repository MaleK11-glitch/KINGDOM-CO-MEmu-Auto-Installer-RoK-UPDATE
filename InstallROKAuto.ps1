param(
    [string]$Mode = "Login",
    [int]$VMCount = 1,
    [string]$FetchMode = "",
    [string]$Email = "",
    [string]$AppPassword = "",
    [int]$VMIndex = 0,
    [int]$StartVM = 1,
    [string]$MasterEmail = "",
    [string]$MasterPass = "",
    [string]$Provider = "gmail",
    [int]$AliasSuffix = 0,
    [int]$EmulResW = 640,
    [int]$EmulResH = 480,
    [int]$EmulDPI = 120,
    [switch]$SkipVMStart = $false,
    [string]$FetchEmail = "",
    [string]$FetchPass = "",
    [string]$FetchProvider = "",
    [string]$ApkBase = "",
    [string]$ApkRaw = "",
    [string]$ApkConfig = "",
    [string]$EngineDir = "",
    [string]$OriginalDir = "",
    [string]$MemuDir = ""
)

$ErrorActionPreference = "SilentlyContinue"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($EngineDir)) { $EngineDir = $scriptDir }
if ([string]::IsNullOrWhiteSpace($OriginalDir)) { $OriginalDir = $scriptDir }
if ([string]::IsNullOrWhiteSpace($MemuDir)) { $MemuDir = "C:\Program Files\Microvirt\MEmu" }
$adb = Join-Path $MemuDir "adb.exe"
$memu = Join-Path $MemuDir "memuc.exe"
$tempDir = $EngineDir
if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir -Force | Out-Null }
$imapScript = Join-Path $EngineDir "fetch_code_imap.py"
$detectScript = Join-Path $EngineDir "detect_ui.py"
# Clean up only THIS VM's leftover code files (not all VMs!)
Remove-Item (Join-Path $OriginalDir "code_need_VM$VMIndex.txt"), (Join-Path $OriginalDir "code_ready_VM$VMIndex.txt") -ErrorAction SilentlyContinue

$C = @{ Green="Green"; Yellow="Yellow"; Red="Red"; Cyan="Cyan"; Dim="DarkGray"; White="White" }

function Write-Log($msg, $color) {
    if (-not $color) { $color = $C.White }
    Write-Host $msg -ForegroundColor $color
}
function Tap($s, $x, $y) { $null = & $adb -s $s shell input tap $x $y 2>&1 }
function Key($s, $k) { $null = & $adb -s $s shell input keyevent $k 2>&1 }
function Back($s) { Key $s "KEYCODE_BACK"; Wait 200 }
function Text($s, $t) {
    # ADB input text: wrap in single quotes to handle @ + ( ) etc.
    $null = & $adb -s $s shell input text "'$t'" 2>&1
}
function Wait($ms) { Start-Sleep -Milliseconds $ms }
function Swipe($s, $x1,$y1,$x2,$y2,$d) { $null = & $adb -s $s shell input swipe $x1 $y1 $x2 $y2 $d 2>&1 }
function GetFocus($s) {
    $raw = & $adb -s $s shell dumpsys window windows 2>&1 | Out-String
    if ($raw -match "mCurrentFocus=.*?[^/]+/([^\s}]+)") { return $Matches[1] }
    return ""
}

function Detect-Button($s) {
    $result = (& python $detectScript --serial $s --action find_button 2>&1 | Out-String).Trim()
    if ($result -match "FOUND:(\d+):(\d+):([\d.]+)") {
        $score = [double]$Matches[3]
        if ($score -ge 0.3) {
            return @{ X=[int]$Matches[1]; Y=[int]$Matches[2]; Score=$score }
        }
        Write-Log "  Button detected but score too low: $score" $C.Dim
    }
    return $null
}

function Check-City($s) {
    $result = (& python $detectScript --serial $s --action check_city 2>&1 | Out-String).Trim()
    if ($result -match "^CITY:([\d.]+)") {
        return @{ Score=[double]$Matches[1]; IsCity=$true }
    }
    if ($result -match "^NOT_CITY:([\d.]+)") {
        return @{ Score=[double]$Matches[1]; IsCity=$false }
    }
    return @{ Score=0.0; IsCity=$false }
}

function Check-TapScreen($s) {
    $result = (& python $detectScript --serial $s --action tap_screen 2>&1 | Out-String).Trim()
    if ($result -match "^TAP_SCREEN:([\d.]+)") {
        return @{ Score=[double]$Matches[1]; Found=$true }
    }
    return @{ Score=0.0; Found=$false }
}

function Check-Splash($s) {
    $result = (& python $detectScript --serial $s --action check_splash 2>&1 | Out-String).Trim()
    if ($result -match "^SPLASH:([\d.]+)") {
        return @{ Score=[double]$Matches[1]; Found=$true }
    }
    return @{ Score=0.0; Found=$false }
}

function Set-AndroidID($s) {
    Write-Log "  Changing Android ID..." $C.Cyan
    $newId = -join ((65..90)+(97..122)+(48..57) | Get-Random -Count 16 | ForEach-Object {[char]$_})
    $null = & $adb -s $s shell settings put secure android_id $newId 2>&1
}

function Clear-AppData($s) {
    Write-Log "  Clearing app data..." $C.Cyan
    $null = & $adb -s $s shell pm clear com.lilithgame.roc.gp 2>&1
}

function Wait-ForActivity($s, $pattern, $timeoutSec) {
    $elapsed = 0
    while ($elapsed -lt $timeoutSec) {
        $f = GetFocus $s
        if ($f -match $pattern) { return $true }
        Wait 2000; $elapsed += 2
    }
    return $false
}

function DumpUI($s) {
    $null = & $adb -s $s shell rm -f /sdcard/u.xml 2>&1
    Wait 300
    $null = & $adb -s $s shell uiautomator dump /sdcard/u.xml 2>&1
    Wait 500
    $xml = & $adb -s $s shell cat /sdcard/u.xml 2>&1 | Out-String
    return $xml
}

function Detect-VMADBPort($idx) {
    $port = 21513 + $idx * 10
    $serial = "127.0.0.1:$port"
    try { $null = & $adb disconnect $serial 2>&1 } catch {} ; Wait 300
    try { $null = & $adb connect $serial 2>&1 } catch {} ; Wait 1000
    try {
        if ((& $adb -s $serial get-state 2>&1) -match "device") {
            if ((& $adb -s $serial shell echo OK 2>&1) -match "OK") { return $serial }
        }
    } catch {}
    return $null
}

function Wait-ForADB($idx, $timeoutSec) {
    $elapsed = 0
    while ($elapsed -lt $timeoutSec) {
        $s = Detect-VMADBPort $idx
        if ($s) { Write-Log "  ADB ready: $s" $C.Green; return $s }
        Write-Log ("  Waiting ADB... ($elapsed s)") $C.Dim
        Wait 5000; $elapsed += 5
    }
    return $null
}

function Start-VM($idx) {
    $name = "MEmu_$($idx + 1)"
    Write-Log "Starting $name..." $C.Cyan
    $null = & $memu start -n $name 2>&1
    Wait 5000
}

function Get-ScreenSize($s) {
    $raw = & $adb -s $s shell wm size 2>&1 | Out-String
    # Check for override size first (if wm size was set)
    if ($raw -match "Override size: (\d+)x(\d+)") { return @{W=[int]$Matches[1]; H=[int]$Matches[2]} }
    if ($raw -match "Physical size: (\d+)x(\d+)") { return @{W=[int]$Matches[1]; H=[int]$Matches[2]} }
    return @{W=640; H=480}
}

function IMAP-FetchCode($email, $pass, $requestTimestamp, $provider, $alias) {
    Write-Log "  Fetching code via IMAP..." $C.Cyan

    if ($provider -eq "hotmail") {
        return IMAP-FetchHotmail $email $pass $requestTimestamp $alias
    }

    # Escape single quotes for Python string safety
    $safeEmail = $email -replace "'", "'\''"
    $safePass = $pass -replace "'", "'\''"
    $safeAlias = $alias -replace "'", "'\''"
    $safeTs = $requestTimestamp -replace "'", "'\''"

    $py = @"
import imaplib, email, re, time, sys, datetime, email.utils
alias = '$safeAlias'
request_ts = '$safeTs'
try:
    if request_ts:
        after_dt = datetime.datetime.fromisoformat(request_ts)
    else:
        after_dt = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=1)

    # Make after_dt timezone-naive if it has timezone info, for safe comparison
    if after_dt.tzinfo is not None:
        after_dt_naive = after_dt.replace(tzinfo=None)
    else:
        after_dt_naive = after_dt

    mail = imaplib.IMAP4_SSL('imap.gmail.com', 993, timeout=30)
    mail.login('$safeEmail', '$safePass')
    mail.select('INBOX')

    # Strategy 1: Search known senders
    senders = ['verify@lilith.com', 'Lilith@email-global.lilithgame.com', 'Lilith@email.lilithgame.com']
    all_ids = set()
    for sender in senders:
        r, d = mail.search(None, 'FROM', sender)
        if r == 'OK' and d[0]:
            for uid in d[0].split():
                uid_str = uid.decode() if isinstance(uid, bytes) else uid
                all_ids.add(uid_str)

    if not all_ids:
        # Strategy 2: Broader search - recent emails with "Lilith" or "lilithgame"
        r, d = mail.search(None, 'FROM', '"lilith"')
        if r == 'OK' and d[0]:
            for uid in d[0].split():
                uid_str = uid.decode() if isinstance(uid, bytes) else uid
                all_ids.add(uid_str)
        else:
            # Strategy 3: Search ALL recent emails (last 50)
            r, d = mail.search(None, 'ALL')
            if r == 'OK' and d[0]:
                all_uids = d[0].split()
                for uid in all_uids[-50:]:
                    uid_str = uid.decode() if isinstance(uid, bytes) else uid
                    all_ids.add(uid_str)

    if not all_ids:
        print('NOEMAIL')
        sys.exit(0)

    # Check newest emails first
    for uid in sorted(all_ids, key=int, reverse=True):
        r, msg_data = mail.fetch(uid, '(RFC822)')
        if r != 'OK': continue
        msg = email.message_from_bytes(msg_data[0][1])
        body = ''
        if msg.is_multipart():
            for part in msg.walk():
                if part.get_content_type() == 'text/html':
                    payload = part.get_payload(decode=True)
                    if payload: body = payload.decode('utf-8', errors='ignore')
                    break
        else:
            payload = msg.get_payload(decode=True)
            if payload: body = payload.decode('utf-8', errors='ignore')

        # Check email arrived AFTER request time (safe compare)
        dt_str = msg['Date']
        if dt_str and after_dt_naive:
            try:
                dt = email.utils.parsedate_to_datetime(dt_str)
                if dt.tzinfo is not None:
                    dt_naive = dt.replace(tzinfo=None)
                else:
                    dt_naive = dt
                if dt_naive < after_dt_naive:
                    continue
            except:
                pass

        # Check alias in To header, Cc, or Subject
        to_header = msg['To'] or ''
        cc_header = msg['Cc'] or ''
        subject = msg['Subject'] or ''
        if alias:
            alias_lower = alias.lower()
            found_alias = (alias_lower in to_header.lower() or
                          alias_lower in cc_header.lower() or
                          alias_lower in subject.lower())
            if not found_alias:
                continue

        # Extract 6-digit code
        m = re.search(r'id="code"[^>]*>(\d{6})', body)
        if not m: m = re.search(r'>(\d{6})</td>', body)
        if not m: m = re.search(r'\b(?!000000\b)(\d{6})\b', body)
        if m:
            print(m.group(1))
            sys.exit(0)

    print('NOCODE')
except Exception as e:
    print('ERR: ' + str(e))
"@
    $tmp = Join-Path $tempDir "imap_fetch_$([System.IO.Path]::GetRandomFileName()).py"
    $py | Out-File -FilePath $tmp -Encoding UTF8
    $raw = (& python $tmp 2>&1 | Out-String).Trim()
    Remove-Item $tmp -ErrorAction SilentlyContinue
    foreach ($line in ($raw -split "`n")) {
        $line = $line.Trim()
        if ($line -match "^\d{6}$") { Write-Log "  Code fetched: $line" $C.Green; return $line }
    }
    Write-Log "  IMAP result: $raw" $C.Yellow
    return $null
}

function IMAP-FetchHotmail($email, $pass, $requestTimestamp, $aliasFilter) {
    Write-Log "  Fetching via Hotmail IMAP..." $C.Cyan
    $result = (& python $imapScript $email $pass "hotmail" $requestTimestamp $aliasFilter 2>&1 | Out-String).Trim()
    if ($result -match "^CODE:(\d{6}):(\d+)") {
        return $Matches[1]
    }
    if ($result -match "^\d{6}$") { return $result }
    Write-Log "  Hotmail IMAP: $result" $C.Red
    return $null
}

function IMAP-GetTimestamp {
    return (Get-Date -Format "o")
}

# ============================================================
# INSTALL FUNCTIONS (XAPK extraction + ADB install)
# ============================================================
function Get-ShortPath($path) {
    return cmd /c "for %A in (`"$path`") do @echo %~sA" 2>$null | Select-Object -First 1
}

function Find-XAPK {
    Write-Log "[INSTALL] Looking for XAPK file..." $C.Cyan
    $xapk = Get-ChildItem -Path $OriginalDir -Filter "*.xapk" | Select-Object -First 1
    if (-not $xapk) {
        $altDir = "C:\Users\MaleK\Downloads\Compressed\KINGDOM ♠ CO  MEmu Auto Installer RoK\KINGDOM ♠ CO  MEmu Auto Installer RoK"
        if (Test-Path $altDir) {
            $xapk = Get-ChildItem -Path $altDir -Filter "*.xapk" | Select-Object -First 1
        }
    }
    if (-not $xapk) {
        $desktopDir = "C:\Users\MaleK\OneDrive\سطح المكتب\New folder 2(2)"
        if (Test-Path $desktopDir) { $xapk = Get-ChildItem -Path $desktopDir -Filter "*.xapk" | Select-Object -First 1 }
    }
    if (-not $xapk) {
        Write-Log "[INSTALL] No .xapk file found!" $C.Red
        exit 1
    }
    Write-Log "[INSTALL] Found: $($xapk.Name)" $C.Green
    return $xapk.FullName
}

function Extract-XAPK($xapkPath) {
    $installTemp = Join-Path $env:TEMP "rok_install_$([System.IO.Path]::GetRandomFileName())"
    New-Item -ItemType Directory -Path $installTemp -Force | Out-Null
    Write-Log "[INSTALL] Extracting XAPK..." $C.Cyan
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $extractOk = $false
    try {
        [System.IO.Compression.ZipFile]::ExtractToDirectory($xapkPath, $installTemp)
        $extractOk = $true
    } catch {
        Write-Log "[INSTALL] .NET extraction failed: $($_.Exception.Message)" $C.Yellow
    }
    if (-not $extractOk) {
        Write-Log "[INSTALL] Trying Expand-Archive fallback..." $C.Yellow
        try {
            Expand-Archive -Path $xapkPath -DestinationPath $installTemp -Force
            $extractOk = $true
        } catch {
            Write-Log "[INSTALL] Expand-Archive failed: $($_.Exception.Message)" $C.Yellow
        }
    }
    if (-not $extractOk) {
        $sevenZ = $null
        foreach ($p in @("C:\Program Files\7-Zip\7z.exe","C:\Program Files (x86)\7-Zip\7z.exe","$env:LOCALAPPDATA\Programs\7-Zip\7z.exe")) {
            if (Test-Path $p) { $sevenZ = $p; break }
        }
        if (-not $sevenZ) {
            $search = Get-ChildItem -Path "C:\","D:\" -Filter "7z.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($search) { $sevenZ = $search.FullName }
        }
        if ($sevenZ) {
            Write-Log "[INSTALL] Trying 7-Zip fallback..." $C.Yellow
            try {
                & $sevenZ x $xapkPath -o"$installTemp" -y | Out-Null
                if ($LASTEXITCODE -eq 0) { $extractOk = $true }
            } catch {
                Write-Log "[INSTALL] 7-Zip failed: $($_.Exception.Message)" $C.Yellow
            }
        } else {
            Write-Log "[INSTALL] 7-Zip not found on system" $C.Yellow
        }
    }
    if (-not $extractOk) { Write-Log "[INSTALL] All extraction methods failed!" $C.Red; exit 1 }
    Write-Log "[INSTALL] Extraction complete" $C.Green
    return $installTemp
}

function Find-APKs($dir) {
    $items = Get-ChildItem -Path $dir -Filter "*.apk" | Sort-Object Length -Descending
    if (-not $items -or $items.Count -lt 3) {
        Write-Log "[INSTALL] Not enough APK files found in XAPK!" $C.Red
        exit 1
    }
    $rawAssets = $items | Where-Object { $_.Length -gt 1GB } | Select-Object -First 1
    $base = $items | Where-Object { $_.Length -gt 100MB -and $_.Length -lt 200MB } | Select-Object -First 1
    $config = $items | Where-Object { $_.Length -gt 30MB -and $_.Length -lt 100MB } | Select-Object -First 1
    if (-not $base -or -not $rawAssets -or -not $config) {
        $sorted = $items | Sort-Object Length -Descending
        $rawAssets = $sorted[0]; $base = $sorted[1]; $config = $sorted[2]
    }
    Write-Log "[INSTALL] APKs: base=$($base.Name) / raw=$($rawAssets.Name) / config=$($config.Name)" $C.Cyan
    return @{ base = Get-ShortPath $base.FullName; raw = Get-ShortPath $rawAssets.FullName; config = Get-ShortPath $config.FullName }
}

function Install-GameOnVM($serial, $apks) {
    Write-Log "[INSTALL] Checking if already installed on $serial..." $C.Cyan
    $pkg = & $adb -s $serial shell pm list packages com.lilithgame.roc.gp 2>$null
    if ($pkg -match "com.lilithgame.roc.gp") {
        Write-Log "[INSTALL] Already installed on $serial" $C.Green
        return $true
    }
    Write-Log "[INSTALL] Installing on $serial..." $C.Yellow
    Write-Log "[INSTALL] HDD: may take 5-15 min, patience..." $C.Dim

    for ($attempt = 1; $attempt -le 3; $attempt++) {
        Write-Log "[INSTALL] Attempt $attempt/3..." $C.Cyan
        $installJob = Start-Job -ScriptBlock {
            param($a, $s, $b, $r, $c)
            & $a -s $s install-multiple "$b" "$r" "$c"
        } -ArgumentList $adb, $serial, $apks.base, $apks.raw, $apks.config

        $elapsed = 0
        while ($installJob.State -eq 'Running') {
            Start-Sleep 15; $elapsed += 15
            Write-Host "." -NoNewline -ForegroundColor $C.Dim
            if ($elapsed % 120 -eq 0) { & $adb -s $serial shell echo keepalive 2>&1 | Out-Null }
        }
        Write-Host ""
        Receive-Job $installJob | Out-Null; Remove-Job $installJob

        $pkg = & $adb -s $serial shell pm list packages com.lilithgame.roc.gp 2>$null
        if ($pkg -match "com.lilithgame.roc.gp") {
            Write-Log "[INSTALL] Install verified on $serial" $C.Green
            return $true
        }
        if ($attempt -lt 3) {
            Write-Log "[INSTALL] Attempt $attempt failed, retrying..." $C.Yellow
            Start-Sleep 10
        }
    }
    Write-Log "[INSTALL] Install FAILED on $serial after 3 attempts" $C.Red
    return $false
}

# ============================================================
# MAIN FLOW
# ============================================================
Write-Host "============================================" -ForegroundColor $C.Yellow
Write-Host "  ROK Auto Installer" -ForegroundColor $C.Yellow
Write-Host "============================================" -ForegroundColor $C.Yellow

Write-Log "  Mode: $Mode, VM $($VMIndex + 1) (MEmu_$($StartVM + $VMIndex))" $C.Cyan

$isAlias = $MasterEmail -ne "" -and $AliasSuffix -gt 0
$serial = $null

# Global try/catch to log any error and keep the job alive for debugging
try {

# ---- INSTALL PHASE (if mode is Install or InstallLogin) ----
if ($Mode -eq "Install" -or $Mode -eq "InstallLogin") {
    if ($ApkBase -and $ApkRaw -and $ApkConfig) {
        Write-Log "[INSTALL] Using pre-extracted APKs from menu" $C.Cyan
        $apks = @{ base = $ApkBase; raw = $ApkRaw; config = $ApkConfig }
        $cleanupExtract = $false
    } else {
        $xapkPath = Find-XAPK
        $extractDir = Extract-XAPK $xapkPath
        $apks = Find-APKs $extractDir
        $cleanupExtract = $true
    }

    if (-not $SkipVMStart) {
        $vmName = "MEmu_$($StartVM + $VMIndex)"
        Write-Log "[INSTALL] Starting $vmName..." $C.Cyan
        & $memu start -n $vmName 2>&1 | Out-Null
        Start-Sleep 5
    }

    $serial = Wait-ForADB ($StartVM - 1 + $VMIndex) 120
    if (-not $serial) { Write-Log "FATAL: ADB not available for install" $C.Red; exit 1 }

    Write-Log "[INSTALL] Connected: $serial" $C.Green
    $installOk = Install-GameOnVM $serial $apks
    if ($cleanupExtract) { Remove-Item -Path $extractDir -Recurse -Force -ErrorAction SilentlyContinue }

    if (-not $installOk) {
        Write-Log "[INSTALL] Game installation FAILED" $C.Red
        exit 1
    }

    if ($Mode -eq "Install") {
        Write-Log "[INSTALL] Game installed successfully! Exiting (Install mode)" $C.Green
        exit 0
    }
    Write-Log "[INSTALL] Game installed, proceeding to login..." $C.Green
}

if ($isAlias) {
    Write-Log "  Alias mode: $Email (master: $MasterEmail, suffix: +$AliasSuffix)" $C.Cyan
}

# ---- START VM (unless SkipVMStart or already started by install) ----
if (-not $serial) {
    if (-not $SkipVMStart) {
        Start-VM $VMIndex
    }
    $serial = Wait-ForADB $VMIndex 120
    if (-not $serial) { Write-Log "FATAL: ADB not available" $C.Red; exit 1 }
    Write-Log "Connected: $serial" $C.Green
} else {
    Write-Log "Already connected: $serial (skipping VM start)" $C.Dim
}

$size = Get-ScreenSize $serial
Write-Log "Screen: $($size.W)x$($size.H)" $C.Cyan

# Try to force resolution (may not work on all emulators)
Write-Log "Attempting ${EmulResW}x${EmulResH} @ ${EmulDPI}dpi..." $C.Cyan
$null = & $adb -s $serial shell wm size "${EmulResW}x${EmulResH}" 2>&1
$null = & $adb -s $serial shell wm density $EmulDPI 2>&1
Wait 2000

# Re-check size
$size = Get-ScreenSize $serial
Write-Log "Effective screen: $($size.W)x$($size.H)" $C.Cyan

# ---- STEP 1: Fresh start ----
Set-AndroidID $serial
Clear-AppData $serial

# ---- Start captcha watcher (runs in background the whole time) ----
$watcherScript = Join-Path $EngineDir "captcha_watcher.py"
# Copy to temp to avoid Arabic path issues
$watcherTemp = Join-Path $tempDir "captcha_watcher.py"
Copy-Item $watcherScript $watcherTemp -Force
Write-Log "[WATCHER] Starting captcha watcher..." $C.Cyan
$watcherProc = Start-Process python -ArgumentList @("`"$watcherTemp`"", "--serial", $serial) -PassThru -WindowStyle Hidden
Write-Log "[WATCHER] PID: $($watcherProc.Id)" $C.Dim

# Watcher restart function
function Restart-Watcher {
    if ($watcherProc.HasExited) {
        Write-Log "[WATCHER] Watcher died! Restarting..." $C.Yellow
        $script:watcherProc = Start-Process python -ArgumentList @("`"$watcherTemp`"", "--serial", $serial) -PassThru -WindowStyle Hidden
        Write-Log "[WATCHER] New PID: $($watcherProc.Id)" $C.Dim
    }
}

# ---- STEP 2: Launch game ----
Write-Log "[LAUNCH] Starting Rise of Kingdoms..." $C.Cyan
Key $serial "KEYCODE_WAKEUP"
Wait 1000
$null = & $adb -s $serial shell am start -n "com.lilithgame.roc.gp/com.harry.engine.MainActivity" 2>&1

# ---- STEP 3: Wait for EULA ----
Write-Log "[EULA] Waiting..." $C.Cyan
$eulaFound = $false
$elapsed = 0
while ($elapsed -lt 45) {
    $f = GetFocus $serial
    if ($f -match "UserAgreement") { $eulaFound = $true; break }
    Wait 3000; $elapsed += 3
}
if ($eulaFound) {
    Write-Log "[EULA] Found, scrolling..." $C.Cyan
    Swipe $serial 320 380 320 100 500; Wait 1000
    Swipe $serial 320 380 320 100 500; Wait 1000
    Swipe $serial 320 380 320 100 500; Wait 1000
    Write-Log "[EULA] Tapping Accept..." $C.Cyan
    Tap $serial 320 409; Wait 3000
    $f = GetFocus $serial
    if ($f -match "MainActivity") { Write-Log "  EULA accepted" $C.Green }
} else {
    Write-Log "  EULA not found, continuing" $C.Dim
}

# ---- STEP 4: Wait for game load ----
Write-Log "[LOAD] Waiting for MainActivity..." $C.Cyan
Wait-ForActivity $serial "MainActivity" 60

# ---- STEP 5: Dismiss hint update popup ----
Write-Log "[POPUP] Checking for hint update..." $C.Cyan
Wait 10000
$xml = DumpUI $serial
if ($xml -match "unitySurfaceView|action_bar_root") {
    Write-Log "  Game surface detected" $C.Green
}
Tap $serial 320 240; Wait 3000

# ---- STEP 6: Tap to Start (center) ----
Write-Log "[START] Tapping center..." $C.Cyan
Tap $serial 320 240; Wait 3000

# ---- STEP 7: Launch LoginActivity via intent ----
Write-Log "[LOGIN] Launching login screen..." $C.Cyan
$null = & $adb -s $serial shell am start -a com.lilith.sdk.action.login 2>&1
Wait 5000

# ---- STEP 8: Wait for login modal ----
Write-Log "[LOGIN] Waiting for login dialog..." $C.Cyan
$loginReady = $false
for ($i = 0; $i -lt 15; $i++) {
    $xml = DumpUI $serial
    if ($xml -match "emailEditText|submitCodeButton|modalPanel") { $loginReady = $true; break }
    Wait 2000
}
if (-not $loginReady) {
    $f = GetFocus $serial
    Write-Log "  Current activity: $f" $C.Yellow
    $null = & $adb -s $serial shell am start -a com.lilith.sdk.action.login 2>&1
    Wait 5000
}

# ---- STEP 9: Enter email ----
Write-Log "[LOGIN] Entering email..." $C.Cyan
# Email field at [208,161][433,191] -> center (320,176)
Tap $serial 320 176; Wait 1000
Text $serial $Email; Wait 2000

# ---- STEP 10: Get latest email ID and request code ----
Restart-Watcher
$actualEmailForCode = $Email
$actualPassForCode = $AppPassword
$actualProvider = "gmail"

if ($isAlias) {
    $actualEmailForCode = $MasterEmail
    $actualPassForCode = $MasterPass
    $actualProvider = $Provider
}

if ($FetchEmail -ne "") {
    $actualEmailForCode = $FetchEmail
    $actualPassForCode = $FetchPass
    $actualProvider = $FetchProvider
}

$aliasFilter = ""
if ($isAlias) { $aliasFilter = $Email }

# ---- STEP 10: Determine code mode ----
if ($FetchMode -eq "sms") {
    $codeMode = "manual"
    Write-Log "  Code mode: manual (from menu)" $C.Green
} elseif ($FetchMode -eq "imap") {
    $codeMode = "imap"
    Write-Log "  Code mode: imap (from menu)" $C.Green
} else {
    # Running as background job - skip Read-Host (it crashes in Start-Job)
    $codeMode = "imap"
    Write-Log "  Code mode: imap (auto, background job)" $C.Green
}

Write-Log "[LOGIN] Recording timestamp before code request..." $C.Cyan

# Stagger code requests: VM1 waits 0s, VM2 waits 30s, VM3 waits 60s, etc.
$staggerDelay = $VMIndex * 30
if ($staggerDelay -gt 0) {
    Write-Log "  Stagger delay: ${staggerDelay}s (VM$($VMIndex + 1) of batch)" $C.Dim
    Wait ($staggerDelay * 1000)
}

$requestTimestamp = IMAP-GetTimestamp
Write-Log "  Request timestamp: $requestTimestamp" $C.Dim

Write-Log "[LOGIN] Tapping Verification Code Login..." $C.Cyan
# Button at [208,249][433,282] -> center (320,265)
Tap $serial 320 265; Wait 5000

# ---- STEP 10b: Captcha handled by background watcher ----
$solveScript = Join-Path $EngineDir "solve_captcha.py"
Wait 5000

# ---- STEP 11: Wait for code input screen ----
Write-Log "[CODE] Waiting for code input..." $C.Cyan
$codeReady = $false
for ($i = 0; $i -lt 20; $i++) {
    $xml = DumpUI $serial
    if ($xml -match "digitsInput|Verification Code") { $codeReady = $true; break }
    Wait 3000
}
if (-not $codeReady) {
    Write-Log "  Code screen not found, trying email tap again" $C.Yellow
    Tap $serial 320 176; Wait 1000; Text $serial $Email; Wait 1000
    Tap $serial 320 265; Wait 10000
}

# ---- STEP 12: Fetch verification code ----
$code = $null

if ($codeMode -eq "manual") {
    Write-Log "" $C.Yellow
    Write-Log "========================================" $C.Yellow
    Write-Log "  MANUAL CODE for VM$($VMIndex + 1)" $C.Yellow
    Write-Log "  Email: $Email" $C.Cyan
    Write-Log "  Check your inbox for the 6-digit code" $C.Cyan
    Write-Log "========================================" $C.Yellow
    $needFile = Join-Path $OriginalDir "code_need_VM${VMIndex}.txt"
    $readyFile = Join-Path $OriginalDir "code_ready_VM${VMIndex}.txt"
    Remove-Item $needFile, $readyFile -ErrorAction SilentlyContinue
    "VM$VMIndex code sent - check email" | Out-File $needFile -Encoding ASCII
    Write-Log "[CODE] Wrote $needFile - waiting for code..." $C.Yellow
    for ($cw = 0; $cw -lt 120; $cw++) {
        if (Test-Path $readyFile) {
            $code = (Get-Content $readyFile -Raw).Trim()
            Remove-Item $needFile, $readyFile -ErrorAction SilentlyContinue
            Write-Log "[CODE] Code read from file: $code" $C.Green
            break
        }
        Wait 5000
    }
} else {
    Write-Log "[CODE] Fetching via IMAP..." $C.Cyan
    Write-Log "  Request timestamp: $requestTimestamp" $C.Dim
    Write-Log "  Alias filter: $aliasFilter" $C.Dim
    # Retry loop: try up to 15 times (total ~4 min)
    for ($s = 0; $s -lt 15; $s++) {
        if ($s -eq 0) {
            # Stagger the IMAP wait too
            $imapWait = 30000
            Write-Log "  Initial ${imapWait}ms wait for delivery..." $C.Dim
            Wait $imapWait
        }
        if ($actualProvider -eq "hotmail") {
            $code = IMAP-FetchHotmail $actualEmailForCode $actualPassForCode $requestTimestamp $aliasFilter
        } else {
            $code = IMAP-FetchCode $actualEmailForCode $actualPassForCode $requestTimestamp $actualProvider $aliasFilter
        }
        if ($code) {
            Write-Log "[CODE] Code fetched: $code" $C.Green
            break
        }
        Write-Log "  Code not found yet, retrying... ($($s+1)/15)" $C.Dim
        Wait 15000
    }
    if (-not $code) {
        Write-Log "[CODE] IMAP failed, using file protocol for manual code..." $C.Yellow
        $needFile = Join-Path $OriginalDir "code_need_VM${VMIndex}.txt"
        $readyFile = Join-Path $OriginalDir "code_ready_VM${VMIndex}.txt"
        Remove-Item $needFile, $readyFile -ErrorAction SilentlyContinue
        "VM$VMIndex IMAP failed - enter code manually" | Out-File $needFile -Encoding ASCII
        Write-Log "[CODE] Wrote $needFile - waiting for code..." $C.Yellow
        for ($cw = 0; $cw -lt 120; $cw++) {
            if (Test-Path $readyFile) {
                $code = (Get-Content $readyFile -Raw).Trim()
                Remove-Item $needFile, $readyFile -ErrorAction SilentlyContinue
                Write-Log "[CODE] Code read from file: $code" $C.Green
                break
            }
            Wait 5000
        }
    }
}
if (-not $code) {
    Write-Log "[CODE] No code available. Exiting." $C.Red
    exit 1
}
Write-Log "  Code: $code" $C.Green

# ---- STEP 13: Enter code ----
Restart-Watcher
Write-Log "[CODE] Entering code..." $C.Cyan
for ($ci = 0; $ci -lt 10; $ci++) { Key $serial "KEYCODE_DEL"; Wait 100 }
Wait 500
Tap $serial 235 255; Wait 500
for ($ci = 0; $ci -lt $code.Length; $ci++) {
    Text $serial $code[$ci]; Wait 400
}
Write-Log "[CODE] Code entered, waiting for verification..." $C.Yellow
Wait 15000

# ---- STEP 14: Check for errors after code entry (captcha handled by watcher) ----
Write-Log "[CODE] Checking for errors after code entry..." $C.Cyan
for ($cap = 0; $cap -lt 5; $cap++) {
    $xml = DumpUI $serial
    if ($xml -match "error|Error|INVALID|invalid|expired|Code is incorrect") {
        Write-Log "[ERROR] Code error detected!" $C.Red
        Tap $serial 320 300; Wait 2000
    }
    $f = GetFocus $serial
    if ($f -match "MainActivity") { break }
    Wait 3000
}

# ---- STEP 15: Wait for login to process ----
Write-Log "[LOGIN] Waiting for login to process..." $C.Cyan
for ($i = 0; $i -lt 40; $i++) {
    $f = GetFocus $serial
    Write-Log "  [$i] Focus: $f" $C.Dim
    if ($f -match "MainActivity" -and $i -gt 3) { break }
    if ($f -match "LoginActivity" -and $i -gt 15) {
        Write-Log "[LOGIN] Still on LoginActivity, checking for errors..." $C.Yellow
        $xml = DumpUI $serial
        if ($xml -match "error|Error|INVALID|invalid|expired") {
            Write-Log "[LOGIN] Error detected in UI" $C.Red
        }
    }
    Wait 3000
}
Write-Log "[LOGIN] Login submitted!" $C.Green

# ---- STEP 16: Wait for MainActivity (captcha handled by watcher) ----
Write-Log "[POST] Waiting for MainActivity..." $C.Cyan
$mainFound = $false
for ($s = 0; $s -lt 120; $s++) {
    $f = GetFocus $serial
    Write-Log "  [$s] Activity: $f" $C.Dim
    if ($f -match "MainActivity") { $mainFound = $true; break }
    $xml = DumpUI $serial
    if ($xml -match "error|Error|INVALID|invalid|expired|fail|Fail") {
        Write-Log "[ERROR] Error detected in UI!" $C.Red
        Tap $serial 320 300; Wait 2000
    }
    Wait 3000
}

if (-not $mainFound) {
    Write-Log "[POST] MainActivity not found after 240s" $C.Yellow
}

# ---- STEP 17: Wait for game update and city load ----
Restart-Watcher
Write-Log "[GAME] Checking for update dialog..." $C.Cyan

# Find and tap CONFIRM button
$confirmTapped = $false
for ($i = 0; $i -lt 30; $i++) {
    $city = Check-City $serial
    if ($city.IsCity) {
        Write-Log "[GAME] City already loaded! (score=$($city.Score))" $C.Green
        $confirmTapped = $true
        break
    }
    $btn = Detect-Button $serial
    if ($btn) {
        Write-Log "[GAME] CONFIRM found! Tapping ($($btn.X),$($btn.Y))..." $C.Yellow
        Tap $serial $btn.X $btn.Y
        $confirmTapped = $true
        break
    }
    $splash = Check-Splash $serial
    if ($splash.Found) {
        Write-Log "[GAME] Splash screen! Tapping..." $C.Yellow
        Tap $serial 320 380
        Wait 3000
        break
    }
    $tap = Check-TapScreen $serial
    if ($tap.Found) {
        Write-Log "[GAME] Tap-anywhere! Tapping..." $C.Yellow
        Tap $serial 320 240
        Wait 3000
        break
    }
    Wait 2000
}

# Wait for download/update to complete (poll for city arrival)
if ($confirmTapped -and -not $city.IsCity) {
    Write-Log "[GAME] Waiting for download (checking every 5s)..." $C.Dim
    for ($w = 0; $w -lt 18; $w++) {
        Wait 5000
        $cityCheck = Check-City $serial
        if ($cityCheck.IsCity) {
            Write-Log "[GAME] City loaded! (score=$($cityCheck.Score))" $C.Green
            break
        }
        Write-Log "." $C.Dim -NoNewline
    }
    Write-Log ""
} elseif ($confirmTapped) {
    Write-Log "[GAME] City already loaded, no wait needed." $C.Green
}

# ---- STEP 18: Final check ----
$f = GetFocus $serial
Write-Log "" $C.Green
Write-Log "===================" $C.Green
if ($mainFound) { 
    Write-Log "[DONE] MainActivity reached!" $C.Green
    Write-Log "  E2E Login: SUCCESS" $C.Green
} else { 
    Write-Log "[DONE] Login submitted (game may still be loading)" $C.Yellow
    Write-Log "  E2E Login: PARTIAL" $C.Yellow
}
Write-Log "  Activity: $f" $C.Cyan
Write-Log "  Screen size: $($size.W)x$($size.H)" $C.Cyan
Write-Log "===================" $C.Green

} catch {
    Write-Log "========================================" $C.Red
    Write-Log "  FATAL ERROR in VM$($VMIndex + 1)" $C.Red
    Write-Log "========================================" $C.Red
    Write-Log "  Message: $($_.Exception.Message)" $C.Red
    Write-Log "  Line: $($_.InvocationInfo.ScriptLineNumber)" $C.Red
    Write-Log "  Position: $($_.InvocationInfo.OffsetInLine)" $C.Red
    Write-Log "  Stack: $($_.ScriptStackTrace)" $C.Dim
    Write-Log "========================================" $C.Red
    # Wait a bit so logs can be captured
    Start-Sleep 10
} finally {
    # Ensure watcher is always stopped
    if ($watcherProc -and -not $watcherProc.HasExited) {
        Write-Log "[WATCHER] Cleaning up watcher..." $C.Dim
        Stop-Process -Id $watcherProc.Id -Force -ErrorAction SilentlyContinue
    }
}
