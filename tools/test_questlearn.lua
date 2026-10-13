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

suite.done()
