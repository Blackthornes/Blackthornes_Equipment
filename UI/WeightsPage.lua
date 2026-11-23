-- Blackthornes Equipment -- UI/WeightsPage.lua
-- The Stat Weights page of Settings: how much each stat counts when gear is
-- judged, for any class and spec, changed by the player.
--
-- It was a window of its own until rework step 6 (2026-11-23); the rows,
-- the numbers and what they save are the same. Class and Spec are
-- drop-downs along the top. Under them, the stats on the left and the
-- kinds of weapon the class can hold on the right, each a row of
-- [name .. - value +]. The value can be typed as well as stepped, because
-- the built-in weights run from 0.005 (a point of armor) to 16 (1% crit)
-- and no one step size suits both. A weapon kind's number is what its
-- whole score is multiplied by, 1 for no change, so a rogue can count
-- daggers above swords.
--
-- What is shown is what Weights:Get and Weights:TypeFactor return, and
-- every change goes through Weights:SetWeight, Weights:SetTypeFactor or
-- Weights:Reset, so the page never keeps a copy of its own. Open it from
-- the Settings tab or with /beq weights.

local _, ns = ...
local L = ns.L

local WeightsPage = ns.NewModule("WeightsPage")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Motion = ns.Motion
local Weights = ns.Weights

WeightsPage.KEY = "weights"

local PICKERS = 62          -- the pickers and the line under them
local HEADS = 22            -- the STAT and WEAPON TYPES headings
local ROW_HEIGHT = 26
local COLUMN_GAP = 18
local FOOT = 74             -- the two lines under the rows

local BUTTON = 22           -- the - and + buttons
local BOX = 58              -- the value between them
local MARK = 10             -- room for the gold bar on a changed row
local TYPE_STEP = 0.1       -- one press of - or + on a kind of weapon

-- The nine classic classes, in the order the character screen lists them.
local CLASSES = {
    { "WARRIOR", L["Warrior"] }, { "PALADIN", L["Paladin"] }, { "HUNTER", L["Hunter"] },
    { "ROGUE", L["Rogue"] }, { "PRIEST", L["Priest"] }, { "SHAMAN", L["Shaman"] },
    { "MAGE", L["Mage"] }, { "WARLOCK", L["Warlock"] }, { "DRUID", L["Druid"] },
}

WeightsPage.CLASSES = CLASSES

--- A class's name in the player's language, or nil.
function WeightsPage.ClassName(class)
    for _, entry in ipairs(CLASSES) do
        if entry[1] == class then return entry[2] end
    end
end

--------------------------------------------------------------------------------
-- Numbers
--------------------------------------------------------------------------------

--- A weight as shown: no trailing zeros, "12" rather than "12.000".
function WeightsPage.Format(value)
    local text = ("%.3f"):format(tonumber(value) or 0)
    text = text:gsub("0+$", ""):gsub("%.$", "")
    return text
end

--- How far one press of - or + moves a weight: small steps for small
--- weights, whole numbers for crit and hit.
function WeightsPage.StepFor(value)
    if value < 0.1 then return 0.01 end
    if value < 1 then return 0.05 end
    if value < 10 then return 0.5 end
    return 1
end

--- The weight one press away from `value` in `direction` (1 or -1).
function WeightsPage.Nudge(value, direction)
    -- Going down, the step is the one for the value just below, so 1 steps
    -- down to 0.95 rather than 0.5.
    local step = WeightsPage.StepFor(direction < 0 and value - 0.0001 or value)
    local wanted = math.floor((value + direction * step) / step + 0.5) * step
    return Weights:Clean(wanted)
end

--- A kind of weapon's number one press away from `value`.
function WeightsPage.NudgeType(value, direction)
    local wanted = math.floor((value + direction * TYPE_STEP) / TYPE_STEP + 0.5) * TYPE_STEP
    return Weights:CleanType(wanted)
end

--- What a row shows now, and its built-in value.
function WeightsPage:RowValue(row)
    if row.entry.weapon then
        return Weights:TypeFactor(self.class, self.spec, row.entry.key), 1
    end
    return Weights:Value(self.class, self.spec, row.entry.key)
end

--- True when the player has changed what a row shows.
function WeightsPage:RowCustom(row)
    if row.entry.weapon then return Weights:IsTypeCustom(self.class, self.spec, row.entry.key) end
    return Weights:IsCustom(self.class, self.spec, row.entry.key)
end

