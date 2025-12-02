<#
.SYNOPSIS
Step 2: Project Setup and Start
.DESCRIPTION
Configures dependencies, environment, and starts the application.
Run this AFTER '1.install_prerequisites.ps1' and a system restart.
#>

$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Administrator privileges required. Restarting with elevated permissions..."
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
$ProjectRoot = Resolve-Path "$PSScriptRoot\..\.."

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "   Step 2: Project Setup & Start" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

Write-Host "`n[1/4] Verifying Prerequisites..." -ForegroundColor Yellow
try {
    $nodeVersion = node -v
    Write-Host "Node.js found: $nodeVersion" -ForegroundColor Green
} catch {
    Write-Error "Node.js not found. Please run '1.install_prerequisites.ps1' first."
}

if (Get-Command "docker" -ErrorAction SilentlyContinue) {
    Write-Host "Docker found." -ForegroundColor Green
} else {
    Write-Error "Docker not found. Please run '1.install_prerequisites.ps1' first and RESTART your computer."
}

Write-Host "`n[2/4] Installing Dependencies..." -ForegroundColor Yellow
Set-Location $ProjectRoot

try {
    Write-Host "Installing pnpm..."
    npm install -g pnpm
} catch {
    Write-Error "Failed to install pnpm. Ensure Node.js is in PATH."
}

Write-Host "Installing project dependencies (pnpm install)..."
pnpm add -D cross-env
pnpm approve-builds
## pnpm install

Write-Host "`n[3/4] Configuring Environment..." -ForegroundColor Yellow
$EnvFile = "$ProjectRoot\.env"
$EnvExample = "$ProjectRoot\.env.example.development"

if (-not (Test-Path $EnvFile)) {
    if (Test-Path $EnvExample) {
        Copy-Item $EnvExample $EnvFile
        Write-Host "Created .env from .env.example.development" -ForegroundColor Green
        
        Write-Host "Generating secure keys..."
        $KeyVaultsSecret = node -e "console.log(require('crypto').randomBytes(32).toString('base64'))"
        
        $EnvContent = Get-Content $EnvFile
        
        if ($EnvContent -match "KEY_VAULTS_SECRET=") {
            $EnvContent = $EnvContent -replace "KEY_VAULTS_SECRET=.*", "KEY_VAULTS_SECRET=$KeyVaultsSecret"
        } else {
            $EnvContent += "KEY_VAULTS_SECRET=$KeyVaultsSecret"
        }
        
        if ($EnvContent -notmatch "ENABLE_MOCK_DEV_USER=") {
            $EnvContent += "ENABLE_MOCK_DEV_USER=1"
            $EnvContent += "MOCK_DEV_USER_ID=user_123"
        }

        if ($EnvContent -notmatch "OPENAI_PROXY_URL=") {
            $EnvContent += "OPENAI_PROXY_URL=http://127.0.0.1:13141/v1"
        }

        if ($EnvContent -match "LOBE_PORT=") {
            $EnvContent = $EnvContent -replace "LOBE_PORT=.*", "LOBE_PORT=3011"
        } else {
            $EnvContent += "LOBE_PORT=3011"
        }

        if ($EnvContent -match "APP_URL=") {
            $EnvContent = $EnvContent -replace "APP_URL=.*", "APP_URL=http://localhost:3010"
        } else {
            $EnvContent += "APP_URL=http://localhost:3010"
        }
        
        if ($EnvContent -notmatch "S3_ACCESS_KEY_ID=") {
            $EnvContent += "S3_ACCESS_KEY_ID=minio"
            $EnvContent += "S3_SECRET_ACCESS_KEY=minio123"
            $EnvContent += "S3_ENDPOINT=http://localhost:9000"
            $EnvContent += "S3_BUCKET=lobe"
            $EnvContent += "S3_ENABLE_PATH_STYLE=1"
        }

        $EnvContent | Set-Content $EnvFile
        Write-Host ".env configured." -ForegroundColor Green
    } else {
        Write-Warning ".env.example.development not found. Skipping .env creation."
    }
} else {
    Write-Host ".env already exists. Skipping creation." -ForegroundColor Gray
}

Write-Host "`n[4/4] Starting Local Infrastructure..." -ForegroundColor Yellow
$DockerComposeFile = "$ProjectRoot\docker-compose\local\docker-compose.yml"

try {
    docker info > $null 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Docker not running" }
} catch {
    Write-Host "Docker daemon is not running. Attempting to start Docker Desktop..."
    $DockerPath = "C:\Program Files\Docker\Docker\Docker Desktop.exe"
    if (Test-Path $DockerPath) {
        Start-Process $DockerPath
        Write-Host "Waiting for Docker to start..."
        for ($i=0; $i -lt 60; $i++) {
            Start-Sleep -Seconds 2
            docker info > $null 2>&1
            if ($LASTEXITCODE -eq 0) { break }
            Write-Host "." -NoNewline
        }
        Write-Host ""
    } else {
        Write-Warning "Could not find Docker Desktop. Please start it manually."
    }
}

if (Test-Path $DockerComposeFile) {
    Write-Host "Starting database, minio, and auth services..."
    docker compose -f $DockerComposeFile up -d postgresql minio casdoor searxng
    Write-Host "Infrastructure started." -ForegroundColor Green
} else {
    Write-Error "Docker Compose file not found at $DockerComposeFile"
}

# Write-Host "`n[5/5] Starting LobeChat..." -ForegroundColor Yellow
# pnpm run dev
