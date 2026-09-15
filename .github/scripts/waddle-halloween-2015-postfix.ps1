param([string]$RepoRoot = $env:GITHUB_WORKSPACE)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

function Read-N([string]$Path){
  if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "WADDLE_PARTY2015_POSTFIX=FAIL missing=$Path"}
  return ([IO.File]::ReadAllText($Path) -replace "`r`n","`n")
}
function Require([bool]$Condition,[string]$Label){
  if(-not $Condition){throw "WADDLE_PARTY2015_POSTFIX=FAIL missing_contract=$Label"}
}

# This script used to rewrite committed source on every CI pass, even when the
# semantic content was already correct. That made source certification non-
# idempotent and could silently undo later runtime work. Committed TypeScript is
# now authoritative; this gate only validates the historical postfix contracts.
$roomsPath=Join-Path $RepoRoot 'src/server/game-data/rooms.ts'
$updatesPath=Join-Path $RepoRoot 'src/server/updates/2015.ts'
$rooms=Read-N $roomsPath
$updates=Read-N $updatesPath

Require (-not $rooms.Contains("  'pufflepark' |  'party' |")) 'rooms_union_format'
Require (-not $rooms.Contains("  },  'party': {")) 'rooms_object_format'

$musicIds=@(345,403,532,588,659,669,838,884,922,1031,1032,1033,1034,1035,1036,1037,1038,1039,1040,1041,1042,1043,1044,1045,1046,1047,1048,1049,1050,1051,1052,1053,1054,1055,1056,1057,1058,1067)
foreach($id in $musicIds){
  Require ($updates.Contains("'play/v2/content/global/music/$id.swf': P + 'music/Music$id.swf'")) "music_$id"
}
Require ($updates.Contains("'play/v2/content/global/membership/party1.swf': P + 'membership/MembershipParty1-HalloweenParty2015.swf'")) 'membership_party1'
Require ($updates.Contains("'play/v2/content/global/membership/party2.swf': P + 'membership/MembershipParty2-HalloweenParty2015.swf'")) 'membership_party2'

Write-Host 'WADDLE_PARTY2015_POSTFIX=PASS mode=validation_only mutation=false music_routes=38 membership_global_aliases=2 room_format=clean'
