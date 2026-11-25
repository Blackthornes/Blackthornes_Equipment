-- Main Spec and Off Spec (Logic/OffSpec.lua, the owner said build it from
-- the mockup, 2026-11-25).
--
-- What must hold:
--   1. Off Spec starts on None, and None does no work at all.
--   2. The pick is saved per character as `offSpec`; Main keeps `spec`.
--      The same spec as Main counts as None.
--   3. Off Spec gains are measured against the best piece owned for it,
--      worn or in the bags, and a piece carried is never offered again.
--   4. The Protection no-two-hander rule follows the Off Spec only.
--   5. Nothing leaks: once judging for the Off Spec ends, every answer is
--      the Main Spec's again, even after an error mid-scan.
--   6. The Off Spec's scan is kept apart: the shared scan the upgrade quest
--      and the small panel read stays the Main Spec's, and so do its kept
--      verdicts.
--   7. The blue arrow: only an upgrade for the Off Spec and not the Main.
--   8. /beq spec off <name> and /beq spec off none.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("offspec")

local ARMOR, WEAPON = 4, 2
local SHIELD, PLATE = 6, 4
local SWORD1H, SWORD2H = 7, 8

local function Tank(n) return { ITEM_MOD_STAMINA_SHORT = n, ITEM_MOD_STRENGTH_SHORT = math.floor(n / 4) } end
local function Ret(n) return { ITEM_MOD_STRENGTH_SHORT = n } end

local ITEMS = {
    -- Worn: a strong Retribution two-hander and a weak chest.
    ["item:1"] = { loc = "INVTYPE_2HWEAPON", class = WEAPON, subclass = SWORD2H, stats = Ret(30) },
    ["item:10"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = PLATE, stats = Ret(2) },
    -- In the bags: a tank one-hander and shield.
    ["item:3"] = { loc = "INVTYPE_WEAPON", class = WEAPON, subclass = SWORD1H, stats = Tank(10) },
    ["item:4"] = { loc = "INVTYPE_SHIELD", class = ARMOR, subclass = SHIELD, stats = Tank(10) },
    -- On offer: a bigger two-hander, a better shield, a better chest.
    ["item:2"] = { loc = "INVTYPE_2HWEAPON", class = WEAPON, subclass = SWORD2H, stats = Ret(60) },
    ["item:11"] = { loc = "INVTYPE_SHIELD", class = ARMOR, subclass = SHIELD, stats = Tank(20) },
    ["item:12"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = PLATE, stats = Tank(20) },
}

local ns = env.Load()
_G.UnitClass = function() return "Paladin", "PALADIN", 2 end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitRace = function() return "Human", "Human", 1 end
env.InstallItems(ITEMS, { [16] = "item:1", [5] = "item:10" }, { [0] = { [1] = "item:3", [2] = "item:4" } }, 40)

local S = ns.Sources
ns.Crafts.ITEMS = {}
ns.RollData.ITEMS = {}
S.ZONES = { [12] = "Elwynn Forest" }
S.NPCS = { [1] = { "Corina Steele", 12, 41.5, 65.9, "A" } }
S.QUESTS, S.DUNGEONS, S.BOSSES, S.FOREVER = {}, {}, {}, {}
S.ITEMS = {}
for _, id in ipairs({ 2, 3, 4, 11, 12 }) do S.ITEMS[id] = { 30, 30, 0, 0, 100, v = { 1, 0 } } end

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end

local OffSpec, Compare, Weights, Finder, Items = ns.OffSpec, ns.Compare, ns.Weights, ns.Finder, ns.Items
ns.charDB.spec = "ret"

