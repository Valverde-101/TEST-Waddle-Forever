param([string]$RepoRoot = $env:GITHUB_WORKSPACE)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
function Read-N([string]$Path){if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "WADDLE_PARTY2015_POSTFIX=FAIL missing=$Path"};return ([IO.File]::ReadAllText($Path)-replace "`r`n","`n")}
function Require([bool]$Condition,[string]$Label){if(-not $Condition){throw "WADDLE_PARTY2015_POSTFIX=FAIL missing_contract=$Label"}}
$rooms=Read-N (Join-Path $RepoRoot 'src/server/game-data/rooms.ts')
$updates=Read-N (Join-Path $RepoRoot 'src/server/updates/2015.ts')
Require (-not $rooms.Contains("  'pufflepark' |  'party' |")) 'rooms_union_format'
Require (-not $rooms.Contains("  },  'party': {")) 'rooms_object_format'

$musicIds=@(345,403,532,588,659,669,838,884,922,1031,1032,1033,1034,1035,1036,1037,1038,1039,1040,1041,1042,1043,1044,1045,1046,1047,1048,1049,1050,1051,1052,1053,1054,1055,1056,1057,1058,1067)
$listMatch=[regex]::Match($updates,'const\s+HALLOWEEN_2015_MUSIC_IDS\s*=\s*\[([^\]]+)\]')
Require $listMatch.Success 'music_id_set_present'
$actual=@([regex]::Matches($listMatch.Groups[1].Value,'\d+')|ForEach-Object{[int]$_.Value})
Require ($actual.Count-eq$musicIds.Count) 'music_id_count_38'
$diff=@(Compare-Object -ReferenceObject $musicIds -DifferenceObject $actual)
Require ($diff.Count-eq0) 'music_id_set_38'
Require ($updates-match'const\s+musicFileChanges\s*=\s*Object\.fromEntries\s*\(') 'music_generator'
Require ($updates-match'HALLOWEEN_2015_MUSIC_IDS\.map\s*\(\s*id\s*=>\s*\[') 'music_generator_ids'
Require ($updates.Contains('`play/v2/content/global/music/${id}.swf`')) 'music_generator_route'
Require ($updates.Contains('ref(`music/Music${id}.swf`)')) 'music_generator_target'
Require ($updates.Contains('...musicFileChanges')) 'music_generator_applied'
Require ($updates-match"'play/v2/content/global/membership/party1\.swf'\s*:\s*ref\('membership/MembershipParty1-HalloweenParty2015\.swf'\)") 'membership_party1'
Require ($updates-match"'play/v2/content/global/membership/party2\.swf'\s*:\s*ref\('membership/MembershipParty2-HalloweenParty2015\.swf'\)") 'membership_party2'
Write-Host 'WADDLE_PARTY2015_POSTFIX=PASS mode=validation_only mutation=false music_routes=38 music_model=data-driven membership_global_aliases=2 room_format=clean'
