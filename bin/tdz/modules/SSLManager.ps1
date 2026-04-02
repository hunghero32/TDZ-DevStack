# ============================================================
# TDZ DevStack - SSLManager Module
# Self-signed SSL certificate generation and management
# ============================================================

function Initialize-SSLCA {
    param([string]$RootDir)
    
    $sslDir = Join-Path $RootDir "etc\ssl"
    $caDir = Join-Path $sslDir "ca"
    $certsDir = Join-Path $sslDir "certs"
    
    foreach ($dir in @($sslDir, $caDir, $certsDir)) {
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    }
    
    $caKey = Join-Path $caDir "TDZ-CA.key"
    $caCert = Join-Path $caDir "TDZ-CA.crt"
    
    if ((Test-Path $caKey) -and (Test-Path $caCert)) {
        return @{ success = $true; message = "CA already initialized" }
    }
    
    # Find openssl binary
    $openssl = Find-OpenSSL -RootDir $RootDir
    if (-not $openssl) {
        return @{ success = $false; message = "OpenSSL not found. Install Apache or add OpenSSL to bin/" }
    }
    
    # Generate CA key
    & $openssl genrsa -out $caKey 4096 2>&1 | Out-Null
    
    # Generate CA certificate
    & $openssl req -x509 -new -nodes -key $caKey -sha256 -days 3650 -out $caCert -subj "/C=VN/ST=HCMC/O=TDZ DevStack/CN=TDZ DevStack Local CA" 2>&1 | Out-Null
    
    if ((Test-Path $caKey) -and (Test-Path $caCert)) {
        Write-TDZLog -RootDir $RootDir -Service "ssl" -Message "CA certificate initialized"
        return @{ success = $true; message = "CA certificate generated. Import TDZ-CA.crt to your browser to trust local SSL." }
    }
    
    return @{ success = $false; message = "Failed to generate CA certificate" }
}

function New-SSLCertificate {
    param(
        [string]$RootDir,
        [string]$Domain
    )
    
    # Ensure CA exists
    $caResult = Initialize-SSLCA -RootDir $RootDir
    if (-not $caResult.success -and $caResult.message -notlike "*already*") {
        return $caResult
    }
    
    $sslDir = Join-Path $RootDir "etc\ssl"
    $caKey = Join-Path $sslDir "ca\TDZ-CA.key"
    $caCert = Join-Path $sslDir "ca\TDZ-CA.crt"
    $certsDir = Join-Path $sslDir "certs"
    
    $certKey = Join-Path $certsDir "$Domain.key"
    $certCSR = Join-Path $certsDir "$Domain.csr"
    $certCRT = Join-Path $certsDir "$Domain.crt"
    $extFile = Join-Path $certsDir "$Domain.ext"
    
    $openssl = Find-OpenSSL -RootDir $RootDir
    if (-not $openssl) {
        return @{ success = $false; message = "OpenSSL not found" }
    }
    
    # Create extension file for SAN
    $extContent = @"
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage=digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName=@alt_names

[alt_names]
DNS.1=$Domain
DNS.2=*.$Domain
DNS.3=localhost
IP.1=127.0.0.1
"@
    Set-Content -Path $extFile -Value $extContent -Force
    
    # Generate private key
    & $openssl genrsa -out $certKey 2048 2>&1 | Out-Null
    
    # Generate CSR
    & $openssl req -new -key $certKey -out $certCSR -subj "/C=VN/ST=HCMC/O=TDZ DevStack/CN=$Domain" 2>&1 | Out-Null
    
    # Sign with CA
    & $openssl x509 -req -in $certCSR -CA $caCert -CAkey $caKey -CAcreateserial -out $certCRT -days 825 -sha256 -extfile $extFile 2>&1 | Out-Null
    
    # Clean up CSR and ext file
    Remove-Item $certCSR -Force -ErrorAction SilentlyContinue
    Remove-Item $extFile -Force -ErrorAction SilentlyContinue
    
    if ((Test-Path $certKey) -and (Test-Path $certCRT)) {
        Write-TDZLog -RootDir $RootDir -Service "ssl" -Message "SSL certificate generated for $Domain"
        return @{
            success = $true
            message = "SSL certificate generated for $Domain"
            certPath = $certCRT
            keyPath = $certKey
        }
    }
    
    return @{ success = $false; message = "Failed to generate SSL certificate for $Domain" }
}

function Get-SSLCertificates {
    param([string]$RootDir)
    
    $certsDir = Join-Path $RootDir "etc\ssl\certs"
    $certs = @()
    
    if (Test-Path $certsDir) {
        Get-ChildItem $certsDir -Filter "*.crt" -ErrorAction SilentlyContinue | ForEach-Object {
            $domain = $_.BaseName
            $keyFile = Join-Path $certsDir "$domain.key"
            $certs += @{
                domain = $domain
                certFile = $_.Name
                hasKey = (Test-Path $keyFile)
                created = $_.CreationTime.ToString("yyyy-MM-dd HH:mm:ss")
                expires = $_.LastWriteTime.AddDays(825).ToString("yyyy-MM-dd")
            }
        }
    }
    
    return $certs
}

function Find-OpenSSL {
    param([string]$RootDir)
    
    # Check Apache's openssl first
    $meta = Get-ServiceMeta -RootDir $RootDir
    $apacheActive = $meta.apache.active
    $apacheOpenSSL = Join-Path $RootDir "bin\apache\$apacheActive\bin\openssl.exe"
    
    if (Test-Path $apacheOpenSSL) { return $apacheOpenSSL }
    
    # Check in PATH
    $inPath = Get-Command openssl -ErrorAction SilentlyContinue
    if ($inPath) { return $inPath.Source }
    
    # Check common locations
    $candidates = @(
        (Join-Path $RootDir "bin\openssl\openssl.exe"),
        "C:\Program Files\OpenSSL-Win64\bin\openssl.exe",
        "C:\Program Files\Git\usr\bin\openssl.exe"
    )
    
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }
    
    return $null
}
