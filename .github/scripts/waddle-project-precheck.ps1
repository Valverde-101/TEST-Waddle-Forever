param(
  [Parameter(Mandatory=$false)][string]$ContextPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'waddle-common.ps1')
. (Join-Path $PSScriptRoot 'waddle-managed-node.ps1')

$ctx = Get-WaddleContext -ContextPath $ContextPath
$repo = Resolve-WaddleRepoRoot -Context $ctx
$androidBuildRoot = Resolve-WaddleAndroidBuildRoot -Context $ctx

Import-WaddleCore -AndroidBuildRoot $androidBuildRoot
$managedNode = Enable-WaddleManagedNodeToolchain -AndroidBuildRoot $androidBuildRoot
$workspace = Initialize-WaddleWorkspace -RepoRoot $repo -AndroidBuildRoot $androidBuildRoot
$toolchain = Test-WaddleToolchain -AndroidBuildRoot $androidBuildRoot

# Regression test for the real desktop failure: a machine may expose Node 24 first
# in PATH while Waddle requires Node 20.19.0. When a foreign system Node exists,
# deliberately put it first, then prove the resolver restores the managed toolchain.
$foreignCandidates = New-Object System.Collections.Generic.List[string]
foreach ($candidate in @(
  (Join-Path $env:ProgramFiles 'nodejs\node.exe'),
  (if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'nodejs\node.exe' } else { $null })
)) {
  if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf) -and -not $foreignCandidates.Contains($candidate)) {
    $foreignCandidates.Add($candidate)
  }
}
foreach ($candidate in @(& where.exe node.exe 2>$null)) {
  if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf) -and -not $foreignCandidates.Contains([string]$candidate)) {
    $foreignCandidates.Add([string]$candidate)
  }
}
$foreignNode = $null
$foreignVersion = $null
foreach ($candidate in $foreignCandidates) {
  try { $version = (& $candidate --version 2>$null).Trim().TrimStart('v') } catch { continue }
  if ($version -and $version -ne '20.19.0') {
    $foreignNode = $candidate
    $foreignVersion = $version
    break
  }
}
if ($foreignNode) {
  $savedPath = $env:PATH
  try {
    $foreignHome = Split-Path -Parent $foreignNode
    $withoutManaged = @([string]$savedPath -split ';' | Where-Object { $_ -and $_.TrimEnd('\') -ine $managedNode.home.TrimEnd('\') -and $_.TrimEnd('\') -ine $foreignHome.TrimEnd('\') })
    $env:PATH = @($foreignHome) + $withoutManaged -join ';'
    $beforeNode = (Get-Command node.exe -ErrorAction Stop).Source
    $beforeVersion = (& $beforeNode --version).Trim().TrimStart('v')
    if ($beforeVersion -eq '20.19.0') { throw "WADDLE_FOREIGN_NODE_ISOLATION=FAIL fixture_not_foreign path=$beforeNode" }
    $reselected = Enable-WaddleManagedNodeToolchain -AndroidBuildRoot $androidBuildRoot
    $afterNode = (Get-Command node.exe -ErrorAction Stop).Source
    $afterVersion = (& $afterNode --version).Trim().TrimStart('v')
    if ($afterVersion -ne '20.19.0') { throw "WADDLE_FOREIGN_NODE_ISOLATION=FAIL expected=20.19.0 actual=$afterVersion path=$afterNode" }
    if ([IO.Path]::GetFullPath($afterNode) -ne [IO.Path]::GetFullPath($reselected.node)) {
      throw "WADDLE_FOREIGN_NODE_ISOLATION=FAIL selected_not_managed selected=$afterNode expected=$($reselected.node)"
    }
    Write-Host "WADDLE_FOREIGN_NODE_ISOLATION=PASS foreign_version=$beforeVersion foreign_path=$beforeNode managed_version=$afterVersion managed_path=$afterNode"
  } finally {
    $env:PATH = $savedPath
    Enable-WaddleManagedNodeToolchain -AndroidBuildRoot $androidBuildRoot | Out-Null
  }
} else {
  Write-Host 'WADDLE_FOREIGN_NODE_ISOLATION=INFO foreign_node_not_present_on_runner'
}

$configPath = Join-Path $repo '.androidbuild.json'
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
if ([string]$config.project.kind -ne 'custom') { throw "PROJECT_KIND=FAIL expected=custom actual=$($config.project.kind)" }
if ([bool]$config.android.applicable) { throw 'ANDROID_SCOPE=FAIL expected_not_applicable' }
if ([string]$config.toolchain.node -ne '20.19.0') { throw "NODE_CONTRACT=FAIL expected=20.19.0 actual=$($config.toolchain.node)" }
if ([string]$config.toolchain.yarn -ne '1.22.22') { throw "YARN_CONTRACT=FAIL expected=1.22.22 actual=$($config.toolchain.yarn)" }

$git = Get-AndroidBuildGitPath $androidBuildRoot
$ignoreProbe = '.work/.androidbuild-work-root'
& $git -C $repo check-ignore -q -- $ignoreProbe
$ignoreExit = $LASTEXITCODE
if ($ignoreExit -ne 0) {
  throw "WORK_GITIGNORE=FAIL probe=$ignoreProbe exit=$ignoreExit"
}
$trackedWork = @(& $git -C $repo ls-files -- '.work')
if ($LASTEXITCODE -ne 0) { throw "WORK_TRACKING_CHECK=FAIL exit=$LASTEXITCODE" }
if ($trackedWork.Count -gt 0) {
  throw "WORK_TRACKING_CHECK=FAIL tracked=$($trackedWork -join ',')"
}
Write-Host "WORK_GITIGNORE=PASS probe=$ignoreProbe semantic=true"
Write-Host 'WORK_TRACKING_CHECK=PASS tracked=0'

if ($ctx.ContainsKey('expected_sha') -and $ctx.expected_sha) {
  Test-AndroidBuildExactHead -RepoRoot $repo -ExpectedSha ([string]$ctx.expected_sha) -AndroidBuildRoot $androidBuildRoot | Out-Null
  Write-Host "EXACT_HEAD=PASS sha=$($ctx.expected_sha)"
}

Write-Host "WADDLE_REPO_ROOT=PASS path=$repo"
Write-Host "WADDLE_WORK_ROOT=PASS path=$($workspace.work_root)"
Write-Host "WADDLE_MANAGED_NODE_HOME=PASS path=$($managedNode.home)"
Write-Host 'ANDROID=NOT_APPLICABLE'
Write-Host 'APK_FINAL=NOT_APPLICABLE'
Write-Host 'APK_APPROVE_ADB=NOT_APPLICABLE'
Write-Host 'PHYSICAL_ADB=NOT_APPLICABLE'
Write-Host 'WADDLE_PROJECT_PRECHECK=PASS'
