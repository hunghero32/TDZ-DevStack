@echo off
setlocal EnableDelayedExpansion

:: ============================================================
:: TDZ DevStack CLI v1.0
:: Portable Development Environment for Windows
:: ============================================================

:: Auto-detect root directory
set "TDZ_ROOT=%~dp0"
if "%TDZ_ROOT:~-1%"=="\" set "TDZ_ROOT=%TDZ_ROOT:~0,-1%"

:: Resolve active runtimes from tdz.json
for /f "tokens=*" %%a in ('powershell -NoProfile -Command "(Get-Content '%TDZ_ROOT%\usr\tdz.json' -Raw | ConvertFrom-Json).runtimes.php.active"') do set "PHP_ACTIVE=%%a"
for /f "tokens=*" %%a in ('powershell -NoProfile -Command "(Get-Content '%TDZ_ROOT%\usr\tdz.json' -Raw | ConvertFrom-Json).runtimes.nodejs.active"') do set "NODE_ACTIVE=%%a"

:: Set PATH for all tools
set "PATH=%TDZ_ROOT%\bin\php\%PHP_ACTIVE%;%PATH%"
set "PATH=%TDZ_ROOT%\bin\nodejs\%NODE_ACTIVE%;%PATH%"
set "PATH=%TDZ_ROOT%\bin\composer;%PATH%"
set "PATH=%TDZ_ROOT%\bin\git\bin;%PATH%"
set "PATH=%TDZ_ROOT%\bin\ngrok;%PATH%"

:: Parse command
set "CMD=%~1"
set "ARG1=%~2"
set "ARG2=%~3"
set "ARG3=%~4"

if "%CMD%"=="" goto :help
if "%CMD%"=="help" goto :help
if "%CMD%"=="-h" goto :help
if "%CMD%"=="--help" goto :help

if "%CMD%"=="start" goto :start
if "%CMD%"=="stop" goto :stop
if "%CMD%"=="restart" goto :restart
if "%CMD%"=="status" goto :status
if "%CMD%"=="use" goto :use
if "%CMD%"=="dashboard" goto :dashboard
if "%CMD%"=="terminal" goto :terminal
if "%CMD%"=="install" goto :install
if "%CMD%"=="list" goto :list
if "%CMD%"=="ssl" goto :ssl
if "%CMD%"=="profile" goto :profile
if "%CMD%"=="projects" goto :projects
if "%CMD%"=="info" goto :info
if "%CMD%"=="log" goto :log
if "%CMD%"=="logs" goto :log
if "%CMD%"=="init" goto :init
if "%CMD%"=="api" goto :api

echo.
echo   Unknown command: %CMD%
echo   Run 'tdz help' for usage
exit /b 1

:: ============================================================
:help
echo.
echo   ╔══════════════════════════════════════════════╗
echo   ║         TDZ DevStack CLI v1.0                ║
echo   ║   Portable Development Environment           ║
echo   ╚══════════════════════════════════════════════╝
echo.
echo   Usage: tdz ^<command^> [options]
echo.
echo   Service Management:
echo     start [service]         Start all or specific service
echo     stop [service]          Stop all or specific service
echo     restart [service]       Restart all or specific service
echo     status                  Show all service status
echo.
echo   Version Management:
echo     use ^<runtime^> ^<version^>  Switch version (e.g. tdz use php 8.2)
echo     list                    List installed packages and versions
echo.
echo   Tools:
echo     dashboard               Open web dashboard in browser
echo     terminal                Open integrated terminal (cmder)
echo     api                     Start API server
echo     info                    Show system information
echo.
echo   Package Management:
echo     install ^<package^>       Install a package from registry
echo.
echo   Project Management:
echo     projects                List all projects
echo     init                    Create .tdz.json for current project
echo.
echo   SSL:
echo     ssl ^<domain^>            Generate SSL certificate for domain
echo.
echo   Profiles:
echo     profile save ^<name^>     Save current config as profile
echo     profile load ^<name^>     Load a saved profile
echo     profile list            List all profiles
echo.
echo   Logs:
echo     log [service]           View logs (default: system)
echo.
echo   Services: apache, mysql, redis, mailpit, memcached, nginx
echo   Runtimes: php, nodejs, python
echo.
exit /b 0

