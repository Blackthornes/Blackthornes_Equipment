-- Why It's Better (the owner said build it, 2026-11-26): what goes up and
-- what goes down when a piece goes on, and one plain line that sums it up.
--
-- What must hold:
--   1. Compare:Why lists each stat the spec weighs that changes, gains first
--      and biggest first, against what the piece replaces.
--   2. Stats the spec doesn't weigh are left out, and plain crit rating
--      counts with crit.
--   3. The plain line names two gains and two losses at most, "a little
--      less" when the losses are small, "less" when they are not.
--   4. The tooltip carries the line under the verdict, only for better or
--      worse gear, and Settings turns it Off.
--   5. The Find Upgrades sheet shows the line, a bar per stat (gains right,
--      losses left) and what the gain is worth.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("whybetter")

local ARMOR, LEATHER = 4, 2
local function Piece(loc, stats)
    return { loc = loc, class = ARMOR, subclass = LEATHER, stats = stats, bind = 0 }
end

-- A hunter judged as Beast Mastery: agility 1, stamina 0.5, crit 12 a
-- percent, armor 0.02, spirit 0.1. Hunters weigh no spell power.
local ITEMS = {
    ["item:800"] = Piece("INVTYPE_HEAD", { ITEM_MOD_AGILITY_SHORT = 10, ITEM_MOD_STAMINA_SHORT = 4 }), -- worn
    ["item:801"] = Piece("INVTYPE_HEAD", { ITEM_MOD_AGILITY_SHORT = 20, ITEM_MOD_STAMINA_SHORT = 2,
        ITEM_MOD_SPELL_POWER_SHORT = 30 }),
    ["item:802"] = Piece("INVTYPE_HEAD", { ITEM_MOD_AGILITY_SHORT = 8, ITEM_MOD_STAMINA_SHORT = 4,
        ITEM_MOD_CRIT_RATING_SHORT = 14 }),
    ["item:803"] = Piece("INVTYPE_HEAD", { ITEM_MOD_STAMINA_SHORT = 14 }),
    ["item:804"] = Piece("INVTYPE_HEAD", { ITEM_MOD_AGILITY_SHORT = 10, ITEM_MOD_STAMINA_SHORT = 4 }),
    ["item:900"] = Piece("INVTYPE_CHEST", { ITEM_MOD_AGILITY_SHORT = 10 }), -- worn
    ["item:901"] = Piece("INVTYPE_CHEST", { ITEM_MOD_AGILITY_SHORT = 20 }),
}

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitRace = function() return "Human", "Human", 1 end
env.InstallItems(ITEMS, { [1] = "item:800", [5] = "item:900" }, { [0] = {} }, 20)
-- At level 60 rating reads as the usual table: 14 crit rating is 1%.
_G.UnitLevel = function() return 60 end

local Compare = ns.Compare

local function Names(changes)
    local out = {}
    for _, change in ipairs(changes or {}) do out[#out + 1] = change.key .. "=" .. Compare.WhyAmount(change) end
    return table.concat(out, ",")
end

-- 1. and 2.
local result = Compare:Judge("item:801")
suite.check("the verdict keeps what it was judged with", type(result.weights) == "table"
    and result.replaced and result.replaced[1] == "item:800", result.replaced and result.replaced[1])
local changes = Compare:Why("item:801", result)
suite.check("gains first, then losses; spell power left out", Names(changes) == "agility=+10,stamina=-2",
    Names(changes))
suite.check("each change says what it is worth", math.abs(changes[1].worth - 10) < 1e-6
    and math.abs(changes[2].worth + 1) < 1e-6, changes[1].worth)
suite.check("and carries the stat's name", changes[1].name == "Agility" and changes[2].name == "Stamina")

local critResult = Compare:Judge("item:802")
local crit = Compare:Why("item:802", critResult)
suite.check("plain crit rating counts as crit, in percent", Names(crit) == "crit=+1%,agility=-2", Names(crit))

suite.check("the same piece changes nothing", Compare:Why("item:804", Compare:Judge("item:804")) ~= nil
    and #Compare:Why("item:804", Compare:Judge("item:804")) == 0)
suite.check("no kept weights, no answer", Compare:Why("item:801", { verdict = "upgrade" }) == nil)

-- 3.
suite.check("small losses read a little less", Compare.WhyLine(changes) == "More Agility. A little less Stamina.",
    Compare.WhyLine(changes))
suite.check("and the worth line says where the gain is", Compare.WhyWorth(changes)
    == "Most of the gain is Agility. Stamina takes a little back.", Compare.WhyWorth(changes))
local stam = Compare:Why("item:803", Compare:Judge("item:803"))
suite.check("big losses read less", Compare.WhyLine(stam) == "More Stamina. Less Agility.", Compare.WhyLine(stam))
suite.check("and nothing comes back a little", Compare.WhyWorth(stam) == "Most of the gain is Stamina.",
    Compare.WhyWorth(stam))
local fake = {
    { key = "a", name = "Strength", amount = 7, worth = 7 },
    { key = "b", name = "Crit", amount = 1, worth = 3 },
    { key = "c", name = "Armor", amount = 38, worth = 0.1 },
    { key = "d", name = "Agility", amount = -4, worth = -1 },
}
suite.check("two gains and a loss, as on the mockup", Compare.WhyLine(fake)
    == "More Strength and Crit. A little less Agility.", Compare.WhyLine(fake))
suite.check("nothing to say, no line", Compare.WhyLine({}) == nil and Compare.WhyLine(nil) == nil)

-- 4.
_G.Enum = { TooltipDataType = { Item = 0 } }
local postCall
_G.TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) postCall = fn end }
ns.Tooltip:OnEnable()
local tip = _G.GameTooltip
local function Hover(link)
    ns.Tooltip.ForgetLines()
    tip._scripts.OnTooltipCleared(tip)
    tip._lines = {}
    postCall(tip, { hyperlink = link })
    return table.concat(tip._lines, "|")
