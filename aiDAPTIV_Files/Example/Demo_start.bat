@echo off
setlocal EnableDelayedExpansion

:: Set environment variables for Demo Mode
set "NEXT_PUBLIC_DEMO_MODE=true"
set "DEMO_CONFIG_PATH=%~dp0LobeChat-Sir-Arthur-Conan-Doyle-session-v7.json"

:: Navigate to the project root (parent directory of Example)
cd /d "%~dp0..\.."

echo ==========================================
echo Starting LobeChat in Demo Mode
echo Config Path: %DEMO_CONFIG_PATH%
echo ==========================================

:: 1. Check and Create docker-compose/local/.env
set "DC_ENV_FILE=docker-compose\local\.env"
if not exist "%DC_ENV_FILE%" (
    echo Creating %DC_ENV_FILE%...
    (
        echo MINIO_PORT=9000
        echo MINIO_ROOT_USER=minio
        echo MINIO_ROOT_PASSWORD=minio123
        echo MINIO_LOBE_BUCKET=lobe
        echo CASDOOR_PORT=8000
        echo LOBE_PORT=3210
        echo LOBE_DB_NAME=lobechat
        echo POSTGRES_PASSWORD=password
        echo AUTH_CASDOOR_ISSUER=http://localhost:8000
        echo S3_ENDPOINT=http://localhost:9000
        echo LOBE_PID=1
        echo MINIO_PID=1
    ) > "%DC_ENV_FILE%"
)

:: 2. Check and Create/Update .env with KEY_VAULTS_SECRET
:: In Demo mode, always use a fixed KEY_VAULTS_SECRET for consistency
set "ROOT_ENV_FILE=.env"
set "DEMO_KEY_SECRET=7dv75vLYisn84VcA87Z8j+5o8VJ/S2IQULC+UK3Yl1Y="

:: Use PowerShell to ensure .env exists and has the fixed Demo KEY_VAULTS_SECRET
powershell -NoProfile -ExecutionPolicy Bypass -Command "& { $envFile = '%ROOT_ENV_FILE%'; $keySecret = '%DEMO_KEY_SECRET%'; $content = ''; if (Test-Path $envFile) { $content = Get-Content $envFile -Raw; if ($null -eq $content) { $content = '' } } else { Write-Host 'Creating .env file...' -ForegroundColor Green }; $contentLines = if ($content) { $content -split \"`r?`n\" } else { @() }; $found = $false; $newContent = @(); foreach ($line in $contentLines) { if ($line -match '^KEY_VAULTS_SECRET\s*=') { $newContent += \"KEY_VAULTS_SECRET=$keySecret\"; $found = $true; Write-Host 'Updated KEY_VAULTS_SECRET for Demo mode' -ForegroundColor Yellow } else { $newContent += $line } }; if (-not $found) { $newContent += \"KEY_VAULTS_SECRET=$keySecret\"; Write-Host 'Added KEY_VAULTS_SECRET for Demo mode' -ForegroundColor Yellow }; if ($content -notmatch 'OPENAI_PROXY_URL=') { $newContent += 'OPENAI_PROXY_URL=http://127.0.0.1:13141/v1' }; if ($content -notmatch 'NEXT_PUBLIC_SERVICE_MODE=') { $newContent += 'NEXT_PUBLIC_SERVICE_MODE=client' }; if ($content -notmatch 'DATABASE_URL=') { $newContent += 'DATABASE_URL=postgres://postgres:password@localhost:5432/lobechat' }; if ($content -notmatch 'ENABLE_MOCK_DEV_USER=') { $newContent += 'ENABLE_MOCK_DEV_USER=1'; $newContent += 'MOCK_DEV_USER_ID=user_123' }; if ($content -notmatch 'DATABASE_DRIVER=') { $newContent += 'DATABASE_DRIVER=node' }; if ($content -notmatch 'S3_ACCESS_KEY_ID=') { $newContent += 'S3_ACCESS_KEY_ID=minio'; $newContent += 'S3_SECRET_ACCESS_KEY=minio123'; $newContent += 'S3_ENDPOINT=http://localhost:9000'; $newContent += 'S3_BUCKET=lobe'; $newContent += 'S3_ENABLE_PATH_STYLE=1' }; $content = $newContent -join \"`r`n\"; Set-Content $envFile -Value $content -NoNewline; Write-Host '.env configured for Demo mode.' -ForegroundColor Green }"

:: Check if Docker is running
docker info >nul 2>&1
if %errorlevel% neq 0 (
    echo Docker is not running. Attempting to start Docker Desktop...
    start "" "C:\Program Files\Docker\Docker\Docker Desktop.exe"
    
    echo Waiting for Docker to start...
    :wait_docker
    timeout /t 5 /nobreak >nul
    docker info >nul 2>&1
    if %errorlevel% neq 0 (
        echo .
        goto wait_docker
    )
    echo Docker started successfully.
)

:: Start Infrastructure Services
echo Starting Infrastructure Services...
docker compose -f docker-compose\local\docker-compose.yml up -d postgresql minio casdoor searxng

if %errorlevel% neq 0 (
    echo Failed to start services. Please check Docker status.
    pause
    exit /b 1
)

:: Run Database Migration
echo Running database migration...
timeout /t 5 /nobreak >nul
call pnpm run db:migrate

:: Start the development server
call pnpm run dev

endlocal
