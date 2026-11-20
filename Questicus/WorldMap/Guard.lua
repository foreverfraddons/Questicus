-- Questicus Maps: the world map, built from OpenMap (MIT, by Ji and the OpenMap contributors - see
-- WorldMap\LICENSE.txt and the map's Credits page). No separate addon needed. If the standalone OpenMap
-- addon is still installed and on, it loaded first (OptionalDeps) and runs the map; Questicus' copy
-- then stays out of the way.
local Q = Questicus
if _G.OpenMapAPI or _G.OpenMap then          -- (the standalone OpenMap addon loaded first)
  Q.mapStandalone = true
  Q.After(8, function()
    Q:Print("Questicus Maps (the world map) is built into Questicus now - disable or delete the OpenMap addon to use it")
  end)
end
