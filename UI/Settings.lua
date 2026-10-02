-- Blackthornes Equipment -- UI/Settings.lua
-- The settings window: every switch the addon has, in one place.
--
-- Built the way Farmer's settings page and Tradeskills' Settings tab are, so
-- the three read as one set: a row is [label .. control] on one line with
-- what it does underneath, and rows are a fixed height so nothing slides
-- under the control beside it.
--
-- Open it with /beq settings, a click on the minimap button, or from the
-- game's own Options > AddOns list. Nothing here deletes anything.

local _, ns = ...

local SettingsUI = ns.NewModule("SettingsUI")

local Theme = ns.Theme
local Widgets = ns.Widgets

local PADDING = 18
local HEADER = 36

local COLUMN_WIDTH = 330
-- Where the controls start: room for a label like "Minimap button" in the
-- game's font, which runs wider than it looks.
local CONTROL_X = 150

local WIDTH = COLUMN_WIDTH + PADDING * 2
local HEIGHT = 586

local ROW_HEIGHT = 50
local ROW_GAP = -6
local SECTION_GAP = -16

local TITLE = "Blackthornes Equipment"

--------------------------------------------------------------------------------
-- Layout helpers
--------------------------------------------------------------------------------

--- Section heading with a rule underneath. Returns a frame to anchor rows to.
local function CreateSection(parent, text, opts)
    local section = CreateFrame("Frame", nil, parent)
    section:SetSize(COLUMN_WIDTH, 18)

    if opts.anchor then
        section:SetPoint("TOPLEFT", opts.anchor, "BOTTOMLEFT", 0, SECTION_GAP)
    else
        section:SetPoint("TOPLEFT", opts.x, opts.y)
    end

    local heading = Theme.CreateLabel(section, "tiny", "accent")
    heading:SetPoint("TOPLEFT", 0, 0)
    heading:SetText(text)

    local divider = Theme.CreateDivider(section, "border")
    divider:SetPoint("TOPLEFT", 0, -14)
    divider:SetWidth(COLUMN_WIDTH)

    return section
end

--- One setting: label and control on a line, what it does underneath.
local function CreateRow(parent, anchor, labelText, description)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, ROW_GAP)
    row:SetSize(COLUMN_WIDTH, ROW_HEIGHT)

    local label = Theme.CreateLabel(row, "small", "text")
    label:SetPoint("TOPLEFT", 0, -4)
    label:SetWidth(CONTROL_X - 8)
    label:SetText(labelText)

    local hint = Theme.CreateLabel(row, "tiny", "dim")
    hint:SetPoint("TOPLEFT", 0, -25)
    hint:SetWidth(COLUMN_WIDTH)
    hint:SetWordWrap(true)
    hint:SetText(description or "")

    row.label = label
    row.hint = hint
    return row
end

--------------------------------------------------------------------------------
-- The spec choices
--
-- The stepper holds an index; index 1 is always "Auto", then the class's
-- specs in talent-tree order.
--------------------------------------------------------------------------------

--- The spec keys this character can pick from, "auto" first.
function SettingsUI:SpecChoices()
    local choices = { "auto" }
    local class = ns.Weights:PlayerClass()
    local specs = class and ns.Weights.SPECS[class]
    if specs then
        for _, key in ipairs(specs.order) do choices[#choices + 1] = key end
    end
    return choices, specs
end

--- Judge gear as `key` ("auto" hands it back to the talents).
function SettingsUI:SetSpec(key)
    if key == "auto" then
        ns.charDB.spec = nil
    else
        ns.charDB.spec = key
    end
    self:Refresh()
    -- Every verdict can change with the spec: the bag arrows, quest rewards,
    -- the main window and Tradeskills' arrows.
    ns.Weights:Changed()
end

--- What the spec row's description says: which spec is in use, and why.
function SettingsUI:SpecHint()
    local spec, why, class = ns.Weights:CurrentSpec()
    if not spec then
        return ("There are no stat weights for %s yet."):format(class or "this class")
    end

    local name = ns.Weights.SPECS[class][spec].name
    if why == "picked" then
        return ("Judging gear as %s because you picked it. Auto goes back to your talents."):format(name)
    elseif why == "talents" then
        return ("Judging gear as %s, the tree with most of your talent points."):format(name)
    end
    return ("Judging gear as %s until your talents say otherwise."):format(name)
end

--- Put the settings window back where it started.
function SettingsUI:ResetPositions()
    ns.db.settingsPoint = nil
    ns.db.settingsRelativePoint = nil
    ns.db.settingsX = nil
    ns.db.settingsY = nil
    self:RestorePosition()
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

function SettingsUI:Build()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "BlackthornesEquipmentSettings", UIParent)
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
        SettingsUI:SavePosition()
    end)

    -- Escape closes it, like the game's own windows.
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "BlackthornesEquipmentSettings")
    end

    self.frame = frame
    self.controls = {}

    self:BuildHeader()
    self:BuildColumn()

    local footer = Theme.CreateLabel(frame, "tiny", "dim")
    footer:SetPoint("BOTTOMLEFT", PADDING, 14)
    footer:SetPoint("BOTTOMRIGHT", -PADDING, 14)
    footer:SetText("Changes save as you make them.")
    self.footer = footer

    frame:Hide()
    return frame
