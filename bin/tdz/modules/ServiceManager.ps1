# ============================================================
# TDZ DevStack - ServiceManager Module
# PS5.1 compatible - No reserved variables, no scriptblocks in hashes
# ============================================================

function Get-ServiceExePath {
    param([string]$RootDir, [string]$ServiceName, [string]$Version)
    $bin = Join-Path $RootDir "bin"
    switch ($ServiceName) {
        "apache"    { return (Join-Path $bin "apache\$Version\bin\httpd.exe") }
        "mysql"     { return (Join-Path $bin "mysql\$Version\bin\mysqld.exe") }
        "redis"     { return (Join-Path $bin "redis\$Version\redis-server.exe") }
        "mailpit"   { return (Join-Path $bin "mailpit\$Version\mailpit.exe") }
        "memcached" { return (Join-Path $bin "memcached\$Version\memcached.exe") }
        "nginx"     { return (Join-Path $bin "nginx\$Version\nginx.exe") }
        default     { return "" }
    }
}

function Get-ServiceArgs {
    param([string]$RootDir, [string]$ServiceName, [string]$Version)
    $cfg = Get-TDZConfig -RootDir $RootDir
    switch ($ServiceName) {
        "mysql" {
            # Let my.ini handle datadir; just pass port
            return @("--port=$($cfg.services.mysql.port)")
        }
        "redis" {
            # Start with defaults - no config file needed
            return @()
        }
        "memcached" {
            $port = $cfg.services.memcached.port
            return @("-m", "64", "-p", "$port")
        }
        "nginx" {
            $ngDir = Join-Path $RootDir "bin\nginx\$Version"
            return @("-p", $ngDir)
        }
        default { return @() }
    }
}

function Get-ServiceProcessName {
    param([string]$ServiceName)
    switch ($ServiceName) {
        "apache"    { return "httpd" }
        "mysql"     { return "mysqld" }
        "redis"     { return "redis-server" }
        "mailpit"   { return "mailpit" }
        "memcached" { return "memcached" }
        "nginx"     { return "nginx" }
        default     { return $ServiceName }
    }
}

function Get-ServiceDisplayInfo {
    param([string]$ServiceName)
    switch ($ServiceName) {
        "apache"    { return @{ name = "Apache";    icon = "W"; color = "#E44D26" } }
        "mysql"     { return @{ name = "MySQL";     icon = "D"; color = "#4479A1" } }
        "redis"     { return @{ name = "Redis";     icon = "R"; color = "#DC382D" } }
        "mailpit"   { return @{ name = "Mailpit";   icon = "M"; color = "#00B4D8" } }
        "memcached" { return @{ name = "Memcached"; icon = "C"; color = "#6DB33F" } }
        "nginx"     { return @{ name = "Nginx";     icon = "N"; color = "#009639" } }
        "php"       { return @{ name = "PHP";       icon = "P"; color = "#777BB4" } }
        "nodejs"    { return @{ name = "Node.js";   icon = "J"; color = "#339933" } }
        "python"    { return @{ name = "Python";    icon = "Y"; color = "#3776AB" } }
        default     { return @{ name = $ServiceName; icon = "?"; color = "#888" } }
    }
}

