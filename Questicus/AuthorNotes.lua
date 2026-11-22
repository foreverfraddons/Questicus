-- Questicus author notes and route rules, shipped with the addon.
-- Written by the addon's author in game (right-click a route step) and copied here from the
-- author's QuesticusAuthor saved variables. Players can read them; nobody else can add to them.
--   notes[stepKey] = "text"       stepKey: "accept:<quest>", "complete:<quest>", "turnin:<quest>",
--                                  "fp:<flight node>", "fly:<flight node>", "buy:<item>"
--   hints[afterKey] = stepKey      "do stepKey right after afterKey"
Questicus.AuthorData = {
  v = 1,
  notes = {
    -- Alcaz Operative Insignia (secret, Completionist routes only)
    ["accept:96335"] = "Secret: Alcaz Operative Insignia. In Alcaz Prison, run past The Questioner at the entrance (don't kill him yet) to Mason Connery, chained up near the end, and take his quest.",
    ["complete:96335"] = "Go back to The Questioner, kill him and loot the Ornate Shackle Key.",
    ["turnin:96335"] = "Bring the key to Mason Connery to free him - he has the next quest.",
    ["complete:96337"] = "Moonbrook inn, second floor (Westfall 43.4, 67.8): click the loose floorboards by the chest for Connery's documents. Keep the Document Box you get.",
    ["turnin:96337"] = "Keep the Document Box: it's for State Secrets.",
    ["accept:96376"] = "Bring the Document Box to Nazgrel in Grommash Hold (Orgrimmar 32.6, 36.6).",
    ["accept:96377"] = "Bring the Document Box to Renzik \"The Shiv\" in the SI:7 building, Old Town (Stormwind 78.8, 70.8).",
    ["accept:96379"] = "Bring the Document Box to Rix Xizzix near the Booty Bay auction house (28.4, 75.8).",
    ["turnin:96376"] = "You get a Fractured Insignia. Six of them make the Alcaz Operative Insignia toy - the other five can be traded or bought.",
    ["turnin:96377"] = "You get a Fractured Insignia. Six of them make the Alcaz Operative Insignia toy - the other five can be traded or bought.",
    ["turnin:96379"] = "You get a Fractured Insignia. Six of them make the Alcaz Operative Insignia toy - the other five can be traded or bought.",
  },
  hints = {
  },
}
