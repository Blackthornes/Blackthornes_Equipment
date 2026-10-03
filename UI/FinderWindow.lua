-- Blackthornes Equipment -- UI/FinderWindow.lua
-- The "Where to get upgrades" window: for each slot, the best gear a vendor
-- sells, a quest gives or a dungeon drops that beats what is worn, and where
-- to go for it.
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
local FILTERS = 30
local ROW_HEIGHT = 40
local VISIBLE = 10
local FOOTER = 48
local WIDTH = 660

local SLOT_WIDTH = 84
local GAIN_WIDTH = 120
local SCROLL_WIDTH = 4

-- Some gear is sold by a dozen vendors; the tooltip lists this many.
local TOOLTIP_SOURCES = 8

local HEIGHT = HEADER + 10 + FILTERS + 8 + VISIBLE * ROW_HEIGHT + FOOTER

-- The tag in front of a source, in its own colour.
local KIND_COLORS = { vendor = "accent", quest = "quest", dungeon = "dungeon" }

local FILTER_BUTTONS = {
    { nil, "Everything" }, { "vendor", "Vendors" }, { "quest", "Quests" },
    { "dungeon", "Dungeons and raids" },
}

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
    end
    GameTooltip:Show()
end

function FinderUI:BuildRow(index)
    local inner = WIDTH - PADDING * 2 - SCROLL_WIDTH - 6
    local row = CreateFrame("Button", nil, self.frame)
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

    local slot = Theme.CreateLabel(row, "small", "muted")
    slot:SetPoint("TOPLEFT", 8, -7)
    slot:SetWidth(SLOT_WIDTH - 10)
    row.slot = slot

    local item = Theme.CreateLabel(row, "normal", "text")
    item:SetPoint("TOPLEFT", SLOT_WIDTH, -6)
    item:SetWidth(inner - SLOT_WIDTH - GAIN_WIDTH - 8)
    row.item = item

    local gain = Theme.CreateLabel(row, "normal", "good", "RIGHT")
    gain:SetPoint("TOPRIGHT", -8, -6)
    gain:SetWidth(GAIN_WIDTH)
    row.gain = gain

    local source = Theme.CreateLabel(row, "tiny", "muted")
    source:SetPoint("TOPLEFT", SLOT_WIDTH, -23)
    source:SetWidth(inner - SLOT_WIDTH - 8)
    row.source = source
    row.sourceWidth = inner - SLOT_WIDTH - 8

    local function Light(p)
        row.background:SetColorTexture(Motion.Mix(row.restKey, "rowHover", p))
        row.edge:SetColorTexture(Theme.Unpack("good", p))
    end

    row:SetScript("OnEnter", function(self)
        Motion:Blend(self, "hover", 1, 0.12, Light)
        ShowTooltip(self)
    end)
    row:SetScript("OnLeave", function(self)
        Motion:Blend(self, "hover", 0, 0.18, Light)
        GameTooltip:Hide()
    end)
    row:SetScript("OnClick", function(self)
        local pick = self.pick
        if not pick then return end
        if type(IsModifiedClick) == "function" and type(ChatEdit_InsertLink) == "function" then
            local ok, chatLink = pcall(IsModifiedClick, "CHATLINK")
            if ok and chatLink then pcall(ChatEdit_InsertLink, pick.link) end
        end
    end)
    if row.RegisterForClicks then row:RegisterForClicks("LeftButtonUp") end

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
    Theme.Border(frame, "borderLit")

    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
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

    self.listTop = -(HEADER + 10 + FILTERS + 8)
    self.rows = {}
    for index = 1, VISIBLE do self.rows[index] = self:BuildRow(index) end

    -- A thin track down the right of the list, and a thumb that shows where
    -- in it the view is.
    local track = frame:CreateTexture(nil, "ARTWORK")
    track:SetPoint("TOPRIGHT", -PADDING, self.listTop)
    track:SetSize(SCROLL_WIDTH, VISIBLE * ROW_HEIGHT)
    track:SetColorTexture(Theme.Unpack("rowAlt"))
    self.track = track

    local thumb = frame:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(SCROLL_WIDTH)
    thumb:SetColorTexture(Theme.Unpack("accent", 0.8))
    self.thumb = thumb

    local empty = Theme.CreateLabel(frame, "normal", "muted", "CENTER")
    empty:SetPoint("TOP", 0, self.listTop - 60)
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
    hint:SetText("Places and prices are from Classic, so Forever may differ. Shift-click an item to link it.")
    self.hint = hint

    frame:Hide()
    return frame
