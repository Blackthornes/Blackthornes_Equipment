-- Blackthornes Equipment -- UI/Tooltip.lua
-- One line on a piece of gear's tooltip: an upgrade or not, for the spec the
-- character is judged as, and by how much. Under it, for a weapon the class
-- can learn but the character has not, where its weapon master is.
--
-- Hooked the way Tradeskills' UI/ItemTooltip.lua is. Its measurement on
-- Forever (docs/FOREVER_API_FINDINGS.md there) is that retail's
-- TooltipDataProcessor is what fires; the older OnTooltipSetItem script is
-- installed too, in case, and a guard stops the line going on twice.
--
-- Blizzard's tooltips are appended to, never replaced, and only the game's
-- main tooltip and the one a chat link opens are touched. The comparison
-- tooltips beside them show what is worn, which needs no verdict.

local _, ns = ...

local Tooltip = ns.NewModule("Tooltip")

local Compare = ns.Compare
local Items = ns.Items
local WeaponSkills = ns.WeaponSkills

local TOOLTIP_NAMES = { "GameTooltip", "ItemRefTooltip" }

local function Field(object, key)
    if type(object) ~= "table" then return nil end
    local ok, value = pcall(function() return object[key] end)
    if ok then return value end
    return nil
end

function Tooltip:IsEnabled()
    return not (ns.db and ns.db.tooltipLine == false)
end

--- Is this one of the tooltips the line belongs on?
function Tooltip:Wanted(tooltip)
    for _, name in ipairs(TOOLTIP_NAMES) do
        if _G[name] ~= nil and _G[name] == tooltip then return true end
    end
    return false
end

--- The link of the item a tooltip shows, however this client offers it.
function Tooltip:LinkFor(tooltip, data)
    local fromData = Items.PlainLink(Field(data, "hyperlink"))
    if fromData then return fromData end

    local displayed = Field(_G.TooltipUtil, "GetDisplayedItem")
    if type(displayed) == "function" then
        local ok, _, link = pcall(displayed, tooltip)
        link = ok and Items.PlainLink(link)
        if link then return link end
    end

    local getItem = Field(tooltip, "GetItem")
    if type(getItem) == "function" then
        local ok, _, link = pcall(getItem, tooltip)
        link = ok and Items.PlainLink(link)
        if link then return link end
    end

    -- Last, the bare id: good enough for the item's base stats.
    local id = Field(data, "id")
    if type(id) == "number" then
        local ok, text = pcall(function() if id > 0 then return "item:" .. id end end)
        if ok and text then return text end
    end
    return nil
end

--- Is the tooltip showing an item from one of the game's bag buttons? Only
--- a button that says its bag (retail) or is named as a bag slot (classic)
--- counts; the character sheet's buttons never do.
function Tooltip:FromBag(tooltip)
    local getOwner = Field(tooltip, "GetOwner")
    if type(getOwner) ~= "function" then return false end
    local ok, owner = pcall(getOwner, tooltip)
    if not ok or type(owner) ~= "table" then return false end

    local getBag = Field(owner, "GetBagID")
    if type(getBag) == "function" then
        local okBag, bag = pcall(getBag, owner)
        if okBag and type(bag) == "number" then return true end
    end
    local getName = Field(owner, "GetName")
    if type(getName) == "function" then
        local okName, name = pcall(getName, owner)
        if okName and type(name) == "string" then
            local okMatch, found = pcall(string.find, name, "^ContainerFrame%d+Item%d+$")
            return okMatch and found ~= nil
        end
    end
    return false
end

-- Which tooltip already carries the line, for which item and at what length.
-- Cleared when the tooltip is, so the next showing gets it again.
local decorated = setmetatable({}, { __mode = "k" })

function Tooltip.Forget(tooltip)
    decorated[tooltip] = nil
end

