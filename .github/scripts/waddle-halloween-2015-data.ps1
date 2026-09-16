[CmdletBinding()]
param([string]$RepoRoot = $env:GITHUB_WORKSPACE)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path

function Read-N([string]$Path) {
  if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "WADDLE_HALLOWEEN2015_DATA=FAIL missing=$Path"}
  return ([IO.File]::ReadAllText($Path) -replace "`r`n", "`n")
}
function Require([bool]$Condition,[string]$Label) {
  if(-not $Condition){throw "WADDLE_HALLOWEEN2015_DATA=FAIL missing_contract=$Label"}
}
function Test-Swf([string]$Path) {
  if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return $false}
  $stream = [IO.File]::OpenRead($Path)
  try {
    if($stream.Length -lt 8){return $false}
    $signature = New-Object byte[] 3
    if($stream.Read($signature,0,3) -ne 3){return $false}
    return @('FWS','CWS','ZWS') -contains [Text.Encoding]::ASCII.GetString($signature)
  } finally {
    $stream.Dispose()
  }
}

# Committed source is authoritative. This gate is validation-only: it must never
# rewrite party data or force a temporary third-party runtime back into 2015.ts.
$pufflePath = Join-Path $repo 'src/server/socket-server/handlers/puffle.ts'
$updatesPath = Join-Path $repo 'src/server/updates/2015.ts'
$runtimePath = Join-Path $repo 'media/default/svanilla/media/play/v2/content/global/content/party.swf'
$puffle = Read-N $pufflePath
$updates = Read-N $updatesPath

Require ($puffle.Contains('category === PuffleCategory.Creature ? puffleInfo.cost')) 'creature_price_from_puffle_data'
Require ($updates.Contains("partyName: 'Halloween Party 2015'")) 'party_name'
Require ($updates.Contains("activeFeatures: '20150501'")) 'activefeatures_20150501'
Require ($updates.Contains("id: 'halloween-2015'")) 'party_progress_id'
Require ($updates.Contains('messageCount: 10')) 'message_count'
Require ($updates.Contains('communicatorMessageCount: 5')) 'communicator_count'
Require ($updates.Contains('taskCount: 10')) 'task_count'
Require ($updates.Contains('maxCoinUpdate: 10')) 'coin_cap'
Require ($updates.Contains("partyStartDate: '2015-10-21 00:00:00'")) 'party_service_start'
Require ($updates.Contains("partyEndDate: '2015-11-05 00:00:00'")) 'party_service_end'
Require ($updates.Contains('unlockDayIndex: 16')) 'party_service_unlock_day'
Require ($updates.Contains('numOfDaysInParty: 16')) 'party_service_days'

$iconAsset = "P + 'content/ContentParty_icon-HalloweenParty2015.swf'"
Require ($updates.Contains("'play/v2/client/interface.swf': P + 'client/ClientInterface-HalloweenParty2015.swf'")) 'client_interface_route'
Require ($updates.Contains("'play/v2/content/global/content/interface.swf': P + 'client/ClientInterface-HalloweenParty2015.swf'")) 'content_interface_alias'
Require ($updates.Contains("'play/v2/content/global/content/party_icon.swf': $iconAsset")) 'party_icon_canonical_route'
Require ($updates -match "'content/party_icon\.swf'\s*:\s*\[[^\]]*'party_icon'[^\]]*\]") 'party_icon_global_crumb'
Require ($updates -match "'content/party_icon\.swf'\s*:\s*\[[^\]]*'scavenger_hunt_icon'[^\]]*\]") 'party_icon_scavenger_alias'
Require ($updates -match "'close_ups/quest_interface\.swf'\s*:\s*\[[^\]]*'w\.p2015\.may\.partyinterface'[^\]]*\]") 'quest_interface_global_path'

# The event archive does not contain its own party.swf. Use the native svanilla
# framework runtime at the canonical URL and reject the old Fair/May substitute.
Require (Test-Swf $runtimePath) 'native_party_runtime'
Require (-not $updates.Contains("'play/v2/content/global/content/party.swf'")) 'no_event_party_runtime_override'
Require (-not $updates.Contains('PartyRuntime-CPImagined-HalloweenClassic.swf')) 'no_cpimagined_party_runtime'

if ($updates -match 'gameStringChanges:\s*\{(?s:.*?)w\.app\.p2015\.halloween') {
  throw 'WADDLE_HALLOWEEN2015_DATA=FAIL unverified_halloween_strings_remain'
}

$runtimeInfo = Get-Item -LiteralPath $runtimePath
Write-Host "WADDLE_HALLOWEEN2015_DATA=PASS mode=validation_only mutation=false party=halloween-2015 tasks=10 activefeatures=20150501 partyservice=true ghost_puffle=1022 party_icon=canonical_plus_aliases quest_path=true runtime=svanilla-native runtime_bytes=$($runtimeInfo.Length)"
