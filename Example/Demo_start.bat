@echo off
setlocal

:: Set environment variables for Demo Mode
set "NEXT_PUBLIC_DEMO_MODE=true"
set "DEMO_CONFIG_PATH=%~dp0LobeChat-Sir-Arthur-Conan-Doyle-session-v7.json"

:: Navigate to the project root (parent directory of Example)
cd /d "%~dp0.."

echo ==========================================
echo Starting LobeChat in Demo Mode
echo Config Path: %DEMO_CONFIG_PATH%
echo ==========================================

:: Start the development server
call pnpm run dev

endlocal