function Get-InstalledVersions {
    param([string]$RootDir, [string]$Category)
    $catDir = Join-Path $RootDir "bin\$Category"
    if (Test-Path $catDir) {
        return @(Get-ChildItem $catDir -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
    }
    return @()
}

function Get-ServiceMeta {
    param([string]$RootDir)
    $cfg = Get-TDZConfig -RootDir $RootDir
    $result = @{}

    $serviceList = @("apache", "mysql", "redis", "mailpit", "memcached", "nginx")
    foreach ($svc in $serviceList) {
        $versions = Get-InstalledVersions -RootDir $RootDir -Category $svc
        $svcCfg = $cfg.services.$svc
        $info = Get-ServiceDisplayInfo -ServiceName $svc
        $isAlt = ($svc -eq "nginx")
        $port = $null
        if ($svcCfg.PSObject.Properties["port"]) { $port = $svcCfg.port }
        $result[$svc] = @{
            name        = $info.name
            processName = (Get-ServiceProcessName -ServiceName $svc)
            icon        = $info.icon
            color       = $info.color
            port        = $port
            active      = $svcCfg.active
            autoStart   = [bool]$svcCfg.autoStart
            versions    = $versions
            isRuntime   = $false
            isAlternate = $isAlt
        }
    }

    $runtimeList = @("php", "nodejs", "python")
    foreach ($rt in $runtimeList) {
        $versions = Get-InstalledVersions -RootDir $RootDir -Category $rt
        $rtCfg = $cfg.runtimes.$rt
        $info = Get-ServiceDisplayInfo -ServiceName $rt
        $result[$rt] = @{
            name        = $info.name
            icon        = $info.icon
            color       = $info.color
            active      = $rtCfg.active
            versions    = $versions
            isRuntime   = $true
            isAlternate = $false
        }
    }

    return $result
}

function Get-ProcessStatus {
    param([string]$ProcessName)
    $procs = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
    if ($procs) {
        $totalMem = 0
        foreach ($p in $procs) { $totalMem += $p.WorkingSet64 }
        return @{
            running = $true
            pid     = @($procs | Select-Object -ExpandProperty Id)
            memory  = [math]::Round($totalMem / 1MB, 1)
        }
    }
    return @{ running = $false; pid = @(); memory = 0 }
}

function Get-AllStatus {
    param([string]$RootDir)
    $meta = Get-ServiceMeta -RootDir $RootDir
    $result = @{}
    foreach ($key in $meta.Keys) {
        $svc = $meta[$key]
        $status = @{ running = $false; pid = @(); memory = 0 }
        if ($svc.processName) {
            $status = Get-ProcessStatus -ProcessName $svc.processName
        }
        $firstPid = $null
        if ($status.pid.Count -gt 0) { $firstPid = $status.pid[0] }
        $result[$key] = @{
            name        = $svc.name
            icon        = $svc.icon
            color       = $svc.color
            running     = $status.running
            pid         = $firstPid
            memory      = $status.memory
            port        = $svc.port
            active      = $svc.active
            versions    = $svc.versions
            autoStart   = [bool]$svc.autoStart
            isRuntime   = [bool]$svc.isRuntime
            isAlternate = [bool]$svc.isAlternate
        }
    }
    return $result
}

function Start-TDZService {
    param([string]$ServiceName, [string]$RootDir)
    $meta = Get-ServiceMeta -RootDir $RootDir
    $svc = $meta[$ServiceName]
    if (-not $svc) { return @{ success = $false; message = "Unknown service: $ServiceName" } }
    if ($svc.isRuntime) { return @{ success = $false; message = "$($svc.name) is a runtime, not a service" } }

    $pName = $svc.processName
    $existing = Get-ProcessStatus -ProcessName $pName
    if ($existing.running) { return @{ success = $true; message = "$($svc.name) already running (PID $($existing.pid[0]))" } }

    $exe = Get-ServiceExePath -RootDir $RootDir -ServiceName $ServiceName -Version $svc.active
    if (-not (Test-Path $exe)) { return @{ success = $false; message = "Binary not found: $exe" } }

    $svcArgs = Get-ServiceArgs -RootDir $RootDir -ServiceName $ServiceName -Version $svc.active

    try {
        Write-TDZLog -RootDir $RootDir -Service $ServiceName -Message "Starting $($svc.name)..."
        if ($svcArgs.Count -gt 0) {
            Start-Process -FilePath $exe -ArgumentList $svcArgs -WindowStyle Hidden
        } else {
            Start-Process -FilePath $exe -WindowStyle Hidden
        }
        Start-Sleep -Seconds 1

        $after = Get-ProcessStatus -ProcessName $pName
        if ($after.running) {
            Write-TDZLog -RootDir $RootDir -Service $ServiceName -Message "$($svc.name) started (PID $($after.pid[0]))"
            return @{ success = $true; message = "$($svc.name) started" }
        } else {
            Write-TDZLog -RootDir $RootDir -Service $ServiceName -Message "Failed to start $($svc.name)" -Level "ERROR"
            return @{ success = $false; message = "Failed to start $($svc.name)" }
        }
    } catch {
        Write-TDZLog -RootDir $RootDir -Service $ServiceName -Message "Error: $_" -Level "ERROR"
        return @{ success = $false; message = "Error starting $($svc.name): $_" }
    }
}

function Stop-TDZService {
    param([string]$ServiceName, [string]$RootDir)
    $meta = Get-ServiceMeta -RootDir $RootDir
    $svc = $meta[$ServiceName]
    if (-not $svc) { return @{ success = $false; message = "Unknown service: $ServiceName" } }

    $pName = $svc.processName
    $procs = Get-Process -Name $pName -ErrorAction SilentlyContinue
    if (-not $procs) { return @{ success = $true; message = "$($svc.name) is not running" } }

    Write-TDZLog -RootDir $RootDir -Service $ServiceName -Message "Stopping $($svc.name)..."

    # Graceful stop for specific services
    if ($ServiceName -eq "apache") {
        $httpd = Get-ServiceExePath -RootDir $RootDir -ServiceName "apache" -Version $svc.active
        if (Test-Path $httpd) {
            Start-Process -FilePath $httpd -ArgumentList @("-k", "stop") -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
        }
    }
    elseif ($ServiceName -eq "mysql") {
        $mysqladmin = Join-Path $RootDir "bin\mysql\$($svc.active)\bin\mysqladmin.exe"
        if (Test-Path $mysqladmin) {
            Start-Process -FilePath $mysqladmin -ArgumentList @("-u", "root", "shutdown") -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
    }

    # Force kill remaining
    $procs = Get-Process -Name $pName -ErrorAction SilentlyContinue
    if ($procs) {
        $procs | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
    }

    $after = Get-ProcessStatus -ProcessName $pName
    if (-not $after.running) {
        Write-TDZLog -RootDir $RootDir -Service $ServiceName -Message "$($svc.name) stopped"
        return @{ success = $true; message = "$($svc.name) stopped" }
    } else {
        return @{ success = $false; message = "Failed to stop $($svc.name)" }
    }
}

function Restart-TDZService {
    param([string]$ServiceName, [string]$RootDir)
    Stop-TDZService -ServiceName $ServiceName -RootDir $RootDir | Out-Null
    Start-Sleep -Milliseconds 500
    return (Start-TDZService -ServiceName $ServiceName -RootDir $RootDir)
}

function Start-AllServices {
    param([string]$RootDir)
    $results = @()
    $order = @("apache", "mysql", "redis", "mailpit", "memcached")
    $meta = Get-ServiceMeta -RootDir $RootDir
    foreach ($svc in $order) {
        if ($meta[$svc] -and $meta[$svc].autoStart) {
            $results += Start-TDZService -ServiceName $svc -RootDir $RootDir
        }
    }
    return @{ success = $true; message = "Services started"; details = $results }
}

function Stop-AllServices {
    param([string]$RootDir)
    $results = @()
    $order = @("memcached", "mailpit", "redis", "mysql", "apache", "nginx")
    foreach ($svc in $order) {
        $pName = Get-ServiceProcessName -ServiceName $svc
        $procs = Get-Process -Name $pName -ErrorAction SilentlyContinue
        if ($procs) {
            $results += Stop-TDZService -ServiceName $svc -RootDir $RootDir
        }
    }
    return @{ success = $true; message = "All services stopped"; details = $results }
}
