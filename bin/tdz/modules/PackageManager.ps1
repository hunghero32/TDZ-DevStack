# ============================================================
# TDZ DevStack - PackageManager Module
# Download, install, and manage packages (PHP, MySQL, etc.)
# ============================================================

function Get-PackageRegistry {
    param([string]$RootDir)
    
    $localRegistry = Join-Path $RootDir "bin\tdz\registry\packages.json"
    
    if (Test-Path $localRegistry) {
        try {
            return (Get-Content $localRegistry -Raw -Encoding UTF8 | ConvertFrom-Json)
        } catch {
            Write-Warning "Failed to parse local registry"
        }
    }
    
    # Also check packages.conf for legacy format
    $packagesConf = Join-Path $RootDir "usr\packages.conf"
    if (Test-Path $packagesConf) {
        return (Import-PackagesConf -Path $packagesConf)
    }
    
    return @{ packages = @{} }
}

function Import-PackagesConf {
    param([string]$Path)
    
    $packages = @{}
    $currentCategory = "other"
    
    Get-Content $Path | ForEach-Object {
        $line = $_.Trim()
        if ($line -match '^#\s*(.+)') {
            $comment = $matches[1].Trim()
            if ($comment -match '(PHP|Web Servers|Node|MySQL|PostgreSQL|MongoDB|DB Tools)') {
                $currentCategory = $matches[1].ToLower() -replace '\s+', '_'
            }
        }
        elseif ($line -match '^[\*]?([^=]+)=(.+)$') {
            $name = $matches[1].Trim()
            $url = $matches[2].Trim()
            $isDefault = $line.StartsWith("*")
            
            if (-not $packages[$currentCategory]) { $packages[$currentCategory] = @{} }
            $packages[$currentCategory][$name] = @{
                url = $url
                default = $isDefault
                name = $name
            }
        }
    }
    
    return @{ packages = $packages }
}

function Get-InstalledPackages {
    param([string]$RootDir)
    
    $binDir = Join-Path $RootDir "bin"
    $categories = @("php", "mysql", "apache", "nginx", "nodejs", "redis", "memcached", "python", "mailpit")
    $installed = @{}
    
    foreach ($cat in $categories) {
        $catDir = Join-Path $binDir $cat
        if (Test-Path $catDir) {
            $versions = @(Get-ChildItem $catDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                @{
                    name = $_.Name
                    path = $_.FullName
                    size = [math]::Round((Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1MB, 1)
                }
            })
            $installed[$cat] = $versions
        }
    }
    
    return $installed
}

