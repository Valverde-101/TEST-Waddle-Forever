[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$AndroidBuildRoot,
  [Parameter(Mandatory)][string]$Repository,
  [Parameter(Mandatory)][string]$ExpectedSha,
  [string]$TargetBranch = 'dev',
  [string]$CertificationRunId = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$module=Join-Path $AndroidBuildRoot 'Core\Current\AndroidBuild.psd1'
if(-not(Test-Path -LiteralPath $module -PathType Leaf)){throw "WADDLE_PROMOTE=FAIL core_missing=$module"}
Import-Module $module -DisableNameChecking -Force -WarningAction SilentlyContinue
Enable-AndroidBuildPortableTools -AndroidBuildRoot $AndroidBuildRoot | Out-Null
$git=[string](Get-AndroidBuildGitPath -AndroidBuildRoot $AndroidBuildRoot)
if(-not(Test-Path -LiteralPath $git -PathType Leaf)){throw "WADDLE_PROMOTE=FAIL git_missing=$git"}

$canonical=Join-Path $AndroidBuildRoot 'Repositories\TEST-Waddle-Forever'
if(-not(Test-Path -LiteralPath (Join-Path $canonical '.git'))){throw "WADDLE_PROMOTE=FAIL canonical_missing=$canonical"}
$expected=$ExpectedSha.Trim().ToLowerInvariant()
if($expected -notmatch '^[0-9a-f]{40}$'){throw "WADDLE_PROMOTE=FAIL invalid_sha=$ExpectedSha"}

function Invoke-Git {
  param([string]$Repo,[string[]]$Arguments,[switch]$AllowFailure)
  $out=@(& $script:git -c "safe.directory=$Repo" -C $Repo @Arguments 2>&1)
  $code=$LASTEXITCODE
  $global:LASTEXITCODE=0
  if($code -ne 0 -and -not $AllowFailure){throw "WADDLE_PROMOTE=FAIL git exit=$code repo=$Repo args=$($Arguments -join ' ') output=$($out -join ' | ')"}
  [pscustomobject]@{code=$code;text=(($out|Out-String).Trim())}
}

function Stop-ManagedWaddle {
  $roots=@(
    ([IO.Path]::GetFullPath((Join-Path $AndroidBuildRoot 'Repositories\TEST-Waddle-Forever')).TrimEnd('\')+'\'),
    ([IO.Path]::GetFullPath((Join-Path $AndroidBuildRoot 'Previews\Waddle-Forever')).TrimEnd('\')+'\'),
    ([IO.Path]::GetFullPath((Join-Path $AndroidBuildRoot 'Certification\Waddle-Forever')).TrimEnd('\')+'\')
  )
  $killed=New-Object System.Collections.Generic.List[int]
  foreach($p in @(Get-CimInstance Win32_Process -Filter "Name='electron.exe'" -ErrorAction SilentlyContinue)){
    $cmd=[string]$p.CommandLine
    if([string]::IsNullOrWhiteSpace($cmd) -or $cmd -notmatch '[\\/]compiled[\\/]client[\\/]main\.js'){continue}
    $owned=$false
    foreach($r in $roots){if($cmd.IndexOf($r,[StringComparison]::OrdinalIgnoreCase)-ge0){$owned=$true;break}}
    if(-not$owned){continue}
    & taskkill.exe /PID ([int]$p.ProcessId) /T /F | Out-Null
    $code=$LASTEXITCODE;$global:LASTEXITCODE=0
    if($code-ne0 -and (Get-Process -Id ([int]$p.ProcessId) -ErrorAction SilentlyContinue)){throw "WADDLE_PROMOTE=FAIL stop pid=$($p.ProcessId) exit=$code"}
    $killed.Add([int]$p.ProcessId)
  }
  Write-Host "WADDLE_PROMOTE_STOP=PASS killed=$($killed.Count) pids=$($killed -join ',')"
}

function Copy-Tree {
  param([string]$Source,[string]$Destination)
  if(-not(Test-Path -LiteralPath $Source -PathType Container)){return 0}
  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  & robocopy.exe $Source $Destination /E /COPY:DAT /DCOPY:DAT /R:2 /W:1 /XJ /NFL /NDL /NJH /NJS /NP | Out-Null
  $code=$LASTEXITCODE;$global:LASTEXITCODE=0
  if($code-ge8){throw "WADDLE_PROMOTE=FAIL robocopy source=$Source destination=$Destination exit=$code"}
  return $code
}

$ref='refs/remotes/waddle-promote/'+([regex]::Replace($TargetBranch,'[^A-Za-z0-9._-]','_'))
$refspec="+refs/heads/$($TargetBranch):$ref"
& $git -c "safe.directory=$canonical" -C $canonical fetch --force --no-tags "https://github.com/$Repository.git" $refspec
if($LASTEXITCODE-ne0){throw "WADDLE_PROMOTE=FAIL fetch branch=$TargetBranch"}
$global:LASTEXITCODE=0
$remoteHead=(Invoke-Git -Repo $canonical -Arguments @('rev-parse',$ref)).text.ToLowerInvariant()
if($remoteHead-ne$expected){throw "WADDLE_PROMOTE=FAIL stale_certification expected=$expected remote_head=$remoteHead"}

# Preflight before stopping the known-good interactive game.
$trackedBefore=(Invoke-Git -Repo $canonical -Arguments @('status','--porcelain=v1','--untracked-files=no')).text
if(-not[string]::IsNullOrWhiteSpace($trackedBefore)){
  throw "WADDLE_PROMOTE=FAIL canonical_tracked_changes_present before_stop repo=$canonical status=$trackedBefore"
}

Stop-ManagedWaddle

$previewBase=Join-Path $AndroidBuildRoot 'Previews\Waddle-Forever'
# Enumerate only registered Waddle worktrees; do not recursively traverse node_modules.
$previewWorktrees=@()
$registered=(Invoke-Git -Repo $canonical -Arguments @('worktree','list','--porcelain')).text
$previewPrefix=[IO.Path]::GetFullPath($previewBase).TrimEnd('\')+'\'
foreach($line in @($registered -split "\r?\n" | Where-Object {$_ -like 'worktree *'})){
  $candidate=([string]$line.Substring(9)).Trim()
  if([string]::IsNullOrWhiteSpace($candidate)){continue}
  $full=[IO.Path]::GetFullPath($candidate)
  if(-not$full.StartsWith($previewPrefix,[StringComparison]::OrdinalIgnoreCase)){continue}
  if(-not(Test-Path -LiteralPath (Join-Path $full '.git'))){continue}
  $previewWorktrees+=Get-Item -LiteralPath $full
}
$previewWorktrees=@($previewWorktrees | Sort-Object LastWriteTimeUtc)
# Keep an independent snapshot of canonical user data before any preview is imported.
$backupBase=Join-Path $AndroidBuildRoot ('Previews\Quarantine\canonical-user-data-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss'))
if(Test-Path -LiteralPath (Join-Path $canonical 'user-data') -PathType Container){
  Copy-Tree -Source (Join-Path $canonical 'user-data') -Destination $backupBase | Out-Null
  Write-Host "WADDLE_PROMOTE_BACKUP=PASS user_data=$backupBase"
}
$migratedUserData=0
$migratedSwfCache=0
foreach($preview in $previewWorktrees){
  $userSource=Join-Path $preview.FullName 'user-data'
  if(Test-Path -LiteralPath $userSource -PathType Container){
    Copy-Tree -Source $userSource -Destination (Join-Path $canonical 'user-data') | Out-Null
    $migratedUserData++
  }
  $cacheSource=Join-Path $preview.FullName '.work\swf-analysis'
  if(Test-Path -LiteralPath $cacheSource -PathType Container){
    Copy-Tree -Source $cacheSource -Destination (Join-Path $canonical '.work\swf-analysis') | Out-Null
    $migratedSwfCache++
  }
  $previewEnv=Join-Path $preview.FullName '.env'
  $canonicalEnv=Join-Path $canonical '.env'
  if((Test-Path -LiteralPath $previewEnv -PathType Leaf) -and -not(Test-Path -LiteralPath $canonicalEnv -PathType Leaf)){
    Copy-Item -LiteralPath $previewEnv -Destination $canonicalEnv -Force
  }
}
Write-Host "WADDLE_PROMOTE_MIGRATE=PASS previews=$($previewWorktrees.Count) user_data=$migratedUserData swf_cache=$migratedSwfCache"

# Never reset the canonical checkout when it contains unpublished tracked edits.
# A stopped migration is safer than preserving a binary diff through PowerShell text.
$quarantine=Join-Path $AndroidBuildRoot ('Previews\Quarantine\canonical-dev\'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss'))
$dirty=(Invoke-Git -Repo $canonical -Arguments @('status','--porcelain=v1','--untracked-files=no')).text
if(-not[string]::IsNullOrWhiteSpace($dirty)){
  throw "WADDLE_PROMOTE=FAIL canonical_tracked_changes_present repo=$canonical status=$dirty; preserve local work before retry"
}
$untracked=(Invoke-Git -Repo $canonical -Arguments @('ls-files','--others','--exclude-standard')).text
if(-not[string]::IsNullOrWhiteSpace($untracked)){
  foreach($relative in @($untracked -split "\r?\n" | Where-Object {$_})){
    $probe=Invoke-Git -Repo $canonical -Arguments @('cat-file','-e',"$($expected):$relative") -AllowFailure
    if($probe.code-ne0){continue}
    New-Item -ItemType Directory -Force -Path $quarantine | Out-Null
    $from=Join-Path $canonical ($relative -replace '/','\')
    $to=Join-Path $quarantine ('untracked\'+($relative -replace '/','\'))
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $to) | Out-Null
    Move-Item -LiteralPath $from -Destination $to -Force
    Write-Host "WADDLE_PROMOTE_QUARANTINE=WARN untracked_collision=$relative"
  }
}

Invoke-Git -Repo $canonical -Arguments @('checkout','-B',$TargetBranch,$expected) | Out-Null
Invoke-Git -Repo $canonical -Arguments @('reset','--hard',$expected) | Out-Null
$actual=(Invoke-Git -Repo $canonical -Arguments @('rev-parse','HEAD')).text.ToLowerInvariant()
$branch=(Invoke-Git -Repo $canonical -Arguments @('symbolic-ref','--quiet','--short','HEAD')).text
if($actual-ne$expected -or $branch-ne$TargetBranch){throw "WADDLE_PROMOTE=FAIL canonical_head branch=$branch actual=$actual expected=$expected"}

# Retain every prior preview and its state until the user has tested canonical dev.
# Deletion/cleanup is a separate explicit post-acceptance operation.
$removed=0
Write-Host "WADDLE_PROMOTE_PREVIEW_RETENTION=PASS retained=$($previewWorktrees.Count) cleanup=deferred_until_user_acceptance"
$fallbackPreview=@($previewWorktrees | Where-Object { $_.FullName -match '(?i)halloween-party-2015' } | Select-Object -Last 1)
if($fallbackPreview.Count -eq 0 -and $previewWorktrees.Count -gt 0){$fallbackPreview=@($previewWorktrees | Select-Object -Last 1)}
$start=Join-Path $canonical '.github\scripts\waddle-start.ps1'
if(-not(Test-Path -LiteralPath $start -PathType Leaf)){throw "WADDLE_PROMOTE=FAIL start_missing=$start"}
try {
  $tracking=$env:RUNNER_TRACKING_ID
  try{
    Remove-Item Env:\RUNNER_TRACKING_ID -ErrorAction SilentlyContinue
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $start -AndroidBuildRoot $AndroidBuildRoot
    $code=$LASTEXITCODE;$global:LASTEXITCODE=0
  }finally{
    if([string]::IsNullOrEmpty($tracking)){Remove-Item Env:\RUNNER_TRACKING_ID -ErrorAction SilentlyContinue}else{$env:RUNNER_TRACKING_ID=$tracking}
  }
  if($code-ne0){throw "WADDLE_PROMOTE=FAIL start_exit=$code"}
  
  $runtimePath=Join-Path $canonical '.work\state\waddle-client.json'
  if(-not(Test-Path -LiteralPath $runtimePath -PathType Leaf)){throw "WADDLE_PROMOTE=FAIL runtime_state_missing=$runtimePath"}
  $runtime=Get-Content -LiteralPath $runtimePath -Raw | ConvertFrom-Json
  if([string]$runtime.status-ne'RUNNING'){throw "WADDLE_PROMOTE=FAIL runtime_status=$($runtime.status)"}
  $runtimeSha=([string]$runtime.source_sha).Trim().ToLowerInvariant()
  if($runtimeSha-ne$expected){throw "WADDLE_PROMOTE=FAIL runtime_sha=$runtimeSha expected=$expected"}
  if(-not(Get-Process -Id ([int]$runtime.pid) -ErrorAction SilentlyContinue)){throw "WADDLE_PROMOTE=FAIL runtime_pid=$($runtime.pid)"}
  
  
} catch {
  $primaryFailure=[string]$_
  if($fallbackPreview.Count -gt 0){
    $oldStart=Join-Path $fallbackPreview[0].FullName '.github\scripts\waddle-start.ps1'
    if(Test-Path -LiteralPath $oldStart -PathType Leaf){
      try {
        $tracking=$env:RUNNER_TRACKING_ID
        try {
          Remove-Item Env:\RUNNER_TRACKING_ID -ErrorAction SilentlyContinue
          & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $oldStart -AndroidBuildRoot $AndroidBuildRoot | Out-Host
          $fallbackCode=$LASTEXITCODE;$global:LASTEXITCODE=0
        } finally {
          if([string]::IsNullOrEmpty($tracking)){Remove-Item Env:\RUNNER_TRACKING_ID -ErrorAction SilentlyContinue}else{$env:RUNNER_TRACKING_ID=$tracking}
        }
        Write-Host "WADDLE_PROMOTE_FALLBACK=ATTEMPTED preview=$($fallbackPreview[0].FullName) exit=$fallbackCode"
      } catch {
        Write-Host "WADDLE_PROMOTE_FALLBACK=FAIL preview=$($fallbackPreview[0].FullName) error=$($_.Exception.Message)"
      }
    }
  }
  throw "WADDLE_PROMOTE=FAIL canonical_launch_or_verification error=$primaryFailure"
}
$state=[ordered]@{
  schema='waddle-canonical-promotion/v1'
  status='PASS'
  repository=$Repository
  branch=$TargetBranch
  source_sha=$expected
  certification_run_id=$CertificationRunId
  canonical_repo=$canonical
  preview_worktrees_removed=0
  preview_worktrees_retained=$previewWorktrees.Count
  pending_user_acceptance=$true
  migrated_user_data=$migratedUserData
  migrated_swf_cache=$migratedSwfCache
  runtime_pid=[int]$runtime.pid
  runtime_status='RUNNING'
  promoted_utc=[DateTime]::UtcNow.ToString('o')
}
$state | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $canonical '.work\state\waddle-canonical-promotion.json') -Encoding UTF8
Write-Host "WADDLE_PROMOTE=PASS mode=canonical_dev branch=$TargetBranch sha=$expected repo=$canonical previews_retained=$($previewWorktrees.Count) user_data_migrated=$migratedUserData runtime_pid=$($runtime.pid)"