--- Keep a new value for a row. The value kept, or nil.
function WeightsPage:RowSet(row, value)
    if row.entry.weapon then
        return Weights:SetTypeFactor(self.class, self.spec, row.entry.key, value)
    end
    return Weights:SetWeight(self.class, self.spec, row.entry.key, value)
end

--------------------------------------------------------------------------------
-- What is shown
--------------------------------------------------------------------------------

--- The stat entries to list for a class and spec: those any of the class's
--- specs weighs, Weights.ALWAYS_LISTED (Spirit and health every 5 sec),
--- plus any the player has given a weight, or every stat when
--- `all` is set.
function WeightsPage:StatsFor(class, spec, all)
    local wanted = {}
    for stat in pairs(Weights.ALWAYS_LISTED or {}) do wanted[stat] = true end
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
function WeightsPage:Specs()
    local specs = Weights.SPECS[self.class]
    return specs and specs.order or {}, specs
end

--- What the line under the pickers says.
function WeightsPage:StatusText()
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

--- A column heading with WEIGHT at its right end.
local function Heads(panel, x, width, text)
    local left = Theme.CreateLabel(panel, "tiny", "heading")
    left:SetPoint("TOPLEFT", x + MARK, -(PICKERS + 4))
    left:SetText(text)
    local right = Theme.CreateLabel(panel, "tiny", "heading", "RIGHT")
    right:SetPoint("TOPRIGHT", panel, "TOPLEFT", x + width - 6, -(PICKERS + 4))
    right:SetText(L["WEIGHT"])
    return left, right
end