end
local shown = Hover("item:801")
suite.check("the tooltip carries the line under the verdict",
    shown:find("Upgrade, %+%d+%%|.-More Agility%. A little less Stamina%.") ~= nil, shown)
suite.check("not on the piece you wear", not Hover("item:800"):find("More ", 1, true), Hover("item:800"))
suite.check("not on gear about the same", not Hover("item:804"):find("More ", 1, true), Hover("item:804"))
ns.db.whyTooltip = false
suite.check("Off takes it away", not Hover("item:801"):find("More ", 1, true), Hover("item:801"))
ns.db.whyTooltip = nil

ns.SettingsUI:Show()
local stepper = ns.SettingsUI.controls.whyTooltip
suite.check("Settings has its row, on Always", stepper and stepper:GetValue() == 2, stepper and stepper:GetValue())
stepper:SetValue(0)
suite.check("Off there saves it off", ns.db.whyTooltip == false)
stepper:SetValue(2)
suite.check("and Always turns it back on", ns.db.whyTooltip == true)

-- 5.
ns.Sources.ITEMS = {}
for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end
local Find, Gear = ns.FindUpgrades, ns.GearWindow
ns.UI:Show()
Gear:ShowTab("find")
Find.sheetHold:SetHeight(590)
local line = { pick = { link = "item:801", itemID = 801, result = result, sources = {} },
    main = nil, group = 1, slotName = "Head", key = "801:1" }
line.main = line.pick
Find.PickedLine = function() return line end
Find:PaintSheet()
suite.check("the sheet shows the line", Find.whyLine:IsShown()
    and Find.whyLine:GetText() == "More Agility. A little less Stamina.", Find.whyLine:GetText())
suite.check("under WHAT CHANGES", Find.whyHeading:IsShown() and Find.whyHeading:GetText() == "WHAT CHANGES")
local rows = Find.whyRows
suite.check("a bar for each stat", rows[1]:IsShown() and rows[2]:IsShown() and not rows[3]:IsShown())
suite.check("named, with its number", rows[1].name:GetText() == "Agility" and rows[1].amount:GetText() == "+10"
    and rows[2].amount:GetText() == "-2", rows[1].amount:GetText())
local gainPoint, lossPoint = rows[1].bar._point, rows[2].bar._point
suite.check("gains grow right of the middle, losses left", gainPoint and gainPoint[1] == "LEFT"
    and gainPoint[3] == "CENTER" and lossPoint and lossPoint[1] == "RIGHT" and lossPoint[3] == "CENTER")
suite.check("the biggest change is the longest bar", rows[1].bar:GetWidth() > rows[2].bar:GetWidth(),
    rows[1].bar:GetWidth() .. " " .. rows[2].bar:GetWidth())
suite.check("and the worth line under them", Find.whyWorth:IsShown()
    and Find.whyWorth:GetText():find("Most of the gain is Agility.", 1, true) == 1, Find.whyWorth:GetText())

line.pick.result = { verdict = "upgrade", empty = true }
Find:PaintSheet()
suite.check("nothing to tell, nothing shown", not Find.whyLine:IsShown() and not Find.whyHeading:IsShown()
    and not rows[1]:IsShown())

suite.done()
