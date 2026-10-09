-- Blackthornes Equipment -- UI/FinderWindow.lua
-- The "Where to get upgrades" window: for each slot, the best gear a vendor
-- sells, a quest gives, a dungeon drops or a crafter makes that beats what
-- is worn, and where to go for it. The stepper beside the filters looks a
-- few levels ahead; "This zone only" keeps the list to the zone the
-- character is in. Click a row to follow it as the upgrade quest
-- (Logic/UpgradeQuest.lua), right-click to track it (Logic/Tracking.lua),
-- Alt-click to pin its spot on the map (Logic/Waypoints.lua).
--
-- Opened from the gear window's "Find upgrades" button and /beq find. Built
-- like the gear window (same header, palette and rows). Logic/Finder.lua does
-- the looking; this only lays it out, and scans again as the server answers
-- about items the client had not seen yet.

local _, ns = ...

local FinderUI = ns.NewModule("FinderUI")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Motion = ns.Motion
local Finder = ns.Finder
local Weights = ns.Weights

local PADDING = 18
local HEADER = 36

-- The metal rim (UI/Titanforged.lua) reaches this far in from the edge;
-- the header sits inside it.
local RIM = 6
local FILTERS = 30
-- The quest filters' row, under the source buttons.
local QUEST_ROW = 28
local ROW_HEIGHT = 50
local VISIBLE = 9
local FOOTER = 48
local WIDTH = 780

-- The line under each item wraps onto a second line rather than being cut.
-- Wrapping breaks at spaces, so a little of each line goes unused.
local SOURCE_LINES = 2
local WRAP_SLACK = 60

local SLOT_WIDTH = 84
local GAIN_WIDTH = 120
local ICON = 28
local TEXT_X = SLOT_WIDTH + ICON + 10
local SCROLL_WIDTH = 4

-- Some gear is sold by a dozen vendors; the tooltip lists this many.
local TOOLTIP_SOURCES = 8

local HEIGHT = HEADER + 10 + FILTERS + QUEST_ROW + 8 + VISIBLE * ROW_HEIGHT + FOOTER

-- The tag in front of a source, in its own colour.
local KIND_COLORS = { vendor = "accent", quest = "quest", dungeon = "dungeon", craft = "craft" }

local FILTER_BUTTONS = {
    { nil, "Everything" }, { "vendor", "Vendors" }, { "quest", "Quests" },
    { "dungeon", "Dungeons and raids" }, { "craft", "Crafted" },
}

-- How many levels ahead the stepper can look.
local MOST_AHEAD = 10

--------------------------------------------------------------------------------
-- Text that fits
--------------------------------------------------------------------------------

--- `text` cut down with "..." until it fits in `width` pixels at `size`.
-- Measured, never guessed: the game's font runs wider than it looks.
function FinderUI.Fit(size, text, width)
    if Theme.TextWidth(size, text) <= width then return text end

    -- Colour codes take no room but must not be cut in half, so the cut is
    -- made on the plain text.
    local plain = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local low, high = 0, #plain
    while low < high do
        local mid = math.ceil((low + high) / 2)
        if Theme.TextWidth(size, plain:sub(1, mid) .. "...") <= width then
            low = mid
        else
            high = mid - 1
        end
    end
    return plain:sub(1, low):gsub("%s+$", "") .. "..."
end

local function Colored(key, text)
    local r, g, b = Theme.Unpack(key)
    return ("|cff%02x%02x%02x%s|r"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
        math.floor(b * 255 + 0.5), text)
end

--- A source as one line: the coloured kind, then where.
function FinderUI.SourceLine(source)
    local line = Colored(KIND_COLORS[source.kind] or "text", Finder.Label(source))
        .. "  " .. Finder:Describe(source)
    -- Seen on Forever, the way Farmer marks what it has confirmed.
    if source.forever then line = line .. "  " .. Colored("good", "[Forever]") end
    return line
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

