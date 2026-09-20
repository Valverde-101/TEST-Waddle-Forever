import { Update } from ".";

const F = 'fair2015:';
const fairRef = (relative: string) => F + relative;

const P = 'party2015:';
const ref = (relative: string) => P + relative;

const FAIR_2015_ROOMS = {
  'beach': fairRef('rooms/RoomsBeach-TheFair2015.swf'),
  'beacon': fairRef('rooms/RoomsBeacon-TheFair2015.swf'),
  'book': fairRef('rooms/RoomsBook-TheFair2015.swf'),
  'shop': fairRef('rooms/RoomsShop-TheFair2015.swf'),
  'cloudforest': fairRef('rooms/RoomsCloudforest-TheFair2015.swf'),
  'coffee': fairRef('rooms/RoomsCoffee-TheFair2015.swf'),
  'cove': fairRef('rooms/RoomsCove-TheFair2015.swf'),
  'dock': fairRef('rooms/RoomsDock-TheFair2015.swf'),
  'dojo': fairRef('rooms/RoomsDojo-TheFair2015.swf'),
  'dojoext': fairRef('rooms/RoomsDojoext-TheFair2015.swf'),
  'agentlobbymulti': fairRef('rooms/TheFair2014EverydayPhoningFacility.swf'),
  'dojofire': fairRef('rooms/RoomsDojofire-TheFair2015.swf'),
  'forest': fairRef('rooms/RoomsForest-TheFair2015.swf'),
  'hotellobby': fairRef('rooms/RoomsHotellobby-TheFair2015.swf'),
  'hotelroof': fairRef('rooms/RoomsHotelroof-TheFair2015.swf'),
  'hotelspa': fairRef('rooms/RoomsHotelspa-TheFair2015.swf'),
  'berg': fairRef('rooms/RoomsBerg-TheFair2015.swf'),
  'light': fairRef('rooms/RoomsLight-TheFair2015.swf'),
  'attic': fairRef('rooms/RoomsAttic-TheFair2015.swf'),
  'shack': fairRef('rooms/RoomsShack-TheFair2015.swf'),
  'pet': fairRef('rooms/RoomsPet-TheFair2015.swf'),
  'pizza': fairRef('rooms/RoomsPizza-TheFair2015.swf'),
  'plaza': fairRef('rooms/RoomsPlaza-TheFair2015.swf'),
  'pufflepark': fairRef('rooms/RoomsPark-TheFair2015.swf'),
  'pufflewild': fairRef('rooms/RoomsPufflewild-TheFair2015.swf'),
  'eco': fairRef('rooms/RoomsSchool-TheFair2015.swf'),
  'skatepark': fairRef('rooms/RoomsSkatepark-TheFair2015.swf'),
  'mtn': fairRef('rooms/RoomsMtn-TheFair2015.swf'),
  'lodge': fairRef('rooms/RoomsLodge-TheFair2015.swf'),
  'village': fairRef('rooms/RoomsVillage-TheFair2015.swf'),
  'dojosnow': fairRef('rooms/RoomsDojosnow-TheFair2015.swf'),
  'forts': fairRef('rooms/RoomsForts-TheFair2015.swf'),
  'rink': fairRef('rooms/RoomsRink-TheFair2015.swf'),
  'town': fairRef('rooms/RoomsTown-TheFair2015.swf'),
  'party10': fairRef('rooms/RoomsParty10-TheFair2015.swf'),
  'party7': fairRef('rooms/RoomsParty7-TheFair2015.swf'),
  'party6': fairRef('rooms/RoomsParty6-TheFair2015.swf'),
  'party2': fairRef('rooms/RoomsParty2-TheFair2015.swf'),
  'party9': fairRef('rooms/RoomsParty9-TheFair2015.swf'),
  'party12': fairRef('rooms/RoomsParty12-TheFair2015.swf'),
  'party11': fairRef('rooms/RoomsParty11-TheFair2015.swf'),
  'party1': fairRef('rooms/RoomsParty1-TheFair2015.swf'),
  'party4': fairRef('rooms/RoomsParty4-TheFair2015.swf'),
  'party5': fairRef('rooms/RoomsParty5-TheFair2015.swf'),
  'party3': fairRef('rooms/RoomsParty3-TheFair2015.swf'),
  'party8': fairRef('rooms/RoomsParty8-TheFair2015.swf'),
};

