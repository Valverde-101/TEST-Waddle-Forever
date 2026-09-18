[CmdletBinding()]
param(
  [string]$RepoRoot = $env:GITHUB_WORKSPACE,
  [string]$CanonicalRoot = 'V:\AndroidBuild\Repositories\TEST-Waddle-Forever',
  [string]$FFDecPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-Swf([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
  $stream = [IO.File]::OpenRead($Path)
  try {
    $buf = New-Object byte[] 3
    if ($stream.Read($buf,0,3) -ne 3) { return $false }
    return @('FWS','CWS','ZWS') -contains [Text.Encoding]::ASCII.GetString($buf)
  } finally { $stream.Dispose() }
}

function Resolve-FFDec([string]$Explicit) {
  if ($Explicit -and (Test-Path -LiteralPath $Explicit -PathType Leaf)) { return (Resolve-Path -LiteralPath $Explicit).Path }
  foreach ($candidate in @($env:FFDEC_PATH,$env:WADDLE_FFDEC)) {
    if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return (Resolve-Path -LiteralPath $candidate).Path }
  }
  $root = 'V:\AndroidBuild\Tools\FFDec'
  if (Test-Path -LiteralPath $root -PathType Container) {
    $exe = Get-ChildItem -LiteralPath $root -Filter 'ffdec-cli.exe' -File -Recurse -ErrorAction SilentlyContinue |
      Sort-Object FullName -Descending | Select-Object -First 1
    if ($exe) { return $exe.FullName }
  }
  throw 'WADDLE_PARTY2015_PROTOCOL=FAIL ffdec_missing'
}

function Stop-FFDecTree($Process) {
  if ($null -eq $Process) { return }
  try {
    & taskkill.exe /PID $Process.Id /T /F 2>$null | Out-Null
  } catch {
    try { Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue } catch {}
  }
}

function Export-Scripts([string]$FFDec,[string]$Swf,[string]$SafeName,[string]$WorkRoot) {
  $out = Join-Path $WorkRoot ($SafeName + '-scripts')
  $stdout = Join-Path $WorkRoot ($SafeName + '.stdout.txt')
  $stderr = Join-Path $WorkRoot ($SafeName + '.stderr.txt')
  $args = @('-cli','-onerror','ignore','-exportTimeout','60','-exportFileTimeout','20','-export','script',('"' + $out + '"'),('"' + $Swf + '"'))
  $maxAttempts = 2

  for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
    if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Recurse -Force -ErrorAction SilentlyContinue }
    foreach ($logPath in @($stdout,$stderr)) {
      if (Test-Path -LiteralPath $logPath) { Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue }
    }
    New-Item -ItemType Directory -Force -Path $out | Out-Null

    $proc = $null
    try {
      $proc = Start-Process -FilePath $FFDec -ArgumentList $args -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -WindowStyle Hidden
      if (-not $proc.WaitForExit(90000)) {
        Stop-FFDecTree $proc
        if ($attempt -lt $maxAttempts) {
          Write-Host "WADDLE_PARTY2015_PROTOCOL_FFDEC=RETRY reason=timeout attempt=$attempt next=$($attempt + 1) swf=$Swf"
          Start-Sleep -Seconds 2
          continue
        }
        throw "WADDLE_PARTY2015_PROTOCOL=FAIL ffdec_timeout attempts=$maxAttempts swf=$Swf"
      }

      $proc.Refresh()
      $exitText = [string]$proc.ExitCode
      if (-not [string]::IsNullOrWhiteSpace($exitText) -and [int]$exitText -ne 0) {
        if ($attempt -lt $maxAttempts) {
          Write-Host "WADDLE_PARTY2015_PROTOCOL_FFDEC=RETRY reason=exit code=$exitText attempt=$attempt next=$($attempt + 1) swf=$Swf"
          Start-Sleep -Seconds 2
          continue
        }
        throw "WADDLE_PARTY2015_PROTOCOL=FAIL ffdec_exit=$exitText attempts=$maxAttempts swf=$Swf"
      }

      $files = @(Get-ChildItem -LiteralPath $out -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in @('.as','.txt') } | Sort-Object FullName)
      $chunks = @()
      $entries = @()
      foreach ($file in $files) {
        $body = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
        if (-not [string]::IsNullOrWhiteSpace($body)) {
          $chunks += $body
          $entries += [pscustomobject]@{
            path = $file.FullName.Substring($out.Length).TrimStart('\')
            text = [string]$body
          }
        }
      }
      return [pscustomobject]@{ files=$files.Count; text=($chunks -join "`n`n"); entries=$entries; exit=$exitText; attempts=$attempt }
    } finally {
      if ($null -ne $proc -and -not $proc.HasExited) { Stop-FFDecTree $proc }
    }
  }

  throw "WADDLE_PARTY2015_PROTOCOL=FAIL ffdec_retry_exhausted swf=$Swf"
}

function Add-Evidence(
  [string]$Text,
  [System.Collections.Generic.HashSet[string]]$Pairs,
  [System.Collections.Generic.HashSet[string]]$Packets,
  [System.Collections.Generic.HashSet[string]]$Localizations,
  [System.Collections.Generic.HashSet[string]]$Loaders
) {
  foreach ($m in [regex]::Matches($Text,'w\.app\.p2015\.halloween(?:\.[A-Za-z0-9_]+)+')) { [void]$Localizations.Add($m.Value) }
  foreach ($m in [regex]::Matches($Text,'(?i)["'']([a-z0-9_]{1,40})#([a-z0-9_]{1,48})["'']')) { [void]$Pairs.Add($m.Groups[1].Value + '#' + $m.Groups[2].Value) }
  foreach ($m in [regex]::Matches($Text,'(?is)sendXtMessage\s*\(\s*["'']([^"'']+)["'']\s*,\s*["'']([^"'']+)["'']')) { [void]$Pairs.Add($m.Groups[1].Value.Trim() + '#' + $m.Groups[2].Value.Trim()) }
  foreach ($m in [regex]::Matches($Text,'["''](partycookie|partyservice|msgviewed|qcmsgviewed|qtaskcomplete|qtupdate|activefeatures|nxquestsettings|nxquestdata|spts)["'']',[Text.RegularExpressions.RegexOptions]::IgnoreCase)) { [void]$Packets.Add($m.Groups[1].Value.ToLowerInvariant()) }
  foreach ($m in [regex]::Matches($Text,'(?i)(?:close_ups/|content/|music/|membership/)[A-Za-z0-9_./-]+\.swf')) { [void]$Loaders.Add($m.Value.Replace('\\','/')) }
}

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$repoPartyRoot = Join-Path $repo 'media\default\party2015'
$partyRoot = $null
if (Test-Path -LiteralPath $repoPartyRoot -PathType Container) {
  $partyRoot = $repoPartyRoot
} elseif ($CanonicalRoot -and (Test-Path -LiteralPath $CanonicalRoot -PathType Container)) {
  $candidate = Join-Path (Resolve-Path -LiteralPath $CanonicalRoot).Path 'media\default\party2015'
  if (Test-Path -LiteralPath $candidate -PathType Container) { $partyRoot = $candidate }
}
if (-not $partyRoot) { throw 'WADDLE_PARTY2015_PROTOCOL=FAIL party_root_missing' }
$ffdec = Resolve-FFDec $FFDecPath

$interactionCore = @(
  @{ role='client-interface-2015'; path='client\ClientInterface-HalloweenParty2015.swf' },
  @{ role='quest-interface-2015'; path='close_ups\Close_upsQuest_interface-HalloweenParty2015.swf' },
  @{ role='features-2015'; path='content\ContentFeatures-HalloweenParty2015.swf' },
  @{ role='party-icon-2015'; path='content\ContentParty_icon-HalloweenParty2015.swf' },
  @{ role='quest-communicator'; path='client\QuestCommunicator.swf' },
  @{ role='robot-avatar'; path='avatar\PenguinRobot.swf' }
)

$robotQuestRooms = @(
  @{ role='robot-room-shack'; path='rooms\Hallo15_shack.swf' },
  @{ role='robot-room-dock'; path='rooms\Hallo15_dock.swf' },
  @{ role='robot-room-forest'; path='rooms\Hallo15_forest.swf' },
  @{ role='robot-room-village'; path='rooms\Hallo15_village.swf' },
  @{ role='robot-room-cove'; path='rooms\Hallo15_cove.swf' },
  @{ role='robot-room-beach'; path='rooms\Hallo15_beach.swf' },
  @{ role='robot-room-forts'; path='rooms\Hallo15_forts.swf' },
  @{ role='robot-room-plaza'; path='rooms\Hallo15_plaza.swf' }
)

$compatibilityTargets = @(
  @{ role='compat-map-2310'; path='content\map.swf' }
)

