-- Blackthornes Equipment -- UI/WeightsWindow.lua
-- The stat weights window: how much each stat counts when gear is judged,
-- for any class and spec, changed by the player.
--
-- Built like the settings window (same header, palette and controls) so the
-- two read as one set. Each stat is a row: [name .. - value +], and the value
-- can be typed as well as stepped, because the built-in weights run from 0.005
-- (a point of armor) to 16 (1% crit) and no one step size suits both.
--
-- Under the stats, one row per kind of weapon the class can hold: what that
-- kind's whole score is multiplied by, 1 for no change, so a rogue can count
-- daggers above swords.
--
-- What is shown is what Weights:Get and Weights:TypeFactor return, and every
-- change goes through Weights:SetWeight, Weights:SetTypeFactor or
-- Weights:Reset, so the window never keeps a copy of its own. Open it from
-- the settings window or with /beq weights.

local _, ns = ...
local L = ns.L

local WeightsUI = ns.NewModule("WeightsUI")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Motion = ns.Motion
local Weights = ns.Weights

local PADDING = 18
local HEADER = 36

-- The metal rim (UI/Titanforged.lua) reaches this far in from the edge;
-- the header sits inside it.
local RIM = 6
local PICKERS = 84          -- the class and spec steppers and the line under them
local ROW_HEIGHT = 26
local COLUMN_GAP = 22
local FOOTER = 92

local BUTTON = 22           -- the - and + buttons
local BOX = 58              -- the value between them
local CONTROL = BUTTON * 2 + BOX + 8
local MARK = 8              -- room for the gold bar on a changed row
local TYPE_HEADING = 30     -- the "Weapon types" line above their rows
local TYPE_STEP = 0.1       -- one press of - or + on a kind of weapon

-- The nine classic classes, in the order the character screen lists them.
local CLASSES = {
    { "WARRIOR", L["Warrior"] }, { "PALADIN", L["Paladin"] }, { "HUNTER", L["Hunter"] },
    { "ROGUE", L["Rogue"] }, { "PRIEST", L["Priest"] }, { "SHAMAN", L["Shaman"] },
    { "MAGE", L["Mage"] }, { "WARLOCK", L["Warlock"] }, { "DRUID", L["Druid"] },
}

WeightsUI.CLASSES = CLASSES

--------------------------------------------------------------------------------
-- Numbers
--------------------------------------------------------------------------------

--- A weight as shown: no trailing zeros, "12" rather than "12.000".
function WeightsUI.Format(value)
    local text = ("%.3f"):format(tonumber(value) or 0)
    text = text:gsub("0+$", ""):gsub("%.$", "")
    return text
end

--- How far one press of - or + moves a weight: small steps for small
--- weights, whole numbers for crit and hit.
function WeightsUI.StepFor(value)
    if value < 0.1 then return 0.01 end
    if value < 1 then return 0.05 end
    if value < 10 then return 0.5 end
    return 1
end

--- The weight one press away from `value` in `direction` (1 or -1).
function WeightsUI.Nudge(value, direction)
    -- Going down, the step is the one for the value just below, so 1 steps
    -- down to 0.95 rather than 0.5.
    local step = WeightsUI.StepFor(direction < 0 and value - 0.0001 or value)
    local wanted = math.floor((value + direction * step) / step + 0.5) * step
    return Weights:Clean(wanted)
end

--- A kind of weapon's number one press away from `value`.
function WeightsUI.NudgeType(value, direction)
    local wanted = math.floor((value + direction * TYPE_STEP) / TYPE_STEP + 0.5) * TYPE_STEP
    return Weights:CleanType(wanted)
end

--- What a row shows now, and its built-in value.
function WeightsUI:RowValue(row)
    if row.entry.weapon then
        return Weights:TypeFactor(self.class, self.spec, row.entry.key), 1
    end
    return Weights:Value(self.class, self.spec, row.entry.key)
end

--- True when the player has changed what a row shows.
function WeightsUI:RowCustom(row)
    if row.entry.weapon then return Weights:IsTypeCustom(self.class, self.spec, row.entry.key) end
    return Weights:IsCustom(self.class, self.spec, row.entry.key)
