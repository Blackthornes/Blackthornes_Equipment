-- White weapons for casters: a staff or dagger with no stats still has
-- weapon damage, so between two plain ones the harder hitter is the upgrade,
-- while real caster stats always come first.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("casterweapons")

local WEAPON, STAFF, DAGGER = 2, 10, 15
local function Dps(n, more)
    local stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = n }
    for k, v in pairs(more or {}) do stats[k] = v end
    return stats
end

local ITEMS = {
    ["item:1"] = { loc = "INVTYPE_2HWEAPON", class = WEAPON, subclass = STAFF, stats = Dps(6) },
    ["item:2"] = { loc = "INVTYPE_2HWEAPON", class = WEAPON, subclass = STAFF, stats = Dps(12) },
    ["item:3"] = { loc = "INVTYPE_WEAPON", class = WEAPON, subclass = DAGGER, stats = Dps(4) },
    ["item:4"] = { loc = "INVTYPE_2HWEAPON", class = WEAPON, subclass = STAFF,
        stats = Dps(8, { ITEM_MOD_INTELLECT_SHORT = 2 }) },
    ["item:5"] = { loc = "INVTYPE_2HWEAPON", class = WEAPON, subclass = STAFF, stats = Dps(30) },
    -- Plain cloth boots: armor only (a quest's Soft Wool Boots over starter shoes).
    ["item:6"] = { loc = "INVTYPE_FEET", class = 4, subclass = 1, stats = { RESISTANCE0_NAME = 2 } },
    ["item:7"] = { loc = "INVTYPE_FEET", class = 4, subclass = 1, stats = { RESISTANCE0_NAME = 7 } },
    ["item:8"] = { loc = "INVTYPE_FEET", class = 4, subclass = 1,
        stats = { RESISTANCE0_NAME = 2, ITEM_MOD_INTELLECT_SHORT = 1 } },
    ["item:9"] = { loc = "INVTYPE_FEET", class = 4, subclass = 1, stats = { RESISTANCE0_NAME = 40 } },
}

local CASTERS = { "WARLOCK", "MAGE", "PRIEST" }

for _, class in ipairs(CASTERS) do
    local ns = env.Load()
    _G.UnitClass = function() return class, class end
    env.InstallItems(ITEMS, { [16] = "item:1" }, nil, 20)
    local Compare = ns.Compare

    local result = Compare:Judge("item:2")
    suite.check(class .. ": a harder hitting white staff is an upgrade",
        result and result.verdict == "upgrade", result and result.verdict)
    result = Compare:Judge("item:3")
    suite.check(class .. ": a weaker white dagger is not",
        result and result.verdict ~= "upgrade", result and result.verdict)

    ns = env.Load()
    _G.UnitClass = function() return class, class end
    env.InstallItems(ITEMS, { [16] = "item:4" }, nil, 20)
    result = ns.Compare:Judge("item:5")
    suite.check(class .. ": stats still beat raw weapon damage",
        result and result.verdict ~= "upgrade", result and result.verdict)

    ns = env.Load()
    _G.UnitClass = function() return class, class end
    env.InstallItems(ITEMS, { [8] = "item:6" }, nil, 3)
    result = ns.Compare:Judge("item:7")
    suite.check(class .. ": white boots with more armor are an upgrade",
        result and result.verdict == "upgrade", result and result.verdict)

    ns = env.Load()
    _G.UnitClass = function() return class, class end
    env.InstallItems(ITEMS, { [8] = "item:8" }, nil, 20)
    result = ns.Compare:Judge("item:9")
    suite.check(class .. ": a point of intellect beats a pile of armor",
        result and result.verdict ~= "upgrade", result and result.verdict)
end

-- Every caster spec weighs melee weapon damage a little, never as much as a
-- point of intellect.
for _, class in ipairs({ "WARLOCK", "MAGE", "PRIEST", "DRUID", "SHAMAN", "PALADIN" }) do
    local specs = env.Load().Weights.SPECS[class]
    for _, key in ipairs(specs.order) do
        local w = specs[key].weights
        suite.check(class .. " " .. key .. " weighs melee weapon damage", (w.meleeDps or 0) > 0)
        suite.check(class .. " " .. key .. " weighs armor", (w.armor or 0) > 0)
        if w.intellect and (w.meleeDps or 0) < 1 then
            suite.check(class .. " " .. key .. " puts intellect above it", w.intellect > w.meleeDps)
        end
    end
end

suite.done()
