Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$core = Join-Path $PSScriptRoot 'waddle-workspace-resilience-core.ps1'
if (-not (Test-Path -LiteralPath $core -PathType Leaf)) {
  throw "WADDLE_WORKSPACE_CORE=FAIL missing=$core"
}
. $core

# Runtime launch can be invoked from a fresh GitHub Actions PowerShell step,
# where PATH changes made by Waddle-Setup.cmd do not survive. Resolve the pinned
# Windows toolchain from AndroidBuild itself so launch never depends on ambient
# or globally installed Node/Yarn.
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

# Final runtime policy: execute Electron, compiled Waddle and Pepper Flash
# directly from the repository. Nothing is copied to AndroidBuild\Runtime.
$repoRuntime = Join-Path $PSScriptRoot 'waddle-repo-runtime.ps1'
if (-not (Test-Path -LiteralPath $repoRuntime -PathType Leaf)) {
  throw "WADDLE_RUNTIME_OVERRIDE=FAIL missing=$repoRuntime"
}
. $repoRuntime
Write-Host "WADDLE_RUNTIME_OVERRIDE=PASS mode=repo_local_direct script=$repoRuntime"

# Final dependency policy: keep exactly one persistent node_modules tree at the
# repository root. This is sourced last intentionally so it replaces the
# historical .work dependency implementation while preserving the rest of the
# resilience logic.
$repoDependencies = Join-Path $PSScriptRoot 'waddle-repo-dependencies.ps1'
if (-not (Test-Path -LiteralPath $repoDependencies -PathType Leaf)) {
  throw "WADDLE_REPO_DEPENDENCIES=FAIL missing=$repoDependencies"
}
. $repoDependencies
Write-Host "WADDLE_REPO_DEPENDENCIES=PASS layout=repo_physical script=$repoDependencies"

# Cross-machine lease policy is loaded after dependency helpers because it can
# determine whether a dependency mutation is actually required. This protects
# the shared repo on SMB without preventing multiple read-only clients.
$runtimeLeases = Join-Path $PSScriptRoot 'waddle-runtime-leases.ps1'
if (-not (Test-Path -LiteralPath $runtimeLeases -PathType Leaf)) {
  throw "WADDLE_RUNTIME_LEASES=FAIL missing=$runtimeLeases"
}
. $runtimeLeases
Write-Host "WADDLE_RUNTIME_LEASES=PASS mode=cross_machine_multi_client script=$runtimeLeases"
