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
      foreach ($file in $files) {
        $body = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
        if (-not [string]::IsNullOrWhiteSpace($body)) { $chunks += $body }
      }
      return [pscustomobject]@{ files=$files.Count; text=($chunks -join "`n`n"); exit=$exitText; attempts=$attempt }
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

function Add-PartyRuntimeContract([string]$Text,[string]$Role) {
  foreach ($match in @([regex]::Matches($Text,'(?i)(?:_currentParty|BaseParty\.CURRENT_PARTY|CURRENT_PARTY)\.([A-Za-z_][A-Za-z0-9_]*)\s*\('))) {
    [void]$requiredPartyMethods.Add([string]$match.Groups[1].Value)
  }
  foreach ($match in @([regex]::Matches($Text,'(?i)\.CONSTANTS\.([A-Z][A-Z0-9_]*)'))) {
    [void]$requiredPartyConstants.Add(([string]$match.Groups[1].Value).ToUpperInvariant())
  }
  foreach ($line in @($Text -split '\r?\n' | Where-Object { $_ -match '(?i)partysolo1' } | ForEach-Object { ($_ -replace '\s+',' ').Trim() } | Where-Object { $_.Length -gt 0 } | Select-Object -Unique -First 40)) {
    $safeLine = if ($line.Length -gt 700) { $line.Substring(0,700) } else { $line }
    [void]$soloRoomEvidence.Add("$Role::$safeLine")
  }
}

foreach ($target in $targets) {
  $swf = Join-Path $partyRoot ([string]$target.path)
  if (-not (Test-Swf $swf)) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL invalid_target role=$($target.role) path=$swf" }
  $safe = ([string]$target.role -replace '[^A-Za-z0-9_.-]','_')
  $evidence = Export-Scripts -FFDec $ffdec -Swf $swf -SafeName $safe -WorkRoot $work
  $text = [string]$evidence.text
  Add-PartyRuntimeContract -Text $text -Role ([string]$target.role)
  if ($evidence.files -gt 0) { $scripted++ }
  if (@($interactionCore | Where-Object { $_.role -eq $target.role }).Count -gt 0) {
    if ($evidence.files -gt 0) { $coreScripted++ }
    $interactionText += "`n" + $text
  }
  if (@($robotQuestRooms | Where-Object { $_.role -eq $target.role }).Count -gt 0) {
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
  Add-PartyRuntimeContract -Text $text -Role $safe
  if ($text -notmatch '(?i)(pickupItem|itemCollectRelease|collectedItem|partysolo1|party7|sendJoinRoom|QUEST_TASK_ID)') { continue }
  $roomLines = @($text -split "`r?`n" | Where-Object { $_ -match '(?i)(class com\.clubpenguin\.world\.rooms2015\.october|QUEST_TASK_ID|pickupItem|itemCollectRelease|collectedItem|displayItemPickupInstructions|partysolo1|party7|sendJoinRoom|triggerFunction)' } | ForEach-Object { ($_ -replace '\s+',' ').Trim() } | Where-Object { $_.Length -gt 0 } | Select-Object -Unique -First 220)
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
if ($soloRoomEvidence.Count -lt 1) {
  throw 'WADDLE_PARTY2015_PROTOCOL=FAIL partysolo1_entry_contract_not_found'
}
Write-Host "WADDLE_PARTY2015_RUNTIME_PARITY=PASS required_methods=$($requiredPartyMethods.Count) required_constants=$($requiredPartyConstants.Count) solo_room_evidence=$($soloRoomEvidence.Count)"

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
if ($localizations.Count -ne 38) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL localization_tokens=$($localizations.Count) expected=38" }

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