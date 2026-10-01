# Creates a self-signed code signing certificate for sideloading development UWP packages.
#
# Writes a password-protected .pfx for signing, and a .cer with only the public certificate,
# which Windows needs in its trusted people store to install a package signed with it.
# Nothing is added to any certificate store. The subject must match the Publisher in
# AppxManifest.xml.
param(
    [Parameter(Mandatory = $true)]
    [string]$Publisher,

    [Parameter(Mandatory = $true)]
    [string]$OutputPfx,

    [Parameter(Mandatory = $true)]
    [string]$Password
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$outputPath = [System.IO.Path]::GetFullPath($OutputPfx)
[System.IO.Directory]::CreateDirectory((Split-Path -Parent $outputPath)) | Out-Null

$X509 = "System.Security.Cryptography.X509Certificates"
$rsa = [System.Security.Cryptography.RSA]::Create(2048)
try {
    $request = New-Object "$X509.CertificateRequest" `
        $Publisher, $rsa, ([System.Security.Cryptography.HashAlgorithmName]::SHA256),
        ([System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
    $request.CertificateExtensions.Add((New-Object "$X509.X509BasicConstraintsExtension" $false, $false, 0, $true))
    $request.CertificateExtensions.Add((New-Object "$X509.X509KeyUsageExtension" `
        ([System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::DigitalSignature), $true))
    $codeSigning = New-Object System.Security.Cryptography.OidCollection
    $codeSigning.Add((New-Object System.Security.Cryptography.Oid "1.3.6.1.5.5.7.3.3")) | Out-Null
    $request.CertificateExtensions.Add((New-Object "$X509.X509EnhancedKeyUsageExtension" $codeSigning, $false))

    $now = [System.DateTimeOffset]::UtcNow
    $certificate = $request.CreateSelfSigned($now.AddDays(-1), $now.AddYears(5))
    try {
        [System.IO.File]::WriteAllBytes($outputPath,
            $certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx, $Password))
        [System.IO.File]::WriteAllBytes([System.IO.Path]::ChangeExtension($outputPath, ".cer"),
            $certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert))
    } finally {
        $certificate.Dispose()
    }
} finally {
    $rsa.Dispose()
}
