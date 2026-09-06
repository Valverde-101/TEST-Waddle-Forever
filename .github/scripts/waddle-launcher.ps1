[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)]
  [ValidateSet('setup','start','stop')]
  [string]$Action,
  [switch]$NonInteractive,
  [switch]$SelfTestFailure
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:WADDLE_LAUNCHER_SELFTEST_FAIL -eq '1') {
  $SelfTestFailure = $true
}

$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$logDir = Join-Path $repo '.work\logs\launcher'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$runLog = Join-Path $logDir ("{0}-{1}.log" -f $Action,$stamp)
$lastLog = Join-Path $logDir ("{0}-last.log" -f $Action)
$target = switch ($Action) {
  'setup' { Join-Path $PSScriptRoot 'waddle-bootstrap.ps1' }
  'start' { Join-Path $PSScriptRoot 'waddle-start.ps1' }
  'stop'  { Join-Path $PSScriptRoot 'waddle-stop.ps1' }
}

if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
  $message = "WADDLE_LAUNCHER=FAIL action=$Action reason=target_missing path=$target"
  $message | Set-Content -LiteralPath $runLog -Encoding UTF8
  Copy-Item -LiteralPath $runLog -Destination $lastLog -Force
  Write-Host $message -ForegroundColor Red
  Write-Host "WADDLE_ERROR_LOG=$lastLog"
  exit 1
}

$exitCode = 0
try {
  & {
    Write-Output "WADDLE_LAUNCHER=START action=$Action repo=$repo"
    Write-Output "WADDLE_LAUNCHER_LOG=$runLog"
    if ($SelfTestFailure) {
      throw "WADDLE_LAUNCHER_SELFTEST_FAIL action=$Action"
    }
    & $target
  } *>&1 | Tee-Object -FilePath $runLog
} catch {
  $exitCode = 1
  $errorText = @(
    "WADDLE_LAUNCHER=FAIL action=$Action"
    "ERROR_MESSAGE=$($_.Exception.Message)"
    "ERROR_TYPE=$($_.Exception.GetType().FullName)"
    "SCRIPT_STACK=$($_.ScriptStackTrace)"
    "ERROR_RECORD=$($_ | Out-String)"
  ) -join [Environment]::NewLine

  Add-Content -LiteralPath $runLog -Value $errorText -Encoding UTF8
  Write-Host ''
  Write-Host "WADDLE_LAUNCHER=FAIL action=$Action" -ForegroundColor Red
  Write-Host "ERROR_MESSAGE=$($_.Exception.Message)" -ForegroundColor Red
  if ($_.ScriptStackTrace) { Write-Host "SCRIPT_STACK=$($_.ScriptStackTrace)" }
}

try {
  Copy-Item -LiteralPath $runLog -Destination $lastLog -Force
} catch {
  Write-Host "WADDLE_LAUNCHER_LOG_COPY_WARN action=$Action error=$($_.Exception.Message)" -ForegroundColor Yellow
}

if ($exitCode -ne 0) {
  Write-Host ''
  Write-Host '============================================================' -ForegroundColor Red
  Write-Host "WADDLE $($Action.ToUpperInvariant()) FAILED" -ForegroundColor Red
  Write-Host "Persistent error log: $lastLog" -ForegroundColor Yellow
  Write-Host 'The window will remain open when launched from the .cmd file.' -ForegroundColor Yellow
  Write-Host '============================================================' -ForegroundColor Red
  exit $exitCode
}

Write-Host "WADDLE_LAUNCHER=PASS action=$Action log=$runLog"
exit 0
