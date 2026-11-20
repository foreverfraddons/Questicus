-- Questicus: patch notes shown in game ("What's new") and on CurseForge.
-- Newest first. Put changes for the coming release in the "next" entry: the release workflow
-- (tools/changelog.py) turns "next" into the real version number and writes CHANGELOG.md from this file.
-- Write for players: what was added, what changed, what was fixed - no code talk.
local Q = Questicus
Q.Changelog = {
  { v = "next" },
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
