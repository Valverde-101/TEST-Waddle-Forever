param([string]$RepoRoot = $env:GITHUB_WORKSPACE)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
function Write-Utf8([string]$Path,[string]$Text){$enc=New-Object System.Text.UTF8Encoding($false);[IO.File]::WriteAllText($Path,$Text,$enc)}
function NeedReplace([string]$Text,[string]$Old,[string]$New,[string]$Label){if($Text.Contains($New)){return $Text};if(-not $Text.Contains($Old)){throw "WADDLE_PARTY2015_SOURCE=FAIL patch_not_found=$Label"};return $Text.Replace($Old,$New)}

$filesPath=Join-Path $RepoRoot 'src/server/game-data/files.ts'
$files=[IO.File]::ReadAllText($filesPath)
$files=NeedReplace $files "const UNKNOWN = 'unknown';" "const UNKNOWN = 'unknown';`nconst PARTY2015 = 'party2015';" 'files-constant'
if(-not $files.Contains('  PARTY2015,')){$files=NeedReplace $files "  UNKNOWN,`n  'archives'," "  UNKNOWN,`n  PARTY2015,`n  'archives'," 'files-subdirectory'}
Write-Utf8 $filesPath $files

$timelinePath=Join-Path $RepoRoot 'src/client/views/timeline/timeline-static.ts'
$timeline=[IO.File]::ReadAllText($timelinePath)
$timeline=NeedReplace $timeline '  const endDate = new Date(2013, 0, 1);' "  // Render through the last real update instead of truncating the calendar at 2012.`n  const endDate = getDateFromDateInfo(days[days.length - 1]);`n  endDate.setDate(endDate.getDate() + 1);" 'timeline-end'
Write-Utf8 $timelinePath $timeline

$htmlPath=Join-Path $RepoRoot 'src/client/views/timeline/timeline.html'
$html=[IO.File]::ReadAllText($htmlPath)
if(-not $html.Contains('<option>2015</option>')){$html=NeedReplace $html '              <option>2012</option>' "              <option>2012</option>`n              <option>2013</option>`n              <option>2014</option>`n              <option>2015</option>`n              <option>2016</option>`n              <option>2017</option>" 'timeline-years'}
Write-Utf8 $htmlPath $html

$roomsPath=Join-Path $RepoRoot 'src/server/game-data/rooms.ts'
$rooms=[IO.File]::ReadAllText($roomsPath)
if(-not $rooms.Contains("  'hotellobby' |")){
  $types="  'hotellobby' |`n  'hotelspa' |`n  'hotelroof' |`n  'cloudforest' |`n  'park' |`n  'skatepark' |`n  'pufflewild' |`n  'school' |`n  'mall' |`n  'dojosnow' |`n"
  $rooms=NeedReplace $rooms "  'party' |" ($types+"  'party' |") 'room-types'
}
if(-not $rooms.Contains("  'hotellobby': {")){
$modern=@"
  'school': {
    id: 122,
    name: 'School',
    preCpipName: null
  },
  'dojosnow': {
    id: 326,
    name: 'Snow Dojo',
    preCpipName: null
  },
  'mall': {
    id: 340,
    name: 'Puffle Berry Mall',
    preCpipName: null
  },
  'hotellobby': {
    id: 430,
    name: 'Puffle Hotel Lobby',
    preCpipName: null
  },
  'hotelspa': {
    id: 431,
    name: 'Puffle Hotel Spa',
    preCpipName: null
  },
  'hotelroof': {
    id: 432,
    name: 'Puffle Hotel Roof',
    preCpipName: null
  },
  'cloudforest': {
    id: 433,
    name: 'Cloud Forest',
    preCpipName: null
  },
  'park': {
    id: 434,
    name: 'Puffle Park',
    preCpipName: null
  },
  'skatepark': {
    id: 435,
    name: 'Skatepark',
    preCpipName: null
  },
  'pufflewild': {
    id: 436,
    name: 'Puffle Wild',
    preCpipName: null
  },
"@
  $rooms=NeedReplace $rooms "  'party': {" ($modern+"  'party': {") 'room-records'
}
Write-Utf8 $roomsPath $rooms

$updates=@'
import { Update } from ".";

const P = 'party2015:';

