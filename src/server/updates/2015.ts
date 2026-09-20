import { CPUpdate, Update } from ".";

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


// Holiday 2015 uses its own archive namespace. Reuse only the genuinely generic
// late-AS3 transport (shell, QuestCommunicator and party-cookie runtime); never
// serve Halloween or Fair interfaces, rooms, quest cards, maps or game strings.
const holidayRef = (relative: string) => 'holiday2015:' + relative;
const HOLIDAY_2015_ROOMS = {
  "agentlobbymulti": holidayRef("party/rooms/RoomsAgentlobbymulti-HolidayParty2015.swf"),
  "attic": holidayRef("party/rooms/RoomsAttic-HolidayParty2015.swf"),
  "beach": holidayRef("party/rooms/RoomsBeach-HolidayParty2015.swf"),
  "beacon": holidayRef("party/rooms/RoomsBeacon-HolidayParty2015.swf"),
  "berg": holidayRef("party/rooms/RoomsBerg-HolidayParty2015.swf"),
  "book": holidayRef("party/rooms/RoomsBook-HolidayParty2015.swf"),
  "cloudforest": holidayRef("party/rooms/RoomsCloudforest-HolidayParty2015.swf"),
  "coffee": holidayRef("party/rooms/RoomsCoffee-HolidayParty2015.swf"),
  "cove": holidayRef("party/rooms/RoomsCove-HolidayParty2015.swf"),
  "dance": holidayRef("party/rooms/RoomsDance-HolidayParty2015.swf"),
  "dock": holidayRef("party/rooms/RoomsDock-HolidayParty2015.swf"),
  "dojo": holidayRef("party/rooms/RoomsDojo-HolidayParty2015.swf"),
  "dojoext": holidayRef("party/rooms/RoomsDojoext-HolidayParty2015.swf"),
  "dojofire": holidayRef("party/rooms/RoomsDojofire-HolidayParty2015.swf"),
  "dojosnow": holidayRef("party/rooms/RoomsDojosnow-HolidayParty2015.swf"),
  "forest": holidayRef("party/rooms/RoomsForest-HolidayParty2015.swf"),
  "forts": holidayRef("party/rooms/RoomsForts-HolidayParty2015.swf"),
  "hotellobby": holidayRef("party/rooms/RoomsHotellobby-HolidayParty2015.swf"),
  "hotelroof": holidayRef("party/rooms/RoomsHotelroof-HolidayParty2015.swf"),
  "hotelspa": holidayRef("party/rooms/RoomsHotelspa-HolidayParty2015.swf"),
  "light": holidayRef("party/rooms/RoomsLight-HolidayParty2015.swf"),
  "lodge": holidayRef("party/rooms/RoomsLodge-HolidayParty2015.swf"),
  "lounge": holidayRef("party/rooms/RoomsLounge-HolidayParty2015.swf"),
  "stage": holidayRef("party/rooms/RoomsMall-HolidayParty2015.swf"),
  "mall": holidayRef("party/rooms/RoomsMall-HolidayParty2015.swf"),
  "mtn": holidayRef("party/rooms/RoomsMtn-HolidayParty2015.swf"),
  "park": holidayRef("party/rooms/RoomsPark-HolidayParty2015.swf"),
  "pufflepark": holidayRef("party/rooms/RoomsPark-HolidayParty2015.swf"),
  "party1": holidayRef("party/rooms/RoomsParty1-HolidayParty2015.swf"),
  "party13": holidayRef("party/rooms/RoomsParty13-HolidayParty2015.swf"),
  "party14": holidayRef("party/rooms/RoomsParty14-HolidayParty2015.swf"),
  "party2": holidayRef("party/rooms/RoomsParty2-HolidayParty2015.swf"),
  "party3": holidayRef("party/rooms/RoomsParty3-HolidayParty2015.swf"),
  "party4": holidayRef("party/rooms/RoomsParty4-HolidayParty2015.swf"),
  "pet": holidayRef("party/rooms/RoomsPet-HolidayParty2015.swf"),
  "pizza": holidayRef("party/rooms/RoomsPizza-HolidayParty2015.swf"),
  "plaza": holidayRef("party/rooms/RoomsPlaza-HolidayParty2015.swf"),
  "pufflewild": holidayRef("party/rooms/RoomsPufflewild-HolidayParty2015.swf"),
  "rink": holidayRef("party/rooms/RoomsRink-HolidayParty2015.swf"),
  "school": holidayRef("party/rooms/RoomsSchool-HolidayParty2015.swf"),
  "eco": holidayRef("party/rooms/RoomsSchool-HolidayParty2015.swf"),
  "shack": holidayRef("party/rooms/RoomsShack-HolidayParty2015.swf"),
  "ship": holidayRef("party/rooms/RoomsShip-HolidayParty2015.swf"),
  "shiphold": holidayRef("party/rooms/RoomsShiphold-HolidayParty2015.swf"),
  "shipnest": holidayRef("party/rooms/RoomsShipnest-HolidayParty2015.swf"),
  "shipquarters": holidayRef("party/rooms/RoomsShipquarters-HolidayParty2015.swf"),
  "shop": holidayRef("party/rooms/RoomsShop-HolidayParty2015.swf"),
  "skatepark": holidayRef("party/rooms/RoomsSkatepark-HolidayParty2015.swf"),
  "town": holidayRef("party/rooms/RoomsTown-HolidayParty2015.swf"),
  "village": holidayRef("party/rooms/RoomsVillage-HolidayParty2015.swf")
};
const HOLIDAY_2015_MUSIC = {
  "agentlobbymulti": 922,
  "attic": 884,
  "beach": 1068,
  "beacon": 583,
  "berg": 1069,
  "book": 1070,
  "cloudforest": 363,
  "coffee": 1070,
  "cove": 1071,
  "dance": 1087,
  "dock": 1072,
  "dojo": 403,
  "dojoext": 404,
  "dojofire": 405,
  "dojosnow": 407,
  "forest": 1088,
  "forts": 1073,
  "hotellobby": 362,
  "hotelroof": 360,
  "hotelspa": 361,
  "light": 588,
  "lodge": 1074,
  "lounge": 1075,
  "stage": 1076,
  "mall": 1076,
  "mtn": 1077,
  "park": 658,
  "pufflepark": 658,
  "party13": 1091,
  "party14": 1080,
  "pet": 659,
  "pizza": 1081,
  "plaza": 1089,
  "pufflewild": 897,
  "rink": 592,
  "school": 1085,
  "eco": 1085,
  "shack": 1090,
  "ship": 1082,
  "shiphold": 1083,
  "shipnest": 1082,
  "shipquarters": 1083,
  "shop": 1086,
  "skatepark": 754,
  "town": 1084,
  "village": 1077
};
const HOLIDAY_2015_MUSIC_FILES = {
  "360": holidayRef("party/music/Music360.swf"),
  "361": holidayRef("party/music/Music361.swf"),
  "362": holidayRef("party/music/Music362.swf"),
  "363": holidayRef("party/music/Music363.swf"),
  "403": holidayRef("party/music/Music403.swf"),
  "404": holidayRef("party/music/Music404.swf"),
  "405": holidayRef("party/music/Music405.swf"),
  "407": holidayRef("party/music/Music407.swf"),
  "583": holidayRef("party/music/Music583.swf"),
  "588": holidayRef("party/music/Music588.swf"),
  "592": holidayRef("party/music/Music592.swf"),
  "658": holidayRef("party/music/Music658.swf"),
  "659": holidayRef("party/music/Music659.swf"),
  "754": holidayRef("party/music/Music754.swf"),
  "884": holidayRef("party/music/Music884.swf"),
  "897": holidayRef("party/music/Music897.swf"),
  "922": holidayRef("party/music/Music922.swf"),
  "1068": holidayRef("party/music/Music1068_2.swf"),
  "1069": holidayRef("party/music/Music1069.swf"),
  "1070": holidayRef("party/music/Music1070.swf"),
  "1071": holidayRef("party/music/Music1071.swf"),
  "1072": holidayRef("party/music/Music1072.swf"),
  "1073": holidayRef("party/music/Music1073.swf"),
  "1074": holidayRef("party/music/Music1074.swf"),
  "1075": holidayRef("party/music/Music1075.swf"),
  "1076": holidayRef("party/music/Music1076.swf"),
  "1077": holidayRef("party/music/Music1077.swf"),
  "1078": holidayRef("party/music/Music1078.swf"),
  "1080": holidayRef("party/music/Music1080.swf"),
  "1081": holidayRef("party/music/Music1081.swf"),
  "1082": holidayRef("party/music/Music1082.swf"),
  "1083": holidayRef("party/music/Music1083.swf"),
  "1084": holidayRef("party/music/Music1084.swf"),
  "1085": holidayRef("party/music/Music1085.swf"),
  "1086": holidayRef("party/music/Music1086.swf"),
  "1087": holidayRef("party/music/Music1087.swf"),
  "1088": holidayRef("party/music/Music1088.swf"),
  "1089": holidayRef("party/music/Music1089.swf"),
  "1090": holidayRef("party/music/Music1090.swf"),
  "1091": holidayRef("party/music/Music1091.swf")
};
const holidayMusicFiles = Object.fromEntries(Object.entries(HOLIDAY_2015_MUSIC_FILES)
  .map(([id, file]) => [`play/v2/content/global/music/${id}.swf`, file]));

