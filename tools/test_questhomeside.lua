-- A Forever quest whose record does not say its side still keeps to one
-- side when something else does. Remember That I Love You (92415, given in
-- Stormwind City) and its second part (95161, which gives Tarnished Locket)
-- were offered to a Horde hunter as an upgrade quest: neither record said
-- its side, so both were laid over the data as open to everyone.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("questhomeside")

local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end
local function Neck(n) return { loc = "INVTYPE_NECK", class = 4, subclass = 0, stats = Agi(n) } end

local ITEMS = {
    ["item:279870"] = Neck(20),  -- Tarnished Locket, after an Alliance quest
    ["item:3001"] = Neck(15),    -- given in Orgrimmar
    ["item:3002"] = Neck(10),    -- an Alliance dungeon quest, said only there
    ["item:3003"] = Neck(5),     -- given in a zone both sides share
}

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitFactionGroup = function() return "Horde", "Horde" end
_G.UnitRace = function() return "Orc", "Orc", 2 end
_G.GetRealZoneText = function() return "The Barrens" end
env.InstallItems(ITEMS, {}, { [0] = {} }, 20)
_G.UnitLevel = function() return 20 end
_G.C_QuestLog = {
    IsQuestFlaggedCompleted = function() return false end,
    IsOnQuest = function() return false end,
}

local Finder = ns.Finder
local QuestLearn = ns.QuestLearn
local S = ns.Sources
ns.Crafts.ITEMS = {}
ns.RollData.ITEMS = {}
S.ZONES = { [17] = "The Barrens" }
S.NPCS = {}
S.QUESTS = {}
S.DUNGEONS = {}
S.BOSSES = {}
S.FOREVER = {}
S.ITEMS = {}
ns.FOREVER_DUNGEON_QUESTS = {
    [3100] = { "1", "A Dungeon Errand", 15, 20, "A", 0, "Someone", "Somewhere", 0, 0, 0, 0 },
}

-- The records as Data/ForeverQuests.lua ships them: no side said.
QuestLearn:Lay(92415, { title = "Remember That I Love You", zone = "Stormwind City", x = 47.2, y = 38.4, rewards = {} })
QuestLearn:Lay(95161, { title = "Remember That I Love You", level = 15, min = 15, prev = 92415,
    rewards = { { 279870, 15, 24, false } } })
QuestLearn:Lay(3000, { title = "An Orgrimmar Errand", level = 15, min = 15, zone = "Orgrimmar", x = 50, y = 50,
    rewards = { { 3001, 15, 24, false } } })
QuestLearn:Lay(3100, { title = "A Dungeon Errand", level = 15, min = 15, rewards = { { 3002, 15, 24, false } } })
QuestLearn:Lay(3200, { title = "A Barrens Errand", level = 15, min = 15, zone = "The Barrens", x = 50, y = 50,
    rewards = { { 3003, 15, 24, false } } })

suite.check("a quest given in Stormwind City is the Alliance's",
    S.QUESTS[92415] and S.QUESTS[92415][4] == Finder.ALLIANCE_RACES, S.QUESTS[92415] and S.QUESTS[92415][4])
suite.check("a quest given in Orgrimmar is the Horde's",
    S.QUESTS[3000] and S.QUESTS[3000][4] == Finder.HORDE_RACES)
suite.check("a dungeon quest takes its side from the dungeon list",
    S.QUESTS[3100] and S.QUESTS[3100][4] == Finder.ALLIANCE_RACES)
suite.check("a quest in a shared zone that says nothing stays open to both",
    S.QUESTS[3200] and S.QUESTS[3200][4] == 0)
suite.check("a quest's own word wins over its zone",
    QuestLearn.SideOf(1, { zone = "Stormwind City", side = "AH" }) == "AH")

local player = Finder:Player()
suite.check("a Horde hunter is read", player and player.faction == "H")
suite.check("the locket's quest is not open to Horde", Finder:QuestOpenTo(95161, player) == false)
suite.check("the Orgrimmar quest is open to Horde", Finder:QuestOpenTo(3000, player) == true)

local function QuestSources(itemID)
    local out = {}
    for _, source in ipairs(Finder:SourcesFor(itemID, player) or {}) do
        if source.kind == "quest" then out[#out + 1] = source.questID end
    end
    return out
end
suite.check("the finder lists no quest for Tarnished Locket", #QuestSources(279870) == 0,
    table.concat(QuestSources(279870), ","))
suite.check("nor for the Alliance dungeon quest's reward", #QuestSources(3002) == 0)
suite.check("the Orgrimmar quest's reward is listed", QuestSources(3001)[1] == 3000)
suite.check("the shared zone quest's reward is listed", QuestSources(3003)[1] == 3200)

suite.done()
