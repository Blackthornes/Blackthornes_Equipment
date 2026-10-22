-- The best enchant for each worn piece: what is on it now, what fits, how
-- much each helps for the spec, who can make it, and what Tradeskills reads.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("enchants")

local ITEMS = {
    ["item:900"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = { ITEM_MOD_AGILITY_SHORT = 10 } },
    ["item:920:247"] = { loc = "INVTYPE_WRIST", class = 4, subclass = 2, stats = { ITEM_MOD_AGILITY_SHORT = 10 } },
    ["item:921:6"] = { loc = "INVTYPE_WRIST", class = 4, subclass = 2, stats = { ITEM_MOD_AGILITY_SHORT = 10 } },
    ["item:930"] = { loc = "INVTYPE_2HWEAPON", class = 2, subclass = 1,
        stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 10 } },
    ["item:940"] = { loc = "INVTYPE_SHIELD", class = 4, subclass = 6, stats = { ITEM_MOD_STAMINA_SHORT = 4 } },
    ["item:950"] = { loc = "INVTYPE_RANGEDRIGHT", class = 2, subclass = 19, stats = {} },
}

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitRace = function() return "Human", "Human", 1 end
env.InstallItems(ITEMS, { [5] = "item:900", [9] = "item:920:247", [16] = "item:930", [17] = "item:940",
    [18] = "item:950" }, {}, 30)

local C = ns.Crafts
C.PROFESSIONS = { [333] = "Enchanting", [165] = "Leatherworking" }
C.MATERIALS = { [10940] = { "Strange Dust", 100 }, [10938] = { "Lesser Magic Essence", 300 } }

ns.EnchantData = {
    RECIPES = {
        [100] = { e = 1, line = 333, slots = { 5 }, k = 50, m = { 10938, 2 }, name = "Enchant Chest - Agility" },
        [101] = { e = 2, line = 333, slots = { 5 }, k = 1, m = { 10940, 1 }, name = "Enchant Chest - Health" },
        [102] = { e = 3, line = 333, slots = { 9 }, k = 150, m = { 10940, 2 }, name = "Enchant Bracer - Agility" },
        [103] = { e = 247, line = 333, slots = { 9 }, k = 80, name = "Enchant Bracer - Minor Agility" },
        [104] = { e = 4, line = 333, slots = { 16 }, w = 2, k = 50, m = { 10940, 1 }, name = "Enchant 2H Weapon - Impact" },
        [105] = { e = 5, line = 333, slots = { 16 }, w = 1, k = 50, name = "Enchant Weapon - Striking" },
        [106] = { e = 7, line = 333, slots = { 17 }, k = 50, name = "Enchant Shield - Stamina" },
        [107] = { e = 8, line = 165, slots = { 5, 7, 8, 10 }, k = 1, m = { 10940, 2 }, kit = 2304,
            name = "Light Armor Kit" },
        [108] = { e = 9, line = 333, slots = { 15 }, k = 1, name = "Enchant Cloak - Agility" },
        [109] = { e = 10, line = 202, slots = { 18 }, w = 3, k = 60, kit = 4405, name = "Crude Scope" },
    },
    EFFECTS = {
        [1] = { s = { agility = 5 } },
        [2] = { s = { health = 10 } },
        [3] = { s = { agility = 5 } },
        [4] = { dmg = 9 },
        [5] = { dmg = 3 },
        [6] = { other = 1, n = "+10 Fire Resistance" },
        [7] = { s = { stamina = 5 } },
        [8] = { s = { armor = 8, stamina = 1 } },
        [9] = { s = { agility = 3 } },
        [10] = { dmg = 2 },
        [247] = { s = { agility = 3 }, n = "Agility +3" },
    },
    MATERIALS = {},
}

local WEIGHTS = { agility = 1, stamina = 0.5, armor = 0.01, meleeDps = 2, rangedDps = 3 }
ns.Weights.ForPlayer = function() return WEIGHTS end

