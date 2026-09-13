[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)]
  [ValidateSet('setup','start','stop')]
  [string]$Action,
  [switch]$NonInteractive,
  [switch]$SelfTestFailure,
  [switch]$SkipBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# A real desktop session must never enter the synthetic failure path because of a
# leaked environment variable. Environment-driven selftest remains available only
# to noninteractive CI; humans can also invoke -SelfTestFailure explicitly.
if ($env:WADDLE_NONINTERACTIVE -eq '1' -and $env:WADDLE_LAUNCHER_SELFTEST_FAIL -eq '1') {
  $SelfTestFailure = $true
}

if ($SkipBuild -and $Action -ne 'start') {
  throw "WADDLE_LAUNCHER=FAIL skip_build_only_valid_for_start action=$Action"
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

$operationLock = $null
function Close-WaddleLauncherOperationLock {
  if ($null -ne $script:operationLock) {
    try { $script:operationLock.Dispose() } catch {}
    $script:operationLock = $null
  }
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
  "WADDLE_TARGET=$target",
  "WADDLE_SKIP_BUILD=$([bool]$SkipBuild)"
) -Encoding UTF8
Write-Host "WADDLE_LAUNCHER=START action=$Action repo=$repo"
Write-Host "WADDLE_LAUNCHER_LOG=$runLog"
Write-Host "WADDLE_SKIP_BUILD=$([bool]$SkipBuild)"

# Setup and Start both mutate the same compiled/dependency/runtime state. A second
# launch must never race the first one: the old behavior produced short partial
# logs that looked like unexplained crashes when users retried while an operation
# was still running. FileShare.None gives us a process-scoped lock that Windows
# releases automatically even if the owning console is terminated.
if ($Action -ne 'stop') {
  $stateDir = Join-Path $repo '.work\state'
  New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
  $operationLockPath = Join-Path $stateDir 'launcher-operation.lock'
  try {
    $operationLock = [IO.File]::Open(
      $operationLockPath,
      [IO.FileMode]::OpenOrCreate,
      [IO.FileAccess]::ReadWrite,
      [IO.FileShare]::None
    )
    $operationLock.SetLength(0)
    $lockText = "pid=$PID action=$Action started_utc=$([DateTime]::UtcNow.ToString('o'))"
    $lockBytes = [Text.Encoding]::UTF8.GetBytes($lockText)
    $operationLock.Write($lockBytes,0,$lockBytes.Length)
    $operationLock.Flush()
    Write-WaddleLauncherLine -Text "WADDLE_OPERATION_LOCK=PASS action=$Action pid=$PID path=$operationLockPath" -Color DarkGreen
  } catch {
    $message = "WADDLE_LAUNCHER=BUSY action=$Action reason=setup_or_start_already_running lock=$operationLockPath"
    Write-WaddleLauncherLine -Text $message -Color Yellow
    try { Copy-Item -LiteralPath $runLog -Destination $lastLog -Force } catch {}
    Write-Host 'Close the other Waddle Setup/Start window or let it finish before retrying.' -ForegroundColor Yellow
    exit 2
  }
}

$exitCode = 0
$failureMessage = $null

if ($SelfTestFailure) {
  $exitCode = 1
  $failureMessage = "WADDLE_LAUNCHER_SELFTEST_FAIL action=$Action"
  Write-WaddleLauncherLine -Text $failureMessage -Color Red
} else {
  try {
    $targetArguments = ''
    if ($Action -eq 'start' -and $SkipBuild) { $targetArguments = ' -SkipBuild' }
    $command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$target`"$targetArguments 2>&1"
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

Close-WaddleLauncherOperationLock

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
