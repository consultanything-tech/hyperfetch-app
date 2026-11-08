@echo off
setlocal enabledelayedexpansion

echo =======================================================
echo HyperFetch Chrome Native Messaging Host Registration
echo =======================================================

:: Resolve directory containing this script
set "SCRIPT_DIR=%~dp0"
set "MANIFEST_PATH=%SCRIPT_DIR%com.hyperfetch.native_host.json"

if not exist "%MANIFEST_PATH%" (
    echo [ERROR] Manifest not found at: %MANIFEST_PATH%
    exit /b 1
)

echo Registering manifest: %MANIFEST_PATH%

:: 1. Google Chrome
echo Registering for Google Chrome...
reg add "HKCU\Software\Google\Chrome\NativeMessagingHosts\com.hyperfetch.native_host" /ve /t REG_SZ /d "%MANIFEST_PATH%" /f >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo   [OK] HKCU\Software\Google\Chrome\NativeMessagingHosts\com.hyperfetch.native_host
) else (
    echo   [WARN] Failed to register Chrome native messaging host
)

reg add "HKCU\Software\Google\Chrome\NativeMessagingHosts\com.hyperfetch.native" /ve /t REG_SZ /d "%MANIFEST_PATH%" /f >nul 2>&1

:: 2. Microsoft Edge
echo Registering for Microsoft Edge...
reg add "HKCU\Software\Microsoft\Edge\NativeMessagingHosts\com.hyperfetch.native_host" /ve /t REG_SZ /d "%MANIFEST_PATH%" /f >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo   [OK] HKCU\Software\Microsoft\Edge\NativeMessagingHosts\com.hyperfetch.native_host
) else (
    echo   [WARN] Failed to register Edge native messaging host
)

reg add "HKCU\Software\Microsoft\Edge\NativeMessagingHosts\com.hyperfetch.native" /ve /t REG_SZ /d "%MANIFEST_PATH%" /f >nul 2>&1

:: 3. Brave Browser
echo Registering for Brave Browser...
reg add "HKCU\Software\BraveSoftware\Brave-Browser\NativeMessagingHosts\com.hyperfetch.native_host" /ve /t REG_SZ /d "%MANIFEST_PATH%" /f >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo   [OK] HKCU\Software\BraveSoftware\Brave-Browser\NativeMessagingHosts\com.hyperfetch.native_host
) else (
    echo   [WARN] Failed to register Brave native messaging host
)

reg add "HKCU\Software\BraveSoftware\Brave-Browser\NativeMessagingHosts\com.hyperfetch.native" /ve /t REG_SZ /d "%MANIFEST_PATH%" /f >nul 2>&1

echo.
echo Native Messaging Host registered successfully for all supported browsers.
exit /b 0
