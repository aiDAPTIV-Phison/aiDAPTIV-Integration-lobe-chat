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

set "LOG_FILE=%~dp0setup_log.txt"
echo ==========================================
echo   Starting Project Setup (Admin Mode)
echo   Logs will be saved to: %LOG_FILE%
echo ==========================================

:: Re-run this script with "__LOG__" argument and use PowerShell to tee output
:: Progress indicators are handled separately, so we just need to log normal output
powershell -NoProfile -ExecutionPolicy Bypass -Command "& '%~f0' '__LOG__' 2>&1 | Tee-Object -FilePath '%LOG_FILE%'; exit $LASTEXITCODE"

set "EXIT_CODE=%errorlevel%"

if %EXIT_CODE% neq 0 (
    echo [ERROR] Setup failed with exit code %EXIT_CODE%.
    echo Please check the log file for details:
    echo %LOG_FILE%
    pause
) else (
    echo Setup finished successfully.
    echo Log saved to: %LOG_FILE%
    pause
)
exit /b %EXIT_CODE%

:Main
:: ---------------------------------------------------------
:: 3. Main Setup Logic
:: ---------------------------------------------------------
:: Set log file path for progress indicators
if not defined LOG_FILE set "LOG_FILE=%~dp0setup_log.txt"

echo ==========================================
echo   Step 2: Project Setup ^& Start
echo ==========================================

set "PROJECT_ROOT=%~dp0..\.."
pushd "%PROJECT_ROOT%"
echo Current Directory: %CD%

echo.
echo [1/4] Verifying Prerequisites...
node -v >nul 2>&1
if %errorlevel% equ 0 (
    for /f "tokens=*" %%i in ('node -v') do echo Node.js found: %%i
) else (
    echo [ERROR] Node.js not found. Please run '1.install_prerequisites.bat' first.
    popd
    exit /b 1
)

docker -v >nul 2>&1
if %errorlevel% equ 0 (
    echo Docker found.
) else (
    echo [ERROR] Docker not found. Please run '1.install_prerequisites.bat' first and RESTART your computer.
    popd
    exit /b 1
)

echo.
echo [2/4] Installing Dependencies...
echo Installing pnpm...
call npm install -g pnpm
if %errorlevel% neq 0 (
    echo [ERROR] Failed to install pnpm. Ensure Node.js is in PATH.
    popd
    exit /b 1
)

echo Installing project dependencies (pnpm install)...
for %%d in ("%PROJECT_ROOT%") do set "PNPM_STORE_DIR=%%~dd\.pnpm-store"
call pnpm config set store-dir "%PNPM_STORE_DIR%"
call pnpm config set package-import-method copy
call pnpm -w install --prefer-offline
if %errorlevel% neq 0 (
    echo [ERROR] Failed to install project dependencies.
    popd
    exit /b 1
)

echo Installing additional packages...
call pnpm add @aws-sdk/client-bedrock-runtime
call pnpm add comlink
call pnpm add dompurify
call pnpm add request-filtering-agent
call pnpm add @opentelemetry/semantic-conventions @xmldom/xmldom concat-stream xlsx yauzl @opentelemetry/auto-instrumentations-node @opentelemetry/exporter-metrics-otlp-http @opentelemetry/exporter-trace-otlp-http @opentelemetry/instrumentation-pg @opentelemetry/resources @opentelemetry/sdk-metrics @opentelemetry/sdk-node
call pnpm add @opentelemetry/instrumentation-http
if %errorlevel% neq 0 (
    echo [WARNING] Some packages may have failed to install. Continuing...
)

echo.
echo [3/4] Configuring Environment...
set "ENV_FILE=%PROJECT_ROOT%\.env"

echo Configuring .env file...
powershell -NoProfile -ExecutionPolicy Bypass -Command "@'
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
'@ | Set-Content '%ENV_FILE%' -Encoding UTF8"

if %errorlevel% equ 0 (
    echo .env configured with required environment variables.
) else (
    echo [WARNING] Failed to configure .env file. You may need to configure it manually.
)