-- Enchanting at 100.
_G.C_TradeSkillUI = {
    GetAllProfessionTradeSkillLines = function() return { 2940 } end,
    GetProfessionInfoBySkillLineID = function()
        return { professionName = "Enchanting", skillLevel = 100, maxSkillLevel = 150 }
    end,
}
_G.IsPlayerSpell = function(id) return id == 101 end

local E = ns.Enchants
ns.db.enchantTooltip = nil

--------------------------------------------------------------------------------
-- Reading
--------------------------------------------------------------------------------

suite.check("no enchant reads as none", E.EnchantOf("item:900") == nil and E.EnchantOf("item:900:0:0") == nil)
suite.check("an enchant is read off the link", E.EnchantOf("|cff1eff00|Hitem:920:247:0:0|h[Bracers]|h|r") == 247)
local health = E:StatsOf(2, "INVTYPE_CHEST")
suite.check("health counts as the stamina that gives it", health.stamina == 1, health.stamina)
local damage = E:StatsOf(4, "INVTYPE_2HWEAPON")
suite.check("weapon damage counts at a two-hander's speed", math.abs(damage.dps - 9 / 3.3) < 0.001)
suite.check("an unknown enchant is nil", E:StatsOf(99999, "INVTYPE_CHEST") == nil)

--------------------------------------------------------------------------------
-- Plans
--------------------------------------------------------------------------------

local plans = E:Plans()
local chest = plans[5]
suite.check("the chest has a plan", chest ~= nil)
suite.check("best first", chest.picks[1].recipeID == 100 and chest.picks[2].recipeID == 107 and chest.picks[3].recipeID == 101,
    chest.picks[1] and chest.picks[1].recipeID)
suite.check("percent of the piece's own score", math.floor(chest.picks[1].percent + 0.5) == 50,
    chest.picks[1].percent)
suite.check("a kit that fits shows too", (function()
    for _, pick in ipairs(chest.picks) do if pick.recipeID == 107 then return true end end
end)())