:: ============================================================
:start
if "%ARG1%"=="" (
    echo   Starting all services...
    powershell -ExecutionPolicy Bypass -Command "& { $Root='%TDZ_ROOT%'; . '%TDZ_ROOT%\bin\tdz\modules\LogManager.ps1'; . '%TDZ_ROOT%\bin\tdz\modules\ConfigManager.ps1'; . '%TDZ_ROOT%\bin\tdz\modules\ServiceManager.ps1'; . '%TDZ_ROOT%\bin\tdz\modules\VHostManager.ps1'; $r = Start-AllServices -RootDir $Root; Write-Host $r.message }"
) else (
    echo   Starting %ARG1%...
    powershell -ExecutionPolicy Bypass -Command "& { $Root='%TDZ_ROOT%'; . '%TDZ_ROOT%\bin\tdz\modules\LogManager.ps1'; . '%TDZ_ROOT%\bin\tdz\modules\ConfigManager.ps1'; . '%TDZ_ROOT%\bin\tdz\modules\ServiceManager.ps1'; $r = Start-TDZService -ServiceName '%ARG1%' -RootDir $Root; Write-Host $r.message }"
)
exit /b 0

:: ============================================================
:stop
if "%ARG1%"=="" (
    echo   Stopping all services...
    powershell -ExecutionPolicy Bypass -Command "& { $Root='%TDZ_ROOT%'; . '%TDZ_ROOT%\bin\tdz\modules\LogManager.ps1'; . '%TDZ_ROOT%\bin\tdz\modules\ConfigManager.ps1'; . '%TDZ_ROOT%\bin\tdz\modules\ServiceManager.ps1'; $r = Stop-AllServices -RootDir $Root; Write-Host $r.message }"
) else (
    echo   Stopping %ARG1%...
    powershell -ExecutionPolicy Bypass -Command "& { $Root='%TDZ_ROOT%'; . '%TDZ_ROOT%\bin\tdz\modules\LogManager.ps1'; . '%TDZ_ROOT%\bin\tdz\modules\ConfigManager.ps1'; . '%TDZ_ROOT%\bin\tdz\modules\ServiceManager.ps1'; $r = Stop-TDZService -ServiceName '%ARG1%' -RootDir $Root; Write-Host $r.message }"
)
exit /b 0

:: ============================================================
:restart
if "%ARG1%"=="" (
    echo   Restarting all services...
    powershell -ExecutionPolicy Bypass -Command "& { $Root='%TDZ_ROOT%'; . '%TDZ_ROOT%\bin\tdz\modules\LogManager.ps1'; . '%TDZ_ROOT%\bin\tdz\modules\ConfigManager.ps1'; . '%TDZ_ROOT%\bin\tdz\modules\ServiceManager.ps1'; . '%TDZ_ROOT%\bin\tdz\modules\VHostManager.ps1'; Stop-AllServices -RootDir $Root | Out-Null; Start-Sleep -Seconds 1; $r = Start-AllServices -RootDir $Root; Write-Host $r.message }"
) else (
    echo   Restarting %ARG1%...
    powershell -ExecutionPolicy Bypass -Command "& { $Root='%TDZ_ROOT%'; . '%TDZ_ROOT%\bin\tdz\modules\LogManager.ps1'; . '%TDZ_ROOT%\bin\tdz\modules\ConfigManager.ps1'; . '%TDZ_ROOT%\bin\tdz\modules\ServiceManager.ps1'; $r = Restart-TDZService -ServiceName '%ARG1%' -RootDir $Root; Write-Host $r.message }"
)
exit /b 0

