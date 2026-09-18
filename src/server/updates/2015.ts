import { Update } from ".";

const P = 'party2015:';
const ref = (relative: string) => P + relative;

const HALLOWEEN_2015_DIALOGUE_STRINGS: Record<string, string> = {
  "w.app.p2015.halloween.login1": "Gadzooks! The robots I built for the 10th Anniversary have gone haywire. What a spooky way to begin Halloween!",
  "w.app.p2015.halloween.login2": "Could you help me deal with these crazed contraptions? The Gary Bot is threatening the Mine Shack right now!",
  "w.app.p2015.halloween.gary1": "The Gary Bot is out of control. Since it was programmed to act like me, it should share my greatest fear.",
  "w.app.p2015.halloween.gary2": "Scare the robot with decaf coffee! You can find some at the Coffee Shop.",
  "w.app.p2015.halloween.gary3": "Excellent! You found the decaf coffee. Show it to the Gary Bot!",
  "w.app.p2015.halloween.gary4": "Success! That caused a fear overload. Now deactivate it by connecting the green terminal to the yellow terminal.",
  "w.app.p2015.halloween.gary5": "Well done! We're safe from that robot, but there are more of them lurking around the island.",
  "w.app.p2015.halloween.AA1": "Oh my! A robot that looks like me is frightening citizens. We have to put a stop to this.",
  "w.app.p2015.halloween.AA2": "There is one thing that should scare it: terrible spelling. Show the robot that failed spelling test!",
  "w.app.p2015.halloween.AA3": "Wonderful work! The Arctic Bot is deactivated and everyone is safe again.",
  "w.app.p2015.halloween.rockhopper1": "Avast! That crazy robot thinks it can be me! Head to the Forest, matey!",
  "w.app.p2015.halloween.rockhopper2": "Scare that robot with a fearsome pink flamingo!",
  "w.app.p2015.halloween.rockhopper3": "Har har! Well done, matey! That Bothopper won't be causing any more trouble.",
  "w.app.p2015.halloween.Djcadence1": "Eeeee! There's a scary robot at the Ski Village! And this one is BIG!",
  "w.app.p2015.halloween.Djcadence2": "What scares me besides evil glitchy robots? Bugs! That's it! Show that bot a bug!",
  "w.app.p2015.halloween.Djcadence3": "Whew! You did it! Now that's a way to finish on a high note!",
  "w.app.p2015.halloween.Dot1": "I'm all for disguises, but there's a robot that looks like me at the Cove. We have to shut it down!",
  "w.app.p2015.halloween.Dot2": "We'll need my greatest fear: an old ugly sweater. Show one to the Dot Bot!",
  "w.app.p2015.halloween.Dot3": "Good work! That robot was no match for your scare skills.",
  "w.app.p2015.halloween.Sensei1": "There is a disturbance at the Beach: a mechanical monster in my clothes, but without my inner calm.",
  "w.app.p2015.halloween.Sensei2": "We must frighten this robot. Threaten its beard with the beard trimmer.",
  "w.app.p2015.halloween.Sensei3": "Your beard-trimming skills are impressive. Well done, grasshopper.",
  "w.app.p2015.halloween.PH1": "Crikey! There's a bonkers robot at the Snow Forts. Let's get over there!",
  "w.app.p2015.halloween.PH2": "It should fear anything that scares me. Show the bot that toy UFO!",
  "w.app.p2015.halloween.PH3": "Bonza! You handled that robot with no worries at all!",
  "w.app.p2015.halloween.Rookie1": "Yikes! Somebody call the EPF! The Rookie Bot is going berserk at the Plaza!",
  "w.app.p2015.halloween.Rookie2": "Ahhh! It's as scary as a clown! Wait... that's it! Scare it with clown face paint!",
  "w.app.p2015.halloween.RookieBOT1": "BZZT! You found my fear. But you'll never find the secret lair in the Coffee Shop! ...Oops! Running scared.exe! ShUTTiNG DooOOoown!",
  "w.app.p2015.halloween.Rookie3": "A secret lair in the Coffee Shop? That sounds scary. I'll alert the EPF!",
  "w.app.p2015.halloween.finale.HerbertMonologue1": "Look, I've told you before, I didn't bring Herbot back!\n\nI think it was that pesky di-",
  "w.app.p2015.halloween.finale.HerbertMonologue2": "Ah, a penguin!\nSo, you think you can just take MY inventions and turn them into party props?\nI'll show YOU not to humiliate Herbert P. Bear, Esquire!",
  "w.app.p2015.halloween.finale.HerBOTReply1": "Making the same mistakes twice, are we?\n\nI really am the superior bear.",
  "w.app.p2015.halloween.finale.HerbertScared1": "GRRRR...\n\nI knew I shouldn't have taken inspiration from that movie...",
  "w.app.p2015.halloween.finale.GaryScreen1": "Connection terminated.\n\nI'm sorry to interrupt you Herbert, if you even-",
  "w.app.p2015.halloween.finale.HerbertReply1": "WHATEVER!\n\nJust get me out of here so I can destroy you with my actual NEW inventions.",
  "w.app.p2015.halloween.finale.GaryScreen2": "Quick, we can't let Herbot escape! Credit due to Herbert, it seems as if he left the same laser intact that put Herbot out of commission the last time. Blast him with the laser and then short circuit his wires!",
  "w.app.p2015.halloween.finale.HerbertRunaway1": "MWAHAHAHAHA! You can't stop Klutzy and I!\n\nWe'll take over this whole island! Quick Klutzy, to the Skyberg!",
  "w.app.p2015.halloween.finale.GaryScreen3": "Excellent work!\nHerbert may have gotten away, but we've hopefully set him back just enough to not spoil the rest of our Halloween fun!",
  "w.app.generic.questui.header": "Robot Rampage",
  "w.app.generic.questui.subheader": "Stop the malfunctioning mascot robots around the island.",
  "w.app.generic.questui.subheader1": "Stop the malfunctioning mascot robots around the island.",
  "w.app.questui.subheader2": "Members can transform into a robot, and everyone can adopt a Ghost Puffle.",
  "w.app.generic.questui.description.task0": "Gary Bot is threatening the Mine Shack.",
  "w.app.generic.questui.description.task1": "Find decaf coffee for the Gary Bot.",
  "w.app.generic.questui.description.task2": "Show Arctic Bot a failed spelling test.",
  "w.app.generic.questui.description.task3": "Scare Bothopper with a pink flamingo.",
  "w.app.generic.questui.description.task4": "Show Cadence Bot a bug.",
  "w.app.generic.questui.description.task5": "Find an ugly sweater for Dot Bot.",
  "w.app.generic.questui.description.task6": "Use the beard trimmer on Sensei Bot.",
  "w.app.generic.questui.description.task7": "Show PH Bot a toy UFO.",
  "w.app.generic.questui.description.task8": "Scare Rookie Bot with clown face paint.",
  "w.app.generic.questui.description.task9": "Find the secret lair and stop Herbot.",
  // QuestInterface displays questTaskId + 1 for its description key: the
  // server completes task 0 for Gary and the card then requests task1.completed.
  // Reuse the party's own post-robot/finale dialogue text instead of inventing a
  // second set of completion copy. task0.completed is retained as a defensive
  // compatibility slot for clients that do not apply the +1 display offset.
  "w.app.generic.questui.description.task0.completed": "Well done! We're safe from that robot, but there are more of them lurking around the island.",
  "w.app.generic.questui.description.task1.completed": "Well done! We're safe from that robot, but there are more of them lurking around the island.",
  "w.app.generic.questui.description.task2.completed": "Wonderful work! The Arctic Bot is deactivated and everyone is safe again.",
  "w.app.generic.questui.description.task3.completed": "Har har! Well done, matey! That Bothopper won't be causing any more trouble.",
  "w.app.generic.questui.description.task4.completed": "Whew! You did it! Now that's a way to finish on a high note!",
  "w.app.generic.questui.description.task5.completed": "Good work! That robot was no match for your scare skills.",
  "w.app.generic.questui.description.task6.completed": "Your beard-trimming skills are impressive. Well done, grasshopper.",
  "w.app.generic.questui.description.task7.completed": "Bonza! You handled that robot with no worries at all!",
  "w.app.generic.questui.description.task8.completed": "A secret lair in the Coffee Shop? That sounds scary. I'll alert the EPF!",
  "w.app.generic.questui.description.task9.completed": "Excellent work! Herbert may have gotten away, but we've hopefully set him back just enough to not spoil the rest of our Halloween fun!"
};

