-- Weapons a class can train on Forever but not in classic. A player's rogue
-- had One-Handed Axes trained and the tooltip still said "Rogues can't use
-- this" (1.13.5). The class lists follow Forever, and a weapon skill the
-- game says this character knows always counts, whatever the list says.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("forever_weapons")

local ITEMS = {
    -- Grunt Axe of Power: a one-handed axe with attack power.
    ["item:1"] = { loc = "INVTYPE_WEAPON", class = 2, subclass = 0,
        stats = { ITEM_MOD_ATTACK_POWER_SHORT = 6, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 10.7 } },
    -- A two-handed mace, which no rogue can train.
    ["item:2"] = { loc = "INVTYPE_2HWEAPON", class = 2, subclass = 5,
        stats = { ITEM_MOD_STRENGTH_SHORT = 9 } },
}

local function Load(class, spells)
    local ns = env.Load()
    _G.UnitClass = function() return class, class end
    _G.UnitFactionGroup = function() return "Horde" end
    _G.IsPlayerSpell = function(id) return (spells or {})[id] == true end
    env.InstallItems(ITEMS, {}, {}, 16)
    return ns
end

-- A rogue who has trained One-Handed Axes (spell 196).
local ns = Load("ROGUE", { [196] = true, [1180] = true })
local result = ns.Compare:Judge("item:1")
suite.check("a rogue with axes trained can use a one-handed axe", result.verdict ~= "cantuse", result.verdict)
suite.check("and is not told otherwise", (ns.Compare:Describe(result)) ~= "Rogues can't use this",
    (ns.Compare:Describe(result)))
suite.check("a two-handed mace is still not for a rogue",
    ns.Compare:Judge("item:2").verdict == "cantuse")

-- Forever lets every rogue train one-handed axes, so one who has not yet is
-- sent to the weapon master, not told no.
ns = Load("ROGUE", { [1180] = true })
suite.check("Forever rogues can train one-handed axes",
    (ns.Weights:CanUse("ROGUE", 2, 0, "INVTYPE_WEAPON")))
suite.check("an untrained rogue is sent to learn them",
    ns.WeaponSkills:Untrained("item:1") == "One-Handed Axes", ns.WeaponSkills:Untrained("item:1"))

-- A skill the game says is known counts, even when the list says no: the
-- list is a guess, the game is not.
ns = Load("PRIEST", { [196] = true })
suite.check("a known skill beats the class list",
    ns.Compare:Judge("item:1").verdict ~= "cantuse", ns.Compare:Judge("item:1").verdict)
-- And when the game won't say, the list still decides.
ns = Load("PRIEST", nil)
suite.check("with nothing known the list decides",
    ns.Compare:Judge("item:1").verdict == "cantuse", ns.Compare:Judge("item:1").verdict)

suite.done()
