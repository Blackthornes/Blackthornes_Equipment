-- Dungeon Loot (the owner said build it, 2026-10-22, from a mockup): what
-- each dungeon's bosses drop, upgrades marked, with armor and stat chips.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("dungeonloot")

local ns = env.Load()
for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end

local DL = ns.DungeonLoot

-- The real data lays out.
local index = DL:Index()
local dungeonsWithDrops = 0
for _ in pairs(index) do dungeonsWithDrops = dungeonsWithDrops + 1 end
suite.check("the data's boss drops lay out by dungeon", dungeonsWithDrops > 10, dungeonsWithDrops)

-- The Drowned City (a player saw none of its gear): listed with its door,
-- levels and bosses, and the gear Farmer saw drop there laid in.
local drowned
for _, d in ipairs(DL:Dungeons({ level = 38, faction = "A" })) do
    if d.name == "The Drowned City" then drowned = d end
end
suite.check("The Drowned City is listed", drowned ~= nil)
suite.check("its door is in Stranglethorn Vale", drowned and drowned.door == "Stranglethorn Vale",
    drowned and drowned.door)
suite.check("its levels are 35 to 40", drowned and drowned.low == 35 and drowned.high == 40,
    drowned and tostring(drowned.low) .. "-" .. tostring(drowned.high))
