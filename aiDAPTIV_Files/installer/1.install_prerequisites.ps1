<#
.SYNOPSIS
Step 1: Prerequisites Installation
.DESCRIPTION
Installs Node.js and Docker Desktop from local files.
Requires system restart after completion.
#>

$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Administrator privileges required. Restarting with elevated permissions..."
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "   Step 1: Install Prerequisites" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

$needsRestart = $false

Write-Host "`n[1/3] Checking System Components (WSL & Hyper-V)..." -ForegroundColor Yellow

# Check and Enable WSL
$wsl = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
if ($wsl.State -ne 'Enabled') {
    Write-Host "Enabling Windows Subsystem for Linux..." -ForegroundColor Cyan
    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -All -NoRestart
    $needsRestart = $true
}
else {
    Write-Host "WSL is already enabled." -ForegroundColor Green
}

# Check and Enable Virtual Machine Platform (Required for WSL 2)
$vmp = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform
if ($vmp.State -ne 'Enabled') {
    Write-Host "Enabling Virtual Machine Platform..." -ForegroundColor Cyan
    Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -All -NoRestart
    $needsRestart = $true
}
else {
    Write-Host "Virtual Machine Platform is already enabled." -ForegroundColor Green
}

# Check and Enable Hyper-V
try {
    $hyperv = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -ErrorAction SilentlyContinue
    if ($hyperv) {
        if ($hyperv.State -ne 'Enabled') {
            Write-Host "Enabling Hyper-V..." -ForegroundColor Cyan
            Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All -NoRestart
            $needsRestart = $true
        }
        else {
            Write-Host "Hyper-V is already enabled." -ForegroundColor Green
        }
    }
    else {
        Write-Warning "Hyper-V feature is not available on this edition of Windows. Skipping."
    }
}
catch {
    Write-Warning "Failed to check Hyper-V status. Skipping."
}

# Best-effort WSL update (do not stop on error)
Write-Host "Updating WSL (best effort)..." -ForegroundColor Cyan
try {
    wsl --update
    Write-Host "WSL updated successfully." -ForegroundColor Green
}
catch {
    Write-Warning "Failed to update WSL. Continuing..."
}

# Enable Long Paths (best effort)
Write-Host "Checking Long Paths support..." -ForegroundColor Cyan
try {
    $longPaths = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -ErrorAction SilentlyContinue
    if ($longPaths.LongPathsEnabled -ne 1) {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -Value 1 -Type DWord
        Write-Host "Long Paths enabled." -ForegroundColor Green
    }
    else {
        Write-Host "Long Paths already enabled." -ForegroundColor Green
    }
}
catch {
    Write-Warning "Failed to enable Long Paths. Continuing..."
}

