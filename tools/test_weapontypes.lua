-- Weapon types: a player can count one kind of weapon above another (a
-- rogue preferring daggers to swords). Nothing changes until they do, the
-- numbers are kept apart from the stat weights, and reset puts them back.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("weapontypes")

local WEAPON, DAGGER, SWORD, MACE_2H = 2, 15, 7, 5

local ITEMS = {
    -- Worn: a dagger, 10 agility and 10 dps (10 + 60 = 70 for Combat).
    ["item:1"] = { loc = "INVTYPE_WEAPONMAINHAND", class = WEAPON, subclass = DAGGER,
        stats = { ITEM_MOD_AGILITY_SHORT = 10, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 10 } },
    -- In the bags: a sword, 12 agility and 10 dps (72).
    ["item:2"] = { loc = "INVTYPE_WEAPONMAINHAND", class = WEAPON, subclass = SWORD,
        stats = { ITEM_MOD_AGILITY_SHORT = 12, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 10 } },
    -- Gloves, to show armor is never touched.
    ["item:3"] = { loc = "INVTYPE_HAND", class = 4, subclass = 2,
        stats = { ITEM_MOD_AGILITY_SHORT = 5 } },
}

local function LoadRogue()
    local ns = env.Load()
    _G.UnitClass = function() return "Rogue", "ROGUE" end
    env.InstallItems(ITEMS, { [16] = "item:1" }, { [0] = { [1] = "item:2", [2] = "item:3" } }, 20)
    return ns
end

local ns = LoadRogue()
local Weights, Compare = ns.Weights, ns.Compare

-- As built in, nothing changes.
suite.check("the sword is an upgrade as built in",
    Compare:Judge("item:2").verdict == "upgrade", Compare:Judge("item:2").verdict)
suite.check("every kind counts as 1", Weights:TypeFactor("ROGUE", "combat", DAGGER) == 1)
suite.check("nothing is saved until something is", ns.db.weaponTypeWeights == nil)
suite.check("and nothing reads as changed", not Weights:IsTypeCustom("ROGUE", "combat"))

-- The kinds offered are the ones the class can hold.
local kinds = {}
for _, entry in ipairs(Weights:WeaponTypesFor("ROGUE")) do kinds[entry.key] = entry.name end
suite.check("a rogue is offered daggers", kinds[DAGGER] == "Daggers")
suite.check("but not two-handed maces", kinds[MACE_2H] == nil)
suite.check("a druid is never offered wands", not (function()
    for _, entry in ipairs(Weights:WeaponTypesFor("DRUID")) do
        if entry.key == 19 then return true end
    end
end)())

-- Daggers count a fifth higher: 84 against 72.
local kept = Weights:SetTypeFactor("ROGUE", "combat", DAGGER, 1.2)
suite.check("a kind can be set", kept == 1.2, kept)
suite.check("it is saved apart from the stat weights",
    ns.db.weaponTypeWeights.ROGUE.combat[DAGGER] == 1.2 and ns.db.customWeights == nil)
suite.check("it reads as changed", Weights:IsTypeCustom("ROGUE", "combat", DAGGER))
suite.check("now the sword is a downgrade",
    Compare:Judge("item:2").verdict == "downgrade", Compare:Judge("item:2").verdict)
suite.check("the weights table still holds only stats", (function()
    for _, value in pairs(Weights:ForPlayer()) do
        if type(value) ~= "number" then return false end
    end
    return true
end)())
suite.check("other specs are untouched", Weights:TypeFactor("ROGUE", "sub", DAGGER) == 1)
suite.check("armor is never multiplied", Compare:ScoreOf("item:3", Weights:ForPlayer()) == 5,
    Compare:ScoreOf("item:3", Weights:ForPlayer()))

-- Clamping, rounding and refusals.
suite.check("above the most is kept as the most",
    Weights:SetTypeFactor("ROGUE", "combat", SWORD, 50) == Weights.MAX_TYPE)
