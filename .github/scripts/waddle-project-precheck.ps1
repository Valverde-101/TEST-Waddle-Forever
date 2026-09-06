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
$toolchain = Test-WaddleToolchain -AndroidBuildRoot $androidBuildRoot

$configPath = Join-Path $repo '.androidbuild.json'
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
if ([string]$config.project.kind -ne 'custom') { throw "PROJECT_KIND=FAIL expected=custom actual=$($config.project.kind)" }
if ([bool]$config.android.applicable) { throw 'ANDROID_SCOPE=FAIL expected_not_applicable' }

$gitignore = Get-Content -LiteralPath (Join-Path $repo '.gitignore') -Raw
if ($gitignore -notmatch '(?m)^/\.work/$') { throw 'WORK_GITIGNORE=FAIL missing=/.work/' }

if ($ctx.ContainsKey('expected_sha') -and $ctx.expected_sha) {
  Test-AndroidBuildExactHead -RepoRoot $repo -ExpectedSha ([string]$ctx.expected_sha) -AndroidBuildRoot $androidBuildRoot | Out-Null
  Write-Host "EXACT_HEAD=PASS sha=$($ctx.expected_sha)"
}

Write-Host "WADDLE_REPO_ROOT=PASS path=$repo"
Write-Host "WADDLE_WORK_ROOT=PASS path=$($workspace.work_root)"
Write-Host 'ANDROID=NOT_APPLICABLE'
Write-Host 'APK_FINAL=NOT_APPLICABLE'
Write-Host 'APK_APPROVE_ADB=NOT_APPLICABLE'
Write-Host 'PHYSICAL_ADB=NOT_APPLICABLE'
Write-Host 'WADDLE_PROJECT_PRECHECK=PASS'
