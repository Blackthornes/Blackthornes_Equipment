-- Set bonuses when judging gear: a bonus a swap would break counts against
-- the new item, one it would finish counts for it, and a set the character
-- can't use (a profession short) counts for nothing.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("itemsets")

local ARMOR, WEAPON, LEATHER, STAFF, DAGGER = 4, 2, 2, 10, 15
local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end

local ITEMS = {
    ["item:1"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = LEATHER, stats = Agi(10) },  -- set
    ["item:2"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = LEATHER, stats = Agi(15) },
    ["item:3"] = { loc = "INVTYPE_FEET", class = ARMOR, subclass = LEATHER, stats = Agi(2) },    -- set
    ["item:4"] = { loc = "INVTYPE_FEET", class = ARMOR, subclass = LEATHER, stats = Agi(3) },
    ["item:7"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = LEATHER, stats = Agi(9) },   -- set
    ["item:8"] = { loc = "INVTYPE_HAND", class = ARMOR, subclass = LEATHER, stats = Agi(5) },
    ["item:20"] = { loc = "INVTYPE_2HWEAPON", class = WEAPON, subclass = STAFF, stats = Agi(8) },
    ["item:21"] = { loc = "INVTYPE_WEAPON", class = WEAPON, subclass = DAGGER, stats = Agi(5) },
    ["item:22"] = { loc = "INVTYPE_WEAPON", class = WEAPON, subclass = DAGGER, stats = Agi(5) }, -- set
}

local SETS = {
    [1] = { items = { 1, 3, 7 }, b = { [2] = { agility = 20 } }, name = "Wolf" },
    [2] = { items = { 21, 22 }, b = { [2] = { agility = 30 } }, name = "Twin Fangs" },
}

local function LoadWith(worn, sets)
    local ns = env.Load()
    _G.UnitClass = function() return "HUNTER", "HUNTER" end
    ns.ItemSetData = { SETS = sets or SETS }
    env.InstallItems(ITEMS, worn)
    return ns
end

-- Worn: chest and boots of the set, so its bonus is on.
local ns = LoadWith({ [5] = "item:1", [8] = "item:3" })
local result = ns.Compare:Judge("item:2")
suite.check("a chest that breaks the bonus is no upgrade", result.verdict == "downgrade", result.verdict)
suite.check("the lost bonus is in the score to beat", (result.setChange or 0) < 0, result.setChange)

result = ns.Compare:Judge("item:7")
suite.check("swapping one set piece for another keeps the bonus", result.setChange == 0, result.setChange)
suite.check("so it's judged on its own stats", result.verdict == "downgrade", result.verdict)

result = ns.Compare:Judge("item:8")
suite.check("gloves touch no set", result.setChange == nil, result.setChange)

-- Worn: the set's chest and plain boots. The set's boots finish the bonus.
ns = LoadWith({ [5] = "item:1", [8] = "item:4" })
result = ns.Compare:Judge("item:3")
suite.check("boots that finish the bonus are an upgrade", result.verdict == "upgrade", result.verdict)
suite.check("the bonus counts for them", (result.setChange or 0) > 0, result.setChange)
suite.check("and it shows in the score", result.score > result.against)

-- The same, but the set wants Blacksmithing at 300 and the character has none.
ns = LoadWith({ [5] = "item:1", [8] = "item:4" },
    { [1] = { items = { 1, 3, 7 }, b = { [2] = { agility = 20 } }, skill = 164, rank = 300 } })
result = ns.Compare:Judge("item:3")
suite.check("a set the character can't use gives nothing", result.verdict == "downgrade", result.verdict)

-- Weapons: a two-hander takes both hands, breaking a set held in them.
ns = LoadWith({ [16] = "item:21", [17] = "item:22" })
local slots = ns.Compare.ReplacedSlots("INVTYPE_2HWEAPON", 16)
suite.check("a two-hander empties the off hand too", slots[1] == 16 and slots[2] == 17)
result = ns.Compare:Judge("item:20")
suite.check("a two-hander that breaks the pair counts the loss", (result.setChange or 0) < 0, result.setChange)

-- A bad data file costs the set, not the verdict.
ns = LoadWith({ [5] = "item:1", [8] = "item:3" }, { [1] = { items = "oops" } })
local ok, judged = pcall(ns.Compare.Judge, ns.Compare, "item:2")
suite.check("broken set data does not raise", ok and judged and judged.verdict == "upgrade",
    judged and judged.verdict)

-- Nothing is read again until the gear changes.
ns = LoadWith({ [5] = "item:1", [8] = "item:3" })
local reads = 0
local Equipped = ns.Items.Equipped
ns.Compare:Judge("item:2")
ns.Items.Equipped = function(self, slot) reads = reads + 1; return Equipped(self, slot) end
ns.ItemSets:Worn()
suite.check("the worn sets are kept between asks", reads == 0, reads)
ns.ItemSets:GearChanged()
ns.ItemSets:Worn()
suite.check("and read again after a gear change", reads > 0, reads)

suite.done()
