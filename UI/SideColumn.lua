local ADDON_NAME, ns = ...

--[[
SideColumn: where the side panels start.

The Upgrade Quest panel and the Upgrade Tracker each used to start on the
right edge, about where the game's quest list is, and close enough to each
other that they piled up. Panels the player has never dragged now stand in
one column left of the game's quest list (on the right edge when that list
is out of sight), each under the one above, and close up when one hides.

A panel the player dragged keeps its saved spot and leaves the column. No
saved key changes: a panel is in the column while its own spot is unsaved
(`questX`, `trackerX`), and Window Spots' Set Default clears those, which
brings it back.

A member is { name, frame(), placed() }. Order is top to bottom.
]]

local SideColumn = ns.NewModule("SideColumn")
ns.SideColumn = SideColumn

SideColumn.GAP = 8            -- between two panels in the column
SideColumn.BESIDE = 12        -- between the column and the game's quest list
SideColumn.EDGE = 40          -- from the screen's right edge, with no quest list
SideColumn.TOP = -220         -- the column's top, when the quest list can't say
SideColumn.LIST_WIDTH = 260   -- the quest list's width, when it can't say

SideColumn.members = {
    {
        name = "quest",
        frame = function() return ns.QuestPanel and ns.QuestPanel.frame end,
        placed = function() return ns.db ~= nil and ns.db.questX ~= nil end,
    },
    {
        name = "tracker",
        frame = function() return ns.TrackerPanel and ns.TrackerPanel.frame end,
        placed = function() return ns.db ~= nil and ns.db.trackerX ~= nil end,
    },
}

local function Number(value)
    return type(value) == "number" and value or nil
end

--- The game's quest list, when it is on screen and not put out of sight by
--- the quest panel's "Hide Game's Tracker:".
function SideColumn.QuestList()
    local log = ns.QuestLogUI
    for _, name in ipairs((log and log.TRACKERS) or { "ObjectiveTrackerFrame", "QuestWatchFrame" }) do
        local frame = rawget(_G, name)
        if type(frame) == "table" then
            local ok, shown = pcall(function() return frame:IsVisible() end)
            local hidden = log and log.TrackerHidden and log:TrackerHidden(name)
            if ok and shown and not hidden then return frame end
        end
    end
end

--- The column's top right corner, as offsets from the screen's top right.
function SideColumn.Corner()
    local list = SideColumn.QuestList()
    if not list then return -SideColumn.EDGE, SideColumn.TOP end
    local ok, left, top, right = pcall(function() return list:GetLeft(), list:GetTop(), list:GetRight() end)
    local okScreen, screenRight, screenTop = pcall(function() return UIParent:GetRight(), UIParent:GetTop() end)
    left, top, right = ok and Number(left), ok and Number(top), ok and Number(right)
    screenRight, screenTop = okScreen and Number(screenRight), okScreen and Number(screenTop)
    if left and top and screenRight and screenTop then
        -- The list's own scale is not the screen's; its corners are in its units.
        local okScale, scale = pcall(function() return list:GetEffectiveScale() / UIParent:GetEffectiveScale() end)
        scale = okScale and Number(scale) or 1
        return math.min(0, left * scale - screenRight - SideColumn.BESIDE), math.min(0, top * scale - screenTop)
    end
    return -(SideColumn.EDGE + SideColumn.LIST_WIDTH + SideColumn.BESIDE), SideColumn.TOP
end

local function Shown(frame)
    local ok, shown = pcall(function() return frame:IsShown() end)
    return ok and shown == true
end

local function Scale(frame)
    local ok, scale = pcall(function() return frame:GetScale() end)
    scale = ok and Number(scale)
    return (scale and scale > 0) and scale or 1
end

--- Put every panel that was never dragged in its place in the column.
function SideColumn:Layout()
    local x, y = SideColumn.Corner()
    local above
    for _, member in ipairs(self.members) do
        local frame = member.frame()
        if frame and not member.placed() then
            local scale = Scale(frame)
            frame:ClearAllPoints()
            if above then
                frame:SetPoint("TOPRIGHT", above, "BOTTOMRIGHT", 0, -SideColumn.GAP / scale)
            else
                frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", x / scale, y / scale)
            end
            if Shown(frame) then above = frame end
        end
    end
end

--- Is this panel in the column (never dragged)?
function SideColumn:Holds(name)
    for _, member in ipairs(self.members) do
        if member.name == name then return not member.placed() end
    end
    return false
end

--- Close up or make room when a panel in the column shows or hides.
local watched = setmetatable({}, { __mode = "k" })

function SideColumn:Watch(frame)
    if not frame or watched[frame] then return end
    watched[frame] = true
    local function Again() SideColumn:Layout() end
    frame:HookScript("OnShow", Again)
    frame:HookScript("OnHide", Again)
end