local function ShowTooltip(row)
    local pick = row.pick
    if not pick then return end

    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    pcall(GameTooltip.SetHyperlink, GameTooltip, pick.link)
    GameTooltip:AddLine(" ")
    if pick.needs then
        GameTooltip:AddLine(Finder.NeedsText(pick.needs), Theme.Unpack("warn"))
    end
    if pick.at then
        GameTooltip:AddLine(("You can wear it from level %d"):format(pick.at), Theme.Unpack("warn"))
    end
    local roll = Finder.RollText(pick)
    if roll then
        local r, g, b = Theme.Unpack("good")
        GameTooltip:AddLine(roll, r, g, b, true)
    end
    GameTooltip:AddLine("Where to get it", Theme.Unpack("accent"))
    for index, source in ipairs(pick.sources) do
        if index > TOOLTIP_SOURCES then
            GameTooltip:AddLine(("and %d more"):format(#pick.sources - TOOLTIP_SOURCES),
                Theme.Unpack("muted"))
            break
        end
        GameTooltip:AddLine(FinderUI.SourceLine(source), Theme.Unpack("text"))
        if source.after then
            GameTooltip:AddLine("    after " .. source.after, Theme.Unpack("muted"))
        end
        if source.kind == "craft" and ns.Crafting then
            -- Light, so it reads on the tooltip's dark background.
            local r, g, b = Theme.Unpack("text")
            GameTooltip:AddLine("    Materials: " .. ns.Crafting:MaterialsText(pick.itemID), r, g, b, true)
        end
    end
    GameTooltip:AddLine(" ")
    local quest = ns.UpgradeQuest
    if quest then
        local _, why = quest.CanFollow(pick)
        -- What a click does, said plainly: players took the green Quest
        -- tag it leaves for a mistake (2026-10-09).
        local r, g, b = Theme.Unpack("text")
        if quest:IsFollowing(pick.itemID) then
            GameTooltip:AddLine("Your upgrade quest: click to show it on the quest panel", Theme.Unpack("good"))
            GameTooltip:AddLine("The green Quest tag marks it. To drop it, click Ignore on the quest panel, "
                .. "or click another upgrade here to follow that one instead.", r, g, b, true)
        elseif why then
            local wr, wg, wb = Theme.Unpack("warn")
            GameTooltip:AddLine("Not a quest yet: " .. why, wr, wg, wb, true)
        else
            GameTooltip:AddLine("Click to follow it on the quest panel", Theme.Unpack("good"))
            GameTooltip:AddLine("It becomes your upgrade quest, with steps to get it, and gets a green Quest tag "
                .. "here. The quest it replaces on that tab can come back later.", r, g, b, true)
        end
    end
    local tracked = ns.Tracking and ns.Tracking:IsTracked(pick.itemID)
    GameTooltip:AddLine(tracked and "Right-click to stop tracking it" or "Right-click to track it",
        Theme.Unpack("muted"))
    if FinderUI.Place(pick) then
        GameTooltip:AddLine("Alt-click to pin it on your map", Theme.Unpack("muted"))
    end
    GameTooltip:Show()
end

function FinderUI:BuildRow(index)
    local inner = WIDTH - PADDING * 2 - SCROLL_WIDTH - 6
    local row = CreateFrame("Button", nil, self.frame)
    -- Above the well, whatever order the client draws siblings in.
    row:SetFrameLevel(self.well:GetFrameLevel() + 1)
    row:SetSize(inner, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", PADDING, self.listTop - (index - 1) * ROW_HEIGHT)
    row.background = Theme.Fill(row, index % 2 == 0 and "row" or "rowAlt")
    row.restKey = index % 2 == 0 and "row" or "rowAlt"

    -- A green edge that lights under the mouse.
    local edge = row:CreateTexture(nil, "ARTWORK")
    edge:SetPoint("TOPLEFT")
    edge:SetPoint("BOTTOMLEFT")
    edge:SetWidth(2)
    edge:SetColorTexture(Theme.Unpack("good", 0))
    row.edge = edge

    -- Under the mouse the row lights from the left too: a gold wash fading
    -- across it (Titanforged).
    local wash = row:CreateTexture(nil, "BACKGROUND", nil, 3)
    wash:SetAllPoints(row)
    Theme.SetGradientAlpha(wash, "HORIZONTAL", "accent", 0.20, 0)
    wash:SetAlpha(0)
    row.hoverWash = wash

    local slot = Theme.CreateLabel(row, "small", "muted")
    slot:SetPoint("TOPLEFT", 8, -7)
    slot:SetWidth(SLOT_WIDTH - 10)
    row.slot = slot

    local icon = Theme.CreateItemIcon(row, ICON)
    icon:SetPoint("LEFT", SLOT_WIDTH, 0)
    row.icon = icon

    local item = Theme.CreateLabel(row, "normal", "text")
    item:SetPoint("TOPLEFT", TEXT_X, -6)
    item:SetWidth(inner - TEXT_X - GAIN_WIDTH - 8)
    row.item = item

    local gain = Theme.CreateLabel(row, "normal", "good", "RIGHT")
    gain:SetPoint("TOPRIGHT", -8, -6)
    gain:SetWidth(GAIN_WIDTH)
    row.gain = gain

    local source = Theme.CreateLabel(row, "tiny", "muted")
    source:SetPoint("TOPLEFT", TEXT_X, -23)
    source:SetWidth(inner - TEXT_X - 8)
    source:SetWordWrap(true)
    pcall(source.SetMaxLines, source, SOURCE_LINES)
    row.source = source
    row.sourceWidth = inner - TEXT_X - 8

    local function Light(p)
        row.background:SetColorTexture(Motion.Mix(row.restKey, "rowHover", p))
        row.edge:SetColorTexture(Theme.Unpack(rawget(row, "edgeKey") or "good", p))
        wash:SetAlpha(p)
    end

    row:SetScript("OnEnter", function(self)
        self.over = true
        Motion:Blend(self, "hover", 1, 0.12, Light)
        ShowTooltip(self)
    end)
    row:SetScript("OnLeave", function(self)
        self.over = false
        Motion:Blend(self, "hover", 0, 0.18, Light)
        GameTooltip:Hide()
    end)
    row:SetScript("OnClick", function(self, button)
        local pick = self.pick
        if not pick then return end
        if button == "RightButton" then
            if ns.Tracking then ns.Tracking:Toggle(pick) end
            if rawget(self, "over") == true then ShowTooltip(self) end
            return
        end
        local okAlt, alt = pcall(function() return IsAltKeyDown() == true end)
        if okAlt and alt then
            local place = FinderUI.Place(pick)
            if place and ns.Waypoints then ns.Waypoints:Show(place, place.name) end
            return
        end
        if type(IsModifiedClick) == "function" and type(ChatEdit_InsertLink) == "function" then
            local ok, chatLink = pcall(IsModifiedClick, "CHATLINK")
            if ok and chatLink then
                pcall(ChatEdit_InsertLink, pick.link)
                return
            end
        end
        -- A plain click follows it on the upgrade quest panel (asked 2026-10-06).
        FinderUI:Follow(pick)
        if rawget(self, "over") == true then ShowTooltip(self) end
    end)
    if row.RegisterForClicks then row:RegisterForClicks("LeftButtonUp", "RightButtonUp") end

    row:Hide()
    return row
end

function FinderUI:Build()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "BlackthornesEquipmentFinder", UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    Theme.Fill(frame, "window")

    -- The house frame, as the gear window wears it (UI/Titanforged.lua).
    if ns.Titanforged then
        local trim = ns.Titanforged:Dress(frame, {
            title = "Where to get upgrades",
            portrait = true,
            close = function() FinderUI:Hide() end,
        })

        -- Kept on the screen whole: the portrait and plate reach out past
        -- the top left, the close gem past the top right.
        local left, right, top, bottom = ns.Titanforged.Reach(trim)
        if frame.SetClampRectInsets then frame:SetClampRectInsets(-left, right, top, -bottom) end
    else
        Theme.Border(frame, "borderLit")
    end
    Theme.Halo(frame, 12, 0.14)

    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if ns.db then ns.db.finderMoved = true end
        FinderUI:SavePosition()
    end)
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta) FinderUI:ScrollBy(-delta) end)
    frame:SetScript("OnHide", function() FinderUI.pending = false end)

    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "BlackthornesEquipmentFinder")
    end

    self.frame = frame
    self:BuildHeader()
    self:BuildFilters()

    self.listTop = -(HEADER + 10 + FILTERS + QUEST_ROW + 8)

    -- The list sits sunk into the window, as the game's inset lists do.
    local well = Theme.CreatePanel(frame, "panel", "border")
    well:SetPoint("TOPLEFT", PADDING - 3, self.listTop + 3)
    well:SetPoint("TOPRIGHT", -(PADDING - 3), self.listTop + 3)
    well:SetHeight(VISIBLE * ROW_HEIGHT + 6)
    Theme.Recess(well)
    self.well = well

    self.rows = {}
    for index = 1, VISIBLE do self.rows[index] = self:BuildRow(index) end

    -- A thin track down the right of the list, and a thumb that shows where
    -- in it the view is. On the well, or the well would hide them.
    local track = well:CreateTexture(nil, "ARTWORK")
    track:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING, self.listTop)
    track:SetSize(SCROLL_WIDTH, VISIBLE * ROW_HEIGHT)
    track:SetColorTexture(Theme.Unpack("rowAlt"))
    self.track = track

    local thumb = well:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(SCROLL_WIDTH)
    thumb:SetColorTexture(Theme.Unpack("accent", 0.8))
    self.thumb = thumb

    local empty = Theme.CreateLabel(well, "normal", "muted", "CENTER")
    empty:SetPoint("TOP", frame, "TOP", 0, self.listTop - 60)
    empty:SetWidth(WIDTH - PADDING * 4)
    empty:SetWordWrap(true)
    self.empty = empty

    local footer = Theme.CreateLabel(frame, "small", "text")
    footer:SetPoint("BOTTOMLEFT", PADDING, 26)
    footer:SetWidth(WIDTH - PADDING * 2)
    self.footer = footer

    local hint = Theme.CreateLabel(frame, "tiny", "dim")
    hint:SetPoint("BOTTOMLEFT", PADDING, 10)
    hint:SetWidth(WIDTH - PADDING * 2)
    hint:SetText("Places and prices are from Classic. Click to follow as a quest, right-click to track, Alt-click for the map.")
    self.hint = hint

    frame:Hide()
    return frame
