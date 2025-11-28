@echo off
setlocal

echo ==========================================
echo   LobeChat One-Click Start
echo ==========================================

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
cd /d "%~dp0"
docker compose -f docker-compose\local\docker-compose.yml up -d postgresql minio casdoor searxng

if %errorlevel% neq 0 (
    echo Failed to start services. Please check Docker status.
    pause
    exit /b 1
)

echo Services started.

:: Start LobeChat Development Server
echo Starting LobeChat...
call pnpm run dev

endlocal
