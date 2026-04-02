# ============================================================
# TDZ DevStack - ConfigEditorManager Module
# Read/write config files, PHP extensions, Quick Open
# ============================================================

function Get-ConfigFilePath {
    param([string]$RootDir, [string]$ServiceName, [string]$FileType)
    $cfg = Get-TDZConfig -RootDir $RootDir
    switch ($ServiceName) {
        "apache" {
            $ver = $cfg.services.apache.active
            switch ($FileType) {
                "main"    { return (Join-Path $RootDir "bin\apache\$ver\conf\httpd.conf") }
                "ssl"     { return (Join-Path $RootDir "etc\apache2\httpd-ssl.conf") }
                "vhosts"  { return (Join-Path $RootDir "etc\apache2\sites-enabled") }
                "mod_php" { return (Join-Path $RootDir "etc\apache2\mod_php.conf") }
                default   { return (Join-Path $RootDir "bin\apache\$ver\conf\httpd.conf") }
            }
        }
        "mysql" {
            $ver = $cfg.services.mysql.active
            return (Join-Path $RootDir "bin\mysql\$ver\my.ini")
        }
        "php" {
            $ver = $cfg.runtimes.php.active
            return (Join-Path $RootDir "bin\php\$ver\php.ini")
        }
        "nginx" {
            $ver = $cfg.services.nginx.active
            return (Join-Path $RootDir "bin\nginx\$ver\conf\nginx.conf")
        }
        "redis" {
            $ver = $cfg.services.redis.active
            return (Join-Path $RootDir "bin\redis\$ver\redis.windows.conf")
        }
        "hosts" {
            return "C:\Windows\System32\drivers\etc\hosts"
        }
        default { return "" }
    }
}

function Get-ConfigFileContent {
    param([string]$RootDir, [string]$ServiceName, [string]$FileType)
    $filePath = Get-ConfigFilePath -RootDir $RootDir -ServiceName $ServiceName -FileType $FileType
    if (-not $filePath -or -not (Test-Path $filePath)) {
        return @{ success = $false; message = "Config file not found: $filePath"; path = "$filePath" }
    }
    try {
        $content = Get-Content $filePath -Raw -Encoding UTF8 -ErrorAction Stop
        return @{
            success = $true
            path    = $filePath
            content = $content
            size    = (Get-Item $filePath).Length
            modified = (Get-Item $filePath).LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
        }
    } catch {
        return @{ success = $false; message = "Cannot read: $_"; path = "$filePath" }
    }
}

function Save-ConfigFileContent {
    param([string]$RootDir, [string]$FilePath, [string]$Content)
    if (-not $FilePath) { return @{ success = $false; message = "No file path" } }

    # Security: only allow files within TDZ root or hosts file
    $hostsPath = "C:\Windows\System32\drivers\etc\hosts"
    $normalPath = [System.IO.Path]::GetFullPath($FilePath)
    $normalRoot = [System.IO.Path]::GetFullPath($RootDir)
    if (-not $normalPath.StartsWith($normalRoot) -and $normalPath -ne $hostsPath) {
        return @{ success = $false; message = "Access denied: path outside TDZ root" }
    }

    try {
        # Auto backup
        $bakPath = "$FilePath.bak"
        if (Test-Path $FilePath) {
            Copy-Item $FilePath $bakPath -Force -ErrorAction SilentlyContinue
        }
        Set-Content -Path $FilePath -Value $Content -Encoding UTF8 -Force -NoNewline
        Write-TDZLog -RootDir $RootDir -Service "config" -Message "Saved config: $FilePath"
        return @{ success = $true; message = "Config saved (backup: .bak)"; path = $FilePath }
    } catch {
        return @{ success = $false; message = "Save failed: $_" }
    }
}

function Get-AvailableConfigFiles {
    param([string]$RootDir)
    $cfg = Get-TDZConfig -RootDir $RootDir
    $files = @()

    # Apache
    $apVer = $cfg.services.apache.active
    $apConf = Join-Path $RootDir "bin\apache\$apVer\conf\httpd.conf"
    if (Test-Path $apConf) { $files += @{ service = "apache"; label = "httpd.conf"; path = $apConf } }
    $apSsl = Join-Path $RootDir "etc\apache2\httpd-ssl.conf"
    if (Test-Path $apSsl) { $files += @{ service = "apache"; label = "httpd-ssl.conf"; path = $apSsl } }

    # MySQL
    $myVer = $cfg.services.mysql.active
    $myIni = Join-Path $RootDir "bin\mysql\$myVer\my.ini"
    if (Test-Path $myIni) { $files += @{ service = "mysql"; label = "my.ini"; path = $myIni } }

    # PHP (all versions)
    $phpVer = $cfg.runtimes.php.active
    $phpIni = Join-Path $RootDir "bin\php\$phpVer\php.ini"
    if (Test-Path $phpIni) { $files += @{ service = "php"; label = "php.ini ($phpVer)"; path = $phpIni } }

    # Nginx
    $ngVer = $cfg.services.nginx.active
    $ngConf = Join-Path $RootDir "bin\nginx\$ngVer\conf\nginx.conf"
    if (Test-Path $ngConf) { $files += @{ service = "nginx"; label = "nginx.conf"; path = $ngConf } }

    # Redis
    $rdVer = $cfg.services.redis.active
    $rdConf = Join-Path $RootDir "bin\redis\$rdVer\redis.windows.conf"
    if (Test-Path $rdConf) { $files += @{ service = "redis"; label = "redis.windows.conf"; path = $rdConf } }

    # Hosts
    $hostsFile = "C:\Windows\System32\drivers\etc\hosts"
    if (Test-Path $hostsFile) { $files += @{ service = "system"; label = "hosts"; path = $hostsFile } }

    return $files
}