end

function SettingsUI:BuildHeader()
    local frame = self.frame

    local header = Theme.CreatePanel(frame, "header", false)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(HEADER)
    Theme.HouseHeader(header, 20)

    local title = Theme.CreateLabel(header, "title", "accent")
    title:SetPoint("LEFT", PADDING, 0)
    title:SetText(TITLE)

    local subtitle = Theme.CreateLabel(header, "small", "muted")
    subtitle:SetPoint("LEFT", title, "RIGHT", 10, -1)
    subtitle:SetText("Settings")

    local version = Theme.CreateLabel(header, "tiny", "dim", "RIGHT")
    version:SetText(ns.VersionLabel())

    local close = Widgets.CreateButton(header, "X", function() SettingsUI:Hide() end,
        { width = 22, height = 20, danger = true })
    close:SetPoint("RIGHT", -PADDING + 4, 0)

    version:SetPoint("RIGHT", close, "LEFT", -10, 0)

    local divider = Theme.CreateDivider(frame, "borderLit")
    divider:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
    divider:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT")
end

function SettingsUI:BuildColumn()
    local frame = self.frame
    local controls = self.controls

    local gear = CreateSection(frame, "GEAR", { x = PADDING, y = -(HEADER + 16) })

    local specRow = CreateRow(frame, gear, "Judge gear as", "")
    controls.spec = Widgets.CreateStepper(specRow, {
        min = 1, max = #SettingsUI:SpecChoices(), step = 1, value = 1,
        format = function(index)
            local choices, specs = SettingsUI:SpecChoices()
            local key = choices[index]
            if key == "auto" or not key then return "Auto" end
            return specs[key].name
        end,
        onChange = function(index)
            local choices = SettingsUI:SpecChoices()
            SettingsUI:SetSpec(choices[index] or "auto")
        end,
    })
    controls.spec:SetWidth(150)
    controls.spec:SetPoint("TOPLEFT", CONTROL_X, 0)
    self.specRow = specRow

    local weightsRow = CreateRow(frame, specRow, "Stat weights",
        "How much each stat counts when gear is judged. Change them for any class and spec.")
    controls.weights = Widgets.CreateButton(weightsRow, "Change weights", function()
        if ns.WeightsUI then ns.WeightsUI:Show() end
    end, { width = 120, height = 20 })
    controls.weights:SetPoint("TOPLEFT", CONTROL_X, 0)
    self.weightsRow = weightsRow

    local tooltipRow = CreateRow(frame, weightsRow, "Tooltip line",
        "Says on a piece of gear's tooltip whether it beats what you wear.")

    controls.tooltip = Widgets.CreateCheckbox(tooltipRow, "Show it", function(checked)
        ns.db.tooltipLine = checked
    end, true)
    controls.tooltip:SetPoint("TOPLEFT", CONTROL_X, -2)

    local arrowRow = CreateRow(frame, tooltipRow, "Upgrade arrows",
        "A green arrow on upgrades you can wear now: in your bags, and on the best quest reward.")

    controls.arrows = Widgets.CreateCheckbox(arrowRow, "Show them", function(checked)
        ns.db.bagArrows = checked
        if ns.BagIcons then pcall(ns.BagIcons.Refresh, ns.BagIcons) end
        if ns.QuestRewards then pcall(ns.QuestRewards.Refresh, ns.QuestRewards) end
    end, true)
    controls.arrows:SetPoint("TOPLEFT", CONTROL_X, -2)

    local windows = CreateSection(frame, "WINDOWS", { anchor = arrowRow })

    local minimapRow = CreateRow(frame, windows, "Minimap button",
        "Click it for the gear window, right-click for this page. Drag it to move it.")

    controls.minimap = Widgets.CreateCheckbox(minimapRow, "Show it", function(checked)
        ns.db.minimapHidden = not checked
        if ns.MinimapButton then ns.MinimapButton:ApplyVisibility() end
    end, true)
    controls.minimap:SetPoint("TOPLEFT", CONTROL_X, -2)

    local positionRow = CreateRow(frame, minimapRow, "Window position",
        "Moves this window back to the middle of the screen, if it ends up off screen.")

    local reset = Widgets.CreateButton(positionRow, "Put it back", function()
        SettingsUI:ResetPositions()
    end, { width = 100, height = 20 })
    reset:SetPoint("TOPLEFT", CONTROL_X, 0)

    local advanced = CreateSection(frame, "ADVANCED", { anchor = positionRow })

    local debugRow = CreateRow(frame, advanced, "Debug output",
        "Extra messages in chat, to help track down a problem.")

    controls.debug = Widgets.CreateCheckbox(debugRow, "Enabled", function(checked)
        ns.db.debug = checked
    end, false)
    controls.debug:SetPoint("TOPLEFT", CONTROL_X, -2)
