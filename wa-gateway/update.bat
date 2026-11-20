@echo off
setlocal enabledelayedexpansion
title L-W.A.V.I.S Gateway Auto-Updater (Windows)
cd /d "%~dp0"

echo ========================================================
echo   L-W.A.V.I.S Gateway Auto-Updater (Windows)
echo ========================================================
echo.

set "REPO_BASE=https://raw.githubusercontent.com/Lucifer-pw/LUCIFAX-PFS/main/wa-gateway"

:: Dapatkan epoch timestamp untuk cache-busting
for /f "tokens=*" %%a in ('powershell -NoProfile -Command "[int][double]::Parse((Get-Date -UFormat %%s))"') do set "TIMESTAMP=%%a"
if "%TIMESTAMP%"=="" set "TIMESTAMP=%random%%random%"
set "CACHE_BUST=?t=%TIMESTAMP%"

:: Baca versi lokal saat ini
if exist version.json (
    for /f "tokens=*" %%v in ('powershell -NoProfile -Command "try { (Get-Content version.json -Raw | ConvertFrom-Json).gateway } catch { '' }"') do set "LOCAL_VER=%%v"
    echo [*] Versi lokal saat ini: v!LOCAL_VER!
) else (
    echo [*] Versi lokal: Belum terdeteksi
)

echo.
echo [*] Mengunduh file terbaru dari GitHub...
echo.

set "FILES=server.js autonomous-po-processor.js wavis-interactive-engine.js wavis-pdf-generator.js fiva-logo.bin firebase-adapter.js notification-dispatcher.js ocr-engine.js bank-slip-parser.js test-wavis-engine.js version.json update.sh"

for %%f in (%FILES%) do (
    <nul set /p="  [>] %%f ... "
    curl -sL -o "%%f" "%REPO_BASE%/%%f%CACHE_BUST%"
    if !errorlevel! equ 0 (
        echo [OK]
    ) else (
        echo [GAGAL]
    )
)

:: Download update.bat ke file sementara
<nul set /p="  [>] update.bat ... "
curl -sL -o "update.bat.tmp" "%REPO_BASE%/update.bat%CACHE_BUST%"
if !errorlevel! equ 0 (
    echo [OK]
) else (
    echo [GAGAL]
)

echo.
:: Baca versi baru dari version.json
if exist version.json (
    for /f "tokens=*" %%v in ('powershell -NoProfile -Command "try { (Get-Content version.json -Raw | ConvertFrom-Json).gateway } catch { '' }"') do set "NEW_VER=%%v"
    for /f "tokens=*" %%c in ('powershell -NoProfile -Command "try { (Get-Content version.json -Raw | ConvertFrom-Json).changelog } catch { '' }"') do set "CHANGELOG=%%c"
    echo ========================================================
    echo   [OK] Update Berhasil! Versi baru: v!NEW_VER!
    echo   Catatan: !CHANGELOG!
    echo ========================================================
)

:: Update file bat sendiri jika ada file baru
if exist "update.bat.tmp" (
    move /y "update.bat.tmp" "update.bat" >nul 2>&1
)

echo.
echo [*] Update selesai! Silakan jalankan kembali start-gateway.bat
echo [*] Tekan tombol apa saja untuk menutup jendela ini...
pause >nul
