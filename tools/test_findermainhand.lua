-- A one-hand weapon is judged against the weaker hand, so a rogue with a
-- good sword in the main hand and an old dagger in the off hand saw a much
-- better sword only on the Off hand list (a player missed Thrash Blade
-- that way, 2026-11-17). It now shows under Main hand too when it beats
-- the main hand weapon, and still counts as one upgrade.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("findermainhand")

local WEAPON, SWORD, DAGGER, MACE = 2, 7, 15, 4
local function Weapon(loc, subclass, dps, more)
    local stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = dps }
    for k, v in pairs(more or {}) do stats[k] = v end
    return { loc = loc, class = WEAPON, subclass = subclass, stats = stats }
end

local ITEMS = {
    ["item:900"] = Weapon("INVTYPE_WEAPON", SWORD, 30.7),               -- worn main hand
    ["item:901"] = Weapon("INVTYPE_WEAPON", DAGGER, 22, { ITEM_MOD_AGILITY_SHORT = 5 }), -- worn off hand
    ["item:2001"] = Weapon("INVTYPE_WEAPON", SWORD, 35.2),              -- beats both hands
    ["item:2002"] = Weapon("INVTYPE_WEAPON", DAGGER, 26),               -- beats only the off hand
    ["item:2003"] = Weapon("INVTYPE_WEAPONMAINHAND", MACE, 32.2),       -- main hand only
    ["item:2004"] = Weapon("INVTYPE_WEAPONOFFHAND", DAGGER, 33),        -- off hand only
}

local ns = env.Load()
_G.UnitClass = function() return "Rogue", "ROGUE", 4 end
_G.UnitFactionGroup = function() return "Horde", "Horde" end
_G.UnitRace = function() return "Orc", "Orc", 2 end
env.InstallItems(ITEMS, { [16] = "item:900", [17] = "item:901" }, {}, 47)
_G.C_QuestLog = { IsQuestFlaggedCompleted = function() return false end }

local S = ns.Sources
ns.Crafts.ITEMS = {}
ns.RollData.ITEMS = {}
S.FOREVER = {}
S.ZONES = { [405] = "Desolace" }
S.NPCS = { [1] = { "Selendra", 405, 26.9, 77.7, "H" } }
S.QUESTS = {}
S.ITEMS = {
    [2001] = { 0, 53, 0, 0, 100, v = { 1, 0 } },
    [2002] = { 40, 50, 0, 0, 100, v = { 1, 0 } },
    [2003] = { 40, 50, 0, 0, 100, v = { 1, 0 } },
    [2004] = { 40, 50, 0, 0, 100, v = { 1, 0 } },
}

local function Offered(found, slot)
    local ids = {}
    for _, pick in ipairs(found.slots[slot] or {}) do ids[#ids + 1] = pick.itemID end
    return table.concat(ids, ",")
end
local function Pick(found, slot, itemID)
    for _, pick in ipairs(found.slots[slot] or {}) do
        if pick.itemID == itemID then return pick end
    end
end

local found = ns.Finder:Scan()
suite.check("it scans", found ~= nil)
suite.check("the better sword shows under Main hand, beside the main hand mace",
    Offered(found, 16):find("2001", 1, true) ~= nil and Offered(found, 16):find("2003", 1, true) ~= nil,
    Offered(found, 16))
suite.check("the better sword still shows under Off hand", Offered(found, 17):find("2001", 1, true) ~= nil,
    Offered(found, 17))
suite.check("a dagger that only beats the off hand stays off the Main hand list",
    Offered(found, 16):find("2002", 1, true) == nil, Offered(found, 16))
suite.check("an off-hand-only dagger never shows under Main hand",
    Offered(found, 16):find("2004", 1, true) == nil, Offered(found, 16))

local main = Pick(found, 16, 2001)
suite.check("the Main hand pick is judged against the main hand weapon",
    main and main.result.slot == 16 and main.result.percent and main.result.percent > 0
    and main.result.percent < 20, main and main.result.percent)
local off = Pick(found, 17, 2001)
suite.check("the Off hand pick keeps its own verdict", off and off.result.slot == 17 and off.gain > main.gain)
suite.check("one sword under both hands counts as one upgrade", found.count == 4, found.count)

-- A second scan reads the kept verdicts and gives the same lists.
ns.Finder:MarkStale()
local again = ns.Finder:Scan()
suite.check("a second scan shows the same Main hand list", Offered(again, 16) == Offered(found, 16),
    Offered(again, 16))

-- With nothing in the off hand a one-hander is judged against the main hand
-- already, and is not listed there twice.
env.InstallItems(ITEMS, { [16] = "item:900" }, {}, 47)
ns.Finder.judgedKey = nil
local alone = ns.Finder:Scan()
local seen = 0
for _, pick in ipairs(alone and alone.slots[16] or {}) do if pick.itemID == 2001 then seen = seen + 1 end end
suite.check("never twice in the same list", seen <= 1, seen)

suite.done()
