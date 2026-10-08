-- Gear tied to a reputation is the last thing the upgrade quest offers on
-- its own (asked 2026-10-08): it is picked only when nothing else on the tab
-- will do, and can still be followed from the finder by hand.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("repquest")

local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end
local function Gear(loc, n) return { loc = loc, class = 4, subclass = 2, stats = Agi(n) } end

local ITEMS = {
    ["item:900"] = Gear("INVTYPE_CHEST", 10),   -- worn
    ["item:1001"] = Gear("INVTYPE_CHEST", 40),  -- a quartermaster's, Friendly
    ["item:1002"] = Gear("INVTYPE_CHEST", 20),  -- an ordinary vendor's
    ["item:1003"] = Gear("INVTYPE_CHEST", 60),  -- Exalted, not reached
}

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitRace = function() return "Human", "Human", 1 end
_G.GetRealZoneText = function() return "Elwynn Forest" end
env.InstallItems(ITEMS, { [5] = "item:900" }, { [0] = {} }, 20)
_G.C_QuestLog = {
    IsQuestFlaggedCompleted = function() return false end,
    IsOnQuest = function() return false end,
    ReadyForTurnIn = function() return false end,
}
-- Friendly with Stormwind.
_G.C_Reputation = {
    GetFactionDataByID = function(id)
        if id == 72 then return { name = "Stormwind", reaction = 5 } end
    end,
}

local S = ns.Sources
ns.Crafts.ITEMS = {}
ns.RollData.ITEMS = {}
S.ZONES = { [12] = "Elwynn Forest" }
S.NPCS = { [1] = { "Corina Steele", 12, 41.5, 65.9, "A" } }
S.QUESTS = {}
S.DUNGEONS = {}
S.BOSSES = {}
S.FOREVER = {}
S.FACTIONS = { [72] = "Stormwind" }
S.ITEMS = {
    [1001] = { 15, 18, 0, 0, 12050, v = { 1, 0 }, r = { 72, 4 } },
    [1002] = { 15, 18, 0, 0, 12050, v = { 1, 0 } },
    [1003] = { 15, 18, 0, 0, 12050, v = { 1, 0 }, r = { 72, 7 } },
}

local Quest, Finder = ns.UpgradeQuest, ns.Finder

suite.check("gear asking for a standing is reputation gear", Finder.Rep(1001) and Finder.Rep(1003))
suite.check("ordinary gear is not", not Finder.Rep(1002))
suite.check("a standing reached asks nothing more", Finder:Needs(1001) == nil)

local found = Finder:Scan()
local chest = found and found.all[5] or {}
local seen = {}
for _, pick in ipairs(chest) do seen[pick.itemID] = pick end
suite.check("the scan marks reputation gear", seen[1001] and seen[1001].rep and seen[1002] and not seen[1002].rep)

ns.HandleSlash("quest")
local quest = Quest:Current()
suite.check("the quest takes the ordinary upgrade over a better reputation one",
    quest and quest.itemID == 1002, quest and quest.itemID)

-- Skipped, nothing else is left on the tab but the reputation gear.
ns.HandleSlash("quest skip")
quest = Quest:Current()
suite.check("with nothing else, the reputation gear reached is offered",
    quest and quest.itemID == 1001, quest and quest.itemID)
suite.check("never gear whose standing is not reached", not (quest and quest.itemID == 1003))

-- Picked by hand from the finder, reputation gear is followed and kept.
ns.charDB.upgradeQuestTabs = {}
Quest:Skipped()[1002] = nil
quest = Quest:Follow(seen[1001])
suite.check("following reputation gear by hand still works", quest and quest.itemID == 1001)
Quest:Update()
suite.check("and it is kept", Quest:Current() and Quest:Current().itemID == 1001)

-- The finder keeps a slot's few best. When reputation gear fills them, the
-- ordinary upgrade pushed out of the short list is still found.
local function Pick(itemID, gain, rep)
    return { itemID = itemID, gain = gain, rep = rep, result = {},
        sources = { { kind = "vendor", zone = "Elwynn Forest" } } }
end
local short = { Pick(1, 9, true), Pick(2, 8, true), Pick(3, 7, true) }
local whole = { short[1], short[2], short[3], Pick(4, 2) }
local best = Quest:Choose({ slots = { [5] = short }, all = { [5] = whole } }, nil, "vendor")
suite.check("an ordinary upgrade past the short list beats reputation gear",
    best and best.pick.itemID == 4, best and best.pick.itemID)
best = Quest:Choose({ slots = { [5] = short }, all = { [5] = short } }, nil, "vendor")
suite.check("with none, the best reputation gear", best and best.pick.itemID == 1, best and best.pick.itemID)

suite.done()
