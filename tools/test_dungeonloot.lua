-- Dungeon Loot (the owner said build it, 2026-10-22, from a mockup): what
-- each dungeon's bosses drop, upgrades marked, with armor and stat chips.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("dungeonloot")

local ns = env.Load()
for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end

local DL, UI = ns.DungeonLoot, ns.DungeonLootUI

-- The real data lays out.
local index = DL:Index()
local dungeonsWithDrops = 0
for _ in pairs(index) do dungeonsWithDrops = dungeonsWithDrops + 1 end
suite.check("the data's boss drops lay out by dungeon", dungeonsWithDrops > 10, dungeonsWithDrops)

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

suite.check("the footer counts", UI.FootText(5, 2) == "5 shown. 2 are upgrades for you."
    and UI.FootText(3, 1) == "3 shown. 1 is an upgrade for you.", UI.FootText(5, 2))
suite.check("the header says where and what levels",
    UI.Where(found) == "Door in The Barrens. Levels 17 to 24.", UI.Where(found))

-- The window.
ns.db.dungeonLootPick = "test_wc"
UI:Show()
suite.check("the window opens", UI.frame and UI.frame:IsShown())
suite.check("the picked dungeon shows", UI.dungeonName:GetText() == "Test Caverns", UI.dungeonName:GetText())
local shown = 0
for _, row in ipairs(UI.rows) do if row:IsShown() then shown = shown + 1 end end
suite.check("its loot shows", shown == 5, shown)
suite.check("the best upgrade is on top with its gain", UI.rows[1].gain:GetText() == "+12%", UI.rows[1].gain:GetText())
UI:SetChip("stat", "strength")
UI:SetChip("armor", "cloth")
suite.check("picks nothing matches says so", UI.empty:GetText() == "Nothing here matches. Try fewer picks.",
    UI.empty:GetText())
UI:SetChip("stat", "all")
UI:SetChip("armor", "all")
UI:SortBy("boss")
suite.check("a column head sorts", UI.rows[1].boss:GetText() == "Lady Test")
UI:SortBy("boss")
UI:SortBy("boss")
suite.check("a third click goes back to best first", UI.rows[1].gain:GetText() == "+12%")
UI:Hide()
suite.check("the window closes", not UI.frame:IsShown())

ns.HandleSlash("loot")
suite.check("/beq loot opens it", UI.frame:IsShown())
UI:Hide()
suite.check("it wears the gear window's tabs, Dungeon Loot lit", UI.tabStrip == nil
    or UI.tabStrip.selected == "loot", UI.tabStrip and UI.tabStrip.selected)

ns.Items.Info, ns.Items.Stats, DL.NameOf = realInfo, realStats, realName
ns.Finder.JudgeOnce, ns.Finder.IsCached, ns.Compare.WearableUpgrade, ns.Finder.Shown =
    realJudge, realCached, realWearable, realShown
for id in pairs(ITEMS) do S.ITEMS[id] = nil end
S.DUNGEONS["test_wc"], S.BOSSES[9101], S.BOSSES[9102] = nil, nil, nil
DL.index = nil

suite.done()
