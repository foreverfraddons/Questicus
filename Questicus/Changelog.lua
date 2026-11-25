-- Questicus: patch notes shown in game ("What's new") and on CurseForge.
-- Newest first. Put changes for the coming release in the "next" entry: the release workflow
-- (tools/changelog.py) turns "next" into the real version number and writes CHANGELOG.md from this file.
-- Write for players: what was added, what changed, what was fixed - no code talk.
-- One line per change: another try at the same fix rewords its line, it doesn't add one. A CurseForge
-- update goes out once "next" holds 10 lines (release.yml, MIN_CHANGES).
local Q = Questicus
Q.Changelog = {
  { v = "next",
    changed = {
      "With Command Center installed, the Questicus icon in its dock, border bar, home page and Tools list takes the theme colour like the other tools; on its own Questicus keeps its own icon.",
    },
    fixed = {
      "Game clients in other languages (German, French, Spanish ...): quest objectives in your log are recognised (by name in your language, else by kind and order), so finished objectives drop out of the route and progress shows; quest, NPC and item names show in your language where the game knows them.",
    },
  },
  { v = "0.9.029",
    added = {
      "Hearthstone in routes: when it's ready and your inn gets you to the next step faster, the route has a \"Hearth to <inn>\" step with a Hearthstone button. Questicus learns where your hearthstone takes you when you set it at an innkeeper or use it. Options > Use my hearthstone in the route.",
    },
    changed = {
      "A quest with a choice of rewards is never handed in on its own any more: Questicus shows the reward it would pick and why, and you press Take it (or choose another yourself).",
    },
  },
  { v = "0.9.028",
    added = {
      "Quest tooltips on the map, minimap, tracker and dungeon window show what the quest says to do (the objective line from the quest log) and its quest ID. Right-click a quest in the tracker for a Wowhead link to copy; Alt-click one to share it with your group.",
      "Quest tooltips list the reward items, and the items its chain ends with; hold Alt over the tooltip to see each item's own tooltip and compare them.",
    },
    fixed = {
      "Respawn times count for every copy of a thing: a quest object (or mob) that comes under several ids with one name - the Pool of Tears' Atal'ai Artifacts - uses the respawn timed on any of them, so the arrow no longer sends you back to a spot after a minute when it takes seven to come back.",
      "Empty quest-object spots are given up much sooner: with the object light on (the default) the game picks objects all around you, so within about 12 yards of the marker, a second or so with nothing there moves the arrow on - no need to stand right on it for several seconds.",
      "Dungeon window tidied up: the facts in a neat two-column table, and the quests with a status icon, a short status (Done, In your log, Eligible, Not eligible - why on hover, with + Route putting the start of its chain on your route) and the quests you can only pick up inside the dungeon in their own box, marked with the dungeon icon.",
      "Dungeon run step tidied up: one line, \"Run <dungeon>  1/5 quests done\". Expand opens each quest's name and what's left of it on short lines, instead of a wall of quest text. A Group finder button on it opens the game's group finder.",
      "Dungeon mode: the dungeon's quests sit together at the top of the quest tracker, under the dungeon's name on a purple band, apart from your other quests.",
      "On a flight the arrow says \"In flight to <place>\" with about how long is left, instead of pointing at the next step thousands of yards away.",
    },
  },
  { v = "0.9.027",
    added = {
      "Quest dialog for ForeverDB: with \"Help fill the database\" on, every quest's texts (the offer, objectives, the \"have you got them?\" and the turn-in text) and the greetings above quest givers' lists are saved as the game shows them - your name, class and race are left out - so ForeverDB has WoW Forever's own words for every quest.",
    },
    fixed = {
      "Stutters near walls gone: routes round walls are worked out in the background now (a few ms a frame) instead of all at once, and every leg of the route on the map is kept instead of being searched again on every redraw. The line and the arrow also no longer loop back to a corner you've already walked past.",
      "The waypoint moves to the new step's spot even when it's close to the last one (it was left on the previous target), and \"Get the flight path\" steps lead to the flight master himself, by whatever name he goes (Wind Rider Master, Hippogryph Master, Bat Handler...).",
      "Dungeon mode: everything inside the dungeon - its objectives, hand-ins to someone or something in there (the Idol of Hakkar, ...) and quests you can only pick up in there - waits until you've got every quest you can get outside, instead of sending you in early. Quests that start inside no longer hold the run up. Outside dungeon mode, a finished quest whose hand-in is inside a dungeon is no longer a step that sends you in: it's handed in when you're in there.",
      "Dungeon list and window: how many of the dungeon's quests are in your log as well as how many are done, and a \"picked up inside\" mark on quests you get in the dungeon itself.",
    },
  },
  { v = "0.9.026",
    added = {
      "Waypoint in the world: a marker with a beam of light stands over where you're going, with the distance, when you'll get there and what it is (the step, your corpse, your own pin), coloured by what the step is. Close up it turns into a card over the target saying what it is; off screen a pointer at the edge shows which way to turn. Right-click to clear it. No other waypoint addon needed.",
      "Your own waypoints: /way [zone] x y [name] (or /qway), /way paste for a list followed one after the other, /way clear, Ctrl-click on the minimap, a pin you put on the world map, or a map link clicked in chat - followed (arrow, map, marker in the world) until you get there, then the route again.",
      "Waypoint options (Options > Waypoint, Waypoint look): pinpoint distance, edge pointer and its arrow, size, smaller with distance, opacity, beam, what's written under it, meters instead of yards, your own colours, showing it with the interface hidden, fade on mouse-over, and sounds for a new waypoint, getting close and walking away (/qc waysound for your own).",
      "While you're a ghost the arrow leads you back to your corpse (\"Your corpse\", along the walkable path) and says when you're close enough to resurrect, the route line on the world map and minimap shows the path to it, the game's waypoint goes on it, and a corpse pin shows where it is on the world map and the minimap (at the minimap's edge when it's further). Back to the route once you're alive.",
      "Your findings now reach ForeverDB from inside the game: respawn times, new spawn points, zone border crossings and objects that only appear on a kill are passed quietly (addon messages, nothing in chat) to ForeverDB's collector when it's online in your guild or group, so the next ForeverDB update has them for everyone. Turn it off with \"Help fill the database\" in Options > Advanced; /qc relay shows how much got through.",
      "Checked walking paths: where ForeverDB has a checked walk for a route step, the arrow and the map follow it exactly instead of working the way out, and that walk isn't learned or recorded any more.",
      "New spawn points: a quest mob standing next to you (out of combat) more than 30 yards from every spawn the database knows is added as a new spawn point - on your map, in the arrow's spots and in the route right away, and in ForeverDB for everyone with your recordings.",
      "Mob respawn times are learned while you play and used right away: a spot you killed at that still has no nameplate in view (not back yet), or is found back later, tightens its respawn time; the arrow re-times every skipped spot of that mob at once, and the route counts the wait for respawns when a quest needs more kills than there are spawns. Everything is saved for ForeverDB.",
    },
    fixed = {
      "The route line on the map and minimap is smooth and solid now: no more stair steps and zig-zags from the path search, rounded corners - it never cuts over a wall (the arrow keeps the exact path).",
      "Landing from a flight always moves the route on now: sometimes the game still said you were on the flight when it handed control back, and the \"Fly to\" step stayed after you'd landed.",
      "Walking to a person, flight master, place or object is exact now: the arrow only turns at a corner once you're really there, an object's spot counts only when you stand on it, and explore spots need you inside - mobs keep the looser rules since they wander. Paths also go round walls marked in ForeverDB (and through the openings between them, however narrow), and the arrow only moves on from a corner round a wall's end once the way on is clear.",
      "Walking between zones follows the real passes: the arrow, the route lines on the map, travel times and the choice of flight master all go through the known crossings between zones (via a third zone if that's the way), never straight over a zone line, and each stretch between crossings still goes round walls - no more being sent to Hammerfall from the Hinterlands.",
      "The arrow no longer points away from the quest mobs in front of you: while a mob for the current objectives is in view (nameplate, target or soft target, not tagged by someone else) the arrow turns into its skull and says \"<mob> in view\" (\"right here\" when it's close) instead of pointing at a spawn marker that may be a different one. Within sight it also aims straight at the target instead of along a detour.",
      "The arrow no longer runs you round every kill spot to find them empty: with enemy nameplates on, spawns within nameplate range whose mob isn't up (no live nameplate, or tagged by someone else) are skipped from a distance until they respawn, and open again as soon as the mob shows up. Without nameplates you get a one-time tip to turn them on.",
    },
  },
  { v = "0.9.025",
    added = {
      "Options > Stat weights: set how much each stat is worth to you, per role. Gear upgrades and quest reward picks use your numbers (scroll over a number to nudge it; Back to defaults undoes it).",
      "Completionist routes now include WoW Forever's secret quest chains, starting with the Alcaz Operative Insignia (Alcaz Prison -> Moonbrook -> State Secrets), with step-by-step notes. Other routes leave secrets out.",
    },
    changed = {
      "The arrow and the route now know WoW Forever's zone borders (from ForeverDB): paths stay off the mountains, walls and open sea between zones and go through the passes people really walk, travel times count the way round, and far targets in another zone are reached through a known crossing. Where you cross a border is recorded and shared through ForeverDB (/qc zone shows where you are).",
      "Objective steps now say how to do them: the quest's own instruction (\"Use the Holy Water on the corrupted Moonwell\"), the quest item to use and on what (with its key), and where each item drops from or is found.",
      "Flights: on a flight path the arrow and the guide just say \"in flight\" (nothing is measured until you land), and every route you fly is timed once - the planner uses your real flight times from then on, and they go into the shared database with your recordings.",
      "The arrow and the route learn your way around much sooner: a wall, gate, cliff or mountain range you had to walk round is remembered (one long detour is enough), walks through caves and dungeons on the way are kept instead of dropped, ground you've walked yourself is preferred, and a chat line tells you when it learned something (/qc paths shows the last walk).",
    },
    fixed = {
      "Dungeon mode now finishes the chain quest you already have in the zone you're in before sending you elsewhere (e.g. Larion and Muigin in Un'Goro for the Sunken Temple): a chain step in your log was treated as already done, and quests across the sea looked \"on the way\" because the dungeon's own quests wait there.",
      "Dungeon mode no longer fills the route with endless \"Do <quest>\" steps for a finished quest of another zone in your log (e.g. It's a Secret to Everybody in Temple of Atal'Hakkar mode). A quest whose objectives have no known place now gets one step at most.",
      "Auto accept only takes the quests your route has you pick up (or ones you added yourself). It used to accept any quest your settings allowed, so NPCs handed you quests the route had left out.",
      "The \"Help calibrate Questicus\" respawn pop-up no longer shows for objects that only appear when you use an item on a mob or kill it (like Broodling Essence) - those have no respawn timer.",
      "Much less lag and stutter while questing: the arrow and the map reuse the way they worked out instead of working it out again many times a second, the route is only planned again when a quest is taken, done or an objective finishes (at most every 5 seconds, never in collection mode), and opening, zooming and keeping the world map open makes much less garbage.",
      "Much less memory churn (the stutters every few seconds): minimap icons are only redrawn when you've moved, turned or the route changed, tooltips are made only when you point at an icon, and opening the world map no longer builds megabytes of temporary data.",
      "The route no longer sends you to quest givers who won't talk to you: quests that need reputation you don't have, quests from a faction you're unfriendly or hostile with (like Timbermaw before you've earned them), and quests whose NPCs you've seen are hostile to you are left out until that changes.",
    },
  },
  { v = "0.9.024",
    added = {
      "Highlights: ore, herbs, quest objects, chests and your fishing bobber light up as you come up to them, with 15 light effects, the object's name and icon, colours per kind of object, and a live preview (Options > Highlights, or /qc glow).",
      "Questicus now records much more for the shared quest database while you play (money and skinning per creature, fishing per zone, flight prices, trainers and every ability's training cost, everything vendors sell with its price, limits, token costs and requirements, quest details and reputation, which quests NPCs really offer, rares, subzones, encounters, gathering skill levels) - /qc recorded shows what it has. Turn it off under Options > Advanced.",
      "Highlights options: hide the light in combat, in instances, on things you can't use yet or on herbs and ore without the profession; ignore objects; pick the range and direction; set the interact key; cut the light out around your character; alternate Find Herbs and Find Minerals if you have both.",
    },
    changed = {
      "Vendor gear on the route: no more plain white items (weapons still count), and only when buying it still leaves enough gold for your class training at the next level (what your trainer showed you, or what other players' trainers showed - every ability's training cost is now recorded and shared through the database).",
      "Quests that let you choose a profession book (Mining for Dummies, Wild Harvest, Pelt Collecting for Beginners ...) are never handed in with a pick made for you: the reward window stays open so you choose.",
      "Kill and collect objectives: the arrow points to the closest spot, leaning toward your next step so you work through the area in that direction. Spots you just cleared, or where there was nothing, are skipped until they respawn; respawn times are measured while you play and shared through the database (1 minute until one is known). A quest object nobody has timed yet asks you once to wait for it to come back, so no one else has to. /qc respawn shows them.",
      "The options window is tidied into sections (General, Questing, Map & minimap, Tracker & alerts, Dungeons, Highlights, Advanced), each a short page with plainer wording; closing the highlight settings takes you back to it.",
    },
    fixed = {
      "Collect-from-object quests (like Harvesting Windstones) no longer get sent to the back of the route because a creature you had just killed was taken for where the items come from; abandoning and retaking a quest is planned fresh; the guide's \"Done:\" line now reads \"Last step:\" so it isn't mistaken for the quest being finished.",
      "Quest XP, gold and reward items now always come from the game itself (your quest log, the quest windows, what you really got) instead of the database whenever the game has shown them; differences are saved so the shared database gets corrected.",
      "Routes skip quests other players found their quest giver doesn't offer yet.",
      "Collection mode now turns every Questicus feature off - map and minimap icons, nameplate marks and tooltip lines, the quest tracker, pop-ups, the quest item button, the boss tracker and highlights - and back on when you leave it.",
    },
  },
  { v = "0.9.023",
    fixed = {
      "Opening the world map no longer redraws the quest areas when nothing has changed.",
      "Fixed an error (\"secret number value\") with the world map open while another addon's frames were in combat.",
      "The What's new window keeps its text inside the window, waits until you've answered the setup questions, and on a first install shows only the latest version's notes.",
    },
    added = {
      "Mob tooltips show about how much money a kill drops and, if you know Skinning, what skinning it gives (real WoW: Forever counts from Drop Tables). /qc mobinfo turns it off.",
    },
  },
  { v = "0.9.022",
    fixed = {
      "The yellow waypoint marker no longer covers the step icon on the world map: it turns see-through while it sits on the icon.",
      "The world map window's close and full-screen buttons are no longer hidden under the quest log's search bar.",
      "Boss tracker: every boss gets its own still, round portrait (no more blank skulls or moving models), and names sit under the pictures instead of running over them.",
    },
    added = {
      "Boss tracker: a boss you've killed this run turns into a skull with a tick; hover it to see what it dropped and who got it.",
    },
  },
  { v = "0.9.21",
    fixed = {
      "The yellow waypoint marker on Questicus Maps' stitched map now goes under Questicus' step icon too.",
      "The quest log's search bar keeps the size it has while you type, instead of stretching when it's empty.",
    },
  },
  { v = "0.9.20",
    fixed = {
      "The quest log's search bar on the world map no longer flickers or covers the buttons beside it.",
    },
  },
  { v = "0.9.19",
    fixed = {
      "The game's yellow waypoint marker now sits under Questicus' step icon on the world map, so you can read the step and its number.",
    },
  },
  { v = "0.9.18",
    fixed = {
      "The quest log no longer collapses and reopens every so often while you quest, and quest areas aren't redrawn as you walk between the spots of the same step (the map pin only moves when your route moves on to another step).",
    },
  },
  { v = "0.9.17",
    changed = {
      "The world map no longer redraws quest areas and icons all the time. They're drawn once and only redrawn when your route changes, you accept or hand in a quest, or after a loading screen. Only the line from you to your current step follows you as you move.",
    },
  },
  { v = "0.9.16",
    fixed = {
      "Map icons no longer flash big for a moment while you zoom or drag the world map, or when quest areas are redrawn.",
      "The quest log's search bar on the world map no longer stretches off past the quest log.",
    },
  },
  { v = "0.9.15",
    added = {
      "Questicus now tells you when a newer version is out (it checks with guild and group members who use it).",
      "Patch notes: after an update, the first time you log in you'll see what's new. Type /qc news to see them again.",
    },
  },
  { v = "0.9.14",
    fixed = {
      "With escort quests turned off, escort quests (like Ringo in Un'Goro) no longer end up on your route.",
    },
  },
  { v = "0.9.13",
    changed = {
      "The quest tracker's fold button sits in the far right corner, and the title bar stays put when you fold or unfold it.",
    },
  },
  { v = "0.9.12",
    fixed = {
      "The route window remembers where you put it when you open it from Command Center or the minimap button.",
    },
  },
  { v = "0.9.11",
    changed = {
      "The minimap button follows Command Center's minimap shape, and route lines fit square minimaps.",
    },
  },
  { v = "0.9.10",
    added = {
      "The quest tracker can be resized (drag the corner, right-click it to fit) and scrolls when your quests don't fit.",
      "The quest tracker can be folded down to its title bar.",
    },
  },
  { v = "0.9.9",
    fixed = {
      "Boss portraits show the first time you open the boss tracker.",
    },
  },
  { v = "0.9.8",
    fixed = {
      "The level and time-to-level text no longer overlaps the route window's title when the window is narrow.",
    },
  },
  { v = "0.9.7",
    changed = {
      "Stat priority in the setup questions is now picked from a drop-down list.",
    },
  },
  { v = "0.9.6",
    added = {
      "Dungeon run history: time, gold, XP and loot (and who got it) for every run, with averages. Type /qc runs.",
      "Pictures for every dungeon in the list.",
    },
    changed = {
      "Boss kills in your current run are tracked more reliably.",
      "The quest list on a dungeon's page scrolls.",
    },
  },
  { v = "0.9.5",
    fixed = {
      "The boss tracker's low profile mode no longer has text running into the buttons.",
    },
  },
  { v = "0.9.4",
    added = {
      "Every WoW Forever dungeon is in the dungeon list, with its real bosses.",
      "Low profile boss tracker - click a boss name for its loot.",
      "The dungeon list shows how many of its quests you've done; finished dungeons turn green with a check.",
      "Dungeon pages show the average gold per run and the state of each quest (done, ready to get, or needs a chain first), with a button to add a chain to your route.",
      "All zones, including the new WoW Forever zones, are in the zone list.",
    },
    fixed = {
      "Quest NPCs no longer show up in boss lists.",
    },
  },
  { v = "0.9.3",
    fixed = {
      "The map pictures are included in the download again.",
    },
  },
}
