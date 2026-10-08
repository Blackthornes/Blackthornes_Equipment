-- A quest that starts from an item says where to get the item: the mob
-- that drops it, its level, zone and spot, and the map pin goes there
-- (asked 2026-10-08: "it starts from Demon Scarred Cloak" said nothing).

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("queststarts")

local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end
local function Gear(loc, n) return { loc = loc, class = 4, subclass = 2, stats = Agi(n) } end

local ITEMS = {
    ["item:900"] = Gear("INVTYPE_CHEST", 10),   -- worn
    ["item:1002"] = Gear("INVTYPE_CHEST", 30),  -- quest reward
}

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitFactionGroup = function() return "Horde", "Horde" end
_G.UnitRace = function() return "Tauren", "Tauren", 6 end
local zone = "Thunder Bluff"
_G.GetRealZoneText = function() return zone end
env.InstallItems(ITEMS, { [5] = "item:900" }, { [0] = {} }, 10)

local onQuest = false
_G.C_QuestLog = {
    IsQuestFlaggedCompleted = function() return false end,
    IsOnQuest = function(id) return id == 770 and onQuest end,
    ReadyForTurnIn = function() return false end,
}
local held = 0
local count = _G.C_Item.GetItemCount
_G.C_Item.GetItemCount = function(id, ...)
    if id == 4854 then return held end
    return count and count(id, ...) or 0
end

local S = ns.Sources
ns.Crafts.ITEMS = {}
ns.RollData.ITEMS = {}
S.ZONES = { [215] = "Mulgore" }
S.NPCS = {}
S.QUESTS = { [770] = { "The Demon Scarred Cloak", 8, 12, 0, 0, "Demon Scarred Cloak", 0, 0, 0, "" } }
S.DUNGEONS = { ["209"] = { "Zul'Farrak", 44, 54, "Tanaris", "" } }
S.BOSSES = {}
S.FOREVER = {}
S.ITEMS = { [1002] = { 8, 12, 0, 0, 0, q = { 770 } } }
S.STARTS = {
    [770] = { 4854, "Demon Scarred Cloak", 3,
        { "mob", "Ghost Howl", "Mulgore", 37.3, 14.2, 12, 12, 100, "rare" },
        { "mob", "Prairie Wolf", "Mulgore", 50, 50, 5, 6, 2, "" } },
}

local Quest = ns.UpgradeQuest

local function Texts()
    local texts = {}
    for _, step in ipairs((Quest:Steps())) do texts[#texts + 1] = step.text end
    return table.concat(texts, " | ")
end

ns.HandleSlash("quest quest")
local quest = Quest:Current()
suite.check("the quest reward is picked", quest and quest.itemID == 1002)

local steps = Quest:Steps()
suite.check("the steps say where the item drops", Texts() == "Travel to Mulgore"
    .. " | Get Demon Scarred Cloak from Ghost Howl (level 12, rare) in Mulgore (37.3, 14.2)"
    .. " | Right-click Demon Scarred Cloak in your bags to start The Demon Scarred Cloak"
    .. " | Complete The Demon Scarred Cloak (level 12)"
    .. " | Hand it in and choose item:1002 | Put on item:1002", Texts())
suite.check("the note says it is a rare and who else drops it",
    steps[2].note:find("A rare", 1, true) ~= nil and steps[2].note:find("Also from Prairie Wolf and 1 more", 1, true) ~= nil,
    steps[2].note)
local place = Quest:NextPlace()
suite.check("from elsewhere, first the zone", place and place.zone == "Mulgore")
zone = "Mulgore"
place = Quest:NextPlace()
suite.check("the next place is the mob's spot", place and place.name == "Ghost Howl" and place.x == 37.3
    and place.zone == "Mulgore", place and place.name)

zone = "Thunder Bluff"

-- With the item in the bags, only using it is left.
held = 1
suite.check("holding it, the step is to use it", Texts():find("^Right%-click Demon Scarred Cloak in your bags") ~= nil,
    Texts())
held = 0
onQuest = true
local _, current = Quest:Steps()
suite.check("on the quest, the next step is to complete it", (Quest:Steps())[current].text:find("^Complete") ~= nil)
onQuest = false

-- A boss drop: the dungeon is the place, its door the zone to travel to.
S.STARTS[770] = { 4854, "Demon Scarred Cloak", 1, { "boss", "Gahz'rilla", "Zul'Farrak", 0, 0, 46, 46, 100, "" } }
suite.check("a boss drop names the dungeon", Texts():find("Get Demon Scarred Cloak from Gahz'rilla (level 46) in Zul'Farrak", 1, true) ~= nil,
    Texts())
suite.check("and travels to its door", Texts():find("^Travel to Tanaris") ~= nil, Texts())

-- Nothing known: says so, and makes up no place.
S.STARTS[770] = nil
suite.check("an unknown item says it is not known",
    Texts():find("Find Demon Scarred Cloak, the item that starts The Demon Scarred Cloak", 1, true) ~= nil, Texts())
suite.check("with no place", Quest:NextPlace() == nil)

suite.done()
