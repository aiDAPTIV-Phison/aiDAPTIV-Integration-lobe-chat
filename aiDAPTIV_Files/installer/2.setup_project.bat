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
set "PNPM_STORE_DIR=%PROJECT_ROOT:~0,2%\.pnpm-store"
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
call pnpm add @opentelemetry/semantic-conventions @xmldom/xmldom concat-stream xlsx yauzl
if %errorlevel% neq 0 (
    echo [WARNING] Some packages may have failed to install. Continuing...
)

echo.
echo [3/4] Configuring Environment...
set "ENV_FILE=%PROJECT_ROOT%\.env"
set "ENV_EXAMPLE=%PROJECT_ROOT%\.env.example.development"

if not exist "%ENV_FILE%" (
    if exist "%ENV_EXAMPLE%" (
        echo Created .env from .env.example.development
        copy "%ENV_EXAMPLE%" "%ENV_FILE%" >nul
        
        echo Generating secure keys...
        for /f "tokens=*" %%k in ('node -e "console.log(require('crypto').randomBytes(32).toString('base64'))"') do set "KEY_VAULTS_SECRET=%%k"
        
        echo Configuring .env file...
        powershell -NoProfile -ExecutionPolicy Bypass -Command ^
            "$keySecret = '!KEY_VAULTS_SECRET!'; ^
            $content = Get-Content '%ENV_FILE%' -Raw; ^
            $content = $content -replace 'KEY_VAULTS_SECRET=.*', (\"KEY_VAULTS_SECRET=\" + $keySecret); ^
            if ($content -notmatch 'KEY_VAULTS_SECRET=') { $content += \"`nKEY_VAULTS_SECRET=\" + $keySecret }; ^
            if ($content -notmatch 'ENABLE_MOCK_DEV_USER=') { $content += \"`nENABLE_MOCK_DEV_USER=1`nMOCK_DEV_USER_ID=user_123\" }; ^
            if ($content -notmatch 'OPENAI_PROXY_URL=') { $content += \"`nOPENAI_PROXY_URL=http://127.0.0.1:13141/v1\" }; ^
            $content = $content -replace 'LOBE_PORT=.*', 'LOBE_PORT=3011'; ^
            if ($content -notmatch 'LOBE_PORT=') { $content += \"`nLOBE_PORT=3011\" }; ^
            $content = $content -replace 'APP_URL=.*', 'APP_URL=http://localhost:3010'; ^
            if ($content -notmatch 'APP_URL=') { $content += \"`nAPP_URL=http://localhost:3010\" }; ^
            if ($content -notmatch 'S3_ACCESS_KEY_ID=') { $content += \"`nS3_ACCESS_KEY_ID=minio`nS3_SECRET_ACCESS_KEY=minio123`nS3_ENDPOINT=http://localhost:9000`nS3_BUCKET=lobe`nS3_ENABLE_PATH_STYLE=1\" }; ^
            Set-Content '%ENV_FILE%' -Value $content -NoNewline"
        
        if %errorlevel% equ 0 (
            echo .env configured.
        ) else (
            echo [WARNING] Failed to configure .env file. You may need to configure it manually.
        )
    ) else (
        echo [WARNING] .env.example.development not found. Skipping .env creation.
    )
) else (
    echo .env already exists. Skipping creation.
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
echo You can now run 'Start_Dev.bat' or 'Demo_start.bat'.
echo ==========================================

popd
exit /b 0
