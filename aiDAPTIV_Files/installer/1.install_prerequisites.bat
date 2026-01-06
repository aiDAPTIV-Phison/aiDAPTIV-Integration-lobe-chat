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
cd /d "%~dp0"
::pushd "%~dp0"

echo ==========================================
echo   Step 1: Install Prerequisites
echo ==========================================
echo Current Directory: %CD%
echo Script Path: %~dp0
echo.

set "NEEDS_RESTART=0"

echo [1/3] Checking System Components (WSL ^& Hyper-V)...

::: Check WSL (enable only when disabled)
set "WSL_STATE="
for /f "tokens=2 delims=: " %%i in ('dism /online /Get-FeatureInfo /featurename:Microsoft-Windows-Subsystem-Linux 2^>nul ^| findstr /C:"State :"') do set "WSL_STATE=%%i"
if /I "!WSL_STATE!"=="Enabled" (
    echo WSL is already enabled.
) else (
    echo Enabling Windows Subsystem for Linux...
    dism /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
    if %errorlevel% equ 0 (
        set "NEEDS_RESTART=1"
        echo WSL enabled successfully.
    ) else (
        echo [WARNING] Failed to enable WSL. Error code: %errorlevel%
    )
)

::: Update WSL (best effort, continue on error)
echo Updating WSL...
start /wait "" wsl --update
echo WSL update process finished.

::: Check Virtual Machine Platform (enable only when disabled)
set "VMP_STATE="
for /f "tokens=2 delims=: " %%i in ('dism /online /Get-FeatureInfo /featurename:VirtualMachinePlatform 2^>nul ^| findstr /C:"State :"') do set "VMP_STATE=%%i"
if /I "!VMP_STATE!"=="Enabled" (
    echo Virtual Machine Platform is already enabled.
) else (
    echo Enabling Virtual Machine Platform...
    dism /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
    if %errorlevel% equ 0 (
        set "NEEDS_RESTART=1"
        echo Virtual Machine Platform enabled successfully.
    ) else (
        echo [WARNING] Failed to enable Virtual Machine Platform. Error code: %errorlevel%
    )
)

::: Check Hyper-V (skip gracefully if not available)
set "HYPERV_STATE="
for /f "tokens=2 delims=: " %%i in ('dism /online /Get-FeatureInfo /featurename:Microsoft-Hyper-V 2^>nul ^| findstr /C:"State :"') do set "HYPERV_STATE=%%i"
if not defined HYPERV_STATE (
    echo [INFO] Hyper-V feature is not available on this edition. Skipping.
) else (
    if /I "!HYPERV_STATE!"=="Enabled" (
        echo Hyper-V is already enabled.
    ) else (
        echo Enabling Hyper-V...
        dism /online /enable-feature /featurename:Microsoft-Hyper-V /all /norestart
        if %errorlevel% equ 0 (
            set "NEEDS_RESTART=1"
            echo Hyper-V enabled successfully.
        ) else (
            echo [INFO] Hyper-V could not be enabled. Error code: %errorlevel%.
            echo This may be expected on Windows Home edition. Skipping.
        )
    )
)

::: Enable Long Paths (safe no-pipe version)
echo Checking Long Paths Support...
set "LP_ENABLED=0"
for /f "tokens=3 skip=1" %%z in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v LongPathsEnabled 2^>nul') do (
    if "%%z"=="0x1" set "LP_ENABLED=1"
)
if "%LP_ENABLED%"=="1" (
    echo Long Paths Support is already enabled.
) else (
    echo Enabling Long Paths Support...
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v LongPathsEnabled /t REG_DWORD /d 1 /f >nul 2>&1
    if !errorlevel! equ 0 (
        echo Long Paths Support enabled.
    ) else (
        echo [WARNING] Failed to enable Long Paths Support.
    )
)

echo [2/3] Checking Node.js...
node -v >nul 2>&1
if %errorlevel% equ 0 (
    for /f "tokens=*" %%i in ('node -v') do echo Node.js is already installed: %%i
    goto :CheckDocker
)

echo Node.js not found. Installing...
echo Downloading Node.js installer from official website...

