-- Blackthornes Equipment -- UI/MainWindow.lua
-- The gear window: every slot, what is worn in it, and the biggest upgrade
-- for it sitting in the bags.
--
-- It is what a click on the minimap button and a bare /beq open. Built like
-- the settings window (same header, palette and row heights) so the two read
-- as one set. It only shows: equipping is left to the player, because
-- putting on a bind-on-equip item binds it, and that cannot be undone.

local _, ns = ...

local UI = ns.NewModule("UI")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Compare = ns.Compare
local Items = ns.Items
local Weights = ns.Weights

local PADDING = 18
local HEADER = 36
local ROW_HEIGHT = 22
local COLUMN_HEADS = 22
local FOOTER = 44

local SLOT_X, WORN_X, BEST_X = 0, 84, 250
local GAIN_WIDTH = 90
local WIDTH = 520

-- The slots in the order the character sheet runs down them.
local SLOTS = {
    { 1, "Head" }, { 2, "Neck" }, { 3, "Shoulder" }, { 15, "Back" },
    { 5, "Chest" }, { 9, "Wrist" }, { 10, "Hands" }, { 6, "Waist" },
    { 7, "Legs" }, { 8, "Feet" }, { 11, "Ring" }, { 12, "Ring" },
    { 13, "Trinket" }, { 14, "Trinket" }, { 16, "Main hand" },
    { 17, "Off hand" }, { 18, "Ranged" },
}

local HEIGHT = HEADER + 12 + COLUMN_HEADS + #SLOTS * ROW_HEIGHT + FOOTER

UI.SLOTS = SLOTS

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

--- A strip of text that shows an item's tooltip under the mouse.
local function CreateItemCell(parent, width)
    local cell = CreateFrame("Button", nil, parent)
    cell:SetSize(width, ROW_HEIGHT)

    local text = Theme.CreateLabel(cell, "small", "text")
    text:SetPoint("LEFT", 0, 0)
    text:SetWidth(width)
    cell.text = text

    cell:SetScript("OnEnter", function(self)
        if type(self.link) ~= "string" then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        pcall(GameTooltip.SetHyperlink, GameTooltip, self.link)
        GameTooltip:Show()
    end)
    cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return cell
end

function UI:Build()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "BlackthornesEquipmentWindow", UIParent)
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
        UI:SavePosition()
    end)

    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "BlackthornesEquipmentWindow")
    end

    self.frame = frame
    self:BuildHeader()
    self:BuildRows()

    local footer = Theme.CreateLabel(frame, "small", "muted")
    footer:SetPoint("BOTTOMLEFT", PADDING, 24)
    footer:SetPoint("BOTTOMRIGHT", -PADDING, 24)
    self.footer = footer

    local hint = Theme.CreateLabel(frame, "tiny", "dim")
    hint:SetPoint("BOTTOMLEFT", PADDING, 10)
    hint:SetText("Hover an item for its tooltip. Equipping is up to you.")
    self.hint = hint

    frame:Hide()
    return frame
end

function UI:BuildHeader()
    local frame = self.frame

    local header = Theme.CreatePanel(frame, "header", false)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(HEADER)
    Theme.HouseHeader(header, 20)

    local title = Theme.CreateLabel(header, "title", "accent")
    title:SetPoint("LEFT", PADDING, 0)
    title:SetText("Blackthornes Equipment")

    local spec = Theme.CreateLabel(header, "small", "muted")
    spec:SetPoint("LEFT", title, "RIGHT", 10, -1)
    self.specLabel = spec

    local close = Widgets.CreateButton(header, "X", function() UI:Hide() end,
        { width = 22, height = 20, danger = true })
    close:SetPoint("RIGHT", -PADDING + 4, 0)

    local settings = Widgets.CreateButton(header, "Settings", function()
        if ns.SettingsUI then ns.SettingsUI:Toggle() end
    end, { width = 70, height = 20 })
    settings:SetPoint("RIGHT", close, "LEFT", -6, 0)

    local divider = Theme.CreateDivider(frame, "borderLit")
    divider:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
    divider:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT")
end

