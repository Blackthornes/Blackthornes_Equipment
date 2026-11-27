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
suite.check("in the bags it is the Off Spec's own piece, no upgrade", Verdict(inBags) ~= "upgrade", Verdict(inBags))
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
suite.check("the shield bought joins the outfit and is no Off Spec upgrade any more",
    Verdict(OffSpec:Judge("item:11")) == "equipped" and OffSpec:Outfit()[17] == "item:11",
    Verdict(OffSpec:Judge("item:11")))
local keptShield, keptChest = OffSpec:Run(function()
    local judged = Finder:Judged()
    return Finder:Kept(judged, 11), Finder:Kept(judged, 12)
end)
suite.check("kept Off Spec verdicts on the changed slot are judged again, others kept",
    keptShield == nil and keptChest ~= nil, tostring(keptShield) .. " " .. tostring(keptChest))
env.bags[0][3] = nil
OffSpec:Forget()

-- 7.
suite.check("blue arrow: only the Off Spec gains", OffSpec:OnlyUpgrade("item:11") ~= nil)
suite.check("no blue arrow when the Main Spec gains too", OffSpec:OnlyUpgrade("item:12") == nil)
suite.check("no blue arrow for a two-hander", OffSpec:OnlyUpgrade("item:2") == nil)


-- 9. Find Upgrades: MAIN and OFF columns, Show, the tags and the footer.
local Gear, Find = ns.GearWindow, ns.FindUpgrades
ns.UI:Show()
Gear:ShowTab("find")
Find.sheetHold:SetHeight(590)
Find:Refresh()
local function Head(key)
    for _, head in ipairs(Find.heads) do
        if head.key == key then return head end
    end
end
local function Line(itemID)
    for _, line in ipairs(Find.shown or {}) do
        if line.pick.itemID == itemID then return line end
    end
end
suite.check("with an Off Spec the list has two gain columns", Find:Dual() and Head("off"):IsShown()
    and Head("gain").label:GetText() == "MAIN" and Head("off").label:GetText() == "OFF",
    tostring(Head("gain").label:GetText()))
suite.check("Show is there", Find.showHold:IsShown())
local shieldLine, bigLine, chestLine = Line(11), Line(2), Line(12)
suite.check("the better shield is an Off only row", shieldLine and shieldLine.off and not shieldLine.main)
suite.check("the big two-hander is a Main only row", bigLine and bigLine.main and not bigLine.off)
suite.check("the chest helps both", chestLine and chestLine.main and chestLine.off)
suite.check("the footer counts both", Find.footer:GetText():find("for Retribution", 1, true) ~= nil
    and Find.footer:GetText():find("for Protection", 1, true) ~= nil, Find.footer:GetText())
Find:SetShow("off")
suite.check("Show Off Spec: only rows that help it, one column named OFF",
    Line(11) and Line(12) and not Line(2) and not Head("off"):IsShown() and Head("gain").label:GetText() == "OFF")
Find:SetShow("main")
suite.check("Show Main Spec: only rows that help it", Line(2) and Line(12) and not Line(11)
    and Head("gain").label:GetText() == "MAIN")
Find:SetShow("both")

-- 10. The tooltip: a line for each spec.
local tipLines = ns.Tooltip.SpecLines("item:11", false, Compare:Judge("item:11"))
suite.check("the tooltip says Main Spec: no upgrade and the Off Spec's gain",
    tipLines and tipLines[1].label == "Main Spec:" and tipLines[1].answer == "no upgrade"
    and tipLines[2].label == "Off Spec:" and tipLines[2].answer:find("^%+%d+%%$") ~= nil,
    tipLines and tipLines[2].answer)
suite.check("no spec lines when neither gains", ns.Tooltip.SpecLines("item:10", false, Compare:Judge("item:10")) == nil)

-- 11. The tank set in the bags gets no arrow (it is the set) and no sell
-- coin.
suite.check("the shield in the bags gets no blue arrow", OffSpec:OnlyUpgrade("item:4", true) == nil)
-- Butler asks the same sell rule the bags use (Butler:Advise), so it must
-- not say Sell for the tank set either. White gear a vendor pays for:
local oldInfo, oldTip = _G.C_Container.GetContainerItemInfo, _G.C_TooltipInfo
_G.C_Container.GetContainerItemInfo = function() return { quality = 1, isBound = false, stackCount = 1 } end
_G.C_TooltipInfo = { GetHyperlink = function() return { lines = { { type = 11, price = 50 } } } end }
local mainOnShield = Compare:JudgeCarried("item:4")
suite.check("the Main Spec has no use for the shield in the bags", Verdict(mainOnShield) ~= "upgrade",
    Verdict(mainOnShield))
suite.check("the sell rule leaves an Off Spec piece alone", ns.BagIcons:Sells(0, 2, "item:4", mainOnShield) == false)
local advice = ns.Butler:Advise("item:4", 0, 2)
suite.check("Butler is not told to sell an Off Spec piece", advice ~= nil and advice.sell == false,
    advice and tostring(advice.sell))
