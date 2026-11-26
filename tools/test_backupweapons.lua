-- The backup weapon set (Logic/BackupWeapons.lua, the owner said build it
-- from the mockup, 2026-11-26).
--
-- What must hold:
--   1. A new off hand looked at while a two-hander is worn was weighed
--      against the whole two-hander on its own (always far worse). Now it
--      is weighed with the best main hand you own: "Main Spec: +13% with
--      ...", and "Your backup set beats your two-hander."
--   2. Find Upgrades pairs a new piece with one you own: "with ..., in your
--      bags", under the new piece's hand.
--   3. With Backup Weapon Set on, a new piece that beats the backup set's
--      piece for its hand is listed and named on the tooltip, even while the
--      pair still loses (the owner asked, 2026-11-26).
--   4. The switch is off at the start: no card, no banner, no extra rows.
--   5. The card shows the best pair, both bars, and Put Them On once the
--      pair wins; Put Them On waits for a fight to end.
--   6. The banner shows once when the pair starts to win; Not Now keeps it
--      quiet.
--   7. The other way round: wearing a pair, the backup is the best
--      two-hander owned.
--   8. A piece of a winning backup set is never offered for sale.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("backupweapons")

local ARMOR, WEAPON = 4, 2
local SHIELD, SWORD1H, SWORD2H = 6, 7, 8
local function Str(n) return { ITEM_MOD_STRENGTH_SHORT = n } end

local ITEMS = {
    ["item:1"] = { loc = "INVTYPE_2HWEAPON", class = WEAPON, subclass = SWORD2H, stats = Str(30) },  -- worn
    ["item:3"] = { loc = "INVTYPE_WEAPON", class = WEAPON, subclass = SWORD1H, stats = Str(14) },    -- bags
    ["item:4"] = { loc = "INVTYPE_SHIELD", class = ARMOR, subclass = SHIELD, stats = Str(12) },      -- bags
    ["item:5"] = { loc = "INVTYPE_SHIELD", class = ARMOR, subclass = SHIELD, stats = Str(20) },      -- new
    ["item:6"] = { loc = "INVTYPE_WEAPON", class = WEAPON, subclass = SWORD1H, stats = Str(15) },    -- new
    ["item:7"] = { loc = "INVTYPE_2HWEAPON", class = WEAPON, subclass = SWORD2H, stats = Str(50) },  -- for 7.
}

local ns = env.Load()
_G.UnitClass = function() return "Paladin", "PALADIN", 2 end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitRace = function() return "Human", "Human", 1 end
env.InstallItems(ITEMS, { [16] = "item:1" },
    { [0] = { [1] = "item:3", [2] = "item:4", [3] = false, [4] = false } }, 40)
_G.C_QuestLog = { IsQuestFlaggedCompleted = function() return false end }

local S = ns.Sources
ns.Crafts.ITEMS = {}
ns.RollData.ITEMS = {}
S.FOREVER, S.QUESTS, S.DUNGEONS, S.BOSSES = {}, {}, {}, {}
S.ZONES = { [12] = "Elwynn Forest" }
S.NPCS = { [1] = { "Andrew", 12, 40, 60, "A" } }
S.ITEMS = {
    [5] = { 30, 35, 0, 0, 100, v = { 1, 0 } },
    [6] = { 30, 35, 0, 0, 100, v = { 1, 0 } },
}

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end
local fighting = false
_G.InCombatLockdown = function() return fighting end
_G.C_Timer = nil
ns.charDB.spec = "ret"

local equipped = {}
local function FindInBags(link)
    for bag, slots in pairs(env.bags) do
        for slot, held in pairs(slots) do
            if held == link then return bag, slot end
        end
    end