end

--------------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------------

--- Put every control back in step with what is saved. Called whenever the
--- page opens and after any /beq command, because each of these can also be
--- changed by typing.
function SettingsUI:Refresh()
    if not (self.frame and self.frame:IsShown() and ns.db) then return end

    local controls = self.controls
    controls.minimap:SetChecked(not ns.db.minimapHidden)
    controls.debug:SetChecked(ns.db.debug == true)
    controls.tooltip:SetChecked(ns.db.tooltipLine ~= false)
    controls.arrows:SetChecked(ns.db.bagArrows ~= false)

    local choices = self:SpecChoices()
    local picked = ns.charDB and ns.charDB.spec
    local index = 1
    for i, key in ipairs(choices) do
        if key == picked then index = i end
    end
    controls.spec:SetValue(index, true)
    self.specRow.hint:SetText(self:SpecHint())
end

--------------------------------------------------------------------------------
-- Position
--------------------------------------------------------------------------------

function SettingsUI:SavePosition()
    if not (ns.db and self.frame) then return end

    local point, _, relativePoint, x, y = self.frame:GetPoint()

    ns.db.settingsPoint = point
    ns.db.settingsRelativePoint = relativePoint
    ns.db.settingsX = x
    ns.db.settingsY = y
end

function SettingsUI:RestorePosition()
    if not self.frame then return end

    local db = ns.db or {}

    self.frame:ClearAllPoints()
    self.frame:SetPoint(db.settingsPoint or "CENTER", UIParent,
        db.settingsRelativePoint or "CENTER", db.settingsX or 0, db.settingsY or 0)
end

--------------------------------------------------------------------------------
-- Visibility
--------------------------------------------------------------------------------

function SettingsUI:Show()
    self:Build()

    if not self.frame:IsShown() then
        self:RestorePosition()
        self.frame:Show()
        ns.Motion:Open(self.frame)
    end

    self:Refresh()
end

function SettingsUI:Hide()
    if self.frame then self.frame:Hide() end
end

function SettingsUI:Toggle()
    if self.frame and self.frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

--------------------------------------------------------------------------------
-- The game's own AddOns options list
--
-- As in Farmer: a small launcher under Options > AddOns rather than this page
-- squeezed into Blizzard's frame. Every call is guarded, because a missing
-- options entry is no reason for the addon to fail to load.
--------------------------------------------------------------------------------

function SettingsUI:RegisterGameOptions()
    if self.optionsPanel then return end

    local panel = CreateFrame("Frame")
    panel.name = TITLE

    local title = Theme.CreateLabel(panel, "title", "accent")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(TITLE)

    local blurb = Theme.CreateLabel(panel, "normal", "text")
    blurb:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    blurb:SetText("Equipment's settings have a window of their own.")

    local open = Widgets.CreateButton(panel, "Open Equipment settings", function()
        -- Close the game's panel first, or the two windows fight for the
        -- keyboard.
        if SettingsPanel and HideUIPanel then
            pcall(HideUIPanel, SettingsPanel)
        end
        SettingsUI:Show()
    end, { width = 190, height = 24 })
    open:SetPoint("TOPLEFT", blurb, "BOTTOMLEFT", 0, -14)

    local hint = Theme.CreateLabel(panel, "small", "muted")
    hint:SetPoint("TOPLEFT", open, "BOTTOMLEFT", 0, -10)
    hint:SetText("Or type /beq settings, or click the minimap button.")

    self.optionsPanel = panel

    local registered = false

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        registered = pcall(function()
            local category = Settings.RegisterCanvasLayoutCategory(panel, TITLE)
            Settings.RegisterAddOnCategory(category)
            SettingsUI.optionsCategory = category
        end)
    end

    -- The older options API, in case this client still has it instead.
    if not registered and type(InterfaceOptions_AddCategory) == "function" then
        registered = pcall(InterfaceOptions_AddCategory, panel)
    end

    if not registered then
        ns.Debug("no game options panel to register with; /beq settings still works")
    end

    return registered
end

function SettingsUI:OnEnable()
    local ok, err = pcall(self.RegisterGameOptions, self)
    if not ok then
        ns.Debug("could not add Equipment to the game's options:", tostring(err))
    end
end

ns.RegisterCommand("settings", "open the settings window", function()
    SettingsUI:Toggle()
end)

-- Common names for the same thing, so a guess works. Kept out of the help
-- list, which would otherwise print the same line three times.
ns.commands.options = ns.commands.settings
ns.commands.config = ns.commands.settings