const HALLOWEEN_2015_ROOMS = {
  "beach": ref('rooms/Hallo15_beach.swf'), "beacon": ref('rooms/Hallo15_beacon.swf'), "book": ref('rooms/Hallo15_book.swf'), "cave": ref('rooms/Hallo15_cave.swf'),
  "shop": ref('rooms/Hallo15_shop.swf'), "cloudforest": ref('rooms/Hallo15_cloudforest.swf'), "coffee": ref('rooms/Hallo15_coffee.swf'), "cove": ref('rooms/Hallo15_cove.swf'),
  "dance": ref('rooms/Hallo15_dance.swf'), "dock": ref('rooms/Hallo15_dock.swf'), "dojo": ref('rooms/Hallo15_dojo.swf'), "dojoext": ref('rooms/Hallo15_dojoext.swf'),
  "agentlobbymulti": ref('rooms/Hallo15_agentlobbymulti.swf'), "dojofire": ref('rooms/Hallo15_dojofire.swf'), "forest": ref('rooms/Hallo15_forest.swf'),
  "party1": ref('rooms/Hallo15_party1.swf'), "party2": ref('rooms/Hallo15_party2.swf'), "berg": ref('rooms/Hallo15_berg.swf'), "light": ref('rooms/Hallo15_light.swf'),
  "attic": ref('rooms/Hallo15_attic.swf'), "lounge": ref('rooms/Hallo15_lounge.swf'), "shack": ref('rooms/Hallo15_shack.swf'), "pet": ref('rooms/Hallo15_pet.swf'),
  "pizza": ref('rooms/Hallo15_pizza.swf'), "plaza": ref('rooms/Hallo15_plaza.swf'), "stage": ref('rooms/Hallo15_mall.swf'), "hotellobby": ref('rooms/Hallo15_hotellobby.swf'),
  "hotelroof": ref('rooms/Hallo15_hotelroof.swf'), "hotelspa": ref('rooms/Hallo15_hotelspa.swf'), "pufflepark": ref('rooms/Hallo15_park.swf'),
  "pufflewild": ref('rooms/Hallo15_pufflewild.swf'), "eco": ref('rooms/Hallo15_school.swf'), "skatepark": ref('rooms/Hallo15_skatepark.swf'), "mtn": ref('rooms/Hallo15_mtn.swf'),
  "lodge": ref('rooms/Hallo15_lodge.swf'), "village": ref('rooms/Hallo15_village.swf'), "dojosnow": ref('rooms/Hallo15_dojosnow.swf'), "forts": ref('rooms/Hallo15_forts.swf'),
  "rink": ref('rooms/Hallo15_rink.swf'), "town": ref('rooms/RoomsTown-HalloweenParty2015.swf')
};

