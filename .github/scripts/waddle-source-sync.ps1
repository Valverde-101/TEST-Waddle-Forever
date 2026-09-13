[CmdletBinding()]
param(
  [ValidateSet('manual','start','setup','post-checkout','ci-publish')]
  [string]$Trigger = 'manual',
  [switch]$RequireRemote,
  [string]$RepoRoot,
  [string]$TargetBranch,
  [string]$ExpectedSha,
  [string]$AndroidBuildRoot,
  [switch]$AllowCiMutation,
  [switch]$RequireCore,
  [switch]$InstallHooks
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = if([string]::IsNullOrWhiteSpace($RepoRoot)) {
  [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
} else {
  [IO.Path]::GetFullPath($RepoRoot).TrimEnd('\')
}
$work = Join-Path $repo '.work'
$stateDir = Join-Path $work 'state'
$logDir = Join-Path $work 'logs\source-sync'
$statePath = Join-Path $stateDir 'source-sync.json'
New-Item -ItemType Directory -Force -Path $stateDir,$logDir | Out-Null

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$logPath = Join-Path $logDir ("source-sync-$stamp.log")
$lastLog = Join-Path $logDir 'source-sync-last.log'
$lockPath = Join-Path $stateDir 'source-sync.lock'
$script:syncLock = $null

function Write-SyncLine {
  param([Parameter(Mandatory)][string]$Text)
  Add-Content -LiteralPath $logPath -Value $Text -Encoding UTF8
  Write-Host $Text
}

function Save-SyncState {
  param(
    [Parameter(Mandatory)][string]$Status,
    [Parameter(Mandatory)][string]$Mode,
    [string]$Branch = '',
    [string]$Remote = '',
    [string]$RemoteBranch = '',
    [string]$LocalSha = '',
    [string]$RemoteSha = '',
    [int]$DirtyCount = 0,
    [string]$Message = '',
    [string]$CoreVersion = '',
    [string]$GitPath = ''
  )
  [ordered]@{
    schema = 'waddle-source-sync/v2'
    generated_utc = [DateTime]::UtcNow.ToString('o')
    status = $Status
    mode = $Mode
    trigger = $Trigger
    repository = $repo
    branch = $Branch
    remote = $Remote
    remote_branch = $RemoteBranch
    local_sha = $LocalSha
    remote_sha = $RemoteSha
    expected_sha = $ExpectedSha
    dirty_count = $DirtyCount
    core_version = $CoreVersion
    git_path = $GitPath
    message = $Message
  } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statePath -Encoding UTF8
  try { Copy-Item -LiteralPath $logPath -Destination $lastLog -Force } catch {}
}

function Find-AndroidBuildRoot {
  param([string]$Preferred)
  $candidates = New-Object System.Collections.Generic.List[string]
  if(-not [string]::IsNullOrWhiteSpace($Preferred)) { $candidates.Add($Preferred) }
  if(-not [string]::IsNullOrWhiteSpace($env:ANDROIDBUILD_ROOT) -and -not $candidates.Contains($env:ANDROIDBUILD_ROOT)) { $candidates.Add($env:ANDROIDBUILD_ROOT) }
  foreach($drive in [IO.DriveInfo]::GetDrives()) {
    try {
      if(-not $drive.IsReady) { continue }
      $candidate = [IO.Path]::Combine($drive.RootDirectory.FullName,'AndroidBuild')
      if(-not $candidates.Contains($candidate)) { $candidates.Add($candidate) }
    } catch {}
  }
  foreach($candidate in $candidates) {
    try { $full = (Resolve-Path -LiteralPath $candidate -ErrorAction Stop).Path } catch { continue }
    if(Test-Path -LiteralPath (Join-Path $full 'Core\Current\AndroidBuild.psd1') -PathType Leaf) { return $full }
  }
  return ''
}

function Resolve-SyncGit {
  param([string]$Root)
  $coreVersion = ''
  $gitPath = ''
  if(-not [string]::IsNullOrWhiteSpace($Root)) {
    try {
      $coreModule = Join-Path $Root 'Core\Current\AndroidBuild.psd1'
      Import-Module $coreModule -DisableNameChecking -Force -WarningAction SilentlyContinue
      if(Get-Command Get-AndroidBuildCoreVersion -ErrorAction SilentlyContinue) {
        $coreVersion = [string](Get-AndroidBuildCoreVersion)
      }
      if(Get-Command Enable-AndroidBuildPortableTools -ErrorAction SilentlyContinue) {
        Enable-AndroidBuildPortableTools -AndroidBuildRoot $Root | Out-Null
      }
      if(Get-Command Get-AndroidBuildGitPath -ErrorAction SilentlyContinue) {
        $gitPath = [string](Get-AndroidBuildGitPath -AndroidBuildRoot $Root)
      }
      if(-not [string]::IsNullOrWhiteSpace($gitPath) -and (Test-Path -LiteralPath $gitPath -PathType Leaf)) {
        Write-SyncLine "WADDLE_SOURCE_SYNC_CORE=PASS root=$Root core=$coreVersion git=$gitPath"
        return [pscustomobject]@{ git=$gitPath; core_version=$coreVersion; root=$Root; mode='androidbuild-core' }
      }
    } catch {
      Write-SyncLine "WADDLE_SOURCE_SYNC_CORE=WARN root=$Root error=$($_.Exception.Message)"
    }
  }

  if($RequireCore) {
    throw 'AndroidBuild Core with managed Git is required for this synchronization.'
  }
  $gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue
  if(-not $gitCommand) { $gitCommand = Get-Command git -ErrorAction SilentlyContinue }
  if(-not $gitCommand) { throw 'Git is not available and AndroidBuild Core could not provide managed Git.' }
  $gitPath = [string]$gitCommand.Source
  Write-SyncLine "WADDLE_SOURCE_SYNC_CORE=WARN mode=fallback-path git=$gitPath"
  return [pscustomobject]@{ git=$gitPath; core_version=$coreVersion; root=$Root; mode='path-fallback' }
}

function Invoke-RepoGit {
  param(
    [Parameter(Mandatory)][string]$GitPath,
    [Parameter(Mandatory)][string[]]$Arguments,
    [switch]$AllowFailure
  )
  $savedPreference = $ErrorActionPreference
  $lines = New-Object System.Collections.Generic.List[string]
  $exitCode = 1
  try {
    $ErrorActionPreference = 'Continue'
    & $GitPath -c "safe.directory=$repo" -C $repo @Arguments 2>&1 | ForEach-Object { $lines.Add([string]$_) }
    $exitCode = $LASTEXITCODE
    $global:LASTEXITCODE = 0
  } finally {
    $ErrorActionPreference = $savedPreference
  }
  $text = ($lines -join "`n").Trim()
  if($exitCode -ne 0 -and -not $AllowFailure) {
    throw "git $($Arguments -join ' ') failed with exit ${exitCode}: $text"
  }
  return [pscustomobject]@{ exit_code=$exitCode; text=$text }
}

function Acquire-SyncLock {
  $deadline = [DateTime]::UtcNow.AddSeconds(45)
  while([DateTime]::UtcNow -lt $deadline) {
    try {
      $script:syncLock = [IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
      $script:syncLock.SetLength(0)
      $payload = [Text.Encoding]::UTF8.GetBytes("pid=$PID trigger=$Trigger started_utc=$([DateTime]::UtcNow.ToString('o'))")
      $script:syncLock.Write($payload,0,$payload.Length)
      $script:syncLock.Flush()
      Write-SyncLine "WADDLE_SOURCE_SYNC_LOCK=PASS pid=$PID trigger=$Trigger"
      return
    } catch {
      Start-Sleep -Milliseconds 500
    }
  }
  throw "Timed out waiting for source synchronization lock: $lockPath"
}

function Release-SyncLock {
  if($null -ne $script:syncLock) {
    try { $script:syncLock.Dispose() } catch {}
    $script:syncLock = $null
  }
}

$coreRoot = Find-AndroidBuildRoot -Preferred $AndroidBuildRoot
$tool = $null
try {
  $tool = Resolve-SyncGit -Root $coreRoot
  $git = [string]$tool.git
  $coreVersion = [string]$tool.core_version

  if(($env:GITHUB_ACTIONS -eq 'true' -or $env:CI -eq 'true') -and -not $AllowCiMutation) {
    $head = (Invoke-RepoGit -GitPath $git -Arguments @('rev-parse','HEAD')).text.Trim().ToLowerInvariant()
    Write-SyncLine "WADDLE_SOURCE_SYNC=PASS mode=ci_exact_sha trigger=$Trigger sha=$head mutation=false core=$coreVersion"
    Save-SyncState -Status 'PASS' -Mode 'ci_exact_sha' -LocalSha $head -Message 'CI exact-SHA workspaces are never synchronized or mutated.' -CoreVersion $coreVersion -GitPath $git
    exit 0
  }

  if($env:WADDLE_DISABLE_SOURCE_SYNC -eq '1') {
    $head = (Invoke-RepoGit -GitPath $git -Arguments @('rev-parse','HEAD')).text.Trim().ToLowerInvariant()
    Write-SyncLine "WADDLE_SOURCE_SYNC=PASS mode=disabled trigger=$Trigger sha=$head mutation=false"
    Save-SyncState -Status 'PASS' -Mode 'disabled' -LocalSha $head -Message 'Source synchronization disabled by WADDLE_DISABLE_SOURCE_SYNC=1.' -CoreVersion $coreVersion -GitPath $git
    exit 0
  }

  Acquire-SyncLock

  Invoke-RepoGit -GitPath $git -Arguments @('config','--local','pull.ff','only') | Out-Null
  Invoke-RepoGit -GitPath $git -Arguments @('config','--local','fetch.prune','true') | Out-Null
  if($InstallHooks -or (Test-Path -LiteralPath (Join-Path $repo '.githooks') -PathType Container)) {
    if(Test-Path -LiteralPath (Join-Path $repo '.githooks') -PathType Container) {
      Invoke-RepoGit -GitPath $git -Arguments @('config','--local','core.hooksPath','.githooks') | Out-Null
      Write-SyncLine 'WADDLE_SOURCE_HOOKS=PASS path=.githooks scope=repository'
    }
  }

  $branchProbe = Invoke-RepoGit -GitPath $git -Arguments @('symbolic-ref','--quiet','--short','HEAD') -AllowFailure
  $localSha = (Invoke-RepoGit -GitPath $git -Arguments @('rev-parse','HEAD')).text.Trim().ToLowerInvariant()
  if($branchProbe.exit_code -ne 0 -or [string]::IsNullOrWhiteSpace($branchProbe.text)) {
    Write-SyncLine "WADDLE_SOURCE_SYNC=PASS mode=detached_exact_sha trigger=$Trigger sha=$localSha mutation=false"
    Save-SyncState -Status 'PASS' -Mode 'detached_exact_sha' -LocalSha $localSha -Message 'Detached HEAD is intentionally left unchanged.' -CoreVersion $coreVersion -GitPath $git
    exit 0
  }
  $branch = $branchProbe.text.Trim()

  if(-not [string]::IsNullOrWhiteSpace($TargetBranch) -and -not $branch.Equals($TargetBranch,[StringComparison]::OrdinalIgnoreCase)) {
    Write-SyncLine "WADDLE_SOURCE_SYNC=FAIL reason=branch_mismatch current=$branch target=$TargetBranch trigger=$Trigger"
    Save-SyncState -Status 'FAIL' -Mode 'branch_mismatch' -Branch $branch -LocalSha $localSha -Message "Current branch '$branch' is not target '$TargetBranch'." -CoreVersion $coreVersion -GitPath $git
    exit 9
  }

  $remoteProbe = Invoke-RepoGit -GitPath $git -Arguments @('config','--get',"branch.$branch.remote") -AllowFailure
  $mergeProbe = Invoke-RepoGit -GitPath $git -Arguments @('config','--get',"branch.$branch.merge") -AllowFailure
  $remote = if($remoteProbe.exit_code -eq 0) { $remoteProbe.text.Trim() } else { '' }
  $mergeRef = if($mergeProbe.exit_code -eq 0) { $mergeProbe.text.Trim() } else { '' }

  if([string]::IsNullOrWhiteSpace($remote) -or $remote -eq '.' -or [string]::IsNullOrWhiteSpace($mergeRef)) {
    $remotes = @((Invoke-RepoGit -GitPath $git -Arguments @('remote')).text -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if($remotes -contains 'androidbuild-source') { $remote = 'androidbuild-source' }
    elseif($remotes -contains 'origin') { $remote = 'origin' }
    elseif($remotes.Count -gt 0) { $remote = [string]$remotes[0] }
    else {
      Write-SyncLine "WADDLE_SOURCE_SYNC=WARN mode=no_remote branch=$branch sha=$localSha trigger=$Trigger"
      Save-SyncState -Status 'WARN' -Mode 'no_remote' -Branch $branch -LocalSha $localSha -Message 'No Git remote is configured.' -CoreVersion $coreVersion -GitPath $git
      if($RequireRemote) { exit 3 } else { exit 0 }
    }
    $mergeRef = "refs/heads/$branch"
  }

  $remoteBranch = $mergeRef -replace '^refs/heads/',''
  $remoteRef = "refs/remotes/$remote/$remoteBranch"
  $fetch = Invoke-RepoGit -GitPath $git -Arguments @('fetch','--no-tags','--prune',$remote,"+refs/heads/$remoteBranch`:$remoteRef") -AllowFailure
  if($fetch.exit_code -ne 0) {
    $message = ($fetch.text -replace "`r|`n",' ').Trim()
    Write-SyncLine "WADDLE_SOURCE_SYNC=WARN mode=offline_or_fetch_failed branch=$branch remote=$remote remote_branch=$remoteBranch sha=$localSha trigger=$Trigger"
    Save-SyncState -Status 'WARN' -Mode 'offline_or_fetch_failed' -Branch $branch -Remote $remote -RemoteBranch $remoteBranch -LocalSha $localSha -Message $message -CoreVersion $coreVersion -GitPath $git
    if($RequireRemote) { exit 4 } else { exit 0 }
  }

  $remoteShaProbe = Invoke-RepoGit -GitPath $git -Arguments @('rev-parse',$remoteRef) -AllowFailure
  if($remoteShaProbe.exit_code -ne 0 -or [string]::IsNullOrWhiteSpace($remoteShaProbe.text)) {
    Write-SyncLine "WADDLE_SOURCE_SYNC=WARN mode=remote_branch_missing branch=$branch remote=$remote remote_branch=$remoteBranch trigger=$Trigger"
    Save-SyncState -Status 'WARN' -Mode 'remote_branch_missing' -Branch $branch -Remote $remote -RemoteBranch $remoteBranch -LocalSha $localSha -Message 'The matching branch does not exist on the selected remote.' -CoreVersion $coreVersion -GitPath $git
    if($RequireRemote) { exit 5 } else { exit 0 }
  }
  $remoteSha = $remoteShaProbe.text.Trim().ToLowerInvariant()

  if(-not [string]::IsNullOrWhiteSpace($ExpectedSha)) {
    $expected = $ExpectedSha.Trim().ToLowerInvariant()
    if($remoteSha -ne $expected) {
      $mode = if($Trigger -eq 'ci-publish') { 'stale_ci_publish' } else { 'expected_sha_mismatch' }
      $status = if($Trigger -eq 'ci-publish') { 'PASS' } else { 'FAIL' }
      Write-SyncLine "WADDLE_SOURCE_SYNC=$status mode=$mode branch=$branch expected=$expected remote_sha=$remoteSha mutation=false"
      Save-SyncState -Status $status -Mode $mode -Branch $branch -Remote $remote -RemoteBranch $remoteBranch -LocalSha $localSha -RemoteSha $remoteSha -Message 'Remote branch no longer points at the requested SHA; stale synchronization was not applied.' -CoreVersion $coreVersion -GitPath $git
      if($Trigger -eq 'ci-publish') { exit 0 } else { exit 10 }
    }
  }

  if($remoteProbe.exit_code -ne 0 -or $mergeProbe.exit_code -ne 0 -or [string]::IsNullOrWhiteSpace($remoteProbe.text) -or [string]::IsNullOrWhiteSpace($mergeProbe.text)) {
    Invoke-RepoGit -GitPath $git -Arguments @('branch',"--set-upstream-to=$remote/$remoteBranch",$branch) | Out-Null
    Write-SyncLine "WADDLE_SOURCE_TRACKING=PASS branch=$branch upstream=$remote/$remoteBranch"
  }

  $dirtyText = (Invoke-RepoGit -GitPath $git -Arguments @('status','--porcelain=v1','--untracked-files=normal')).text
  $dirtyEntries = if([string]::IsNullOrWhiteSpace($dirtyText)) { @() } else { @($dirtyText -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) }
  $dirtyCount = $dirtyEntries.Count

  $counts = (Invoke-RepoGit -GitPath $git -Arguments @('rev-list','--left-right','--count',"$remoteRef...HEAD")).text.Trim() -split '\s+'
  if($counts.Count -lt 2) { throw "Unable to compare HEAD with $remoteRef." }
  $remoteOnly = [int]$counts[0]
  $localOnly = [int]$counts[1]

  if($remoteOnly -eq 0 -and $localOnly -eq 0) {
    $status = if($dirtyCount -gt 0) { 'WARN' } else { 'PASS' }
    $mode = if($dirtyCount -gt 0) { 'up_to_date_with_local_changes' } else { 'up_to_date' }
    Write-SyncLine "WADDLE_SOURCE_SYNC=$status mode=$mode branch=$branch upstream=$remote/$remoteBranch sha=$localSha dirty=$dirtyCount trigger=$Trigger core=$coreVersion"
    Save-SyncState -Status $status -Mode $mode -Branch $branch -Remote $remote -RemoteBranch $remoteBranch -LocalSha $localSha -RemoteSha $remoteSha -DirtyCount $dirtyCount -Message 'Remote and local commits are aligned.' -CoreVersion $coreVersion -GitPath $git
    exit 0
  }

  if($remoteOnly -eq 0 -and $localOnly -gt 0) {
    Write-SyncLine "WADDLE_SOURCE_SYNC=WARN mode=local_ahead branch=$branch upstream=$remote/$remoteBranch sha=$localSha ahead=$localOnly dirty=$dirtyCount trigger=$Trigger"
    Save-SyncState -Status 'WARN' -Mode 'local_ahead' -Branch $branch -Remote $remote -RemoteBranch $remoteBranch -LocalSha $localSha -RemoteSha $remoteSha -DirtyCount $dirtyCount -Message "Local branch is $localOnly commit(s) ahead; local commits were preserved for manual push/review." -CoreVersion $coreVersion -GitPath $git
    exit 0
  }

  if($remoteOnly -gt 0 -and $localOnly -gt 0) {
    Write-SyncLine "WADDLE_SOURCE_SYNC=FAIL reason=diverged branch=$branch upstream=$remote/$remoteBranch local_sha=$localSha remote_sha=$remoteSha remote_only=$remoteOnly local_only=$localOnly dirty=$dirtyCount trigger=$Trigger"
    Save-SyncState -Status 'FAIL' -Mode 'diverged' -Branch $branch -Remote $remote -RemoteBranch $remoteBranch -LocalSha $localSha -RemoteSha $remoteSha -DirtyCount $dirtyCount -Message 'Local and remote histories diverged; automatic synchronization is intentionally blocked.' -CoreVersion $coreVersion -GitPath $git
    exit 6
  }

  if($remoteOnly -gt 0 -and $dirtyCount -gt 0) {
    Write-SyncLine "WADDLE_SOURCE_SYNC=FAIL reason=remote_ahead_with_local_changes branch=$branch upstream=$remote/$remoteBranch local_sha=$localSha remote_sha=$remoteSha behind=$remoteOnly dirty=$dirtyCount trigger=$Trigger"
    Write-SyncLine 'WADDLE_SOURCE_SYNC_PROTECTION=PASS action=none local_files_preserved=true hard_reset=false clean=false'
    Save-SyncState -Status 'FAIL' -Mode 'remote_ahead_with_local_changes' -Branch $branch -Remote $remote -RemoteBranch $remoteBranch -LocalSha $localSha -RemoteSha $remoteSha -DirtyCount $dirtyCount -Message 'Remote is newer, but local files contain changes. Commit, restore, or stash them before synchronizing.' -CoreVersion $coreVersion -GitPath $git
    exit 7
  }

  if($remoteOnly -gt 0 -and $localOnly -eq 0) {
    $before = $localSha
    Invoke-RepoGit -GitPath $git -Arguments @('merge','--ff-only',$remoteRef) | Out-Null
    $after = (Invoke-RepoGit -GitPath $git -Arguments @('rev-parse','HEAD')).text.Trim().ToLowerInvariant()
    if($after -ne $remoteSha) { throw "Fast-forward verification failed: expected $remoteSha, got $after." }
    Write-SyncLine "WADDLE_SOURCE_SYNC=PASS mode=fast_forward branch=$branch upstream=$remote/$remoteBranch from=$before to=$after commits=$remoteOnly dirty=0 trigger=$Trigger core=$coreVersion"
    Save-SyncState -Status 'PASS' -Mode 'fast_forward' -Branch $branch -Remote $remote -RemoteBranch $remoteBranch -LocalSha $after -RemoteSha $remoteSha -DirtyCount 0 -Message "Fast-forwarded $remoteOnly commit(s) without merge commits, hard reset, clean, or local-file deletion." -CoreVersion $coreVersion -GitPath $git
    exit 0
  }

  throw 'Unexpected source synchronization state.'
} catch {
  $message = $_.Exception.Message
  Write-SyncLine "WADDLE_SOURCE_SYNC=FAIL reason=internal trigger=$Trigger message=$message"
  $coreVersion = if($tool) { [string]$tool.core_version } else { '' }
  $gitPath = if($tool) { [string]$tool.git } else { '' }
  Save-SyncState -Status 'FAIL' -Mode 'internal_error' -Message $message -CoreVersion $coreVersion -GitPath $gitPath
  exit 8
} finally {
  Release-SyncLock
}
