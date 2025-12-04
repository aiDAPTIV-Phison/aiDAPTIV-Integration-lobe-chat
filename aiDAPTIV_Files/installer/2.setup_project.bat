@echo off
setlocal EnableDelayedExpansion

:: Check for Administrator privileges
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Administrator privileges required. Restarting...
    powershell -Command "Start-Process '%~0' -Verb RunAs"
    exit /b
)

echo ==========================================
echo   Step 2: Project Setup
echo ==========================================

set "PROJECT_ROOT=%~dp0..\.."
pushd "%PROJECT_ROOT%"

echo.
echo [1/3] Verifying Prerequisites...
node -v >nul 2>&1
if %errorlevel% equ 0 (
    for /f "tokens=*" %%i in ('node -v') do echo Node.js found: %%i
) else (
    echo [ERROR] Node.js not found. Please run '1.install_prerequisites.bat' first.
    pause
    exit /b
)

docker -v >nul 2>&1
if %errorlevel% equ 0 (
    echo Docker found.
) else (
    echo [ERROR] Docker not found. Please run '1.install_prerequisites.bat' first and RESTART your computer.
    pause
    exit /b
)

echo.
echo [2/3] Installing pnpm...
call npm install -g pnpm
if %errorlevel% neq 0 (
    echo [ERROR] Failed to install pnpm. Ensure Node.js is in PATH.
    pause
    exit /b
)

echo.
echo [3/3] Extracting Release Files...
set "RELEASE_ZIP=%~dp0release.zip"
if exist "!RELEASE_ZIP!" (
    echo Cleaning up old files...
    if exist ".next" rmdir /s /q ".next"
    if exist "node_modules" rmdir /s /q "node_modules"

    echo Extracting release.zip to project root...
    tar -xvf "!RELEASE_ZIP!"
    if !errorlevel! equ 0 (
        echo Extraction complete.
    ) else (
        echo [ERROR] Failed to extract release.zip.
        pause
        exit /b
    )
) else (
    echo [WARNING] release.zip not found in %~dp0. Skipping extraction.
)

echo.
echo ==========================================
echo Setup complete.
echo You can now run 'Start_Dev.bat' or 'Demo_start.bat'.
pause