end

--- Keep a new value for a row. The value kept, or nil.
function WeightsUI:RowSet(row, value)
    if row.entry.weapon then
        return Weights:SetTypeFactor(self.class, self.spec, row.entry.key, value)
    end
    return Weights:SetWeight(self.class, self.spec, row.entry.key, value)
end

--------------------------------------------------------------------------------
-- What is shown
--------------------------------------------------------------------------------

--- The stat entries to list for a class and spec: those any of the class's
--- specs weighs, plus any the player has given a weight, or every stat when
--- `all` is set.
function WeightsUI:StatsFor(class, spec, all)
    local wanted = {}
    local specs = Weights.SPECS[class]
    if specs then
        for _, key in ipairs(specs.order) do
            for stat in pairs(Weights:Defaults(class, key) or {}) do wanted[stat] = true end
        end
    end
    for stat, value in pairs(Weights:Get(class, spec) or {}) do
        if value > 0 then wanted[stat] = true end
    end

    local list = {}
    for _, entry in ipairs(Weights.STAT_ORDER) do
        if all or wanted[entry.key] then list[#list + 1] = entry end
    end
    return list
end

--- The label a stat's row reads, with "per 1%" in grey where it applies.
local function LabelText(entry)
    local name = Weights.Label(entry.name)
    if entry.per then
        return L.Format("%s  |c%sper 1%%|r", name, "ff545963")
    end
    return name
end

--- The spec keys for the class being edited, and the class's table.
function WeightsUI:Specs()
    local specs = Weights.SPECS[self.class]
    return specs and specs.order or {}, specs
end

--- What the line under the pickers says.
function WeightsUI:StatusText()
    local specs = Weights.SPECS[self.class]
    if not (specs and specs[self.spec]) then return "" end

    local name = Weights.Label(specs[self.spec].name)
    local changed, weapons = 0, 0
    for _, entry in ipairs(Weights.STAT_ORDER) do
        if Weights:IsCustom(self.class, self.spec, entry.key) then changed = changed + 1 end
    end
    for _, entry in ipairs(Weights:WeaponTypesFor(self.class)) do
        if Weights:IsTypeCustom(self.class, self.spec, entry.key) then weapons = weapons + 1 end
    end

    local parts = {}
    if changed == 1 then
        parts[#parts + 1] = L["1 stat changed"]
    elseif changed > 1 then
        parts[#parts + 1] = L.Format("%d stats changed", changed)
    end
    if weapons == 1 then
        parts[#parts + 1] = L["1 weapon type changed"]
    elseif weapons > 1 then
        parts[#parts + 1] = L.Format("%d weapon types changed", weapons)
    end

    local text
    if #parts == 0 then
        text = L.Format("%s uses the built-in weights.", name)
    else
        text = L.Format("%s uses your weights: %s.", name, table.concat(parts, ", "))
    end

    local playing, _, playerClass = Weights:CurrentSpec()
    if playerClass == self.class and playing == self.spec then
        text = text .. " " .. L["Your gear is judged by this spec."]
    end
    return text
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

--- The widest stat label, so no name is ever cut off.
local function LabelWidth()
    local widest = 0
    for _, entry in ipairs(Weights.STAT_ORDER) do
        widest = math.max(widest, Theme.TextWidth("small", LabelText(entry)))
    end
    for _, entry in ipairs(Weights.WEAPON_TYPES) do
        widest = math.max(widest, Theme.TextWidth("small", Weights.Label(entry.name)))
    end
    return widest
end

function WeightsUI:Build()
    if self.frame then return self.frame end

    self.labelWidth = LabelWidth()
    self.columnWidth = MARK + self.labelWidth + 14 + CONTROL
    self.width = PADDING * 2 + self.columnWidth * 2 + COLUMN_GAP

    local frame = CreateFrame("Frame", "BlackthornesEquipmentWeights", UIParent)
    frame:SetSize(self.width, 400)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")

    Theme.Fill(frame, "window")

    -- The house frame (UI/Titanforged.lua): the gold rim and corner gems,
    -- the name on a plate and the red close gem. No portrait: that is for
    -- the gear window and the finder.
    if ns.Titanforged then
        self.trim = ns.Titanforged:Dress(frame, {
            title = "Blackthornes Equipment",
            close = function() WeightsUI:Hide() end,
        })
        local left, right, top, bottom = ns.Titanforged.Reach(self.trim)
        if frame.SetClampRectInsets then frame:SetClampRectInsets(-left, right, top, -bottom) end
    else
        Theme.Border(frame, "borderLit")
    end
    Theme.Halo(frame, 12, 0.14)

    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        WeightsUI:SavePosition()
    end)

    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "BlackthornesEquipmentWeights")
    end

    self.frame = frame
    self.rows = {}

    self:BuildHeader()
    self:BuildPickers()
    for index, entry in ipairs(Weights.STAT_ORDER) do
        self.rows[index] = self:BuildRow(entry)
    end
    self:BuildTypes()
    self:BuildFooter()

    frame:Hide()
    return frame
end

function WeightsUI:BuildHeader()
    local frame = self.frame

    -- The name is on the plate across the top edge and the close gem on the
    -- top right corner (UI/Titanforged.lua), so the header holds what this
    -- window is, a little low, under the plate.
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", RIM, 0)
    header:SetPoint("TOPRIGHT", -RIM, 0)
    header:SetHeight(HEADER)

    local subtitle = Theme.CreateLabel(header, "normal", "muted")
    subtitle:SetPoint("LEFT", PADDING - RIM, -4)
    subtitle:SetText(L["Stat weights"])

    -- The plate and the corner gems either side of it must fit; the window
    -- widens for them rather than letting the plate run over a corner.
    local plate = self.trim and rawget(self.trim, "plate")
    local plateWidth = plate and plate:GetWidth()
    if type(plateWidth) ~= "number" then
        plateWidth = Theme.TextWidth("title", "Blackthornes Equipment") + 58
    end
    local needed = math.max(plateWidth + 2 * 40,
        PADDING + Theme.TextWidth("normal", L["Stat weights"]) + PADDING)
    if needed > self.width then
        self.width = needed
        frame:SetWidth(needed)
    end

    -- A gold rule under it, bright at the left and fading out to the right.
    local rule = header:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    rule:SetHeight(1)
    Theme.SetGradientAlpha(rule, "HORIZONTAL", "accent", 0.6, 0.05)
end

function WeightsUI:BuildPickers()
    local frame = self.frame
    local top = -(HEADER + 14)

    local classLabel = Theme.CreateLabel(frame, "small", "text")
    classLabel:SetPoint("TOPLEFT", PADDING, top - 3)
    classLabel:SetText(L["Class"])

    self.classPicker = Widgets.CreateStepper(frame, {
        min = 1, max = #CLASSES, step = 1, value = 1,
        format = function(index) return CLASSES[index] and CLASSES[index][2] or "" end,
        onChange = function(index) WeightsUI:PickClass(CLASSES[index][1]) end,
    })
    -- Wide enough for the longest class name, in the client's language.
    local widestClass = 0
    for _, entry in ipairs(CLASSES) do
        widestClass = math.max(widestClass, Theme.TextWidth("small", entry[2]))
    end
    self.classPicker:SetWidth(BUTTON * 2 + 8 + math.max(BOX, widestClass + 12))
    self.classPicker:SetPoint("TOPLEFT", PADDING + Theme.TextWidth("small", L["Class"]) + 10, top)

    local specLabel = Theme.CreateLabel(frame, "small", "text")
    specLabel:SetPoint("LEFT", self.classPicker, "RIGHT", 22, 0)
    specLabel:SetText(L["Spec"])

    -- Wide enough for the longest spec name of any class.
    local widest = 0
    for _, specs in pairs(Weights.SPECS) do
        for _, key in ipairs(specs.order) do
            widest = math.max(widest, Theme.TextWidth("small", Weights.Label(specs[key].name)))
        end
    end

    self.specPicker = Widgets.CreateStepper(frame, {
        min = 1, max = 3, step = 1, value = 1,
        format = function(index)
            local order, specs = WeightsUI:Specs()
            local key = order[index]
            return key and Weights.Label(specs[key].name) or ""
        end,
        onChange = function(index)
            local order = WeightsUI:Specs()
            if order[index] then WeightsUI:PickSpec(order[index]) end
        end,
    })
    self.specPicker:SetWidth(BUTTON * 2 + 8 + widest + 16)
    self.specPicker:SetPoint("LEFT", specLabel, "RIGHT", 10, 0)

    self.allStats = Widgets.CreateCheckbox(frame, L["Every stat"], function()
        WeightsUI:Refresh()
    end, false)
    self.allStats:SetPoint("TOPRIGHT", -PADDING, top - 1)

    -- Everything on this line must fit side by side; the window widens for it.
    local needed = PADDING + Theme.TextWidth("small", L["Class"]) + 10 + self.classPicker:GetWidth()
        + 22 + Theme.TextWidth("small", L["Spec"]) + 10 + self.specPicker:GetWidth()
        + 24 + self.allStats:GetWidth() + PADDING
    if needed > self.width then
        self.width = needed
        frame:SetWidth(needed)
    end

    local status = Theme.CreateLabel(frame, "small", "muted")
    status:SetPoint("TOPLEFT", PADDING, top - 30)
    status:SetPoint("TOPRIGHT", -PADDING, top - 30)
    status:SetWordWrap(true)
    self.status = status

    local divider = Theme.CreateDivider(frame, "border")
    divider:SetPoint("TOPLEFT", PADDING, -(HEADER + PICKERS - 6))
    divider:SetPoint("TOPRIGHT", -PADDING, -(HEADER + PICKERS - 6))
end

--- The "Weapon types" heading and a row for every kind of weapon; Refresh
--- shows the ones the class being edited can hold.
function WeightsUI:BuildTypes()
    local heading = Theme.CreateLabel(self.frame, "small", "accent")
    heading:SetText(L["Weapon types"])
    self.typeHeading = heading


    self.typeRows = {}
    for index, entry in ipairs(Weights.WEAPON_TYPES) do
        self.typeRows[index] = self:BuildRow({ key = entry.key, name = entry.name, weapon = true })
    end
end

--- One stat: a gold bar when changed, its name, and [- value +].
function WeightsUI:BuildRow(entry)
    local row = CreateFrame("Button", nil, self.frame)
    row:SetSize(self.columnWidth, ROW_HEIGHT - 2)
    row.entry = entry
    row.editing = false

    row.hover = Theme.Fill(row, "rowHover", 0)
    -- The flash when a weight changes: gold, fading out.
    row.flash = Theme.Fill(row, "accent", 0, "ARTWORK")

    row.mark = row:CreateTexture(nil, "OVERLAY")
    row.mark:SetPoint("TOPLEFT", 0, -3)
    row.mark:SetPoint("BOTTOMLEFT", 0, 3)
    row.mark:SetWidth(2)
    row.mark:SetColorTexture(Theme.Unpack("accent"))

    row.label = Theme.CreateLabel(row, "small", "text")
    row.label:SetPoint("LEFT", MARK, 0)
    row.label:SetWidth(self.labelWidth + 4)
    row.label:SetText(LabelText(entry))

    row.plus = Widgets.CreateButton(row, "+", function() WeightsUI:Step(row, 1) end,
        { width = BUTTON, height = 20 })
    row.plus:SetPoint("RIGHT", -2, 0)

    -- The typed value sits sunk into the row, its edge lit gold while it
    -- has the keyboard.
    local well = Theme.CreatePanel(row, "panel", "border")
    well:SetSize(BOX, 20)
    well:SetPoint("RIGHT", row.plus, "LEFT", -4, 0)
    Theme.Recess(well)
    row.well = well

    row.minus = Widgets.CreateButton(row, "-", function() WeightsUI:Step(row, -1) end,
        { width = BUTTON, height = 20 })
    row.minus:SetPoint("RIGHT", well, "LEFT", -4, 0)

    local box = CreateFrame("EditBox", nil, well)
    box:SetAllPoints(well)
    box:SetAutoFocus(false)
    box:SetMaxLetters(7)
    box:SetJustifyH("CENTER")
    box:SetFont(Theme.FONT, Theme.sizes.small, "")
    box:SetTextColor(Theme.Unpack("text"))
    box:SetTextInsets(4, 4, 0, 0)
    row.box = box

    box:SetScript("OnEnterPressed", function(self)
        WeightsUI:Commit(row, self:GetText())
        self:ClearFocus()
    end)
    box:SetScript("OnEscapePressed", function(self)
        row.editing = false
        self:ClearFocus()
        WeightsUI:Refresh()
    end)
    box:SetScript("OnEditFocusGained", function(self)
        row.editing = true
        Theme.SetBorderColor(well, "accent", 0.9)
        self:HighlightText()
    end)
    box:SetScript("OnEditFocusLost", function(self)
        -- Back to sunk: a dim edge with its top in shadow.
        Theme.SetBorderColor(well, "border", 0.8)
        well.borderTextures[1]:SetColorTexture(0.016, 0.020, 0.028, 1)
        if row.editing then WeightsUI:Commit(row, self:GetText()) end
    end)

    row:SetScript("OnEnter", function(self) WeightsUI:ShowRowTooltip(self) end)

    -- The row's own buttons and box take the mouse from it, so leaving the
    -- row through one of them has to put the row out too.
    local function LeftChild()
        local okOver, over = pcall(row.IsMouseOver, row)
        if okOver and over == true then return end
        Motion:Blend(row, "hover", 0, 0.18, function(p)
            row.hover:SetColorTexture(Theme.Unpack("rowHover", 0.6 * p))
        end)
        if GameTooltip then GameTooltip:Hide() end
    end
    for _, child in ipairs({ row.minus, row.plus, box }) do
        if child.HookScript then child:HookScript("OnLeave", LeftChild) end
    end
    row:SetScript("OnLeave", function(self)
        -- Moving onto the row's own - or + button is still being on the row.
        local okOver, over = pcall(self.IsMouseOver, self)
        if okOver and over == true then return end
        Motion:Blend(self, "hover", 0, 0.18, function(p)
            self.hover:SetColorTexture(Theme.Unpack("rowHover", 0.6 * p))
        end)
        if GameTooltip then GameTooltip:Hide() end
    end)

    return row
end

function WeightsUI:BuildFooter()
    local frame = self.frame

    local divider = Theme.CreateDivider(frame, "border")
    divider:SetPoint("BOTTOMLEFT", PADDING, FOOTER - 8)
    divider:SetPoint("BOTTOMRIGHT", -PADDING, FOOTER - 8)

    local hint = Theme.CreateLabel(frame, "tiny", "dim")
    hint:SetPoint("BOTTOMLEFT", PADDING, 44)
    hint:SetPoint("BOTTOMRIGHT", -PADDING, 44)
    hint:SetWordWrap(true)
    hint:SetHeight(30)
    hint:SetJustifyV("BOTTOM")
    hint:SetText(L["A weight is how much one point of a stat is worth to you. 0 means the stat doesn't count. For weapon types, 1 means no change and a higher number makes that kind of weapon score better. Changes count right away for every character of that class."])
    self.hint = hint

    self.reset = Widgets.CreateButton(frame, L["Use the built-in weights"], function()
        WeightsUI:ResetSpec()
    end, { width = 160, height = 22 })
    self.reset:SetPoint("BOTTOMLEFT", PADDING, 14)

    self.saved = Theme.CreateLabel(frame, "tiny", "dim")
    self.saved:SetPoint("LEFT", self.reset, "RIGHT", 12, 0)
    self.saved:SetText(L["Changes save as you make them."])
end

--------------------------------------------------------------------------------
-- Changing weights
--------------------------------------------------------------------------------

--- Light a row up gold for a moment, so a change is seen to land.
function WeightsUI:Flash(row)
    Motion:Run(row, "flash", 0.6, function(p)
        row.flash:SetColorTexture(Theme.Unpack("accent", 0.28 * (1 - p)))
    end)
    Motion:Run(row.well, "pop", 0.6, function(p)
        Theme.SetBorderColor(row.well, "accent", 1 - p)
        if p >= 1 then Theme.SetBorderColor(row.well, "border") end
    end)
end

function WeightsUI:Step(row, direction)
    local value = self:RowValue(row)
    local wanted
    if row.entry.weapon then
        wanted = WeightsUI.NudgeType(value, direction)
    else
        wanted = WeightsUI.Nudge(value, direction)
    end
    if wanted and wanted ~= value then
        self:RowSet(row, wanted)
        self:Refresh()
        self:Flash(row)
    end
end

--- Keep what was typed in a row's box. Anything that is not a number puts
--- the box back to the weight as it was.
function WeightsUI:Commit(row, text)
    row.editing = false
    text = (text or ""):gsub(",", "."):gsub("^%s+", ""):gsub("%s+$", "")

    local before = self:RowValue(row)
    local kept = tonumber(text) and self:RowSet(row, text)
    self:Refresh()
    if kept and kept ~= before then self:Flash(row) end
end

function WeightsUI:ResetSpec()
    Weights:Reset(self.class, self.spec)
    self:Refresh()
    for _, list in ipairs({ self.rows, self.typeRows }) do
        for _, row in ipairs(list) do
            if row:IsShown() then self:Flash(row) end
        end
    end
end

function WeightsUI:ShowRowTooltip(row)
    Motion:Blend(row, "hover", 1, 0.12, function(p)
        row.hover:SetColorTexture(Theme.Unpack("rowHover", 0.6 * p))
    end)
    if not GameTooltip then return end

    local value, default = self:RowValue(row)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(Weights.Label(row.entry.name), Theme.Unpack("accent"))
    if self:RowCustom(row) then
        GameTooltip:AddLine(L.Format("Yours: %s", WeightsUI.Format(value)), Theme.Unpack("text"))
        GameTooltip:AddLine(L.Format("Built in: %s", WeightsUI.Format(default)), Theme.Unpack("muted"))
    else
        GameTooltip:AddLine(L.Format("Built in: %s", WeightsUI.Format(default)), Theme.Unpack("text"))
    end
    if row.entry.per then
        GameTooltip:AddLine(L["Counted per 1%, the way items print it."], Theme.Unpack("muted"))
    end
    if row.entry.weapon then
        -- One sentence, wrapped by the tooltip rather than split in two.
        GameTooltip:AddLine(L["Multiplies these weapons' whole score. 1.2 counts them a fifth higher, 0.8 a fifth lower, and 0 leaves them out."],
            Theme.Unpack("muted"))
    end
    GameTooltip:AddLine(L["Type a number or use - and +."], Theme.Unpack("dim"))
    GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Picking a class and spec
--------------------------------------------------------------------------------

function WeightsUI:PickClass(class)
    if not Weights.SPECS[class] then return end
    self.class = class

    -- The spec the player is judged as when it is their class, else the
    -- class's first spec.
    local playing, _, playerClass = Weights:CurrentSpec()
    if playerClass == class and playing then
        self.spec = playing
    else
        self.spec = Weights.SPECS[class].order[1]
    end
    self:Refresh()
end

function WeightsUI:PickSpec(spec)
    if not (Weights.SPECS[self.class] and Weights.SPECS[self.class][spec]) then return end
    self.spec = spec
    self:Refresh()
end

--------------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------------

--- Put every row and picker in step with what is saved, and lay the rows
--- out in two columns with the window sized to fit them.
function WeightsUI:Refresh()
    if not (self.frame and self.frame:IsShown()) then return end
    if not (self.class and Weights.SPECS[self.class]) then return end

    for index, entry in ipairs(CLASSES) do
        if entry[1] == self.class then self.classPicker:SetValue(index, true) end
    end
    local order = self:Specs()
    for index, key in ipairs(order) do
        if key == self.spec then self.specPicker:SetValue(index, true) end
    end

    self.status:SetText(self:StatusText())
    self.reset:SetShown(Weights:IsCustom(self.class, self.spec)
        or Weights:IsTypeCustom(self.class, self.spec))

    local shown = {}
    for _, entry in ipairs(self:StatsFor(self.class, self.spec, self.allStats:GetChecked())) do
        shown[entry.key] = true
    end

    local visible = {}
    for _, row in ipairs(self.rows) do
        local on = shown[row.entry.key] or false
        row:SetShown(on)
        if on then visible[#visible + 1] = row end
    end

    local perColumn = math.ceil(#visible / 2)
    local top = HEADER + PICKERS + 4
    -- The two columns sit in the middle when the window is wider than they
    -- need, for its header line.
    local left = math.max(PADDING, math.floor((self.width - self.columnWidth * 2 - COLUMN_GAP) / 2))
    local function Place(list, from)
        local half = math.ceil(#list / 2)
        for index, row in ipairs(list) do
            local column = index > half and 1 or 0
            local line = column == 1 and index - half - 1 or index - 1
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self.frame, "TOPLEFT",
                left + column * (self.columnWidth + COLUMN_GAP), -(from + line * ROW_HEIGHT))

            local value = self:RowValue(row)
            local custom = self:RowCustom(row)
            local most = row.entry.weapon and Weights.MAX_TYPE or Weights.MAX_WEIGHT
            if not row.editing then row.box:SetText(WeightsUI.Format(value)) end
            row.box:SetTextColor(Theme.Unpack(custom and "accent" or (value > 0 and "text" or "dim")))
            row.label:SetTextColor(Theme.Unpack(custom and "accent" or "text"))
            row.mark:SetShown(custom)
            row.minus:SetDimmed(value <= 0)
            row.plus:SetDimmed(value >= most)
        end
        return from + half * ROW_HEIGHT
    end

    local bottom = Place(visible, top)

    -- The kinds of weapon this class can hold, under their own heading.
    local holds = {}
    for _, entry in ipairs(Weights:WeaponTypesFor(self.class)) do holds[entry.key] = true end
    local types = {}
    for _, row in ipairs(self.typeRows) do
        local on = holds[row.entry.key] or false
        row:SetShown(on)
        if on then types[#types + 1] = row end
    end
    self.typeHeading:SetShown(#types > 0)
    if #types > 0 then
        self.typeHeading:ClearAllPoints()
        self.typeHeading:SetPoint("TOPLEFT", self.frame, "TOPLEFT", left + MARK, -(bottom + 12))
        bottom = Place(types, bottom + TYPE_HEADING)
    end

    self.frame:SetHeight(bottom + 8 + FOOTER)
end

--------------------------------------------------------------------------------
-- Position and visibility
--------------------------------------------------------------------------------

function WeightsUI:SavePosition()
    if not (ns.db and self.frame) then return end
    local point, _, relativePoint, x, y = self.frame:GetPoint()
    ns.db.weightsPoint, ns.db.weightsRelativePoint = point, relativePoint
    ns.db.weightsX, ns.db.weightsY = x, y
end

function WeightsUI:RestorePosition()
    if not self.frame then return end
    local db = ns.db or {}
    self.frame:ClearAllPoints()
    self.frame:SetPoint(db.weightsPoint or "CENTER", UIParent,
        db.weightsRelativePoint or "CENTER", db.weightsX or 0, db.weightsY or 0)
end

--- Open on the class and spec the player's gear is judged by.
function WeightsUI:Show()
    self:Build()

    if not self.frame:IsShown() then
        local playing, _, playerClass = Weights:CurrentSpec()
        if playing then
            self.class, self.spec = playerClass, playing
        elseif not self.class then
            self.class = CLASSES[1][1]
            self.spec = Weights.SPECS[self.class].order[1]
        end

        self:RestorePosition()
        self.frame:Show()
        Motion:Open(self.frame)
    end

    self:Refresh()
end

function WeightsUI:Hide()
    if self.frame then self.frame:Hide() end
end

function WeightsUI:Toggle()
    if self.frame and self.frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

ns.RegisterCommand("weights", L["change how much each stat counts for your class and spec"], function()
    WeightsUI:Toggle()
end)
