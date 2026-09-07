[CmdletBinding()]
param(
  [string]$AndroidBuildRoot,
  [switch]$SkipBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'waddle-common.ps1')
. (Join-Path $PSScriptRoot 'waddle-managed-node.ps1')
. (Join-Path $PSScriptRoot 'waddle-local-runtime.ps1')
. (Join-Path $PSScriptRoot 'waddle-workspace-resilience.ps1')
. (Join-Path $PSScriptRoot 'waddle-git.ps1')

$ctx = @{}
if ($AndroidBuildRoot) { $ctx.androidbuild_root = $AndroidBuildRoot }
$repo = Resolve-WaddleRepoRoot -Context $ctx
$root = Resolve-WaddleAndroidBuildRoot -Context $ctx
Import-WaddleCore -AndroidBuildRoot $root
$managedNode = Enable-WaddleManagedNodeToolchain -AndroidBuildRoot $root
$workspace = Initialize-WaddleWorkspace -RepoRoot $repo -AndroidBuildRoot $root
$toolchain = Test-WaddleToolchain -AndroidBuildRoot $root
$envPath = Update-WaddleLocalEnv -RepoRoot $repo -AndroidBuildRoot $root -WorkRoot $workspace.work_root -FFDecPath $toolchain.ffdec
Set-WaddleEnvValue -Path $envPath -Name 'WADDLE_NODE_HOME' -Value $managedNode.home
Set-WaddleEnvValue -Path $envPath -Name 'WADDLE_NODE_EXE' -Value $managedNode.node
Set-WaddleEnvValue -Path $envPath -Name 'WADDLE_NPM_CMD' -Value $managedNode.npm
Set-WaddleEnvValue -Path $envPath -Name 'WADDLE_YARN_CMD' -Value $managedNode.yarn
Import-WaddleLocalEnv -Path $envPath
$dependencies = Invoke-WaddleDependencyBootstrap -RepoRoot $repo -WorkRoot $workspace.work_root
Test-WaddlePepperFlash -RepoRoot $repo | Out-Null

# The launcher lives in the repository root. Heavy/generated state remains under
# .work by design and is surfaced back at the root through junctions. This keeps
# exact-source syncs clean while the root launcher still sees node_modules,
# compiled and dist as normal project paths.
Write-Host "WADDLE_LAYOUT=PASS launcher_root=$repo mutable_root=$($workspace.work_root) node_modules=repo_junction swf_analysis=.work\swf-analysis"

$gitState = $null
try {
  $gitState = Get-WaddleRepositoryHead -RepoRoot $repo -AndroidBuildRoot $root
  $sha = [string]$gitState.sha
  if ([string]::IsNullOrWhiteSpace($sha)) { throw 'WADDLE_START=FAIL head_unresolved' }

  if (-not $SkipBuild) {
    Invoke-AndroidBuildBuild `
      -RepoRoot $repo `
      -AndroidBuildRoot $root `
      -ExpectedSha $sha `
      -Repository 'Valverde-101/TEST-Waddle-Forever' `
      -RunId ("manual-" + (Get-Date -Format 'yyyyMMddHHmmss')) `
      -JobId 'interactive-start' `
      -RunnerName $env:COMPUTERNAME `
      -LeaseWaitSeconds 1200 | Out-Host
  }
} finally {
  # Ownership trust is process-scoped only. Never leave a global safe.directory
  # exception behind on the user's Git installation.
  Restore-WaddleGitSafeDirectoryScope -State $gitState
}

$entry = Join-Path $repo 'compiled\client\main.js'
$electron = Join-Path $workspace.work_root 'dependencies\node_modules\electron\dist\electron.exe'
if (-not (Test-Path -LiteralPath $entry -PathType Leaf)) { throw "WADDLE_START=FAIL compiled_entry_missing=$entry" }
if (-not (Test-Path -LiteralPath $electron -PathType Leaf)) { throw "WADDLE_START=FAIL electron_executable_missing=$electron run=Waddle-Setup.cmd" }