const FAIR_2015_MUSIC = {
  'beach': 582,
  'beacon': 583,
  'book': 669,
  'shop': 345,
  'cloudforest': 363,
  'coffee': 429,
  'cove': 579,
  'dock': 611,
  'dojo': 403,
  'dojoext': 404,
  'agentlobbymulti': 7,
  'dojofire': 405,
  'forest': 586,
  'hotellobby': 362,
  'hotelroof': 360,
  'hotelspa': 361,
  'berg': 584,
  'light': 588,
  'attic': 672,
  'shack': 580,
  'pet': 659,
  'pizza': 676,
  'plaza': 677,
  'pufflepark': 658,
  'pufflewild': 897,
  'eco': 436,
  'skatepark': 754,
  'mtn': 590,
  'lodge': 589,
  'village': 591,
  'dojosnow': 407,
  'forts': 587,
  'rink': 592,
  'town': 581,
  'party10': 610,
  'party7': 607,
  'party6': 606,
  'party2': 602,
  'party9': 609,
  'party12': 918,
  'party11': 917,
  'party1': 601,
  'party4': 604,
  'party5': 605,
  'party3': 603,
  'party8': 608,
};

const FAIR_2015_MUSIC_FILES = {
  'play/v2/content/global/music/7.swf': fairRef('music/Music7.swf'),
  'play/v2/content/global/music/345.swf': fairRef('music/Music345.swf'),
  'play/v2/content/global/music/360.swf': fairRef('music/Music360.swf'),
  'play/v2/content/global/music/361.swf': fairRef('music/Music361.swf'),
  'play/v2/content/global/music/362.swf': fairRef('music/Music362.swf'),
  'play/v2/content/global/music/363.swf': fairRef('music/Music363.swf'),
  'play/v2/content/global/music/403.swf': fairRef('music/Music403.swf'),
  'play/v2/content/global/music/404.swf': fairRef('music/Music404.swf'),
  'play/v2/content/global/music/405.swf': fairRef('music/Music405.swf'),
  'play/v2/content/global/music/407.swf': fairRef('music/Music407.swf'),
  'play/v2/content/global/music/429.swf': fairRef('music/Music429.swf'),
  'play/v2/content/global/music/436.swf': fairRef('music/Music436.swf'),
  'play/v2/content/global/music/579.swf': fairRef('music/Music579.swf'),
  'play/v2/content/global/music/580.swf': fairRef('music/Music580.swf'),
  'play/v2/content/global/music/581.swf': fairRef('music/Music581.swf'),
  'play/v2/content/global/music/582.swf': fairRef('music/Music582.swf'),
  'play/v2/content/global/music/583.swf': fairRef('music/Music583.swf'),
  'play/v2/content/global/music/584.swf': fairRef('music/Music584.swf'),
  'play/v2/content/global/music/586.swf': fairRef('music/Music586.swf'),
  'play/v2/content/global/music/587.swf': fairRef('music/Music587.swf'),
  'play/v2/content/global/music/588.swf': fairRef('music/Music588.swf'),
  'play/v2/content/global/music/589.swf': fairRef('music/Music589.swf'),
  'play/v2/content/global/music/590.swf': fairRef('music/Music590.swf'),
  'play/v2/content/global/music/591.swf': fairRef('music/Music591.swf'),
  'play/v2/content/global/music/592.swf': fairRef('music/Music592.swf'),
  'play/v2/content/global/music/601.swf': fairRef('music/Music601.swf'),
  'play/v2/content/global/music/602.swf': fairRef('music/Music602.swf'),
  'play/v2/content/global/music/603.swf': fairRef('music/Music603.swf'),
  'play/v2/content/global/music/604.swf': fairRef('music/Music604.swf'),
  'play/v2/content/global/music/605.swf': fairRef('music/Music605.swf'),
  'play/v2/content/global/music/606.swf': fairRef('music/Music606.swf'),
  'play/v2/content/global/music/607.swf': fairRef('music/Music607.swf'),
  'play/v2/content/global/music/608.swf': fairRef('music/Music608.swf'),
  'play/v2/content/global/music/609.swf': fairRef('music/Music609.swf'),
  'play/v2/content/global/music/610.swf': fairRef('music/Music610.swf'),
  'play/v2/content/global/music/611.swf': fairRef('music/Music611.swf'),
  'play/v2/content/global/music/658.swf': fairRef('music/Music658.swf'),
  'play/v2/content/global/music/659.swf': fairRef('music/Music659.swf'),
  'play/v2/content/global/music/669.swf': fairRef('music/Music669.swf'),
  'play/v2/content/global/music/672.swf': fairRef('music/Music672.swf'),
  'play/v2/content/global/music/676.swf': fairRef('music/Music676.swf'),
  'play/v2/content/global/music/677.swf': fairRef('music/Music677.swf'),
  'play/v2/content/global/music/754.swf': fairRef('music/Music754.swf'),
  'play/v2/content/global/music/897.swf': fairRef('music/Music897.swf'),
  'play/v2/content/global/music/917.swf': fairRef('music/Music917.swf'),
  'play/v2/content/global/music/918.swf': fairRef('music/Music918.swf'),
};

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

