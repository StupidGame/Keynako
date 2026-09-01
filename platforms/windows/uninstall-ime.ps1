$ErrorActionPreference = 'Stop'
$installRoot = Join-Path $env:LOCALAPPDATA 'Keynako\IME'
$registration = 'Registry::HKEY_CURRENT_USER\Software\Classes\CLSID\{F7959D5B-0818-43CC-9919-6AFA791730FC}\InprocServer32'
$dll = if (Test-Path -LiteralPath $registration) {
  (Get-Item -LiteralPath $registration).GetValue('')
} else {
  $null
}
if ($dll -and (Test-Path -LiteralPath $dll -PathType Leaf)) {
  & "$env:SystemRoot\System32\regsvr32.exe" /s /u $dll
  if ($LASTEXITCODE -ne 0) { throw "regsvr32 /u failed with exit code $LASTEXITCODE" }
}
Write-Output 'Keynako IME was unregistered. The installed files can now be removed.'