local wrist = plans[9]
suite.check("what's on it now is read", wrist.current == 247 and wrist.currentScore == 3)
suite.check("only what beats it is offered", #wrist.picks == 1 and wrist.picks[1].recipeID == 102)
suite.check("and by the gain over it", math.floor(wrist.picks[1].percent + 0.5) == 20, wrist.picks[1].percent)

local weapon = plans[16]
suite.check("a two-hander takes both kinds", #weapon.picks == 2 and weapon.picks[1].recipeID == 104)

suite.check("a shield takes the shield's enchant", plans[17] and plans[17].picks[1].recipeID == 106)
suite.check("a wand takes no scope", plans[18] == nil)
suite.check("an empty slot has no plan", plans[15] == nil)
suite.check("plans are kept", E:Plans() == plans)

-- An enchant stats can't weigh is the player's choice.
env.worn[9] = "item:921:6"
E:GearChanged()
plans = E:Plans()
suite.check("a gear change is seen", plans[9].current == 6)
suite.check("nothing is offered over a resistance", #plans[9].picks == 0 and plans[9].unknown)
env.worn[9] = "item:920:247"
E:GearChanged()

-- A one-handed weapon takes only the any-weapon enchants.
ITEMS["item:931"] = { loc = "INVTYPE_WEAPON", class = 2, subclass = 7, stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 5 } }
env.worn[16] = "item:931"
E:GearChanged()
plans = E:Plans()
suite.check("a one-hander can't take a two-hand enchant", #plans[16].picks == 1 and plans[16].picks[1].recipeID == 105)
env.worn[16] = "item:930"
E:GearChanged()

--------------------------------------------------------------------------------
-- Who can make it
--------------------------------------------------------------------------------

suite.check("a recipe you know", E:Source(101).state == "known")
suite.check("one you can learn", E:Source(100).state == "learn")
suite.check("one you need more skill for", E:Source(102).state == "skill" and E:Source(102).have == 100)
local kit = E:Source(107)
suite.check("a kit from a profession you lack", kit.state == "other" and kit.kit == 2304)
suite.check("in words", E:Describe(kit, ns.Finder.Money):find("Made with Leatherworking 1", 1, true) == 1,
    E:Describe(kit, ns.Finder.Money))
suite.check("materials priced", E:Source(100).cost == 600)
suite.check("learn in words", E:Describe(E:Source(100)):find("You can learn it (Enchanting 50)", 1, true) == 1,
    E:Describe(E:Source(100)))

--------------------------------------------------------------------------------
-- The line: an upgrade waiting makes the cheapest worth having the pick
--------------------------------------------------------------------------------

local line = E:Line(5)
suite.check("the best is the pick", line.pick.recipeID == 100 and not line.soon)
ns.Finder.latest = { slots = { [5] = { { itemID = 1 } } } }
line = E:Line(5)
suite.check("an upgrade waiting picks the cheapest", line.pick.recipeID == 101 and line.soon,
    line.pick.recipeID)
ns.Finder.latest = nil
suite.check("lines in order", E:Lines()[1].slot == 5)

--------------------------------------------------------------------------------
-- For Tradeskills
--------------------------------------------------------------------------------

local answer = E:ForRecipe(100)
suite.check("a recipe that helps says where and how much", answer and answer.slot == "Chest"
    and answer.slotID == 5 and answer.gain == 50 and answer.best == true, answer and answer.gain)
answer = E:ForRecipe(102)
suite.check("it names what it would replace", answer and answer.current == "Agility +3")
suite.check("not the best for its slot", E:ForRecipe(101).best == nil)
suite.check("one that helps nothing worn", E:ForRecipe(103) == nil and E:ForRecipe(108) == nil)
suite.check("a recipe it doesn't know", E:ForRecipe(424242) == nil and E:ForRecipe("x") == nil)
local copy = E:ForRecipe(100)
copy.gain = 0
suite.check("each answer is a fresh table", E:ForRecipe(100).gain == 50)

--------------------------------------------------------------------------------
-- The tooltip line
--------------------------------------------------------------------------------

suite.check("the tooltip names the best", E:TooltipLine("item:900") == "Best enchant: Enchant Chest - Agility (+50%)",
    E:TooltipLine("item:900"))
suite.check("not on gear that isn't worn", E:TooltipLine("item:931") == nil)
ns.db.enchantTooltip = false
suite.check("the setting turns it off", E:TooltipLine("item:900") == nil)
ns.db.enchantTooltip = nil

--------------------------------------------------------------------------------
-- Queue it and Show the way, through Tradeskills
--------------------------------------------------------------------------------

suite.check("no Tradeskills, no queue", not E:CanQueue() and not E:CanShowTheWay(100))
local ensured, bought, pinned = {}, {}, {}
_G.BlackthornesTS = {
    Queue = {
        Ensure = function(_, recipeID, count) ensured[#ensured + 1] = { recipeID, count } return true end,
        EnsureBuy = function(_, itemID, count, forItem, forRecipe)
            bought[#bought + 1] = { itemID, count, forItem, forRecipe and forRecipe.recipeID }
            return true
        end,
    },
    LearnNext = {
        WhereFor = function(_, recipeID)
            if recipeID == 100 then return { kind = "trainer", name = "Lavinia Crowe", zone = "Stormwind City" } end
        end,
        ShowTheWayFor = function(_, recipeID) pinned[#pinned + 1] = recipeID return true end,
    },
}
suite.check("Tradeskills, a queue", E:CanQueue())
suite.check("a recipe you know is queued", E:Queue(101) and ensured[1][1] == 101 and ensured[1][2] == 1)
suite.check("one to learn puts its materials on the list", E:Queue(100) and bought[1][1] == 10938
    and bought[1][2] == 2 and bought[1][4] == 100)
suite.check("a kit nobody makes goes on the list", E:Queue(107) and bought[2][1] == 2304 and bought[2][3] == 2304)
suite.check("where to learn it", E:WhereToLearn(100).name == "Lavinia Crowe" and E:CanShowTheWay(100)
    and not E:CanShowTheWay(102))
suite.check("Show the way asks Tradeskills", E:ShowTheWay(100) and pinned[1] == 100)
_G.BlackthornesTS.LearnNext.WhereFor = function() error("boom") end
suite.check("an error is no place", E:WhereToLearn(100) == nil)
_G.BlackthornesTS = false

--------------------------------------------------------------------------------
-- The Enchants view in Find Upgrades
--------------------------------------------------------------------------------

local UI = ns.FinderUI
E:Forget()
UI:SetFilter("enchant")
UI:Show()
suite.check("the view is picked and kept", ns.db.finderShow == "enchant" and UI:ShowingEnchants())
local lit = 0
for _, button in ipairs(UI.slotButtons) do
    if button.count:GetText() == "1" then lit = lit + 1 end
end
suite.check("each slot with something better counts one", lit == 4, lit)
suite.check("the first of them shows", #UI.lines == 1 and UI.listTitle:GetText() == "Chest", UI.listTitle:GetText())
suite.check("the gear controls step aside", not UI.ahead:IsShown() and not UI.solo:IsShown()
    and not UI.getNow:IsShown() and not UI.sourceBoxes[1]:IsShown())
suite.check("and the Enchants tab is lit", UI.tabStrip.selected == "enchant", UI.tabStrip.selected)
suite.check("the footer counts them", UI.footer:GetText():find("4 pieces you wear", 1, true) ~= nil,
    UI.footer:GetText())
local row = UI.rows[1]
suite.check("the row is the chest's enchant", row.enchant ~= nil and row.enchant.slot == 5)
suite.check("it names the enchant and its gain", row.item:GetText() == "Enchant Chest - Agility"
    and row.gain:GetText() == "+50%", row.gain:GetText())
suite.check("it says how to get it", row.source:GetText():find("You can learn it", 1, true) ~= nil,
    row.source:GetText())
suite.check("and what's on it now", row.source:GetText():find("Nothing on it now", 1, true) ~= nil)
suite.check("no Tradeskills, no buttons", not row.queueIt:IsShown() and not row.showWay:IsShown())
row:GetScript("OnEnter")(row)
local tip = table.concat(GameTooltip._lines, "\n")
suite.check("the tooltip says what it gives", tip:find("Gives +5", 1, true) ~= nil, tip)
suite.check("and its materials", tip:find("Materials: 2 ", 1, true) ~= nil, table.concat(GameTooltip._lines, " / "))
row:GetScript("OnLeave")(row)

local queued = {}
_G.BlackthornesTS = {
    Queue = {
        Ensure = function() return true end,
        EnsureBuy = function(_, itemID) queued[#queued + 1] = itemID return true end,
    },
    LearnNext = {
        WhereFor = function(_, recipeID) if recipeID == 100 then return { name = "Lavinia Crowe" } end end,
        ShowTheWayFor = function(_, recipeID) pinned[#pinned + 1] = recipeID return true end,
    },
}
UI:Refresh()
suite.check("with Tradeskills, Queue it and Show the way", row.queueIt:IsShown() and row.showWay:IsShown())
row.queueIt:GetScript("OnClick")(row.queueIt)
suite.check("Queue it puts its materials on the list", queued[1] == 10938, queued[1])
row.showWay:GetScript("OnClick")(row.showWay)
suite.check("Show the way asks for the trainer", pinned[#pinned] == 100)
_G.BlackthornesTS = false

UI:SetFilter(nil)
suite.check("back to gear, the controls come back", UI.ahead:IsShown() and UI.solo:IsShown()
    and rawget(UI.rows[1], "enchant") == nil)

suite.done()
