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

-- The ranged slot follows the class list only. A player's hunter was told a
-- thrown weapon would replace a bow (1.19.0): Forever's client says a hunter
-- knows the Thrown skill (spell 2567), and a known skill beat the list.
-- Hunters never use thrown weapons, so a known skill must not open one.
ITEMS["item:3"] = { loc = "INVTYPE_THROWN", class = 2, subclass = 16,
    stats = { ITEM_MOD_AGILITY_SHORT = 8, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 14 } }
ITEMS["item:4"] = { loc = "INVTYPE_RANGED", class = 2, subclass = 2,
    stats = { ITEM_MOD_AGILITY_SHORT = 2, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 6 } }
ITEMS["item:5"] = { loc = "INVTYPE_RANGEDRIGHT", class = 2, subclass = 19,
    stats = { ITEM_MOD_INTELLECT_SHORT = 4, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 12 } }

-- Every skill a hunter could be said to know: bows, guns, crossbows, thrown, wands.
local ALL_RANGED = { [264] = true, [266] = true, [5011] = true, [2567] = true, [5009] = true }
ns = Load("HUNTER", ALL_RANGED)
suite.check("a hunter the game says knows Thrown still can't use a thrown weapon",
    ns.Compare:Judge("item:3").verdict == "cantuse", ns.Compare:Judge("item:3").verdict)
suite.check("nor a wand", ns.Compare:Judge("item:5").verdict == "cantuse", ns.Compare:Judge("item:5").verdict)
suite.check("but a bow is still for a hunter", ns.Compare:Judge("item:4").verdict ~= "cantuse",
    ns.Compare:Judge("item:4").verdict)

-- Who uses what in the ranged slot, by class, with every ranged skill
-- "known": classic's rules, which Forever keeps.
local RANGED = {
    -- class:     bow    gun    thrown crossbow wand
    HUNTER  = { true,  true,  false, true,  false },
    WARRIOR = { true,  true,  true,  true,  false },
    ROGUE   = { true,  true,  true,  true,  false },
    MAGE    = { false, false, false, false, true  },
    PRIEST  = { false, false, false, false, true  },
    WARLOCK = { false, false, false, false, true  },
    DRUID   = { false, false, false, false, false },
    PALADIN = { false, false, false, false, false },
    SHAMAN  = { false, false, false, false, false },
}
local KINDS = {
    { 2, "INVTYPE_RANGED", "bow" }, { 3, "INVTYPE_RANGED", "gun" },
    { 16, "INVTYPE_THROWN", "thrown" }, { 18, "INVTYPE_RANGED", "crossbow" },
    { 19, "INVTYPE_RANGEDRIGHT", "wand" },
}
for class, row in pairs(RANGED) do
    ns = Load(class, ALL_RANGED)
    for index, kind in ipairs(KINDS) do
        local can = ns.Weights:CanUse(class, 2, kind[1], kind[2]) and true or false
        suite.check(("%s %s a %s"):format(class, row[index] and "can use" or "can't use", kind[3]),
            can == row[index], tostring(can))
    end
end

suite.done()
