-- Learning what Classic's data lacks as the player goes: the rewards of
-- quests already in the log, and gear vendors sell that the data does not
-- list for them (Forever's own islands, say).

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("learnmore")

local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end
local ITEMS = {
    ["item:900"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = Agi(10) },
    ["item:1001"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = Agi(20) },
    ["item:1002"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = Agi(25) },
    ["item:1003"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = Agi(30) },
}

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitFactionGroup = function(unit) if unit == "npc" then return nil end return "Alliance", "Alliance" end
_G.UnitRace = function() return "High Order Skyborne", "Skyborne", 95 end
env.InstallItems(ITEMS, { [5] = "item:900" }, { [0] = {} }, 6)

-- Items by ID, as the learning code asks: gear except 1009, a potion.
_G.C_Item.GetItemInfoInstant = function(id)
    if id == 1009 then return id, "Consumable", "Potion", "" end
    return id, "Armor", "Mail", "INVTYPE_CHEST"
end
local loaded = true
_G.C_Item.GetItemInfo = function(id)
    if not loaded then return nil end
    return "Item", "item:" .. id, 2, 8, 5
end

local S = ns.Sources
S.ZONES = { [215] = "Mulgore" }
S.NPCS, S.DUNGEONS, S.BOSSES, S.FOREVER = {}, {}, {}, {}
S.QUESTS = {}
S.ITEMS = {}
ns.Crafts.ITEMS = {}

_G.C_Map = {
    GetBestMapForUnit = function() return 7 end,
    GetPlayerMapPosition = function() return { GetXY = function() return 0.4, 0.6 end } end,
    GetMapInfo = function() return { name = "Zephras Isle" } end,
}

--------------------------------------------------------------------------------
-- The quest log
--------------------------------------------------------------------------------

local selected = 7
local log = {
    { title = "Zephras Isle", isHeader = true },
    { title = "Foul Matriarch", questID = 92470, level = 4 },
    { title = "Agitators", questID = 92465, level = 3 },
}
local rewards = {
    [92470] = { choice = { "item:1001", "item:1009" }, reward = { "item:1002" } },
    [92465] = { choice = {}, reward = {} },
}
_G.C_QuestLog = {
    GetNumQuestLogEntries = function() return #log end,
    GetInfo = function(i) return log[i] end,
    GetSelectedQuest = function() return selected end,
    SetSelectedQuest = function(id) selected = id end,
    GetQuestDifficultyLevel = function() return 4 end,
}
_G.GetNumQuestLogChoices = function(id) return #rewards[id or selected].choice end
_G.GetNumQuestLogRewards = function(id) return #rewards[id or selected].reward end
_G.GetQuestLogItemLink = function(kind, i, id)
    local link = rewards[id or selected][kind][i]
    return link and ("|cffffffff|H%s::|h[x]|h|r"):format(link)
end

local Learn = ns.QuestLearn
Learn:LearnLog()
local rec = ns.db.learnedQuests and ns.db.learnedQuests[92470]
suite.check("a quest in the log is learned", rec ~= nil and rec.title == "Foul Matriarch" and rec.level == 4)
suite.check("with the gear it rewards, not the potion", rec and #rec.rewards == 2
    and rec.rewards[1][1] == 1001 and rec.rewards[1][4] == false
    and rec.rewards[2][1] == 1002 and rec.rewards[2][4] == true)
suite.check("and the side it was seen by", rec and rec.side == "A")
suite.check("a quest with no gear is kept as a quest", ns.db.learnedQuests[92465] ~= nil
    and #ns.db.learnedQuests[92465].rewards == 0)
suite.check("the log's own pick is put back", selected == 7)
suite.check("the finder links the reward to it", S.ITEMS[1001] and S.ITEMS[1001].q[1] == 92470)

local player = ns.Finder:Player()
local offered
for _, source in ipairs(ns.Finder:SourcesFor(1001, player)) do
    if source.kind == "quest" and source.questID == 92470 then offered = true end
end
suite.check("and offers it to this side", offered)

-- One quest, as it is accepted
rewards[92465] = { choice = { "item:1003" }, reward = {} }
Learn:LearnLog(92465)
suite.check("a quest just accepted gains its gear", #ns.db.learnedQuests[92465].rewards == 1)

-- A log that raises keeps nothing and breaks nothing
_G.C_QuestLog.GetInfo = function() error("secret value") end
local ok = pcall(Learn.LearnLog, Learn)
suite.check("a log that raises is left alone", ok)
_G.C_QuestLog.GetInfo = function(i) return log[i] end

--------------------------------------------------------------------------------
-- Vendors
--------------------------------------------------------------------------------

local Spots = ns.NPCSpots
local stock = {
    { id = 1002, price = 120, stack = 1, avail = -1 },
    { id = 1009, price = 50, stack = 1, avail = -1 },
    { id = 1003, price = 300, stack = 1, avail = 2 },
}
_G.GetMerchantNumItems = function() return #stock end
_G.GetMerchantItemID = function(i) return stock[i] and stock[i].id end
_G.GetMerchantItemInfo = function(i)
    local s = stock[i]
    return "Item", "icon", s.price, s.stack, s.avail, true, true, false
end
_G.C_MerchantFrame = nil
_G.UnitGUID = function(unit) return unit == "npc" and "Creature-0-1-2-3-250001-0000A1" or nil end
_G.UnitName = function(unit) return unit == "npc" and "Aetheen of the Gales" or nil end

suite.check("no vendors learned yet", Spots:VendorCount() == 0)
local n = Spots:LearnStock()
local vendor = ns.db.learnedVendors and ns.db.learnedVendors[250001]
suite.check("a merchant's gear the data lacks is learned", n == 2 and vendor ~= nil)
suite.check("with its name, spot and price", vendor and vendor.name == "Aetheen of the Gales"
    and vendor.zone == "Zephras Isle" and vendor.x == 40 and vendor.y == 60 and vendor.items[1002][1] == 120)
suite.check("not the potion", vendor and vendor.items[1009] == nil)
suite.check("and whether stock is limited", vendor and vendor.items[1003][4] == true and vendor.items[1002][4] == false)
suite.check("a vendor of no side serves both", vendor and vendor.side == "AH")
suite.check("the data now has the vendor", S.NPCS[250001] and S.NPCS[250001][5] == "AH"
    and S.ZONES[S.NPCS[250001][2]] == "Zephras Isle")
suite.check("and lists the gear under it", S.ITEMS[1002].v[1] == 250001 and S.ITEMS[1003].v[2] == 1)

local sold
for _, source in ipairs(ns.Finder:SourcesFor(1003, player)) do
    if source.kind == "vendor" then sold = source end
end
suite.check("the finder offers it like any vendor", sold and sold.name == "Aetheen of the Gales"
    and sold.zone == "Zephras Isle" and sold.limited == true)

suite.check("opening it again learns nothing new", Spots:LearnStock() == 0)

-- A Horde vendor is kept to the Horde
_G.UnitGUID = function(unit) return unit == "npc" and "Creature-0-1-2-3-250002-0000A2" or nil end
_G.UnitFactionGroup = function(unit) if unit == "npc" then return "Horde" end return "Alliance", "Alliance" end
stock = { { id = 1001, price = 80, stack = 1, avail = -1 } }
Spots:LearnStock()
sold = nil
for _, source in ipairs(ns.Finder:SourcesFor(1001, player)) do
    if source.kind == "vendor" then sold = source end
end
suite.check("a Horde vendor is not offered to the Alliance", ns.db.learnedVendors[250002].side == "H" and not sold)

-- An item the client has not loaded yet
loaded = false
_G.UnitGUID = function(unit) return unit == "npc" and "Creature-0-1-2-3-250003-0000A3" or nil end
_G.UnitFactionGroup = function(unit) if unit == "npc" then return nil end return "Alliance", "Alliance" end
ITEMS["item:1004"] = ITEMS["item:1003"]
stock = { { id = 1004, price = 90, stack = 1, avail = -1 } }
Spots:LearnStock()
suite.check("an item not loaded yet is kept with no item level", ns.db.learnedVendors[250003].items[1004][3] == 0)
suite.check("and still judged at any level", S.ITEMS[1004][2] == 999)
loaded = true
suite.check("its item level is filled in when it arrives", Spots:LearnStock() == 1
    and ns.db.learnedVendors[250003].items[1004][3] == 8 and S.ITEMS[1004][2] == 8)

-- Laid at login from what ships and what was learned
S.NPCS, S.ITEMS = {}, {}
ns.ForeverVendors = { [250010] = { name = "Shipped", zone = "Zephras Isle", x = 1, y = 2, side = "A",
    items = { [1001] = { 70, 3, 6, false } } } }
Spots:LayAllVendors()
suite.check("shipped vendors are laid over the data", S.NPCS[250010] and S.ITEMS[1001].v[1] == 250010)
suite.check("and so are the ones this account learned", S.NPCS[250001] ~= nil and S.ITEMS[1002] ~= nil)
suite.check("laying twice adds nothing twice", Spots:LayAllVendors() == false and #S.ITEMS[1001].v == 4)

suite.done()
