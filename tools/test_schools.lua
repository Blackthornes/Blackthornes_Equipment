-- Spell damage for one school ("Increases damage done by Frost spells and
-- effects by up to 10."), which Classic gear carries as an Equip: line the
-- tooltip shows rather than a stat GetItemStats hands back.
--
-- The case a player sent in (2026-10-06): judged as a Frost mage, Colorful
-- Kilt (+5 Spirit, +5 spell damage and healing) was called a +57% upgrade
-- over the Azure Silk Pants worn (+6 Intellect, +10 Frost spell damage),
-- because the Frost damage counted for nothing.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("schools")

local ARMOR, CLOTH = 4, 1
local LEGS = 7

local PANTS, KILT = "item:7062", "item:10055"

local ITEMS = {
    [PANTS] = { loc = "INVTYPE_LEGS", class = ARMOR, subclass = CLOTH, minLevel = 18,
        stats = { ITEM_MOD_INTELLECT_SHORT = 6, RESISTANCE0_NAME = 36 } },
    [KILT] = { loc = "INVTYPE_LEGS", class = ARMOR, subclass = CLOTH, minLevel = 14,
        stats = { ITEM_MOD_SPIRIT_SHORT = 5, ITEM_MOD_SPELL_POWER_SHORT = 5, RESISTANCE0_NAME = 29 } },
    ["item:1"] = { loc = "INVTYPE_LEGS", class = ARMOR, subclass = CLOTH,
        stats = { ITEM_MOD_INTELLECT_SHORT = 6 } },
    ["item:2"] = { loc = "INVTYPE_LEGS", class = ARMOR, subclass = CLOTH,
        stats = { ITEM_MOD_INTELLECT_SHORT = 6 } },
}

local TOOLTIPS = {
    [PANTS] = {
        "Azure Silk Pants", "Soulbound", "36 Armor", "+6 Intellect",
        "Equip: Increases damage done by Frost spells and effects by up to 10.",
    },
    [KILT] = {
        "Colorful Kilt", "Binds when equipped", "29 Armor", "+5 Spirit",
        "Equip: Increases damage and healing done by magical spells and effects by up to 5.",
    },
    ["item:1"] = { "Shadow Pants", "Equip: Increases damage done by Shadow spells and effects by up to 10." },
    ["item:2"] = { "Plain Pants", "+6 Intellect" },
}

local asked = 0
local function InstallTooltips()
    _G.C_TooltipInfo = {
        GetHyperlink = function(link)
            asked = asked + 1
            local lines = {}
            for _, text in ipairs(TOOLTIPS[link] or { "Retrieving item information" }) do
                lines[#lines + 1] = { leftText = text }
            end
            return { lines = lines }
        end,
    }
end

local function LoadAs(class, spec, worn)
    local ns = env.Load()
    _G.UnitClass = function() return class, class end
    env.InstallItems(ITEMS, worn, {}, 25)
    InstallTooltips()
    ns.charDB.spec = spec
    ns.Weights:Changed()
    return ns
end

-- The line itself.
local ns = LoadAs("MAGE", "frost", { [LEGS] = PANTS })
local Items = ns.Items
local stat, amount = Items.SchoolLine("Equip: Increases damage done by Frost spells and effects by up to 10.")
suite.check("a Frost line is read", stat == "frostDamage" and amount == 10, tostring(stat) .. " " .. tostring(amount))
stat = Items.SchoolLine("Equip: Increases damage and healing done by magical spells and effects by up to 5.")
suite.check("the all-schools line is left to the stats", stat == nil, stat)
stat = Items.SchoolLine("+10 Frost Resistance")
suite.check("a resistance is not spell damage", stat == nil, stat)
for _, school in ipairs({ "Arcane", "Fire", "Frost", "Nature", "Shadow", "Holy" }) do
    stat = Items.SchoolLine(("Equip: Increases damage done by %s spells and effects by up to 7."):format(school))
    suite.check(school .. " is read", stat == school:lower() .. "Damage", stat)
end
local damage = Items:SchoolDamage(PANTS)
suite.check("the pants carry 10 Frost damage", damage and damage.frostDamage == 10)

-- The reported case.
local result = ns.Compare:Judge(KILT)
suite.check("the kilt is not an upgrade for a Frost mage", result.verdict == "downgrade",
    result.verdict .. " " .. tostring(result.percent))
local text = ns.Compare:Describe(result)
suite.check("the line says worse", text and text:find("^Worse for Frost"), text)

-- A Fire mage gets little from Frost damage, so the kilt wins there.
ns = LoadAs("MAGE", "fire", { [LEGS] = PANTS })
result = ns.Compare:Judge(KILT)
suite.check("for a Fire mage the kilt is still an upgrade", result.verdict == "upgrade", result.verdict)
suite.check("but by far less than 57%", result.percent < 30, result.percent)

-- Shadow damage for the specs that cast shadow.
for _, case in ipairs({ { "PRIEST", "shadow" }, { "WARLOCK", "affliction" }, { "WARLOCK", "destro" } }) do
    ns = LoadAs(case[1], case[2], { [LEGS] = "item:2" })
    result = ns.Compare:Judge("item:1")
    suite.check(("Shadow damage counts for %s %s"):format(case[1], case[2]),
        result.verdict == "upgrade", result.verdict)
end

-- Every caster spec values the school it casts most.
local W = ns.Weights.SPECS
local wants = {
    { "MAGE", "arcane", "arcaneDamage" }, { "MAGE", "fire", "fireDamage" }, { "MAGE", "frost", "frostDamage" },
    { "PRIEST", "shadow", "shadowDamage" }, { "WARLOCK", "affliction", "shadowDamage" },
    { "WARLOCK", "demo", "shadowDamage" }, { "WARLOCK", "destro", "shadowDamage" },
    { "SHAMAN", "elemental", "natureDamage" }, { "DRUID", "balance", "natureDamage" },
    { "DRUID", "balance", "arcaneDamage" }, { "PALADIN", "ret", "holyDamage" },
}
for _, want in ipairs(wants) do
    local weight = W[want[1]][want[2]].weights[want[3]]
    suite.check(("%s %s weighs %s"):format(want[1], want[2], want[3]), (weight or 0) > 0, weight)
end
-- And never more than spell damage for every school.
for class, specs in pairs(W) do
    for _, key in ipairs(specs.order) do
        local weights = specs[key].weights
        for school in pairs({ arcaneDamage = 1, fireDamage = 1, frostDamage = 1,
            natureDamage = 1, shadowDamage = 1, holyDamage = 1 }) do
            if weights[school] then
                suite.check(("%s %s %s is no more than spell power"):format(class, key, school),
                    weights[school] <= (weights.spellPower or 0) + 1e-9, weights[school])
            end
        end
    end
end

-- Every school is a weight a player can change.
local listed = {}
for _, entry in ipairs(ns.Weights.STAT_ORDER) do listed[entry.key] = true end
for _, school in ipairs({ "arcaneDamage", "fireDamage", "frostDamage", "natureDamage", "shadowDamage", "holyDamage" }) do
    suite.check(school .. " is in the weights window", listed[school])
end

-- A client that does hand school damage over as a stat is read too, and the
-- tooltip line is then not counted a second time.
local stats = ns.Weights:Normalize({ ITEM_MOD_SPELL_DAMAGE_FROST_SHORT = 10, RESISTANCE4_NAME = 10 })
suite.check("a Frost damage stat key is read", stats.frostDamage == 10, stats.frostDamage)
local _, unknown = ns.Weights:Normalize({ RESISTANCE4_NAME = 10 })
suite.check("Frost resistance is not", #unknown == 1)
stats = ns.Weights:AddSchools({ frostDamage = 10 }, { frostDamage = 10, fireDamage = 3 })
suite.check("not counted twice", stats.frostDamage == 10 and stats.fireDamage == 3)

-- Kept per link once the item is loaded; not kept while it is loading.
asked = 0
Items:SchoolDamage("item:99")
Items:SchoolDamage("item:99")
suite.check("a loading item is asked again", asked == 2, asked)
asked = 0
Items:SchoolDamage("item:2")
Items:SchoolDamage("item:2")
suite.check("a loaded item is asked once", asked == 1, asked)

-- No tooltip reader, or one that raises: judged on the stats alone.
_G.C_TooltipInfo = nil
suite.check("no tooltip reader is nil", Items:SchoolDamage("item:5") == nil)
_G.C_TooltipInfo = { GetHyperlink = function() error("secret value") end }
suite.check("a tooltip that raises does not raise here", pcall(Items.SchoolDamage, Items, "item:6"))
_G.C_TooltipInfo = { GetHyperlink = function()
    return { lines = { { leftText = setmetatable({}, { __concat = function() error("secret") end }) }, {} } }
end }
suite.check("a secret line does not raise here", pcall(Items.SchoolDamage, Items, "item:7"))

suite.done()
