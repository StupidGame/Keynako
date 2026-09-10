[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CertificatePath,

    [Parameter(Mandatory = $true)]
    [string]$CertificatePassword,

    [Parameter(Mandatory = $true)]
    [string[]]$Files,

    [switch]$AllowUntrustedCertificate,

    [string]$TimestampUrl = 'http://timestamp.digicert.com'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $CertificatePath -PathType Leaf)) {
    throw "Authenticode certificate not found: $CertificatePath"
}

$signToolCommand = Get-Command 'signtool.exe' -ErrorAction SilentlyContinue
if ($signToolCommand) {
    $signTool = $signToolCommand.Source
} else {
    $kitsRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    $signTool = Get-ChildItem -LiteralPath $kitsRoot -Filter 'signtool.exe' -File -Recurse |
        Where-Object { $_.FullName -match '[\\/]x64[\\/]signtool\.exe$' } |
        Sort-Object { [version]$_.Directory.Parent.Name } -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}

if (-not $signTool) {
    throw 'signtool.exe was not found in PATH or the Windows SDK.'
}

foreach ($file in $Files) {
    $resolvedFile = (Resolve-Path -LiteralPath $file).Path
    & $signTool sign /fd SHA256 /tr $TimestampUrl /td SHA256 /f $CertificatePath /p $CertificatePassword $resolvedFile
    if ($LASTEXITCODE -ne 0) {
        throw "Authenticode signing failed for $resolvedFile with exit code $LASTEXITCODE"
    }

    if ($AllowUntrustedCertificate) {
        $signature = Get-AuthenticodeSignature -LiteralPath $resolvedFile
        if ($null -eq $signature.SignerCertificate -or
            $signature.Status -eq [System.Management.Automation.SignatureStatus]::NotSigned -or
            $signature.Status -eq [System.Management.Automation.SignatureStatus]::HashMismatch) {
            throw "Authenticode integrity verification failed for $resolvedFile with status $($signature.Status)"
        }
    } else {
        & $signTool verify /pa /all $resolvedFile
        if ($LASTEXITCODE -ne 0) {
            throw "Authenticode verification failed for $resolvedFile with exit code $LASTEXITCODE"
        }
    }
}
