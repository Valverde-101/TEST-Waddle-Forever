param(
  [Parameter(Mandatory=$false)][string]$ContextPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'waddle-common.ps1')

$ctx = Get-WaddleContext -ContextPath $ContextPath
$repo = Resolve-WaddleRepoRoot -Context $ctx
$androidBuildRoot = Resolve-WaddleAndroidBuildRoot -Context $ctx
Import-WaddleCore -AndroidBuildRoot $androidBuildRoot
$workspace = Initialize-WaddleWorkspace -RepoRoot $repo -AndroidBuildRoot $androidBuildRoot
Test-WaddleToolchain -AndroidBuildRoot $androidBuildRoot | Out-Null

if ($ctx.ContainsKey('expected_sha') -and $ctx.expected_sha) {
  Test-AndroidBuildExactHead -RepoRoot $repo -ExpectedSha ([string]$ctx.expected_sha) -AndroidBuildRoot $androidBuildRoot | Out-Null
}

$logDir = Join-Path $workspace.work_root 'logs\build'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$transcript = Join-Path $logDir "build-$stamp.log"
$summaryPath = Join-Path $workspace.work_root 'state\waddle-build-summary.json'

function Invoke-WaddleCommand {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string[]]$Arguments
  )
  Write-Host "WADDLE_STEP=START name=$Name"
  $sw = [Diagnostics.Stopwatch]::StartNew()
  & yarn.cmd @Arguments
  $code = $LASTEXITCODE
  $sw.Stop()
  if ($code -ne 0) { throw "WADDLE_STEP=FAIL name=$Name exit=$code duration_ms=$($sw.ElapsedMilliseconds)" }
  Write-Host "WADDLE_STEP=PASS name=$Name duration_ms=$($sw.ElapsedMilliseconds)"
}

function Reset-WaddleCompiledOutput {
  $link = Join-Path $repo 'compiled'
  $target = Join-Path $workspace.work_root 'build\compiled'

  if (Test-Path -LiteralPath $link) {
    $item = Get-Item -LiteralPath $link -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
      & cmd.exe /d /c "rmdir `"$link`"" | Out-Null
      if ($LASTEXITCODE -ne 0) { throw "COMPILED_RESET=FAIL remove_junction exit=$LASTEXITCODE" }
    } else {
      Remove-Item -LiteralPath $link -Recurse -Force
    }
  }
  if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $target | Out-Null
  Ensure-WaddleJunction -LinkPath $link -TargetPath $target
  Write-Host "COMPILED_RESET=PASS target=$target"
}

Start-Transcript -LiteralPath $transcript -Force | Out-Null
try {
  Push-Location $repo
  try {
    Invoke-WaddleCommand -Name 'yarn-install' -Arguments @('install','--frozen-lockfile','--non-interactive','--cache-folder',$env:YARN_CACHE_FOLDER)
    Invoke-WaddleCommand -Name 'build-packages' -Arguments @('build-packages')

    # Upstream `yarn build-tsc` begins with scripts/remove-compiled.mjs, which removes
    # the compatibility junction itself. Reproduce the same build sequence while
    # cleaning the real .work target and recreating the junction before tsc writes.
    Reset-WaddleCompiledOutput
    Invoke-WaddleCommand -Name 'tsc' -Arguments @('exec','tsc')
    Invoke-WaddleCommand -Name 'tsc-alias' -Arguments @('exec','tsc-alias')
    Invoke-WaddleCommand -Name 'build-browser' -Arguments @('build-browser')
    Invoke-WaddleCommand -Name 'copy-files' -Arguments @('copy-files')
    Invoke-WaddleCommand -Name 'lint' -Arguments @('lint')
  } finally {
    Pop-Location
  }

  $summary = [ordered]@{
    schema = 'waddle-build-summary/v1'
    status = 'PASS'
    source_sha = if ($ctx.ContainsKey('expected_sha')) { [string]$ctx.expected_sha } else { '' }
    repo_root = $repo
    work_root = $workspace.work_root
    node_modules = (Join-Path $workspace.work_root 'dependencies\node_modules')
    compiled = (Join-Path $workspace.work_root 'build\compiled')
    dist = (Join-Path $workspace.work_root 'dist\package')
    yarn_cache = $env:YARN_CACHE_FOLDER
    transcript = $transcript
    completed_utc = [DateTime]::UtcNow.ToString('o')
    android = 'NOT_APPLICABLE'
    physical_adb = 'NOT_APPLICABLE'
  }
  $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
  Write-Host "WADDLE_BUILD_SUMMARY=$summaryPath"
  Write-Host 'WADDLE_BUILD=PASS'
} finally {
  try { Stop-Transcript | Out-Null } catch {}
}