# ============================================================
# PHP Extensions
# ============================================================
function Get-PHPExtensions {
    param([string]$RootDir)
    $cfg = Get-TDZConfig -RootDir $RootDir
    $phpVer = $cfg.runtimes.php.active
    $phpIni = Join-Path $RootDir "bin\php\$phpVer\php.ini"

    if (-not (Test-Path $phpIni)) {
        return @{ success = $false; message = "php.ini not found"; extensions = @() }
    }

    $extensions = @()
    $lines = Get-Content $phpIni -ErrorAction SilentlyContinue
    $lineNum = 0
    foreach ($line in $lines) {
        $lineNum++
        $trimmed = $line.Trim()
        if ($trimmed -match '^;?\s*extension\s*=\s*(.+)$') {
            $extName = $matches[1].Trim()
            $enabled = -not $trimmed.StartsWith(";")
            $extensions += @{
                name    = $extName
                enabled = $enabled
                line    = $lineNum
            }
        }
    }

    return @{
        success    = $true
        phpVersion = $phpVer
        iniPath    = $phpIni
        extensions = $extensions
    }
}

function Set-PHPExtension {
    param([string]$RootDir, [string]$ExtName, [bool]$Enabled)
    $cfg = Get-TDZConfig -RootDir $RootDir
    $phpVer = $cfg.runtimes.php.active
    $phpIni = Join-Path $RootDir "bin\php\$phpVer\php.ini"

    if (-not (Test-Path $phpIni)) {
        return @{ success = $false; message = "php.ini not found" }
    }

    # Backup
    Copy-Item $phpIni "$phpIni.bak" -Force -ErrorAction SilentlyContinue

    $lines = Get-Content $phpIni
    $found = $false
    $newLines = @()
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^;?\s*extension\s*=\s*(.+)$') {
            $thisExt = $matches[1].Trim()
            if ($thisExt -eq $ExtName) {
                $found = $true
                if ($Enabled) {
                    $newLines += "extension=$ExtName"
                } else {
                    $newLines += ";extension=$ExtName"
                }
                continue
            }
        }
        $newLines += $line
    }

    if (-not $found) {
        return @{ success = $false; message = "Extension '$ExtName' not found in php.ini" }
    }

    $newLines | Set-Content $phpIni -Encoding UTF8 -Force
    $action = if ($Enabled) { "enabled" } else { "disabled" }
    Write-TDZLog -RootDir $RootDir -Service "php" -Message "Extension $ExtName $action"
    return @{ success = $true; message = "Extension $ExtName $action" }
}

# ============================================================
# Port Management
# ============================================================
function Set-ServicePort {
    param([string]$RootDir, [string]$ServiceName, [int]$NewPort)

    $cfg = Get-TDZConfig -RootDir $RootDir

    # Update tdz.json
    switch ($ServiceName) {
        "apache"    { $cfg.services.apache.port = $NewPort }
        "mysql"     { $cfg.services.mysql.port = $NewPort }
        "redis"     { $cfg.services.redis.port = $NewPort }
        "memcached" { $cfg.services.memcached.port = $NewPort }
        "nginx"     { $cfg.services.nginx.port = $NewPort }
        default     { return @{ success = $false; message = "Unknown service" } }
    }
    Save-TDZConfig -RootDir $RootDir -Config $cfg

    # Also update config files
    switch ($ServiceName) {
        "apache" {
            $confPath = Get-ConfigFilePath -RootDir $RootDir -ServiceName "apache" -FileType "main"
            if (Test-Path $confPath) {
                $content = Get-Content $confPath -Raw -Encoding UTF8
                $content = $content -replace 'Listen\s+\d+', "Listen $NewPort"
                Set-Content $confPath $content -Encoding UTF8 -Force -NoNewline
            }
        }
        "mysql" {
            $confPath = Get-ConfigFilePath -RootDir $RootDir -ServiceName "mysql"
            if (Test-Path $confPath) {
                $content = Get-Content $confPath -Raw -Encoding UTF8
                $content = $content -replace 'port\s*=\s*\d+', "port=$NewPort"
                Set-Content $confPath $content -Encoding UTF8 -Force -NoNewline
            }
        }
    }

    Write-TDZLog -RootDir $RootDir -Service $ServiceName -Message "Port changed to $NewPort"
    return @{ success = $true; message = "$ServiceName port set to $NewPort. Restart service to apply." }
}

# ============================================================
# Quick Open
# ============================================================
function Open-TDZPath {
    param([string]$RootDir, [string]$Path, [string]$OpenType)

    $fullPath = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $RootDir $Path }

    if (-not (Test-Path $fullPath)) {
        return @{ success = $false; message = "Path not found: $fullPath" }
    }

    switch ($OpenType) {
        "explorer" {
            if (Test-Path $fullPath -PathType Container) {
                Start-Process "explorer.exe" $fullPath
            } else {
                Start-Process "explorer.exe" "/select,$fullPath"
            }
        }
        "code" {
            $codePath = Get-Command "code" -ErrorAction SilentlyContinue
            if ($codePath) {
                Start-Process "code" $fullPath
            } else {
                Start-Process "notepad.exe" $fullPath
            }
        }
        "terminal" {
            $dir = if (Test-Path $fullPath -PathType Container) { $fullPath } else { Split-Path $fullPath }
            Start-Process "cmd.exe" "/k cd /d `"$dir`""
        }
        "notepad" {
            Start-Process "notepad.exe" $fullPath
        }
        default {
            Start-Process $fullPath
        }
    }

    return @{ success = $true; message = "Opened: $fullPath" }
}
