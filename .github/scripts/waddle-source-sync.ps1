[CmdletBinding()]
param(
  [ValidateSet('manual','start','setup','post-checkout')]
  [string]$Trigger = 'manual',
  [switch]$RequireRemote
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$work = Join-Path $repo '.work'
$stateDir = Join-Path $work 'state'
$logDir = Join-Path $work 'logs\source-sync'
$statePath = Join-Path $stateDir 'source-sync.json'
New-Item -ItemType Directory -Force -Path $stateDir,$logDir | Out-Null

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$logPath = Join-Path $logDir ("source-sync-$stamp.log")
$lastLog = Join-Path $logDir 'source-sync-last.log'

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
    [string]$Message = ''
  )
  [ordered]@{
    schema = 'waddle-source-sync/v1'
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
    dirty_count = $DirtyCount
    message = $Message
  } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $statePath -Encoding UTF8
  try { Copy-Item -LiteralPath $logPath -Destination $lastLog -Force } catch {}
}

$gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue
if (-not $gitCommand) { $gitCommand = Get-Command git -ErrorAction SilentlyContinue }
if (-not $gitCommand) {
  $message = 'Git is not available on PATH.'
  Write-SyncLine "WADDLE_SOURCE_SYNC=FAIL reason=git_missing trigger=$Trigger"
  Save-SyncState -Status 'FAIL' -Mode 'git_missing' -Message $message
  exit 2
}
$git = [string]$gitCommand.Source

function Invoke-RepoGit {
  param(
    [Parameter(Mandatory)][string[]]$Arguments,
    [switch]$AllowFailure
  )
  $savedPreference = $ErrorActionPreference
  $lines = New-Object System.Collections.Generic.List[string]
  $exitCode = 1
  try {
    $ErrorActionPreference = 'Continue'
    & $git -c "safe.directory=$repo" -C $repo @Arguments 2>&1 | ForEach-Object { $lines.Add([string]$_) }
    $exitCode = $LASTEXITCODE
    $global:LASTEXITCODE = 0
  } finally {
    $ErrorActionPreference = $savedPreference
  }
  $text = ($lines -join "`n").Trim()
  if ($exitCode -ne 0 -and -not $AllowFailure) {
    throw "git $($Arguments -join ' ') failed with exit ${exitCode}: $text"
  }
  return [pscustomobject]@{ exit_code=$exitCode; text=$text }
}

if ($env:GITHUB_ACTIONS -eq 'true' -or $env:CI -eq 'true') {
  $head = (Invoke-RepoGit -Arguments @('rev-parse','HEAD')).text.Trim().ToLowerInvariant()
  Write-SyncLine "WADDLE_SOURCE_SYNC=PASS mode=ci_exact_sha trigger=$Trigger sha=$head mutation=false"
  Save-SyncState -Status 'PASS' -Mode 'ci_exact_sha' -LocalSha $head -Message 'CI exact-SHA workspaces are never synchronized or mutated.'
  exit 0
}

if ($env:WADDLE_DISABLE_SOURCE_SYNC -eq '1') {
  $head = (Invoke-RepoGit -Arguments @('rev-parse','HEAD')).text.Trim().ToLowerInvariant()
  Write-SyncLine "WADDLE_SOURCE_SYNC=PASS mode=disabled trigger=$Trigger sha=$head mutation=false"
  Save-SyncState -Status 'PASS' -Mode 'disabled' -LocalSha $head -Message 'Source synchronization disabled by WADDLE_DISABLE_SOURCE_SYNC=1.'
  exit 0
}

