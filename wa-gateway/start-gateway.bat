@echo off
cd /d "%~dp0"
echo ========================================================
echo   Lucifax-PFS WhatsApp Gateway Microservice (Portable)
echo ========================================================

:: 1. Cek Node.js Portable di folder apk-tools\node
if exist "%~dp0apk-tools\node\node.exe" (
    set "NODE_BIN=%~dp0apk-tools\node\node.exe"
    echo [OK] Menggunakan Node.js Portable.
) else if exist "%~dp0apk-tools\node-v24.22.0-win-x64\node.exe" (
    set "NODE_BIN=%~dp0apk-tools\node-v24.22.0-win-x64\node.exe"
    echo [OK] Menggunakan Node.js Portable.
) else if exist "C:\Program Files\nodejs\node.exe" (
    set "NODE_BIN=C:\Program Files\nodejs\node.exe"
    echo [OK] Menggunakan Node.js di Program Files.
) else (
    set "NODE_BIN=node"
    echo [INFO] Menggunakan Node.js bawaan sistem komputer.
)

echo [INFO] Menjalankan server.js ...
echo ========================================================
"%NODE_BIN%" server.js
pause
