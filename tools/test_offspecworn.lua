-- Each spec judged against its own gear (a Discord report on 2.0.2).
--
-- With the Off Spec's gear on, the Main Spec measured bag pieces against
-- that gear, so the Main Spec's own set in the bags showed nine upgrades.
-- And with the Main Spec's gear on, every piece of the Off Spec's set in
-- the bags showed a blue arrow ("+186%" for Resto shoulders over the
-- Enhancement ones worn). What must hold:
--   1. The Off Spec's set in the bags is no Off Spec upgrade: it is the set.
--      A better piece for it still is, over the set's piece.
--   2. With the Off Spec's gear on, the Main Spec's set in the bags is no
--      upgrade, and gear on offer is measured against the Main Spec's set,
--      not the Off Spec gear worn.
--   3. With the Switch Gear note, a better Main Spec piece that lands in
--      the bags still is an upgrade, over the noted piece.
--   4. With Off Spec on None nothing changes: what is worn is what counts.

local lfs_cwd = os.getenv("PWD") or "."
local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("offspecworn")

local ARMOR, WEAPON = 4, 2
local SHIELD, PLATE = 6, 4
local SWORD1H, SWORD2H = 7, 8

local function Tank(n) return { ITEM_MOD_STAMINA_SHORT = n, ITEM_MOD_STRENGTH_SHORT = math.floor(n / 4) } end
local function Ret(n) return { ITEM_MOD_STRENGTH_SHORT = n } end

local ITEMS = {
    ["item:1"] = { loc = "INVTYPE_2HWEAPON", class = WEAPON, subclass = SWORD2H, stats = Ret(30) },
    ["item:10"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = PLATE, stats = Ret(2) },
    ["item:3"] = { loc = "INVTYPE_WEAPON", class = WEAPON, subclass = SWORD1H, stats = Tank(10) },
    ["item:4"] = { loc = "INVTYPE_SHIELD", class = ARMOR, subclass = SHIELD, stats = Tank(10) },
    ["item:2"] = { loc = "INVTYPE_2HWEAPON", class = WEAPON, subclass = SWORD2H, stats = Ret(60) },
    ["item:11"] = { loc = "INVTYPE_SHIELD", class = ARMOR, subclass = SHIELD, stats = Tank(20) },
}

local ns = env.Load()
_G.UnitClass = function() return "Paladin", "PALADIN", 2 end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitRace = function() return "Human", "Human", 1 end
-- The Main Spec's gear on, the tank set in the bags.
env.InstallItems(ITEMS, { [16] = "item:1", [5] = "item:10" }, { [0] = { [1] = "item:3", [2] = "item:4" } }, 40)

local S = ns.Sources
ns.Crafts.ITEMS = {}
ns.RollData.ITEMS = {}
S.ZONES = { [12] = "Elwynn Forest" }
S.NPCS = { [1] = { "Corina Steele", 12, 41.5, 65.9, "A" } }
S.QUESTS, S.DUNGEONS, S.BOSSES, S.FOREVER = {}, {}, {}, {}
S.ITEMS = {}
for _, id in ipairs({ 1, 2, 3, 4, 11 }) do S.ITEMS[id] = { 30, 30, 0, 0, 100, v = { 1, 0 } } end

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end

local OffSpec, Compare = ns.OffSpec, ns.Compare
ns.charDB.spec = "ret"
ns.charDB.offSpec = "prot"
OffSpec:Forget()

local function Verdict(result) return type(result) == "table" and result.verdict or tostring(result) end
local function Percent(result) return type(result) == "table" and tonumber(result.percent) or nil end

-- 1.
local shield = OffSpec:Judge("item:4", true)
suite.check("the tank shield in the bags is no Off Spec upgrade", Verdict(shield) ~= "upgrade", Verdict(shield))
suite.check("so it gets no blue arrow", OffSpec:OnlyUpgrade("item:4", true) == nil)
local tip = ns.Tooltip.SpecLines("item:4", true, Compare:JudgeCarried("item:4"))
suite.check("and no spec lines on its tooltip", tip == nil)
local better = OffSpec:Judge("item:11")
suite.check("a better shield is still an Off Spec upgrade, over the one carried",
    Verdict(better) == "upgrade" and Percent(better) and Percent(better) > 50 and Percent(better) < 150,
    tostring(Percent(better)))
suite.check("the tank shield is still never sold", ns.BagIcons:Sells(0, 2, "item:4", Compare:JudgeCarried("item:4")) == false)

local Finder = ns.Finder
local _, okKept, kept = Finder:JudgeOnce(Finder:Judged(), 2)
suite.check("the finder's Main Spec verdict on the bigger two-hander, gear on",
    okKept and Verdict(kept) == "upgrade" and Percent(kept) and Percent(kept) > 50 and Percent(kept) < 150,
    Verdict(kept) .. " " .. tostring(Percent(kept)))

-- 2. Put the tank set on by hand (no Switch Gear note): the two-hander
-- goes to the bags.
env.worn = { [16] = "item:3", [17] = "item:4", [5] = "item:10" }
env.bags = { [0] = { [1] = "item:1" } }
OffSpec:Forget()
local twoHand = Compare:JudgeCarried("item:1")
suite.check("with the tank set on, the two-hander in the bags is no Main Spec upgrade",
    Verdict(twoHand) ~= "upgrade", Verdict(twoHand) .. " " .. tostring(Percent(twoHand)))
local inBags = Compare:BestInBags()
suite.check("and the bags count no Main Spec upgrade", next(inBags) == nil)
local offer = Compare:Judge("item:2")
suite.check("a bigger two-hander on offer is measured against the one carried",
    Verdict(offer) == "upgrade" and Percent(offer) and Percent(offer) > 50 and Percent(offer) < 150,
    tostring(Percent(offer)))
_, okKept, kept = Finder:JudgeOnce(Finder:Judged(), 2)
suite.check("the finder's kept verdict still measures it against the two-hander",
    okKept and Verdict(kept) == "upgrade" and Percent(kept) and Percent(kept) > 50 and Percent(kept) < 150,
    Verdict(kept) .. " " .. tostring(Percent(kept)))
suite.check("the tank set worn is no Off Spec upgrade either", Verdict(OffSpec:Judge("item:4")) ~= "upgrade")
suite.check("what is really worn is still read as worn", ns.Items:WornNow(16) == "item:3")

-- 3. Switch Gear noted the two-hander on the way to the tank set, and a
-- bigger one has dropped.
ns.charDB.swapBack = { [16] = "item:1", [17] = false }
env.bags = { [0] = { [1] = "item:1", [2] = "item:2" } }
OffSpec:Forget()
local dropped = Compare:JudgeCarried("item:2")
suite.check("a bigger two-hander in the bags is a Main Spec upgrade over the noted one",
    Verdict(dropped) == "upgrade" and Percent(dropped) and Percent(dropped) > 50 and Percent(dropped) < 150,
    Verdict(dropped) .. " " .. tostring(Percent(dropped)))
suite.check("the noted two-hander itself is not", Verdict(Compare:JudgeCarried("item:1")) ~= "upgrade")
ns.charDB.swapBack = nil

-- 4.
env.bags = { [0] = { [1] = "item:1" } }
ns.charDB.offSpec = nil
OffSpec:Forget()
local plain = Compare:JudgeCarried("item:1")
suite.check("with Off Spec on None the two-hander beats the gear worn, as before",
    Verdict(plain) == "upgrade", Verdict(plain))

suite.done()