Write-Host "`n[2/3] Checking Node.js..." -ForegroundColor Yellow
try {
    $nodeVersion = node -v
    Write-Host "Node.js is already installed: $nodeVersion" -ForegroundColor Green
}
catch {
    Write-Host "Node.js not found. Installing..." -ForegroundColor Cyan
    
    # Download Node.js installer from official website
    $nodeVersion = "24.11.0"  # Node.js 24 LTS version
    $nodeArch = "x64"  # Default to x64, can be enhanced to detect architecture
    
    # Detect architecture
    $arch = (Get-WmiObject Win32_Processor).Architecture
    if ($arch -eq 5) { $nodeArch = "x86" }
    elseif ($arch -eq 12) { $nodeArch = "arm64" }
    
    $nodeInstallerUrl = "https://nodejs.org/dist/v$nodeVersion/node-v$nodeVersion-$nodeArch.msi"
    $nodeInstallerPath = Join-Path $env:TEMP "node-v$nodeVersion-$nodeArch.msi"
    
    Write-Host "Downloading Node.js v$nodeVersion ($nodeArch) from official website..." -ForegroundColor Cyan
    Write-Host "URL: $nodeInstallerUrl" -ForegroundColor Gray
    
    try {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $nodeInstallerUrl -OutFile $nodeInstallerPath -UseBasicParsing
        $ProgressPreference = 'Continue'
        
        if (Test-Path $nodeInstallerPath) {
            Write-Host "Node.js installer downloaded successfully." -ForegroundColor Green
            Write-Host "Installing Node.js..." -ForegroundColor Cyan
            Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$nodeInstallerPath`" /qn /norestart" -Wait
            
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
            Write-Host "Node.js installed successfully." -ForegroundColor Green
            $needsRestart = $true
            
            # Clean up downloaded installer
            Remove-Item $nodeInstallerPath -Force -ErrorAction SilentlyContinue
        }
        else {
            Write-Error "Failed to download Node.js installer. File not found at $nodeInstallerPath"
        }
    }
    catch {
        Write-Error "Failed to download Node.js installer: $_"
        Write-Host "Please check your internet connection and try again." -ForegroundColor Red
        exit 1
    }
}

Write-Host "`n[3/3] Checking Docker..." -ForegroundColor Yellow
if (Get-Command "docker" -ErrorAction SilentlyContinue) {
    Write-Host "Docker is already installed." -ForegroundColor Green
}
else {
    Write-Host "Docker not found. Installing..." -ForegroundColor Cyan
    
    # Download Docker Desktop installer from official website
    # Detect architecture for Docker Desktop
    $dockerArch = "amd64"  # Default to amd64
    $arch = (Get-WmiObject Win32_Processor).Architecture
    if ($arch -eq 12) { $dockerArch = "arm64" }
    
    $dockerInstallerUrl = "https://desktop.docker.com/win/main/$dockerArch/Docker%20Desktop%20Installer.exe"
    $dockerInstallerPath = Join-Path $env:TEMP "Docker Desktop Installer.exe"
    
    Write-Host "Downloading Docker Desktop from official website..." -ForegroundColor Cyan
    Write-Host "URL: $dockerInstallerUrl" -ForegroundColor Gray
    
    try {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $dockerInstallerUrl -OutFile $dockerInstallerPath -UseBasicParsing
        $ProgressPreference = 'Continue'
        
        if (Test-Path $dockerInstallerPath) {
            Write-Host "Docker Desktop installer downloaded successfully." -ForegroundColor Green
            Write-Host "Installing Docker Desktop..." -ForegroundColor Cyan
            
            Start-Process -FilePath $dockerInstallerPath -ArgumentList "install --accept-license" -Wait
            Write-Host "Docker Desktop installation finished." -ForegroundColor Green
            $needsRestart = $true

            Write-Host "Configuring Docker to start on login (All Users)..." -ForegroundColor Cyan
            $DockerExe = "C:\Program Files\Docker\Docker\Docker Desktop.exe"
            if (Test-Path $DockerExe) {
                try {
                    # HKLM for all users auto-start
                    New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "Docker Desktop" -PropertyType String -Value "`"$DockerExe`"" -Force -ErrorAction Stop | Out-Null
                    Write-Host "Docker set to auto-start (HKLM) successfully." -ForegroundColor Green
                }
                catch {
                    Write-Warning "Failed to set Docker auto-start registry key in HKLM. Continuing..."
                }

                try {
                    Write-Host "Ensuring Docker Background Service is set to Auto-Start..." -ForegroundColor Cyan
                    sc.exe config com.docker.service start= auto | Out-Null
                    Write-Host "Docker background service set to Auto." -ForegroundColor Green
                }
                catch {
                    Write-Warning "Failed to set Docker service start mode. Continuing..."
                }
            }
            
            # Clean up downloaded installer
            Remove-Item $dockerInstallerPath -Force -ErrorAction SilentlyContinue
        }
        else {
            Write-Error "Failed to download Docker Desktop installer. File not found at $dockerInstallerPath"
        }
    }
    catch {
        Write-Error "Failed to download Docker Desktop installer: $_"
        Write-Host "Please check your internet connection and try again." -ForegroundColor Red
        exit 1
    }
}

Write-Host "`n==========================================" -ForegroundColor Cyan
if ($needsRestart) {
    Write-Warning "Installation complete. A SYSTEM RESTART IS REQUIRED."
    Write-Warning "Please restart your computer, then run '2.setup_project.ps1'."
    
    $choice = Read-Host "Do you want to restart now? (Y/N)"
    if ($choice -eq 'Y' -or $choice -eq 'y') {
        Restart-Computer
    }
}
else {
    Write-Host "Prerequisites are ready." -ForegroundColor Green
    Write-Host "You can now run '2.setup_project.ps1'." -ForegroundColor Cyan
}
Read-Host "Press Enter to exit..."
