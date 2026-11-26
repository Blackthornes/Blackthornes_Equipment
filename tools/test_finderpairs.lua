-- A pair of one-handers against a worn two-hander (the owner said build
-- it from a mockup, 2026-11-26). Before, only the other way round was
-- weighed: a two-hander against the main hand and off hand together. A
-- warrior with a big axe never saw that a sword and a shield together
-- beat it.
--
-- What must hold:
--   1. With a two-hander worn, the best one-hander and its best partner
--      (a shield, an off-hand piece or, for those who dual wield, another
--      one-hander) show as one "Pair" line when the two beat it.
--   2. The pair's gain is both scores against the two-hander's.
--   3. Find Upgrades lists it under Both Hands, with where each comes from;
--      untick the partner's source and the pair leaves.
--   4. No pair while a one-hander is worn, or when the two don't beat it.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("finderpairs")

local WEAPON, ARMOR, AXE2H, SWORD, SHIELD = 2, 4, 1, 7, 6
local function Weapon(loc, subclass, dps, more)
    local stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = dps }
    for k, v in pairs(more or {}) do stats[k] = v end
    return { loc = loc, class = WEAPON, subclass = subclass, stats = stats }
end

local ITEMS = {
    ["item:900"] = Weapon("INVTYPE_2HWEAPON", AXE2H, 20),   -- worn
    ["item:2001"] = Weapon("INVTYPE_WEAPON", SWORD, 16, { ITEM_MOD_STRENGTH_SHORT = 8 }),
    ["item:2002"] = { loc = "INVTYPE_SHIELD", class = ARMOR, subclass = SHIELD,
        stats = { ITEM_MOD_STRENGTH_SHORT = 30, ITEM_MOD_STAMINA_SHORT = 20 } },
    ["item:2003"] = Weapon("INVTYPE_WEAPON", SWORD, 4),     -- a weak one
}

local ns = env.Load()
_G.UnitClass = function() return "Warrior", "WARRIOR", 1 end
_G.UnitFactionGroup = function() return "Horde", "Horde" end
_G.UnitRace = function() return "Orc", "Orc", 2 end
env.InstallItems(ITEMS, { [16] = "item:900" }, { [0] = {} }, 38)
_G.C_QuestLog = { IsQuestFlaggedCompleted = function() return false end }

local S = ns.Sources
ns.Crafts.ITEMS = {}
ns.RollData.ITEMS = {}
S.FOREVER, S.QUESTS, S.DUNGEONS, S.BOSSES = {}, {}, {}, {}
S.ZONES = { [405] = "Desolace", [17] = "The Barrens" }
S.NPCS = { [1] = { "Selendra", 405, 26.9, 77.7, "H" }, [2] = { "Jazzik", 17, 50, 50, "H" } }
S.ITEMS = {
    [2001] = { 30, 35, 0, 0, 100, v = { 1, 0 } },
    [2002] = { 30, 35, 0, 0, 100, v = { 2, 0 } },
    [2003] = { 30, 35, 0, 0, 100, v = { 1, 0 } },
}

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end
local Finder, Compare = ns.Finder, ns.Compare
ns.UpgradeQuest.Zone = function() return "Desolace" end

local weights = ns.Weights:ForPlayer()
local axe = Compare:ScoreOf("item:900", weights)
local sword = Compare:ScoreOf("item:2001", weights)
local shield = Compare:ScoreOf("item:2002", weights)
suite.check("the sample: neither beats the axe alone, but both do", sword < axe and shield < axe
    and sword + shield > axe, ("%s %s %s"):format(axe, sword, shield))

-- 1. and 2.
local found = Finder:Scan()
suite.check("it scans", found ~= nil)
local pair = found and found.pairs and found.pairs[1]
suite.check("a pair is found", pair ~= nil)
suite.check("the sword in the main hand, the shield beside it", pair and pair.itemID == 2001
    and pair.pair.itemID == 2002, pair and (pair.itemID .. "+" .. pair.pair.itemID))
suite.check("one pair per main hand at most, the weak sword's too weak", #found.pairs == 1, #found.pairs)
local percent = (sword + shield - axe) / axe * 100
suite.check("its gain is both against the axe", pair and math.abs(pair.result.percent - percent) < 0.01,
    pair and pair.result.percent)
suite.check("it keeps where each comes from", pair and pair.sources[1].name == "Selendra"
    and pair.pair.sources[1].name == "Jazzik")

-- 3.
local Gear, Find = ns.GearWindow, ns.FindUpgrades
ns.UI:Show()
Gear:ShowTab("find")
Find.sheetHold:SetHeight(590)
local line
for _, l in ipairs(Find.shown or {}) do if l.pair then line = l end end
suite.check("Find Upgrades lists the pair", line ~= nil)
local row
for _, r in ipairs(Find.rows) do if r:IsShown() and rawget(r, "line") == line then row = r end end
suite.check("as one row naming both", row and row.item:GetText():find("2001", 1, true) ~= nil
    and row.item:GetText():find(" + ", 1, true) ~= nil and row.item:GetText():find("2002", 1, true) ~= nil,
    row and row.item:GetText())
suite.check("tagged Pair", row and row.item:GetText():find("Pair", 1, true) ~= nil)
suite.check("under Both Hands", row and row.slot:GetText() == "Both Hands", row and row.slot:GetText())
suite.check("with where each comes from", row and row.where:GetText():find("Desolace", 1, true) ~= nil
    and row.where:GetText():find("The Barrens", 1, true) ~= nil, row and row.where:GetText())
suite.check("Main Hand keeps it", (function() Find:SetSlot(16) local ok = false
    for _, l in ipairs(Find.shown) do if l.pair then ok = true end end Find:SetSlot(nil) return ok end)())
Find.picked = line.key
Find:PaintSheet()
suite.check("the sheet names both", Find.sheetName:GetText():find(" + ", 1, true) ~= nil)
local placed = {}
for _, label in ipairs(Find.sheetPlaces) do if label:IsShown() then placed[#placed + 1] = label:GetText() end end
suite.check("and lists both places", #placed == 2 and placed[2]:find("Jazzik", 1, true) ~= nil, #placed)
suite.check("found by the partner's name", (function()
    Find.find = "2002" Find:Narrow()
    local ok = false
    for _, l in ipairs(Find.shown) do if l.pair then ok = true end end
    Find.find = nil Find:Narrow() return ok end)())

-- 4.
_G.GetInventoryItemLink = function(_, slot) if slot == 16 then return "item:2003" end end
local realEquipped = ns.Items.Equipped
ns.Items.Equipped = function(self, slot) if slot == 16 then return "item:2003" end return nil end
Finder:ForgetVerdicts()
Finder:MarkStale()
local again = Finder:Scan()
suite.check("no pair beside a one-hander", again and #again.pairs == 0, again and #again.pairs)
ns.Items.Equipped = function(self, slot) if slot == 16 then return "item:900" end return nil end
ITEMS["item:900"].stats.ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 60
Compare:ForgetScores()
Finder:ForgetVerdicts()
Finder:MarkStale()
again = Finder:Scan()
suite.check("no pair when the two don't beat the two-hander", again and #again.pairs == 0, again and #again.pairs)
ns.Items.Equipped = realEquipped

suite.done()
