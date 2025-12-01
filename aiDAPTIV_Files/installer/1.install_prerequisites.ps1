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
} else {
    Write-Host "WSL is already enabled." -ForegroundColor Green
}

# Check and Enable Virtual Machine Platform (Required for WSL 2)
$vmp = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform
if ($vmp.State -ne 'Enabled') {
    Write-Host "Enabling Virtual Machine Platform..." -ForegroundColor Cyan
    Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -All -NoRestart
    $needsRestart = $true
} else {
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
        } else {
            Write-Host "Hyper-V is already enabled." -ForegroundColor Green
        }
    } else {
         Write-Warning "Hyper-V feature is not available on this edition of Windows. Skipping."
    }
} catch {
    Write-Warning "Failed to check Hyper-V status. Skipping."
}

Write-Host "`n[2/3] Checking Node.js..." -ForegroundColor Yellow
try {
    $nodeVersion = node -v
    Write-Host "Node.js is already installed: $nodeVersion" -ForegroundColor Green
}
catch {
    Write-Host "Node.js not found. Installing..." -ForegroundColor Cyan
    $nodeInstaller = Get-ChildItem -Path $PSScriptRoot -Filter "node-*.msi" | Select-Object -First 1
    if ($nodeInstaller) {
        Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$($nodeInstaller.FullName)`" /qn /norestart" -Wait
        
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        Write-Host "Node.js installed successfully." -ForegroundColor Green
        $needsRestart = $true
    } else {
        Write-Error "Node.js installer (node-*.msi) not found in $PSScriptRoot"
    }
}

Write-Host "`n[3/3] Checking Docker..." -ForegroundColor Yellow
if (Get-Command "docker" -ErrorAction SilentlyContinue) {
    Write-Host "Docker is already installed." -ForegroundColor Green
} else {
    Write-Host "Docker not found. Installing..." -ForegroundColor Cyan
    $dockerInstaller = Get-ChildItem -Path $PSScriptRoot -Filter "Docker Desktop Installer.exe" | Select-Object -First 1
    if ($dockerInstaller) {
        Write-Host "Installing Docker Desktop (This may take a while)..."
        Start-Process -FilePath $dockerInstaller.FullName -ArgumentList "install --quiet --accept-license" -Wait
        Write-Host "Docker Desktop installed." -ForegroundColor Green
        $needsRestart = $true
    } else {
        Write-Error "Docker installer (Docker Desktop Installer.exe) not found in $PSScriptRoot"
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
} else {
    Write-Host "Prerequisites are ready." -ForegroundColor Green
    Write-Host "You can now run '2.setup_project.ps1'." -ForegroundColor Cyan
}
Read-Host "Press Enter to exit..."