:: ============================================================
:status
powershell -ExecutionPolicy Bypass -Command "& { $Root='%TDZ_ROOT%'; . '%TDZ_ROOT%\bin\tdz\modules\LogManager.ps1'; . '%TDZ_ROOT%\bin\tdz\modules\ConfigManager.ps1'; . '%TDZ_ROOT%\bin\tdz\modules\ServiceManager.ps1'; $s = Get-AllStatus -RootDir $Root; Write-Host ''; Write-Host '  TDZ DevStack Status' -ForegroundColor Cyan; Write-Host '  ===================' -ForegroundColor DarkCyan; Write-Host ''; foreach ($k in ($s.Keys | Sort-Object)) { $v = $s[$k]; $icon = if ($v.running) { '[ON]' } else { '[OFF]' }; $color = if ($v.running) { 'Green' } else { 'DarkGray' }; $mem = if ($v.running -and $v.memory) { \" ($($v.memory)MB)\" } else { '' }; $rt = if ($v.isRuntime) { ' [runtime]' } else { '' }; Write-Host \"  $icon $($v.name.PadRight(12)) $($v.active)$mem$rt\" -ForegroundColor $color }; Write-Host '' }"
exit /b 0

:: ============================================================
:use
if "%ARG1%"=="" (
    echo   Usage: tdz use ^<runtime^> ^<version^>
    echo   Example: tdz use php 8.2
    exit /b 1
)
echo   Switching %ARG1% to %ARG2%...
powershell -ExecutionPolicy Bypass -Command "& { $Root='%TDZ_ROOT%'; . '%TDZ_ROOT%\bin\tdz\modules\LogManager.ps1'; . '%TDZ_ROOT%\bin\tdz\modules\ConfigManager.ps1'; . '%TDZ_ROOT%\bin\tdz\modules\ServiceManager.ps1'; . '%TDZ_ROOT%\bin\tdz\modules\VersionManager.ps1'; $versions = (Get-ServiceMeta -RootDir $Root)['%ARG1%'].versions; $match = $versions | Where-Object { $_ -like '*%ARG2%*' } | Select-Object -First 1; if ($match) { $r = Switch-ServiceVersion -ServiceName '%ARG1%' -NewVersion $match -RootDir $Root; Write-Host $r.message } else { Write-Host 'Version not found. Available:' -ForegroundColor Red; $versions | ForEach-Object { Write-Host \"  $_\" } } }"
exit /b 0

:: ============================================================
:dashboard
echo   Opening TDZ DevStack Dashboard...
start http://localhost:8080
exit /b 0

:: ============================================================
:terminal
if exist "%TDZ_ROOT%\bin\cmder\Cmder.exe" (
    start "" "%TDZ_ROOT%\bin\cmder\Cmder.exe" /START "%TDZ_ROOT%\www"
) else (
    echo   Opening PowerShell terminal...
    start powershell -NoExit -Command "cd '%TDZ_ROOT%\www'; Write-Host 'TDZ DevStack Terminal' -ForegroundColor Cyan; Write-Host 'Root: %TDZ_ROOT%' -ForegroundColor DarkGray"
)
exit /b 0

:: ============================================================
:api
echo   Starting TDZ DevStack API Server...
"%TDZ_ROOT%\bin\nodejs\node-v24\node.exe" "%TDZ_ROOT%\devstack-dashboard\api.js"
exit /b 0

:: ============================================================
:install
if "%ARG1%"=="" (
    echo   Usage: tdz install ^<package-name^>
    exit /b 1
)
echo   Installing %ARG1%...
powershell -ExecutionPolicy Bypass -Command "& { $Root='%TDZ_ROOT%'; . '%TDZ_ROOT%\bin\tdz\modules\LogManager.ps1'; . '%TDZ_ROOT%\bin\tdz\modules\ConfigManager.ps1'; . '%TDZ_ROOT%\bin\tdz\modules\PackageManager.ps1'; $r = Install-Package -RootDir $Root -PackageName '%ARG1%'; Write-Host $r.message }"
exit /b 0