# Validate the exact executable that will be launched. The old implementation
# executed node_modules\.bin\electron.cmd through `cmd.exe /s /c`, which is
# fragile on mapped/network repositories because cmd.exe rewrites the quoted
# command line before Electron receives it. Launch the packaged electron.exe
# directly so there is no intermediary shell, no .cmd shim and no V:/UNC
# quoting ambiguity.
$electronVersionOutput = @(& $electron --version 2>&1)
$electronProbeExit = $LASTEXITCODE
$electronVersion = (($electronVersionOutput | ForEach-Object { [string]$_ }) -join '').Trim().TrimStart('v')
if ($electronProbeExit -ne 0) {
  throw "WADDLE_START=FAIL electron_probe_exit=$electronProbeExit executable=$electron output=$($electronVersionOutput -join ' | ')"
}
if ([string]::IsNullOrWhiteSpace($electronVersion)) {
  throw "WADDLE_START=FAIL electron_probe_empty executable=$electron"
}
if ($electronVersion -ne [string]$dependencies.electron) {
  throw "WADDLE_START=FAIL electron_version_mismatch manifest=$($dependencies.electron) executable=$electronVersion path=$electron"
}
Set-WaddleEnvValue -Path $envPath -Name 'WADDLE_ELECTRON_EXE' -Value ([IO.Path]::GetFullPath($electron))
[Environment]::SetEnvironmentVariable('WADDLE_ELECTRON_EXE',[IO.Path]::GetFullPath($electron),'Process')
Write-Host "WADDLE_ELECTRON_RUNTIME=PASS version=$electronVersion executable=$electron launch_mode=direct_exe"

$flash = Test-WaddlePepperFlash -RepoRoot $repo
$runtimeLogs = Join-Path $workspace.work_root 'logs\runtime'
New-Item -ItemType Directory -Force -Path $runtimeLogs | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$stdout = Join-Path $runtimeLogs "client-$stamp.stdout.log"
$stderr = Join-Path $runtimeLogs "client-$stamp.stderr.log"
$statePath = Join-Path $workspace.work_root 'state\waddle-client.json'

$env:NODE_ENV = 'dev'
# A Windows path cannot contain a double quote, so quoting the one application
# argument is sufficient for ProcessStartInfo/Start-Process argument parsing.
$entryArgument = '"' + $entry + '"'
$process = Start-Process -FilePath $electron -ArgumentList $entryArgument -WorkingDirectory $repo -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
Start-Sleep -Seconds 3
$process.Refresh()
if ($process.HasExited) {
  $tail = if (Test-Path -LiteralPath $stderr) { (Get-Content -LiteralPath $stderr -Tail 30 -ErrorAction SilentlyContinue) -join ' | ' } else { '' }
  throw "WADDLE_START=FAIL process_exited code=$($process.ExitCode) stderr=$tail"
}

$state = [ordered]@{
  schema = 'waddle-client-state/v4'
  status = 'RUNNING'
  pid = $process.Id
  source_sha = $sha
  repo_root = $repo
  work_root = $workspace.work_root
  managed_node_home = $managedNode.home
  managed_node_exe = $managedNode.node
  electron_executable = $electron
  electron_version = $electronVersion
  electron_launch_mode = 'direct_exe'
  dependency_mode = $dependencies.mode
  ppapi_flash_path = $flash.path
  ppapi_flash_version = $flash.version
  ffdec_path = $toolchain.ffdec
  stdout = $stdout
  stderr = $stderr
  started_utc = [DateTime]::UtcNow.ToString('o')
}
$state | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statePath -Encoding UTF8

Write-Host "WADDLE_START=PASS pid=$($process.Id) sha=$sha node=$($managedNode.node) electron=$electronVersion launch_mode=direct_exe dependencies=$($dependencies.mode)"
Write-Host "WADDLE_PPAPI_FLASH=PASS path=$($flash.path) version=$($flash.version)"
Write-Host 'WADDLE_VISUAL_STUDIO=NOT_REQUIRED'
Write-Host "WADDLE_RUNTIME_STDOUT=$stdout"
Write-Host "WADDLE_RUNTIME_STDERR=$stderr"