--- Build the page on Settings' pages (UI/SettingsPages.lua), `width` wide.
function WeightsPage:Build(pages, key, width)
    if self.frame then return self.frame end
    local page = pages and pages.pages[key or WeightsPage.KEY]
    if not page then return nil end
    self.pages, self.key = pages, key or WeightsPage.KEY
    self.width = width
    self.columnWidth = math.floor((width - COLUMN_GAP) / 2)

    local panel = CreateFrame("Frame", nil, page.content)
    panel:SetSize(width, 400)
    panel.fixedHeight = 400
    pages:Place(self.key, 1, panel)
    self.frame = panel
    self.rows = {}

    self:BuildPickers()
    self.statHeading = Heads(panel, 0, self.columnWidth, L["STAT"])
    self.typeHeading, self.typeWeight = Heads(panel, self.columnWidth + COLUMN_GAP, self.columnWidth,
        L["WEAPON TYPES"])
    for index, entry in ipairs(Weights.STAT_ORDER) do
        self.rows[index] = self:BuildRow(entry)
    end
    self.typeRows = {}
    for index, entry in ipairs(Weights.WEAPON_TYPES) do
        self.typeRows[index] = self:BuildRow({ key = entry.key, name = entry.name, weapon = true })
    end
    self:BuildFooter()

    -- Find a Setting finds the page by its stats and weapon kinds.
    local words = { L["STAT WEIGHTS"], L["Class:"], L["Spec:"], L["WEAPON TYPES"] }
    for _, entry in ipairs(Weights.STAT_ORDER) do words[#words + 1] = Weights.Label(entry.name) end
    for _, entry in ipairs(Weights.WEAPON_TYPES) do words[#words + 1] = Weights.Label(entry.name) end
    pages:Searchable(self.key, panel, table.concat(words, " "))
    return panel
end

function WeightsPage:BuildPickers()
    local panel = self.frame

    local classLabel = Theme.CreateLabel(panel, "small", "text")
    classLabel:SetPoint("TOPLEFT", MARK, -5)
    classLabel:SetText(L["Class:"])

    -- Drop-downs (a player asked, 2026-10-22): a pick is one click, not a
    -- walk through every class one step at a time.
    local classOptions = {}
    for _, entry in ipairs(CLASSES) do
        classOptions[#classOptions + 1] = { text = entry[2], value = entry[1] }
    end
    local classWidth = Widgets.DropdownWidth(classOptions, BOX)
    self.classPicker = Widgets.CreateDropdown(panel, classOptions, function(class)
        WeightsPage:PickClass(class)
    end, { width = classWidth })
    self.classPicker:SetPoint("TOPLEFT", MARK + Theme.TextWidth("small", L["Class:"]) + 10, -2)

    local specLabel = Theme.CreateLabel(panel, "small", "text")
    specLabel:SetPoint("LEFT", self.classPicker, "RIGHT", 22, 0)
    specLabel:SetText(L["Spec:"])

    -- Wide enough for the longest spec name of any class.
    local specNames = {}
    for _, specs in pairs(Weights.SPECS) do
        for _, key in ipairs(specs.order) do
            specNames[#specNames + 1] = { text = Weights.Label(specs[key].name) }
        end
    end
    local specWidth = Widgets.DropdownWidth(specNames, BOX)
    self.specPicker = Widgets.CreateDropdown(panel, {}, function(spec)
        WeightsPage:PickSpec(spec)
    end, { width = specWidth })
    self.specPicker:SetPoint("LEFT", specLabel, "RIGHT", 10, 0)

    self.allStats = Widgets.CreateCheckbox(panel, L["Every stat"], function()
        WeightsPage:Refresh()
    end, false)
    self.allStats:SetPoint("LEFT", self.specPicker, "RIGHT", 22, 0)

    -- Shown only while something differs from the built-in weights.
    local resetText = L["Use the Built-in Weights"]
    self.reset = Widgets.CreateButton(panel, resetText, function()
        WeightsPage:ResetSpec()
    end, { width = math.max(160, Theme.TextWidth("small", resetText) + 24), height = 22 })
    self.reset:SetPoint("TOPRIGHT", 0, -2)

    local status = Theme.CreateLabel(panel, "small", "muted")
    status:SetPoint("TOPLEFT", MARK, -34)
    status:SetPoint("TOPRIGHT", 0, -34)
    status:SetWordWrap(true)
    self.status = status
end

--- A row's colour at rest, lit under the mouse.
local function Paint(row)
    local over = rawget(row, "over") == true
    row.background:SetColorTexture(Theme.Unpack(over and "glassHover" or row.restKey or "glass"))
    row.edge:SetShown(over)
end

--- One stat: a gold bar when changed, its name, and [- value +]. A dark
--- glass row, as every list is.
function WeightsPage:BuildRow(entry)
    local row = CreateFrame("Button", nil, self.frame)
    row:SetSize(self.columnWidth, ROW_HEIGHT)
    row.entry = entry
    row.editing = false

    row.restKey = "glass"
    row.background = Theme.Fill(row, "glass")
    local under = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    under:SetPoint("BOTTOMLEFT")
    under:SetPoint("BOTTOMRIGHT")
    under:SetHeight(1)
    under:SetColorTexture(Theme.Unpack("border", 0.6))
    row.edge = row:CreateTexture(nil, "ARTWORK")
    row.edge:SetPoint("TOPLEFT")
    row.edge:SetPoint("BOTTOMLEFT")
    row.edge:SetWidth(3)
    row.edge:SetColorTexture(Theme.Unpack("accent"))
    row.edge:Hide()
    -- The flash when a weight changes: gold, fading out.
    row.flash = Theme.Fill(row, "accent", 0, "ARTWORK")

    row.mark = row:CreateTexture(nil, "OVERLAY")
    row.mark:SetPoint("TOPLEFT", 4, -5)
    row.mark:SetPoint("BOTTOMLEFT", 4, 5)
    row.mark:SetWidth(2)
    row.mark:SetColorTexture(Theme.Unpack("accent"))

    row.plus = Widgets.CreateButton(row, "+", function() WeightsPage:Step(row, 1) end,
        { width = BUTTON, height = 20 })
    row.plus:SetPoint("RIGHT", -4, 0)

    -- The typed value sits sunk into the row, its edge lit gold while it
    -- has the keyboard.
    local well = Theme.CreatePanel(row, "panel", "border")
    well:SetSize(BOX, 20)
    well:SetPoint("RIGHT", row.plus, "LEFT", -4, 0)
    Theme.Recess(well)
    row.well = well

    row.minus = Widgets.CreateButton(row, "-", function() WeightsPage:Step(row, -1) end,
        { width = BUTTON, height = 20 })
    row.minus:SetPoint("RIGHT", well, "LEFT", -4, 0)

    -- The whole name, wrapped in the room left of the buttons.
    row.label = Theme.CreateLabel(row, "small", "text")
    row.label:SetPoint("LEFT", MARK, 0)
    row.label:SetPoint("RIGHT", row.minus, "LEFT", -8, 0)
    row.label:SetJustifyH("LEFT")
    if row.label.SetWordWrap then row.label:SetWordWrap(true) end
    row.label:SetText(LabelText(entry))

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
        WeightsPage:Commit(row, self:GetText())
        self:ClearFocus()
    end)
    box:SetScript("OnEscapePressed", function(self)
        row.editing = false
        self:ClearFocus()
        WeightsPage:Refresh()
    end)
    box:SetScript("OnEditFocusGained", function(self)
        row.editing = true
        Theme.SetBorderColor(well, "accent", 0.9)
        self:HighlightText()
    end)
    box:SetScript("OnEditFocusLost", function(self)
        -- Back to sunk: a dim edge with its top in shadow.
        Theme.SetBorderColor(well, "border", 0.8)
        well.borderTextures[1]:SetColorTexture(0.024, 0.020, 0.012, 1)
        if row.editing then WeightsPage:Commit(row, self:GetText()) end
    end)

    row:SetScript("OnEnter", function(self) WeightsPage:ShowRowTooltip(self) end)

    -- The row's own buttons and box take the mouse from it, so leaving the
    -- row through one of them has to put the row out too.
    local function Left()
        local okOver, over = pcall(row.IsMouseOver, row)
        if okOver and over == true then return end
        row.over = false
        Paint(row)
        if GameTooltip then GameTooltip:Hide() end
    end
    for _, child in ipairs({ row.minus, row.plus, box }) do
        if child.HookScript then child:HookScript("OnLeave", Left) end
    end
    row:SetScript("OnLeave", Left)

    return row
end

function WeightsPage:BuildFooter()
    local panel = self.frame

    local gold = Theme.CreateLabel(panel, "small", "muted")
    gold:SetPoint("BOTTOMLEFT", MARK, 40)
    gold:SetPoint("BOTTOMRIGHT", 0, 40)
    gold:SetWordWrap(true)
    gold:SetJustifyH("LEFT")
    gold:SetText(L["Gold marks what you changed. Every tooltip, arrow and list uses your numbers right away."])
    self.goldHint = gold

    local hint = Theme.CreateLabel(panel, "tiny", "dim")
    hint:SetPoint("BOTTOMLEFT", MARK, 0)
    hint:SetPoint("BOTTOMRIGHT", 0, 0)
    hint:SetWordWrap(true)
    hint:SetHeight(36)
    hint:SetJustifyH("LEFT")
    hint:SetJustifyV("BOTTOM")
    hint:SetText(L["A weight is how much one point of a stat is worth to you. 0 means the stat doesn't count. For weapon types, 1 means no change and a higher number makes that kind of weapon score better. Changes count right away for every character of that class."])
    self.hint = hint
end

--------------------------------------------------------------------------------
-- Changing weights
--------------------------------------------------------------------------------

--- Light a row up gold for a moment, so a change is seen to land.
function WeightsPage:Flash(row)
    Motion:Run(row, "flash", 0.6, function(p)
        row.flash:SetColorTexture(Theme.Unpack("accent", 0.28 * (1 - p)))
    end)
    Motion:Run(row.well, "pop", 0.6, function(p)
        Theme.SetBorderColor(row.well, "accent", 1 - p)
        if p >= 1 then Theme.SetBorderColor(row.well, "border") end
    end)
end

function WeightsPage:Step(row, direction)
    local value = self:RowValue(row)
    local wanted
    if row.entry.weapon then
        wanted = WeightsPage.NudgeType(value, direction)
    else
        wanted = WeightsPage.Nudge(value, direction)
    end
    if wanted and wanted ~= value then
        self:RowSet(row, wanted)
        self:Refresh()
        self:Flash(row)
    end
end

--- Keep what was typed in a row's box. Anything that is not a number puts
--- the box back to the weight as it was.
function WeightsPage:Commit(row, text)
    row.editing = false
    text = (text or ""):gsub(",", "."):gsub("^%s+", ""):gsub("%s+$", "")

    local before = self:RowValue(row)
    local kept = tonumber(text) and self:RowSet(row, text)
    self:Refresh()
    if kept and kept ~= before then self:Flash(row) end
end

function WeightsPage:ResetSpec()
    Weights:Reset(self.class, self.spec)
    self:Refresh()
    for _, list in ipairs({ self.rows, self.typeRows }) do
        for _, row in ipairs(list) do
            if row:IsShown() then self:Flash(row) end
        end
    end
end

function WeightsPage:ShowRowTooltip(row)
    row.over = true
    Paint(row)
    if not GameTooltip then return end

    local value, default = self:RowValue(row)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(Weights.Label(row.entry.name), Theme.Unpack("accent"))
    if self:RowCustom(row) then
        GameTooltip:AddLine(L.Format("Yours: %s", WeightsPage.Format(value)), Theme.Unpack("text"))
        GameTooltip:AddLine(L.Format("Built in: %s", WeightsPage.Format(default)), Theme.Unpack("muted"))
    else
        GameTooltip:AddLine(L.Format("Built in: %s", WeightsPage.Format(default)), Theme.Unpack("text"))
    end
    if row.entry.per then
        GameTooltip:AddLine(L["Counted per 1%, the way items print it."], Theme.Unpack("muted"))
    end
    if row.entry.weapon then
        -- One sentence, wrapped by the tooltip rather than split in two.
        GameTooltip:AddLine(L["1 is no change, 1.2 counts these weapons a fifth more, and 0 leaves them out."],
            Theme.Unpack("muted"))
    end
    GameTooltip:AddLine(L["Type a number or use - and +."], Theme.Unpack("dim"))
    GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Picking a class and spec
--------------------------------------------------------------------------------

function WeightsPage:PickClass(class)
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

function WeightsPage:PickSpec(spec)
    if not (Weights.SPECS[self.class] and Weights.SPECS[self.class][spec]) then return end
    self.spec = spec
    self:Refresh()
end

--- The class and spec the page starts on: the ones the player's gear is
--- judged by, else the first.
function WeightsPage:Start()
    if self.class and Weights.SPECS[self.class] then return end
    local playing, _, playerClass = Weights:CurrentSpec()
    if playing and Weights.SPECS[playerClass] then
        self.class, self.spec = playerClass, playing
    else
        self.class = CLASSES[1][1]
        self.spec = Weights.SPECS[self.class].order[1]
    end
end

--------------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------------

--- Is the page the one Settings is showing?
function WeightsPage:IsShown()
    local settings = ns.SettingsUI
    return self.frame ~= nil and settings ~= nil and settings:IsShown()
        and self.pages.shown == self.key
end

--- Put every row and picker in step with what is saved: the stats down the
--- left, the weapon kinds down the right, and the page as tall as the
--- longer of the two.
function WeightsPage:Refresh()
    if not self:IsShown() then return end
    self:Start()

    self.classPicker:SetValue(self.class)
    local order, specs = self:Specs()
    local specOptions = {}
    for _, key in ipairs(order) do
        specOptions[#specOptions + 1] = { text = Weights.Label(specs[key].name), value = key }
    end
    self.specPicker.options = specOptions
    self.specPicker:SetValue(self.spec)

    self.status:SetText(self:StatusText())
    self.reset:SetShown(Weights:IsCustom(self.class, self.spec)
        or Weights:IsTypeCustom(self.class, self.spec))

    local shown = {}
    for _, entry in ipairs(self:StatsFor(self.class, self.spec, self.allStats:GetChecked())) do
        shown[entry.key] = true
    end
    local holds = {}
    for _, entry in ipairs(Weights:WeaponTypesFor(self.class)) do holds[entry.key] = true end

    local top = PICKERS + HEADS
    local function Place(list, wanted, x)
        local place = 0
        for _, row in ipairs(list) do
            local on = wanted[row.entry.key] or false
            row:SetShown(on)
            if on then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, -(top + place * ROW_HEIGHT))
                place = place + 1
                row.restKey = place % 2 == 0 and "glassAlt" or "glass"
                Paint(row)

                local value = self:RowValue(row)
                local custom = self:RowCustom(row)
                local most = row.entry.weapon and Weights.MAX_TYPE or Weights.MAX_WEIGHT
                if not row.editing then row.box:SetText(WeightsPage.Format(value)) end
                row.box:SetTextColor(Theme.Unpack(custom and "accent" or (value > 0 and "text" or "dim")))
                row.label:SetTextColor(Theme.Unpack(custom and "accent" or "text"))
                row.mark:SetShown(custom)
                row.minus:SetDimmed(value <= 0)
                row.plus:SetDimmed(value >= most)
            end
        end
        return place
    end

    local stats = Place(self.rows, shown, 0)
    local types = Place(self.typeRows, holds, self.columnWidth + COLUMN_GAP)
    self.typeHeading:SetShown(types > 0)
    self.typeWeight:SetShown(types > 0)

    local height = top + math.max(stats, types) * ROW_HEIGHT + 12 + FOOT
    self.frame.fixedHeight = height
    self.frame:SetHeight(height)
    if self.pages.UpdateScroll then self.pages:UpdateScroll() end
end

--- Open Settings on this page.
function WeightsPage:Show()
    if ns.SettingsUI then ns.SettingsUI:Show(self.key) end
end

ns.RegisterCommand("weights", L["change how much each stat counts for your class and spec"], function()
    WeightsPage:Show()
end)
