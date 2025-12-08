@echo off
setlocal EnableDelayedExpansion

echo ==========================================
echo   LobeChat One-Click Start
echo ==========================================

cd /d "%~dp0"

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

:: 2. Check and Create .env
set "ROOT_ENV_FILE=.env"
if not exist "%ROOT_ENV_FILE%" (
    echo Creating %ROOT_ENV_FILE%...
    (
        echo OPENAI_PROXY_URL=http://127.0.0.1:13141/v1
        echo KEY_VAULTS_SECRET=7dv75vLYisn84VcA87Z8j+5o8VJ/S2IQULC+UK3Yl1Y=
        echo # NEXT_PUBLIC_IS_DESKTOP_APP=1
        echo NEXT_PUBLIC_SERVICE_MODE=client
        echo DATABASE_URL=postgres://postgres:password@localhost:5432/lobechat
        echo ENABLE_MOCK_DEV_USER=1
        echo MOCK_DEV_USER_ID=user_123
        echo DATABASE_DRIVER=node
        echo LOBE_DB_NAME=lobechat
        echo POSTGRES_PASSWORD=password
        echo MINIO_PORT=9000
        echo MINIO_ROOT_USER=minio
        echo MINIO_ROOT_PASSWORD=minio123
        echo MINIO_LOBE_BUCKET=lobe
        echo CASDOOR_PORT=8000
        echo AUTH_CASDOOR_ISSUER=http://localhost:8000
        echo S3_ENDPOINT=http://localhost:9000
        echo S3_ACCESS_KEY_ID=minio
        echo S3_SECRET_ACCESS_KEY=minio123
        echo S3_BUCKET=lobe
        echo S3_ENABLE_PATH_STYLE=1
        echo LOBE_PID=1
        echo MINIO_PID=1
    ) > "%ROOT_ENV_FILE%"
)

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
echo Starting Infrastructure Services (PostgreSQL, MinIO, Casdoor, SearXNG)...
docker compose -f docker-compose\local\docker-compose.yml up -d postgresql minio casdoor searxng

if %errorlevel% neq 0 (
    echo Failed to start services. Please check Docker status.
    pause
    exit /b 1
)

echo Services started.

:: Run Database Migration
echo Running database migration...
timeout /t 5 /nobreak >nul
call pnpm run db:migrate

:: Start LobeChat
echo Starting LobeChat...
call pnpm start

endlocal
