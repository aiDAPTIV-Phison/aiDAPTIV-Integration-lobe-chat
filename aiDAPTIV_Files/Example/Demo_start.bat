@echo off
setlocal

:: Set environment variables for Demo Mode
set "NEXT_PUBLIC_DEMO_MODE=true"
set "DEMO_CONFIG_PATH=%~dp0LobeChat-Sir-Arthur-Conan-Doyle-session-v7.json"

:: Navigate to the project root (parent directory of Example)
cd /d "%~dp0..\.."

echo ==========================================
echo Starting LobeChat in Demo Mode
echo Config Path: %DEMO_CONFIG_PATH%
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
echo Starting Infrastructure Services...
docker compose -f docker-compose\local\docker-compose.yml up -d postgresql minio casdoor searxng

:: Start the development server
call pnpm run dev

endlocal