const HALLOWEEN_2015_MUSIC = {
  "beach":1054,"beacon":1053,"book":669,"cave":532,"shop":345,"cloudforest":1044,"coffee":1031,"cove":1035,"dance":1036,"dock":1037,"dojo":403,
  "dojoext":1045,"agentlobbymulti":922,"dojofire":1046,"forest":1038,"party1":838,"party2":1058,"berg":1043,"light":588,"attic":884,"lounge":1055,
  "shack":1041,"pet":659,"pizza":1033,"plaza":1052,"stage":1032,"hotellobby":1048,"hotelroof":1049,"hotelspa":1050,"pufflepark":1051,"pufflewild":1057,
  "eco":1040,"skatepark":1034,"mtn":1042,"lodge":1056,"village":1042,"dojosnow":1047,"forts":1039,"rink":1067,"town":1052
};

const HALLOWEEN_2015_MUSIC_IDS = [345,403,532,588,659,669,838,884,922,1031,1032,1033,1034,1035,1036,1037,1038,1039,1040,1041,1042,1043,1044,1045,1046,1047,1048,1049,1050,1051,1052,1053,1054,1055,1056,1057,1058,1067];
const HALLOWEEN_2015_DIALOGUE_FILES = ["dialogue_login","dialogue_AA_start","dialogue_AA_instruct","dialogue_AA_congrats","dialogue_Cad_start","dialogue_Cad_instruct","dialogue_Cad_congrats","dialogue_Dot_start","dialogue_Dot_instruct","dialogue_Dot_congrats","dialogue_PH_start","dialogue_PH_instruct","dialogue_PH_congrats","dialogue_RH_start","dialogue_RH_instruct","dialogue_RH_congrats","dialogue_Rook_start","dialogue_Rook_instruct","dialogue_Rook_congrats","dialogue_Rookie_bot","dialogue_Sen_start","dialogue_Sen_instruct","dialogue_Sen_congrats","dialogue_Gary_instruct","dialogue_Gary_instruct_2","dialogue_Gary_instruct_3","dialogue_Gary_lair","dialogue_Gary_congrats","dialogue_Gary_final","dialogue_Herbert_caged","dialogue_Herbert_escape","dialogue_Herbot","dialogue_Herbert_monologue","dialogue_Herbert_monologue_2"] as const;
const dialogueGlobalChanges = Object.fromEntries(HALLOWEEN_2015_DIALOGUE_FILES.map(name => [`close_ups/${name}.swf`, [ref(`close_ups/Hallo15_${name}.swf`), `w.app.p2015.halloween.${name}`]]));
const dialogueLocalChanges = Object.fromEntries(HALLOWEEN_2015_DIALOGUE_FILES.map(name => [`close_ups/${name}.swf`, { en: ref(`close_ups/Hallo15_${name}.swf`) }]));
const tileGlobalChanges = Object.fromEntries(Array.from({length:9},(_,i)=>[`close_ups/tiles_minigame${i}.swf`,[ref(`close_ups/Close_upsTiles_minigame${i}-HalloweenParty2015.swf`),`w.app.p2015.halloween.tiles${i}`]]));
const tileLocalChanges = Object.fromEntries(Array.from({length:9},(_,i)=>[`close_ups/tiles_minigame${i}.swf`,{en:ref(`close_ups/Close_upsTiles_minigame${i}-HalloweenParty2015.swf`)}]));
const musicFileChanges = Object.fromEntries(HALLOWEEN_2015_MUSIC_IDS.map(id=>[`play/v2/content/global/music/${id}.swf`,ref(`music/Music${id}.swf`)]));

