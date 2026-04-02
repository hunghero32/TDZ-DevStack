# ============================================================
# TDZ DevStack - LogManager Module
# Centralized logging and log viewing
# ============================================================

function Write-TDZLog {
    param(
        [string]$RootDir,
        [string]$Service = "system",
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $logDir = Join-Path $RootDir "logs"
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "[$timestamp] [$Level] [$Service] $Message"
    
    # Write to main log
    $mainLog = Join-Path $logDir "tdz.log"
    Add-Content -Path $mainLog -Value $logLine -ErrorAction SilentlyContinue
    
    # Write to service-specific log
    if ($Service -ne "system") {
        $svcLogDir = Join-Path $logDir $Service
        if (-not (Test-Path $svcLogDir)) { New-Item -ItemType Directory -Path $svcLogDir -Force | Out-Null }
        $svcLog = Join-Path $svcLogDir "$Service.log"
        Add-Content -Path $svcLog -Value $logLine -ErrorAction SilentlyContinue
    }
    
    # Console output with color
    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARN"  { "Yellow" }
        "INFO"  { "Cyan" }
        "DEBUG" { "Gray" }
        default { "White" }
    }
    Write-Host "  $logLine" -ForegroundColor $color
}

function Get-TDZLogs {
    param(
        [string]$RootDir,
        [string]$Service = "system",
        [int]$Lines = 100,
        [string]$Level = ""
    )
    
    $logDir = Join-Path $RootDir "logs"
    
    if ($Service -eq "system" -or $Service -eq "all") {
        $logFile = Join-Path $logDir "tdz.log"
    } else {
        $logFile = Join-Path $logDir "$Service\$Service.log"
    }
    
    if (-not (Test-Path $logFile)) {
        return @{ success = $true; logs = @(); message = "No logs found for $Service" }
    }
    
    $logs = Get-Content $logFile -Tail $Lines -ErrorAction SilentlyContinue
    
    if ($Level) {
        $logs = $logs | Where-Object { $_ -match "\[$Level\]" }
    }
    
    return @{
        success = $true
        service = $Service
        count = $logs.Count
        logs = @($logs)
    }
}

function Clear-TDZLogs {
    param(
        [string]$RootDir,
        [string]$Service = "all"
    )
    
    $logDir = Join-Path $RootDir "logs"
    
    if ($Service -eq "all") {
        Get-ChildItem $logDir -Filter "*.log" -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force
        Write-TDZLog -RootDir $RootDir -Service "system" -Message "All logs cleared"
        return @{ success = $true; message = "All logs cleared" }
    } else {
        $logFile = Join-Path $logDir "$Service\$Service.log"
        if (Test-Path $logFile) { Remove-Item $logFile -Force }
        Write-TDZLog -RootDir $RootDir -Service "system" -Message "Logs cleared for $Service"
        return @{ success = $true; message = "Logs cleared for $Service" }
    }
}

function Get-ServiceLogFiles {
    param([string]$RootDir)
    
    $logDir = Join-Path $RootDir "logs"
    $files = @()
    
    if (Test-Path $logDir) {
        Get-ChildItem $logDir -Filter "*.log" -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            $files += @{
                name = $_.Name
                path = $_.FullName -replace [regex]::Escape($RootDir), ""
                size = [math]::Round($_.Length / 1KB, 1)
                lastModified = $_.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
            }
        }
    }
    
    return $files
}