suite.check("its gear is laid in", drowned and (drowned.count or 0) >= 3, drowned and drowned.count)
local drownedBosses = DL:Bosses("2970") or {}
suite.check("its six bosses are listed", #drownedBosses == 6, #drownedBosses)

-- A pretend dungeon and its drops.
local S = ns.Sources
S.DUNGEONS["test_wc"] = { "Test Caverns", 17, 24, "The Barrens", "" }
S.BOSSES[9101] = { "Lord Test", "test_wc", 20 }
S.BOSSES[9102] = { "Lady Test", "test_wc", 21 }
local ITEMS = {
    [8001] = { name = "Leggings of Test", equipLoc = "INVTYPE_LEGS", classID = 4, subclassID = 2, stats = { ITEM_MOD_AGILITY_SHORT = 5 } },
    [8002] = { name = "Robe of Test", equipLoc = "INVTYPE_CHEST", classID = 4, subclassID = 1, stats = { ITEM_MOD_INTELLECT_SHORT = 4 } },
    [8003] = { name = "Cloak of Test", equipLoc = "INVTYPE_CLOAK", classID = 4, subclassID = 1, stats = { ITEM_MOD_AGILITY_SHORT = 2 } },
    [8004] = { name = "Staff of Test", equipLoc = "INVTYPE_2HWEAPON", classID = 2, subclassID = 10, stats = { ITEM_MOD_SPIRIT_SHORT = 3 } },
    [8005] = { name = "Belt of Test", equipLoc = "INVTYPE_WAIST", classID = 4, subclassID = 2, stats = { ITEM_MOD_STRENGTH_SHORT = 3 } },
}
S.ITEMS[8001] = { d = { 9101, 30 } }
S.ITEMS[8002] = { d = { 9102, 20 } }
S.ITEMS[8003] = { d = { 9101, 10 } }
S.ITEMS[8004] = { d = { 9102, 12 } }
S.ITEMS[8005] = { d = { 9102, 15 } }
DL.index = nil

local IdOf = function(link) return tonumber(tostring(link):match("item:(%d+)")) end
local realInfo, realStats = ns.Items.Info, ns.Items.Stats
ns.Items.Info = function(self, link)
    local item = ITEMS[IdOf(link)]
    if item then return { equipLoc = item.equipLoc, classID = item.classID, subclassID = item.subclassID } end
    return realInfo(self, link)
end
ns.Items.Stats = function(self, link)
    local item = ITEMS[IdOf(link)]
    if item then return item.stats end
    return realStats(self, link)
end
local realName = DL.NameOf
DL.NameOf = function(itemID) return ITEMS[itemID] and ITEMS[itemID].name or realName(itemID) end
local gains = { [8001] = 12, [8004] = 9 }
local realJudge, realCached, realWearable, realShown = ns.Finder.JudgeOnce, ns.Finder.IsCached, ns.Compare.WearableUpgrade, ns.Finder.Shown
ns.Finder.IsCached = function() return true end
ns.Finder.JudgeOnce = function(_, _, itemID) return nil, true, { itemID = itemID } end
ns.Compare.WearableUpgrade = function(result) return gains[result.itemID] ~= nil end
ns.Finder.Shown = function(result) return gains[result.itemID] end

local found
for _, d in ipairs(DL:Dungeons({ level = 20, faction = "H" })) do
    if d.key == "test_wc" then found = d end
end
suite.check("the dungeon is listed with its count", found and found.count == 5, found and found.count)

local data = DL:Rows("test_wc", "all", "all", false)
suite.check("every piece shows", #data.rows == 5, #data.rows)
suite.check("two are upgrades", data.upgrades == 2)
suite.check("upgrades come first, biggest gain first",
    data.rows[1].itemID == 8001 and data.rows[2].itemID == 8004, data.rows[1].itemID)
suite.check("each row names its boss", data.rows[1].boss == "Lord Test")

data = DL:Rows("test_wc", "leather", "all", false)
local ids = {}
for _, row in ipairs(data.rows) do ids[row.itemID] = true end
suite.check("Leather leaves cloth body armor out", not ids[8002])
suite.check("but keeps cloaks and weapons", ids[8003] and ids[8004] and ids[8001] and ids[8005])

data = DL:Rows("test_wc", "all", "agility", false)
suite.check("Agility shows only pieces with agility", #data.rows == 2, #data.rows)

data = DL:Rows("test_wc", "all", "all", true)
suite.check("Upgrades Only shows only upgrades", #data.rows == 2 and data.upgrades == 2)

data = DL:Rows("test_wc", "all", "all", false)
local byBoss = DL.SortRows(data.rows, "boss")
suite.check("sorting by boss", byBoss[1].boss == "Lady Test" and byBoss[#byBoss].boss == "Lord Test")
local flipped = DL.SortRows(data.rows, "boss", true)
suite.check("a second click flips it", flipped[1].boss == "Lord Test")
local byItem = DL.SortRows(data.rows, "item")
suite.check("sorting by item name", byItem[1].name == "Belt of Test")
suite.check("no column keeps best first", DL.SortRows(data.rows, nil) == data.rows)

local door = DL.Door(found)
suite.check("the door is the dungeon's zone", door and door.zone == "The Barrens")
suite.check("no door, no place", DL.Door({ name = "Nowhere" }) == nil)


-- Forever's bosses from the game's tables: one nobody has seen drop gear
-- still gets a row, after the loot, in the game's order.
local realBosses = ns.FOREVER_BOSSES
suite.check("the game's boss lists ship", type(realBosses) == "table" and #(realBosses["2999"] or {}) >= 5)
local crypts
for _, d in ipairs(DL:Dungeons({ level = 20, faction = "H" })) do
    if d.key == "2875" then crypts = d end
end
suite.check("a Forever dungeon with no drops seen is listed", crypts ~= nil and crypts.name == "Karazhan Crypts")
ns.FOREVER_BOSSES = { test_wc = { "Lord Test", "The Hidden Test", "Lady Test", "Silent Test" } }
data = DL:Rows("test_wc", "all", "all", false)
suite.check("bosses with no drops seen add rows", #data.rows == 7, #data.rows)
suite.check("the foot still counts only the loot", data.shown == 5, data.shown)
suite.check("they come after the loot, in the game's order",
    data.rows[6].bossOnly and data.rows[6].boss == "The Hidden Test" and data.rows[7].boss == "Silent Test")
suite.check("a boss with drops gets no extra row", data.rows[6].boss ~= "Lord Test")
suite.check("\"The\" and case don't stop a match", DL.BossKey("The Hidden Test") == DL.BossKey("hidden test"))
suite.check("a chip leaves them out", #DL:Rows("test_wc", "leather", "all", false).rows == 4)
suite.check("so does Upgrades Only", #DL:Rows("test_wc", "all", "all", true).rows == 2)
local sortedByBoss = DL.SortRows(data.rows, "boss")
suite.check("sorting by boss puts them among the rest", sortedByBoss[1].boss == "Lady Test"
    and sortedByBoss[#sortedByBoss].boss == "The Hidden Test")
local sortedByGain = DL.SortRows(data.rows, "gain")
suite.check("sorting by gain leaves them last", not sortedByGain[1].bossOnly)
ns.FOREVER_BOSSES = realBosses

ns.Items.Info, ns.Items.Stats, DL.NameOf = realInfo, realStats, realName
ns.Finder.JudgeOnce, ns.Finder.IsCached, ns.Compare.WearableUpgrade, ns.Finder.Shown =
    realJudge, realCached, realWearable, realShown
for id in pairs(ITEMS) do S.ITEMS[id] = nil end
S.DUNGEONS["test_wc"], S.BOSSES[9101], S.BOSSES[9102] = nil, nil, nil
DL.index = nil

suite.done()