:: ============================================================
:list
powershell -ExecutionPolicy Bypass -Command "& { $Root='%TDZ_ROOT%'; . '%TDZ_ROOT%\bin\tdz\modules\LogManager.ps1'; . '%TDZ_ROOT%\bin\tdz\modules\ConfigManager.ps1'; . '%TDZ_ROOT%\bin\tdz\modules\PackageManager.ps1'; $pkgs = Get-InstalledPackages -RootDir $Root; Write-Host ''; Write-Host '  Installed Packages' -ForegroundColor Cyan; Write-Host '  ==================' -ForegroundColor DarkCyan; foreach ($cat in ($pkgs.Keys | Sort-Object)) { Write-Host \"`n  $($cat.ToUpper())\" -ForegroundColor Yellow; foreach ($v in $pkgs[$cat]) { Write-Host \"    $($v.name) ($($v.size)MB)\" } }; Write-Host '' }"
exit /b 0

:: ============================================================
:ssl
if "%ARG1%"=="" (
    echo   Usage: tdz ssl ^<domain^>
    exit /b 1
)
echo   Generating SSL for %ARG1%...
powershell -ExecutionPolicy Bypass -Command "& { $Root='%TDZ_ROOT%'; . '%TDZ_ROOT%\bin\tdz\modules\LogManager.ps1'; . '%TDZ_ROOT%\bin\tdz\modules\ConfigManager.ps1'; . '%TDZ_ROOT%\bin\tdz\modules\ServiceManager.ps1'; . '%TDZ_ROOT%\bin\tdz\modules\SSLManager.ps1'; $r = New-SSLCertificate -RootDir $Root -Domain '%ARG1%'; Write-Host $r.message }"
exit /b 0

:: ============================================================
:profile
if "%ARG1%"=="save" (
    if "%ARG2%"=="" ( echo   Usage: tdz profile save ^<name^> & exit /b 1 )
    powershell -ExecutionPolicy Bypass -Command "& { $Root='%TDZ_ROOT%'; . '%TDZ_ROOT%\bin\tdz\modules\LogManager.ps1'; . '%TDZ_ROOT%\bin\tdz\modules\ConfigManager.ps1'; . '%TDZ_ROOT%\bin\tdz\modules\ProfileManager.ps1'; $r = Save-Profile -RootDir $Root -ProfileName '%ARG2%' -Description '%ARG3%'; Write-Host $r.message }"
) else if "%ARG1%"=="load" (
    if "%ARG2%"=="" ( echo   Usage: tdz profile load ^<name^> & exit /b 1 )
    powershell -ExecutionPolicy Bypass -Command "& { $Root='%TDZ_ROOT%'; . '%TDZ_ROOT%\bin\tdz\modules\LogManager.ps1'; . '%TDZ_ROOT%\bin\tdz\modules\ConfigManager.ps1'; . '%TDZ_ROOT%\bin\tdz\modules\ProfileManager.ps1'; $r = Load-Profile -RootDir $Root -ProfileName '%ARG2%'; Write-Host $r.message }"
) else if "%ARG1%"=="list" (
    powershell -ExecutionPolicy Bypass -Command "& { $Root='%TDZ_ROOT%'; . '%TDZ_ROOT%\bin\tdz\modules\LogManager.ps1'; . '%TDZ_ROOT%\bin\tdz\modules\ConfigManager.ps1'; . '%TDZ_ROOT%\bin\tdz\modules\ProfileManager.ps1'; $profiles = Get-Profiles -RootDir $Root; if ($profiles.Count -eq 0) { Write-Host '  No profiles saved' } else { Write-Host ''; Write-Host '  Saved Profiles' -ForegroundColor Cyan; $profiles | ForEach-Object { Write-Host \"  - $($_.name): $($_.description) ($($_.createdAt))\" } }; Write-Host '' }"
) else (
    echo   Usage: tdz profile ^<save^|load^|list^> [name]
)
exit /b 0