echo.
echo Checking docker-compose/local/.env...
set "DOCKER_COMPOSE_ENV_FILE=%PROJECT_ROOT%\docker-compose\local\.env"
set "DOCKER_COMPOSE_ENV_DIR=%PROJECT_ROOT%\docker-compose\local"

if not exist "%DOCKER_COMPOSE_ENV_FILE%" (
    if not exist "%DOCKER_COMPOSE_ENV_DIR%" (
        mkdir "%DOCKER_COMPOSE_ENV_DIR%"
    )
    echo Creating docker-compose/local/.env...
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
    ) > "%DOCKER_COMPOSE_ENV_FILE%"
    if %errorlevel% equ 0 (
        echo docker-compose/local/.env created.
    ) else (
        echo [WARNING] Failed to create docker-compose/local/.env file.
    )
) else (
    echo docker-compose/local/.env already exists. Skipping creation.
)

echo.
echo [4/4] Starting Local Infrastructure...
set "DOCKER_COMPOSE_FILE=%PROJECT_ROOT%\docker-compose\local\docker-compose.yml"

docker info >nul 2>&1
if %errorlevel% neq 0 (
    echo Docker daemon is not running. Attempting to start Docker Desktop...
    set "DOCKER_PATH=C:\Program Files\Docker\Docker\Docker Desktop.exe"
    if exist "%DOCKER_PATH%" (
        start "" "%DOCKER_PATH%"
        echo Waiting for Docker to start...
        set /a "WAIT_COUNT=0"
        :WAIT_DOCKER
        timeout /t 2 /nobreak >nul
        docker info >nul 2>&1
        if %errorlevel% equ 0 (
            powershell -NoProfile -ExecutionPolicy Bypass -Command "[System.IO.File]::AppendAllText('!LOG_FILE!', \"`r`n\", [System.Text.Encoding]::UTF8)"
            echo Docker started successfully.
            goto :DOCKER_READY
        )
        set /a "WAIT_COUNT+=1"
        if !WAIT_COUNT! lss 60 (
            powershell -NoProfile -ExecutionPolicy Bypass -Command "Write-Host '.' -NoNewline; [System.IO.File]::AppendAllText('!LOG_FILE!', '.', [System.Text.Encoding]::UTF8)"
            goto :WAIT_DOCKER
        )
        powershell -NoProfile -ExecutionPolicy Bypass -Command "[System.IO.File]::AppendAllText('!LOG_FILE!', \"`r`n\", [System.Text.Encoding]::UTF8)"
        echo.
        echo [WARNING] Docker did not start within timeout. Please start it manually.
        popd
        exit /b 1
    ) else (
        echo [WARNING] Could not find Docker Desktop. Please start it manually.
        popd
        exit /b 1
    )
)

:DOCKER_READY
if exist "%DOCKER_COMPOSE_FILE%" (
    echo Starting database, minio, and auth services...
    docker compose -f "%DOCKER_COMPOSE_FILE%" up -d postgresql minio casdoor searxng
    if %errorlevel% equ 0 (
        echo Infrastructure started.
        echo Running database migrations...
        call pnpm run db:migrate
        if %errorlevel% neq 0 (
            echo [WARNING] Database migration may have failed. Please check manually.
        )
    ) else (
        echo [ERROR] Failed to start infrastructure services.
        popd
        exit /b 1
    )
) else (
    echo [ERROR] Docker Compose file not found at %DOCKER_COMPOSE_FILE%
    popd
    exit /b 1
)

echo.
echo ==========================================
echo Setup complete.
echo.
echo You can now run:
echo   - 'Start_Dev.bat' (development mode, no build required)
echo   - 'Demo_start.bat' (Demo mode, no build required)
echo.
echo Note: If you want to run in production mode, you need to build first:
echo   pnpm run build
echo   Then use 'Start_Prod_Dist.bat' or 'Start_Demo_Dist.bat'
echo ==========================================

popd
exit /b 0

