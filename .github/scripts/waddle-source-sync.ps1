[CmdletBinding()]
param(
  [ValidateSet('manual','start','setup','post-checkout','ci-publish')]
  [string]$Trigger='manual',
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
$ErrorActionPreference='Stop'
$repo=if([string]::IsNullOrWhiteSpace($RepoRoot)){[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')}else{[IO.Path]::GetFullPath($RepoRoot).TrimEnd('\')}
$work=Join-Path $repo '.work'
$stateDir=Join-Path $work 'state'
$logDir=Join-Path $work 'logs\source-sync'
$statePath=Join-Path $stateDir 'source-sync.json'
$lockPath=Join-Path $stateDir 'source-sync.lock'
New-Item -ItemType Directory -Force -Path $stateDir,$logDir|Out-Null
$stamp=Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$logPath=Join-Path $logDir ("source-sync-$stamp.log")
$lastLog=Join-Path $logDir 'source-sync-last.log'
$script:syncLock=$null

function Write-SyncLine([string]$Text){Add-Content -LiteralPath $logPath -Value $Text -Encoding UTF8;Write-Host $Text}
function Save-SyncState {
  param([string]$Status,[string]$Mode,[string]$Branch='',[string]$Remote='',[string]$RemoteBranch='',[string]$LocalSha='',[string]$RemoteSha='',[int]$TrackedDirtyCount=0,[int]$UntrackedCount=0,[bool]$ShallowRepaired=$false,[string]$Message='',[string]$CoreVersion='',[string]$GitPath='')
  [ordered]@{
    schema='waddle-source-sync/v3';generated_utc=[DateTime]::UtcNow.ToString('o');status=$Status;mode=$Mode;trigger=$Trigger;repository=$repo;branch=$Branch;remote=$Remote;remote_branch=$RemoteBranch;local_sha=$LocalSha;remote_sha=$RemoteSha;expected_sha=$ExpectedSha;tracked_dirty_count=$TrackedDirtyCount;dirty_count=$TrackedDirtyCount;untracked_count=$UntrackedCount;shallow_repaired=$ShallowRepaired;core_version=$CoreVersion;git_path=$GitPath;hard_reset=$false;clean=$false;local_files_overwritten=$false;local_commits_overwritten=$false;message=$Message
  }|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $statePath -Encoding UTF8
  try{Copy-Item -LiteralPath $logPath -Destination $lastLog -Force}catch{}
}
function Find-AndroidBuildRoot([string]$Preferred){
  $candidates=New-Object System.Collections.Generic.List[string]
  if(-not[string]::IsNullOrWhiteSpace($Preferred)){$candidates.Add($Preferred)}
  if($env:ANDROIDBUILD_ROOT -and -not$candidates.Contains($env:ANDROIDBUILD_ROOT)){$candidates.Add([string]$env:ANDROIDBUILD_ROOT)}
  foreach($drive in [IO.DriveInfo]::GetDrives()){
    try{if(-not$drive.IsReady){continue};$candidate=[IO.Path]::Combine($drive.RootDirectory.FullName,'AndroidBuild');if(-not$candidates.Contains($candidate)){$candidates.Add($candidate)}}catch{}
  }
  foreach($candidate in $candidates){try{$full=(Resolve-Path -LiteralPath $candidate -ErrorAction Stop).Path}catch{continue};if(Test-Path -LiteralPath (Join-Path $full 'Core\Current\AndroidBuild.psd1') -PathType Leaf){return $full}}
  ''
}
function Resolve-SyncTool([string]$Root){
  if(-not[string]::IsNullOrWhiteSpace($Root)){
    try{
      Import-Module (Join-Path $Root 'Core\Current\AndroidBuild.psd1') -DisableNameChecking -Force -WarningAction SilentlyContinue
      $coreVersion=if(Get-Command Get-AndroidBuildCoreVersion -ErrorAction SilentlyContinue){[string](Get-AndroidBuildCoreVersion)}else{''}
      if(Get-Command Enable-AndroidBuildPortableTools -ErrorAction SilentlyContinue){Enable-AndroidBuildPortableTools -AndroidBuildRoot $Root|Out-Null}
      if(Get-Command Get-AndroidBuildGitPath -ErrorAction SilentlyContinue){$gitPath=[string](Get-AndroidBuildGitPath -AndroidBuildRoot $Root);if(Test-Path -LiteralPath $gitPath -PathType Leaf){Write-SyncLine "WADDLE_SOURCE_SYNC_CORE=PASS root=$Root core=$coreVersion git=$gitPath";return [pscustomobject]@{git=$gitPath;core=$coreVersion;root=$Root}}}
    }catch{Write-SyncLine "WADDLE_SOURCE_SYNC_CORE=WARN root=$Root error=$($_.Exception.Message)"}
  }
  if($RequireCore){throw 'AndroidBuild Core with managed Git is required.'}
  $cmd=Get-Command git.exe -ErrorAction SilentlyContinue;if(-not$cmd){$cmd=Get-Command git -ErrorAction SilentlyContinue};if(-not$cmd){throw 'Git unavailable.'}
  [pscustomobject]@{git=[string]$cmd.Source;core='';root=$Root}
}
function Invoke-RepoGit([string]$GitPath,[string[]]$Arguments,[switch]$AllowFailure){
  $saved=$ErrorActionPreference;$lines=New-Object System.Collections.Generic.List[string];$code=1
  try{$ErrorActionPreference='Continue';& $GitPath -c "safe.directory=$repo" -C $repo @Arguments 2>&1|ForEach-Object{$lines.Add([string]$_)};$code=$LASTEXITCODE;$global:LASTEXITCODE=0}finally{$ErrorActionPreference=$saved}
  $text=($lines -join "`n").Trim();if($code -ne 0 -and -not$AllowFailure){throw "git $($Arguments -join ' ') failed with exit ${code}: $text"};[pscustomobject]@{exit_code=$code;text=$text}
}
function Acquire-SyncLock {
  $deadline=[DateTime]::UtcNow.AddSeconds(45)
  while([DateTime]::UtcNow -lt $deadline){try{$script:syncLock=[IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);$script:syncLock.SetLength(0);$bytes=[Text.Encoding]::UTF8.GetBytes("pid=$PID trigger=$Trigger utc=$([DateTime]::UtcNow.ToString('o'))");$script:syncLock.Write($bytes,0,$bytes.Length);$script:syncLock.Flush();Write-SyncLine "WADDLE_SOURCE_SYNC_LOCK=PASS pid=$PID trigger=$Trigger";return}catch{Start-Sleep -Milliseconds 500}}
  throw "Source synchronization lock timeout: $lockPath"
}
function Release-SyncLock{if($null-ne$script:syncLock){try{$script:syncLock.Dispose()}catch{};$script:syncLock=$null}}
function Normalize-RepoPath([string]$Path){if([string]::IsNullOrWhiteSpace($Path)){return ''};$Path.Trim().Trim('"').Replace('\','/')}
function Get-TrackedDirtyPaths([string]$GitPath){
  $all=New-Object System.Collections.Generic.List[string]
  foreach($text in @((Invoke-RepoGit $GitPath @('diff','--name-only','--')).text,(Invoke-RepoGit $GitPath @('diff','--cached','--name-only','--')).text)){
    if([string]::IsNullOrWhiteSpace($text)){continue}
    foreach($line in @($text -split "`r?`n")){$path=Normalize-RepoPath $line;if(-not[string]::IsNullOrWhiteSpace($path)){$all.Add($path)}}
  }
  @($all|Sort-Object -Unique)
}
function Get-UntrackedCount([string]$GitPath){$text=(Invoke-RepoGit $GitPath @('ls-files','--others','--exclude-standard')).text;if([string]::IsNullOrWhiteSpace($text)){0}else{@($text -split "`r?`n"|Where-Object{-not[string]::IsNullOrWhiteSpace($_)}).Count}}

$coreRoot=Find-AndroidBuildRoot $AndroidBuildRoot
$tool=$null
try{
  $tool=Resolve-SyncTool $coreRoot;$git=[string]$tool.git;$coreVersion=[string]$tool.core
  if(($env:GITHUB_ACTIONS -eq 'true' -or $env:CI -eq 'true') -and -not$AllowCiMutation){$head=(Invoke-RepoGit $git @('rev-parse','HEAD')).text.Trim().ToLowerInvariant();Write-SyncLine "WADDLE_SOURCE_SYNC=PASS mode=ci_exact_sha sha=$head mutation=false";Save-SyncState 'PASS' 'ci_exact_sha' -LocalSha $head -CoreVersion $coreVersion -GitPath $git;exit 0}
  if($env:WADDLE_DISABLE_SOURCE_SYNC -eq '1'){$head=(Invoke-RepoGit $git @('rev-parse','HEAD')).text.Trim().ToLowerInvariant();Write-SyncLine "WADDLE_SOURCE_SYNC=PASS mode=disabled sha=$head mutation=false";Save-SyncState 'PASS' 'disabled' -LocalSha $head -CoreVersion $coreVersion -GitPath $git;exit 0}

  Acquire-SyncLock
  Invoke-RepoGit $git @('config','--local','pull.ff','only')|Out-Null;Invoke-RepoGit $git @('config','--local','fetch.prune','true')|Out-Null
  if((Test-Path -LiteralPath (Join-Path $repo '.githooks') -PathType Container) -and ($InstallHooks -or $Trigger -in @('manual','start','setup','ci-publish'))){Invoke-RepoGit $git @('config','--local','core.hooksPath','.githooks')|Out-Null;Write-SyncLine 'WADDLE_SOURCE_HOOKS=PASS path=.githooks scope=repository'}

  $branchProbe=Invoke-RepoGit $git @('symbolic-ref','--quiet','--short','HEAD') -AllowFailure;$localSha=(Invoke-RepoGit $git @('rev-parse','HEAD')).text.Trim().ToLowerInvariant()
  if($branchProbe.exit_code -ne 0 -or [string]::IsNullOrWhiteSpace($branchProbe.text)){Write-SyncLine "WADDLE_SOURCE_SYNC=PASS mode=detached_exact_sha sha=$localSha";Save-SyncState 'PASS' 'detached_exact_sha' -LocalSha $localSha -CoreVersion $coreVersion -GitPath $git;exit 0}
  $branch=$branchProbe.text.Trim()
  if($TargetBranch -and -not$branch.Equals($TargetBranch,[StringComparison]::OrdinalIgnoreCase)){Write-SyncLine "WADDLE_SOURCE_SYNC=FAIL reason=branch_mismatch current=$branch target=$TargetBranch";Save-SyncState 'FAIL' 'branch_mismatch' -Branch $branch -LocalSha $localSha -CoreVersion $coreVersion -GitPath $git;exit 9}

  $remoteProbe=Invoke-RepoGit $git @('config','--get',"branch.$branch.remote") -AllowFailure;$mergeProbe=Invoke-RepoGit $git @('config','--get',"branch.$branch.merge") -AllowFailure
  $remote=if($remoteProbe.exit_code -eq 0){$remoteProbe.text.Trim()}else{''};$mergeRef=if($mergeProbe.exit_code -eq 0){$mergeProbe.text.Trim()}else{''}
  $remotes=@((Invoke-RepoGit $git @('remote')).text -split "`r?`n"|Where-Object{-not[string]::IsNullOrWhiteSpace($_)})
  if([string]::IsNullOrWhiteSpace($remote) -or $remote -eq '.'){$remote=if($remotes -contains 'androidbuild-source'){'androidbuild-source'}elseif($remotes -contains 'origin'){'origin'}elseif($remotes.Count -gt 0){[string]$remotes[0]}else{''}}
  if([string]::IsNullOrWhiteSpace($remote)){Write-SyncLine 'WADDLE_SOURCE_SYNC=WARN mode=no_remote';Save-SyncState 'WARN' 'no_remote' -Branch $branch -LocalSha $localSha -CoreVersion $coreVersion -GitPath $git;if($RequireRemote){exit 3}else{exit 0}}
  $remoteBranch=if(-not[string]::IsNullOrWhiteSpace($mergeRef)){($mergeRef -replace '^refs/heads/','')}else{$branch};if([string]::IsNullOrWhiteSpace($remoteBranch)){$remoteBranch=$branch}
  $remoteRef="refs/remotes/$remote/$remoteBranch";$shallowRepaired=$false

  $shallow=Invoke-RepoGit $git @('rev-parse','--is-shallow-repository') -AllowFailure
  if($shallow.exit_code -eq 0 -and $shallow.text.Trim().ToLowerInvariant() -eq 'true'){$unshallow=Invoke-RepoGit $git @('fetch','--unshallow','--no-tags','--prune',$remote) -AllowFailure;if($unshallow.exit_code -ne 0){Write-SyncLine "WADDLE_SOURCE_SYNC=FAIL reason=unshallow remote=$remote";Save-SyncState 'FAIL' 'unshallow_failed' -Branch $branch -Remote $remote -LocalSha $localSha -CoreVersion $coreVersion -GitPath $git;exit 11};$shallowRepaired=$true;Write-SyncLine "WADDLE_SOURCE_HISTORY=PASS mode=unshallow remote=$remote"}

  $fetch=Invoke-RepoGit $git @('fetch','--no-tags','--prune',$remote,"+refs/heads/$remoteBranch`:$remoteRef") -AllowFailure
  if($fetch.exit_code -ne 0){Write-SyncLine "WADDLE_SOURCE_SYNC=WARN mode=fetch_failed remote=$remote branch=$remoteBranch";Save-SyncState 'WARN' 'fetch_failed' -Branch $branch -Remote $remote -RemoteBranch $remoteBranch -LocalSha $localSha -ShallowRepaired $shallowRepaired -CoreVersion $coreVersion -GitPath $git;if($RequireRemote){exit 4}else{exit 0}}
  $remoteSha=(Invoke-RepoGit $git @('rev-parse',$remoteRef)).text.Trim().ToLowerInvariant()
  if($ExpectedSha){$expected=$ExpectedSha.Trim().ToLowerInvariant();if($remoteSha -ne $expected){$mode=if($Trigger -eq 'ci-publish'){'stale_ci_publish'}else{'expected_sha_mismatch'};Write-SyncLine "WADDLE_SOURCE_SYNC=PASS mode=$mode expected=$expected remote_sha=$remoteSha mutation=false";Save-SyncState 'PASS' $mode -Branch $branch -Remote $remote -RemoteBranch $remoteBranch -LocalSha $localSha -RemoteSha $remoteSha -ShallowRepaired $shallowRepaired -CoreVersion $coreVersion -GitPath $git;exit 0}}
  if($remoteProbe.exit_code -ne 0 -or $mergeProbe.exit_code -ne 0 -or [string]::IsNullOrWhiteSpace($remoteProbe.text) -or [string]::IsNullOrWhiteSpace($mergeProbe.text)){Invoke-RepoGit $git @('branch',"--set-upstream-to=$remote/$remoteBranch",$branch)|Out-Null;Write-SyncLine "WADDLE_SOURCE_TRACKING=PASS branch=$branch upstream=$remote/$remoteBranch"}

  $trackedPaths=Get-TrackedDirtyPaths $git
  if($Trigger -eq 'ci-publish' -and $localSha -eq '2520b8593f934187e63ea835e2ad3da7e25bf60f'){
    $known=@('.github/workflows/androidbuild-local-integration.yml','.github/workflows/waddle-command-center-live.yml','src/client/views/commands/commands-compact.css','src/client/views/commands/commands.html','src/client/views/commands/commands.ts')|Sort-Object
    $actual=@($trackedPaths|Sort-Object)
    $unexpected=@($actual|Where-Object{$known -notcontains $_})
    $missing=@($known|Where-Object{$actual -notcontains $_})
    if($unexpected.Count -eq 0 -and $missing.Count -eq 0 -and $actual.Count -eq $known.Count){
      Invoke-RepoGit $git (@('restore','--source=HEAD','--worktree','--')+$known)|Out-Null
      $trackedPaths=Get-TrackedDirtyPaths $git
      if($trackedPaths.Count -ne 0){throw "Historical source migration did not clean the expected tracked paths: $($trackedPaths -join ',')"}
      Write-SyncLine "WADDLE_SOURCE_MIGRATION=PASS from_sha=$localSha restored_tracked=$($known.Count) untracked_preserved=true"
    }else{
      Write-SyncLine "WADDLE_SOURCE_MIGRATION=SKIP from_sha=$localSha actual=$($actual -join ',') missing=$($missing -join ',') unexpected=$($unexpected -join ',') mutation=false"
    }
  }
  $trackedDirtyCount=$trackedPaths.Count;$untrackedCount=Get-UntrackedCount $git

  $coreSync=Get-Command Sync-AndroidBuildRepositoryBranchSafe -ErrorAction SilentlyContinue
  if($coreSync){
    $result=Sync-AndroidBuildRepositoryBranchSafe -RepoRoot $repo -Branch $branch -AndroidBuildRoot $coreRoot -Remote $remote -ExpectedSha $remoteSha -RequireRemote -SetTrackingWhenMissing
    $mode=[string]$result.mode;$status=[string]$result.status;$localSha=[string]$result.local_sha;$trackedDirtyCount=[int]$result.tracked_dirty_count;$untrackedCount=[int]$result.untracked_count;$shallowRepaired=$shallowRepaired -or [bool]$result.shallow_repaired
    if($status -eq 'BLOCKED'){$stateStatus=if($Trigger -eq 'ci-publish'){'WARN'}else{'FAIL'};Write-SyncLine "WADDLE_SOURCE_SYNC=$stateStatus mode=$mode branch=$branch tracked_dirty=$trackedDirtyCount untracked=$untrackedCount mutation=false";Save-SyncState $stateStatus $mode -Branch $branch -Remote $remote -RemoteBranch $remoteBranch -LocalSha $localSha -RemoteSha $remoteSha -TrackedDirtyCount $trackedDirtyCount -UntrackedCount $untrackedCount -ShallowRepaired $shallowRepaired -CoreVersion $coreVersion -GitPath $git;if($Trigger -eq 'ci-publish'){exit 0}else{exit 6}}
    Write-SyncLine "WADDLE_SOURCE_SYNC=$status mode=$mode branch=$branch sha=$localSha tracked_dirty=$trackedDirtyCount untracked=$untrackedCount core=$coreVersion";Save-SyncState $status $mode -Branch $branch -Remote $remote -RemoteBranch $remoteBranch -LocalSha $localSha -RemoteSha $remoteSha -TrackedDirtyCount $trackedDirtyCount -UntrackedCount $untrackedCount -ShallowRepaired $shallowRepaired -CoreVersion $coreVersion -GitPath $git;exit 0
  }

  $counts=(Invoke-RepoGit $git @('rev-list','--left-right','--count',"$remoteRef...HEAD")).text.Trim() -split '\s+';if($counts.Count -lt 2){throw 'Unable to compare local and remote history.'};$remoteOnly=[int]$counts[0];$localOnly=[int]$counts[1]
  if($remoteOnly -eq 0 -and $localOnly -eq 0){$mode=if($trackedDirtyCount -gt 0){'up_to_date_with_local_changes'}else{'up_to_date'};$status=if($trackedDirtyCount -gt 0){'WARN'}else{'PASS'};Write-SyncLine "WADDLE_SOURCE_SYNC=$status mode=$mode sha=$localSha tracked_dirty=$trackedDirtyCount untracked=$untrackedCount";Save-SyncState $status $mode -Branch $branch -Remote $remote -RemoteBranch $remoteBranch -LocalSha $localSha -RemoteSha $remoteSha -TrackedDirtyCount $trackedDirtyCount -UntrackedCount $untrackedCount -ShallowRepaired $shallowRepaired -CoreVersion $coreVersion -GitPath $git;exit 0}
  if($remoteOnly -eq 0 -and $localOnly -gt 0){Write-SyncLine "WADDLE_SOURCE_SYNC=WARN mode=local_ahead ahead=$localOnly mutation=false";Save-SyncState 'WARN' 'local_ahead' -Branch $branch -Remote $remote -RemoteBranch $remoteBranch -LocalSha $localSha -RemoteSha $remoteSha -TrackedDirtyCount $trackedDirtyCount -UntrackedCount $untrackedCount -ShallowRepaired $shallowRepaired -CoreVersion $coreVersion -GitPath $git;exit 0}
  if($remoteOnly -gt 0 -and $localOnly -gt 0){$s=if($Trigger -eq 'ci-publish'){'WARN'}else{'FAIL'};Write-SyncLine "WADDLE_SOURCE_SYNC=$s mode=diverged remote_only=$remoteOnly local_only=$localOnly mutation=false";Save-SyncState $s 'diverged' -Branch $branch -Remote $remote -RemoteBranch $remoteBranch -LocalSha $localSha -RemoteSha $remoteSha -TrackedDirtyCount $trackedDirtyCount -UntrackedCount $untrackedCount -ShallowRepaired $shallowRepaired -CoreVersion $coreVersion -GitPath $git;if($Trigger -eq 'ci-publish'){exit 0}else{exit 6}}
  if($remoteOnly -gt 0 -and $trackedDirtyCount -gt 0){$s=if($Trigger -eq 'ci-publish'){'WARN'}else{'FAIL'};Write-SyncLine "WADDLE_SOURCE_SYNC=$s mode=remote_ahead_with_local_changes behind=$remoteOnly tracked_dirty=$trackedDirtyCount untracked=$untrackedCount mutation=false";Save-SyncState $s 'remote_ahead_with_local_changes' -Branch $branch -Remote $remote -RemoteBranch $remoteBranch -LocalSha $localSha -RemoteSha $remoteSha -TrackedDirtyCount $trackedDirtyCount -UntrackedCount $untrackedCount -ShallowRepaired $shallowRepaired -CoreVersion $coreVersion -GitPath $git;if($Trigger -eq 'ci-publish'){exit 0}else{exit 7}}
  if($remoteOnly -gt 0 -and $localOnly -eq 0){$merge=Invoke-RepoGit $git @('merge','--ff-only',$remoteRef) -AllowFailure;if($merge.exit_code -ne 0){Write-SyncLine 'WADDLE_SOURCE_SYNC=FAIL mode=fast_forward_refused mutation=false';Save-SyncState 'FAIL' 'fast_forward_refused' -Branch $branch -Remote $remote -RemoteBranch $remoteBranch -LocalSha $localSha -RemoteSha $remoteSha -TrackedDirtyCount $trackedDirtyCount -UntrackedCount $untrackedCount -ShallowRepaired $shallowRepaired -CoreVersion $coreVersion -GitPath $git;exit 12};$after=(Invoke-RepoGit $git @('rev-parse','HEAD')).text.Trim().ToLowerInvariant();if($after -ne $remoteSha){throw "Fast-forward verification failed expected=$remoteSha actual=$after"};Write-SyncLine "WADDLE_SOURCE_SYNC=PASS mode=fast_forward from=$localSha to=$after commits=$remoteOnly untracked=$untrackedCount";Save-SyncState 'PASS' 'fast_forward' -Branch $branch -Remote $remote -RemoteBranch $remoteBranch -LocalSha $after -RemoteSha $remoteSha -UntrackedCount $untrackedCount -ShallowRepaired $shallowRepaired -CoreVersion $coreVersion -GitPath $git;exit 0}
  throw 'Unexpected source synchronization state.'
}catch{
  $message=$_.Exception.Message;Write-SyncLine "WADDLE_SOURCE_SYNC=FAIL reason=internal trigger=$Trigger message=$message";try{Save-SyncState 'FAIL' 'internal_error' -Message $message -CoreVersion $(if($tool){[string]$tool.core}else{''}) -GitPath $(if($tool){[string]$tool.git}else{''})}catch{};exit 8
}finally{Release-SyncLock}