end

function FinderUI:BuildHeader()
    local frame = self.frame

    local header = Theme.CreatePanel(frame, "header", false)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(HEADER)
    Theme.HouseHeader(header, 20)

    local title = Theme.CreateLabel(header, "title", "accent")
    title:SetPoint("LEFT", PADDING, 0)
    title:SetText("Where to get upgrades")

    local spec = Theme.CreateLabel(header, "small", "muted")
    spec:SetPoint("LEFT", title, "RIGHT", 10, -1)
    self.specLabel = spec

    local close = Widgets.CreateButton(header, "X", function() FinderUI:Hide() end,
        { width = 22, height = 20, danger = true })
    close:SetPoint("RIGHT", -PADDING + 4, 0)

    local divider = Theme.CreateDivider(frame, "borderLit")
    divider:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
    divider:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT")
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
            button:SetPoint("TOPLEFT", PADDING, -(HEADER + 10))
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
end

--------------------------------------------------------------------------------
-- Filling it in
--------------------------------------------------------------------------------

--- The kind showing: "vendor", "quest", "dungeon", or nil for everything.
function FinderUI:Filter()
    local show = ns.db and ns.db.finderShow
    if show == "vendor" or show == "quest" or show == "dungeon" then return show end
    return nil
end

function FinderUI:SetFilter(kind)
    if ns.db then ns.db.finderShow = kind or "all" end
    self.offset = 0
    self:Refresh()
end

--- The picks as one list in character-sheet order, keeping only sources of
--- the kind showing (and picks that have one).
function FinderUI:Lines(found)
    local lines, only = {}, self:Filter()
    local seen = {}
    for _, entry in ipairs(ns.UI.SLOTS) do
        local slot = entry[1]
        local picks = found.slots[slot]
        if picks and not seen[slot] then
            seen[slot] = true
            local first = true
            for _, pick in ipairs(picks) do
                local sources = {}
                for _, source in ipairs(pick.sources) do
                    if not only or source.kind == only then sources[#sources + 1] = source end
                end
                if #sources > 0 then
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
        needs = line.pick.needs,
    }
    row.slot:SetText(line.first and line.slotName or "")
    row.item:SetText(line.pick.link)
    row.gain:SetText(Gain(line.pick.result))
    -- Gear that waits on a reputation is shown in amber, not green.
    row.gain:SetTextColor(Theme.Unpack(line.pick.needs and "warn" or "good"))

    local text = FinderUI.SourceLine(line.sources[1])
    if line.pick.needs then
        text = Colored("warn", ("Needs %s with %s"):format(line.pick.needs.standing,
            line.pick.needs.faction)) .. "  " .. text
    end
    local more = #line.sources - 1
    local tail = more > 0 and ("  +%d more"):format(more) or ""
    local room = row.sourceWidth - Theme.TextWidth("tiny", tail)
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

    local found, why = Finder:Scan(self:Filter())
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
    self.specLabel:SetText(("%s, level %d"):format(specName, found.player.level))

    self.lines = self:Lines(found)
    local most = math.max(0, #self.lines - VISIBLE)
    self.offset = math.min(self.offset or 0, most)
    self:Draw()

    local shown = #self.lines
    if shown == 0 then
        if found.waiting > 0 then
            self.empty:SetText("Asking the server about the gear on offer...")
        else
            self.empty:SetText(NO_UPGRADES[self:Filter() or false])
        end
        self.empty:Show()
    else
        self.empty:Hide()
    end

    local text
    if shown == 1 then
        text = "1 upgrade you can go and get now."
    else
        text = ("%d upgrades you can go and get now."):format(shown)
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

local EVENTS = {
    "GET_ITEM_INFO_RECEIVED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP",
    "QUEST_TURNED_IN", "TRAIT_CONFIG_UPDATED",
}

function FinderUI:OnEnable()
    for _, event in ipairs(EVENTS) do
        ns.RegisterEvent(self, event, self.RefreshSoon)
    end
end
