[CmdletBinding()]
param([string]$RepoRoot = $env:GITHUB_WORKSPACE)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Read-N([string]$Path) { return ([IO.File]::ReadAllText($Path) -replace "`r`n", "`n") }
function Write-N([string]$Path,[string]$Text) { [IO.File]::WriteAllText($Path,($Text -replace "`r`n", "`n"),$utf8) }
function Replace-Once([string]$Text,[string]$Old,[string]$New,[string]$Label) {
  if ($Text.Contains($New)) { return $Text }
  if (-not $Text.Contains($Old)) { throw "WADDLE_HALLOWEEN2015_DATA=FAIL anchor=$Label" }
  return $Text.Replace($Old,$New)
}

# The party's Ghost Puffle is a creature subtype with canonical price 0.
# Generic creature pricing must respect PUFFLES so other event creatures can
# declare their own price without another handler special case.
$pufflePath = Join-Path $repo 'src/server/socket-server/handlers/puffle.ts'
$puffle = Read-N $pufflePath
if (-not $puffle.Contains('category === PuffleCategory.Creature ? puffleInfo.cost')) {
  $puffle = Replace-Once $puffle @'
  const isFreeBrownPuffle = puffleType === 9 && data.isBrownPuffleFree();

  const cost =
    (isFreeBrownPuffle || category === PuffleCategory.Gold) ? 0 :
    (data.isVanillaEngine() && category !== PuffleCategory.Creature) ? 400 : 800;

  const puffleTypeId = puffleSubtype === 0 ? puffleType : puffleSubtype;
  const puffleInfo = PUFFLES.getStrict(puffleTypeId);
'@ @'
  const isFreeBrownPuffle = puffleType === 9 && data.isBrownPuffleFree();

  const puffleTypeId = puffleSubtype === 0 ? puffleType : puffleSubtype;
  const puffleInfo = PUFFLES.getStrict(puffleTypeId);

  // Event creature prices are data-driven by PUFFLES (Ghost 1022 is free).
  const cost =
    (isFreeBrownPuffle || category === PuffleCategory.Gold) ? 0 :
    category === PuffleCategory.Creature ? puffleInfo.cost :
    data.isVanillaEngine() ? 400 : 800;
'@ 'creature-price'
}
Write-N $pufflePath $puffle

$updatesPath = Join-Path $repo 'src/server/updates/2015.ts'
$updates = Read-N $updatesPath
if (-not $updates.Contains("id: 'halloween-2015'")) {
  $updates = Replace-Once $updates "        partyName: 'Halloween Party 2015'," @'
        partyName: 'Halloween Party 2015',
        partyProgress: {
          id: 'halloween-2015',
          messageCount: 10,
          communicatorMessageCount: 5,
          taskCount: 10,
          maxCoinUpdate: 10
        },
'@.TrimEnd() 'party-progress'
}

