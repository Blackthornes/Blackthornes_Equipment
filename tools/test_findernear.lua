-- Where to get upgrades: upgrades that show the same percent come nearest
-- first, and the zone the character is in is named in green (asked
-- 2026-10-09).

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("findernear")

local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end
local function Chest(n) return { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = Agi(n) } end

local ITEMS = {
    ["item:900"] = Chest(10),    -- worn
    ["item:1001"] = Chest(20),   -- a vendor's in Westfall
    ["item:1002"] = Chest(20),   -- the same, from a vendor in Elwynn Forest
    ["item:1003"] = Chest(20),   -- the same, from a vendor far off in Elwynn Forest
}

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitRace = function() return "Human", "Human", 1 end
local zone = "Elwynn Forest"
_G.GetRealZoneText = function() return zone end
env.InstallItems(ITEMS, { [5] = "item:900" }, { [0] = {} }, 20)
_G.C_QuestLog = { IsQuestFlaggedCompleted = function() return false end }

local S = ns.Sources
ns.Crafts.ITEMS = {}
ns.RollData.ITEMS = {}
S.ZONES = { [12] = "Elwynn Forest", [40] = "Westfall" }
S.NPCS = {
    [1] = { "Kirsta Deepshadow", 40, 56.3, 31.0, "A" },
    [2] = { "Corina Steele", 12, 41.5, 65.9, "A" },
    [3] = { "Far Vendor", 12, 90.0, 90.0, "A" },
}
S.QUESTS = {}
S.DUNGEONS = {}
S.BOSSES = {}
S.FOREVER = {}
S.STARTS = {}
S.ITEMS = {
    [1001] = { 15, 18, 0, 0, 500, v = { 1, 0 } },
    [1002] = { 15, 18, 0, 0, 500, v = { 2, 0 } },
    [1003] = { 15, 18, 0, 0, 500, v = { 3, 0 } },
}

local Finder, UI = ns.Finder, ns.FinderUI

local function Order()
    local found = Finder:Scan()
    local ids = {}
    for _, pick in ipairs(found.all.chest or found.all[5] or {}) do ids[#ids + 1] = pick.itemID end
    if #ids == 0 then
        for _, list in pairs(found.all) do
            for _, pick in ipairs(list) do ids[#ids + 1] = pick.itemID end
        end
    end
    return table.concat(ids, ",")
end

-- Where the character stands is not known: the zone decides.
suite.check("same percent, the ones in this zone come first", Order():find("^100[23],100[23],1001$") ~= nil, Order())
zone = "Westfall"
suite.check("in Westfall, Westfall's comes first", Order():find("^1001,") ~= nil, Order())
zone = "Elwynn Forest"

-- Where the character stands is known, on this zone's map: nearer first.
local map = 37
ns.Waypoints.MapFor = function(_, name) return name == "Elwynn Forest" and map or nil end
local spot = { map = map, x = 0.88, y = 0.88 }
ns.QuestArrow.Here = function() return spot end
suite.check("standing by the far vendor, its upgrade comes first", Order() == "1003,1002,1001", Order())
spot = { map = map, x = 0.42, y = 0.66 }
suite.check("standing by the near one, that one does", Order() == "1002,1003,1001", Order())
-- A spot on another map (a city inside the zone) is not used.
spot = { map = 99, x = 0.88, y = 0.88 }
suite.check("a spot on another map is not trusted", Order():find("^100[23],100[23],1001$") ~= nil, Order())

-- A bigger upgrade still wins whatever the distance.
ITEMS["item:1004"] = Chest(30)
S.ITEMS[1004] = { 15, 18, 0, 0, 500, v = { 1, 0 } }
suite.check("a bigger upgrade in another zone still comes first", Order():find("^1004,") ~= nil, Order())
S.ITEMS[1004] = nil

-- Green zone names.
local line = UI.SourceLine({ kind = "vendor", name = "Corina Steele", zone = "Elwynn Forest", x = 41.5, y = 65.9 })
suite.check("the zone you are in is green", line:find("|cff[0-9a-f]+Elwynn Forest|r") ~= nil, line)
line = UI.SourceLine({ kind = "vendor", name = "Kirsta Deepshadow", zone = "Westfall", x = 56.3, y = 31.0 })
suite.check("another zone is not", not line:find("|cff[0-9a-f]+Westfall|r"), line)
suite.check("only whole words", UI.MarkZone("Elwynn Forestry", "Elwynn Forest") == "Elwynn Forestry")
suite.check("a zone with odd characters is safe", UI.MarkZone("in Ahn'Qiraj (x)", "Ahn'Qiraj"):find("Ahn'Qiraj|r", 1, true) ~= nil)

suite.done()