// Original Fair 2015 minigame archive assets, mounted at the URLs requested
// by the late-AS3 game launchers. This is separate from Halloween's game runtime.
const FAIR_2015_MINIGAME_FILES = {
  'play/v2/games/cp_party_games/spin/bootstrap.swf': fairRef('minigames/daily_spin/GamesSpinBootstrap.swf'),
  'play/v2/games/cp_party_games/spin/main.swf': fairRef('minigames/daily_spin/GamesSpinMain.swf'),
  // The archived bootstrap explicitly requests spin.swf (not main.swf).
  'play/v2/games/cp_party_games/spin/spin.swf': fairRef('minigames/daily_spin/GamesSpinMain.swf'),
  // Archived bootstrap requests spin.swf directly, not main.swf.
  'play/v2/games/cp_party_games/spin/spin.swf': fairRef('minigames/daily_spin/GamesSpinMain.swf'),
  'play/v2/games/cp_party_games/spin/lang/en/locale.swf': fairRef('minigames/daily_spin/GamesSpinLangENLocale.swf'),
  'play/v2/games/cp_party_games/spin/lang/en/spin.swf': fairRef('minigames/daily_spin/GamesSpinLangENSpin.swf'),
  'play/v2/games/cp_party_games/spin/lang/en/title.swf': fairRef('minigames/daily_spin/GamesSpinLangENTitle.swf'),
  'play/v2/games/cp_party_games/bell/bootstrap.swf': fairRef('minigames/lunar_launch/GamesBellBootstrap.swf'),
  'play/v2/games/cp_party_games/bell/main.swf': fairRef('minigames/lunar_launch/GamesBellMain.swf'),
  'play/v2/games/cp_party_games/bell/lang/en/locale.swf': fairRef('minigames/lunar_launch/GamesBellLangENLocale.swf'),
  'play/v2/games/cp_party_games/bell/lang/en/title.swf': fairRef('minigames/lunar_launch/GamesBellLangENTitle.swf'),
  'play/v2/games/cp_party_games/paddle/bootstrap.swf': fairRef('minigames/puffle_paddle/GamesPufflePaddle-Bootstrap-TheFair2015.swf'),
  'play/v2/games/cp_party_games/paddle/main.swf': fairRef('minigames/puffle_paddle/GamesPufflePaddle-TheFair2015.swf'),
  'play/v2/games/cp_party_games/shuffle/bootstrap.swf': fairRef('minigames/puffle_shuffle/PuffleShuffleBootstrap.swf'),
  'play/v2/games/cp_party_games/shuffle/lang/en/locale.swf': fairRef('minigames/puffle_shuffle/PuffleShuffleLocale.swf'),
  'play/v2/games/cp_party_games/shuffle/lang/en/title.swf': fairRef('minigames/puffle_shuffle/PuffleShuffle_title.swf'),
  'play/v2/games/cp_party_games/shuffle/lang/en/sign.swf': fairRef('minigames/puffle_shuffle/PuffleShuffleSign.swf'),
  'play/v2/games/cp_party_games/bounce/main.swf': fairRef('minigames/super_hero_bounce/GamesCpPartyGamesBounceMain.swf'),
  'play/v2/games/cp_party_games/bounce/lang/en/locale.swf': fairRef('minigames/super_hero_bounce/GamesChaseLangEnLocale.swf'),
  'play/v2/games/cp_party_games/spin/lang/de/locale.swf': fairRef('minigames/daily_spin/GamesSpinLangDELocale.swf'),
  'play/v2/games/cp_party_games/spin/lang/de/spin.swf': fairRef('minigames/daily_spin/GamesSpinLangDESpin.swf'),
  'play/v2/games/cp_party_games/spin/lang/de/title.swf': fairRef('minigames/daily_spin/GamesSpinLangDETitle.swf'),
  'play/v2/games/cp_party_games/bell/lang/de/locale.swf': fairRef('minigames/lunar_launch/GamesBellLangDELocale.swf'),
  'play/v2/games/cp_party_games/bell/lang/de/title.swf': fairRef('minigames/lunar_launch/GamesBellLangDETitle.swf'),
  'play/v2/games/cp_party_games/spin/lang/es/locale.swf': fairRef('minigames/daily_spin/GamesSpinLangESLocale.swf'),
  'play/v2/games/cp_party_games/spin/lang/es/spin.swf': fairRef('minigames/daily_spin/GamesSpinLangESSpin.swf'),
  'play/v2/games/cp_party_games/spin/lang/es/title.swf': fairRef('minigames/daily_spin/GamesSpinLangESTitle.swf'),
  'play/v2/games/cp_party_games/bell/lang/es/locale.swf': fairRef('minigames/lunar_launch/GamesBellLangESLocale.swf'),
  'play/v2/games/cp_party_games/bell/lang/es/title.swf': fairRef('minigames/lunar_launch/GamesBellLangESTitle.swf'),
  'play/v2/games/cp_party_games/spin/lang/fr/locale.swf': fairRef('minigames/daily_spin/GamesSpinLangFRLocale.swf'),
  'play/v2/games/cp_party_games/spin/lang/fr/spin.swf': fairRef('minigames/daily_spin/GamesSpinLangFRSpin.swf'),
  'play/v2/games/cp_party_games/spin/lang/fr/title.swf': fairRef('minigames/daily_spin/GamesSpinLangFRTitle.swf'),
  'play/v2/games/cp_party_games/bell/lang/fr/locale.swf': fairRef('minigames/lunar_launch/GamesBellLangFRLocale.swf'),
  'play/v2/games/cp_party_games/bell/lang/fr/title.swf': fairRef('minigames/lunar_launch/GamesBellLangFRTitle.swf'),
  'play/v2/games/cp_party_games/spin/lang/pt/locale.swf': fairRef('minigames/daily_spin/GamesSpinLangPTLocale.swf'),
  'play/v2/games/cp_party_games/spin/lang/pt/spin.swf': fairRef('minigames/daily_spin/GamesSpinLangPTSpin.swf'),
  'play/v2/games/cp_party_games/spin/lang/pt/title.swf': fairRef('minigames/daily_spin/GamesSpinLangPTTitle.swf'),
  'play/v2/games/cp_party_games/bell/lang/pt/locale.swf': fairRef('minigames/lunar_launch/GamesBellLangPTLocale.swf'),
  'play/v2/games/cp_party_games/bell/lang/pt/title.swf': fairRef('minigames/lunar_launch/GamesBellLangPTTitle.swf'),
  'play/v2/games/cp_party_games/spin/lang/ru/locale.swf': fairRef('minigames/daily_spin/GamesSpinLangRULocale.swf'),
  'play/v2/games/cp_party_games/spin/lang/ru/spin.swf': fairRef('minigames/daily_spin/GamesSpinLangRUSpin.swf'),
  'play/v2/games/cp_party_games/spin/lang/ru/title.swf': fairRef('minigames/daily_spin/GamesSpinLangRUTitle.swf'),
  'play/v2/games/cp_party_games/bell/lang/ru/locale.swf': fairRef('minigames/lunar_launch/GamesBellLangRULocale.swf'),
  'play/v2/games/cp_party_games/bell/lang/ru/title.swf': fairRef('minigames/lunar_launch/GamesBellLangRUTitle.swf'),
  'play/v2/content/global/music/618.swf': fairRef('minigames/daily_spin/Music618.swf'),
  'play/v2/content/global/music/614.swf': fairRef('minigames/lunar_launch/Music614.swf'),
  'play/v2/content/global/music/222.swf': fairRef('minigames/puffle_shuffle/Music222.swf'),
  'play/v2/content/global/music/395.swf': fairRef('minigames/super_hero_bounce/Music395.swf'),
  'play/v2/games/cp_party_games/bounce/launcher.swf': fairRef('minigames/super_hero_bounce/ClientGame_launcher_3.swf'),
  'play/v2/games/cp_party_games/balloon_pop/main.swf': fairRef('minigames/balloon_pop/BalloonPop.swf'),
  'play/v2/games/cp_party_games/feed_a_puffle/main.swf': fairRef('minigames/feed_a_puffle/Feed-A-Puffle.swf'),
  'play/v2/games/cp_party_games/memory_card_game/main.swf': fairRef('minigames/memory_card_game/MemoryCardGame.swf'),
  'play/v2/games/cp_party_games/puffle_soaker/main.swf': fairRef('minigames/puffle_soaker/PuffleSoaker.swf'),
  'play/v2/games/cp_party_games/spin/game.swf': fairRef('minigames/daily_spin/Grab&Spin.swf'),
  'play/v2/games/cp_party_games/bell/game.swf': fairRef('minigames/lunar_launch/RingTheBell.swf')
};