local function Verdict(result) return type(result) == "table" and result.verdict or tostring(result) end
local function Listed(found, slot)
    local ids = {}
    for _, pick in ipairs(found and found.all and found.all[slot] or {}) do ids[#ids + 1] = pick.itemID end
    table.sort(ids)
    return table.concat(ids, ",")
end

-- 1.
local outfits = 0
local realScore = Compare.ScoreOf
local judgedAs = {}
Compare.ScoreOf = function(self, link, weights)
    judgedAs[#judgedAs + 1] = Weights:CurrentSpec()
    return realScore(self, link, weights)
end
suite.check("Off Spec starts on None", OffSpec:Key() == nil and ns.charDB.offSpec == nil)
judgedAs = {}
suite.check("None judges nothing for an Off Spec", OffSpec:Judge("item:11") == nil
    and OffSpec:OnlyUpgrade("item:11") == nil and OffSpec:Outfit() == nil)
local said
Finder:ScanOff(0, function(found, why) said = why end)
suite.check("None makes no Off Spec scan", said == "none" and not Finder:ScanningOff()
    and Finder:OffFound(0) == nil)
local before = Finder:Scan()
for _, spec in ipairs(judgedAs) do
    if spec ~= "ret" then outfits = outfits + 1 end
end
suite.check("with None every piece is judged for the Main Spec only", outfits == 0 and #judgedAs > 0)
Compare.ScoreOf = realScore

-- 2.
OffSpec:Set("prot")
suite.check("the pick is saved per character as offSpec", ns.charDB.offSpec == "prot" and OffSpec:Key() == "prot")
suite.check("Main keeps its own key", ns.charDB.spec == "ret" and Weights:CurrentSpec() == "ret")
suite.check("the Off Spec's name", OffSpec:Name() == "Protection", OffSpec:Name())
ns.charDB.spec = "prot"
suite.check("the same spec as Main counts as None", OffSpec:Key() == nil)
ns.charDB.spec = "ret"

-- 3.
local outfit = OffSpec:Outfit()
suite.check("the outfit takes the tank one-hander and shield from the bags",
    outfit and outfit[16] == "item:3" and outfit[17] == "item:4", outfit and tostring(outfit[16]) .. "/" .. tostring(outfit[17]))
suite.check("a slot with nothing better keeps what is worn", outfit and outfit[5] == "item:10")
local shield = OffSpec:Judge("item:11")
suite.check("a better shield is measured against the shield in the bags",
    Verdict(shield) == "upgrade" and shield.percent and shield.percent > 50 and shield.percent < 150,
    shield and tostring(shield.percent))
local carried = OffSpec:Judge("item:4")
suite.check("the shield already carried is no Off Spec upgrade from a vendor", Verdict(carried) == "equipped",
    Verdict(carried))
local inBags = OffSpec:Judge("item:4", true)
suite.check("in the bags it is an Off Spec piece over what is worn", Verdict(inBags) == "upgrade", Verdict(inBags))
suite.check("an outfit piece is known as one", OffSpec:InOutfit("item:4") and not OffSpec:InOutfit("item:11"))

-- 4.
local big = OffSpec:Judge("item:2")
suite.check("Protection never gets a two-hander", Verdict(big) == "cantuse" and big.tankTwoHand)
suite.check("Retribution still does", Verdict(Compare:Judge("item:2")) == "upgrade",
    Verdict(Compare:Judge("item:2")))

-- 5.
suite.check("nothing leaks after judging for the Off Spec",
    Weights.judgeAs == nil and Items.wornAs == nil and Weights:CurrentSpec() == "ret"
    and Items:Equipped(16) == "item:1" and not OffSpec:Inside())
suite.check("the Main Spec's verdict on the better shield is its own",
    Verdict(Compare:Judge("item:11")) == "downgrade", Verdict(Compare:Judge("item:11")))
OffSpec:Enter()
OffSpec:Enter()
suite.check("inside, the Off Spec and its outfit answer", Weights:CurrentSpec() == "prot"
    and Items:Equipped(16) == "item:3" and Finder.offPass == true)
OffSpec:Settle()
suite.check("Settle leaves every Enter left open", Weights.judgeAs == nil and Items.wornAs == nil
    and not Finder.offPass and Items:Equipped(16) == "item:1")
local okRun = OffSpec:Run(function() error("boom") end)
suite.check("an error inside Run leaves nothing open", okRun == nil and not OffSpec:Inside()
    and Weights.judgeAs == nil)

-- 6.
Finder:MarkStale()
local main = Finder:Scan()
local mainJudged = Finder.judged
local offFound
Finder:ScanOff(0, function(found) offFound = found end)
suite.check("the Off Spec scan is in", offFound ~= nil)
suite.check("it lists the better shield and chest", Listed(offFound, 17) == "11" and Listed(offFound, 5) == "12",
    Listed(offFound, 17) .. " / " .. Listed(offFound, 5))
suite.check("it never lists a two-hander or what is carried",
    not Listed(offFound, 16):find("2", 1, true) and not Listed(offFound, 17):find("4", 1, true),
    Listed(offFound, 16))
suite.check("the shared scan is still the Main Spec's", Finder.latest == main and Listed(main, 17) == ""
    and Listed(main, 16) == "2", Listed(main, 16))
suite.check("the Main Spec's kept verdicts are untouched", Finder.judged == mainJudged
    and Finder.judged[11] and Finder.judged[11].result.verdict == "downgrade")
suite.check("the Off Spec scan is kept", Finder:OffFound(0) == offFound and Finder:OffLatest() == offFound)
local again
Finder:ScanOff(0, function(found) again = found end)
suite.check("asked again with nothing changed it is handed back", again == offFound)
env.bags[0][3] = "item:11"
OffSpec:Forget()
suite.check("a bag change makes it old", Finder:OffFound(0) == nil)
env.bags[0][3] = nil
OffSpec:Forget()

-- 7.
suite.check("blue arrow: only the Off Spec gains", OffSpec:OnlyUpgrade("item:11") ~= nil)
suite.check("no blue arrow when the Main Spec gains too", OffSpec:OnlyUpgrade("item:12") == nil)
suite.check("no blue arrow for a two-hander", OffSpec:OnlyUpgrade("item:2") == nil)

-- 8.
ns.HandleSlash("spec off none")
suite.check("/beq spec off none turns it off", ns.charDB.offSpec == nil and OffSpec:Key() == nil)
ns.HandleSlash("spec off holy")
suite.check("/beq spec off holy picks it", ns.charDB.offSpec == "holy", tostring(ns.charDB.offSpec))
ns.HandleSlash("spec off nonsense")
suite.check("a wrong name keeps the pick", ns.charDB.offSpec == "holy")
ns.HandleSlash("spec auto")
suite.check("/beq spec auto leaves the Off Spec alone", ns.charDB.offSpec == "holy" and ns.charDB.spec == nil)

suite.done()
