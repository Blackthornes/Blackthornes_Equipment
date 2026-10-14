-- Random rolls ("of the Monkey"): reading the roll off a link, naming it from
-- the stats it adds, judging gear at its best roll, and the tooltip line.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("rolls")

local function Chest(stats)
    return { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = stats }
end

local ITEMS = {
    ["item:900"] = Chest({ ITEM_MOD_AGILITY_SHORT = 10 }),   -- worn
    -- A green with three rolls; the plain item has armor only.
    ["item:4000"] = Chest({ RESISTANCE0_NAME = 50 }),
    ["item:4000::::::1"] = Chest({ RESISTANCE0_NAME = 50, ITEM_MOD_AGILITY_SHORT = 8, ITEM_MOD_STAMINA_SHORT = 8 }),
    ["item:4000::::::2"] = Chest({ RESISTANCE0_NAME = 50, ITEM_MOD_INTELLECT_SHORT = 8, ITEM_MOD_SPIRIT_SHORT = 8 }),
    ["item:4000::::::3"] = Chest({ RESISTANCE0_NAME = 50, ITEM_MOD_AGILITY_SHORT = 20 }),
    -- A roll no name is known for.
    ["item:4000::::::4"] = Chest({ RESISTANCE0_NAME = 50, ITEM_MOD_AGILITY_SHORT = 4, ITEM_MOD_SPIRIT_SHORT = 4,
        ITEM_MOD_STAMINA_SHORT = 2 }),
}

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitRace = function() return "Human", "Human", 1 end
env.InstallItems(ITEMS, { [5] = "item:900" }, {}, 20)

local Rolls = ns.Rolls

suite.check("the roll is the link's eighth field",
    Rolls.RollOf("|cff1eff00|Hitem:4000:0:0:0:0:0:1:0:20|h[Chain Vest of the Monkey]|h|r") == 1)
suite.check("empty fields count too", Rolls.RollOf("item:4000::::::3") == 3)
suite.check("no roll is nil", Rolls.RollOf("item:4000") == nil and Rolls.RollOf("item:4000:0:0:0:0:0:0") == nil)
suite.check("nothing is nil", Rolls.RollOf(nil) == nil and Rolls.RollOf("junk") == nil)
suite.check("a rolled link is made the same way", Rolls.Link(4000, 2) == "item:4000::::::2")

local name, stats = Rolls:Describe("item:4000::::::1")
suite.check("named from the stats it adds", name == "of the Monkey", name)
suite.check("and what it adds, armor left out", stats == "+8 Agility, +8 Stamina", stats)
name, stats = Rolls:Describe("item:4000::::::2")
suite.check("the owl", name == "of the Owl" and stats == "+8 Intellect, +8 Spirit", stats)
name, stats = Rolls:Describe("item:4000::::::3")
suite.check("a single stat", name == "of Agility" and stats == "+20 Agility", stats)
name, stats = Rolls:Describe("item:4000::::::4")
suite.check("a roll without a known name is described by its stats", name == nil
    and stats == "+4 Agility, +4 Spirit, +2 Stamina", stats)
suite.check("a roll the client cannot read says nothing", Rolls:Describe("item:4000::::::9") == nil)

suite.check("percent reads plainly", Rolls.Percent(40) == "40%" and Rolls.Percent(4.5) == "4.5%"
    and Rolls.Percent(3) == "3%" and Rolls.Percent(0.2) == "< 1%")

--------------------------------------------------------------------------------
-- Best roll, and the finder
--------------------------------------------------------------------------------

ns.Crafts.ITEMS = {}
ns.RollData.GROUPS = { [7] = { 1, 30, 2, 60, 3, 10 } }
ns.RollData.ITEMS = { [4000] = 7 }

local best = Rolls:Best(4000)
suite.check("a hunter's best roll is the most agility", best and best.roll == 3, best and best.roll)
suite.check("with its chance", best.chance == 10)
suite.check("and how often it drops as an upgrade at all", best.upgradeChance == 40, best.upgradeChance)
suite.check("every roll was judged", best.rolls == 3)
suite.check("gear without rolls has no best roll", Rolls:Best(900) == nil)

local S = ns.Sources
S.ZONES = { [12] = "Elwynn Forest" }
S.NPCS = {}
S.QUESTS = {}
S.DUNGEONS = { ["36"] = { "The Deadmines", 17, 26, "Westfall", "" } }
S.BOSSES = { [100] = { "Edwin VanCleef", "36", 21 } }
S.FOREVER = {}
S.ITEMS = { [4000] = { 15, 18, 0, 0, 0, d = { 100, 5 } } }

local found = ns.Finder:Scan()
local pick = found.slots[5] and found.slots[5][1]
suite.check("the finder offers it at its best roll", pick and pick.roll and pick.roll.link == "item:4000::::::3",
    pick and pick.link)
suite.check("shown by the client's link, or the plain item's when it has none", pick.link == "item:4000",
    pick.link)
suite.check("and says so", ns.Finder.RollText(pick) == "Best roll of Agility: 10% of drops, and 40% of drops are an upgrade",
    ns.Finder.RollText(pick))
suite.check("gear without rolls has no roll text", ns.Finder.RollText({}) == nil)

--------------------------------------------------------------------------------
-- The tooltip line
--------------------------------------------------------------------------------

local lines = ns.Tooltip:MoreLines("item:4000::::::1")
suite.check("the tooltip names the roll", lines[1] and lines[1][1] == "of the Monkey: +8 Agility, +8 Stamina",
    lines[1] and lines[1][1])
lines = ns.Tooltip:MoreLines("item:4000::::::4")
suite.check("or describes it", lines[1] and lines[1][1] == "Random roll: +4 Agility, +4 Spirit, +2 Stamina")
suite.check("nothing for gear without a roll", #ns.Tooltip:MoreLines("item:900") == 0)
ns.db.suffixLine = false
suite.check("and nothing with the setting off", #ns.Tooltip:MoreLines("item:4000::::::1") == 0)
ns.db.suffixLine = true

suite.done()
