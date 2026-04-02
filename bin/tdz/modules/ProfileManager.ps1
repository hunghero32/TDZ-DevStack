# ============================================================
# TDZ DevStack - ProfileManager Module
# Save, load, and manage environment profiles
# ============================================================

function Save-Profile {
    param(
        [string]$RootDir,
        [string]$ProfileName,
        [string]$Description = ""
    )
    
    $profileDir = Join-Path $RootDir "usr\profiles"
    if (-not (Test-Path $profileDir)) { New-Item -ItemType Directory -Path $profileDir -Force | Out-Null }
    
    $config = Get-TDZConfig -RootDir $RootDir
    
    $profile = @{
        name        = $ProfileName
        description = $Description
        createdAt   = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        services    = $config.services
        runtimes    = $config.runtimes
        preferences = @{
            tld   = $config.preferences.tld
            theme = $config.preferences.theme
        }
    }
    
    $profilePath = Join-Path $profileDir "$ProfileName.json"
    $profile | ConvertTo-Json -Depth 10 | Set-Content -Path $profilePath -Encoding UTF8 -Force
    
    Write-TDZLog -RootDir $RootDir -Service "profile" -Message "Profile saved: $ProfileName"
    return @{ success = $true; message = "Profile '$ProfileName' saved" }
}

function Load-Profile {
    param(
        [string]$RootDir,
        [string]$ProfileName
    )
    
    $profilePath = Join-Path $RootDir "usr\profiles\$ProfileName.json"
    
    if (-not (Test-Path $profilePath)) {
        return @{ success = $false; message = "Profile '$ProfileName' not found" }
    }
    
    try {
        $profile = Get-Content $profilePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $config = Get-TDZConfig -RootDir $RootDir
        
        # Apply profile values
        if ($profile.services) { $config.services = $profile.services }
        if ($profile.runtimes) { $config.runtimes = $profile.runtimes }
        if ($profile.preferences) {
            if ($profile.preferences.tld) { $config.preferences.tld = $profile.preferences.tld }
            if ($profile.preferences.theme) { $config.preferences.theme = $profile.preferences.theme }
        }
        
        Save-TDZConfig -RootDir $RootDir -Config $config
        
        Write-TDZLog -RootDir $RootDir -Service "profile" -Message "Profile loaded: $ProfileName"
        return @{ success = $true; message = "Profile '$ProfileName' loaded. Restart services to apply changes." }
    } catch {
        return @{ success = $false; message = "Error loading profile: $_" }
    }
}

function Get-Profiles {
    param([string]$RootDir)
    
    $profileDir = Join-Path $RootDir "usr\profiles"
    $profiles = @()
    
    if (Test-Path $profileDir) {
        Get-ChildItem $profileDir -Filter "*.json" -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $p = Get-Content $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                $profiles += @{
                    name        = $p.name
                    description = $p.description
                    createdAt   = $p.createdAt
                    fileName    = $_.Name
                }
            } catch {
                $profiles += @{
                    name     = $_.BaseName
                    description = "Error reading profile"
                    createdAt = $_.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                    fileName = $_.Name
                }
            }
        }
    }
    
    return $profiles
}

function Remove-Profile {
    param(
        [string]$RootDir,
        [string]$ProfileName
    )
    
    $profilePath = Join-Path $RootDir "usr\profiles\$ProfileName.json"
    
    if (Test-Path $profilePath) {
        Remove-Item $profilePath -Force
        Write-TDZLog -RootDir $RootDir -Service "profile" -Message "Profile deleted: $ProfileName"
        return @{ success = $true; message = "Profile '$ProfileName' deleted" }
    }
    
    return @{ success = $false; message = "Profile '$ProfileName' not found" }
}
