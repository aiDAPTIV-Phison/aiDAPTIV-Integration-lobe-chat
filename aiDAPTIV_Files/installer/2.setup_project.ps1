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
}
catch {
    Write-Error "Node.js not found. Please run '1.install_prerequisites.ps1' first."
}

if (Get-Command "docker" -ErrorAction SilentlyContinue) {
    Write-Host "Docker found." -ForegroundColor Green
}
else {
    Write-Error "Docker not found. Please run '1.install_prerequisites.ps1' first and RESTART your computer."
}

Write-Host "`n[2/4] Installing Dependencies..." -ForegroundColor Yellow
Set-Location $ProjectRoot

try {
    Write-Host "Installing pnpm..."
    npm install -g pnpm
}
catch {
    Write-Error "Failed to install pnpm. Ensure Node.js is in PATH."
}

Write-Host "Installing project dependencies (pnpm install)..."
# pnpm add -D cross-env
# pnpm approve-builds

# Cange to root 
pnpm config set store-dir R:\.pnpm-store
pnpm config set package-import-method copy
pnpm -w install --prefer-offline
pnpm add @aws-sdk/client-bedrock-runtime
pnpm add comlink
pnpm add dompurify
pnpm add request-filtering-agent
pnpm add @opentelemetry/semantic-conventions @xmldom/xmldom concat-stream xlsx yauzl @opentelemetry/auto-instrumentations-node @opentelemetry/auto-instrumentations-node @opentelemetry/exporter-metrics-otlp-http @opentelemetry/exporter-trace-otlp-http @opentelemetry/instrumentation-pg @opentelemetry/resources @opentelemetry/sdk-metrics @opentelemetry/sdk-node
pnpm add @opentelemetry/instrumentation-http

Write-Host "`n[3/4] Configuring Environment..." -ForegroundColor Yellow
$EnvFile = "$ProjectRoot\.env"

# Define the required environment variables
$RequiredEnvVars = @"
OPENAI_PROXY_URL=http://127.0.0.1:13141/v1
KEY_VAULTS_SECRET=7dv75vLYisn84VcA87Z8j+5o8VJ/S2IQULC+UK3Yl1Y=
# NEXT_PUBLIC_IS_DESKTOP_APP=1
NEXT_PUBLIC_SERVICE_MODE=client
DATABASE_URL=postgres://postgres:password@localhost:5432/lobechat
ENABLE_MOCK_DEV_USER=1
MOCK_DEV_USER_ID=user_123
DATABASE_DRIVER=node
LOBE_DB_NAME=lobechat
POSTGRES_PASSWORD=password
MINIO_PORT=9000
MINIO_ROOT_USER=minio
MINIO_ROOT_PASSWORD=minio123
MINIO_LOBE_BUCKET=lobe
CASDOOR_PORT=8000
AUTH_CASDOOR_ISSUER=http://localhost:8000
S3_ENDPOINT=http://localhost:9000
S3_ACCESS_KEY_ID=minio
S3_SECRET_ACCESS_KEY=minio123
S3_BUCKET=lobe
S3_ENABLE_PATH_STYLE=1
LOBE_PID=1
MINIO_PID=1
"@

# Create or overwrite .env file with required values
$RequiredEnvVars | Set-Content $EnvFile -Encoding UTF8
Write-Host ".env configured with required environment variables." -ForegroundColor Green

# Check docker-compose/local/.env
$DockerComposeEnvFile = "$ProjectRoot\docker-compose\local\.env"
$DockerComposeEnvDir = "$ProjectRoot\docker-compose\local"

if (-not (Test-Path $DockerComposeEnvFile)) {
    # Ensure directory exists
    if (-not (Test-Path $DockerComposeEnvDir)) {
        New-Item -ItemType Directory -Path $DockerComposeEnvDir -Force | Out-Null
    }
    
    Write-Host "Creating docker-compose/local/.env..." -ForegroundColor Yellow
    $DockerComposeEnvContent = @"
MINIO_PORT=9000
MINIO_ROOT_USER=minio
MINIO_ROOT_PASSWORD=minio123
MINIO_LOBE_BUCKET=lobe
CASDOOR_PORT=8000
LOBE_PORT=3210
LOBE_DB_NAME=lobechat
POSTGRES_PASSWORD=password
AUTH_CASDOOR_ISSUER=http://localhost:8000
S3_ENDPOINT=http://localhost:9000
LOBE_PID=1
MINIO_PID=1
"@
    $DockerComposeEnvContent | Set-Content $DockerComposeEnvFile -Encoding UTF8
    Write-Host "docker-compose/local/.env created." -ForegroundColor Green
}
else {
    Write-Host "docker-compose/local/.env already exists. Skipping creation." -ForegroundColor Gray
}

Write-Host "`n[4/4] Starting Local Infrastructure..." -ForegroundColor Yellow
$DockerComposeFile = "$ProjectRoot\docker-compose\local\docker-compose.yml"

try {
    docker info > $null 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Docker not running" }
}
catch {
    Write-Host "Docker daemon is not running. Attempting to start Docker Desktop..."
    $DockerPath = "C:\Program Files\Docker\Docker\Docker Desktop.exe"
    if (Test-Path $DockerPath) {
        Start-Process $DockerPath
        Write-Host "Waiting for Docker to start..."
        for ($i = 0; $i -lt 60; $i++) {
            Start-Sleep -Seconds 2
            docker info > $null 2>&1
            if ($LASTEXITCODE -eq 0) { break }
            Write-Host "." -NoNewline
        }
        Write-Host ""
    }
    else {
        Write-Warning "Could not find Docker Desktop. Please start it manually."
    }
}


if (Test-Path $DockerComposeFile) {
    Write-Host "Starting database, minio, and auth services..."
    docker compose -f $DockerComposeFile up -d postgresql minio casdoor searxng
    Write-Host "Infrastructure started." -ForegroundColor Green
    pnpm run db:migrate
}
else {
    Write-Error "Docker Compose file not found at $DockerComposeFile"
}

# Write-Host "`n[5/5] Starting LobeChat..." -ForegroundColor Yellow
# pnpm run dev
