@echo off
setlocal EnableDelayedExpansion

:: ---------------------------------------------------------
:: 1. Administrator Privilege Check
:: ---------------------------------------------------------
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Administrator privileges required. Restarting...
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

:: ---------------------------------------------------------
:: 2. Logging Wrapper
:: ---------------------------------------------------------
:: If the first argument is "__LOG__", we are already inside the logging session.
if "%~1"=="__LOG__" goto :Main

set "LOG_FILE=%~dp0install_log.txt"
echo ==========================================
echo   Starting Installation (Admin Mode)
echo   Logs will be saved to: %LOG_FILE%
echo ==========================================

:: Re-run this script with "__LOG__" argument and use PowerShell to tee output
powershell -NoProfile -ExecutionPolicy Bypass -Command "& '%~f0' __LOG__ 2>&1 | Tee-Object -FilePath '%LOG_FILE%'; exit $LASTEXITCODE"
set "EXIT_CODE=%errorlevel%"

if %EXIT_CODE% neq 0 (
    echo [ERROR] Installation failed with exit code %EXIT_CODE%.
    echo Please check the log file for details:
    echo %LOG_FILE%
    pause
) else (
    echo Installation finished successfully.
    echo Log saved to: %LOG_FILE%
    pause
)
exit /b %EXIT_CODE%

:Main
:: ---------------------------------------------------------
:: 3. Main Installation Logic
:: ---------------------------------------------------------

:: Ensure we are in the script's directory
pushd "%~dp0"

echo ==========================================
echo   Step 1: Install Prerequisites
echo ==========================================
echo Current Directory: %CD%
echo Script Path: %~dp0
echo.

set "NEEDS_RESTART=0"

echo [1/3] Checking System Components (WSL ^& Hyper-V)...

:: Check WSL
echo Checking WSL status...
dism /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
if %errorlevel% equ 0 (
    echo WSL enabled or already active.
    set "NEEDS_RESTART=1"
) else (
    echo [WARNING] Failed to enable WSL. Error code: %errorlevel%
)

:: Update WSL to avoid prompt after restart
echo Updating WSL...
wsl --update
if %errorlevel% equ 0 (
    echo WSL updated successfully.
) else (
    echo [WARNING] Failed to update WSL.
)

:: Check Virtual Machine Platform
echo Checking Virtual Machine Platform status...
dism /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
if %errorlevel% equ 0 (
    echo Virtual Machine Platform enabled or already active.
    set "NEEDS_RESTART=1"
) else (
    echo [WARNING] Failed to enable Virtual Machine Platform. Error code: %errorlevel%
)

:: Check Hyper-V
echo Checking Hyper-V status...
:: Try to enable Hyper-V directly. If it's not available (Home edition), it will fail gracefully.
dism /online /enable-feature /featurename:Microsoft-Hyper-V /all /norestart
if %errorlevel% equ 0 (
    echo Hyper-V enabled or already active.
    set "NEEDS_RESTART=1"
) else (
    echo [INFO] Hyper-V could not be enabled. Error code: %errorlevel%.
    echo This is expected on Windows Home edition. Skipping.
)

:CheckLongPaths
echo Checking Long Paths Support...
reg query "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v LongPathsEnabled 2>nul | find "0x1" >nul
if %errorlevel% neq 0 (
    echo Enabling Long Paths Support...
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v LongPathsEnabled /t REG_DWORD /d 1 /f
    echo Long Paths Support enabled.
) else (
    echo Long Paths Support is already enabled.
)

echo [2/3] Checking Node.js...
node -v >nul 2>&1
if %errorlevel% equ 0 (
    for /f "tokens=*" %%i in ('node -v') do echo Node.js is already installed: %%i
    goto :CheckDocker
)

echo Node.js not found. Installing...
set "NODE_MSI="
for %%f in (node-*.msi) do set "NODE_MSI=%%~f"

if not defined NODE_MSI (
    echo [ERROR] Node.js installer node-*.msi not found in %~dp0
    echo Files in current directory:
    dir /b
    exit /b 1
)

echo Installing !NODE_MSI!...
echo Command: msiexec /i "!NODE_MSI!" /qb /norestart
start /wait "" msiexec /i "!NODE_MSI!" /qb /norestart
if %errorlevel% neq 0 (
    echo [ERROR] Node.js installation failed with error code %errorlevel%.
    exit /b 1
)

echo Node.js installed successfully.
set "NEEDS_RESTART=1"

:CheckDocker
echo [3/3] Checking Docker...
docker -v >nul 2>&1
if %errorlevel% equ 0 (
    echo Docker is already installed.
    goto :EndChecks
)

echo Docker not found. Installing...
set "DOCKER_EXE="
for %%f in ("Docker Desktop Installer.exe") do set "DOCKER_EXE=%%~f"

if not defined DOCKER_EXE (
    echo [ERROR] Docker installer 'Docker Desktop Installer.exe' not found in %~dp0
    echo Files in current directory:
    dir /b
    exit /b 1
)

echo Installing Docker Desktop...
echo Command: "!DOCKER_EXE!" install --accept-license --quiet
start /wait "" "!DOCKER_EXE!" install --accept-license --quiet
if %errorlevel% neq 0 (
    echo [ERROR] Docker installation failed with error code %errorlevel%.
    exit /b 1
)

echo Docker Desktop installation finished.
set "NEEDS_RESTART=1"

echo Configuring Docker to start on login (All Users)...
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v "Docker Desktop" /t REG_SZ /d "\"C:\Program Files\Docker\Docker\Docker Desktop.exe\"" /f >nul 2>&1

if %errorlevel% equ 0 (
    echo Docker set to auto-start successfully.
) else (
    echo [WARNING] Failed to set Docker auto-start registry key.
)

echo Ensuring Docker Background Service is set to Auto-Start...
sc config com.docker.service start= auto >nul 2>&1

:EndChecks
echo ==========================================
if "%NEEDS_RESTART%"=="1" (
    echo Installation complete. A SYSTEM RESTART IS REQUIRED.
    echo Please restart your computer, then run '2.setup_project.bat'.
    
    :: We cannot interactively ask for restart inside a redirected log session easily
    :: because stdin is also redirected or not attached to console.
    :: So we just warn the user.
    echo [IMPORTANT] You must manually restart your computer now.
) else (
    echo Prerequisites are ready.
    echo You can now run '2.setup_project.bat'.
)

echo Done.
popd
exit /b 0
