-- Worn gear whose stats the client hasn't handed back yet (it can let a
-- worn item go for a while) must not count as nothing: a demonology
-- warlock was told a weaker piece was an upgrade over one they wore.
-- With the worn item unread there is no verdict, and once it reads, the
-- better piece wins.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("wornunread")

local CLOTH = 1
local ITEMS = {
    -- What the warlock wears: spell power and intellect.
    ["item:1"] = { loc = "INVTYPE_CHEST", class = 4, subclass = CLOTH,
        stats = { ITEM_MOD_SPELL_POWER_SHORT = 12, ITEM_MOD_INTELLECT_SHORT = 8 } },
    -- A weaker robe in the bags.
    ["item:2"] = { loc = "INVTYPE_CHEST", class = 4, subclass = CLOTH,
        stats = { ITEM_MOD_STAMINA_SHORT = 5, ITEM_MOD_INTELLECT_SHORT = 3 } },
    -- The worn robe while the client can't read it.
    ["item:3"] = { loc = "INVTYPE_CHEST", class = 4, subclass = CLOTH, stats = nil },
    ["item:4"] = { loc = "INVTYPE_FINGER", class = 4, subclass = 0,
        stats = { ITEM_MOD_STAMINA_SHORT = 4 } },
    ["item:5"] = { loc = "INVTYPE_FINGER", class = 4, subclass = 0, stats = nil },
}

local function Warlock(worn)
    local ns = env.Load()
    _G.UnitClass = function() return "Warlock", "WARLOCK" end
    env.InstallItems(ITEMS, worn, nil, 30)
    ns.charDB = ns.charDB or {}; ns.charDB.spec = "demo"
    return ns
end

local ns = Warlock({ [5] = "item:3" })
local result = ns.Compare:Judge("item:2")
suite.check("unread worn chest: the bag robe is not called an upgrade",
    not (result and result.verdict == "upgrade"), result and result.verdict)

ns = Warlock({ [5] = "item:1" })
result = ns.Compare:Judge("item:2")
suite.check("read worn chest: the weaker robe is a downgrade",
    result and result.verdict == "downgrade", result and result.verdict)

-- Rings: the second ring is judged against the other worn ring.
ns = Warlock({ [11] = "item:4", [12] = "item:5" })
result = ns.Compare:JudgeCarried("item:4")
suite.check("unread other ring: no upgrade for the twin slot",
    not (result and result.verdict == "upgrade" and result.slot == 12), result and result.verdict)

suite.done()