try {
  Invoke-RepoGit -Arguments @('config','--local','pull.ff','only') | Out-Null
  Invoke-RepoGit -Arguments @('config','--local','fetch.prune','true') | Out-Null

  $branchProbe = Invoke-RepoGit -Arguments @('symbolic-ref','--quiet','--short','HEAD') -AllowFailure
  $localSha = (Invoke-RepoGit -Arguments @('rev-parse','HEAD')).text.Trim().ToLowerInvariant()
  if ($branchProbe.exit_code -ne 0 -or [string]::IsNullOrWhiteSpace($branchProbe.text)) {
    Write-SyncLine "WADDLE_SOURCE_SYNC=PASS mode=detached_exact_sha trigger=$Trigger sha=$localSha mutation=false"
    Save-SyncState -Status 'PASS' -Mode 'detached_exact_sha' -LocalSha $localSha -Message 'Detached HEAD is intentionally left unchanged.'
    exit 0
  }
  $branch = $branchProbe.text.Trim()

  $remoteProbe = Invoke-RepoGit -Arguments @('config','--get',"branch.$branch.remote") -AllowFailure
  $mergeProbe = Invoke-RepoGit -Arguments @('config','--get',"branch.$branch.merge") -AllowFailure
  $remote = if ($remoteProbe.exit_code -eq 0) { $remoteProbe.text.Trim() } else { '' }
  $mergeRef = if ($mergeProbe.exit_code -eq 0) { $mergeProbe.text.Trim() } else { '' }

  if ([string]::IsNullOrWhiteSpace($remote) -or $remote -eq '.' -or [string]::IsNullOrWhiteSpace($mergeRef)) {
    $remotes = @((Invoke-RepoGit -Arguments @('remote')).text -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($remotes -contains 'androidbuild-source') { $remote = 'androidbuild-source' }
    elseif ($remotes -contains 'origin') { $remote = 'origin' }
    elseif ($remotes.Count -gt 0) { $remote = [string]$remotes[0] }
    else {
      Write-SyncLine "WADDLE_SOURCE_SYNC=WARN mode=no_remote branch=$branch sha=$localSha trigger=$Trigger"
      Save-SyncState -Status 'WARN' -Mode 'no_remote' -Branch $branch -LocalSha $localSha -Message 'No Git remote is configured.'
      if ($RequireRemote) { exit 3 } else { exit 0 }
    }
    $mergeRef = "refs/heads/$branch"
  }

  $remoteBranch = $mergeRef -replace '^refs/heads/',''
  $remoteRef = "refs/remotes/$remote/$remoteBranch"

  $fetch = Invoke-RepoGit -Arguments @('fetch','--no-tags','--prune',$remote,"+refs/heads/$remoteBranch`:$remoteRef") -AllowFailure
  if ($fetch.exit_code -ne 0) {
    $message = ($fetch.text -replace "`r|`n",' ').Trim()
    Write-SyncLine "WADDLE_SOURCE_SYNC=WARN mode=offline_or_fetch_failed branch=$branch remote=$remote remote_branch=$remoteBranch sha=$localSha trigger=$Trigger"
    Save-SyncState -Status 'WARN' -Mode 'offline_or_fetch_failed' -Branch $branch -Remote $remote -RemoteBranch $remoteBranch -LocalSha $localSha -Message $message
    if ($RequireRemote) { exit 4 } else { exit 0 }
  }

  $remoteShaProbe = Invoke-RepoGit -Arguments @('rev-parse',$remoteRef) -AllowFailure
  if ($remoteShaProbe.exit_code -ne 0 -or [string]::IsNullOrWhiteSpace($remoteShaProbe.text)) {
    Write-SyncLine "WADDLE_SOURCE_SYNC=WARN mode=remote_branch_missing branch=$branch remote=$remote remote_branch=$remoteBranch trigger=$Trigger"
    Save-SyncState -Status 'WARN' -Mode 'remote_branch_missing' -Branch $branch -Remote $remote -RemoteBranch $remoteBranch -LocalSha $localSha -Message 'The matching branch does not exist on the selected remote.'
    if ($RequireRemote) { exit 5 } else { exit 0 }
  }
  $remoteSha = $remoteShaProbe.text.Trim().ToLowerInvariant()

  if ($remoteProbe.exit_code -ne 0 -or $mergeProbe.exit_code -ne 0 -or [string]::IsNullOrWhiteSpace($remoteProbe.text) -or [string]::IsNullOrWhiteSpace($mergeProbe.text)) {
    Invoke-RepoGit -Arguments @('branch',"--set-upstream-to=$remote/$remoteBranch",$branch) | Out-Null
    Write-SyncLine "WADDLE_SOURCE_TRACKING=PASS branch=$branch upstream=$remote/$remoteBranch"
  }

  $dirtyText = (Invoke-RepoGit -Arguments @('status','--porcelain=v1','--untracked-files=normal')).text
  $dirtyEntries = if ([string]::IsNullOrWhiteSpace($dirtyText)) { @() } else { @($dirtyText -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) }
  $dirtyCount = $dirtyEntries.Count

  $counts = (Invoke-RepoGit -Arguments @('rev-list','--left-right','--count',"$remoteRef...HEAD")).text.Trim() -split '\s+'
  if ($counts.Count -lt 2) { throw "Unable to compare HEAD with $remoteRef." }
  $remoteOnly = [int]$counts[0]
  $localOnly = [int]$counts[1]

  if ($remoteOnly -eq 0 -and $localOnly -eq 0) {
    $status = if ($dirtyCount -gt 0) { 'WARN' } else { 'PASS' }
    $mode = if ($dirtyCount -gt 0) { 'up_to_date_with_local_changes' } else { 'up_to_date' }
    Write-SyncLine "WADDLE_SOURCE_SYNC=$status mode=$mode branch=$branch upstream=$remote/$remoteBranch sha=$localSha dirty=$dirtyCount trigger=$Trigger"
    Save-SyncState -Status $status -Mode $mode -Branch $branch -Remote $remote -RemoteBranch $remoteBranch -LocalSha $localSha -RemoteSha $remoteSha -DirtyCount $dirtyCount -Message 'Remote and local commits are aligned.'
    exit 0
  }

  if ($remoteOnly -eq 0 -and $localOnly -gt 0) {
    Write-SyncLine "WADDLE_SOURCE_SYNC=WARN mode=local_ahead branch=$branch upstream=$remote/$remoteBranch sha=$localSha ahead=$localOnly dirty=$dirtyCount trigger=$Trigger"
    Save-SyncState -Status 'WARN' -Mode 'local_ahead' -Branch $branch -Remote $remote -RemoteBranch $remoteBranch -LocalSha $localSha -RemoteSha $remoteSha -DirtyCount $dirtyCount -Message "Local branch is $localOnly commit(s) ahead; nothing was overwritten. Push when ready."
    exit 0
  }

  if ($remoteOnly -gt 0 -and $localOnly -gt 0) {
    Write-SyncLine "WADDLE_SOURCE_SYNC=FAIL reason=diverged branch=$branch upstream=$remote/$remoteBranch local_sha=$localSha remote_sha=$remoteSha remote_only=$remoteOnly local_only=$localOnly dirty=$dirtyCount trigger=$Trigger"
    Save-SyncState -Status 'FAIL' -Mode 'diverged' -Branch $branch -Remote $remote -RemoteBranch $remoteBranch -LocalSha $localSha -RemoteSha $remoteSha -DirtyCount $dirtyCount -Message 'Local and remote histories diverged; automatic synchronization is intentionally blocked.'
    exit 6
  }

  if ($remoteOnly -gt 0 -and $dirtyCount -gt 0) {
    Write-SyncLine "WADDLE_SOURCE_SYNC=FAIL reason=remote_ahead_with_local_changes branch=$branch upstream=$remote/$remoteBranch local_sha=$localSha remote_sha=$remoteSha behind=$remoteOnly dirty=$dirtyCount trigger=$Trigger"
    Write-SyncLine 'WADDLE_SOURCE_SYNC_PROTECTION=PASS action=none local_files_preserved=true'
    Save-SyncState -Status 'FAIL' -Mode 'remote_ahead_with_local_changes' -Branch $branch -Remote $remote -RemoteBranch $remoteBranch -LocalSha $localSha -RemoteSha $remoteSha -DirtyCount $dirtyCount -Message 'Remote is newer, but local files contain changes. Commit, restore, or stash them before synchronizing.'
    exit 7
  }

  if ($remoteOnly -gt 0 -and $localOnly -eq 0) {
    $before = $localSha
    Invoke-RepoGit -Arguments @('merge','--ff-only',$remoteRef) | Out-Null
    $after = (Invoke-RepoGit -Arguments @('rev-parse','HEAD')).text.Trim().ToLowerInvariant()
    if ($after -ne $remoteSha) { throw "Fast-forward verification failed: expected $remoteSha, got $after." }
    Write-SyncLine "WADDLE_SOURCE_SYNC=PASS mode=fast_forward branch=$branch upstream=$remote/$remoteBranch from=$before to=$after commits=$remoteOnly dirty=0 trigger=$Trigger"
    Save-SyncState -Status 'PASS' -Mode 'fast_forward' -Branch $branch -Remote $remote -RemoteBranch $remoteBranch -LocalSha $after -RemoteSha $remoteSha -DirtyCount 0 -Message "Fast-forwarded $remoteOnly commit(s) without merge commits or file deletion commands."
    exit 0
  }

  throw 'Unexpected source synchronization state.'
} catch {
  $message = $_.Exception.Message
  Write-SyncLine "WADDLE_SOURCE_SYNC=FAIL reason=internal trigger=$Trigger message=$message"
  Save-SyncState -Status 'FAIL' -Mode 'internal_error' -Message $message
  exit 8
}