export const UPDATES_2015: Update[] = [
  { date:'2015-05-01', rooms:{ lake:'archives:RoomsLake-May2015.swf' } },
  {
    date: '2015-05-20',
    temp: { party: {
      partyName: 'The Fair 2015',
      // Historical Fair cookie namespace 20150501: separate tickets/spin from Halloween.
      activeFeatures: '20150501',
      partyProgress: {
        id: 'fair-2015', messageCount: 2, communicatorMessageCount: 0,
        taskCount: 0, maxCoinUpdate: 0, ticketBased: true,
        service: { partyStartDate: '2015-05-20 00:00:00', partyEndDate: '2015-06-11 00:00:00', unlockDayIndex: 22, numOfDaysInParty: 22 }
      },
      // Fair's own copy of the native dialogue keys; not Halloween quest text.
      gameStringChanges: {
        'w.p2015.may.dialogue.login': "Welcome to the Fair. Come to the Docks for fun games, crazy\nrides, and wacky prizes! There's a plunger hat and everything!",
        'w.p2015.may.dialogue.dailyspin.member': "Take a spin every day to wins items, coins, or silver tickets!\n\nWin a silver ticket and you get a bonus 1,000 coins!"
      },
      // Do not reuse Halloween's party runtime, robot state or quest protocol.
      // These original 2015 SWFs form the visual/room layer. Fair ticket,
      // daily-spin and prize transactions need their own protocol evidence.
      rooms: FAIR_2015_ROOMS,
      music: FAIR_2015_MUSIC,
      fileChanges: {
        // Mounted only in Fair's temporary update (May 20 to June 11, 2015).
        'play/v2/content/global/content/party.swf': fairRef('cpimagined/content/party.swf'),
        // CPImagined's supplemental map is a snow-season bitmap, not the May 2015
        // island map. Keep the modern island map independent of Fair's event
        // close-up, which the preserved party_map + party_map_note SWFs open.
        'play/v2/content/global/content/map.swf': 'approximation:modern_map.swf',
        'play/v2/content/global/content/room_pin/7236.swf': fairRef('cpimagined/content/room_pin/7236.swf'),
        'play/v2/client/shell.swf': 'svanilla:media/play/v2/client/shell.swf',
        'play/v2/client/interface.swf': fairRef('client/ClientInterfaceFair2015.swf'),
        'play/v2/content/global/content/interface.swf': fairRef('client/ClientInterfaceFair2015.swf'),
        'play/v2/content/global/content/party_icon.swf': fairRef('content/ContentParty_icon-TheFair2015.swf'),
        'play/v2/content/global/scavenger_hunt/scavenger_hunt_icon.swf': fairRef('content/ContentParty_icon-TheFair2015.swf'),
        // QuestCommunicator is a shared late-AS3 client module, not Halloween event art.
        'play/v2/client/QuestCommunicator.swf': ref('client/QuestCommunicator.swf'),
        'play/v2/content/global/logo/logo.swf': fairRef('content/ContentLogo-TheFair2015.swf'),
        'play/v2/content/global/membership/party1.swf': fairRef('membership/MembershipParty1-TheFair2015.swf'),
        'play/v2/content/global/membership/party2.swf': fairRef('membership/MembershipParty2-TheFair2015.swf'),
        'play/v2/content/global/rooms/effects/boatback.swf': fairRef('effects/RoomsEffectsBoatback-TheFair2015.swf'),
        'play/v2/content/global/rooms/effects/boatfront.swf': fairRef('effects/RoomsEffectsBoatfront-TheFair2015.swf'),
        'play/v2/content/global/rooms/effects/pixelpenguin.swf': fairRef('effects/RoomsEffectsPixelpenguin-TheFair2015.swf'),
        'play/v2/content/global/avatar/sprites/crab.swf': fairRef('avatar/AvatarSpritesCrab.swf'),
        'play/v2/content/global/avatar/sprites/dragon.swf': fairRef('avatar/AvatarSpritesDragon.swf'),
        'play/v2/content/global/avatar/sprites/robotcgrey.swf': fairRef('avatar/AvatarSpritesRobotCGrey.swf'),
        'play/v2/content/global/avatar/sprites/werewolf.swf': fairRef('avatar/AvatarSpritesWerewolf.swf'),
        ...FAIR_2015_MUSIC_FILES,
        ...FAIR_2015_MINIGAME_FILES
      },
      globalChanges: {
        'content/party_icon.swf': [fairRef('content/ContentParty_icon-TheFair2015.swf'), 'party_icon', 'scavenger_hunt_icon'],
        'close_ups/quest_interface.swf': [fairRef('close_ups/CloseUpsEN-QuestInterface-TheFair2015.swf'), 'w.p2015.may.partyinterface', 'w.app.generic.partyinterface', 'scavenger_hunt'],
        // Exact showContent identifiers referenced by the original MayPartyConstants.
        // The localChanges below already covers the direct close-up paths, but
        // none of these interactive showContent keys worked through that route.
        'close_ups/dialog_rookie_login.swf': [fairRef('close_ups/CloseUps-DialogueRookieLogin-TheFair2015.swf'), 'w.p2015.may.login'],
        'close_ups/party_map.swf': [fairRef('close_ups/ENCloseUpsPartyMap-TheFair2015.swf'), 'w.p2015.may.partymap', 'party_map'],
        'close_ups/party_map_note.swf': [fairRef('close_ups/ENCloseUpsPartyMapNote-TheFair2015.swf'), 'party_map_note'],
        'close_ups/ride_prompt.swf': [fairRef('close_ups/ENCloseUpsRidePrompt-TheFair2015.swf'), 'w.p2015.may.rideprompt', 'ride_prompt'],
        // Historical Fair paths.json maps these exact MayParty avatar tokens.
        // "coyote" intentionally points at werewolf.swf in the original config.
        'avatar/sprites/werewolf.swf': [fairRef('avatar/AvatarSpritesWerewolf.swf'), 'w.avatarSprite.coyote'],
        'avatar/sprites/crab.swf': [fairRef('avatar/AvatarSpritesCrab.swf'), 'w.avatarSprite.crab'],
        'avatar/sprites/dragon.swf': [fairRef('avatar/AvatarSpritesDragon.swf'), 'w.avatarSprite.dragon'],
        'avatar/sprites/robotcgrey.swf': [fairRef('avatar/AvatarSpritesRobotCGrey.swf'), 'w.avatarSprite.robo']
      },
      localChanges: {
        'close_ups/quest_interface.swf': { en: fairRef('close_ups/CloseUpsEN-QuestInterface-TheFair2015.swf') },
        'close_ups/party_map.swf': { en: fairRef('close_ups/ENCloseUpsPartyMap-TheFair2015.swf') },
        'close_ups/party_map_note.swf': { en: fairRef('close_ups/ENCloseUpsPartyMapNote-TheFair2015.swf') },
        'close_ups/ride_prompt.swf': { en: fairRef('close_ups/ENCloseUpsRidePrompt-TheFair2015.swf') },
        'close_ups/dialog_rookie_login.swf': { en: fairRef('close_ups/CloseUps-DialogueRookieLogin-TheFair2015.swf') },
        'close_ups/dialog_rookie_firstdailyspin_login.swf': { en: fairRef('close_ups/CloseUpsDialogRookieFirstdailyspinLogin-TheFair2015.swf') }
      }
    } }
  },
  { date: '2015-06-11', end: ['party'] },
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
        // Do NOT mount the archived recreation game_configs.bin here.
        // The known-good Halloween runtime intentionally lets this optional bundle
        // miss, then loads Waddle's generated chunked config JSON. Mounting the
        // recreation bundle replaces our timeline rooms/music/paths wholesale
        // (for example it advertises unpreserved 2048-2053 music) and breaks the
        // party icon/robot quest bootstrap even though the SWFs themselves resolve.
        // A 2012 update left its approximation shell persistent; restore the preserved late-AS3 shell for 2015.
        'play/v2/client/shell.swf':'svanilla:media/play/v2/client/shell.swf',
        // Never substitute intro_to_cp with world.swf: loading world as a child
        // starts a second internal client/session. The exact intro module is being
        // recovered from the pinned media archive below, so do not advertise a
        // nonexistent local target in the meantime.
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
        // Exact all-episodes Night of the Living Sled from the pinned source;
        // never substitute the episode-3-only SWF.
        'play/v2/content/global/rooms/NOTLS-ALL-EN.swf':ref('rooms/NOTLS-ALL-EN.swf'),
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