Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-WaddleGitHeadProbe {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$GitPath,
    [Parameter(Mandatory)][string]$RepoRoot
  )

  # Windows PowerShell 5.1 promotes native stderr to NativeCommandError when the
  # caller uses ErrorActionPreference=Stop. A Git ownership rejection is an
  # expected diagnostic probe here, so capture its combined stream and classify
  # by LASTEXITCODE instead of letting PowerShell terminate before recovery.
  $lines = New-Object System.Collections.Generic.List[string]
  $savedErrorActionPreference = $ErrorActionPreference
  $exitCode = 1
  try {
    $ErrorActionPreference = 'Continue'
    & $GitPath -C $RepoRoot rev-parse HEAD 2>&1 | ForEach-Object {
      $lines.Add([string]$_)
    }
    $exitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $savedErrorActionPreference
  }
  $text = ($lines -join "`n").Trim()

  [pscustomobject]@{
    exit_code = $exitCode
    text = $text
  }
}

function Get-WaddleRepositoryHead {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$AndroidBuildRoot
  )

  $repo = [IO.Path]::GetFullPath($RepoRoot)
  $git = Get-AndroidBuildGitPath $AndroidBuildRoot
  $probe = Invoke-WaddleGitHeadProbe -GitPath $git -RepoRoot $repo

  if ($probe.exit_code -eq 0) {
    $sha = [string]$probe.text
    if ([string]::IsNullOrWhiteSpace($sha)) { throw 'WADDLE_GIT_HEAD=FAIL empty_stdout' }
    Write-Host "WADDLE_GIT_HEAD=PASS sha=$sha ownership_mode=normal"
    return [pscustomobject]@{
      status = 'PASS'
      sha = $sha
      ownership_mode = 'normal'
      safe_directory_injected = $false
      injected_index = -1
      previous_count = $null
      previous_key = $null
      previous_value = $null
      safe_directory = $null
    }
  }

  $diagnostic = [string]$probe.text
  if ($diagnostic -notmatch '(?i)dubious ownership|safe\.directory') {
    throw "WADDLE_GIT_HEAD=FAIL exit=$($probe.exit_code) output=$diagnostic"
  }

  # Git itself reports the canonical path it wants trusted. This matters for mapped
  # drives: PowerShell may see V:\..., while Git canonicalizes the same repository
  # to //server/share/... . Reuse Git's exact recommendation instead of hardcoding
  # a drive letter, UNC server, username, or machine-specific global configuration.
  $safeDirectory = $null
  $recommended = [regex]::Match(
    $diagnostic,
    "(?im)git\s+config\s+--global\s+--add\s+safe\.directory\s+'([^']+)'"
  )
  if ($recommended.Success) {
    $safeDirectory = [string]$recommended.Groups[1].Value
  }
  if ([string]::IsNullOrWhiteSpace($safeDirectory)) {
    $detected = [regex]::Match($diagnostic, "(?im)repository at '([^']+)'" )
    if ($detected.Success) { $safeDirectory = [string]$detected.Groups[1].Value }
  }
  if ([string]::IsNullOrWhiteSpace($safeDirectory)) {
    $safeDirectory = $repo.Replace('\','/')
  }

  # Inject safe.directory only into this launcher PowerShell process. Child Git
  # calls made by AndroidBuild Core inherit it, but the user's global/system Git
  # config is never modified. Existing GIT_CONFIG_COUNT entries are preserved.
  $previousCount = $env:GIT_CONFIG_COUNT
  $baseCount = 0
  if ($previousCount -and $previousCount -match '^\d+$') { $baseCount = [int]$previousCount }
  $keyName = "GIT_CONFIG_KEY_$baseCount"
  $valueName = "GIT_CONFIG_VALUE_$baseCount"
  $previousKey = [Environment]::GetEnvironmentVariable($keyName,'Process')
  $previousValue = [Environment]::GetEnvironmentVariable($valueName,'Process')

  Set-Item -Path ("Env:" + $keyName) -Value 'safe.directory'
  Set-Item -Path ("Env:" + $valueName) -Value $safeDirectory
  $env:GIT_CONFIG_COUNT = [string]($baseCount + 1)

  $retry = Invoke-WaddleGitHeadProbe -GitPath $git -RepoRoot $repo
  if ($retry.exit_code -ne 0) {
    $state = [pscustomobject]@{
      safe_directory_injected = $true
      injected_index = $baseCount
      previous_count = $previousCount
      previous_key = $previousKey
      previous_value = $previousValue
    }
    Restore-WaddleGitSafeDirectoryScope -State $state
    throw "WADDLE_GIT_HEAD=FAIL ownership_retry exit=$($retry.exit_code) safe_directory=$safeDirectory output=$($retry.text)"
  }

  $sha = ([string]$retry.text).Trim()
  if ([string]::IsNullOrWhiteSpace($sha)) {
    $state = [pscustomobject]@{
      safe_directory_injected = $true
      injected_index = $baseCount
      previous_count = $previousCount
      previous_key = $previousKey
      previous_value = $previousValue
    }
    Restore-WaddleGitSafeDirectoryScope -State $state
    throw 'WADDLE_GIT_HEAD=FAIL ownership_retry_empty_stdout'
  }

  Write-Host "WADDLE_GIT_OWNERSHIP=PASS mode=process_scoped safe_directory=$safeDirectory global_config_mutation=false"
  Write-Host "WADDLE_GIT_HEAD=PASS sha=$sha ownership_mode=process_scoped"
  return [pscustomobject]@{
    status = 'PASS'
    sha = $sha
    ownership_mode = 'process_scoped'
    safe_directory_injected = $true
    injected_index = $baseCount
    previous_count = $previousCount
    previous_key = $previousKey
    previous_value = $previousValue
    safe_directory = $safeDirectory
  }
}

function Restore-WaddleGitSafeDirectoryScope {
  [CmdletBinding()]
  param($State)

  if ($null -eq $State) { return }
  $injected = $false
  try { $injected = [bool]$State.safe_directory_injected } catch {}
  if (-not $injected) { return }

  $index = [int]$State.injected_index
  $keyName = "GIT_CONFIG_KEY_$index"
  $valueName = "GIT_CONFIG_VALUE_$index"

  if ($null -eq $State.previous_key) {
    Remove-Item -Path ("Env:" + $keyName) -ErrorAction SilentlyContinue
  } else {
    Set-Item -Path ("Env:" + $keyName) -Value ([string]$State.previous_key)
  }
  if ($null -eq $State.previous_value) {
    Remove-Item -Path ("Env:" + $valueName) -ErrorAction SilentlyContinue
  } else {
    Set-Item -Path ("Env:" + $valueName) -Value ([string]$State.previous_value)
  }

  if ([string]::IsNullOrWhiteSpace([string]$State.previous_count)) {
    Remove-Item Env:GIT_CONFIG_COUNT -ErrorAction SilentlyContinue
  } else {
    $env:GIT_CONFIG_COUNT = [string]$State.previous_count
  }
  Write-Host 'WADDLE_GIT_OWNERSHIP_SCOPE=RESTORED global_config_mutation=false'
}
