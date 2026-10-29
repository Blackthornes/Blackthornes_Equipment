-- Show on Map when the game takes no pin (Forever turns its own user
-- waypoint down; a German player found nothing at the Crossroads,
-- 2026-10-29): our own marker goes on the spot, the quest arrow shows the
-- way, a zone-only step gets "Somewhere in ZONE", and the marker goes once
-- you stand there.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("showonmap")

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitFactionGroup = function() return "Horde", "Horde" end
_G.UnitRace = function() return "Tauren", "Tauren", 6 end
env.InstallItems({}, {}, { [0] = {} }, 20)

local opened
_G.OpenWorldMap = function(id) opened = id end
local MAPS = {
    [1414] = { name = "Kalimdor", parentMapID = 947 },
    [947] = { name = "Azeroth", parentMapID = 0 },
    [1413] = { name = "The Barrens", parentMapID = 1414 },
    [2521] = { name = "Zephras Isle", parentMapID = 1414 },
}
-- No SetUserWaypoint: the client takes no pin at all.
_G.C_Map = {
    GetBestMapForUnit = function() return 1413 end,
    GetMapInfo = function(id) return MAPS[id] end,
    GetMapChildrenInfo = function()
        return { { name = "The Barrens", mapID = 1413 }, { name = "Zephras Isle", mapID = 2521 } }
    end,
}

-- A client in another language finds these by ID, so they must be listed.
local Z = ns.Waypoints.ZONE_MAPS
suite.check("Forever's own zones have a map ID", Z["Zephras Isle"] == 2521 and Z["Mount Hyjal"] == 2482
    and Z["Riverglades"] == 2548 and Z["Shen'dralas"] == 2652)

-- A spot: our marker, the arrow, the map, and no "couldn't" line.
local spot = { zone = "The Barrens", x = 52, y = 30, name = "Crossroads" }
ns.QuestArrow.free = nil
local before = #env.chat
suite.check("a spot shows with no game pin", ns.Waypoints:Show(spot, "Crossroads", 123) == true)
local said = table.concat(env.chat, "\n", before + 1)
suite.check("it never says it couldn't", said:find("Couldn't", 1, true) == nil, said)
local light = ns.MapPins.spotlight
suite.check("our marker sits on the spot", light and light.place == spot and light.icon == 123
    and light.gamePin == false and light.area == false)
suite.check("the arrow points there", ns.QuestArrow.free and ns.QuestArrow.free.place.x == 52
    and ns.QuestArrow.free.place.zone == "The Barrens")
suite.check("and the map opens on the zone", opened == 1413, opened)

-- Arrival: within 15 yards the marker goes, farther it stays.
local arrow = ns.QuestArrow
local here, offset, measure = arrow.Here, arrow.Offset, arrow.Measure
local away = 40
arrow.Here = function() return { map = 1413, x = 0.5, y = 0.3 } end
arrow.Offset = function() return away, 0 end
ns.MapPins.arriveSince = 0
suite.check("it waits a moment before looking", ns.MapPins:SpotlightDone(0.2) == false)
suite.check("far away it stays", ns.MapPins:SpotlightDone(1) == false)
away = 10
suite.check("standing on it, it goes", ns.MapPins:SpotlightDone(1) == true)
arrow.Here, arrow.Offset, arrow.Measure = here, offset, measure
ns.MapPins:Spotlight(nil)

-- A zone-only step: a marker in the middle that says so, and it stays.
ns.QuestArrow.free, opened = nil, nil
before = #env.chat
suite.check("a zone alone shows too", ns.Waypoints:Show({ zone = "Zephras Isle" }, "Zephras Isle") == true)
light = ns.MapPins.spotlight
suite.check("a marker in the middle of the zone", light and light.place.zone == "Zephras Isle"
    and light.place.x == 50 and light.place.y == 50 and light.area == true)
suite.check("that says somewhere in it", light and light.name == "Somewhere in Zephras Isle", light and light.name)
suite.check("chat says to head there", table.concat(env.chat, "\n", before + 1):find("head for Zephras Isle.", 1, true) ~= nil)
suite.check("the arrow heads for the zone", ns.QuestArrow.free and ns.QuestArrow.free.place.zone == "Zephras Isle")
suite.check("and the zone's map opens", opened == 2521, opened)
suite.check("a zone marker never goes by itself", ns.MapPins:SpotlightDone(5) == false)
ns.MapPins:Spotlight(nil)

-- A zone with no map says so and shows nothing.
before = #env.chat
suite.check("a zone with no map fails", ns.Waypoints:Show({ zone = "Nowhere" }, "it") == false)
suite.check("and leaves no marker", ns.MapPins.spotlight == nil)

-- A click on a hunt's map pin goes through Show, marker and all.
local canvas = env.Stub({ _width = 1000, _height = 600 })
local pin = ns.MapPins:MakePin(canvas)
pin.hunt = { link = "item:1", place = spot }
ns.QuestArrow.free = nil
pin:GetScript("OnClick")(pin)
suite.check("a pin's click lays our marker", ns.MapPins.spotlight and ns.MapPins.spotlight.place == spot)
suite.check("and aims the arrow", ns.QuestArrow.free ~= nil)
ns.MapPins:Spotlight(nil)
ns.QuestArrow.free = nil

suite.done()
