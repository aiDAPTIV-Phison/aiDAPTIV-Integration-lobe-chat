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
echo   Step 1: Install Prerequisites
echo ==========================================

set "NEEDS_RESTART=0"

echo.
echo [1/3] Checking System Components (WSL ^& Hyper-V)...

:: Check WSL
dism /online /get-featureinfo /featurename:Microsoft-Windows-Subsystem-Linux | find "State : Enabled" >nul
if %errorlevel% neq 0 (
    echo Enabling Windows Subsystem for Linux...
    dism /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
    set "NEEDS_RESTART=1"
) else (
    echo WSL is already enabled.
)

:: Check Virtual Machine Platform
dism /online /get-featureinfo /featurename:VirtualMachinePlatform | find "State : Enabled" >nul
if %errorlevel% neq 0 (
    echo Enabling Virtual Machine Platform...
    dism /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
    set "NEEDS_RESTART=1"
) else (
    echo Virtual Machine Platform is already enabled.
)

:: Check Hyper-V (Might fail on Home edition, ignore errors)
dism /online /get-featureinfo /featurename:Microsoft-Hyper-V >nul 2>&1
if %errorlevel% equ 0 (
    dism /online /get-featureinfo /featurename:Microsoft-Hyper-V | find "State : Enabled" >nul
    if !errorlevel! neq 0 (
        echo Enabling Hyper-V...
        dism /online /enable-feature /featurename:Microsoft-Hyper-V /all /norestart
        set "NEEDS_RESTART=1"
    ) else (
        echo Hyper-V is already enabled.
    )
)

echo.
echo Checking Long Paths Support...
reg query "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v LongPathsEnabled 2>nul | find "0x1" >nul
if %errorlevel% neq 0 (
    echo Enabling Long Paths Support...
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v LongPathsEnabled /t REG_DWORD /d 1 /f
    echo Long Paths Support enabled.
) else (
    echo Long Paths Support is already enabled.
)

echo.
echo [2/3] Checking Node.js...
node -v >nul 2>&1
if %errorlevel% equ 0 (
    for /f "tokens=*" %%i in ('node -v') do echo Node.js is already installed: %%i
) else (
    echo Node.js not found. Installing...
    pushd "%~dp0"
    set "NODE_MSI="
    for %%f in (node-*.msi) do set "NODE_MSI=%%f"
    
    if defined NODE_MSI (
        echo Installing !NODE_MSI!...
        msiexec /i "!NODE_MSI!" /qn /norestart
        echo Node.js installed successfully.
        set "NEEDS_RESTART=1"
    ) else (
        echo [ERROR] Node.js installer (node-*.msi) not found in %~dp0
    )
    popd
)

echo.
echo [3/3] Checking Docker...
docker -v >nul 2>&1
if %errorlevel% equ 0 (
    echo Docker is already installed.
) else (
    echo Docker not found. Installing...
    pushd "%~dp0"
    set "DOCKER_EXE="
    for %%f in ("Docker Desktop Installer.exe") do set "DOCKER_EXE=%%f"
    
    if defined DOCKER_EXE (
        echo Installing Docker Desktop...
        start /wait "" "!DOCKER_EXE!" install --accept-license
        echo Docker Desktop installation finished.
        set "NEEDS_RESTART=1"
        
        echo Configuring Docker to start on login...
        reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "Docker Desktop" /t REG_SZ /d "\"C:\Program Files\Docker\Docker\Docker Desktop.exe\"" /f >nul 2>&1
        if !errorlevel! equ 0 (
            echo Docker set to auto-start successfully.
        ) else (
            echo [WARNING] Failed to set Docker auto-start registry key.
        )
    ) else (
        echo [ERROR] Docker installer (Docker Desktop Installer.exe) not found in %~dp0
    )
    popd
)

echo.
echo ==========================================
if "%NEEDS_RESTART%"=="1" (
    echo Installation complete. A SYSTEM RESTART IS REQUIRED.
    echo Please restart your computer, then run '2.setup_project.bat'.
    set /p "RESTART_NOW=Do you want to restart now? (Y/N) "
    if /i "!RESTART_NOW!"=="Y" (
        shutdown /r /t 0
    )
) else (
    echo Prerequisites are ready.
    echo You can now run '2.setup_project.bat'.
)

pause
