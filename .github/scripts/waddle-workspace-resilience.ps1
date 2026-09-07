Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$core = Join-Path $PSScriptRoot 'waddle-workspace-resilience-core.ps1'
if (-not (Test-Path -LiteralPath $core -PathType Leaf)) {
  throw "WADDLE_WORKSPACE_CORE=FAIL missing=$core"
}
. $core

# Runtime deployment can be invoked from a fresh GitHub Actions PowerShell step,
# where PATH changes made by Waddle-Setup.cmd do not survive. Resolve the pinned
# Windows toolchain from AndroidBuild itself so runtime publication never depends
# on ambient/global Node or Yarn.
if ($env:ANDROIDBUILD_ROOT) {
  $managedNodeHome = [IO.Path]::GetFullPath((Join-Path $env:ANDROIDBUILD_ROOT 'Tools\Node\20.19.0\x64'))
  $managedNode = Join-Path $managedNodeHome 'node.exe'
  $managedYarn = Join-Path $managedNodeHome 'yarn.cmd'
  if ((Test-Path -LiteralPath $managedNode -PathType Leaf) -and (Test-Path -LiteralPath $managedYarn -PathType Leaf)) {
    $parts = @([string]$env:PATH -split ';' | Where-Object { $_ })
    if (-not ($parts | Where-Object { $_.TrimEnd('\') -ieq $managedNodeHome.TrimEnd('\') })) {
      $env:PATH = "$managedNodeHome;$env:PATH"
    }
    $env:WADDLE_NODE_EXE = $managedNode
    $env:WADDLE_YARN_CMD = $managedYarn
    Write-Host "WADDLE_RUNTIME_TOOLCHAIN=PASS node=$managedNode yarn=$managedYarn source=androidbuild_managed"
  } else {
    throw "WADDLE_RUNTIME_TOOLCHAIN=FAIL node=$managedNode yarn=$managedYarn"
  }
}

$externalRuntime = Join-Path $PSScriptRoot 'waddle-external-runtime.ps1'
if (-not (Test-Path -LiteralPath $externalRuntime -PathType Leaf)) {
  throw "WADDLE_RUNTIME_OVERRIDE=FAIL missing=$externalRuntime"
}
. $externalRuntime
Write-Host "WADDLE_RUNTIME_OVERRIDE=PASS mode=external_deployment script=$externalRuntime"