:: ============================================================
:projects
powershell -ExecutionPolicy Bypass -Command "& { $Root='%TDZ_ROOT%'; . '%TDZ_ROOT%\bin\tdz\modules\LogManager.ps1'; . '%TDZ_ROOT%\bin\tdz\modules\ConfigManager.ps1'; $config = Get-TDZConfig -RootDir $Root; $wwwDir = Join-Path $Root 'www'; if (Test-Path $wwwDir) { Write-Host ''; Write-Host '  Projects' -ForegroundColor Cyan; Write-Host '  ========' -ForegroundColor DarkCyan; Get-ChildItem $wwwDir -Directory | ForEach-Object { $domain = \"$($_.Name)$($config.preferences.tld)\"; $fw = if (Test-Path (Join-Path $_.FullName 'composer.json')) { 'PHP' } elseif (Test-Path (Join-Path $_.FullName 'package.json')) { 'Node' } else { 'Static' }; Write-Host \"  $($_.Name.PadRight(25)) http://$domain [$fw]\" }; Write-Host '' } else { Write-Host '  No www/ directory' } }"
exit /b 0

:: ============================================================
:info
powershell -ExecutionPolicy Bypass -Command "& { $Root='%TDZ_ROOT%'; . '%TDZ_ROOT%\bin\tdz\modules\LogManager.ps1'; . '%TDZ_ROOT%\bin\tdz\modules\ConfigManager.ps1'; . '%TDZ_ROOT%\bin\tdz\modules\ServiceManager.ps1'; $meta = Get-ServiceMeta -RootDir $Root; $phpExe = Join-Path $Root \"bin\php\$($meta.php.active)\php.exe\"; Write-Host ''; Write-Host '  TDZ DevStack System Info' -ForegroundColor Cyan; Write-Host '  ========================' -ForegroundColor DarkCyan; Write-Host \"  Root     : $Root\"; Write-Host \"  Hostname : $env:COMPUTERNAME\"; Write-Host \"  OS       : $([System.Environment]::OSVersion.VersionString)\"; if (Test-Path $phpExe) { Write-Host \"  PHP      : $(& $phpExe -v 2>&1 | Select -First 1)\" }; Write-Host \"  TLD      : $((Get-TDZConfig -RootDir $Root).preferences.tld)\"; Write-Host '' }"
exit /b 0

:: ============================================================
:log
set "LOG_SVC=%ARG1%"
if "%LOG_SVC%"=="" set "LOG_SVC=system"
powershell -ExecutionPolicy Bypass -Command "& { $Root='%TDZ_ROOT%'; . '%TDZ_ROOT%\bin\tdz\modules\LogManager.ps1'; $r = Get-TDZLogs -RootDir $Root -Service '%LOG_SVC%' -Lines 50; if ($r.logs) { $r.logs | ForEach-Object { Write-Host $_ } } else { Write-Host '  No logs found for %LOG_SVC%' } }"
exit /b 0

:: ============================================================
:init
echo   Creating .tdz.json for current project...
powershell -ExecutionPolicy Bypass -Command "& { $Root='%TDZ_ROOT%'; . '%TDZ_ROOT%\bin\tdz\modules\LogManager.ps1'; . '%TDZ_ROOT%\bin\tdz\modules\ConfigManager.ps1'; $config = Get-TDZConfig -RootDir $Root; $projectConfig = @{ php = $config.runtimes.php.active; node = $config.runtimes.nodejs.active; env = @{ APP_ENV = 'local' }; scripts = @{ setup = 'composer install'; start = 'php artisan serve' } }; $projectConfig | ConvertTo-Json -Depth 5 | Set-Content '.tdz.json' -Encoding UTF8; Write-Host '  .tdz.json created in current directory' -ForegroundColor Green }"
exit /b 0
