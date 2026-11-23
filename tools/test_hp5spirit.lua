-- Health every 5 sec as a weight, and Spirit listed for warriors (a player
-- asked, the owner said add both for every class at 0, 2026-11-19).

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("hp5spirit")

local ns = env.Load()
local Weights, Items = ns.Weights, ns.Items

-- The stat keys the client may hand back.
local stats = Weights:Normalize({ ITEM_MOD_HEALTH_REGEN_SHORT = 3 })
suite.check("health regen from the stats is hp5", stats.hp5 == 3, stats.hp5)
stats = Weights:Normalize({ ITEM_MOD_HEALTH_REGENERATION_SHORT = 4 })
suite.check("the longer key is hp5 too", stats.hp5 == 4, stats.hp5)

-- The tooltip line.
local stat, amount = Items.HealthLine("Equip: Restores 3 health per 5 sec.")
suite.check("the Equip line is read", stat == "hp5" and amount == 3, tostring(stat) .. " " .. tostring(amount))
stat = Items.HealthLine("Equip: Restores 4 mana per 5 sec.")
suite.check("a mana line is not health", stat == nil, stat)
_G.ITEM_MOD_HEALTH_REGEN = "Stellt alle 5 Sek. %s Gesundheit wieder her."
stat, amount = Items.HealthLine("Anlegen: Stellt alle 5 Sek. 6 Gesundheit wieder her.")
suite.check("the client's own words are read", stat == "hp5" and amount == 6, tostring(amount))
_G.ITEM_MOD_HEALTH_REGEN = nil

_G.C_TooltipInfo = { GetHyperlink = function()
    return { lines = { { leftText = "Troll's Ring" }, { leftText = "Equip: Restores 5 health per 5 sec." } } }
end }
local found = Items:SchoolDamage("item:9001")
suite.check("the tooltip reader keeps hp5", found and found.hp5 == 5)
stats = Weights:AddSchools(Weights:Normalize({ ITEM_MOD_HEALTH_REGEN_SHORT = 5 }), found)
suite.check("never counted twice", stats.hp5 == 5, stats.hp5)

-- Listed, changeable, and worth nothing until a player sets it.
local listed = {}
for _, entry in ipairs(Weights.STAT_ORDER) do listed[entry.key] = true end
suite.check("health every 5 sec is a row", listed.hp5)
for class, specs in pairs(Weights.SPECS) do
    for _, key in ipairs(specs.order) do
        local rows = {}
        for _, entry in ipairs(ns.WeightsPage:StatsFor(class, key, false)) do rows[entry.key] = true end
        suite.check(class .. " " .. key .. " lists Spirit and hp5", rows.spirit and rows.hp5)
        suite.check(class .. " " .. key .. " weighs hp5 at 0", (Weights:Value(class, key, "hp5") or 0) == 0)
    end
end
suite.check("warriors weigh Spirit at 0", (Weights:Value("WARRIOR", "arms", "spirit") or 0) == 0)
local kept = Weights:SetWeight("WARRIOR", "prot", "hp5", 0.5)
suite.check("a player can weigh hp5", kept == 0.5 and Weights:Value("WARRIOR", "prot", "hp5") == 0.5)
kept = Weights:SetWeight("WARRIOR", "fury", "spirit", 0.2)
suite.check("a warrior can weigh Spirit", kept == 0.2)

suite.done()
