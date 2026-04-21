# test-ssl-cert.ps1 -Url <https-url> -OutJson <path>
# - Fetches SSL certificate using X509Certificate2
# - Emits JSON to -OutJson
# - Deterministic portion of check-cert command

param(
    [Parameter(Mandatory=$true)][string]$Url,
    [Parameter(Mandatory=$true)][string]$OutJson
)

$uri = [System.Uri]$Url
if ($uri.Scheme -ne 'https') {
    Write-Error "URL must be https: $Url"
    exit 2
}

$host = $uri.Host
$port = if ($uri.Port -gt 0) { $uri.Port } else { 443 }

try {
    $tcp = New-Object System.Net.Sockets.TcpClient($host, $port)
    $ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false, ({ $true }))
    $ssl.AuthenticateAsClient($host)
    $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $ssl.RemoteCertificate
    $daysRemaining = ($cert.NotAfter - (Get-Date)).Days
    $result = [ordered]@{
        url = $Url
        valid = ((Get-Date) -lt $cert.NotAfter -and (Get-Date) -gt $cert.NotBefore)
        issuer = $cert.Issuer
        subject = $cert.Subject
        not_before = $cert.NotBefore.ToString('yyyy-MM-ddTHH:mm:ssZ')
        not_after = $cert.NotAfter.ToString('yyyy-MM-ddTHH:mm:ssZ')
        days_remaining = $daysRemaining
        thumbprint = $cert.Thumbprint
    }
    $ssl.Close(); $tcp.Close()
    $result | ConvertTo-Json | Set-Content -Path $OutJson -Encoding UTF8
    Write-Host "[test-ssl-cert] $Url : valid=$($result.valid), days=$daysRemaining"
    exit 0
} catch {
    $err = [ordered]@{
        url = $Url
        valid = $false
        error = $_.Exception.Message
    }
    $err | ConvertTo-Json | Set-Content -Path $OutJson -Encoding UTF8
    Write-Error $_.Exception.Message
    exit 1
}