export const UPDATES_2015: Update[] = [
  {
    date: '2015-05-01',
    rooms: { lake: 'archives:RoomsLake-May2015.swf' }
  },
  {
    date: '2015-10-21',
    temp: {
      party: {
        partyName: 'Halloween Party 2015',
        rooms: {
          beach: P+'rooms/Hallo15_beach.swf', beacon: P+'rooms/Hallo15_beacon.swf', book: P+'rooms/Hallo15_book.swf', cave: P+'rooms/Hallo15_cave.swf', shop: P+'rooms/Hallo15_shop.swf',
          cloudforest: P+'rooms/Hallo15_cloudforest.swf', coffee: P+'rooms/Hallo15_coffee.swf', cove: P+'rooms/Hallo15_cove.swf', dance: P+'rooms/Hallo15_dance.swf', dock: P+'rooms/Hallo15_dock.swf',
          dojo: P+'rooms/Hallo15_dojo.swf', dojoext: P+'rooms/Hallo15_dojoext.swf', agentlobbymulti: P+'rooms/Hallo15_agentlobbymulti.swf', dojofire: P+'rooms/Hallo15_dojofire.swf', forest: P+'rooms/Hallo15_forest.swf',
          party1: P+'rooms/Hallo15_party1.swf', party2: P+'rooms/Hallo15_party2.swf', berg: P+'rooms/Hallo15_berg.swf', light: P+'rooms/Hallo15_light.swf', attic: P+'rooms/Hallo15_attic.swf', lounge: P+'rooms/Hallo15_lounge.swf',
          shack: P+'rooms/Hallo15_shack.swf', pet: P+'rooms/Hallo15_pet.swf', pizza: P+'rooms/Hallo15_pizza.swf', plaza: P+'rooms/Hallo15_plaza.swf', mall: P+'rooms/Hallo15_mall.swf',
          hotellobby: P+'rooms/Hallo15_hotellobby.swf', hotelroof: P+'rooms/Hallo15_hotelroof.swf', hotelspa: P+'rooms/Hallo15_hotelspa.swf', park: P+'rooms/Hallo15_park.swf', pufflewild: P+'rooms/Hallo15_pufflewild.swf',
          school: P+'rooms/Hallo15_school.swf', skatepark: P+'rooms/Hallo15_skatepark.swf', mtn: P+'rooms/Hallo15_mtn.swf', lodge: P+'rooms/Hallo15_lodge.swf', village: P+'rooms/Hallo15_village.swf',
          dojosnow: P+'rooms/Hallo15_dojosnow.swf', forts: P+'rooms/Hallo15_forts.swf', rink: P+'rooms/Hallo15_rink.swf', town: P+'rooms/RoomsTown-HalloweenParty2015.swf'
        },
        music: {
          beach:1054, beacon:1053, book:669, cave:532, shop:345, cloudforest:1044, coffee:1031, cove:1035, dance:1036, dock:1037,
          dojo:403, dojoext:1045, agentlobbymulti:922, dojofire:1046, forest:1038, party1:838, party2:1058, berg:1043, light:588, attic:884,
          lounge:1055, shack:1041, pet:659, pizza:1033, plaza:1052, mall:1032, hotellobby:1048, hotelroof:1049, hotelspa:1050, park:1051,
          pufflewild:1057, school:1040, skatepark:1034, mtn:1042, lodge:1056, village:1042, dojosnow:1047, forts:1039, rink:1067, town:1052
        },
        fileChanges: {
          'play/v2/client/interface.swf': P+'client/ClientInterface-HalloweenParty2015.swf',
          'play/v2/content/global/content/features.swf': P+'content/ContentFeatures-HalloweenParty2015.swf',
          'play/v2/content/global/content/logo.swf': P+'content/ContentLogo-HalloweenParty2015.swf',
          'play/v2/content/global/content/party_icon.swf': P+'content/ContentParty_icon-HalloweenParty2015.swf',
          'play/v2/content/global/avatar/sprites/penguin_robot.swf': P+'avatar/PenguinRobot.swf',
          'play/v2/content/global/telescope/telescope.swf': P+'other/Telescope-HalloweenParty2015.swf',
          'play/v2/content/global/binoculars/binoculars.swf': P+'other/Binoculars-HalloweenParty2015.swf'
        },
        localChanges: {
          'close_ups/quest_interface.swf': { en: P+'close_ups/Close_upsQuest_interface-HalloweenParty2015.swf' },
          'close_ups/tiles_minigame0.swf': { en: P+'close_ups/Close_upsTiles_minigame0-HalloweenParty2015.swf' },
          'close_ups/tiles_minigame1.swf': { en: P+'close_ups/Close_upsTiles_minigame1-HalloweenParty2015.swf' },
          'close_ups/tiles_minigame2.swf': { en: P+'close_ups/Close_upsTiles_minigame2-HalloweenParty2015.swf' },
          'close_ups/tiles_minigame3.swf': { en: P+'close_ups/Close_upsTiles_minigame3-HalloweenParty2015.swf' },
          'close_ups/tiles_minigame4.swf': { en: P+'close_ups/Close_upsTiles_minigame4-HalloweenParty2015.swf' },
          'close_ups/tiles_minigame5.swf': { en: P+'close_ups/Close_upsTiles_minigame5-HalloweenParty2015.swf' },
          'close_ups/tiles_minigame6.swf': { en: P+'close_ups/Close_upsTiles_minigame6-HalloweenParty2015.swf' },
          'close_ups/tiles_minigame7.swf': { en: P+'close_ups/Close_upsTiles_minigame7-HalloweenParty2015.swf' },
          'close_ups/tiles_minigame8.swf': { en: P+'close_ups/Close_upsTiles_minigame8-HalloweenParty2015.swf' },
          'membership/party1.swf': { en: P+'membership/MembershipParty1-HalloweenParty2015.swf' },
          'membership/party2.swf': { en: P+'membership/MembershipParty2-HalloweenParty2015.swf' }
        }
      }
    }
  },
  { date: '2015-11-04', end: ['party'] }
];
'@
Write-Utf8 (Join-Path $RepoRoot 'src/server/updates/2015.ts') $updates
Write-Host 'WADDLE_PARTY2015_SOURCE=PASS calendar=dynamic years=2005-2017 modern_rooms=10 party_start=2015-10-21 party_end=2015-11-04 media_prefix=party2015'
