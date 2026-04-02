@echo off
chcp 65001 >nul 2>&1
title TDZ DevStack Control Panel

set "TDZ_ROOT=%~dp0"
if "%TDZ_ROOT:~-1%"=="\" set "TDZ_ROOT=%TDZ_ROOT:~0,-1%"

echo.
echo   ========================================
echo       TDZ DevStack v1.0
echo       Dashboard: http://localhost:8080
echo   ========================================
echo.

:: Resolve active runtimes from tdz.json
for /f "tokens=*" %%a in ('powershell -NoProfile -Command "(Get-Content '%TDZ_ROOT%\usr\tdz.json' -Raw | ConvertFrom-Json).runtimes.php.active"') do set "PHP_ACTIVE=%%a"
for /f "tokens=*" %%a in ('powershell -NoProfile -Command "(Get-Content '%TDZ_ROOT%\usr\tdz.json' -Raw | ConvertFrom-Json).runtimes.nodejs.active"') do set "NODE_ACTIVE=%%a"

:: Set PATH for all tools globally for this session
set "PATH=%TDZ_ROOT%\bin\php\%PHP_ACTIVE%;%PATH%"
set "PATH=%TDZ_ROOT%\bin\nodejs\%NODE_ACTIVE%;%PATH%"
set "PATH=%TDZ_ROOT%\bin\composer;%PATH%"
set "PATH=%TDZ_ROOT%\bin\git\bin;%PATH%"
set "PATH=%TDZ_ROOT%\bin\ngrok;%PATH%"

echo   Active PHP: %PHP_ACTIVE%
echo   Active Node: %NODE_ACTIVE%
echo.

:: Auto-repair paths if DevStack was moved (Make it 100%% Portable)
"%TDZ_ROOT%\bin\nodejs\%NODE_ACTIVE%\node.exe" "%TDZ_ROOT%\bin\tdz\update_paths.js"

echo   Starting Background Services and API Server...


:: Start the API server in a separate minimum window
powershell -ExecutionPolicy Bypass -NoProfile -Command "Start-Process -FilePath '%TDZ_ROOT%\bin\nodejs\node-v24\node.exe' -ArgumentList '\"%TDZ_ROOT%\devstack-dashboard\api.js\"' -WindowStyle Hidden"

:: Open dashboard in browser after a short delay
timeout /t 2 /nobreak >nul
start http://localhost:8080

:menu
cls
echo.
echo   ========================================
echo       TDZ DevStack v1.0
echo       Status: RUNNING
echo   ========================================
echo.
echo   CAUTION: Do not close this window with the 'X' button!
echo   Background services (MySQL, Apache, etc.) will keep running.
echo.
echo   Type 'Q' and press Enter to gently shut down everything.
echo.
set /p choice="Action [Q]: "
if /i "%choice%"=="Q" goto shutdown
goto menu

:shutdown
echo.
echo   Shutting down TDZ DevStack...
:: Call API to shutdown politely
powershell -NoProfile -Command "Invoke-WebRequest -Uri 'http://localhost:8080/api/shutdown' -Method POST -UseBasicParsing -ErrorAction SilentlyContinue | Out-Null" >nul 2>&1

echo   Waiting for services to stop...
timeout /t 3 /nobreak >nul

:: Fallback Force Stop
powershell -ExecutionPolicy Bypass -NoProfile -Command "$ErrorActionPreference='SilentlyContinue'; Get-Process mysqld,httpd,nginx,redis-server,memcached,mailpit -ErrorAction SilentlyContinue | Stop-Process -Force" >nul 2>&1

echo.
echo   All services stopped. Press any key to exit...
pause >nul
exit
