-- The other side's quests never show: a quest learned on Forever that does
-- not say its side, but comes after a quest for the other side (a Horde
-- rogue was sent to Teldrassil for Twisted Hatred), another race's or
-- class's quest anywhere in a chain, and a pick saved before the fix.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("questotherside")

local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end
local function Gear(loc, n) return { loc = loc, class = 2, subclass = 15, stats = Agi(n) } end

local ITEMS = {
    ["item:900"] = Gear("INVTYPE_WEAPON", 2),    -- worn
    ["item:1001"] = Gear("INVTYPE_WEAPON", 30),  -- after a night elf quest
    ["item:1002"] = Gear("INVTYPE_WEAPON", 20),  -- after a warrior quest
    ["item:1003"] = Gear("INVTYPE_WEAPON", 10),  -- a Horde quest
}

local ns = env.Load()
_G.UnitClass = function() return "Rogue", "ROGUE", 4 end
_G.UnitFactionGroup = function() return "Horde", "Horde" end
_G.UnitRace = function() return "Orc", "Orc", 2 end
_G.GetRealZoneText = function() return "Durotar" end
env.InstallItems(ITEMS, { [16] = "item:900" }, { [0] = {} }, 6)
_G.UnitLevel = function() return 6 end
_G.C_QuestLog = {
    IsQuestFlaggedCompleted = function() return false end,
    IsOnQuest = function() return false end,
}

local Finder = ns.Finder
local S = ns.Sources
ns.Crafts.ITEMS = {}
ns.RollData.ITEMS = {}
S.ZONES = { [14] = "Durotar", [141] = "Teldrassil" }
S.NPCS = {}
S.QUESTS = {
    [932] = { "Twisted Hatred", 4, 7, Finder.ALLIANCE_RACES, 0, "Tallonkai Swiftroot", 141, 55.6, 56.9, "" },
    -- Learned on Forever: no side said, only the quest before it.
    [98403] = { "Twisted Hatred", 1, 1, 0, 0, "", 0, 0, 0, "", learned = true, p = 932 },
    [500] = { "A Warrior's Start", 1, 4, 0, 1, "Frang", 14, 42, 69, "" },
    [501] = { "Warrior Gift", 1, 5, 0, 0, "Frang", 14, 42, 69, "", p = 500 },
    [700] = { "Sting of the Scorpid", 4, 6, Finder.HORDE_RACES, 0, "Gornek", 14, 42, 68, "" },
}
S.DUNGEONS = {}
S.BOSSES = {}
S.FOREVER = {}
S.ITEMS = {
    [1001] = { 1, 10, 0, 0, 0, q = { 98403 } },
    [1002] = { 1, 10, 0, 0, 0, q = { 501 } },
    [1003] = { 1, 10, 0, 0, 0, q = { 700 } },
}

local player = Finder:Player()
suite.check("a Horde rogue is read", player and player.faction == "H")
local function Open(id, who)
    return Finder.QuestOpenTo and Finder:QuestOpenTo(id, who)
end
local function QuestSources(itemID)
    local out = {}
    for _, source in ipairs(Finder:SourcesFor(itemID, player) or {}) do
        if source.kind == "quest" then out[#out + 1] = source.questID end
    end
    return out
end
suite.check("the finder lists no quest for the Alliance chain's reward", #QuestSources(1001) == 0,
    table.concat(QuestSources(1001), ","))
suite.check("nor for the warrior chain's reward", #QuestSources(1002) == 0)
suite.check("the Horde quest's reward is listed", QuestSources(1003)[1] == 700)

suite.check("a quest after an Alliance quest is not open to Horde", Open(98403, player) == false)
suite.check("the Alliance quest itself is not open", Open(932, player) == false)
suite.check("a quest after a warrior quest is not open to a rogue", Open(501, player) == false)
suite.check("a Horde quest is open", Open(700, player) == true)


-- A pick saved before the fix is let go and the tab picks again.
local Quest = ns.UpgradeQuest
ns.db.upgradeQuest = true
ns.charDB.upgradeQuestTabs = { quest = { itemID = 1001, link = "item:1001",
    source = { kind = "quest", questID = 98403, title = "Twisted Hatred" } } }
ns.charDB.upgradeQuestTab = "quest"
Finder:MarkStale()
Quest.rescan = true
Quest:Update()
local now = Quest:Quests().quest
suite.check("a saved Alliance pick is let go", not now or now.itemID ~= 1001, now and now.itemID)
suite.check("and the Horde quest is picked instead", now and now.itemID == 1003, now and now.itemID)

suite.done()