end
_G.C_Item.EquipItemByName = function(link, slot)
    equipped[#equipped + 1] = tostring(slot) .. "=" .. link
    local bag, bagSlot = FindInBags(link)
    if not bag then return end
    env.bags[bag][bagSlot] = env.worn[slot] or false
    env.worn[slot] = link
end

local Backup, Compare, Finder, Tooltip = ns.BackupWeapons, ns.Compare, ns.Finder, ns.Tooltip
local weights = ns.Weights:ForPlayer()
suite.check("the sample: Retribution weights read Strength", weights ~= nil
    and Compare:ScoreOf("item:1", weights) > Compare:ScoreOf("item:3", weights))

-- 1.
local alone = Compare:Judge("item:5")
suite.check("on its own the new shield is far worse than the two-hander", alone and alone.verdict == "downgrade",
    alone and alone.verdict)
local paired = Backup:WithPartner("item:5", alone)
suite.check("with the sword you own it wins", paired and paired.verdict == "upgrade"
    and paired.partner and paired.partner.link == "item:3", paired and paired.verdict)
local s1, s3, s5 = Compare:ScoreOf("item:1", weights), Compare:ScoreOf("item:3", weights),
    Compare:ScoreOf("item:5", weights)
suite.check("by both scores against the two-hander's", paired
    and math.abs(paired.percent - (s3 + s5 - s1) / s1 * 100) < 0.01, paired and paired.percent)
Tooltip.ForgetLines()
local lines = Tooltip:WorkOutLines("item:5", false)
local first = lines[1]
suite.check("the tooltip says Main Spec: +N% with the sword", first and first.label == "Main Spec:"
    and first.answer:find("^%+%d+%% with ") ~= nil and first.answer:find("item:3", 1, true) ~= nil,
    first and first.answer)
local says = false
for _, line in ipairs(lines) do
    if line[1] == "Your backup set beats your two-hander." then says = true end
end
suite.check("and that the backup set beats the two-hander", says)
suite.check("a chest is judged as before", Backup:WithPartner("item:1", Compare:Judge("item:1")) == nil)

-- 4.
suite.check("Backup Weapon Set is off at the start", not Backup.On())
local found = Finder:Scan()
suite.check("no backup rows with it off", found and (found.backup == nil or #found.backup == 0))
suite.check("no backup tooltip line with it off", Tooltip.BackupLine("item:6") == nil)

-- 2.
local owned
for _, pick in ipairs(found and found.pairs or {}) do
    if pick.pair and pick.pair.owned then owned = owned or pick end
end
suite.check("Find Upgrades pairs the new shield with the sword you own", owned and owned.itemID == 5
    and owned.pair.link == "item:3" and owned.pair.owned == "bags",
    owned and (owned.itemID .. "+" .. tostring(owned.pair.link)))
suite.check("listed under the off hand", owned and owned.result.slot == 17)

local Gear, Find = ns.GearWindow, ns.FindUpgrades
ns.UI:Show()
Gear:ShowTab("find")
Find.sheetHold:SetHeight(590)
local row
for _, r in ipairs(Find.rows) do
    local l = r:IsShown() and rawget(r, "line")
    if l and l.pair and l.pair.owned then row = r end
end
suite.check("the row says with the sword, in your bags", row
    and row.item:GetText():find("with item:3, in your bags", 1, true) ~= nil, row and row.item:GetText())
suite.check("tagged Pair, under Off Hand", row and row.item:GetText():find("Pair", 1, true) ~= nil
    and row.slot:GetText() ~= "Both Hands", row and row.slot:GetText())

-- 3.
Backup:SetOn(true)
suite.check("ticked, it is on", Backup.On() and ns.db.backupWeapons == true)
Finder:ForgetVerdicts()
Finder:MarkStale()
found = Finder:Scan()
local ups = {}
for _, pick in ipairs(found and found.backup or {}) do ups[pick.itemID] = pick end
suite.check("the new sword beats the backup sword", ups[6] ~= nil and ups[6].backup.link == "item:3")
suite.check("the new shield beats the backup shield", ups[5] ~= nil and ups[5].backup.link == "item:4")
local beats = Tooltip.BackupLine("item:6")
suite.check("the tooltip says Backup Set: +N% over the sword", beats and beats.label == "Backup Set:"
    and beats.answer:find("over item:3", 1, true) ~= nil, beats and beats.answer)
suite.check("a backup piece is not better than itself", Tooltip.BackupLine("item:3") == nil)
local backupRow
Find:Refresh()
for _, r in ipairs(Find.rows) do
    local l = r:IsShown() and rawget(r, "line")
    if l and l.backup then backupRow = r end
end
suite.check("Find Upgrades lists it, tagged Backup", backupRow
    and backupRow.item:GetText():find("Backup", 1, true) ~= nil
    and backupRow.item:GetText():find("in your backup set", 1, true) ~= nil,
    backupRow and backupRow.item:GetText())

-- 5.
local set = Backup:Set()
suite.check("the backup set is the sword and the shield", set and set.mode == "pair"
    and set.main.link == "item:3" and set.off.link == "item:4")
suite.check("it does not beat the two-hander yet", set and not set.beats)
Gear:ShowTab("gear")
local MyGear = ns.MyGear
MyGear:Refresh()
MyGear:PickSlot(16)
local card = MyGear.backupCard
suite.check("the card shows on My Gear with a hand picked", card and card:IsShown())
suite.check("its bars are the two-hander and the backup set", card
    and card.wornBar.label:GetText() == "Your two-hander:" and card.backupBar.label:GetText() == "Backup set:")
suite.check("no Put Them On while the two-hander wins", card and not card.button:IsShown())
MyGear:PickSlot(5)
suite.check("not on another slot", not card:IsShown())

-- 6. The shield comes into the bags: now the pair wins.
local banners = {}
local realShow = ns.Toast.Show
ns.Toast.Show = function(_, banner) banners[#banners + 1] = banner return true end
Backup.seen = nil
Backup:Check()
suite.check("the first look notes what is so, with no banner", #banners == 0)
env.bags[0][3] = "item:5"
Backup:Forget()
Backup:Check()
suite.check("a banner when the pair starts to win", #banners == 1
    and banners[1].title == "BACKUP WEAPON SET", #banners)
suite.check("it names the worn two-hander", banners[1] and banners[1].line:find("item:1", 1, true) ~= nil)
suite.check("with Put Them On and Not Now", banners[1] and banners[1].actions[1].text == "Put Them On"
    and banners[1].actions[2].text == "Not Now")
banners[1].actions[2].fn()
Backup.seen = ""
Backup:Check()
suite.check("Not Now keeps it quiet", #banners == 1)
ns.Toast.Show = realShow

set = Backup:Set()
MyGear:PickSlot(17)
suite.check("the card says the backup set beats the two-hander", card:IsShown()
    and card.line:GetText():find("Your backup set now beats your two-hander by", 1, true) ~= nil,
    card.line:GetText())
suite.check("and offers Put Them On", card.button:IsShown())

-- 8.
_G.C_Container.GetContainerItemInfo = function() return { quality = 1, isBound = false, stackCount = 1 } end
_G.C_TooltipInfo = { GetHyperlink = function() return { lines = { { type = 11, price = 50 } } } end }
suite.check("a piece of the winning set is never offered for sale",
    ns.BagIcons:Sells(0, 1, "item:3", Compare:JudgeCarried("item:3")) == false)

fighting = true
Backup:PutOn()
suite.check("in a fight nothing goes on", #equipped == 0)
fighting = false
Backup:FightOver()
suite.check("after it the sword and the new shield go on", env.worn[16] == "item:3" and env.worn[17] == "item:5",
    tostring(env.worn[16]) .. "/" .. tostring(env.worn[17]))
suite.check("main hand first", equipped[1] == "16=item:3" and equipped[2] == "17=item:5")

-- 7. Now a pair is worn: the backup is the best two-hander owned.
Backup:Forget()
set = Backup:Set()
suite.check("wearing a pair, the backup is the two-hander", set and set.mode == "two"
    and set.two.link == "item:1")
env.bags[0][4] = "item:7"
Backup:Forget()
set = Backup:Set()
suite.check("a stronger two-hander takes its place and wins", set and set.two.link == "item:7" and set.beats)
MyGear:PickSlot(16)
suite.check("the card's bars say your pair", card.wornBar.label:GetText() == "Your pair:")

-- The switch off again: no card.
Backup:SetOn(false)
MyGear:PickSlot(16)
suite.check("unticked, the card goes", not card:IsShown())

suite.done()