// The original Advent Calendar opens before the decorated party. Its icon and
// close-up must not replace the full penguin interface or persist after 16 Dec.
// The archived Holiday interface and dialogue SWFs reference these exact string
// keys. Content is isolated to Holiday dates; no Halloween generic labels leak
// into the December party. The December UI labels are compatibility copy where
// the complete original 2015 game_strings bundle is not archived.
const HOLIDAY_2015_DIALOGUE_STRINGS: Record<string, string> = {
  'w.app.p2015.december.login1': 'Hello. You can collect free gifts from this calendar. New ones unlock every day until Dec. 25. Happy holidays!',
  'w.app.p2015.december.login2': 'The Holiday Party is here! Open the Calendar to collect gifts and help with Coins for Change.',
  'w.app.generic.questui.header': 'Holiday Party',
  'w.app.generic.questui.subheader1': 'Collect your holiday gifts in the Calendar.',
  'w.app.questui.subheader2': 'Help Coins for Change by earning and donating coins.',
  'w.app.december2015.ui.calendar': 'December',
  'w.app.december2015.ui.calendarbtn': 'Open Calendar',
  'w.app.december2015.ui.donate': 'Donate',
  'w.app.december2015.ui.donations': 'Donations',
  'w.app.december2015.ui.beach': 'Beach',
  'w.app.december2015.ui.forest': 'Forest',
  'w.app.december2015.ui.plaza': 'Plaza',
  'w.app.december2015.ui.furnigloobtn': 'Furniture & Igloo',
  'w.app.december2015.ui.penguinstylebtn': 'Penguin Style'
};

