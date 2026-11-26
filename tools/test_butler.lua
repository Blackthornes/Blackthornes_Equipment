-- What Equipment tells Blackthornes Butler about one carried item
-- (Butler:Advise): an upgrade now or later and by how much, the sell coin,
-- a tool kept to use, nothing for what is not gear, and never an error.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("butler")

local ARMOR, WEAPON = 4, 2
local LEATHER, MAIL = 2, 3
local AXE, DAGGER, FISHING_POLE = 0, 15, 20

local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end

local ITEMS = {
    -- Worn.
    ["item:1"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = LEATHER, stats = Agi(10) },
    -- Half as good again: an upgrade to wear now.
    ["item:2"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = LEATHER, stats = Agi(15) },
    -- Mail, which a hunter of 20 waits until 40 to wear.
    ["item:3"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = MAIL, stats = Agi(30) },
    -- Worse than the worn chest: white, and soulbound green.
    ["item:4"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = LEATHER, stats = Agi(4) },
    ["item:5"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = LEATHER, stats = Agi(5) },
    -- Boots for an empty slot: an upgrade with no percent to give.
    ["item:6"] = { loc = "INVTYPE_FEET", class = ARMOR, subclass = LEATHER, stats = Agi(2) },
    -- Not gear: a reagent.
    ["item:7"] = { loc = "", class = 7, subclass = 0, stats = {} },
    -- The mining pick, a fishing pole, a dagger that adds to Skinning, and
    -- a known tool that is never worn.
    ["item:2901"] = { loc = "INVTYPE_WEAPON", class = WEAPON, subclass = AXE, stats = {} },
    ["item:8"] = { loc = "INVTYPE_2HWEAPON", class = WEAPON, subclass = FISHING_POLE, stats = {} },
    ["item:9"] = { loc = "INVTYPE_WEAPON", class = WEAPON, subclass = DAGGER, stats = {} },
    ["item:6219"] = { loc = "", class = 7, subclass = 0, stats = {} },
    -- A helm that adds to Mining: a tool only to a class that can wear it.
    ["item:10"] = { loc = "INVTYPE_HEAD", class = ARMOR, subclass = 4, stats = {} },
}

-- Quality and soulbound for each bag slot.
local SLOTS = {
    [4] = { quality = 1 },                  -- white
    [5] = { quality = 2, bound = true },    -- soulbound green
}

local ns = env.Load()
_G.UnitClass = function() return "HUNTER", "HUNTER" end
env.InstallItems(ITEMS, { [5] = "item:1" }, { [0] = {
    [2] = "item:2", [3] = "item:3", [4] = "item:4", [5] = "item:5", [6] = "item:6",
} })
_G.C_Container.GetContainerItemInfo = function(bag, slot)
    local s = SLOTS[slot]
    if bag ~= 0 or not s then return nil end
    return { quality = s.quality, isBound = s.bound == true, stackCount = 1 }
end
_G.C_TooltipInfo = { GetHyperlink = function(link)
    local lines = { { type = 11, price = 50 } }
    if link == "item:9" then lines[2] = { type = 0, leftText = "Equip: Skinning +10." } end
    if link == "item:10" then lines[2] = { type = 0, leftText = "Equip: Mining +5." } end
    return { lines = lines }
end }

local Butler = _G.BlackthornesEquipment.Butler
suite.check("Butler answers on the global", type(Butler) == "table" and type(Butler.Advise) == "function")

-- Upgrades.
local advice = Butler:Advise("item:2", 0, 2)
suite.check("an upgrade to wear now", advice and advice.upgrade == "now", advice and advice.upgrade)
suite.check("worth 50 percent", advice.gain == 50, advice.gain)
suite.check("is never sold", advice.sell == false and advice.tool == false)
suite.check("the same as the bag arrow", ns.Compare:IsUpgradeNow("item:2", true))

advice = Butler:Advise("item:3", 0, 3)
suite.check("mail far from 40 is not kept", advice and advice.upgrade == nil, advice and advice.upgrade)
local atTwenty = _G.UnitLevel
_G.UnitLevel = function() return 38 end
advice = Butler:Advise("item:3", 0, 3)
suite.check("mail waits for level 40", advice and advice.upgrade == "later", advice and advice.upgrade)
suite.check("with its size", advice.gain == 200, advice.gain)
suite.check("and is not sold", advice.sell == false)
_G.UnitLevel = atTwenty

advice = Butler:Advise("item:6", 0, 6)
suite.check("an empty slot is an upgrade now", advice and advice.upgrade == "now")
suite.check("with no percent to give", advice.gain == nil, advice.gain)