function Install-Package {
    param(
        [string]$RootDir,
        [string]$PackageName,
        [string]$Url,
        [string]$ExtractTo
    )
    
    if (-not $Url) {
        # Try to find URL from registry
        $registry = Get-PackageRegistry -RootDir $RootDir
        # Search in packages
        foreach ($cat in $registry.packages.PSObject.Properties) {
            foreach ($pkg in $cat.Value.PSObject.Properties) {
                if ($pkg.Name -eq $PackageName) {
                    $Url = $pkg.Value.url
                    break
                }
            }
        }
        
        if (-not $Url) {
            return @{ success = $false; message = "Package '$PackageName' not found in registry. Provide a URL." }
        }
    }
    
    $tmpDir = Join-Path $RootDir "tmp"
    if (-not (Test-Path $tmpDir)) { New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null }
    
    $fileName = [System.IO.Path]::GetFileName([System.Uri]::new($Url).AbsolutePath)
    $downloadPath = Join-Path $tmpDir $fileName
    
    Write-TDZLog -RootDir $RootDir -Service "package" -Message "Downloading $PackageName from $Url..."
    
    try {
        # Download
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add('User-Agent', 'TDZ-DevStack/1.0')
        $webClient.DownloadFile($Url, $downloadPath)
        
        if (-not (Test-Path $downloadPath)) {
            return @{ success = $false; message = "Download failed" }
        }
        
        # Determine extract target
        if (-not $ExtractTo) {
            # Auto-detect based on package name
            if ($PackageName -match "php") { $ExtractTo = "bin\php" }
            elseif ($PackageName -match "mysql") { $ExtractTo = "bin\mysql" }
            elseif ($PackageName -match "node") { $ExtractTo = "bin\nodejs" }
            elseif ($PackageName -match "apache|httpd") { $ExtractTo = "bin\apache" }
            elseif ($PackageName -match "nginx") { $ExtractTo = "bin\nginx" }
            elseif ($PackageName -match "redis") { $ExtractTo = "bin\redis" }
            elseif ($PackageName -match "postgres") { $ExtractTo = "bin\postgresql" }
            else { $ExtractTo = "bin\$PackageName" }
        }
        
        $targetDir = Join-Path $RootDir $ExtractTo
        if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
        
        Write-TDZLog -RootDir $RootDir -Service "package" -Message "Extracting $fileName to $ExtractTo..."
        
        # Extract based on file type
        if ($fileName -match '\.zip$') {
            Expand-Archive -Path $downloadPath -DestinationPath $targetDir -Force
        }
        elseif ($fileName -match '\.(tar\.gz|tgz)$') {
            # Use tar if available (Windows 10+)
            $tarExe = Get-Command tar -ErrorAction SilentlyContinue
            if ($tarExe) {
                & tar -xzf $downloadPath -C $targetDir 2>&1 | Out-Null
            } else {
                return @{ success = $false; message = "tar not available. Please extract manually: $downloadPath -> $targetDir" }
            }
        }
        elseif ($fileName -match '\.tar\.xz$') {
            $tarExe = Get-Command tar -ErrorAction SilentlyContinue
            if ($tarExe) {
                & tar -xJf $downloadPath -C $targetDir 2>&1 | Out-Null
            } else {
                return @{ success = $false; message = "tar not available for .tar.xz files" }
            }
        }
        
        # Clean up download
        Remove-Item $downloadPath -Force -ErrorAction SilentlyContinue
        
        Write-TDZLog -RootDir $RootDir -Service "package" -Message "$PackageName installed successfully to $ExtractTo"
        return @{ success = $true; message = "$PackageName installed to $ExtractTo" }
    } catch {
        return @{ success = $false; message = "Installation failed: $_" }
    }
}

function Remove-Package {
    param(
        [string]$RootDir,
        [string]$Category,
        [string]$Version
    )
    
    $targetDir = Join-Path $RootDir "bin\$Category\$Version"
    
    if (-not (Test-Path $targetDir)) {
        return @{ success = $false; message = "Package not found: $Category/$Version" }
    }
    
    # Check if it's the active version
    $config = Get-TDZConfig -RootDir $RootDir
    $isActive = $false
    
    if ($config.services.PSObject.Properties[$Category]) {
        $isActive = $config.services.$Category.active -eq $Version
    } elseif ($config.runtimes.PSObject.Properties[$Category]) {
        $isActive = $config.runtimes.$Category.active -eq $Version
    }
    
    if ($isActive) {
        return @{ success = $false; message = "Cannot remove active version '$Version'. Switch to another version first." }
    }
    
    Remove-Item $targetDir -Recurse -Force
    Write-TDZLog -RootDir $RootDir -Service "package" -Message "Removed $Category/$Version"
    
    return @{ success = $true; message = "Removed $Category/$Version" }
}

function Update-RemoteRegistry {
    param([string]$RootDir)
    
    $config = Get-TDZConfig -RootDir $RootDir
    $registryUrl = $config.packages.registryUrl
    $localRegistry = Join-Path $RootDir "bin\tdz\registry\packages.json"
    
    if (-not $registryUrl) {
        return @{ success = $false; message = "No registry URL configured" }
    }
    
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add('User-Agent', 'TDZ-DevStack/1.0')
        $content = $webClient.DownloadString($registryUrl)
        
        # Validate JSON
        $null = $content | ConvertFrom-Json
        
        Set-Content -Path $localRegistry -Value $content -Encoding UTF8 -Force
        Write-TDZLog -RootDir $RootDir -Service "package" -Message "Registry updated from $registryUrl"
        
        return @{ success = $true; message = "Package registry updated" }
    } catch {
        return @{ success = $false; message = "Failed to update registry: $_" }
    }
}