end

function FinderUI:BuildHeader()
    local frame = self.frame

    -- The window's name is on the plate and the close gem on the top right
    -- corner (UI/Titanforged.lua), so the header holds the spec line, clear
    -- of the portrait on the left and a little low, under the plate.
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", RIM, 0)
    header:SetPoint("TOPRIGHT", -RIM, 0)
    header:SetHeight(HEADER)

    local spec = Theme.CreateLabel(header, "small", "muted")
    spec:SetPoint("LEFT", 58 - RIM, -4)
    spec:SetPoint("RIGHT", -(PADDING + 16 - RIM), -4)
    self.specLabel = spec

    -- A gold rule under it, bright at the left and fading out to the right.
    local rule = header:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    rule:SetHeight(1)
    Theme.SetGradientAlpha(rule, "HORIZONTAL", "accent", 0.6, 0.05)
end

function FinderUI:BuildFilters()
    self.filters = {}
    local previous
    for _, entry in ipairs(FILTER_BUTTONS) do
        local kind = entry[1]
        local button = Widgets.CreateButton(self.frame, entry[2], function()
            FinderUI:SetFilter(kind)
        end, { width = 80, height = 22 })
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 6, 0)
        else
            -- A few pixels lower than the header's foot, clear of the
            -- round portrait above it.
            button:SetPoint("TOPLEFT", PADDING, -(HEADER + 13))
        end

        -- A gold bar under the one that is showing.
        local mark = button:CreateTexture(nil, "OVERLAY")
        mark:SetPoint("BOTTOMLEFT", 1, 1)
        mark:SetPoint("BOTTOMRIGHT", -1, 1)
        mark:SetHeight(2)
        mark:SetColorTexture(Theme.Unpack("accent"))
        button.mark = mark
        button.kind = kind

        self.filters[#self.filters + 1] = button
        previous = button
    end

    -- Plan ahead: "Now", or a level up to MOST_AHEAD past the character's.
    local ahead = Widgets.CreateStepper(self.frame, {
        min = 0, max = MOST_AHEAD, step = 1, value = self:Ahead(),
        format = function(value) return FinderUI.AheadText(value) end,
        onChange = function(value)
            if ns.db then ns.db.finderAhead = value end
            FinderUI.offset = 0
            FinderUI:Refresh()
        end,
    })
    ahead:SetPoint("TOPRIGHT", -PADDING, -(HEADER + 14))
    self.ahead = ahead

    -- The quest filters, on a row of their own: how far above the
    -- character a quest may be, then the solo tick box. The upgrade quest
    -- follows both.
    local rowY = -(HEADER + 13 + FILTERS + 1)
    local levelLabel = Theme.CreateLabel(self.frame, "small", "muted")
    levelLabel:SetPoint("TOPLEFT", PADDING, rowY - 4)
    levelLabel:SetText("Quest level")
    self.levelLabel = levelLabel

    local questLevels = Widgets.CreateStepper(self.frame, {
        min = 0, max = Finder.QUEST_LEVELS_ANY, step = 1, value = self:QuestLevelsValue(),
        format = function(value) return FinderUI.QuestLevelsText(value) end,
        onChange = function(value) Finder:SetQuestLevelsAbove(value) end,
    })
    questLevels:SetWidth(150)
    questLevels:SetPoint("LEFT", levelLabel, "RIGHT", 10, 0)
    questLevels:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Quest level", Theme.Unpack("accent"))
        GameTooltip:AddLine("How far above your level a quest may be and still be offered. "
            .. "Quests 5 or more levels up show in red in your quest log.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    questLevels:HookScript("OnLeave", function() GameTooltip:Hide() end)
    self.questLevels = questLevels

    -- Hide quests that need a group, a dungeon, a raid or a battleground.
    -- The same switch as in Settings.
    local solo = Widgets.CreateCheckbox(self.frame, "Solo quests only", function(checked)
        Finder:SetSoloOnly(checked)
    end, Finder:SoloOnly())
    solo:SetPoint("LEFT", questLevels, "RIGHT", 24, 0)
    solo:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Solo quests only", Theme.Unpack("accent"))
        GameTooltip:AddLine("Hides quests that need a group, a dungeon, a raid or a battleground, "
            .. "and quests that come after one. Quests to kill an elite count as group quests.",
            1, 1, 1, true)
        GameTooltip:Show()
    end)
    solo:HookScript("OnLeave", function() GameTooltip:Hide() end)
    self.solo = solo

    -- Only gear from the zone the character is in, as the upgrade quest
    -- panel's box of the same name does (each keeps its own setting).
    local zone = Widgets.CreateCheckbox(self.frame, "This zone only", function(checked)
        FinderUI:SetZoneOnly(checked)
    end, self:ZoneOnly())
    zone:SetPoint("LEFT", solo, "RIGHT", 24, 0)
    zone:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("This zone only", Theme.Unpack("accent"))
        GameTooltip:AddLine("Lists only upgrades from the zone you are in: a vendor, a quest giver or a "
            .. "dungeon's entrance here, and gear you can make anywhere. The list changes as you travel. "
            .. "Untick it to look anywhere.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    zone:HookScript("OnLeave", function() GameTooltip:Hide() end)
    self.zone = zone
end

--- Is "This zone only" ticked? Saved account wide as `finderZoneOnly`,
--- off unless ticked.
function FinderUI:ZoneOnly()
    return ns.db ~= nil and ns.db.finderZoneOnly == true
end

function FinderUI:SetZoneOnly(on)
    if not ns.db then return end
    ns.db.finderZoneOnly = on and true or false
    if self.zone then self.zone:SetChecked(ns.db.finderZoneOnly) end
    self.offset = 0
    self:Refresh()
end

--- The zone the list keeps to, or nil for anywhere.
function FinderUI:Here(found)
    if not self:ZoneOnly() then return nil end
    local quest = ns.UpgradeQuest
    return quest and quest.Zone() or (found and found.player and found.player.zone) or nil
end

--- "Solo quests only" changed, here or in Settings.
function FinderUI:OnQuestFilterChanged()
    if self.solo then self.solo:SetChecked(Finder:SoloOnly()) end
    if self.questLevels then self.questLevels:SetValue(self:QuestLevelsValue(), true) end
    self.offset = 0
    self:Refresh()
end

--- The quest level stepper's place: 0 to 10 levels up, or 11 for any.
function FinderUI:QuestLevelsValue()
    return Finder:QuestLevelsAbove() or Finder.QUEST_LEVELS_ANY
end

--- Its words: "Up to my level", "Up to +4" or "Any".
function FinderUI.QuestLevelsText(value)
    if (value or 0) >= Finder.QUEST_LEVELS_ANY then return "Any" end
    if (value or 0) <= 0 then return "Up to my level" end
    return ("Up to +%d"):format(value)
end

--- How many levels ahead the window looks (0 for now).
function FinderUI:Ahead()
    local value = tonumber(ns.db and ns.db.finderAhead) or 0
    return math.max(0, math.min(MOST_AHEAD, math.floor(value)))
end

--- The stepper's words: "Now", or "Level 27".
function FinderUI.AheadText(value)
    if (value or 0) <= 0 then return "Now" end
    local level = ns.Items and ns.Items:PlayerLevel()
    if not level then return ("+%d levels"):format(value) end
    return ("Level %d"):format(math.min(60, level + value))
end

--- Where a pick's first source with an exact spot is, for the map.
function FinderUI.Place(pick)
    for _, source in ipairs(pick and pick.sources or {}) do
        if source.zone and source.x and source.y then return source end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Filling it in
--------------------------------------------------------------------------------

--- The kind showing: "vendor", "quest", "dungeon", "craft", or nil for
--- everything.
function FinderUI:Filter()
    local show = ns.db and ns.db.finderShow
    if show == "vendor" or show == "quest" or show == "dungeon" or show == "craft" then return show end
    return nil
end

function FinderUI:SetFilter(kind)
    if ns.db then ns.db.finderShow = kind or "all" end
    self.offset = 0
    self:Refresh()
end

--- The picks as one list in character-sheet order, keeping only sources of
--- the kind showing (and picks that have one). With "This zone only", only
--- sources in the zone the character is in, looked for among every pick
--- (the best here are seldom the best anywhere), the usual few per slot.
function FinderUI:Lines(found)
    local lines, only = {}, self:Filter()
    local here = self:Here(found)
    local inZone = ns.UpgradeQuest and ns.UpgradeQuest.InZone
    local all = here and inZone and type(found.all) == "table" and found.all or nil
    local most = Finder.PER_SLOT or 3
    local seen = {}
    for _, entry in ipairs(ns.UI.SLOTS) do
        local slot = entry[1]
        local picks = (all or found.slots)[slot]
        if picks and not seen[slot] then
            seen[slot] = true
            local first, kept = true, 0
            for _, pick in ipairs(picks) do
                local sources = {}
                for _, source in ipairs(pick.sources) do
                    if (not only or source.kind == only) and (not all or inZone(source, here)) then
                        sources[#sources + 1] = source
                    end
                end
                if #sources > 0 and kept < most then
                    kept = kept + 1
                    lines[#lines + 1] = {
                        slotName = entry[2], first = first, pick = pick, sources = sources,
                    }
                    first = false
                end
            end
        end
    end
    return lines
end

local function Gain(result)
    if result.empty then return "empty slot" end
    if result.percent then return ("%+d%%"):format(math.floor(result.percent + 0.5)) end
    return "better"
end

function FinderUI:FillRow(row, line)
    if not line then
        row.pick = nil
        row:Hide()
        return
    end

    row.pick = {
        link = line.pick.link, sources = line.sources, itemID = line.pick.itemID,
        needs = line.pick.needs, result = line.pick.result, roll = line.pick.roll, at = line.pick.at,
        gain = line.pick.gain,
    }
    row.slot:SetText(line.first and line.slotName or "")
    Theme.SetItemIcon(row.icon, line.pick.link)
    row.item:SetText(line.pick.link)
    local gain = Gain(line.pick.result)
    if line.pick.at then gain = ("at %d: %s"):format(line.pick.at, gain) end
    row.gain:SetText(gain)
    -- Gear that waits on a reputation, a level or a crafter is shown in
    -- amber, not green.
    row.edgeKey = (line.pick.needs or line.pick.at or line.pick.remote) and "warn" or "good"
    row.gain:SetTextColor(Theme.Unpack(row.edgeKey))

    local text = FinderUI.SourceLine(line.sources[1])
    if ns.Tracking and ns.Tracking:IsTracked(line.pick.itemID) then
        text = Colored("accent", "Tracking") .. "  " .. text
    end
    if ns.UpgradeQuest and ns.UpgradeQuest:IsFollowing(line.pick.itemID) then
        text = Colored("good", "Quest") .. "  " .. text
    end
    if line.pick.needs then
        text = Colored("warn", ("Needs %s with %s"):format(line.pick.needs.standing,
            line.pick.needs.faction)) .. "  " .. text
    end
    local more = #line.sources - 1
    local tail = more > 0 and ("  +%d more"):format(more) or ""
    local room = row.sourceWidth * SOURCE_LINES - WRAP_SLACK - Theme.TextWidth("tiny", tail)
    row.source:SetText(FinderUI.Fit("tiny", text, room) .. Colored("dim", tail))
    row:Show()
end

function FinderUI:ScrollBy(steps)
    local most = math.max(0, #(self.lines or {}) - VISIBLE)
    self.offset = math.max(0, math.min(most, (self.offset or 0) + steps))
    self:Draw()
end

function FinderUI:Draw()
    local lines = self.lines or {}
    local offset = self.offset or 0
    for index, row in ipairs(self.rows) do
        self:FillRow(row, lines[offset + index])
        -- Scrolled under a still mouse: the tooltip follows the new item.
        if rawget(row, "over") == true then
            if rawget(row, "pick") then ShowTooltip(row) else GameTooltip:Hide() end
        end
    end

    -- The thumb only shows when there is more than fits.
    local total = #lines
    if total > VISIBLE then
        local height = VISIBLE * ROW_HEIGHT
        local size = math.max(16, height * VISIBLE / total)
        local top = (height - size) * offset / (total - VISIBLE)
        self.thumb:SetHeight(size)
        self.thumb:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -PADDING, self.listTop - top)
        self.thumb:Show()
        self.track:Show()
    else
        self.thumb:Hide()
        self.track:Hide()
    end
end

local NO_UPGRADES = {
    [false] = "Nothing on offer beats what you wear right now.",
    vendor = "No vendor sells anything better than what you wear.",
    quest = "No quest open to you gives anything better than what you wear.",
    dungeon = "No dungeon or raid open to you drops anything better than what you wear.",
    craft = "No crafted gear beats what you wear.",
}

--- Look again and redraw.
-- @return the scan, or nil when there was nothing to look with
function FinderUI:Refresh()
    if not (self.frame and self.frame:IsShown()) then return nil end

    for _, button in ipairs(self.filters) do
        local on = button.kind == self:Filter()
        button.mark:SetShown(on)
        button:SetLabelColor(on and "accent" or "text")
    end

    local found, why = Finder:Scan(self:Filter(), self:Ahead())
    if not found then
        self.lines = {}
        self:Draw()
        if why == "noweights" then
            self.empty:SetText(("There are no stat weights for %s yet.")
                :format(Weights:PlayerClass() or "this class"))
        else
            self.empty:SetText("Your level and faction aren't known yet. Try again in a moment.")
        end
        self.empty:Show()
        self.footer:SetText("")
        self.specLabel:SetText("")
        return nil
    end

    local spec, _, class = Weights:CurrentSpec()
    local specName = spec and Weights.SPECS[class][spec].name or ""
    local planning = found.reach > found.player.level and (", planning for %d"):format(found.reach) or ""
    self.specLabel:SetText(("%s, level %d%s"):format(specName, found.player.level, planning))
    if self.ahead then self.ahead:SetValue(self:Ahead(), true) end

    self.lines = self:Lines(found)
    local most = math.max(0, #self.lines - VISIBLE)
    self.offset = math.min(self.offset or 0, most)
    self:Draw()

    local shown = #self.lines
    if shown == 0 then
        if found.waiting > 0 then
            self.empty:SetText("Asking the server about the gear on offer...")
        elseif self:Here(found) then
            self.empty:SetText(("Nothing in %s beats what you wear. Untick This zone only to look anywhere.")
                :format(self:Here(found)))
        else
            self.empty:SetText(NO_UPGRADES[self:Filter() or false])
        end
        self.empty:Show()
    else
        self.empty:Hide()
    end

    local text
    local when = found.reach > found.player.level and ("by level %d"):format(found.reach) or "now"
    local here = self:Here(found)
    if here then when = ("in %s %s"):format(here, when) end
    if shown == 1 then
        text = ("1 upgrade you can go and get %s."):format(when)
    else
        text = ("%d upgrades you can go and get %s."):format(shown, when)
    end
    if found.waiting > 0 then
        text = text .. Colored("muted", ("  Still asking the server about %d items."):format(found.waiting))
    end
    self.footer:SetText(text)

    self.found = found
    return found
end

--- Look again once a burst of events settles.
function FinderUI:RefreshSoon()
    if not (self.frame and self.frame:IsShown()) or self.pending then return end
    self.pending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0.5, function()
            FinderUI.pending = false
            FinderUI:Refresh()
        end)
    else
        self.pending = false
        self:Refresh()
    end
end

--------------------------------------------------------------------------------
-- Position and visibility
--------------------------------------------------------------------------------

function FinderUI:SavePosition()
    if not (ns.db and self.frame) then return end
    local point, _, relativePoint, x, y = self.frame:GetPoint()
    ns.db.finderPoint, ns.db.finderRelativePoint = point, relativePoint
    ns.db.finderX, ns.db.finderY = x, y
end

function FinderUI:RestorePosition()
    if not self.frame then return end
    local db = ns.db or {}
    self.frame:ClearAllPoints()
    -- Until it is dragged somewhere, it opens beside the gear window rather
    -- than over its title, far enough off that its portrait clears the gear
    -- window's close gem.
    local gear = ns.UI and ns.UI.frame
    local okShown, shown = pcall(function() return gear and gear:IsShown() end)
    if not db.finderMoved and okShown and shown then
        self.frame:SetPoint("TOPLEFT", gear, "TOPRIGHT", 30, 0)
        return
    end
    self.frame:SetPoint(db.finderPoint or "CENTER", UIParent, db.finderRelativePoint or "CENTER",
        db.finderX or 40, db.finderY or 20)
end

function FinderUI:Show()
    self:Build()
    if not self.frame:IsShown() then
        self:RestorePosition()
        self.offset = 0
        self.frame:Show()
        Motion:Open(self.frame)
        -- And a light runs round the portrait.
        if ns.Titanforged then ns.Titanforged:Opened(self.frame) end
    end
    self:Refresh()
end

function FinderUI:Hide()
    if self.frame then self.frame:Hide() end
end

function FinderUI:Toggle()
    if self.frame and self.frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

function FinderUI:OnTrackingChanged()
    if self.frame and self.frame:IsShown() then self:Draw() end
end

function FinderUI:OnUpgradeQuestChanged()
    self:OnTrackingChanged()
end

--- Follow a row's pick on the upgrade quest panel, or say why it cannot be.
function FinderUI:Follow(pick)
    local logic = ns.UpgradeQuest
    if not logic then return nil end
    local quest, why = logic:Follow(pick)
    if quest then
        ns.Print(("following %s on the upgrade quest panel."):format(pick.link or quest.link))
    else
        ns.Print(("%s can't be an upgrade quest yet: %s."):format(pick.link or "that", why or "unknown"))
    end
    return quest
end

local EVENTS = {
    "GET_ITEM_INFO_RECEIVED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP",
    "QUEST_TURNED_IN", "TRAIT_CONFIG_UPDATED", "BAG_UPDATE_DELAYED",
}

function FinderUI:OnEnable()
    for _, event in ipairs(EVENTS) do
        ns.RegisterEvent(self, event, self.RefreshSoon)
    end
    -- A new zone has its own list while "This zone only" is ticked.
    ns.RegisterEvent(self, "ZONE_CHANGED_NEW_AREA", function()
        if FinderUI:ZoneOnly() then FinderUI:RefreshSoon() end
    end)
    -- Only the "need ... more" on vendor rows changes: redraw, no rescan.
    ns.RegisterEvent(self, "PLAYER_MONEY", function()
        if FinderUI.frame and FinderUI.frame:IsShown() then FinderUI:Draw() end
    end)
end