local function LineCount(tooltip)
    local numLines = Field(tooltip, "NumLines")
    if type(numLines) ~= "function" then return nil end
    local ok, count = pcall(numLines, tooltip)
    if ok and type(count) == "number" then return count end
    return nil
end

--- Put the line on a tooltip.
-- @return "added", "quiet" (nothing to say), "duplicate" or "noitem"
function Tooltip:Decorate(tooltip, data)
    if not self:IsEnabled() then return "quiet" end
    if not self:Wanted(tooltip) then return "quiet" end
    if self.writing then return "duplicate" end

    local link = self:LinkFor(tooltip, data)
    if not link then return "noitem" end

    local mark = decorated[tooltip]
    if mark and mark.link == link then
        local now = LineCount(tooltip)
        if not now or now >= mark.lines then return "duplicate" end
    end

    local lines = {}
    -- An item shown from a bag slot is a carried copy, so a second copy of a
    -- worn ring is judged against the other ring, as its bag arrow is.
    local judge = self:FromBag(tooltip) and Compare.JudgeCarried or Compare.Judge
    local text, color = Compare:Describe(judge(Compare, link))
    if text then lines[#lines + 1] = { text, color } end
    local okTrainer, trainer, trainerColor = pcall(WeaponSkills.Describe, WeaponSkills, link)
    if okTrainer and trainer then lines[#lines + 1] = { trainer, trainerColor, true } end
    if #lines == 0 then return "quiet" end

    local addLine = Field(tooltip, "AddLine")
    if type(addLine) ~= "function" then return "noitem" end

    self.writing = true
    for _, line in ipairs(lines) do
        -- The trainer line wraps, so a list of cities folds onto a second
        -- line rather than stretching the tooltip.
        pcall(addLine, tooltip, ("|c%s%s|r"):format(ns.COLORS[line[2]] or ns.COLORS.text, line[1]),
            nil, nil, nil, line[3])
    end

    -- Adding a line needs the tooltip resized, which Show does; on a client
    -- where that re-enters the hook, `writing` is what stops it.
    local show = Field(tooltip, "Show")
    if type(show) == "function" then pcall(show, tooltip) end
    self.writing = false

    decorated[tooltip] = { link = link, lines = LineCount(tooltip) or 0 }
    return "added"
end

--- Every hook comes through here, so one bad item costs its line and never a
--- Lua error on hover.
function Tooltip:OnTooltip(tooltip, data, source)
    local ok, outcome = pcall(self.Decorate, self, tooltip, data)
    if not ok then
        self.writing = false
        return "noitem"
    end
    if outcome == "added" then
        self.fired[source] = (self.fired[source] or 0) + 1
    end
    return outcome
end

function Tooltip:InstallDataProcessor()
    local processor = _G.TooltipDataProcessor
    local dataType = Field(Field(_G.Enum, "TooltipDataType"), "Item")
    local add = Field(processor, "AddTooltipPostCall")
    if type(add) ~= "function" or dataType == nil then return false end

    return (pcall(add, dataType, function(tooltip, data)
        Tooltip:OnTooltip(tooltip, data, "TooltipDataProcessor")
    end))
end

function Tooltip:InstallScriptHooks()
    local installed = false
    for _, name in ipairs(TOOLTIP_NAMES) do
        local tooltip = _G[name]
        local hook = Field(tooltip, "HookScript")
        if type(hook) == "function" then
            if pcall(hook, tooltip, "OnTooltipSetItem", function(shown)
                Tooltip:OnTooltip(shown, nil, "OnTooltipSetItem")
            end) then
                installed = true
            end
            pcall(hook, tooltip, "OnTooltipCleared", function(shown)
                Tooltip.Forget(shown)
            end)
        end
    end
    return installed
end

function Tooltip:OnEnable()
    self.fired = {}
    self.installed = {
        TooltipDataProcessor = self:InstallDataProcessor(),
        OnTooltipSetItem = self:InstallScriptHooks(),
    }
end