-- The sell coin.
advice = Butler:Advise("item:4", 0, 4)
suite.check("white gear that is no upgrade sells", advice and advice.sell == true)
suite.check("and is no upgrade", advice.upgrade == nil and advice.gain == nil)
advice = Butler:Advise("item:5", 0, 5)
suite.check("a soulbound green sells without Enchanting", advice and advice.sell == true)
advice = Butler:Advise("item:5")
suite.check("without its slot, a green is not called sold", advice and advice.sell == false)
ns.db.bagSellCoins = false
advice = Butler:Advise("item:4", 0, 4)
suite.check("no coin when the coins are unticked", advice and advice.sell == false)
ns.db.bagSellCoins = nil

-- Tools.
advice = Butler:Advise("item:2901")
suite.check("the mining pick is a tool", advice and advice.tool == true and advice.sell == false)
advice = Butler:Advise("item:8")
suite.check("a fishing pole is a tool", advice and advice.tool == true)
advice = Butler:Advise("item:9")
suite.check("a dagger that adds to Skinning is a tool", advice and advice.tool == true)
advice = Butler:Advise(6219)
suite.check("a tool never worn is one too, by item ID", advice and advice.tool == true)

-- What is not gear, after the cheap check alone.
local judged = 0
local judge = ns.Compare.JudgeCarried
ns.Compare.JudgeCarried = function(...)
    judged = judged + 1
    return judge(...)
end
suite.check("a reagent says nothing", Butler:Advise("item:7") == nil)
suite.check("an item not loaded yet says nothing", Butler:Advise("item:999") == nil)
suite.check("nor anything that is not a link", Butler:Advise({}) == nil and Butler:Advise(nil) == nil)
suite.check("without judging the gear", judged == 0, judged)
ns.Compare.JudgeCarried = judge

-- Never: only gear this class can never wear.
local function AdviseAs(result)
    ns.Compare.JudgeCarried = function() return result end
    local a = Butler:Advise("item:2", 0, 2)
    ns.Compare.JudgeCarried = judge
    return a
end
advice = AdviseAs({ verdict = "cantuse" })
suite.check("gear the class can never wear says never", advice and advice.never == true)
suite.check("mail learned later is not never", AdviseAs({ verdict = "cantuse", laterArmor = 40 }).never == nil)
suite.check("Best Armor Only is not never", AdviseAs({ verdict = "cantuse", lighterArmor = true }).never == nil)
suite.check("a hidden untrained weapon is not never",
    AdviseAs({ verdict = "cantuse", ignoredSkill = "Staves" }).never == nil)
suite.check("a downgrade is not never", AdviseAs({ verdict = "downgrade", percent = -5 }).never == nil)

-- A helm with Mining on it is gear, not a tool, to a class that can never
-- wear it; worn later (mail or plate at 40) it stays a tool.
local function HelmAs(result)
    ns.Compare.JudgeCarried = function() return result end
    local a = Butler:Advise("item:10")
    ns.Compare.JudgeCarried = judge
    return a
end
advice = HelmAs({ verdict = "cantuse" })
suite.check("an unwearable helm with Mining is no tool", advice and advice.tool == false, advice and advice.tool)
suite.check("and says never", advice and advice.never == true)
suite.check("and is judged for the sell coin", advice and advice.sell ~= nil)
suite.check("a Mining helm for later stays a tool",
    HelmAs({ verdict = "cantuse", laterArmor = 40 }).tool == true)
suite.check("a wearable Mining helm stays a tool", HelmAs({ verdict = "downgrade", percent = -5 }).tool == true)
suite.check("BagIcons gives the unwearable helm no tool pass",
    ns.BagIcons.KeptTool("item:10", { verdict = "cantuse" }) == false)

-- Never raises.
ns.Compare.JudgeCarried = function() error("boom") end
local ok, answer = pcall(Butler.Advise, Butler, "item:2", 0, 2)
suite.check("an error inside says nothing, and does not raise", ok and answer == nil)
ns.Compare.JudgeCarried = judge

-- What each character wears, for Butler's search.
local savedNotes = ns.db.characterGear
ns.db.characterGear = {
    ["Player-1-A"] = { worn = { [1] = "item:5::::", [11] = "item:7", [12] = "item:7" }, at = 100 },
    ["Player-1-B"] = { worn = {} },
    ["Player-1-C"] = "not a note",
}
local worn = Butler:Worn()
local byKey = {}
for _, entry in ipairs(worn or {}) do byKey[entry.key] = entry end
suite.check("one entry per note", worn and #worn == 2, worn and #worn)
suite.check("a worn piece counts", byKey["Player-1-A"] and byKey["Player-1-A"].worn[5] == 1)
suite.check("two rings of one kind count two", byKey["Player-1-A"] and byKey["Player-1-A"].worn[7] == 2)
suite.check("when it was read", byKey["Player-1-A"] and byKey["Player-1-A"].at == 100)
suite.check("nothing worn is empty", byKey["Player-1-B"] and next(byKey["Player-1-B"].worn) == nil)
local savedAlts = ns.Alts
ns.Alts = { Notes = function() error("boom") end }
suite.check("an error says nil, and does not raise", Butler:Worn() == nil)
ns.Alts = savedAlts
ns.db.characterGear = savedNotes

suite.done()
