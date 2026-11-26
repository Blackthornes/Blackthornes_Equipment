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
    -- Why It's Better has its own suite (tools/test_whybetter.lua); the
    -- line counts here are the verdict's.
    ns.db.whyTooltip = false
    return ns
end

local ns = LoadWithProcessor()
-- The shared tooltip block (UI/TooltipBlock.lua) puts the lines on, under a
-- blank row with the gold line on it; Equipment hands it its lines.
suite.check("the data processor is hooked", ns.Tooltip.installed["tooltip block"]
    and ns.TooltipBlock.shared.installed == "post-call")

local tip = _G.GameTooltip
postCall(tip, { id = 2, hyperlink = "item:2" })
suite.check("the block starts with a blank row", tip._lines[1] == " ", tip._lines[1])
suite.check("the line goes on", tip._lines[2] == "For Beast Mastery: Upgrade, +50%", tip._lines[2])

postCall(tip, { id = 2, hyperlink = "item:2" })
suite.check("but only once", #tip._lines == 2, #tip._lines)

tip._scripts.OnTooltipCleared(tip)
tip._lines = {}
postCall(tip, { id = 2, hyperlink = "item:2" })
suite.check("and again once the tooltip is cleared", #tip._lines == 2, #tip._lines)

tip._lines = {}
postCall(tip, { id = 2 })
suite.check("a bare id is enough", #tip._lines == 2, #tip._lines)

tip._lines = {}
postCall(tip, { id = 1, hyperlink = "item:1" })
suite.check("the worn item gets no verdict, only its best enchant", #tip._lines == 2
    and tip._lines[2]:find("Best Enchant: ", 1, true) ~= nil, tip._lines[2])

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
suite.check("a chat link's tooltip gets it", #_G.ItemRefTooltip._lines == 2)

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
suite.check("and each still carries the line", #tip._lines == 2, #tip._lines)
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

-- Forever says GET_ITEM_INFO_RECEIVED each time a tooltip reads gear it
-- knows. That threw the kept lines away on every draw, so hovering judged
-- the item over and over. Only the item shown arriving does that now.
local function Fire(...) ns.eventFrame:GetScript("OnEvent")(ns.eventFrame, "GET_ITEM_INFO_RECEIVED", ...) end
judges = 0
for _ = 1, 5 do
    Fire(2, true)
    tip._scripts.OnTooltipCleared(tip)
    tip._lines = {}
    postCall(tip, { id = 1, hyperlink = "item:1" })
    clock = clock + 0.15
end
suite.check("another item arriving keeps the lines while hovering", judges == 0, judges)
Fire(1, true)
tip._scripts.OnTooltipCleared(tip)
postCall(tip, { id = 1, hyperlink = "item:1" })
suite.check("the item shown arriving judges it afresh", judges == 1, judges)
ns.Compare.Judge = realJudge
_G.GetTime = nil

-- The older script hook does the same job where the processor is missing.
ns = env.Load()
_G.UnitClass = function() return "HUNTER", "HUNTER" end
env.InstallItems(ITEMS, { [5] = "item:1" })
ns.Tooltip:OnEnable()
ns.db.whyTooltip = false
suite.check("no processor on this client", ns.TooltipBlock.shared.installed == "scripts")
tip = _G.GameTooltip
tip.GetItem = function() return "Item", "item:2" end
tip._scripts.OnTooltipSetItem(tip)
suite.check("OnTooltipSetItem adds it from GetItem", #tip._lines == 2, #tip._lines)

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

-- The block's names and answers.
local pair = { ns.Tooltip.VerdictPair({ verdict = "upgrade", specName = "Fury", percent = 12 }) }
suite.check("an upgrade names the spec", pair[1] == "For Fury:" and pair[2] == "Upgrade, +12%", pair[2])
pair = { ns.Tooltip.VerdictPair({ verdict = "upgrade", specName = "Fury", percent = 12, level = 24 }) }
suite.check("a level wait is said", pair[2] == "Upgrade at level 24, +12%", pair[2])
pair = { ns.Tooltip.VerdictPair({ verdict = "downgrade", specName = "Fury", percent = -4 }) }
suite.check("worse", pair[2] == "Worse, -4%", pair[2])
pair = { ns.Tooltip.VerdictPair({ verdict = "same", specName = "Fury" }) }
suite.check("about the same", pair[2] == "About the same", pair[2])
pair = { ns.Tooltip.VerdictPair({ verdict = "cantuse", specName = "Fury", className = "WARRIOR" }) }
suite.check("can't use", pair[2] == "Can't use this", pair[2])
local drops
for _, line in ipairs(ns.Tooltip:MoreLines("item:7001")) do if line.key == "drops" then drops = line end end
suite.check("the drop line's name", drops and drops.label == "Drops From:", drops and drops.label)
suite.check("and its answer", drops and drops.answer == "Lady Anacondra, Wailing Caverns", drops and drops.answer)
_G.GameTooltip._lines = {}
local source = ns.Tooltip:BlockLines(_G.GameTooltip, { id = 7001, hyperlink = "item:7001" }, "source")
suite.check("the drop goes in the source part", source and source[1] and source[1][1] == "Drops From:")

suite.done()
