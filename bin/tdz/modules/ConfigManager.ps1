# ============================================================
# TDZ DevStack - ConfigManager Module
# Manages reading/writing JSON configuration
# ============================================================

function Get-TDZRoot {
    # Auto-detect TDZ root by walking up from script location
    $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    
    # Walk up from bin/tdz/modules/ to root
    $root = (Resolve-Path (Join-Path $scriptDir "..\..\..")).Path
    
    # Validate it's a TDZ root
    if (-not (Test-Path (Join-Path $root "usr"))) {
        # Fallback: try common locations
        $candidates = @(
            $env:TDZ_ROOT,
            (Join-Path $PSScriptRoot "..\..\.."),
            "C:\TDZ env",
            (Join-Path $env:USERPROFILE "Desktop\TDZ env")
        )
        foreach ($c in $candidates) {
            if ($c -and (Test-Path (Join-Path $c "usr"))) {
                $root = (Resolve-Path $c).Path
                break
            }
        }
    }
    
    return $root
}

function Get-TDZConfig {
    param([string]$RootDir)
    
    $configPath = Join-Path $RootDir "usr\tdz.json"
    
    if (Test-Path $configPath) {
        try {
            return (Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json)
        } catch {
            Write-Warning "Failed to parse tdz.json: $_"
        }
    }
    
    # Fallback: try to migrate from laragon.ini
    $iniPath = Join-Path $RootDir "usr\laragon.ini"
    if (Test-Path $iniPath) {
        return (Import-LaragonIni -IniPath $iniPath -RootDir $RootDir)
    }
    
    # Return defaults
    return Get-DefaultConfig
}

function Save-TDZConfig {
    param(
        [string]$RootDir,
        [PSCustomObject]$Config
    )
    
    $configPath = Join-Path $RootDir "usr\tdz.json"
    $Config | ConvertTo-Json -Depth 10 | Set-Content -Path $configPath -Encoding UTF8 -Force
}

function Get-DefaultConfig {
    return [PSCustomObject]@{
        version = "1.0.0"
        name = "TDZ DevStack"
        preferences = [PSCustomObject]@{
            autoStart = $false
            autoVirtualHosts = $true
            tld = ".test"
            language = "vi"
            theme = "dark"
            apiPort = 9100
            dashboardAutoOpen = $true
            logLevel = "info"
        }
        services = [PSCustomObject]@{
            apache = [PSCustomObject]@{ active = ""; autoStart = $true; port = 80; sslPort = 443 }
            mysql = [PSCustomObject]@{ active = ""; autoStart = $true; port = 3306; rootPassword = "" }
            redis = [PSCustomObject]@{ active = ""; autoStart = $true; port = 6379 }
            memcached = [PSCustomObject]@{ active = ""; autoStart = $true; port = 11211 }
            mailpit = [PSCustomObject]@{ active = "mailpit"; autoStart = $true; smtpPort = 1025; uiPort = 8025 }
            nginx = [PSCustomObject]@{ active = ""; autoStart = $false; port = 80; isAlternate = $true }
        }
        runtimes = [PSCustomObject]@{
            php = [PSCustomObject]@{ active = "" }
            nodejs = [PSCustomObject]@{ active = "" }
            python = [PSCustomObject]@{ active = "" }
        }
        packages = [PSCustomObject]@{
            registryUrl = "https://raw.githubusercontent.com/tdz-devstack/registry/main/packages.json"
            sourcesFile = "packages.conf"
        }
    }
}

function Import-LaragonIni {
    param(
        [string]$IniPath,
        [string]$RootDir
    )
    
    $config = Get-DefaultConfig
    $ini = @{}
    $section = ""
    
    Get-Content $IniPath | ForEach-Object {
        $line = $_.Trim()
        if ($line -match '^\[(.+)\]$') { $section = $matches[1] }
        elseif ($line -match '^(\w+)=(.*)$') { $ini["$section.$($matches[1])"] = $matches[2] }
    }
    
    # Map INI values to JSON config
    if ($ini["apache.Version"]) { $config.services.apache.active = $ini["apache.Version"] }
    if ($ini["mysql.Version"]) { $config.services.mysql.active = $ini["mysql.Version"] }
    if ($ini["redis.Version"]) { $config.services.redis.active = $ini["redis.Version"] }
    if ($ini["memcached.Version"]) { $config.services.memcached.active = $ini["memcached.Version"] }
    if ($ini["nginx.Version"]) { $config.services.nginx.active = $ini["nginx.Version"] }
    if ($ini["php.Version"]) { $config.runtimes.php.active = $ini["php.Version"] }
    if ($ini["nodejs.Version"]) { $config.runtimes.nodejs.active = $ini["nodejs.Version"] }
    if ($ini["python.Version"]) { $config.runtimes.python.active = $ini["python.Version"] }
    
    # Auto-detect versions from bin directories
    $binDir = Join-Path $RootDir "bin"
    $serviceMap = @{
        "apache" = "services.apache"
        "mysql" = "services.mysql"
        "redis" = "services.redis"
        "memcached" = "services.memcached"
        "nginx" = "services.nginx"
        "php" = "runtimes.php"
        "nodejs" = "runtimes.nodejs"
        "python" = "runtimes.python"
    }
    
    foreach ($svc in $serviceMap.Keys) {
        $svcDir = Join-Path $binDir $svc
        if (Test-Path $svcDir) {
            $versions = @(Get-ChildItem $svcDir -Directory | Select-Object -ExpandProperty Name)
            $path = $serviceMap[$svc]
            $parts = $path -split '\.'
            $obj = $config
            for ($i = 0; $i -lt $parts.Count - 1; $i++) {
                $obj = $obj.($parts[$i])
            }
            $prop = $parts[-1]
            if (-not $obj.$prop.active -and $versions.Count -gt 0) {
                $obj.$prop.active = $versions[-1]
            }
        }
    }
    
    # Save migrated config
    Save-TDZConfig -RootDir $RootDir -Config $config
    Write-Host "  [ConfigManager] Migrated laragon.ini -> tdz.json" -ForegroundColor Green
    
    return $config
}

function Get-ProjectConfig {
    param(
        [string]$ProjectPath,
        [string]$RootDir
    )
    
    $projectConfigPath = Join-Path $ProjectPath ".tdz.json"
    $globalConfig = Get-TDZConfig -RootDir $RootDir
    
    if (Test-Path $projectConfigPath) {
        try {
            $projectConfig = Get-Content $projectConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
            return $projectConfig
        } catch {
            Write-Warning "Failed to parse .tdz.json in $ProjectPath"
        }
    }
    
    return $null
}

function Update-ConfigValue {
    param(
        [string]$RootDir,
        [string]$Path,
        $Value
    )
    
    $config = Get-TDZConfig -RootDir $RootDir
    $parts = $Path -split '\.'
    $obj = $config
    
    for ($i = 0; $i -lt $parts.Count - 1; $i++) {
        $obj = $obj.($parts[$i])
    }
    
    $prop = $parts[-1]
    $obj.$prop = $Value
    
    Save-TDZConfig -RootDir $RootDir -Config $config
    return $config
}
