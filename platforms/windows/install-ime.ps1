param(
  [string]$PackageDirectory = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
$package = (Resolve-Path -LiteralPath $PackageDirectory).Path
$dll = Join-Path $package 'KeynakoIME.dll'
if (-not (Test-Path -LiteralPath $dll -PathType Leaf)) {
  throw "KeynakoIME.dll was not found in $package"
}

$installRoot = Join-Path $env:LOCALAPPDATA 'Keynako\IME'
New-Item -ItemType Directory -Force -Path $installRoot | Out-Null
Get-ChildItem -LiteralPath $package | Copy-Item -Destination $installRoot -Recurse -Force
$installedDll = Join-Path $installRoot 'KeynakoIME.dll'
& "$env:SystemRoot\System32\regsvr32.exe" /s $installedDll
if ($LASTEXITCODE -ne 0) { throw "regsvr32 failed with exit code $LASTEXITCODE" }

Write-Output 'Keynako IME was installed. Select Keynako from Windows input settings.'