# Party-local strings are merged only while this timeline update is active.
# The finale text is preserved from the archived game strings; the MascBot
# quest dialogue follows the leaked 2015 dialogue/screens in their original
# order. Keeping these here makes localization another party data dependency.
$dialogueOverlay = @'
        gameStringChanges: {
          "w.app.p2015.halloween.login1": "Gadzooks! I fear the robots I created for the 10th Anniversary Party have gone haywire! This is an especially spooky start to Halloween. Could you help me deal with these mad machines?",
          "w.app.p2015.halloween.login2": "The Gary Bot is menacing the Mine Shack right now!",
          "w.app.p2015.halloween.gary1": "Scare this robot by showing it its greatest fear: decaf coffee!",
          "w.app.p2015.halloween.gary2": "Success! That caused a fear overload. Now deactivate it.",
          "w.app.p2015.halloween.gary3": "Connect the green terminal to the yellow terminal.",
          "w.app.p2015.halloween.gary4": "Well done! We're safe from that robot, but there are others sneaking around.",
          "w.app.p2015.halloween.gary5": "Excellent work! The robot has been deactivated. Stay alert for the others.",
          "w.app.p2015.halloween.AA1": "Oh my! A robot that looks like me is scaring citizens. We have to put an end to this.",
          "w.app.p2015.halloween.AA2": "There is one thing that should stop it: my terrible spelling. Show this failed spelling test to the robot.",
          "w.app.p2015.halloween.AA3": "Excellent work! That is one less robot causing trouble.",
          "w.app.p2015.halloween.rockhopper1": "Avast! That crazy robot thinks it can be me! Head to the Forest, matey.",
          "w.app.p2015.halloween.rockhopper2": "Scare that robot with a fearsome pink flamingo!",
          "w.app.p2015.halloween.rockhopper3": "Har har! Well done, matey!",
          "w.app.p2015.halloween.Djcadence1": "Eeeeee! There's a scary robot in the Ski Village! This is a BIG one!",
          "w.app.p2015.halloween.Djcadence2": "What scares me... besides evil glitchy robots? Bugs! That's it! Show it some bugs!",
          "w.app.p2015.halloween.Djcadence3": "Whew! You did it! What a way to end the day on a high note.",
          "w.app.p2015.halloween.Dot1": "I'm all for disguises, but there's a robot that looks like me at the Cove! We have to shut it down.",
          "w.app.p2015.halloween.Dot2": "We'll have to find my greatest fear: an ugly sweater. Show one to the robot.",
          "w.app.p2015.halloween.Dot3": "Good work! That robot was no match for your scare skills!",
          "w.app.p2015.halloween.Sensei1": "There is a disturbance at the Beach. A mechanical monster wears my clothes, but not my inner calm.",
          "w.app.p2015.halloween.Sensei2": "We must scare this robot. Threaten the robot's beard with a trimmer.",
          "w.app.p2015.halloween.Sensei3": "Your beard-trimming skills are impressive! Well done, grasshopper.",
          "w.app.p2015.halloween.PH1": "Crikey! There's a rogue robot at the Snow Forts. Let's head over there!",
          "w.app.p2015.halloween.PH2": "That thing must fear whatever scares me. Show it this toy UFO.",
          "w.app.p2015.halloween.PH3": "Bonza! You took care of that robot no worries!",
          "w.app.p2015.halloween.Rookie1": "Yikes! Somebody call the EPF! The Rookie Bot is going crazy in the Plaza!",
          "w.app.p2015.halloween.Rookie2": "Ahhh!! That's scarier than a clown! Wait... that's it! Scare it with clown face paint!",
          "w.app.p2015.halloween.Rookie3": "A secret lair in the Coffee Shop? Sounds scary. I'll alert the EPF.",
          "w.app.p2015.halloween.RookieBOT1": "BZZZT! You found my fear. But you'll never find the secret lair in the Coffee Shop! ... Oops! running scared.exe! ShUTTiNG DooOOoown",
          "w.app.p2015.halloween.finale.HerbertMonologue1": "Look, I've told you before, I didn't bring Herbot back!\n\nI think it was that pesky di-",
          "w.app.p2015.halloween.finale.HerbertMonologue2": "Ah, a penguin!\nSo, you think you can just take MY inventions and turn them into party props?\nI'll show YOU not to humiliate Herbert P. Bear, Esquire!",
          "w.app.p2015.halloween.finale.HerBOTReply1": "Making the same mistakes twice, are we?\n\nI really am the superior bear.",
          "w.app.p2015.halloween.finale.HerbertScared1": "GRRRR...\n\nI knew I shouldn't have taken inspiration from that movie...",
          "w.app.p2015.halloween.finale.GaryScreen1": "Connection terminated.\n\nI'm sorry to interrupt you Herbert, if you even-",
          "w.app.p2015.halloween.finale.HerbertReply1": "WHATEVER!\n\nJust get me out of here so I can destroy you with my actual NEW inventions.",
          "w.app.p2015.halloween.finale.GaryScreen2": "Quick, we can't let Herbot escape! Credit due to Herbert, it seems as if he left the same laser intact that put Herbot out of commission the last time. Blast him with the laser and then short circuit his wires!",
          "w.app.p2015.halloween.finale.HerbertRunaway1": "MWAHAHAHAHA! You can't stop Klutzy and I!\n\nWe'll take over this whole island! Quick Klutzy, to the Skyberg!",
          "w.app.p2015.halloween.finale.GaryScreen3": "Excellent work!\nHerbert may have gotten away, but we've hopefully set him back just enough to not spoil the rest of our Halloween fun!"
        },
'@
if (-not $updates.Contains('gameStringChanges: {')) {
  $anchor = @'
          maxCoinUpdate: 10
        },
        rooms: {
'@
  $replacement = "          maxCoinUpdate: 10`n        },`n" + $dialogueOverlay + "        rooms: {`n"
  $updates = Replace-Once $updates $anchor $replacement 'dialogue-overlay'
}
Write-N $updatesPath $updates

$verifyUpdates = Read-N $updatesPath
if (-not $verifyUpdates.Contains("id: 'halloween-2015'")) { throw 'WADDLE_HALLOWEEN2015_DATA=FAIL party_progress_missing' }
if (-not $verifyUpdates.Contains('gameStringChanges: {')) { throw 'WADDLE_HALLOWEEN2015_DATA=FAIL dialogue_overlay_missing' }
$dialogueKeys = @([regex]::Matches($verifyUpdates,'"w\.app\.p2015\.halloween[^"\r\n]+"') | ForEach-Object { $_.Value } | Sort-Object -Unique)
if ($dialogueKeys.Count -ne 38) { throw "WADDLE_HALLOWEEN2015_DATA=FAIL expected_dialogue_keys=38 actual=$($dialogueKeys.Count)" }
if (-not (Read-N $pufflePath).Contains('category === PuffleCategory.Creature ? puffleInfo.cost')) { throw 'WADDLE_HALLOWEEN2015_DATA=FAIL ghost_puffle_price_missing' }

& git -C $repo add -- 'src/server/updates/2015.ts' 'src/server/socket-server/handlers/puffle.ts'
if ($LASTEXITCODE -ne 0) { throw "WADDLE_HALLOWEEN2015_DATA=FAIL git_add_exit=$LASTEXITCODE" }
Write-Host 'WADDLE_HALLOWEEN2015_DATA=PASS party=halloween-2015 tasks=10 dialogue_keys=38 ghost_puffle=1022 staged=true'