$targets = @($interactionCore) + @($robotQuestRooms)
foreach ($dialogue in @(Get-ChildItem -LiteralPath (Join-Path $partyRoot 'close_ups') -Filter 'Hallo15_dialogue_*.swf' -File | Sort-Object Name)) {
  $targets += @{ role=('dialogue-' + ([IO.Path]::GetFileNameWithoutExtension($dialogue.Name) -replace '^Hallo15_dialogue_','').ToLowerInvariant()); path=('close_ups\' + $dialogue.Name) }
}
foreach ($i in 0..8) { $targets += @{ role="tiles-$i"; path="close_ups\Close_upsTiles_minigame$i-HalloweenParty2015.swf" } }

$dialogueCount = @($targets | Where-Object { $_.role -like 'dialogue-*' }).Count
if ($dialogueCount -ne 34) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL dialogue_targets=$dialogueCount expected=34" }
$expectedRewardDialogues = @('dialogue-gary_congrats','dialogue-aa_congrats','dialogue-rh_congrats','dialogue-cad_congrats','dialogue-dot_congrats','dialogue-sen_congrats','dialogue-ph_congrats','dialogue-rook_congrats')
$rewardDialogueRoles = @($targets | Where-Object { $_.role -in $expectedRewardDialogues } | ForEach-Object { [string]$_.role })
if ($rewardDialogueRoles.Count -ne 8) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL reward_dialogues=$($rewardDialogueRoles.Count) expected=8" }
foreach ($role in $expectedRewardDialogues) {
  if ($role -notin $rewardDialogueRoles) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL reward_dialogue_missing=$role" }
}
if ($targets.Count -ne 57) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL target_count=$($targets.Count) expected=57" }

$work = Join-Path $repo '.work\halloween2015-protocol'
if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
New-Item -ItemType Directory -Force -Path $work | Out-Null
$pairs = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$packets = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$localizations = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
$loaders = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$compatibilityLoaders = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$reports = @()
$compatibilityReports = @()
$scripted = 0
$coreScripted = 0
$robotRoomScripted = 0
$compatibilityScripted = 0
$interactionText = ''
$robotRoomText = ''
$compatibilityText = ''
$requiredPartyMethods = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
$requiredPartyConstants = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
$soloRoomEvidence = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$coffeeSecretEntryEvidence = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$schoolDoorEvidence = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$finaleRoomEvidence = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

function Write-FunctionWindow([string]$Text,[string]$Role,[string]$FunctionName) {
  $lines = @($Text -split "`r?`n")
  for ($i=0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -notmatch ("(?i)^\s*(?:static\s+)?function\s+" + [regex]::Escape($FunctionName) + "\s*\(")) { continue }
    $end = [Math]::Min($lines.Count - 1,$i + 45)
    $window = [regex]::Replace(($lines[$i..$end] -join ' '),'\s+',' ').Trim()
    if ($window.Length -gt 3500) { $window = $window.Substring(0,3500) }
    Write-Host "WADDLE_PARTY2015_FUNCTION_WINDOW role=$Role function=$FunctionName text=$window"
    return
  }
  Write-Host "WADDLE_PARTY2015_FUNCTION_WINDOW role=$Role function=$FunctionName text=MISSING"
}

function Add-HalloweenRoomRuntimeContract($Evidence,[string]$Role) {
  foreach ($entry in @($Evidence.entries)) {
    $body = [string]$entry.text
    if ($body -notmatch '(?i)class\s+com\.clubpenguin\.world\.rooms2015\.october\.') { continue }

    foreach ($match in @([regex]::Matches($body,'(?i)(?:_currentParty|BaseParty\.CURRENT_PARTY|CURRENT_PARTY)\.([A-Za-z_][A-Za-z0-9_]*)\s*\('))) {
      [void]$requiredPartyMethods.Add([string]$match.Groups[1].Value)
    }
    foreach ($match in @([regex]::Matches($body,'(?i)\.CONSTANTS\.([A-Z][A-Z0-9_]*)'))) {
      [void]$requiredPartyConstants.Add(([string]$match.Groups[1].Value).ToUpperInvariant())
    }
    foreach ($line in @($body -split '\r?\n' | Where-Object { $_ -match '(?i)(partysolo1|party1_mc|enterCave|sendJoinRoom)' } | ForEach-Object { ($_ -replace '\s+',' ').Trim() } | Where-Object { $_.Length -gt 0 } | Select-Object -Unique -First 80)) {
      $safeLine = if ($line.Length -gt 700) { $line.Substring(0,700) } else { $line }
      [void]$soloRoomEvidence.Add("$Role::$safeLine")
    }

    if (($Role -match '(?i)coffee' -or $body -match '(?i)class\s+com\.clubpenguin\.world\.rooms2015\.october\.Coffee') -and
        $body -match '(?i)party1_mc' -and $body -match '(?i)enterCave') {
      [void]$coffeeSecretEntryEvidence.Add("$Role::party1_mc->enterCave")
    }
    if (($Role -match '(?i)robot-room-shack' -or $body -match '(?i)class\s+com\.clubpenguin\.world\.rooms2015\.october\.Shack') -and
        $body -match '(?i)triggers_mc\.school_mc' -and
        $body -match '(?i)(?:exit|sendJoinRoom)[^\r\n]{0,160}["'']school["'']') {
      [void]$schoolDoorEvidence.Add("$Role::shack->school")
    }
    if ($Role -match '(?i)partysolo1' -and
        $body -match '(?i)PENULTIMATE_TASK_ID\s*=\s*8' -and
        $body -match '(?i)HERBOT_DEFEATED_TASK_ID\s*=\s*9' -and
        $body -match '(?i)loadMiniGame\s*\(' -and
        $body -match '(?i)taskCompleteRoomUpdate\s*\(' -and
        $body -match '(?i)showClassDialog6\s*\(' -and
        $body -match '(?i)showClassDialog7\s*\(') {
      [void]$finaleRoomEvidence.Add("$Role::task8-minigame->task9-defeat->room-powerdown->dialog6->dialog7")
    }
  }
}

foreach ($target in $targets) {
  $swf = Join-Path $partyRoot ([string]$target.path)
  if (-not (Test-Swf $swf)) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL invalid_target role=$($target.role) path=$swf" }
  $safe = ([string]$target.role -replace '[^A-Za-z0-9_.-]','_')
  $evidence = Export-Scripts -FFDec $ffdec -Swf $swf -SafeName $safe -WorkRoot $work
  $text = [string]$evidence.text
  if ($evidence.files -gt 0) { $scripted++ }
  if (@($interactionCore | Where-Object { $_.role -eq $target.role }).Count -gt 0) {
    if ($evidence.files -gt 0) { $coreScripted++ }
    $interactionText += "`n" + $text
  }
  if (@($robotQuestRooms | Where-Object { $_.role -eq $target.role }).Count -gt 0) {
    Add-HalloweenRoomRuntimeContract -Evidence $evidence -Role ([string]$target.role)
    Write-FunctionWindow -Text $text -Role ([string]$target.role) -FunctionName 'taskCompleteRoomUpdate'
    if ($evidence.files -gt 0) { $robotRoomScripted++ }
    $robotRoomText += "`n" + $text
    $candidateLines = @($text -split "`r?`n" | Where-Object { $_ -match '(?i)(MouseEvent|CLICK|showContent|dialogue|quest|robot|bot|tiles_minigame|item|inventory|qtaskcomplete|qtupdate|party)' } | ForEach-Object { ($_ -replace '\s+',' ').Trim() } | Where-Object { $_.Length -gt 0 } | Select-Object -Unique -First 80)
    foreach ($line in $candidateLines) {
      $safeLine = if ($line.Length -gt 420) { $line.Substring(0,420) } else { $line }
      Write-Host "WADDLE_PARTY2015_ROBOT_ROOM_EVIDENCE role=$($target.role) line=$safeLine"
    }
    $criticalRoomLines = @($text -split "`r?`n" | Where-Object { $_ -match '(?i)(class com\\.clubpenguin\\.world\\.rooms2015\\.october|partysolo1|party1|party7|sendJoinRoom|triggerFunction|QUEST_TASK_ID|pickupItem|collectedItem|showRobotInstructionsPopup|displayItemPickupInstructions|loadMiniGame|taskCompleteRoomUpdate)' } | ForEach-Object { ($_ -replace '\\s+',' ').Trim() } | Where-Object { $_.Length -gt 0 } | Select-Object -Unique -First 160)
    foreach ($line in $criticalRoomLines) {
      $safeLine = if ($line.Length -gt 700) { $line.Substring(0,700) } else { $line }
      Write-Host "WADDLE_PARTY2015_ROBOT_ROOM_CRITICAL role=$($target.role) line=$safeLine"
    }
  }
  if ([string]$target.role -like 'tiles-*') {
    $tileLines = @($text -split "`r?`n" | Where-Object { $_ -match '(?i)(qtaskcomplete|sendTaskComplete|partyCookie|taskCompleteRoomUpdate|closeContent|CURRENT_PARTY|getCurrentParty|QUEST_TASK_ID|questTask|taskIndex|send\()' } | ForEach-Object { ($_ -replace '\\s+',' ').Trim() } | Where-Object { $_.Length -gt 0 } | Select-Object -Unique -First 200)
    foreach ($line in $tileLines) {
      $safeLine = if ($line.Length -gt 700) { $line.Substring(0,700) } else { $line }
      Write-Host "WADDLE_PARTY2015_TILE_CRITICAL role=$($target.role) line=$safeLine"
    }
  }
  if ([string]$target.role -match '^dialogue-(gary|aa|rh|cad|dot|sen|ph|rook)_congrats$') {
    if ($evidence.files -lt 1) {
      throw "WADDLE_PARTY2015_PROTOCOL=FAIL reward_dialogue_unscripted role=$($target.role)"
    }
    $rewardLines = @($text -split "`r?`n" | Where-Object { $_ -match '(?i)(inventory|item|reward|unlock|buy|claim|quest|task|closeContent|onRelease|showContent|partyCookie)' } | ForEach-Object { ($_ -replace '\\s+',' ').Trim() } | Where-Object { $_.Length -gt 0 } | Select-Object -Unique -First 120)
    Write-Host "WADDLE_PARTY2015_REWARD_DIALOGUE=ANALYZED role=$($target.role) scripts=$($evidence.files) evidence_lines=$($rewardLines.Count)"
    foreach ($line in $rewardLines) {
      $safeLine = if ($line.Length -gt 700) { $line.Substring(0,700) } else { $line }
      Write-Host "WADDLE_PARTY2015_REWARD_EVIDENCE role=$($target.role) line=$safeLine"
    }
  }
  Add-Evidence -Text $text -Pairs $pairs -Packets $packets -Localizations $localizations -Loaders $loaders
  $reports += [pscustomobject]@{ role=[string]$target.role; file=[string]$target.path; bytes=[int64](Get-Item -LiteralPath $swf).Length; scriptFiles=[int]$evidence.files; ffdecExit=[string]$evidence.exit; ffdecAttempts=[int]$evidence.attempts }
  Write-Host "WADDLE_PARTY2015_PROTOCOL_FILE=PASS role=$($target.role) bytes=$((Get-Item -LiteralPath $swf).Length) script_files=$($evidence.files) ffdec_exit=$($evidence.exit) ffdec_attempts=$($evidence.attempts)"
}


# Scan every preserved Halloween room for the client-local pickup/portal contracts.
# These calls never reach the server until the party runtime turns them into the
# appropriate local state or room join, so this evidence is essential for root
# cause analysis when an object is visible but clicking it appears to do nothing.
$robotRoomPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($entry in $robotQuestRooms) { [void]$robotRoomPaths.Add(([string]$entry.path).Replace('/','\')) }
$roomDir = Join-Path $partyRoot 'rooms'
foreach ($roomFile in @(Get-ChildItem -LiteralPath $roomDir -Filter '*.swf' -File | Sort-Object Name)) {
  $relativeRoomPath = ('rooms\' + $roomFile.Name)
  if ($robotRoomPaths.Contains($relativeRoomPath)) { continue }
  $safe = 'room-scan-' + ([IO.Path]::GetFileNameWithoutExtension($roomFile.Name) -replace '[^A-Za-z0-9_.-]','_')
  $evidence = Export-Scripts -FFDec $ffdec -Swf $roomFile.FullName -SafeName $safe -WorkRoot $work
  $text = [string]$evidence.text
  Add-HalloweenRoomRuntimeContract -Evidence $evidence -Role $safe
  if ($safe -eq 'room-scan-Hallo15_partysolo1') {
    Write-FunctionWindow -Text $text -Role $safe -FunctionName 'taskCompleteRoomUpdate'
    Write-FunctionWindow -Text $text -Role $safe -FunctionName 'showClassDialog6'
    Write-FunctionWindow -Text $text -Role $safe -FunctionName 'showClassDialog7'
  }
  if ($text -notmatch '(?i)(pickupItem|itemCollectRelease|collectedItem|partysolo1|party7|sendJoinRoom|QUEST_TASK_ID)') { continue }
  $roomLines = @($text -split "`r?`n" | Where-Object { $_ -match '(?i)(class com\.clubpenguin\.world\.rooms2015\.october|QUEST_TASK_ID|PENULTIMATE_TASK_ID|HERBOT_DEFEATED_TASK_ID|pickupItem|itemCollectRelease|collectedItem|displayItemPickupInstructions|partysolo1|party1_mc|party7|enterCave|sendTaskComplete|hasPlayerCompletedTask|halloHerbertGame|taskCompleteRoomUpdate|showClassDialog6|showClassDialog7|HERBERT_GETAWAY|GARY_FINAL|sendJoinRoom|triggerFunction)' } | ForEach-Object { ($_ -replace '\s+',' ').Trim() } | Where-Object { $_.Length -gt 0 } | Select-Object -Unique -First 220)
  foreach ($line in $roomLines) {
    $safeLine = if ($line.Length -gt 700) { $line.Substring(0,700) } else { $line }
    Write-Host "WADDLE_PARTY2015_ROOM_INTERACTION role=$safe line=$safeLine"
  }
}


# Derive the complete direct CURRENT_PARTY API used by the preserved Halloween
# client and prove the generated live runtime implements it. This prevents
# visible-but-dead room objects from returning when a future donor/runtime is
# swapped without matching the room contract.
$liveRuntimePath = Join-Path $partyRoot 'content\party-runtime-2015.swf'
if (-not (Test-Swf $liveRuntimePath)) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL live_runtime_invalid=$liveRuntimePath" }
$liveRuntimeEvidence = Export-Scripts -FFDec $ffdec -Swf $liveRuntimePath -SafeName 'live-runtime-contract' -WorkRoot $work
$liveRuntimeText = [string]$liveRuntimeEvidence.text
$runtimeMethods = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
foreach ($match in @([regex]::Matches($liveRuntimeText,'(?i)static\s+function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\('))) {
  [void]$runtimeMethods.Add([string]$match.Groups[1].Value)
}
$runtimeConstants = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
foreach ($match in @([regex]::Matches($liveRuntimeText,'(?i)\.CONSTANTS\.([A-Z][A-Z0-9_]*)'))) {
  [void]$runtimeConstants.Add(([string]$match.Groups[1].Value).ToUpperInvariant())
}
$robotRampageScareConstants = @('COFFEE_CUP','SPELLING_TEST','PINK_FLAMINGO','INSECTS','UGLY_SWEATER','BEARD_TRIMMER','UFO','CLOWN')
foreach ($constant in $robotRampageScareConstants) {
  if (-not $requiredPartyConstants.Contains($constant)) {
    throw "WADDLE_PARTY2015_PROTOCOL=FAIL robot_rampage_contract_missing_constant=$constant"
  }
}
$finaleContentConstants = @('HERBERT_MONOLOGUE','HERBERT_MONOLOGUE2','HERBERT_BOT','HERBERT_CAGE','GARY_LAIR1','HERBERT_GETAWAY','GARY_FINAL')
foreach ($constant in $finaleContentConstants) {
  if (-not $requiredPartyConstants.Contains($constant)) {
    throw "WADDLE_PARTY2015_PROTOCOL=FAIL halloween_finale_contract_missing_constant=$constant"
  }
}
foreach ($method in @('getQuestVOByIndex','showRobotInstructionsPopup','loadMiniGame','displayItemPickupInstructions')) {
  if (-not $requiredPartyMethods.Contains($method)) {
    throw "WADDLE_PARTY2015_PROTOCOL=FAIL robot_rampage_contract_missing_method=$method"
  }
}

foreach ($method in @('getCompletionDialogue','getCompletedTaskIndex','finishMiniGamePresentation','gameCompleted')) {
  if (-not $runtimeMethods.Contains($method)) {
    throw "WADDLE_PARTY2015_PROTOCOL=FAIL completion_runtime_method_missing=$method"
  }
}
foreach ($dialoguePath in @(
  'w.app.p2015.halloween.dialogue_Gary_congrats',
  'w.app.p2015.halloween.dialogue_AA_congrats',
  'w.app.p2015.halloween.dialogue_RH_congrats',
  'w.app.p2015.halloween.dialogue_Cad_congrats',
  'w.app.p2015.halloween.dialogue_Dot_congrats',
  'w.app.p2015.halloween.dialogue_Sen_congrats',
  'w.app.p2015.halloween.dialogue_PH_congrats',
  'w.app.p2015.halloween.dialogue_Rook_congrats'
)) {
  if (-not $liveRuntimeText.Contains($dialoguePath)) {
    throw "WADDLE_PARTY2015_PROTOCOL=FAIL completion_dialogue_missing=$dialoguePath"
  }
}
foreach ($needle in @('PENULTIMATE_TASK_ID','HERBOT_DEFEATED_TASK_ID','taskCompleteRoomUpdate')) {
  if (-not $liveRuntimeText.Contains($needle)) {
    throw "WADDLE_PARTY2015_PROTOCOL=FAIL completion_lifecycle_missing=$needle"
  }
}

$missingMethods = @($requiredPartyMethods | Where-Object { -not $runtimeMethods.Contains($_) } | Sort-Object)
if ($missingMethods.Count -gt 0) {
  throw "WADDLE_PARTY2015_PROTOCOL=FAIL live_runtime_missing_methods=$($missingMethods -join ',')"
}
$missingConstants = @($requiredPartyConstants | Where-Object { -not $runtimeConstants.Contains($_) } | Sort-Object)
if ($missingConstants.Count -gt 0) {
  throw "WADDLE_PARTY2015_PROTOCOL=FAIL live_runtime_missing_constants=$($missingConstants -join ',')"
}
foreach ($method in @($requiredPartyMethods | Sort-Object)) { Write-Host "WADDLE_PARTY2015_RUNTIME_REQUIRED_METHOD=$method" }
foreach ($constant in @($requiredPartyConstants | Sort-Object)) { Write-Host "WADDLE_PARTY2015_RUNTIME_REQUIRED_CONSTANT=$constant" }
foreach ($evidenceLine in @($soloRoomEvidence | Sort-Object)) { Write-Host "WADDLE_PARTY2015_SOLO_ROOM_EVIDENCE=$evidenceLine" }
foreach ($evidenceLine in @($coffeeSecretEntryEvidence | Sort-Object)) { Write-Host "WADDLE_PARTY2015_COFFEE_SECRET_ENTRY=$evidenceLine" }
foreach ($evidenceLine in @($schoolDoorEvidence | Sort-Object)) { Write-Host "WADDLE_PARTY2015_SCHOOL_DOOR=$evidenceLine" }
foreach ($evidenceLine in @($finaleRoomEvidence | Sort-Object)) { Write-Host "WADDLE_PARTY2015_FINALE_ROOM=$evidenceLine" }
if ($soloRoomEvidence.Count -lt 1) {
  throw 'WADDLE_PARTY2015_PROTOCOL=FAIL partysolo1_entry_contract_not_found'
}
if ($coffeeSecretEntryEvidence.Count -lt 1) {
  throw 'WADDLE_PARTY2015_PROTOCOL=FAIL coffee_secret_lair_entry_not_found'
}
if ($schoolDoorEvidence.Count -lt 1) {
  throw 'WADDLE_PARTY2015_PROTOCOL=FAIL shack_school_door_contract_not_found'
}
if ($finaleRoomEvidence.Count -lt 1) {
  throw 'WADDLE_PARTY2015_PROTOCOL=FAIL finale_task8_to_task9_postdefeat_sequence_contract_not_found'
}
Write-Host "WADDLE_PARTY2015_RUNTIME_PARITY=PASS required_methods=$($requiredPartyMethods.Count) required_constants=$($requiredPartyConstants.Count) solo_room_evidence=$($soloRoomEvidence.Count) coffee_secret_entry=$($coffeeSecretEntryEvidence.Count) school_door=$($schoolDoorEvidence.Count) finale_room=$($finaleRoomEvidence.Count)"

foreach ($target in $compatibilityTargets) {
  $swf = Join-Path $partyRoot ([string]$target.path)
  if (-not (Test-Swf $swf)) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL invalid_compatibility_target role=$($target.role) path=$swf" }
  $safe = ([string]$target.role -replace '[^A-Za-z0-9_.-]','_')
  $evidence = Export-Scripts -FFDec $ffdec -Swf $swf -SafeName $safe -WorkRoot $work
  $text = [string]$evidence.text
  if ($evidence.files -gt 0) { $compatibilityScripted++ }
  $compatibilityText += "`n" + $text
  $compatPairs = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  $compatPackets = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  $compatLocalizations = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
  Add-Evidence -Text $text -Pairs $compatPairs -Packets $compatPackets -Localizations $compatLocalizations -Loaders $compatibilityLoaders
  $compatibilityReports += [pscustomobject]@{ role=[string]$target.role; file=[string]$target.path; bytes=[int64](Get-Item -LiteralPath $swf).Length; scriptFiles=[int]$evidence.files; ffdecExit=[string]$evidence.exit; ffdecAttempts=[int]$evidence.attempts }
  Write-Host "WADDLE_PARTY2015_PROTOCOL_COMPAT_FILE=ANALYZED role=$($target.role) bytes=$((Get-Item -LiteralPath $swf).Length) script_files=$($evidence.files) ffdec_exit=$($evidence.exit) ffdec_attempts=$($evidence.attempts)"
}

if ($coreScripted -lt 4) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL interaction_core_scripted=$coreScripted expected_at_least=4" }
if ($robotRoomScripted -ne 8) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL robot_room_scripted=$robotRoomScripted expected=8" }
if ($compatibilityScripted -ne 1) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL compatibility_map_scripted=$compatibilityScripted expected=1" }
if ($scripted -lt 48) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL scripted_targets=$scripted expected_at_least=48" }
if ($interactionText -notmatch '(?i)(party|quest|halloween|robot|PARTY_ICON|showContent)') { throw 'WADDLE_PARTY2015_PROTOCOL=FAIL historical_interaction_core_has_no_party_evidence' }
if ($robotRoomText -notmatch '(?i)(robot|bot|dialogue|quest|showContent|MouseEvent|CLICK|party)') { throw 'WADDLE_PARTY2015_PROTOCOL=FAIL robot_rooms_have_no_interaction_evidence' }
if ($compatibilityText -notmatch '(?i)(map|room|joinRoom|showContent|party)') { throw 'WADDLE_PARTY2015_PROTOCOL=FAIL compatibility_map_has_no_map_evidence' }
# The Halloween namespace is shared by two different contracts:
#   1) game-string localization keys (38, validated from the versioned contract), and
#   2) content crumbs such as dialogue_Gary_congrats / tiles0 used by SHELL paths.
# Static SWF evidence must not conflate those sets. Doing so made legitimate runtime
# additions change the "localization" count and produced false protocol failures.
$localizationContractPath = Join-Path $partyRoot 'game_configs\halloween2015_dialogue_strings.json'
if (-not (Test-Path -LiteralPath $localizationContractPath -PathType Leaf)) {
  throw "WADDLE_PARTY2015_PROTOCOL=FAIL localization_contract_missing=$localizationContractPath"
}
$localizationContract = Get-Content -LiteralPath $localizationContractPath -Raw | ConvertFrom-Json
if ($null -eq $localizationContract.strings) {
  throw 'WADDLE_PARTY2015_PROTOCOL=FAIL localization_contract_strings_missing'
}
$expectedLocalizationKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
foreach ($property in @($localizationContract.strings.PSObject.Properties)) {
  [void]$expectedLocalizationKeys.Add([string]$property.Name)
}
if ($expectedLocalizationKeys.Count -ne 38 -or [int]$localizationContract.totalKeys -ne 38) {
  throw "WADDLE_PARTY2015_PROTOCOL=FAIL localization_contract_count=$($expectedLocalizationKeys.Count) declared=$($localizationContract.totalKeys) expected=38"
}

$observedLocalizationKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
$contentCrumbTokens = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
foreach ($token in $localizations) {
  if ($expectedLocalizationKeys.Contains($token)) {
    [void]$observedLocalizationKeys.Add($token)
    continue
  }
  if ($token -match '^w\.app\.p2015\.halloween\.(?:dialogue_[A-Za-z0-9_]+|tiles[0-8])

foreach ($loader in @($loaders | Sort-Object)) { Write-Host "WADDLE_PARTY2015_PROTOCOL_LOADER=$loader" }
foreach ($badLoader in @('content/party_map_note.swf','close_ups/party_map_note.swf','music/2048.swf','music/2049.swf','music/2050.swf','music/2051.swf','music/2052.swf','music/2053.swf')) {
  if ($loaders.Contains($badLoader)) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL live_runtime_mixed_loader=$badLoader" }
}

foreach ($loader in @($compatibilityLoaders | Sort-Object)) { Write-Host "WADDLE_PARTY2015_PROTOCOL_COMPAT_LOADER=$loader" }
if (-not $compatibilityLoaders.Contains('close_ups/party_map_note.swf')) {
  throw 'WADDLE_PARTY2015_PROTOCOL=FAIL compat_map_rejection_evidence_changed expected=close_ups/party_map_note.swf'
}
Write-Host 'WADDLE_PARTY2015_COMPAT_MAP=REJECTED reason=requires_missing_close_ups_party_map_note source=2310_provenance_only routed_live=false'

$worldHandlersPath = Join-Path $repo 'src\server\socket-server\world-handlers.ts'
$partyHandlerPath = Join-Path $repo 'src\server\socket-server\handlers\party.ts'
$xtHandlerPath = Join-Path $repo 'src\server\socket-server\xt-handler.ts'
$worldHandlers = [IO.File]::ReadAllText($worldHandlersPath)
$partyHandler = [IO.File]::ReadAllText($partyHandlerPath)
$xtHandler = [IO.File]::ReadAllText($xtHandlerPath)
foreach ($route in @('party#partycookie','party#msgviewed','party#qcmsgviewed','party#qtaskcomplete','party#qtupdate')) {
  if (-not $worldHandlers.Contains($route)) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL server_route_missing=$route" }
}
foreach ($token in @('getPartyServiceConfig','sendCurrentPartyCookie','partyservice','partycookie','activefeatures','qtupdate','party-task-complete','taskCount')) {
  if (-not $partyHandler.Contains($token)) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL party_handler_missing=$token" }
}
foreach ($alias in @(
  "['s%fair#fair', 's%party#partycookie']",
  "['s%fair#partycookie', 's%party#partycookie']",
  "['s%fair#msgviewed', 's%party#msgviewed']"
)) {
  if (-not $xtHandler.Contains($alias)) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL mayparty_alias_missing=$alias" }
}

$summary = [ordered]@{
  schema='waddle-modern-party-protocol/v13'; party='Halloween Party 2015'; evidence='exact-cparchives-2015-with-selector-aware-runtime-robot-room-interactions-and-rejected-2310-map';
  targetCount=$targets.Count; interactionCoreCount=$interactionCore.Count; interactionCoreScripted=$coreScripted;
  robotQuestRoomCount=$robotQuestRooms.Count; robotQuestRoomScripted=$robotRoomScripted;
  compatibilityTargetCount=$compatibilityTargets.Count; compatibilityScripted=$compatibilityScripted; compatibilityStatus='rejected';
  mayPartyNamespaceAliases=3; compatibilityLoaders=@($compatibilityLoaders | Sort-Object); dialogueCount=$dialogueCount;
  scriptedTargetCount=$scripted; pairs=@($pairs | Sort-Object); packetTokens=@($packets | Sort-Object);
  namespaceTokens=@($localizations | Sort-Object);
  localizationTokens=@($observedLocalizationKeys | Sort-Object);
  contentCrumbTokens=@($contentCrumbTokens | Sort-Object);
  localizationContractCount=$expectedLocalizationKeys.Count;
  dynamicSwfLoaders=@($loaders | Sort-Object);
  requiredPartyMethods=@($requiredPartyMethods | Sort-Object); requiredPartyConstants=@($requiredPartyConstants | Sort-Object);
  soloRoomEvidence=@($soloRoomEvidence | Sort-Object); files=$reports; compatibilityFiles=$compatibilityReports
}
$summaryPath = Join-Path $work 'summary.json'
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
foreach ($pair in @($pairs | Sort-Object)) { Write-Host "WADDLE_PARTY2015_PROTOCOL_PAIR=$pair" }
foreach ($packet in @($packets | Sort-Object)) { Write-Host "WADDLE_PARTY2015_PROTOCOL_PACKET=$packet" }
Write-Host "WADDLE_PARTY2015_PROTOCOL=PASS runtime=exact-cparchives-2015 selector_runtime=20151101 mayparty_aliases=3 compatibility_map=rejected targets=$($targets.Count) core=$($interactionCore.Count) core_scripted=$coreScripted robot_rooms=$($robotQuestRooms.Count) robot_room_scripted=$robotRoomScripted compatibility_scripted=$compatibilityScripted dialogues=34 tiles=9 scripted_targets=$scripted localization_contract=$($expectedLocalizationKeys.Count) localization_observed=$($observedLocalizationKeys.Count) content_crumbs=$($contentCrumbTokens.Count) namespace_tokens=$($localizations.Count) dynamic_loaders=$($loaders.Count) server_routes=5 ffdec_retry=true summary=$summaryPath") {
    [void]$contentCrumbTokens.Add($token)
    continue
  }
  throw "WADDLE_PARTY2015_PROTOCOL=FAIL unknown_halloween_namespace_token=$token"
}
if ($observedLocalizationKeys.Count -lt 1) {
  throw 'WADDLE_PARTY2015_PROTOCOL=FAIL no_localization_evidence_in_preserved_swfs'
}
foreach ($token in @($observedLocalizationKeys | Sort-Object)) { Write-Host "WADDLE_PARTY2015_PROTOCOL_LOCALIZATION=$token" }
foreach ($token in @($contentCrumbTokens | Sort-Object)) { Write-Host "WADDLE_PARTY2015_PROTOCOL_CONTENT_CRUMB=$token" }
Write-Host "WADDLE_PARTY2015_LOCALIZATION_EVIDENCE=PASS contract=38 observed_static=$($observedLocalizationKeys.Count) content_crumbs=$($contentCrumbTokens.Count) namespace_tokens=$($localizations.Count)"

foreach ($loader in @($loaders | Sort-Object)) { Write-Host "WADDLE_PARTY2015_PROTOCOL_LOADER=$loader" }
foreach ($badLoader in @('content/party_map_note.swf','close_ups/party_map_note.swf','music/2048.swf','music/2049.swf','music/2050.swf','music/2051.swf','music/2052.swf','music/2053.swf')) {
  if ($loaders.Contains($badLoader)) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL live_runtime_mixed_loader=$badLoader" }
}

foreach ($loader in @($compatibilityLoaders | Sort-Object)) { Write-Host "WADDLE_PARTY2015_PROTOCOL_COMPAT_LOADER=$loader" }
if (-not $compatibilityLoaders.Contains('close_ups/party_map_note.swf')) {
  throw 'WADDLE_PARTY2015_PROTOCOL=FAIL compat_map_rejection_evidence_changed expected=close_ups/party_map_note.swf'
}
Write-Host 'WADDLE_PARTY2015_COMPAT_MAP=REJECTED reason=requires_missing_close_ups_party_map_note source=2310_provenance_only routed_live=false'

$worldHandlersPath = Join-Path $repo 'src\server\socket-server\world-handlers.ts'
$partyHandlerPath = Join-Path $repo 'src\server\socket-server\handlers\party.ts'
$xtHandlerPath = Join-Path $repo 'src\server\socket-server\xt-handler.ts'
$worldHandlers = [IO.File]::ReadAllText($worldHandlersPath)
$partyHandler = [IO.File]::ReadAllText($partyHandlerPath)
$xtHandler = [IO.File]::ReadAllText($xtHandlerPath)
foreach ($route in @('party#partycookie','party#msgviewed','party#qcmsgviewed','party#qtaskcomplete','party#qtupdate')) {
  if (-not $worldHandlers.Contains($route)) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL server_route_missing=$route" }
}
foreach ($token in @('getPartyServiceConfig','sendCurrentPartyCookie','partyservice','partycookie','activefeatures','qtupdate')) {
  if (-not $partyHandler.Contains($token)) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL party_handler_missing=$token" }
}
foreach ($alias in @(
  "['s%fair#fair', 's%party#partycookie']",
  "['s%fair#partycookie', 's%party#partycookie']",
  "['s%fair#msgviewed', 's%party#msgviewed']"
)) {
  if (-not $xtHandler.Contains($alias)) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL mayparty_alias_missing=$alias" }
}

$summary = [ordered]@{
  schema='waddle-modern-party-protocol/v13'; party='Halloween Party 2015'; evidence='exact-cparchives-2015-with-selector-aware-runtime-robot-room-interactions-and-rejected-2310-map';
  targetCount=$targets.Count; interactionCoreCount=$interactionCore.Count; interactionCoreScripted=$coreScripted;
  robotQuestRoomCount=$robotQuestRooms.Count; robotQuestRoomScripted=$robotRoomScripted;
  compatibilityTargetCount=$compatibilityTargets.Count; compatibilityScripted=$compatibilityScripted; compatibilityStatus='rejected';
  mayPartyNamespaceAliases=3; compatibilityLoaders=@($compatibilityLoaders | Sort-Object); dialogueCount=$dialogueCount;
  scriptedTargetCount=$scripted; pairs=@($pairs | Sort-Object); packetTokens=@($packets | Sort-Object);
  localizationTokens=@($localizations | Sort-Object); dynamicSwfLoaders=@($loaders | Sort-Object);
  requiredPartyMethods=@($requiredPartyMethods | Sort-Object); requiredPartyConstants=@($requiredPartyConstants | Sort-Object);
  soloRoomEvidence=@($soloRoomEvidence | Sort-Object); files=$reports; compatibilityFiles=$compatibilityReports
}
$summaryPath = Join-Path $work 'summary.json'
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
foreach ($pair in @($pairs | Sort-Object)) { Write-Host "WADDLE_PARTY2015_PROTOCOL_PAIR=$pair" }
foreach ($packet in @($packets | Sort-Object)) { Write-Host "WADDLE_PARTY2015_PROTOCOL_PACKET=$packet" }
Write-Host "WADDLE_PARTY2015_PROTOCOL=PASS runtime=exact-cparchives-2015 selector_runtime=20151101 mayparty_aliases=3 compatibility_map=rejected targets=$($targets.Count) core=$($interactionCore.Count) core_scripted=$coreScripted robot_rooms=$($robotQuestRooms.Count) robot_room_scripted=$robotRoomScripted compatibility_scripted=$compatibilityScripted dialogues=34 tiles=9 scripted_targets=$scripted localization_tokens=$($localizations.Count) dynamic_loaders=$($loaders.Count) server_routes=5 ffdec_retry=true summary=$summaryPath") {
    if ($evidence.files -lt 1) {
      throw "WADDLE_PARTY2015_PROTOCOL=FAIL reward_dialogue_unscripted role=$($target.role)"
    }
    $rewardLines = @($text -split "`r?`n" | Where-Object { $_ -match '(?i)(inventory|item|reward|unlock|buy|claim|quest|task|closeContent|onRelease|showContent|partyCookie)' } | ForEach-Object { ($_ -replace '\\s+',' ').Trim() } | Where-Object { $_.Length -gt 0 } | Select-Object -Unique -First 120)
    Write-Host "WADDLE_PARTY2015_REWARD_DIALOGUE=ANALYZED role=$($target.role) scripts=$($evidence.files) evidence_lines=$($rewardLines.Count)"
    foreach ($line in $rewardLines) {
      $safeLine = if ($line.Length -gt 700) { $line.Substring(0,700) } else { $line }
      Write-Host "WADDLE_PARTY2015_REWARD_EVIDENCE role=$($target.role) line=$safeLine"
    }
  }
  Add-Evidence -Text $text -Pairs $pairs -Packets $packets -Localizations $localizations -Loaders $loaders
  $reports += [pscustomobject]@{ role=[string]$target.role; file=[string]$target.path; bytes=[int64](Get-Item -LiteralPath $swf).Length; scriptFiles=[int]$evidence.files; ffdecExit=[string]$evidence.exit; ffdecAttempts=[int]$evidence.attempts }
  Write-Host "WADDLE_PARTY2015_PROTOCOL_FILE=PASS role=$($target.role) bytes=$((Get-Item -LiteralPath $swf).Length) script_files=$($evidence.files) ffdec_exit=$($evidence.exit) ffdec_attempts=$($evidence.attempts)"
}


# Scan every preserved Halloween room for the client-local pickup/portal contracts.
# These calls never reach the server until the party runtime turns them into the
# appropriate local state or room join, so this evidence is essential for root
# cause analysis when an object is visible but clicking it appears to do nothing.
$robotRoomPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($entry in $robotQuestRooms) { [void]$robotRoomPaths.Add(([string]$entry.path).Replace('/','\')) }
$roomDir = Join-Path $partyRoot 'rooms'
foreach ($roomFile in @(Get-ChildItem -LiteralPath $roomDir -Filter '*.swf' -File | Sort-Object Name)) {
  $relativeRoomPath = ('rooms\' + $roomFile.Name)
  if ($robotRoomPaths.Contains($relativeRoomPath)) { continue }
  $safe = 'room-scan-' + ([IO.Path]::GetFileNameWithoutExtension($roomFile.Name) -replace '[^A-Za-z0-9_.-]','_')
  $evidence = Export-Scripts -FFDec $ffdec -Swf $roomFile.FullName -SafeName $safe -WorkRoot $work
  $text = [string]$evidence.text
  Add-HalloweenRoomRuntimeContract -Evidence $evidence -Role $safe
  if ($text -notmatch '(?i)(pickupItem|itemCollectRelease|collectedItem|partysolo1|party7|sendJoinRoom|QUEST_TASK_ID)') { continue }
  $roomLines = @($text -split "`r?`n" | Where-Object { $_ -match '(?i)(class com\.clubpenguin\.world\.rooms2015\.october|QUEST_TASK_ID|PENULTIMATE_TASK_ID|HERBOT_DEFEATED_TASK_ID|pickupItem|itemCollectRelease|collectedItem|displayItemPickupInstructions|partysolo1|party1_mc|party7|enterCave|sendTaskComplete|hasPlayerCompletedTask|halloHerbertGame|taskCompleteRoomUpdate|showClassDialog6|showClassDialog7|HERBERT_GETAWAY|GARY_FINAL|sendJoinRoom|triggerFunction)' } | ForEach-Object { ($_ -replace '\s+',' ').Trim() } | Where-Object { $_.Length -gt 0 } | Select-Object -Unique -First 220)
  foreach ($line in $roomLines) {
    $safeLine = if ($line.Length -gt 700) { $line.Substring(0,700) } else { $line }
    Write-Host "WADDLE_PARTY2015_ROOM_INTERACTION role=$safe line=$safeLine"
  }
}


# Derive the complete direct CURRENT_PARTY API used by the preserved Halloween
# client and prove the generated live runtime implements it. This prevents
# visible-but-dead room objects from returning when a future donor/runtime is
# swapped without matching the room contract.
$liveRuntimePath = Join-Path $partyRoot 'content\party-runtime-2015.swf'
if (-not (Test-Swf $liveRuntimePath)) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL live_runtime_invalid=$liveRuntimePath" }
$liveRuntimeEvidence = Export-Scripts -FFDec $ffdec -Swf $liveRuntimePath -SafeName 'live-runtime-contract' -WorkRoot $work
$liveRuntimeText = [string]$liveRuntimeEvidence.text
$runtimeMethods = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
foreach ($match in @([regex]::Matches($liveRuntimeText,'(?i)static\s+function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\('))) {
  [void]$runtimeMethods.Add([string]$match.Groups[1].Value)
}
$runtimeConstants = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
foreach ($match in @([regex]::Matches($liveRuntimeText,'(?i)\.CONSTANTS\.([A-Z][A-Z0-9_]*)'))) {
  [void]$runtimeConstants.Add(([string]$match.Groups[1].Value).ToUpperInvariant())
}
$robotRampageScareConstants = @('COFFEE_CUP','SPELLING_TEST','PINK_FLAMINGO','INSECTS','UGLY_SWEATER','BEARD_TRIMMER','UFO','CLOWN')
foreach ($constant in $robotRampageScareConstants) {
  if (-not $requiredPartyConstants.Contains($constant)) {
    throw "WADDLE_PARTY2015_PROTOCOL=FAIL robot_rampage_contract_missing_constant=$constant"
  }
}
$finaleContentConstants = @('HERBERT_MONOLOGUE','HERBERT_MONOLOGUE2','HERBERT_BOT','HERBERT_CAGE','GARY_LAIR1','HERBERT_GETAWAY','GARY_FINAL')
foreach ($constant in $finaleContentConstants) {
  if (-not $requiredPartyConstants.Contains($constant)) {
    throw "WADDLE_PARTY2015_PROTOCOL=FAIL halloween_finale_contract_missing_constant=$constant"
  }
}
foreach ($method in @('getQuestVOByIndex','showRobotInstructionsPopup','loadMiniGame','displayItemPickupInstructions')) {
  if (-not $requiredPartyMethods.Contains($method)) {
    throw "WADDLE_PARTY2015_PROTOCOL=FAIL robot_rampage_contract_missing_method=$method"
  }
}

foreach ($method in @('getCompletionDialogue','getCompletedTaskIndex','finishMiniGamePresentation','gameCompleted')) {
  if (-not $runtimeMethods.Contains($method)) {
    throw "WADDLE_PARTY2015_PROTOCOL=FAIL completion_runtime_method_missing=$method"
  }
}
foreach ($dialoguePath in @(
  'w.app.p2015.halloween.dialogue_Gary_congrats',
  'w.app.p2015.halloween.dialogue_AA_congrats',
  'w.app.p2015.halloween.dialogue_RH_congrats',
  'w.app.p2015.halloween.dialogue_Cad_congrats',
  'w.app.p2015.halloween.dialogue_Dot_congrats',
  'w.app.p2015.halloween.dialogue_Sen_congrats',
  'w.app.p2015.halloween.dialogue_PH_congrats',
  'w.app.p2015.halloween.dialogue_Rook_congrats'
)) {
  if (-not $liveRuntimeText.Contains($dialoguePath)) {
    throw "WADDLE_PARTY2015_PROTOCOL=FAIL completion_dialogue_missing=$dialoguePath"
  }
}
foreach ($needle in @('PENULTIMATE_TASK_ID','HERBOT_DEFEATED_TASK_ID','taskCompleteRoomUpdate')) {
  if (-not $liveRuntimeText.Contains($needle)) {
    throw "WADDLE_PARTY2015_PROTOCOL=FAIL completion_lifecycle_missing=$needle"
  }
}

$missingMethods = @($requiredPartyMethods | Where-Object { -not $runtimeMethods.Contains($_) } | Sort-Object)
if ($missingMethods.Count -gt 0) {
  throw "WADDLE_PARTY2015_PROTOCOL=FAIL live_runtime_missing_methods=$($missingMethods -join ',')"
}
$missingConstants = @($requiredPartyConstants | Where-Object { -not $runtimeConstants.Contains($_) } | Sort-Object)
if ($missingConstants.Count -gt 0) {
  throw "WADDLE_PARTY2015_PROTOCOL=FAIL live_runtime_missing_constants=$($missingConstants -join ',')"
}
foreach ($method in @($requiredPartyMethods | Sort-Object)) { Write-Host "WADDLE_PARTY2015_RUNTIME_REQUIRED_METHOD=$method" }
foreach ($constant in @($requiredPartyConstants | Sort-Object)) { Write-Host "WADDLE_PARTY2015_RUNTIME_REQUIRED_CONSTANT=$constant" }
foreach ($evidenceLine in @($soloRoomEvidence | Sort-Object)) { Write-Host "WADDLE_PARTY2015_SOLO_ROOM_EVIDENCE=$evidenceLine" }
foreach ($evidenceLine in @($coffeeSecretEntryEvidence | Sort-Object)) { Write-Host "WADDLE_PARTY2015_COFFEE_SECRET_ENTRY=$evidenceLine" }
foreach ($evidenceLine in @($schoolDoorEvidence | Sort-Object)) { Write-Host "WADDLE_PARTY2015_SCHOOL_DOOR=$evidenceLine" }
foreach ($evidenceLine in @($finaleRoomEvidence | Sort-Object)) { Write-Host "WADDLE_PARTY2015_FINALE_ROOM=$evidenceLine" }
if ($soloRoomEvidence.Count -lt 1) {
  throw 'WADDLE_PARTY2015_PROTOCOL=FAIL partysolo1_entry_contract_not_found'
}
if ($coffeeSecretEntryEvidence.Count -lt 1) {
  throw 'WADDLE_PARTY2015_PROTOCOL=FAIL coffee_secret_lair_entry_not_found'
}
if ($schoolDoorEvidence.Count -lt 1) {
  throw 'WADDLE_PARTY2015_PROTOCOL=FAIL shack_school_door_contract_not_found'
}
if ($finaleRoomEvidence.Count -lt 1) {
  throw 'WADDLE_PARTY2015_PROTOCOL=FAIL finale_task8_to_task9_postdefeat_sequence_contract_not_found'
}
Write-Host "WADDLE_PARTY2015_RUNTIME_PARITY=PASS required_methods=$($requiredPartyMethods.Count) required_constants=$($requiredPartyConstants.Count) solo_room_evidence=$($soloRoomEvidence.Count) coffee_secret_entry=$($coffeeSecretEntryEvidence.Count) school_door=$($schoolDoorEvidence.Count) finale_room=$($finaleRoomEvidence.Count)"

foreach ($target in $compatibilityTargets) {
  $swf = Join-Path $partyRoot ([string]$target.path)
  if (-not (Test-Swf $swf)) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL invalid_compatibility_target role=$($target.role) path=$swf" }
  $safe = ([string]$target.role -replace '[^A-Za-z0-9_.-]','_')
  $evidence = Export-Scripts -FFDec $ffdec -Swf $swf -SafeName $safe -WorkRoot $work
  $text = [string]$evidence.text
  if ($evidence.files -gt 0) { $compatibilityScripted++ }
  $compatibilityText += "`n" + $text
  $compatPairs = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  $compatPackets = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  $compatLocalizations = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
  Add-Evidence -Text $text -Pairs $compatPairs -Packets $compatPackets -Localizations $compatLocalizations -Loaders $compatibilityLoaders
  $compatibilityReports += [pscustomobject]@{ role=[string]$target.role; file=[string]$target.path; bytes=[int64](Get-Item -LiteralPath $swf).Length; scriptFiles=[int]$evidence.files; ffdecExit=[string]$evidence.exit; ffdecAttempts=[int]$evidence.attempts }
  Write-Host "WADDLE_PARTY2015_PROTOCOL_COMPAT_FILE=ANALYZED role=$($target.role) bytes=$((Get-Item -LiteralPath $swf).Length) script_files=$($evidence.files) ffdec_exit=$($evidence.exit) ffdec_attempts=$($evidence.attempts)"
}

if ($coreScripted -lt 4) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL interaction_core_scripted=$coreScripted expected_at_least=4" }
if ($robotRoomScripted -ne 8) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL robot_room_scripted=$robotRoomScripted expected=8" }
if ($compatibilityScripted -ne 1) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL compatibility_map_scripted=$compatibilityScripted expected=1" }
if ($scripted -lt 48) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL scripted_targets=$scripted expected_at_least=48" }
if ($interactionText -notmatch '(?i)(party|quest|halloween|robot|PARTY_ICON|showContent)') { throw 'WADDLE_PARTY2015_PROTOCOL=FAIL historical_interaction_core_has_no_party_evidence' }
if ($robotRoomText -notmatch '(?i)(robot|bot|dialogue|quest|showContent|MouseEvent|CLICK|party)') { throw 'WADDLE_PARTY2015_PROTOCOL=FAIL robot_rooms_have_no_interaction_evidence' }
if ($compatibilityText -notmatch '(?i)(map|room|joinRoom|showContent|party)') { throw 'WADDLE_PARTY2015_PROTOCOL=FAIL compatibility_map_has_no_map_evidence' }
# The Halloween namespace is shared by two different contracts:
#   1) game-string localization keys (38, validated from the versioned contract), and
#   2) content crumbs such as dialogue_Gary_congrats / tiles0 used by SHELL paths.
# Static SWF evidence must not conflate those sets. Doing so made legitimate runtime
# additions change the "localization" count and produced false protocol failures.
$localizationContractPath = Join-Path $partyRoot 'game_configs\halloween2015_dialogue_strings.json'
if (-not (Test-Path -LiteralPath $localizationContractPath -PathType Leaf)) {
  throw "WADDLE_PARTY2015_PROTOCOL=FAIL localization_contract_missing=$localizationContractPath"
}
$localizationContract = Get-Content -LiteralPath $localizationContractPath -Raw | ConvertFrom-Json
if ($null -eq $localizationContract.strings) {
  throw 'WADDLE_PARTY2015_PROTOCOL=FAIL localization_contract_strings_missing'
}
$expectedLocalizationKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
foreach ($property in @($localizationContract.strings.PSObject.Properties)) {
  [void]$expectedLocalizationKeys.Add([string]$property.Name)
}
if ($expectedLocalizationKeys.Count -ne 38 -or [int]$localizationContract.totalKeys -ne 38) {
  throw "WADDLE_PARTY2015_PROTOCOL=FAIL localization_contract_count=$($expectedLocalizationKeys.Count) declared=$($localizationContract.totalKeys) expected=38"
}

$observedLocalizationKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
$contentCrumbTokens = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
foreach ($token in $localizations) {
  if ($expectedLocalizationKeys.Contains($token)) {
    [void]$observedLocalizationKeys.Add($token)
    continue
  }
  if ($token -match '^w\.app\.p2015\.halloween\.(?:dialogue_[A-Za-z0-9_]+|tiles[0-8])

foreach ($loader in @($loaders | Sort-Object)) { Write-Host "WADDLE_PARTY2015_PROTOCOL_LOADER=$loader" }
foreach ($badLoader in @('content/party_map_note.swf','close_ups/party_map_note.swf','music/2048.swf','music/2049.swf','music/2050.swf','music/2051.swf','music/2052.swf','music/2053.swf')) {
  if ($loaders.Contains($badLoader)) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL live_runtime_mixed_loader=$badLoader" }
}

foreach ($loader in @($compatibilityLoaders | Sort-Object)) { Write-Host "WADDLE_PARTY2015_PROTOCOL_COMPAT_LOADER=$loader" }
if (-not $compatibilityLoaders.Contains('close_ups/party_map_note.swf')) {
  throw 'WADDLE_PARTY2015_PROTOCOL=FAIL compat_map_rejection_evidence_changed expected=close_ups/party_map_note.swf'
}
Write-Host 'WADDLE_PARTY2015_COMPAT_MAP=REJECTED reason=requires_missing_close_ups_party_map_note source=2310_provenance_only routed_live=false'

$worldHandlersPath = Join-Path $repo 'src\server\socket-server\world-handlers.ts'
$partyHandlerPath = Join-Path $repo 'src\server\socket-server\handlers\party.ts'
$xtHandlerPath = Join-Path $repo 'src\server\socket-server\xt-handler.ts'
$worldHandlers = [IO.File]::ReadAllText($worldHandlersPath)
$partyHandler = [IO.File]::ReadAllText($partyHandlerPath)
$xtHandler = [IO.File]::ReadAllText($xtHandlerPath)
foreach ($route in @('party#partycookie','party#msgviewed','party#qcmsgviewed','party#qtaskcomplete','party#qtupdate')) {
  if (-not $worldHandlers.Contains($route)) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL server_route_missing=$route" }
}
foreach ($token in @('getPartyServiceConfig','sendCurrentPartyCookie','partyservice','partycookie','activefeatures','qtupdate')) {
  if (-not $partyHandler.Contains($token)) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL party_handler_missing=$token" }
}
foreach ($alias in @(
  "['s%fair#fair', 's%party#partycookie']",
  "['s%fair#partycookie', 's%party#partycookie']",
  "['s%fair#msgviewed', 's%party#msgviewed']"
)) {
  if (-not $xtHandler.Contains($alias)) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL mayparty_alias_missing=$alias" }
}

$summary = [ordered]@{
  schema='waddle-modern-party-protocol/v13'; party='Halloween Party 2015'; evidence='exact-cparchives-2015-with-selector-aware-runtime-robot-room-interactions-and-rejected-2310-map';
  targetCount=$targets.Count; interactionCoreCount=$interactionCore.Count; interactionCoreScripted=$coreScripted;
  robotQuestRoomCount=$robotQuestRooms.Count; robotQuestRoomScripted=$robotRoomScripted;
  compatibilityTargetCount=$compatibilityTargets.Count; compatibilityScripted=$compatibilityScripted; compatibilityStatus='rejected';
  mayPartyNamespaceAliases=3; compatibilityLoaders=@($compatibilityLoaders | Sort-Object); dialogueCount=$dialogueCount;
  scriptedTargetCount=$scripted; pairs=@($pairs | Sort-Object); packetTokens=@($packets | Sort-Object);
  namespaceTokens=@($localizations | Sort-Object);
  localizationTokens=@($observedLocalizationKeys | Sort-Object);
  contentCrumbTokens=@($contentCrumbTokens | Sort-Object);
  localizationContractCount=$expectedLocalizationKeys.Count;
  dynamicSwfLoaders=@($loaders | Sort-Object);
  requiredPartyMethods=@($requiredPartyMethods | Sort-Object); requiredPartyConstants=@($requiredPartyConstants | Sort-Object);
  soloRoomEvidence=@($soloRoomEvidence | Sort-Object); files=$reports; compatibilityFiles=$compatibilityReports
}
$summaryPath = Join-Path $work 'summary.json'
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
foreach ($pair in @($pairs | Sort-Object)) { Write-Host "WADDLE_PARTY2015_PROTOCOL_PAIR=$pair" }
foreach ($packet in @($packets | Sort-Object)) { Write-Host "WADDLE_PARTY2015_PROTOCOL_PACKET=$packet" }
Write-Host "WADDLE_PARTY2015_PROTOCOL=PASS runtime=exact-cparchives-2015 selector_runtime=20151101 mayparty_aliases=3 compatibility_map=rejected targets=$($targets.Count) core=$($interactionCore.Count) core_scripted=$coreScripted robot_rooms=$($robotQuestRooms.Count) robot_room_scripted=$robotRoomScripted compatibility_scripted=$compatibilityScripted dialogues=34 tiles=9 scripted_targets=$scripted localization_contract=$($expectedLocalizationKeys.Count) localization_observed=$($observedLocalizationKeys.Count) content_crumbs=$($contentCrumbTokens.Count) namespace_tokens=$($localizations.Count) dynamic_loaders=$($loaders.Count) server_routes=5 ffdec_retry=true summary=$summaryPath") {
    [void]$contentCrumbTokens.Add($token)
    continue
  }
  throw "WADDLE_PARTY2015_PROTOCOL=FAIL unknown_halloween_namespace_token=$token"
}
if ($observedLocalizationKeys.Count -lt 1) {
  throw 'WADDLE_PARTY2015_PROTOCOL=FAIL no_localization_evidence_in_preserved_swfs'
}
foreach ($token in @($observedLocalizationKeys | Sort-Object)) { Write-Host "WADDLE_PARTY2015_PROTOCOL_LOCALIZATION=$token" }
foreach ($token in @($contentCrumbTokens | Sort-Object)) { Write-Host "WADDLE_PARTY2015_PROTOCOL_CONTENT_CRUMB=$token" }
Write-Host "WADDLE_PARTY2015_LOCALIZATION_EVIDENCE=PASS contract=38 observed_static=$($observedLocalizationKeys.Count) content_crumbs=$($contentCrumbTokens.Count) namespace_tokens=$($localizations.Count)"

foreach ($loader in @($loaders | Sort-Object)) { Write-Host "WADDLE_PARTY2015_PROTOCOL_LOADER=$loader" }
foreach ($badLoader in @('content/party_map_note.swf','close_ups/party_map_note.swf','music/2048.swf','music/2049.swf','music/2050.swf','music/2051.swf','music/2052.swf','music/2053.swf')) {
  if ($loaders.Contains($badLoader)) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL live_runtime_mixed_loader=$badLoader" }
}

foreach ($loader in @($compatibilityLoaders | Sort-Object)) { Write-Host "WADDLE_PARTY2015_PROTOCOL_COMPAT_LOADER=$loader" }
if (-not $compatibilityLoaders.Contains('close_ups/party_map_note.swf')) {
  throw 'WADDLE_PARTY2015_PROTOCOL=FAIL compat_map_rejection_evidence_changed expected=close_ups/party_map_note.swf'
}
Write-Host 'WADDLE_PARTY2015_COMPAT_MAP=REJECTED reason=requires_missing_close_ups_party_map_note source=2310_provenance_only routed_live=false'

$worldHandlersPath = Join-Path $repo 'src\server\socket-server\world-handlers.ts'
$partyHandlerPath = Join-Path $repo 'src\server\socket-server\handlers\party.ts'
$xtHandlerPath = Join-Path $repo 'src\server\socket-server\xt-handler.ts'
$worldHandlers = [IO.File]::ReadAllText($worldHandlersPath)
$partyHandler = [IO.File]::ReadAllText($partyHandlerPath)
$xtHandler = [IO.File]::ReadAllText($xtHandlerPath)
foreach ($route in @('party#partycookie','party#msgviewed','party#qcmsgviewed','party#qtaskcomplete','party#qtupdate')) {
  if (-not $worldHandlers.Contains($route)) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL server_route_missing=$route" }
}
foreach ($token in @('getPartyServiceConfig','sendCurrentPartyCookie','partyservice','partycookie','activefeatures','qtupdate')) {
  if (-not $partyHandler.Contains($token)) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL party_handler_missing=$token" }
}
foreach ($alias in @(
  "['s%fair#fair', 's%party#partycookie']",
  "['s%fair#partycookie', 's%party#partycookie']",
  "['s%fair#msgviewed', 's%party#msgviewed']"
)) {
  if (-not $xtHandler.Contains($alias)) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL mayparty_alias_missing=$alias" }
}

$summary = [ordered]@{
  schema='waddle-modern-party-protocol/v13'; party='Halloween Party 2015'; evidence='exact-cparchives-2015-with-selector-aware-runtime-robot-room-interactions-and-rejected-2310-map';
  targetCount=$targets.Count; interactionCoreCount=$interactionCore.Count; interactionCoreScripted=$coreScripted;
  robotQuestRoomCount=$robotQuestRooms.Count; robotQuestRoomScripted=$robotRoomScripted;
  compatibilityTargetCount=$compatibilityTargets.Count; compatibilityScripted=$compatibilityScripted; compatibilityStatus='rejected';
  mayPartyNamespaceAliases=3; compatibilityLoaders=@($compatibilityLoaders | Sort-Object); dialogueCount=$dialogueCount;
  scriptedTargetCount=$scripted; pairs=@($pairs | Sort-Object); packetTokens=@($packets | Sort-Object);
  localizationTokens=@($localizations | Sort-Object); dynamicSwfLoaders=@($loaders | Sort-Object);
  requiredPartyMethods=@($requiredPartyMethods | Sort-Object); requiredPartyConstants=@($requiredPartyConstants | Sort-Object);
  soloRoomEvidence=@($soloRoomEvidence | Sort-Object); files=$reports; compatibilityFiles=$compatibilityReports
}
$summaryPath = Join-Path $work 'summary.json'
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
foreach ($pair in @($pairs | Sort-Object)) { Write-Host "WADDLE_PARTY2015_PROTOCOL_PAIR=$pair" }
foreach ($packet in @($packets | Sort-Object)) { Write-Host "WADDLE_PARTY2015_PROTOCOL_PACKET=$packet" }
Write-Host "WADDLE_PARTY2015_PROTOCOL=PASS runtime=exact-cparchives-2015 selector_runtime=20151101 mayparty_aliases=3 compatibility_map=rejected targets=$($targets.Count) core=$($interactionCore.Count) core_scripted=$coreScripted robot_rooms=$($robotQuestRooms.Count) robot_room_scripted=$robotRoomScripted compatibility_scripted=$compatibilityScripted dialogues=34 tiles=9 scripted_targets=$scripted localization_tokens=$($localizations.Count) dynamic_loaders=$($loaders.Count) server_routes=5 ffdec_retry=true summary=$summaryPath"