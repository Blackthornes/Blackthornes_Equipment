-- Quests met in game: a quest window keeps the quest and the gear it
-- rewards, and the finder then offers them like the Classic ones.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("questlearn")

local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end
local ITEMS = {
    ["item:900"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = Agi(10) },
    ["item:1001"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = Agi(20) },
    ["item:1002"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = Agi(25) },
}

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitFactionGroup = function() return "Horde", "Horde" end
_G.UnitRace = function() return "Tauren", "Tauren", 6 end
env.InstallItems(ITEMS, { [5] = "item:900" }, { [0] = {} }, 20)

local S = ns.Sources
S.ZONES = { [215] = "Mulgore" }
S.NPCS, S.DUNGEONS, S.BOSSES, S.FOREVER = {}, {}, {}, {}
S.QUESTS = { [5] = { "Old Errand", 1, 5, 0, 0, "Ann", 215, 40, 40, "" } }
S.ITEMS = {}
ns.Crafts.ITEMS = {}

local Learn = ns.QuestLearn
local player = ns.Finder:Player()

-- The quest window
local window = {
    id = 90001, title = "A New Errand", npc = "Bob",
    choices = { "item:1001" }, rewards = { "item:1002" },
}
_G.GetQuestID = function() return window.id end
_G.GetTitleText = function() return window.title end
_G.GetNumQuestChoices = function() return #window.choices end
_G.GetNumQuestRewards = function() return #window.rewards end
_G.GetQuestItemLink = function(kind, i)
    local id = (kind == "choice" and window.choices or window.rewards)[i]
    return id and ("|cffffffff|H%s::|h[x]|h|r"):format(id)
end
_G.C_Item.GetItemInfoInstant = function(id) return id, "Armor", "Mail", "INVTYPE_CHEST" end
_G.UnitName = function(unit) return unit == "npc" and window.npc or nil end
_G.UnitLevel = function() return 12 end
_G.C_QuestLog = { GetQuestDifficultyLevel = function() return 14 end }
_G.C_Map = {
    GetBestMapForUnit = function() return 7 end,
    GetPlayerMapPosition = function() return { GetXY = function() return 0.4, 0.6 end } end,
    GetMapInfo = function() return { name = "Mulgore" } end,
}

suite.check("nothing learned yet", Learn:Count() == 0)
Learn:OnQuestWindow(true)
local rec = ns.db.learnedQuests[90001]
suite.check("an offered quest is kept", rec ~= nil and Learn:Count() == 1)
suite.check("with its title, levels, giver and spot",
    rec and rec.title == "A New Errand" and rec.level == 14 and rec.min == 12 and rec.giver == "Bob"
        and rec.zone == "Mulgore" and rec.x == 40 and rec.y == 60)
suite.check("and the gear it rewards, given or to choose",
    rec and #rec.rewards == 2 and rec.rewards[1][1] == 1001 and rec.rewards[1][4] == false
        and rec.rewards[2][1] == 1002 and rec.rewards[2][4] == true)

suite.check("the data now has the quest", S.QUESTS[90001] and S.QUESTS[90001][1] == "A New Errand"
    and S.ZONES[S.QUESTS[90001][7]] == "Mulgore")
suite.check("and links the rewards to it",
    S.ITEMS[1001] and S.ITEMS[1001].q[1] == 90001 and S.ITEMS[1002].g[1] == 90001)

local found
for _, source in ipairs(ns.Finder:SourcesFor(1001, player)) do
    if source.kind == "quest" then found = source end
end
suite.check("the finder offers it like any quest", found and found.questID == 90001 and found.name == "Bob")

