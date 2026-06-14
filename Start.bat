@echo off
chcp 65001 >nul
title KINGDOM ^& CO

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo  ============================================
    echo    KINGDOM BOTS ^& CO
    echo  ============================================
    echo.
    echo  [INFO] Please run as Administrator!
    echo.
    echo  Right-click Start.bat ^> Run as Administrator
    echo.
    pause
    exit /b
)

echo.
echo  ============================================
echo    KINGDOM BOTS ^& CO
echo  ============================================
echo.
echo  Loading KingdomCo.Engine...
echo.

set "BS=%TEMP%\kr_%RANDOM%.ps1"
echo $dll='%~dp0KingdomCo.Engine.dll' > "%BS%"
echo [Reflection.Assembly]::LoadFile($dll^)^|Out-Null >> "%BS%"
echo $p=[KingdomCo.Engine.Engine]::GetPassphrase(^) >> "%BS%"
echo $t=Join-Path $env:TEMP ('KR_'+[System.IO.Path]::GetRandomFileName(^)^) >> "%BS%"
echo New-Item -ItemType Directory -Path $t -Force^|Out-Null >> "%BS%"
echo [KingdomCo.Engine.Engine]::ExtractAll($p,$t) >> "%BS%"
echo Copy-Item $dll (Join-Path $t 'KingdomCo.Engine.dll'^) -Force >> "%BS%"
echo $global:KR_PASSPHRASE=$p >> "%BS%"
echo try { . (Join-Path $t 'Launcher.ps1'^) } finally { Remove-Item $t -Recurse -Force } >> "%BS%"

echo  Running...
echo.
powershell -ExecutionPolicy Bypass -NoProfile -File "%BS%"
del "%BS%" >nul 2>&1
pause
