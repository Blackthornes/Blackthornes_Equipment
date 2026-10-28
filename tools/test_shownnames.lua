-- Names shown in the client's language, and the big Show on Map marker (a
-- German player asked, 2026-10-28: the upgrade quest's steps named quests
-- and zones in English, and the game's map pin was hard to see). The data
-- stays English for every comparison; only what is shown is the game's.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("shownnames")

local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end
local function Gear(loc, n) return { loc = loc, class = 4, subclass = 2, stats = Agi(n) } end

local ITEMS = {
    ["item:900"] = Gear("INVTYPE_CHEST", 10),
    ["item:1002"] = Gear("INVTYPE_CHEST", 30),
}

local ns = env.Load("deDE")
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitFactionGroup = function() return "Horde", "Horde" end
_G.UnitRace = function() return "Tauren", "Tauren", 6 end
_G.GetRealZoneText = function(id)
    if id == 389 then return "Flammenschlund" end
    return "Mulgore"
end
env.InstallItems(ITEMS, { [5] = "item:900" }, { [0] = {} }, 10)

local GERMAN_MAPS = { [1412] = "Mulgore (DE)", [1429] = "Wald von Elwynn" }
local GERMAN_TITLES = { [749] = "Die verwüstete Karawane" }
local inLog, done, asked = {}, {}, {}
_G.C_QuestLog = {
    IsQuestFlaggedCompleted = function(id) return done[id] == true end,
    IsOnQuest = function(id) return inLog[id] == true end,
    ReadyForTurnIn = function() return false end,
    GetTitleForQuestID = function(id) return GERMAN_TITLES[id] end,
    RequestLoadQuestByID = function(id) asked[id] = true end,
}
_G.C_Map = _G.C_Map or {}
_G.C_Map.GetMapInfo = function(id)
    if GERMAN_MAPS[id] then return { name = GERMAN_MAPS[id], parentMapID = 1414 } end
    return nil
end

local S = ns.Sources
ns.Crafts.ITEMS = {}
ns.RollData.ITEMS = {}
S.ZONES = { [215] = "Mulgore" }
S.NPCS = {}
S.QUESTS = {
    [749] = { "The Ravaged Caravan", 5, 8, 178, 0, "Morin Cloudstalker", 215, 51.9, 59.6, "" },
    [765] = { "Supervisor Fizsprocket", 5, 12, 178, 0, "Morin Cloudstalker", 215, 51.9, 59.6, "", p = 749 },
}
S.DUNGEONS = { ["389"] = { "Ragefire Chasm", 13, 18, "Orgrimmar" } }
S.BOSSES = {}
S.FOREVER = {}
S.STARTS = {}
S.ITEMS = { [1002] = { 5, 12, 0, 0, 0, q = { 765 } } }
S.ENDS = {}

local W = ns.Waypoints

-- Zones and dungeons from the game.
suite.check("a zone shows the game's name", W.ShowZone("Elwynn Forest") == "Wald von Elwynn",
    W.ShowZone("Elwynn Forest"))
suite.check("a dungeon shows the game's name", W.ShowZone("Ragefire Chasm") == "Flammenschlund",
    W.ShowZone("Ragefire Chasm"))
suite.check("a name the game won't give stays", W.ShowZone("Nowhere Special") == "Nowhere Special")
suite.check("nothing in, nothing out", W.ShowZone(nil) == nil)

-- The finder's words: the game's quest title and zone, plain text kept English.
local source = { kind = "quest", questID = 749, title = "The Ravaged Caravan", questLevel = 8,
    name = "Morin Cloudstalker", zone = "Mulgore", x = 51.9, y = 59.6 }
local shown = ns.Finder:Describe(source)
suite.check("the finder shows the game's quest title", shown:find("Die verwüstete Karawane", 1, true) ~= nil, shown)
suite.check("the finder shows the game's zone", shown:find("Mulgore (DE)", 1, true) ~= nil, shown)
local saved = ns.Finder:Describe(source, true)
suite.check("saved text keeps the data's names", saved:find("The Ravaged Caravan", 1, true) ~= nil
    and saved:find("Mulgore (51.9", 1, true) ~= nil, saved)