export const UPDATES_2015: Update[] = [
  { date:'2015-05-01', rooms:{ lake:'archives:RoomsLake-May2015.swf' } },
  {
    date:'2015-10-21',
    temp:{ party:{
      partyName:'Halloween Party 2015',
      // Halloween's Features SWF uses the late-2015 templated PartyJSON API; MayParty cannot parse it.
      activeFeatures:'20151101',
      gameStringChanges:HALLOWEEN_2015_DIALOGUE_STRINGS,
      partyProgress:{ id:'halloween-2015', messageCount:10, communicatorMessageCount:5, taskCount:10, maxCoinUpdate:10,
        service:{ partyStartDate:'2015-10-21 00:00:00', partyEndDate:'2015-11-05 00:00:00', unlockDayIndex:16, numOfDaysInParty:16 } },
      rooms:HALLOWEEN_2015_ROOMS,
      music:HALLOWEEN_2015_MUSIC,
      fileChanges:{
        'play/v2/content/global/content/party.swf':ref('content/party-runtime-2015.swf'),
        // A 2012 update left its approximation shell persistent; restore the preserved late-AS3 shell for 2015.
        'play/v2/client/shell.swf':'svanilla:media/play/v2/client/shell.swf',
        // Use the actual vanilla intro module. Never alias this to world.swf:
        // loading world as a child starts a second internal client/session.
        'play/v2/client/intro_to_cp.swf':'svanilla:media/play/v2/client/intro_to_cp.swf',
        'play/v2/client/QuestCommunicator.swf':ref('client/QuestCommunicator.swf'),
        'play/v2/client/interface.swf':ref('client/ClientInterface-HalloweenParty2015.swf'),
        'play/v2/content/global/content/interface.swf':ref('client/ClientInterface-HalloweenParty2015.swf'),
        'play/v2/content/global/content/features.swf':ref('content/ContentFeatures-HalloweenParty2015.swf'),
        'play/v2/content/global/content/party_icon.swf':ref('content/ContentParty_icon-HalloweenParty2015.swf'),
        'play/v2/content/global/logo/logo.swf':ref('content/ContentLogo-HalloweenParty2015.swf'),
        'play/v2/content/global/avatar/sprites/robot.swf':ref('avatar/PenguinRobot.swf'),
        'play/v2/content/global/avatar/sprites/penguin_robot.swf':ref('avatar/PenguinRobot.swf'),
        'play/v2/content/global/telescope/telescope.swf':ref('other/Telescope-HalloweenParty2015.swf'),
        'play/v2/content/global/binoculars/binoculars.swf':ref('other/Binoculars-HalloweenParty2015.swf'),
        'play/v2/content/global/rooms/mall.swf':ref('rooms/Hallo15_mall.swf'),
        // Late-AS3 asks for this independent room overlay on room joins.
        'play/v2/content/global/rooms/NOTLS-ALL-EN.swf':'svanilla:media/play/v2/content/global/rooms/NOTLS-ALL-EN.swf',
        'play/v2/content/global/rooms/school.swf':ref('rooms/Hallo15_school.swf'),
        'play/v2/content/global/rooms/park.swf':ref('rooms/Hallo15_park.swf'),
        'play/v2/content/global/rooms/partysolo1.swf':ref('rooms/Hallo15_partysolo1.swf'),
        'play/v2/content/global/membership/party1.swf':ref('membership/MembershipParty1-HalloweenParty2015.swf'),
        'play/v2/content/global/membership/party2.swf':ref('membership/MembershipParty2-HalloweenParty2015.swf'),
        ...musicFileChanges
      },
      globalChanges:{
        'content/party_icon.swf':[ref('content/ContentParty_icon-HalloweenParty2015.swf'),'party_icon','scavenger_hunt_icon'],
        'avatar/sprites/robot.swf':[ref('avatar/PenguinRobot.swf'),'robot_tf','w.avatarSprite.robot'],
        'close_ups/quest_interface.swf':[ref('close_ups/Close_upsQuest_interface-HalloweenParty2015.swf'),'w.p2015.may.partyinterface','w.app.generic.partyinterface','scavenger_hunt'],
        'close_ups/halloLogin.swf':[ref('close_ups/Hallo15_dialogue_login.swf'),'w.p2015.may.login','w.app.loginprompt'],
        ...dialogueGlobalChanges,...tileGlobalChanges,
        'close_ups/tiles_minigame8v2.swf':[ref('close_ups/Close_upsTiles_minigame8-HalloweenParty2015.swf'),'halloHerbertGame'],
        'close_ups/halloHerbertMonologue.swf':[ref('close_ups/Hallo15_dialogue_Herbert_monologue.swf'),'halloHerbertMonologue'],
        'close_ups/halloHerbertMonologue2.swf':[ref('close_ups/Hallo15_dialogue_Herbert_monologue_2.swf'),'halloHerbertMonologue2'],
        'close_ups/halloHerbot.swf':[ref('close_ups/Hallo15_dialogue_Herbot.swf'),'halloHerbot'],
        'close_ups/halloHerbertCage.swf':[ref('close_ups/Hallo15_dialogue_Herbert_caged.swf'),'halloHerbertCage'],
        'close_ups/halloGaryLair.swf':[ref('close_ups/Hallo15_dialogue_Gary_lair.swf'),'halloGaryLair'],
        'close_ups/halloHerbertGetaway.swf':[ref('close_ups/Hallo15_dialogue_Herbert_escape.swf'),'halloHerbertGetaway'],
        'close_ups/halloGaryFinal.swf':[ref('close_ups/Hallo15_dialogue_Gary_final.swf'),'halloGaryFinal']
      },
      localChanges:{
        'close_ups/quest_interface.swf':{en:ref('close_ups/Close_upsQuest_interface-HalloweenParty2015.swf')},
        'close_ups/halloLogin.swf':{en:ref('close_ups/Hallo15_dialogue_login.swf')},
        ...dialogueLocalChanges,...tileLocalChanges,
        'membership/party1.swf':{en:ref('membership/MembershipParty1-HalloweenParty2015.swf')},
        'membership/party2.swf':{en:ref('membership/MembershipParty2-HalloweenParty2015.swf')}
      }
    }}
  },
  { date:'2015-11-05', end:['party'] }
];