:: Detect architecture
set "NODE_ARCH=x64"
for /f "tokens=*" %%i in ('powershell -Command "(Get-WmiObject Win32_Processor).Architecture"') do set "ARCH_CODE=%%i"
if "%ARCH_CODE%"=="5" set "NODE_ARCH=x86"
if "%ARCH_CODE%"=="12" set "NODE_ARCH=arm64"

set "NODE_VERSION=24.11.0"
set "NODE_URL=https://nodejs.org/dist/v%NODE_VERSION%/node-v%NODE_VERSION%-%NODE_ARCH%.msi"
set "NODE_MSI=%TEMP%\node-v%NODE_VERSION%-%NODE_ARCH%.msi"

echo Node.js Version: %NODE_VERSION%
echo Architecture: %NODE_ARCH%
echo Download URL: %NODE_URL%

:: Download using PowerShell
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri '%NODE_URL%' -OutFile '%NODE_MSI%' -UseBasicParsing"
if %errorlevel% neq 0 (
    echo [ERROR] Failed to download Node.js installer. Error code: %errorlevel%
    echo Please check your internet connection and try again.
    exit /b 1
)

if not exist "%NODE_MSI%" (
    echo [ERROR] Node.js installer not found at %NODE_MSI%
    exit /b 1
)

echo Node.js installer downloaded successfully.
echo Installing Node.js...
echo Command: msiexec /i "%NODE_MSI%" /qn /norestart
start /wait "" msiexec /i "%NODE_MSI%" /qn /norestart
if %errorlevel% neq 0 (
    echo [ERROR] Node.js installation failed with error code %errorlevel%.
    del "%NODE_MSI%" >nul 2>&1
    exit /b 1
)

echo Node.js installed successfully.
set "NEEDS_RESTART=1"

:: Clean up downloaded installer
del "%NODE_MSI%" >nul 2>&1

:CheckDocker
echo [3/3] Checking Docker...
docker -v >nul 2>&1
if %errorlevel% equ 0 (
    echo Docker is already installed.
    goto :EndChecks
)

echo Docker not found. Installing...
echo Downloading Docker Desktop installer from official website...

:: Detect architecture for Docker Desktop
set "DOCKER_ARCH=amd64"
for /f "tokens=*" %%i in ('powershell -Command "(Get-WmiObject Win32_Processor).Architecture"') do set "ARCH_CODE=%%i"
if "%ARCH_CODE%"=="12" set "DOCKER_ARCH=arm64"

set "DOCKER_URL=https://desktop.docker.com/win/main/%DOCKER_ARCH%/Docker Desktop Installer.exe"
set "DOCKER_EXE=%TEMP%\Docker Desktop Installer.exe"

echo Architecture: %DOCKER_ARCH%
echo Download URL: %DOCKER_URL%

:: Download using PowerShell (PowerShell will handle URL encoding automatically)
powershell -NoProfile -ExecutionPolicy Bypass -Command "$url = '%DOCKER_URL%'; $outFile = '%DOCKER_EXE%'; Invoke-WebRequest -Uri $url -OutFile $outFile -UseBasicParsing"
if %errorlevel% neq 0 (
    echo [ERROR] Failed to download Docker Desktop installer. Error code: %errorlevel%
    echo Please check your internet connection and try again.
    exit /b 1
)

if not exist "%DOCKER_EXE%" (
    echo [ERROR] Docker Desktop installer not found at %DOCKER_EXE%
    exit /b 1
)

echo Docker Desktop installer downloaded successfully.
echo Installing Docker Desktop...
echo Command: "%DOCKER_EXE%" install --accept-license
start /wait "" "%DOCKER_EXE%" install --accept-license
if %errorlevel% neq 0 (
    echo [ERROR] Docker installation failed with error code %errorlevel%.
    del "%DOCKER_EXE%" >nul 2>&1
    exit /b 1
)

echo Docker Desktop installation finished.
set "NEEDS_RESTART=1"

:: Clean up downloaded installer
del "%DOCKER_EXE%" >nul 2>&1

:: echo Configuring Docker to start on login (Current User)...
:: reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "Docker Desktop" /t REG_SZ /d "\"C:\Program Files\Docker\Docker\Docker Desktop.exe\"" /f >nul 2>&1
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
::popd
exit /b 0

