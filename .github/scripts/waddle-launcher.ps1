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

function Write-WaddleLauncherLine {
  param(
    [Parameter(Mandatory)][string]$Text,
    [ConsoleColor]$Color = [ConsoleColor]::Gray
  )
  Add-Content -LiteralPath $runLog -Value $Text -Encoding UTF8
  Write-Host $Text -ForegroundColor $Color
}

if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
  $message = "WADDLE_LAUNCHER=FAIL action=$Action reason=target_missing path=$target"
  Set-Content -LiteralPath $runLog -Value $message -Encoding UTF8
  Copy-Item -LiteralPath $runLog -Destination $lastLog -Force
  Write-Host $message -ForegroundColor Red
  Write-Host "WADDLE_ERROR_LOG=$lastLog"
  exit 1
}

Set-Content -LiteralPath $runLog -Value @(
  "WADDLE_LAUNCHER=START action=$Action repo=$repo",
  "WADDLE_LAUNCHER_LOG=$runLog",
  "WADDLE_TARGET=$target"
) -Encoding UTF8
Write-Host "WADDLE_LAUNCHER=START action=$Action repo=$repo"
Write-Host "WADDLE_LAUNCHER_LOG=$runLog"

$exitCode = 0
$failureMessage = $null

if ($SelfTestFailure) {
  $exitCode = 1
  $failureMessage = "WADDLE_LAUNCHER_SELFTEST_FAIL action=$Action"
  Write-WaddleLauncherLine -Text $failureMessage -Color Red
} else {
  try {
    # Run the actual action in a child PowerShell. cmd.exe merges stderr into stdout
    # before it reaches this wrapper, so benign native warnings (for example Yarn
    # package metadata warnings) are logged and displayed but cannot be promoted into
    # terminating PowerShell ErrorRecords. The child exit code remains authoritative.
    $command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$target`" 2>&1"
    & cmd.exe /d /s /c $command | ForEach-Object {
      $line = [string]$_
      Add-Content -LiteralPath $runLog -Value $line -Encoding UTF8
      Write-Host $line
    }
    $targetExit = $LASTEXITCODE
    if ($targetExit -ne 0) {
      $exitCode = [int]$targetExit
      $failureMessage = "WADDLE_TARGET_EXIT=FAIL action=$Action exit=$targetExit"
      Write-WaddleLauncherLine -Text $failureMessage -Color Red
    } else {
      Write-WaddleLauncherLine -Text "WADDLE_TARGET_EXIT=PASS action=$Action exit=0" -Color Green
    }
  } catch {
    $exitCode = 1
    $failureMessage = "WADDLE_LAUNCHER_INTERNAL_FAIL action=$Action message=$($_.Exception.Message)"
    Write-WaddleLauncherLine -Text $failureMessage -Color Red
    if ($_.ScriptStackTrace) {
      Write-WaddleLauncherLine -Text "SCRIPT_STACK=$($_.ScriptStackTrace)" -Color DarkYellow
    }
  }
}

# Write the terminal classification before producing the stable *-last.log copy so
# the file is self-contained for humans and future Inspector/CI consumers.
if ($exitCode -ne 0) {
  Write-WaddleLauncherLine -Text "WADDLE_LAUNCHER=FAIL action=$Action exit=$exitCode" -Color Red
} else {
  Write-WaddleLauncherLine -Text "WADDLE_LAUNCHER=PASS action=$Action exit=0" -Color Green
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
  if ($failureMessage) { Write-Host $failureMessage -ForegroundColor Red }
  Write-Host "Persistent error log: $lastLog" -ForegroundColor Yellow
  Write-Host 'The window will remain open when launched from the .cmd file.' -ForegroundColor Yellow
  Write-Host '============================================================' -ForegroundColor Red
  exit $exitCode
}

Write-Host "Persistent launcher log: $lastLog"
exit 0