-- Not saved twice
local before = rec.at
Learn:OnQuestWindow(true)
suite.check("seeing it again saves nothing new", Learn:Count() == 1 and #rec.rewards == 2)

-- A hand-in adds what the offer did not show
window.rewards = { "item:1002", "item:1003" }
_G.C_Item.GetItemInfoInstant = function(id)
    return id, "Armor", "Mail", id == 1003 and "" or "INVTYPE_CHEST"
end
Learn:OnQuestWindow(false)
suite.check("a hand-in window leaves out what is not gear", #rec.rewards == 2)

-- A Classic quest only gains rewards
window.id, window.title, window.choices, window.rewards = 5, "Old Errand", { "item:1001" }, {}
Learn:OnQuestWindow(true)
suite.check("a Classic quest keeps its own row", S.QUESTS[5][1] == "Old Errand" and S.QUESTS[5][6] == "Ann")
suite.check("and gains the reward", ns.db.learnedQuests[5] and S.ITEMS[1001].q[2] == 5)

-- Unreadable windows
window.id = nil
local count = Learn:Count()
Learn:OnQuestWindow(true)
suite.check("a window with no quest ID keeps nothing", Learn:Count() == count)
_G.GetQuestID = function() error("secret value") end
Learn:OnQuestWindow(true)
suite.check("nor one that raises", Learn:Count() == count)

-- Shipped and saved quests are laid at load
S.QUESTS, S.ITEMS = {}, {}
ns.ForeverQuests = { [90100] = { title = "Shipped", level = 20, min = 18, giver = "Cy", zone = "Dun Morogh",
    x = 10, y = 20, rewards = { { 2001, 18, 22, false } } } }
Learn:LayAll()
suite.check("shipped quests are laid over the data", S.QUESTS[90100] and S.QUESTS[90100][1] == "Shipped"
    and S.ITEMS[2001].q[1] == 90100)
suite.check("and so are the ones this account learned", S.QUESTS[90001] ~= nil)
suite.check("a zone the data lacks is added", S.ZONES[S.QUESTS[90100][7]] == "Dun Morogh")
suite.check("laying twice adds nothing twice", (Learn:LayAll() == false) and #S.ITEMS[2001].q == 1)

-- Sides: a learned quest is kept to the side that was offered it
suite.check("the side that was offered it is kept", rec.side == "H")
suite.check("so the data keeps it to the Horde", S.QUESTS[90001][4] == ns.Finder.HORDE_RACES)

-- Forever's Skyborne: both races are named "Skyborne", told apart by race ID
_G.UnitRace = function() return "High Order Skyborne", "Skyborne", 95 end
_G.UnitFactionGroup = function() return nil end
local side, races = ns.Finder.Side()
suite.check("a High Order Skyborne is Alliance by race ID", side == "Alliance")
suite.check("and gets every Alliance race's quests", races == ns.Finder.ALLIANCE_RACES)
_G.UnitRace = function() return "Windshaper Skyborne", "Skyborne", 96 end
suite.check("a Windshaper Skyborne is Horde", (ns.Finder.Side()) == "Horde")
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitRace = function() return "Windshaper Skyborne", "Skyborne", 96 end
suite.check("the game's own side wins over the race ID", (ns.Finder.Side()) == "Alliance")

_G.UnitRace = function() return "High Order Skyborne", "Skyborne", 95 end
local alliance = ns.Finder:Player()
local offered
for _, source in ipairs(ns.Finder:SourcesFor(1001, alliance)) do
    if source.kind == "quest" and source.questID == 90001 then offered = true end
end
suite.check("an Alliance Skyborne is not offered a quest only the Horde saw", not offered)
S.QUESTS[90200] = { "Horde Only", 1, 5, 2 + 16 + 32 + 128, 0, "Zed", 215, 1, 1, "" }
S.ITEMS[1001].q[#S.ITEMS[1001].q + 1] = 90200
offered = false
for _, source in ipairs(ns.Finder:SourcesFor(1001, alliance)) do
    if source.kind == "quest" and source.questID == 90200 then offered = true end
end
suite.check("nor a Classic Horde quest", not offered)

-- Once the Alliance is offered it too, it is both sides'
window.id, window.title, window.npc = 90001, "A New Errand", "Bob"
_G.GetQuestID = function() return window.id end
window.choices, window.rewards = { "item:1001" }, { "item:1002" }
_G.C_Item.GetItemInfoInstant = function(id) return id, "Armor", "Mail", "INVTYPE_CHEST" end
Learn:OnQuestWindow(true)
suite.check("seen by both sides, it is both sides'", ns.db.learnedQuests[90001].side == "AH"
    and S.QUESTS[90001][4] == 0)

-- A record kept before sides were noted stays both sides'
ns.db.learnedQuests[90001].side = nil
Learn:OnQuestWindow(true)
suite.check("an older record is not given a side", ns.db.learnedQuests[90001].side == nil)

suite.done()
