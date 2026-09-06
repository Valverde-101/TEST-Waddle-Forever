[CmdletBinding()]
param(
  [string]$AndroidBuildRoot,
  [switch]$SkipBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'waddle-common.ps1')

$ctx = @{}
if ($AndroidBuildRoot) { $ctx.androidbuild_root = $AndroidBuildRoot }
$repo = Resolve-WaddleRepoRoot -Context $ctx
$root = Resolve-WaddleAndroidBuildRoot -Context $ctx
Import-WaddleCore -AndroidBuildRoot $root
$workspace = Initialize-WaddleWorkspace -RepoRoot $repo -AndroidBuildRoot $root
Test-WaddleToolchain -AndroidBuildRoot $root | Out-Null

$git = Get-AndroidBuildGitPath $root
$sha = (& $git -C $repo rev-parse HEAD).Trim()
if (-not $sha) { throw 'WADDLE_START=FAIL head_unresolved' }

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

$entry = Join-Path $repo 'compiled\client\main.js'
$electron = Join-Path $repo 'node_modules\.bin\electron.cmd'
if (-not (Test-Path -LiteralPath $entry -PathType Leaf)) { throw "WADDLE_START=FAIL compiled_entry_missing=$entry" }
if (-not (Test-Path -LiteralPath $electron -PathType Leaf)) { throw "WADDLE_START=FAIL electron_missing=$electron" }

$runtimeLogs = Join-Path $workspace.work_root 'logs\runtime'
New-Item -ItemType Directory -Force -Path $runtimeLogs | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$stdout = Join-Path $runtimeLogs "client-$stamp.stdout.log"
$stderr = Join-Path $runtimeLogs "client-$stamp.stderr.log"
$statePath = Join-Path $workspace.work_root 'state\waddle-client.json'

$env:NODE_ENV = 'dev'
$command = "`"$electron`" `"$entry`""
$process = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/d','/s','/c',$command) -WorkingDirectory $repo -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru

$state = [ordered]@{
  schema = 'waddle-client-state/v1'
  status = 'RUNNING'
  pid = $process.Id
  source_sha = $sha
  repo_root = $repo
  work_root = $workspace.work_root
  stdout = $stdout
  stderr = $stderr
  started_utc = [DateTime]::UtcNow.ToString('o')
}
$state | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statePath -Encoding UTF8

Write-Host "WADDLE_START=PASS pid=$($process.Id) sha=$sha"
Write-Host "WADDLE_RUNTIME_STDOUT=$stdout"
Write-Host "WADDLE_RUNTIME_STDERR=$stderr"
