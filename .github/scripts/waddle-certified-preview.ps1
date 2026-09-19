[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$AndroidBuildRoot,
  [Parameter(Mandatory)][string]$SourceRepoRoot,
  [Parameter(Mandatory)][string]$Repository,
  [Parameter(Mandatory)][string]$TargetBranch,
  [Parameter(Mandatory)][string]$ExpectedSha,
  [string]$CertificationRunId = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-GitText {
  param(
    [Parameter(Mandatory)][string]$Repo,
    [Parameter(Mandatory)][string[]]$Arguments,
    [switch]$AllowFailure
  )
  $lines = @(& $script:Git -c "safe.directory=$Repo" -C $Repo @Arguments 2>$null)
  $code = $LASTEXITCODE
  $global:LASTEXITCODE = 0
  if ($code -ne 0 -and -not $AllowFailure) {
    throw "WADDLE_CERTIFIED_PREVIEW=FAIL git exit=$code repo=$Repo args=$($Arguments -join ' ')"
  }
  [pscustomobject]@{ code=$code; text=($lines -join "`n").Trim(); lines=$lines }
}

function Get-CanonicalSnapshot {
  param([Parameter(Mandatory)][string]$Repo)
  $branchResult = Get-GitText -Repo $Repo -Arguments @('symbolic-ref','--quiet','--short','HEAD') -AllowFailure
  $branch = if ($branchResult.code -eq 0) { $branchResult.text } else { '' }
  $head = (Get-GitText -Repo $Repo -Arguments @('rev-parse','HEAD')).text.ToLowerInvariant()
  $tracked = (Get-GitText -Repo $Repo -Arguments @('status','--porcelain=v1','--untracked-files=no')).text
  [pscustomobject]@{ branch=$branch; head=$head; tracked=$tracked }
}

function Assert-CanonicalUnchanged {
  param(
    [Parameter(Mandatory)][string]$Repo,
    [Parameter(Mandatory)]$Before
  )
  $after = Get-CanonicalSnapshot -Repo $Repo
  if ($after.branch -ne $Before.branch -or $after.head -ne $Before.head -or $after.tracked -ne $Before.tracked) {
    throw "WADDLE_CERTIFIED_PREVIEW=FAIL canonical_mutated before_branch=$($Before.branch) after_branch=$($after.branch) before_head=$($Before.head) after_head=$($after.head)"
  }
  Write-Host "WADDLE_CERTIFIED_PREVIEW_CANONICAL=PASS branch=$($after.branch) head=$($after.head) tracked_state_preserved=true"
}

function Resolve-PathAgainst {
  param(
    [Parameter(Mandatory)][string]$Base,
    [Parameter(Mandatory)][string]$Path
  )
  if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
  return [IO.Path]::GetFullPath((Join-Path $Base $Path))
}

function Stop-OtherWaddleClients {
  param([Parameter(Mandatory)][string]$Root)

  $managedRoots = @(
    ([IO.Path]::GetFullPath((Join-Path $Root 'Repositories\TEST-Waddle-Forever')).TrimEnd('\') + '\'),
    ([IO.Path]::GetFullPath((Join-Path $Root 'Previews\Waddle-Forever')).TrimEnd('\') + '\'),
    ([IO.Path]::GetFullPath((Join-Path $Root 'Certification\Waddle-Forever')).TrimEnd('\') + '\')
  )
  $killed = New-Object System.Collections.Generic.List[int]

  foreach ($candidate in @(Get-CimInstance Win32_Process -Filter "Name='electron.exe'" -ErrorAction SilentlyContinue)) {
    $cmd = [string]$candidate.CommandLine
    if ([string]::IsNullOrWhiteSpace($cmd) -or $cmd -notmatch '[\\/]compiled[\\/]client[\\/]main\.js') { continue }

    $belongsToWaddle = $false
    foreach ($rootPrefix in $managedRoots) {
      if ($cmd.IndexOf($rootPrefix,[StringComparison]::OrdinalIgnoreCase) -ge 0) {
        $belongsToWaddle = $true
        break
      }
    }
    if (-not $belongsToWaddle) { continue }

    $processId = [int]$candidate.ProcessId
    & taskkill.exe /PID $processId /T /F | Out-Null
    $code = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($code -ne 0 -and (Get-Process -Id $processId -ErrorAction SilentlyContinue)) {
      throw "WADDLE_CERTIFIED_PREVIEW=FAIL exclusive_stop pid=$processId exit=$code"
    }
    $killed.Add($processId)
  }

  Write-Host "WADDLE_CERTIFIED_PREVIEW_EXCLUSIVE=PASS killed=$($killed.Count) pids=$($killed -join ',') scope=managed_waddle_only"
}

$module = Join-Path $AndroidBuildRoot 'Core\Current\AndroidBuild.psd1'
if (-not (Test-Path -LiteralPath $module -PathType Leaf)) {
  throw "WADDLE_CERTIFIED_PREVIEW=FAIL core_missing=$module"
}
Import-Module $module -DisableNameChecking -Force -WarningAction SilentlyContinue
Enable-AndroidBuildPortableTools -AndroidBuildRoot $AndroidBuildRoot | Out-Null
$script:Git = [string](Get-AndroidBuildGitPath -AndroidBuildRoot $AndroidBuildRoot)
if (-not (Test-Path -LiteralPath $script:Git -PathType Leaf)) {
  throw "WADDLE_CERTIFIED_PREVIEW=FAIL managed_git_missing=$script:Git"
}

$source = [IO.Path]::GetFullPath($SourceRepoRoot)
if (-not (Test-Path -LiteralPath (Join-Path $source '.git'))) {
  throw "WADDLE_CERTIFIED_PREVIEW=FAIL source_repo_missing=$source"
}
$expected = $ExpectedSha.Trim().ToLowerInvariant()
if ($expected -notmatch '^[0-9a-f]{40}$') {
  throw "WADDLE_CERTIFIED_PREVIEW=FAIL invalid_expected_sha=$ExpectedSha"
}
if ([string]::IsNullOrWhiteSpace($TargetBranch)) {
  throw 'WADDLE_CERTIFIED_PREVIEW=FAIL target_branch_missing'
}

$canonicalBefore = Get-CanonicalSnapshot -Repo $source
$safeTarget = [regex]::Replace($TargetBranch,'[^A-Za-z0-9._-]','_')
$safePreviewRelative = ([regex]::Replace($TargetBranch,'[^A-Za-z0-9._/-]','_')).Replace('/','\_')
$previewRoot = Join-Path $AndroidBuildRoot ("Previews\Waddle-Forever\$safePreviewRelative")
$stateRoot = Join-Path $AndroidBuildRoot 'Previews\State'
$quarantineBase = Join-Path $AndroidBuildRoot ("Previews\Quarantine\$safePreviewRelative")
foreach ($dir in @((Split-Path -Parent $previewRoot),$stateRoot,$quarantineBase)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

$previewRef = "refs/remotes/waddle-certified/$safeTarget"
$refspec = "+refs/heads/{0}:{1}" -f $TargetBranch,$previewRef
& $script:Git -c "safe.directory=$source" -C $source fetch --force --no-tags "https://github.com/$Repository.git" $refspec
if ($LASTEXITCODE -ne 0) { throw "WADDLE_CERTIFIED_PREVIEW=FAIL target_fetch branch=$TargetBranch" }
$global:LASTEXITCODE = 0
$branchHead = (Get-GitText -Repo $source -Arguments @('rev-parse',$previewRef)).text.ToLowerInvariant()
$expectedObject = Get-GitText -Repo $source -Arguments @('cat-file','-e',("$expected^{commit}")) -AllowFailure
if ($expectedObject.code -ne 0) {
  throw "WADDLE_CERTIFIED_PREVIEW=FAIL certified_sha_not_fetched expected=$expected branch_head=$branchHead"
}
$ancestor = Get-GitText -Repo $source -Arguments @('merge-base','--is-ancestor',$expected,$previewRef) -AllowFailure
if ($ancestor.code -ne 0) {
  throw "WADDLE_CERTIFIED_PREVIEW=FAIL certified_sha_not_on_target_branch expected=$expected branch_head=$branchHead"
}

$registered = $false
if (Test-Path -LiteralPath $previewRoot) {
  if (-not (Test-Path -LiteralPath (Join-Path $previewRoot '.git'))) {
    throw "WADDLE_CERTIFIED_PREVIEW=FAIL preview_path_not_git_worktree=$previewRoot"
  }
  $top = (Get-GitText -Repo $previewRoot -Arguments @('rev-parse','--show-toplevel')).text
  if ([IO.Path]::GetFullPath($top).TrimEnd('\') -ine [IO.Path]::GetFullPath($previewRoot).TrimEnd('\')) {
    throw "WADDLE_CERTIFIED_PREVIEW=FAIL preview_toplevel_mismatch expected=$previewRoot actual=$top"
  }
  $commonRaw = (Get-GitText -Repo $previewRoot -Arguments @('rev-parse','--git-common-dir')).text
  $common = Resolve-PathAgainst -Base $previewRoot -Path $commonRaw
  $sourceGit = [IO.Path]::GetFullPath((Join-Path $source '.git'))
  if ($common.TrimEnd('\') -ine $sourceGit.TrimEnd('\')) {
    throw "WADDLE_CERTIFIED_PREVIEW=FAIL preview_owner_mismatch expected_common=$sourceGit actual_common=$common"
  }
  $registered = $true
}

if (-not $registered) {
  & $script:Git -c "safe.directory=$source" -C $source worktree prune
  $global:LASTEXITCODE = 0
  & $script:Git -c "safe.directory=$source" -C $source worktree add --detach $previewRoot $expected
  if ($LASTEXITCODE -ne 0) { throw "WADDLE_CERTIFIED_PREVIEW=FAIL worktree_add path=$previewRoot" }
  $global:LASTEXITCODE = 0
  Write-Host "WADDLE_CERTIFIED_PREVIEW_WORKTREE=PASS mode=created path=$previewRoot"
} else {
  $timestamp = Get-Date -Format 'yyyyMMdd-HHmmssfff'
  $quarantine = Join-Path $quarantineBase $timestamp
  $dirtyPaths = @()
  $workingDiff = Get-GitText -Repo $previewRoot -Arguments @('diff','--name-only','--')
  $stagedDiff = Get-GitText -Repo $previewRoot -Arguments @('diff','--cached','--name-only','--')
  foreach ($result in @($workingDiff,$stagedDiff)) {
    if (-not [string]::IsNullOrWhiteSpace($result.text)) { $dirtyPaths += @($result.text -split "`r?`n") }
  }
  $dirtyPaths = @($dirtyPaths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
  foreach ($path in $dirtyPaths) {
    $sourcePath = Join-Path $previewRoot ($path -replace '/','\')
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { continue }
    $backupPath = Join-Path $quarantine ($path -replace '/','\')
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backupPath) | Out-Null
    Copy-Item -LiteralPath $sourcePath -Destination $backupPath -Force
  }

  $untrackedResult = Get-GitText -Repo $previewRoot -Arguments @('ls-files','--others','--exclude-standard')
  $untracked = if ([string]::IsNullOrWhiteSpace($untrackedResult.text)) { @() } else { @($untrackedResult.text -split "`r?`n") }
  $collisionCount = 0
  foreach ($path in $untracked) {
    if ([string]::IsNullOrWhiteSpace($path)) { continue }
    $probe = Get-GitText -Repo $source -Arguments @('rev-parse',"$expected`:$path") -AllowFailure
    if ($probe.code -ne 0 -or [string]::IsNullOrWhiteSpace($probe.text)) { continue }
    $from = Join-Path $previewRoot ($path -replace '/','\')
    if (-not (Test-Path -LiteralPath $from -PathType Leaf)) { continue }
    $to = Join-Path $quarantine ("untracked\" + ($path -replace '/','\'))
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $to) | Out-Null
    Move-Item -LiteralPath $from -Destination $to -Force
    $collisionCount++
  }

  & $script:Git -c "safe.directory=$previewRoot" -C $previewRoot reset --hard HEAD
  if ($LASTEXITCODE -ne 0) { throw "WADDLE_CERTIFIED_PREVIEW=FAIL worktree_clean_before_checkout path=$previewRoot" }
  $global:LASTEXITCODE = 0
  & $script:Git -c "safe.directory=$previewRoot" -C $previewRoot checkout --detach $expected
  if ($LASTEXITCODE -ne 0) { throw "WADDLE_CERTIFIED_PREVIEW=FAIL worktree_checkout path=$previewRoot" }
  $global:LASTEXITCODE = 0
  & $script:Git -c "safe.directory=$previewRoot" -C $previewRoot reset --hard $expected
  if ($LASTEXITCODE -ne 0) { throw "WADDLE_CERTIFIED_PREVIEW=FAIL worktree_reset path=$previewRoot expected=$expected" }
  $global:LASTEXITCODE = 0
  Write-Host "WADDLE_CERTIFIED_PREVIEW_WORKTREE=PASS mode=updated path=$previewRoot quarantined_tracked=$($dirtyPaths.Count) quarantined_collisions=$collisionCount"
}

$previewHead = (Get-GitText -Repo $previewRoot -Arguments @('rev-parse','HEAD')).text.ToLowerInvariant()
$previewDirty = (Get-GitText -Repo $previewRoot -Arguments @('status','--porcelain=v1','--untracked-files=no')).text
if ($previewHead -ne $expected) { throw "WADDLE_CERTIFIED_PREVIEW=FAIL preview_head expected=$expected actual=$previewHead" }
if (-not [string]::IsNullOrWhiteSpace($previewDirty)) { throw "WADDLE_CERTIFIED_PREVIEW=FAIL preview_tracked_dirty path=$previewRoot" }

Assert-CanonicalUnchanged -Repo $source -Before $canonicalBefore

# The interactive preview is authoritative for this project. Remove only other
# verified Waddle Forever Electron clients under AndroidBuild-managed roots so a
# stale canonical checkout cannot remain visible while the certified preview runs.
Stop-OtherWaddleClients -Root $AndroidBuildRoot

$startScript = Join-Path $previewRoot '.github\scripts\waddle-start.ps1'
if (-not (Test-Path -LiteralPath $startScript -PathType Leaf)) {
  throw "WADDLE_CERTIFIED_PREVIEW=FAIL start_script_missing=$startScript"
}
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $startScript -AndroidBuildRoot $AndroidBuildRoot
$startExit = $LASTEXITCODE
$global:LASTEXITCODE = 0
if ($startExit -ne 0) { throw "WADDLE_CERTIFIED_PREVIEW=FAIL start_exit=$startExit" }

$runtimeStatePath = Join-Path $previewRoot '.work\state\waddle-client.json'
if (-not (Test-Path -LiteralPath $runtimeStatePath -PathType Leaf)) {
  throw "WADDLE_CERTIFIED_PREVIEW=FAIL runtime_state_missing=$runtimeStatePath"
}
$runtimeState = Get-Content -LiteralPath $runtimeStatePath -Raw | ConvertFrom-Json
$runtimeSha = ([string]$runtimeState.source_sha).Trim().ToLowerInvariant()
if ([string]$runtimeState.status -ne 'RUNNING') { throw "WADDLE_CERTIFIED_PREVIEW=FAIL runtime_status actual=$($runtimeState.status)" }
if ($runtimeSha -ne $expected) { throw "WADDLE_CERTIFIED_PREVIEW=FAIL runtime_sha expected=$expected actual=$runtimeSha" }
$process = Get-Process -Id ([int]$runtimeState.pid) -ErrorAction SilentlyContinue
if (-not $process) { throw "WADDLE_CERTIFIED_PREVIEW=FAIL runtime_process_missing pid=$($runtimeState.pid)" }
$postBuildDirty = (Get-GitText -Repo $previewRoot -Arguments @('status','--porcelain=v1','--untracked-files=no')).text
if (-not [string]::IsNullOrWhiteSpace($postBuildDirty)) { throw "WADDLE_CERTIFIED_PREVIEW=FAIL preview_source_mutated_by_start path=$previewRoot" }

Assert-CanonicalUnchanged -Repo $source -Before $canonicalBefore

$state = [ordered]@{
  schema='waddle-certified-preview/v1'
  status='PASS'
  repository=$Repository
  target_branch=$TargetBranch
  source_sha=$expected
  certification_run_id=$CertificationRunId
  canonical_repo=$source
  canonical_branch=$canonicalBefore.branch
  canonical_head=$canonicalBefore.head
  canonical_tracked_state_preserved=$true
  preview_root=$previewRoot
  preview_head=$previewHead
  runtime_pid=[int]$runtimeState.pid
  runtime_status='RUNNING'
  exclusive_runtime=$true
  activated_utc=[DateTime]::UtcNow.ToString('o')
}
$statePath = Join-Path $stateRoot ("$safeTarget.json")
$state | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statePath -Encoding UTF8
Write-Host "VALIDATED_SOURCE_SYNC=PASS mode=isolated_certified_preview branch=$TargetBranch sha=$expected preview=$previewRoot canonical_branch=$($canonicalBefore.branch) canonical_head=$($canonicalBefore.head) canonical_preserved=true exclusive_runtime=true pid=$($runtimeState.pid)"
