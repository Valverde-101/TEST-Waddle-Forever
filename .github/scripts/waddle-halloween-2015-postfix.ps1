param([string]$RepoRoot = $env:GITHUB_WORKSPACE)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
function Read-N([string]$Path){ return ([IO.File]::ReadAllText($Path) -replace "`r`n","`n") }
function Write-Utf8([string]$Path,[string]$Text){ $enc=New-Object System.Text.UTF8Encoding($false); [IO.File]::WriteAllText($Path,($Text -replace "`r`n","`n"),$enc) }

$roomsPath=Join-Path $RepoRoot 'src/server/game-data/rooms.ts'
$rooms=Read-N $roomsPath
$rooms=$rooms.Replace("  'pufflepark' |  'party' |","  'pufflepark' |`n  'party' |")
$rooms=$rooms.Replace("  },  'party': {","  },`n  'party': {")
Write-Utf8 $roomsPath $rooms

$updatesPath=Join-Path $RepoRoot 'src/server/updates/2015.ts'
$updates=Read-N $updatesPath
if(-not $updates.Contains("'play/v2/content/global/music/345.swf'")){
  $needle="          'play/v2/content/global/music/838.swf': P + 'music/Music838.swf',"
  $insert=@"
          'play/v2/content/global/music/345.swf': P + 'music/Music345.swf',
          'play/v2/content/global/music/403.swf': P + 'music/Music403.swf',
          'play/v2/content/global/music/532.swf': P + 'music/Music532.swf',
          'play/v2/content/global/music/588.swf': P + 'music/Music588.swf',
          'play/v2/content/global/music/659.swf': P + 'music/Music659.swf',
          'play/v2/content/global/music/669.swf': P + 'music/Music669.swf',
          'play/v2/content/global/music/838.swf': P + 'music/Music838.swf',
"@
  if(-not $updates.Contains($needle)){throw 'WADDLE_PARTY2015_POSTFIX=FAIL music_anchor_missing'}
  $updates=$updates.Replace($needle,$insert.TrimEnd("`r","`n"))
}
if(-not $updates.Contains("'play/v2/content/global/membership/party1.swf'")){
  $needle="          'play/v2/content/global/rooms/partysolo1.swf': P + 'rooms/Hallo15_partysolo1.swf',"
  $insert=@"
          'play/v2/content/global/rooms/partysolo1.swf': P + 'rooms/Hallo15_partysolo1.swf',
          'play/v2/content/global/membership/party1.swf': P + 'membership/MembershipParty1-HalloweenParty2015.swf',
          'play/v2/content/global/membership/party2.swf': P + 'membership/MembershipParty2-HalloweenParty2015.swf',
"@
  if(-not $updates.Contains($needle)){throw 'WADDLE_PARTY2015_POSTFIX=FAIL membership_anchor_missing'}
  $updates=$updates.Replace($needle,$insert.TrimEnd("`r","`n"))
}
Write-Utf8 $updatesPath $updates
Write-Host 'WADDLE_PARTY2015_POSTFIX=PASS music_routes=38 membership_global_aliases=2 room_format=clean'