suite.check("below 0 is kept as 0", Weights:SetTypeFactor("ROGUE", "combat", SWORD, -1) == 0)
suite.check("0 leaves the kind out", Compare:ScoreOf("item:2", Weights:ForPlayer()) == 0)
suite.check("decimals are kept to two places",
    Weights:SetTypeFactor("ROGUE", "combat", SWORD, 0.333) == 0.33)
suite.check("a kind the class cannot hold is refused",
    Weights:SetTypeFactor("ROGUE", "combat", MACE_2H, 2) == nil)
suite.check("so is text that is not a number",
    Weights:SetTypeFactor("ROGUE", "combat", SWORD, "lots") == nil)
Weights:SetTypeFactor("ROGUE", "combat", SWORD, 1)
suite.check("setting 1 forgets the change", ns.db.weaponTypeWeights.ROGUE.combat[SWORD] == nil)

-- Saved numbers survive a reload.
local saved = ns.db
ns = env.Load()
_G.BlackthornesEquipmentDB = saved
ns.LoadSavedVariables()
_G.UnitClass = function() return "Rogue", "ROGUE" end
env.InstallItems(ITEMS, { [16] = "item:1" }, { [0] = { [1] = "item:2" } }, 20)
suite.check("kinds survive a reload", ns.Weights:TypeFactor("ROGUE", "combat", DAGGER) == 1.2)
suite.check("and the verdict with them", ns.Compare:Judge("item:2").verdict == "downgrade")

-- Junk saved where a number should be is skipped, never removed.
saved.weaponTypeWeights.ROGUE.combat[SWORD] = "junk"
ns.Weights:Changed()
suite.check("junk counts as 1", ns.Weights:TypeFactor("ROGUE", "combat", SWORD) == 1)

-- Reset puts the kinds back with the stats, and leaves junk be.
ns.Weights:Reset("ROGUE", "combat")
suite.check("reset forgets the kinds", not ns.Weights:IsTypeCustom("ROGUE", "combat"))
suite.check("and leaves junk where it was", saved.weaponTypeWeights.ROGUE.combat[SWORD] == "junk")
suite.check("the sword is an upgrade again", ns.Compare:Judge("item:2").verdict == "upgrade")

-- The weights window lists the rogue's kinds and steps them by a tenth.
local WeightsUI = ns.WeightsUI
WeightsUI:Show()
local function TypeRow(key)
    for _, row in ipairs(WeightsUI.typeRows) do
        if row.entry.key == key then return row end
    end
end
suite.check("the window shows daggers for a rogue", TypeRow(DAGGER):IsShown())
suite.check("but not two-handed maces", not TypeRow(MACE_2H):IsShown())
suite.check("under a heading", WeightsUI.typeHeading:IsShown())
suite.check("a kind shows 1", TypeRow(DAGGER).box:GetText() == "1", TypeRow(DAGGER).box:GetText())
TypeRow(DAGGER).plus:GetScript("OnClick")(TypeRow(DAGGER).plus)
suite.check("+ adds a tenth", ns.Weights:TypeFactor("ROGUE", "combat", DAGGER) == 1.1,
    ns.Weights:TypeFactor("ROGUE", "combat", DAGGER))
suite.check("the row is marked as changed", TypeRow(DAGGER).mark:IsShown())
suite.check("the status counts it",
    WeightsUI.status:GetText():find("1 weapon type changed", 1, true), WeightsUI.status:GetText())
suite.check("and reset appears", WeightsUI.reset:IsShown())
WeightsUI:Commit(TypeRow(SWORD), "0.8")
suite.check("a typed number is kept", ns.Weights:TypeFactor("ROGUE", "combat", SWORD) == 0.8)
WeightsUI.reset:GetScript("OnClick")(WeightsUI.reset)
suite.check("the reset button puts them back",
    not ns.Weights:IsTypeCustom("ROGUE", "combat") and TypeRow(DAGGER).box:GetText() == "1")
for _, row in ipairs(WeightsUI.typeRows) do
    suite.check(row.entry.name .. " fits its label", row.label:GetWidth() >= #row.entry.name * 6)
end

suite.done()
