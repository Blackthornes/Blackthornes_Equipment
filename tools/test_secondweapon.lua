-- A second copy of the one-hander you hold, carried in the bags, can go in
-- your other hand. It was judged "equipped" (the link is the same as the
-- worn one), so it got no arrow and white copies got the sell coin.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("secondweapon")

local ITEMS = {
    -- The good dagger, a weak one, a book for the off hand and a two-hander.
    ["item:1"] = { loc = "INVTYPE_WEAPON", class = 2, subclass = 15, stats = { ITEM_MOD_AGILITY_SHORT = 10 } },
    ["item:2"] = { loc = "INVTYPE_WEAPON", class = 2, subclass = 15, stats = { ITEM_MOD_AGILITY_SHORT = 2 } },
    ["item:3"] = { loc = "INVTYPE_HOLDABLE", class = 4, subclass = 0, stats = { ITEM_MOD_AGILITY_SHORT = 1 } },
}

local ns = env.Load()
_G.UnitClass = function() return "ROGUE", "ROGUE" end
_G.CanDualWield = function() return true end
env.InstallItems(ITEMS, { [16] = "item:1", [17] = "item:2" }, { [0] = { [1] = "item:1" } })
env.InstallHooks()

local Compare = ns.Compare

local result = Compare:JudgeCarried("item:1")
suite.check("a copy of the main hand dagger is judged for the off hand",
    result and result.verdict == "upgrade" and result.slot == 17)
suite.check("against the weaker dagger held there", result and result.against and result.against > 0)
suite.check("worn, the same link is still equipped", Compare:Judge("item:1").verdict == "equipped")

suite.check("the bag arrow counts it as an upgrade", Compare.WearableUpgrade(result) == true)

-- A white copy got the gold sell coin, as "equipped" is no upgrade.
_G.C_Container.GetContainerItemInfo = function()
    return { quality = 1, isBound = false, stackCount = 1 }
end
_G.C_TooltipInfo = { GetHyperlink = function() return { lines = { { type = 11, price = 50 } } } end }
suite.check("a white copy that fits the other hand gets no sell coin",
    ns.BagIcons:Sells(0, 1, "item:1", result) == false)
suite.check("worn in both hands, a third white copy still sells",
    ns.BagIcons:Sells(0, 1, "item:1", { verdict = "equipped", slot = 16 }) == true)

env.worn = { [16] = "item:2", [17] = "item:1" }
result = Compare:JudgeCarried("item:1")
suite.check("a copy of the off hand dagger is judged for the main hand",
    result and result.verdict == "upgrade" and result.slot == 16)

env.worn = { [16] = "item:1" }
result = Compare:JudgeCarried("item:1")
suite.check("an empty off hand takes the copy",
    result and result.verdict == "upgrade" and result.slot == 17 and result.empty == true)

env.worn = { [16] = "item:1", [17] = "item:1" }
suite.check("one in each hand already: equipped", Compare:JudgeCarried("item:1").verdict == "equipped")

env.worn = { [16] = "item:1", [17] = "item:3" }
suite.check("a book in the off hand: the copy has nowhere to go",
    Compare:JudgeCarried("item:1").verdict == "equipped")

-- Only one may be worn: the copy stays "equipped".
env.worn = { [16] = "item:1", [17] = "item:2" }
local isUnique = Compare.IsUnique
Compare.IsUnique = function() return true end
suite.check("a unique dagger's copy stays equipped", Compare:JudgeCarried("item:1").verdict == "equipped")
Compare.IsUnique = isUnique

-- A class that can't dual wield has one hand for it.
_G.CanDualWield = function() return false end
env.worn = { [16] = "item:1" }
suite.check("no dual wield: the copy stays equipped", Compare:JudgeCarried("item:1").verdict == "equipped")

suite.done()