local dungeon = ns.Finder:Describe({ kind = "dungeon", name = "Taragaman", dungeon = "Ragefire Chasm",
    minLevel = 13, maxLevel = 18 })
suite.check("a dungeon drop names the dungeon as the game does",
    dungeon:find("Flammenschlund", 1, true) ~= nil, dungeon)

-- The zone the character is in is marked in either name.
local marked = ns.FinderUI.MarkZone("Morin, Mulgore (DE) (51.9, 59.6)", "Mulgore")
suite.check("the shown zone is marked green", marked:find("|c", 1, true) ~= nil, marked)
suite.check("where a row is, in the client's language",
    ns.FinderUI.WhereOf({ sources = { { kind = "dungeon", dungeon = "Ragefire Chasm" } } }) == "Flammenschlund")

-- The upgrade quest's steps.
local Quest = ns.UpgradeQuest
ns.HandleSlash("quest quest")
local texts = {}
for _, step in ipairs((Quest:Steps())) do texts[#texts + 1] = step.text end
local all = table.concat(texts, " | ")
suite.check("the steps name the earlier quest as the game does",
    all:find("Die verwüstete Karawane", 1, true) ~= nil, all)
suite.check("the steps name the zone as the game does", all:find("Mulgore (DE)", 1, true) ~= nil, all)
suite.check("a title the game hasn't loaded is asked for once", asked[765] == true)
suite.check("and the data's title shows meanwhile", all:find("Supervisor Fizsprocket", 1, true) ~= nil, all)

-- The big marker on the map.
local Pins = ns.MapPins
Pins:Spotlight({ zone = "Mulgore", x = 51.9, y = 59.6 }, nil, "Morin Cloudstalker")
suite.check("Show on Map lays the big marker", Pins.spotlight and Pins.spotlight.name == "Morin Cloudstalker")
suite.check("with a map icon when no item is given", Pins.spotlight.icon == Pins.SPOT_ICON)
Pins:Spotlight({ zone = "Mulgore", x = 51.9, y = 59.6 })
suite.check("with no name it names the zone as the game does", Pins.spotlight.name == "Mulgore (DE)",
    Pins.spotlight.name)

local early = Pins.SpotLook(0.5, "full")
suite.check("Full: waves go out at first", #early.waves >= 1 and early.waves[1].size > Pins.SPOT_SIZE)
local later = Pins.SpotLook(Pins.WAVE_FOR + 1, "full")
suite.check("Full: then only the glow breathes", #later.waves == 0 and later.glow > 0)
local other = Pins.SpotLook(Pins.WAVE_FOR + 2, "full")
suite.check("the glow moves", math.abs(other.glow - later.glow) > 0.01)
local subtle = Pins.SpotLook(0.5, "subtle")
suite.check("Subtle: a still glow, no waves", #subtle.waves == 0 and Pins.SpotLook(3, "subtle").glow == subtle.glow)
local off = Pins.SpotLook(0.5, "off")
suite.check("Off: holds still", #off.waves == 0 and Pins.SpotLook(9, "off").glow == off.glow)

_G.C_Map.HasUserWaypoint = function() return false end
suite.check("the game's pin gone means the marker goes", not Pins.PinStillSet())
_G.C_Map.HasUserWaypoint = nil
suite.check("a client that won't say keeps it", Pins.PinStillSet())
Pins:Spotlight(nil)
suite.check("a cleared marker is gone", Pins.spotlight == nil)

suite.done()

-- An English client is left as it was.
local en = env.Load()
_G.C_Map = _G.C_Map or {}
_G.C_Map.GetMapInfo = function() return { name = "Should not show" } end
suite.check("English clients keep the data's names", en.Waypoints.ShowZone("Elwynn Forest") == "Elwynn Forest")