const HOLIDAY_2015_ADVENT: CPUpdate = {
  partyName: 'Advent Calendar 2015',
  decorated: false as const,
  roomComment: 'The 2015 Advent Calendar opens in the Snow Forts',
  gameStringChanges: { 'w.app.p2015.december.login1': HOLIDAY_2015_DIALOGUE_STRINGS['w.app.p2015.december.login1'] },
  rooms: { forts: holidayRef('preparty/rooms/2015AdventCalendarforts.swf') },
  music: { forts: 587 },
  fileChanges: {
    'play/v2/content/global/music/587.swf': holidayRef('preparty/music/Music587.swf'),
    'play/v2/content/global/content/party_icon.swf': holidayRef('preparty/content/2015AdventCalendarpartyicon.swf')
  },
  globalChanges: {
    'content/party_icon.swf': [holidayRef('preparty/content/2015AdventCalendarpartyicon.swf'), 'party_icon'],
    'close_ups/advent_calendar.swf': [holidayRef('preparty/close_ups/2015AdventCalendarinterface.swf'), 'advent_calendar']
  },
  localChanges: {
    'close_ups/advent_calendar.swf': { en: holidayRef('preparty/close_ups/2015AdventCalendarinterface.swf') },
    'close_ups/advent_calendar_login.swf': { en: holidayRef('preparty/close_ups/2015AdventCalendarlogin.swf') },
    'membership/party1.swf': { en: holidayRef('preparty/membership/2015AdventCalendarmembership.swf') }
  }
};
const HOLIDAY_2015_PARTY: CPUpdate = {
  partyName: 'Holiday Party 2015',
  // The original ClientParty SWF defines PARTY_ID_2015_DECEMBERPARTY=20151100.
  // Without an explicit feature ID, Waddle inherits 20141002 from an old party
  // and DecemberParty refuses to activate its icon, map, rooms and dialogues.
  activeFeatures: '20151100',
  gameStringChanges: HOLIDAY_2015_DIALOGUE_STRINGS,
  migrator: true,
  coinsForChange: true,
  // Party cookie uses an independent ID, not Halloween's quest/task state.
  partyProgress: {
    id: 'holiday-2015', messageCount: 3, communicatorMessageCount: 0,
    // ContentFeatures-HolidayParty2015.swf declares numOfQuests=4. The
    // 25 calendar dates are service days, not 25 questTaskStatus entries.
    taskCount: 4, maxCoinUpdate: 10,
    service: {
      partyStartDate: '2015-12-17 00:00:00',
      partyEndDate: '2016-01-07 00:00:00',
      unlockDayIndex: 21,
      numOfDaysInParty: 21
    }
  },
  rooms: HOLIDAY_2015_ROOMS,
  music: HOLIDAY_2015_MUSIC,
  fileChanges: {
    // The Halloween runtime is patched for Robot Rampage and must NEVER
    // bootstrap Holiday. Use the original archived Holiday party logic.
    'play/v2/content/global/content/party.swf': holidayRef('party/client/ClientParty-HolidayParty2015.swf'),
    'play/v2/client/QuestCommunicator.swf': ref('client/QuestCommunicator.swf'),
    'play/v2/client/shell.swf': 'svanilla:media/play/v2/client/shell.swf',
    'play/v2/client/interface.swf': holidayRef('party/client/ClientInterface-HolidayParty2015.swf'),
    'play/v2/client/party.swf': holidayRef('party/client/ClientParty-HolidayParty2015.swf'),
    'play/v2/content/global/content/interface.swf': holidayRef('party/client/ClientInterface-HolidayParty2015.swf'),
    'play/v2/content/global/content/features.swf': holidayRef('party/content/ContentFeatures-HolidayParty2015.swf'),
    'play/v2/content/global/content/party_icon.swf': holidayRef('party/content/ContentParty_icon-HolidayParty2015.swf'),
    'play/v2/content/global/logo/logo.swf': holidayRef('party/content/ContentLogo-HolidayParty2015.swf'),
    'play/v2/content/global/avatar/sprites/frostbite.swf': holidayRef('party/avatar/sprites/AvatarPenguinFrostbite-HolidayParty2015.swf'),
    'play/v2/content/global/telescope/telescope.swf': holidayRef('party/other/Telescope-HolidayParty2015.swf'),
    'play/v2/content/global/binoculars/binoculars.swf': holidayRef('party/other/Binoculars-HolidayParty2015.swf'),
    ...holidayMusicFiles
  },
  globalChanges: {
    'content/party_icon.swf': [holidayRef('party/content/ContentParty_icon-HolidayParty2015.swf'), 'party_icon', 'scavenger_hunt_icon'],
    'close_ups/quest_interface.swf': [holidayRef('party/close_ups/Close_upsQuest_interface-HolidayParty2015.swf'), 'w.app.generic.partyinterface'],
    'close_ups/item_calendar_web.swf': [holidayRef('party/close_ups/Close_upsItem_calendar_web-HolidayParty2015.swf'), 'advent_calendar'],
    'close_ups/dialogue_december_login.swf': [holidayRef('party/close_ups/Close_upsCharacter_dialogue_december_login-HolidayParty2015.swf'), 'w.app.loginprompt'],
    'close_ups/dialogue_december_congrats.swf': holidayRef('party/close_ups/Close_upsCharacter_dialogue_december_congrats-HolidayParty2015.swf'),
    'close_ups/dialogue_walrus_collect.swf': holidayRef('party/close_ups/Close_upsCharacter_dialogue_walrus_collect-HolidayParty2015.swf'),
    'avatar/sprites/frostbite.swf': holidayRef('party/avatar/sprites/AvatarPenguinFrostbite-HolidayParty2015.swf'),
    'avatar/sprites/rooms_effects_avatar.swf': holidayRef('party/avatar/sprites/RoomsEffectsAvatar-HolidayParty2015.swf')
  },
  localChanges: {
    'close_ups/quest_interface.swf': { en: holidayRef('party/close_ups/Close_upsQuest_interface-HolidayParty2015.swf') },
    'close_ups/item_calendar_web.swf': { en: holidayRef('party/close_ups/Close_upsItem_calendar_web-HolidayParty2015.swf') },
    'close_ups/dialogue_december_login.swf': { en: holidayRef('party/close_ups/Close_upsCharacter_dialogue_december_login-HolidayParty2015.swf') },
    'close_ups/dialogue_december_congrats.swf': { en: holidayRef('party/close_ups/Close_upsCharacter_dialogue_december_congrats-HolidayParty2015.swf') },
    'close_ups/dialogue_walrus_collect.swf': { en: holidayRef('party/close_ups/Close_upsCharacter_dialogue_walrus_collect-HolidayParty2015.swf') },
    'membership/party2.swf': { en: holidayRef('party/membership/MembershipParty2-HolidayParty2015.swf') },
    'membership/party3.swf': { en: holidayRef('party/membership/MembershipParty3-HolidayParty2015.swf') }
  }
};

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
  { date:'2015-11-05', end:['party'] },
  // Timeline shows the December pre-party separately from the live Holiday event.
  { date:'2015-12-02', temp:{ event:HOLIDAY_2015_ADVENT } },
  { date:'2015-12-17', end:['event'], temp:{ party:HOLIDAY_2015_PARTY } },
  // The exclusive end is in 2016.ts to retain chronological update ordering.
];