$ErrorActionPreference = 'Stop'
$installRoot = Join-Path $env:LOCALAPPDATA 'Keynako\IME'
$dll = Join-Path $installRoot 'KeynakoIME.dll'
if (Test-Path -LiteralPath $dll -PathType Leaf) {
  & "$env:SystemRoot\System32\regsvr32.exe" /s /u $dll
  if ($LASTEXITCODE -ne 0) { throw "regsvr32 /u failed with exit code $LASTEXITCODE" }
}
Write-Output 'Keynako IME was unregistered. The installed files can now be removed.'