ns.charDB.offSpec = nil
OffSpec:Forget()
suite.check("with None the same shield sells as before", ns.BagIcons:Sells(0, 2, "item:4", mainOnShield) == true)
ns.charDB.offSpec = "prot"
OffSpec:Forget()
_G.C_Container.GetContainerItemInfo, _G.C_TooltipInfo = oldInfo, oldTip

-- 8.
ns.HandleSlash("spec off none")
suite.check("/beq spec off none turns it off", ns.charDB.offSpec == nil and OffSpec:Key() == nil)
Find:Refresh()
suite.check("with None the list is as before", not Find:Dual() and not Head("off"):IsShown()
    and Head("gain").label:GetText() == "GAIN" and not Find.showHold:IsShown())
ns.HandleSlash("spec off holy")
suite.check("/beq spec off holy picks it", ns.charDB.offSpec == "holy", tostring(ns.charDB.offSpec))
ns.HandleSlash("spec off nonsense")
suite.check("a wrong name keeps the pick", ns.charDB.offSpec == "holy")
ns.HandleSlash("spec auto")
suite.check("/beq spec auto leaves the Off Spec alone", ns.charDB.offSpec == "holy" and ns.charDB.spec == nil)


-- 12. Settings: the Off Spec row, and the drop-down on Find Upgrades.
Gear:ShowTab("settings")
local controls = ns.SettingsUI.controls
suite.check("Settings has the Off Spec drop-down, set to the pick", controls.offSpec ~= nil
    and controls.offSpec:GetValue() == ns.SettingsUI:OffSpecIndex())
controls.offSpec:Pick(1)
suite.check("picking None in Settings turns it off", ns.charDB.offSpec == nil)
local choices = ns.SettingsUI:OffSpecChoices()
local protIndex
for index, key in ipairs(choices) do if key == "prot" then protIndex = index end end
Gear:ShowTab("find")
Find.offChoice:Pick(protIndex)
suite.check("picking it on Find Upgrades saves it", ns.charDB.offSpec == "prot")
suite.check("the Main Spec drop-down names what Auto follows", ns.FinderUI.SpecText(1):find("^Auto %(") ~= nil,
    ns.FinderUI.SpecText(1))

-- 13. Make It My Quest on an Off only row (Find Upgrades): the quest is
-- kept, though the Main Spec has no use for the piece. Before, it was
-- dropped at once with "you're already wearing something as good".
local Quest = ns.UpgradeQuest
local function OnATab(itemID)
    for _, quest in pairs(Quest:Quests()) do
        if type(quest) == "table" and quest.itemID == itemID then return quest end
    end
end
ns.charDB.spec = "ret"
OffSpec:Forget()
Finder:MarkStale()
Finder:Scan()
local offNow
Finder:ScanOff(0, function(found) offNow = found end)
local shieldPick = offNow and offNow.all[17] and offNow.all[17][1]
suite.check("the better shield is an Off Spec pick the Main Spec does not want",
    shieldPick and shieldPick.itemID == 11 and Verdict(Compare:Judge("item:11")) == "downgrade")
local followed = Quest:Follow(shieldPick)
suite.check("Make It My Quest takes an Off only pick", followed ~= nil and followed.itemID == 11)
Quest:Update()
Quest:Update()
suite.check("and the quest is kept on later looks", OnATab(11) ~= nil, env.ChatText())
suite.check("with the Off Spec's gain", OnATab(11) and tostring(OnATab(11).howMuch):find("^%+%d+%%$") ~= nil,
    OnATab(11) and tostring(OnATab(11).howMuch))
-- Bought: it waits in the bags for the Off Spec, so the quest stays until
-- it is put on.
env.bags[0][3] = "item:11"
OffSpec:Forget()
Finder:MarkStale()
Quest:Update()
suite.check("carried and not yet worn, the quest still stands", OnATab(11) ~= nil)
env.bags[0][3] = nil
OffSpec:Forget()
Finder:MarkStale()
-- With the Off Spec back on None the Main Spec's answer stands again.
ns.charDB.offSpec = nil
OffSpec:Forget()
Quest:Update()
suite.check("with None a followed piece the Main Spec does not want is let go", OnATab(11) == nil)
-- The other way round: Protection as Main, and a two-hander followed for
-- a Retribution Off Spec is not let go as "a two-hander for a tank".
ns.charDB.spec, ns.charDB.offSpec = "prot", "ret"
OffSpec:Forget()
ns.Weights:Changed()
Finder:Scan()
offNow = nil
Finder:ScanOff(0, function(found) offNow = found end)
local bigPick
for _, pick in ipairs(offNow and offNow.all[16] or {}) do
    if pick.itemID == 2 then bigPick = pick end
end
suite.check("the big two-hander is an Off Spec pick for Retribution", bigPick ~= nil
    and Compare:Judge("item:2").tankTwoHand == true)
Quest:Follow(bigPick)
Quest:Update()
Quest:Update()
suite.check("a two-hander followed for the Off Spec is kept", OnATab(2) ~= nil)
ns.charDB.offSpec = nil
OffSpec:Forget()
Quest:Update()
suite.check("and let go once the Off Spec is None", OnATab(2) == nil)
ns.charDB.spec = "ret"
ns.Weights:Changed()

suite.done()