function UI:BuildRows()
    local frame = self.frame
    local top = -(HEADER + 12)
    local inner = WIDTH - PADDING * 2

    local heads = { { SLOT_X, "SLOT" }, { WORN_X, "WEARING" }, { BEST_X, "BEST IN BAGS" } }
    for _, head in ipairs(heads) do
        local label = Theme.CreateLabel(frame, "tiny", "accent")
        label:SetPoint("TOPLEFT", PADDING + head[1], top - 4)
        label:SetText(head[2])
    end

    self.rows = {}
    for index, entry in ipairs(SLOTS) do
        local row = CreateFrame("Frame", nil, frame)
        row:SetSize(inner, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", PADDING, top - COLUMN_HEADS - (index - 1) * ROW_HEIGHT)
        Theme.Fill(row, index % 2 == 0 and "row" or "rowAlt")

        local name = Theme.CreateLabel(row, "small", "muted")
        name:SetPoint("LEFT", SLOT_X + 6, 0)
        name:SetText(entry[2])

        local worn = CreateItemCell(row, BEST_X - WORN_X - 8)
        worn:SetPoint("LEFT", WORN_X, 0)

        local best = CreateItemCell(row, inner - BEST_X - GAIN_WIDTH - 8)
        best:SetPoint("LEFT", BEST_X, 0)

        local gain = Theme.CreateLabel(row, "small", "good", "RIGHT")
        gain:SetPoint("RIGHT", -6, 0)
        gain:SetWidth(GAIN_WIDTH)

        self.rows[index] = { slot = entry[1], worn = worn, best = best, gain = gain }
    end
end

--------------------------------------------------------------------------------
-- Filling it in
--------------------------------------------------------------------------------

local function SetCell(cell, link, emptyText, colorKey)
    cell.link = link
    if link then
        cell.text:SetText(link)
        cell.text:SetTextColor(Theme.Unpack("text"))
    else
        cell.text:SetText(emptyText)
        cell.text:SetTextColor(Theme.Unpack(colorKey or "dim"))
    end
end

--- Put what is worn and what is in the bags into every row.
-- @return how many slots have an upgrade waiting
function UI:Refresh()
    if not (self.frame and self.frame:IsShown()) then return 0 end

    local spec, why, class = Weights:CurrentSpec()
    local best = {}
    if spec then
        local ok, found = pcall(Compare.BestInBags, Compare)
        if ok then best = found end
        self.specLabel:SetText(("judging gear as %s"):format(Weights.SPECS[class][spec].name))
    else
        self.specLabel:SetText("")
    end

    local upgrades = 0
    for _, row in ipairs(self.rows) do
        SetCell(row.worn, Items:Equipped(row.slot), "empty")

        local pick = best[row.slot]
        if pick then
            upgrades = upgrades + 1
            SetCell(row.best, pick.link)
            row.gain:SetText(Compare:HowMuch(pick.result))
        else
            SetCell(row.best, nil, "-")
            row.gain:SetText("")
        end
    end

    if spec and Weights:IsCustom(class, spec) then
        self.hint:SetText("Judged by your own stat weights. Equipping is up to you.")
    else
        self.hint:SetText("Hover an item for its tooltip. Equipping is up to you.")
    end

    if not spec then
        self.footer:SetText(("There are no stat weights for %s yet."):format(class or "this class"))
    elseif upgrades == 0 then
        self.footer:SetText("Nothing in your bags beats what you wear.")
    elseif upgrades == 1 then
        self.footer:SetText("1 upgrade in your bags.")
    else
        self.footer:SetText(("%d upgrades in your bags."):format(upgrades))
    end
    self.upgrades = upgrades
    return upgrades
end

--- Refresh once a burst of bag events settles.
function UI:RefreshSoon()
    if not (self.frame and self.frame:IsShown()) or self.pending then return end
    self.pending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0.2, function()
            UI.pending = false
            UI:Refresh()
        end)
    else
        self.pending = false
        self:Refresh()
    end
end

--------------------------------------------------------------------------------
-- Position and visibility
--------------------------------------------------------------------------------

function UI:SavePosition()
    if not (ns.db and self.frame) then return end
    local point, _, relativePoint, x, y = self.frame:GetPoint()
    ns.db.point, ns.db.relativePoint, ns.db.x, ns.db.y = point, relativePoint, x, y
end

function UI:RestorePosition()
    if not self.frame then return end
    local db = ns.db or {}
    self.frame:ClearAllPoints()
    self.frame:SetPoint(db.point or "CENTER", UIParent, db.relativePoint or "CENTER",
        db.x or 0, db.y or 40)
end

function UI:Show()
    self:Build()
    if not self.frame:IsShown() then
        self:RestorePosition()
        self.frame:Show()
        ns.Motion:Open(self.frame)
    end
    self:Refresh()
end

function UI:Hide()
    if self.frame then self.frame:Hide() end
end

function UI:Toggle()
    if self.frame and self.frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

local EVENTS = {
    "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP",
    "GET_ITEM_INFO_RECEIVED", "TRAIT_CONFIG_UPDATED",
}

function UI:OnEnable()
    for _, event in ipairs(EVENTS) do
        ns.RegisterEvent(self, event, self.RefreshSoon)
    end
end

ns.RegisterCommand("window", "open the gear window (so does /beq on its own)", function()
    UI:Toggle()
end)
