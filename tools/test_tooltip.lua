-- The verdict line on item tooltips: which hook puts it there, that it goes
-- on once, and only on the tooltips it belongs on.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("tooltip")

local ITEMS = {
    ["item:1"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = { ITEM_MOD_AGILITY_SHORT = 10 } },
    ["item:2"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = { ITEM_MOD_AGILITY_SHORT = 15 } },
}

local postCall
local function LoadWithProcessor()
    local ns = env.Load()
    _G.UnitClass = function() return "HUNTER", "HUNTER" end
    env.InstallItems(ITEMS, { [5] = "item:1" })
    _G.Enum = { TooltipDataType = { Item = 0 } }
    _G.TooltipDataProcessor = {
        AddTooltipPostCall = function(_, fn) postCall = fn end,
    }
    ns.Tooltip:OnEnable()
    return ns
end

local ns = LoadWithProcessor()
suite.check("the data processor is hooked", ns.Tooltip.installed.TooltipDataProcessor)
suite.check("and the script hook alongside", ns.Tooltip.installed.OnTooltipSetItem)

local tip = _G.GameTooltip
postCall(tip, { id = 2, hyperlink = "item:2" })
suite.check("the line goes on", tip._lines[1] == "|cff4fd18bUpgrade for Beast Mastery: +50%|r", tip._lines[1])
suite.check("and is counted", ns.Tooltip.fired.TooltipDataProcessor == 1)

postCall(tip, { id = 2, hyperlink = "item:2" })
suite.check("but only once", #tip._lines == 1, #tip._lines)

tip._scripts.OnTooltipCleared(tip)
tip._lines = {}
postCall(tip, { id = 2, hyperlink = "item:2" })
suite.check("and again once the tooltip is cleared", #tip._lines == 1, #tip._lines)

tip._lines = {}
postCall(tip, { id = 2 })
suite.check("a bare id is enough", #tip._lines == 1, #tip._lines)

tip._lines = {}
postCall(tip, { id = 1, hyperlink = "item:1" })
suite.check("the worn item gets no verdict, only its best enchant", #tip._lines == 1
    and tip._lines[1]:find("Best enchant: ", 1, true) ~= nil, tip._lines[1])

-- With the enchant line turned off, the worn item gets nothing.
ns.db.enchantTooltip = false
ns.Tooltip.ForgetLines()
tip._scripts.OnTooltipCleared(tip)
tip._lines = {}
postCall(tip, { id = 1, hyperlink = "item:1" })
suite.check("the worn item gets no line", #tip._lines == 0, #tip._lines)
ns.db.enchantTooltip = nil
ns.Tooltip.ForgetLines()

local shopping = env.Stub({ _lines = {}, AddLine = function(self, t) self._lines[#self._lines + 1] = t end })
postCall(shopping, { id = 2, hyperlink = "item:2" })
suite.check("the comparison tooltips are left alone", #shopping._lines == 0)

_G.ItemRefTooltip._lines = {}
postCall(_G.ItemRefTooltip, { id = 2, hyperlink = "item:2" })
suite.check("a chat link's tooltip gets it", #_G.ItemRefTooltip._lines == 1)

-- Hovering a bag slot: the game draws the tooltip again several times a
-- second, and the item is judged once a second at most, not on every draw.
ns = LoadWithProcessor()
tip = _G.GameTooltip
local clock = 100
_G.GetTime = function() return clock end
local realJudge, judges = ns.Compare.Judge, 0
ns.Compare.Judge = function(...) judges = judges + 1 return realJudge(...) end
local function Redraw()
    tip._scripts.OnTooltipCleared(tip)
    tip._lines = {}
    postCall(tip, { id = 2, hyperlink = "item:2" })
end
for _ = 1, 5 do Redraw() clock = clock + 0.15 end
suite.check("five redraws while hovering judge the item once", judges == 1, judges)
suite.check("and each still carries the line", #tip._lines == 1, #tip._lines)
clock = clock + 1
Redraw()
suite.check("a second later it is judged again", judges == 2, judges)

ns.eventFrame:GetScript("OnEvent")(ns.eventFrame, "PLAYER_LEVEL_UP", 20)
Redraw()
suite.check("a level up judges it afresh at once", judges == 3, judges)
tip._lines = {}
tip._scripts.OnTooltipCleared(tip)
postCall(tip, { id = 1, hyperlink = "item:1" })
suite.check("another item is judged for itself", judges == 4, judges)
ns.Weights:Changed()
judges = 0
postCall(tip, { id = 1, hyperlink = "item:1" })
tip._scripts.OnTooltipCleared(tip)
postCall(tip, { id = 1, hyperlink = "item:1" })
suite.check("and new stat weights judge it afresh", judges == 1, judges)
ns.Compare.Judge = realJudge
_G.GetTime = nil

-- The older script hook does the same job where the processor is missing.
ns = env.Load()
_G.UnitClass = function() return "HUNTER", "HUNTER" end
env.InstallItems(ITEMS, { [5] = "item:1" })
ns.Tooltip:OnEnable()
suite.check("no processor on this client", not ns.Tooltip.installed.TooltipDataProcessor)
tip = _G.GameTooltip
tip.GetItem = function() return "Item", "item:2" end
tip._scripts.OnTooltipSetItem(tip)
suite.check("OnTooltipSetItem adds it from GetItem", #tip._lines == 1, #tip._lines)

-- Switched off.
tip._scripts.OnTooltipCleared(tip)
tip._lines = {}
ns.db.tooltipLine = false
tip._scripts.OnTooltipSetItem(tip)
suite.check("the setting switches it off", #tip._lines == 0, #tip._lines)
ns.db.tooltipLine = true

-- A link that raises when touched is no item, and no error.
tip.GetItem = function() error("secret value") end
local ok = pcall(tip._scripts.OnTooltipSetItem, tip)
suite.check("a secret link does not raise", ok)
suite.check("and adds nothing", #tip._lines == 0, #tip._lines)

-- Boss drops: which boss drops it, and where.
local S = ns.Sources
S.ITEMS[7001] = { d = { 9001, 12, 9002, 30 } }
S.BOSSES[9001] = { "Lord Cobrahn", "test_wc", 20 }
S.BOSSES[9002] = { "Mutanus", "test_wc", 22 }
S.DUNGEONS.test_wc = S.DUNGEONS.test_wc or { "Wailing Caverns", 17, 24, "The Barrens" }
suite.check("the boss most likely to drop it is named", ns.Tooltip.DropLine(7001) == "Drops from Mutanus in Wailing Caverns",
    ns.Tooltip.DropLine(7001))
S.FOREVER = S.FOREVER or {}
S.FOREVER[7001] = { { "Lady Anacondra", "test_wc", 5 } }
suite.check("a drop seen on Forever wins", ns.Tooltip.DropLine(7001) == "Drops from Lady Anacondra in Wailing Caverns",
    ns.Tooltip.DropLine(7001))
suite.check("nothing for an item no boss drops", ns.Tooltip.DropLine(7002) == nil)
local function DropLines(link)
    local count = 0
    for _, line in ipairs(ns.Tooltip:MoreLines(link)) do
        if line.key == "drops" then count = count + 1 end
    end
    return count
end
suite.check("the line goes on the tooltip", DropLines("item:7001") == 1, DropLines("item:7001"))
ns.db.dropsTooltip = false
suite.check("and the setting takes it off", DropLines("item:7001") == 0)
ns.db.dropsTooltip = nil

suite.done()
