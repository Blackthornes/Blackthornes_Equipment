-- The player's own stat weights: kept by class and spec, laid over the
-- built-in ones, used by every verdict, and never lost.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("customweights")

local ARMOR, LEATHER = 4, 2

local ITEMS = {
    -- Worn: 10 agility. In the bags: 8 agility and 3 stamina.
    ["item:1"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = LEATHER,
        stats = { ITEM_MOD_AGILITY_SHORT = 10 } },
    ["item:2"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = LEATHER,
        stats = { ITEM_MOD_AGILITY_SHORT = 8, ITEM_MOD_STAMINA_SHORT = 3 } },
}

local function LoadHunter()
    local ns = env.Load()
    _G.UnitClass = function() return "Hunter", "HUNTER" end
    env.InstallItems(ITEMS, { [5] = "item:1" }, { [0] = { [1] = "item:2" } }, 20)
    return ns
end

local ns = LoadHunter()
local Weights, Compare = ns.Weights, ns.Compare

-- Built in: 8 + 1.5 = 9.5 against 10.
suite.check("as built in, the stamina chest is worse",
    Compare:Judge("item:2").verdict == "downgrade", Compare:Judge("item:2").verdict)
suite.check("nothing is changed yet", not Weights:IsCustom("HUNTER", "beast"))
suite.check("and nothing is saved until something is", ns.db.customWeights == nil)

local kept = Weights:SetWeight("HUNTER", "beast", "stamina", 1)
suite.check("a weight can be set", kept == 1, kept)
suite.check("it is saved by class and spec",
    ns.db.customWeights.HUNTER.beast.stamina == 1)
suite.check("the stat reads as changed", Weights:IsCustom("HUNTER", "beast", "stamina"))
suite.check("ForPlayer uses it", Weights:ForPlayer().stamina == 1)
local value, default = Weights:Value("HUNTER", "beast", "stamina")
suite.check("Value gives yours and the built-in one", value == 1 and default == 0.5)
suite.check("the built-in table is untouched", Weights.SPECS.HUNTER.beast.weights.stamina == 0.5)
suite.check("other stats keep their built-in weight", Weights:ForPlayer().agility == 1.0)
suite.check("other specs are untouched", Weights:Get("HUNTER", "marks").stamina == 0.35)

-- 8 + 3 = 11 against 10.
suite.check("now the stamina chest is an upgrade",
    Compare:Judge("item:2").verdict == "upgrade", Compare:Judge("item:2").verdict)
suite.check("for the bag arrow too", Compare:IsUpgradeNow("item:2"))
suite.check("and for Tradeskills' arrows", Compare:IsUpgrade("item:2") == true)

-- Clamping and rounding.
suite.check("below 0 is kept as 0", Weights:SetWeight("HUNTER", "beast", "spirit", -5) == 0)
suite.check("0 wins over the built-in weight", Weights:Get("HUNTER", "beast").spirit == 0)
suite.check("above the most is kept as the most",
    Weights:SetWeight("HUNTER", "beast", "hit", 5000) == Weights.MAX_WEIGHT)
suite.check("decimals are kept to three places",
    Weights:SetWeight("HUNTER", "beast", "armor", 0.1 + 0.2) == 0.3)
suite.check("a stat that does not exist is refused",
    Weights:SetWeight("HUNTER", "beast", "luck", 3) == nil)
suite.check("so is a spec that does not exist",
    Weights:SetWeight("HUNTER", "fury", "stamina", 3) == nil)
suite.check("and text that is not a number",
    Weights:SetWeight("HUNTER", "beast", "stamina", "lots") == nil)
suite.check("which leaves the weight as it was", Weights:Get("HUNTER", "beast").stamina == 1)

-- Back to the built-in value forgets the change.
Weights:SetWeight("HUNTER", "beast", "spirit", 0.1)
suite.check("setting a weight back to built in forgets it",
    ns.db.customWeights.HUNTER.beast.spirit == nil)

-- Saved data survives a reload and a new version's defaults.
local saved = ns.db
ns = env.Load()
_G.BlackthornesEquipmentDB = saved
ns.LoadSavedVariables()
_G.UnitClass = function() return "Hunter", "HUNTER" end
env.InstallItems(ITEMS, { [5] = "item:1" }, { [0] = { [1] = "item:2" } }, 20)
suite.check("weights survive a reload", ns.Weights:Get("HUNTER", "beast").stamina == 1)
suite.check("and the verdict with them", ns.Compare:Judge("item:2").verdict == "upgrade")

-- Junk in the saved table is skipped, never deleted.
ns.db.customWeights.HUNTER.beast.agility = "oops"
ns.Weights:Changed()
suite.check("a value that is not a number is skipped",
    ns.Weights:Get("HUNTER", "beast").agility == 1.0)
suite.check("and left where it was", ns.db.customWeights.HUNTER.beast.agility == "oops")
ns.db.customWeights.HUNTER.marks = "not a table"
suite.check("a spec that is not a table does not break it",
    ns.Weights:Get("HUNTER", "marks").stamina == 0.35)

-- Reset.
ns.Weights:Reset("HUNTER", "beast")
suite.check("reset puts the built-in weights back",
    ns.Weights:Get("HUNTER", "beast").stamina == 0.5 and not ns.Weights:IsCustom("HUNTER", "beast"))
suite.check("reset leaves what it cannot read alone",
    ns.db.customWeights.HUNTER.beast.agility == "oops")
suite.check("the verdict goes back too", ns.Compare:Judge("item:2").verdict == "downgrade")

-- Another class's weights are kept apart.
ns.Weights:SetWeight("MAGE", "frost", "stamina", 2)
suite.check("each class keeps its own", ns.Weights:Get("MAGE", "frost").stamina == 2
    and ns.Weights:Get("HUNTER", "beast").stamina == 0.5)

-- Tradeskills is told to ask again when a weight changes.
local asked = 0
_G.BlackthornesTS = { Upgrades = { RedrawSoon = function() asked = asked + 1 end } }
ns.Weights:SetWeight("HUNTER", "beast", "stamina", 2)
suite.check("Tradeskills redraws its arrows", asked == 1, asked)
_G.BlackthornesTS = { Upgrades = { RedrawSoon = function() error("broken") end } }
suite.check("a Tradeskills that raises does not break it",
    ns.Weights:SetWeight("HUNTER", "beast", "stamina", 3) == 3)
_G.BlackthornesTS = nil
suite.check("and none at all is fine", ns.Weights:SetWeight("HUNTER", "beast", "stamina", 4) == 4)

suite.done()
