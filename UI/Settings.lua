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

-- The metal rim (UI/Titanforged.lua) reaches this far in from the edge;
-- the header sits inside it.
local RIM = 6

local COLUMN_WIDTH = 330
-- Where the controls start: room for a label like "Minimap button" in the
-- game's font, which runs wider than it looks.
local CONTROL_X = 150

-- Two columns: the gear and the windows on the left, upgrade hunts on the
-- right.
local WIDTH = COLUMN_WIDTH * 2 + PADDING * 3
local HEIGHT = 642

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

--- A button's tooltip: what it does, in clear white on the dark tooltip.
local function Explain(button, title, text)
    button:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(title, Theme.Unpack("accent"))
        GameTooltip:AddLine(text, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:HookScript("OnLeave", function() GameTooltip:Hide() end)
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

-- Where each window keeps its spot in the saved data.
local POSITION_KEYS = {
    { "point", "relativePoint", "x", "y" },
    { "settingsPoint", "settingsRelativePoint", "settingsX", "settingsY" },
    { "weightsPoint", "weightsRelativePoint", "weightsX", "weightsY" },
    { "finderPoint", "finderRelativePoint", "finderX", "finderY", "finderMoved" },
    { "trackerPoint", "trackerRelativePoint", "trackerX", "trackerY" },
    { "questPoint", "questRelativePoint", "questX", "questY" },
}

--- Put every Equipment window back where it started: the gear window, this
--- one, the stat weights, the upgrade finder, the upgrade tracker and the
--- upgrade quest. Only
--- the saved spots are cleared; nothing else is touched.
function SettingsUI:ResetPositions()
    for _, keys in ipairs(POSITION_KEYS) do
        for _, key in ipairs(keys) do ns.db[key] = nil end
    end
    for _, module in ipairs({ self, ns.UI, ns.WeightsUI, ns.FinderUI, ns.TrackerPanel, ns.QuestPanel }) do
        if module and module.frame and module.RestorePosition then module:RestorePosition() end
    end
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

    -- The house frame (UI/Titanforged.lua): the gold rim and corner gems,
    -- the name on a plate and the red close gem. No portrait: that is for
    -- the gear window and the finder.
    if ns.Titanforged then
        local trim = ns.Titanforged:Dress(frame, {
            title = TITLE,
            close = function() SettingsUI:Hide() end,
        })
        local left, right, top, bottom = ns.Titanforged.Reach(trim)
        if frame.SetClampRectInsets then frame:SetClampRectInsets(-left, right, top, -bottom) end
    else
        Theme.Border(frame, "borderLit")
    end
    Theme.Halo(frame, 12, 0.14)

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
    self:BuildHunting()

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

    -- The name is on the plate across the top edge and the close gem on the
    -- top right corner (UI/Titanforged.lua), so the header holds what this
    -- window is and the version, a little low, under the plate.
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", RIM, 0)
    header:SetPoint("TOPRIGHT", -RIM, 0)
    header:SetHeight(HEADER)

    local subtitle = Theme.CreateLabel(header, "normal", "muted")
    subtitle:SetPoint("LEFT", PADDING - RIM, -4)
    subtitle:SetText("Settings")

    -- Clear of the close gem on the corner.
    local version = Theme.CreateLabel(header, "tiny", "dim", "RIGHT")
    version:SetText(ns.VersionLabel())
    version:SetPoint("RIGHT", -(PADDING + 16 - RIM), -4)

    -- A gold rule under it, bright at the left and fading out to the right.
    local rule = header:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    rule:SetHeight(1)
    Theme.SetGradientAlpha(rule, "HORIZONTAL", "accent", 0.6, 0.05)
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
        "Whether gear beats what you wear, and where to learn a weapon skill.")

    controls.tooltip = Widgets.CreateCheckbox(tooltipRow, "Show it", function(checked)
        ns.db.tooltipLine = checked
    end, true)
    controls.tooltip:SetPoint("TOPLEFT", CONTROL_X, -2)

    local arrowRow = CreateRow(frame, tooltipRow, "Upgrade arrows",
        "A green arrow on upgrades you can wear now: in your bags, on the best quest reward and on loot up for a roll.")

    controls.arrows = Widgets.CreateCheckbox(arrowRow, "Show them", function(checked)
        ns.db.bagArrows = checked
        if ns.BagIcons then pcall(ns.BagIcons.Refresh, ns.BagIcons) end
        if ns.QuestRewards then pcall(ns.QuestRewards.Refresh, ns.QuestRewards) end
        if ns.LootRolls then pcall(ns.LootRolls.Refresh, ns.LootRolls) end
    end, true)
    controls.arrows:SetPoint("TOPLEFT", CONTROL_X, -2)

    local chatRow = CreateRow(frame, arrowRow, "Upgrade in chat",
        "One line in chat when an upgrade you can wear now lands in your bags.")

    controls.upgradeChat = Widgets.CreateCheckbox(chatRow, "Say so", function(checked)
        ns.db.upgradeChat = checked
    end, true)
    controls.upgradeChat:SetPoint("TOPLEFT", CONTROL_X, -2)
    self.chatRow = chatRow

    local windows = CreateSection(frame, "WINDOWS", { anchor = chatRow })

    local minimapRow = CreateRow(frame, windows, "Minimap button",
        "Click it for the gear window, right-click for this page. Drag it to move it.")

    controls.minimap = Widgets.CreateCheckbox(minimapRow, "Show it", function(checked)
        ns.db.minimapHidden = not checked
        if ns.MinimapButton then ns.MinimapButton:ApplyVisibility() end
    end, true)
    controls.minimap:SetPoint("TOPLEFT", CONTROL_X, -2)

    local positionRow = CreateRow(frame, minimapRow, "Window positions",
        "Moves every Equipment window back to the middle of the screen, if one ends up off screen.")

    local reset = Widgets.CreateButton(positionRow, "Put them back", function()
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

-- The right-hand column's switches: saved key, label, what it does, the
-- checkbox's words, and what to redraw when it changes.
local HUNTING = {
    { "upgradeToast", "Upgrade banner",
        "A glowing banner when an upgrade lands in your bags, or a tracked one is got.", "Show it" },
    { "showTracker", "Upgrade tracker",
        "The panel of upgrades you are tracking. Right-click a row in Where to get upgrades to track it.",
        "Show it", "TrackerPanel" },
    { "mapPins", "Map pins",
        "Pins on the world map where each tracked upgrade comes from.", "Show them", "MapPins" },
    { "slotUpgrades", "Character sheet",
        "Hover a gear slot for the upgrades on offer for it; Alt-click it to track one.", "Show them" },
    { "suffixLine", "Random roll names",
        "Names a green's random roll on its tooltip (of the Monkey), which Forever leaves off.", "Show them" },
}

function SettingsUI:BuildHunting()
    local frame = self.frame
    local controls = self.controls

    local section = CreateSection(frame, "UPGRADE HUNTS",
        { x = PADDING * 2 + COLUMN_WIDTH, y = -(HEADER + 16) })

    -- Off unless the player turns it on, unlike the switches below.
    local questRow = CreateRow(frame, section, "Upgrade quest",
        "A quest for your best next upgrade, with the steps to go and get it.")
    controls.upgradeQuest = Widgets.CreateCheckbox(questRow, "Turn it on", function(checked)
        if ns.UpgradeQuest then ns.UpgradeQuest:SetEnabled(checked) end
    end, false)
    controls.upgradeQuest:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- The /beq quest commands as buttons, each doing just what its command
    -- does, chat line included.
    local thisRow = CreateRow(frame, questRow, "This upgrade",
        "Skip moves on to the next best. Switch takes the upgrade a level up opened, when one is on offer.")
    controls.questSkip = Widgets.CreateButton(thisRow, "Skip", function()
        ns.HandleSlash("quest skip")
    end, { width = 64, height = 20 })
    controls.questSkip:SetPoint("TOPLEFT", CONTROL_X, 0)
    Explain(controls.questSkip, "Skip this upgrade",
        "Leave the upgrade you are following and get a quest for the next best one. Same as /beq quest skip.")
    controls.questSwitch = Widgets.CreateButton(thisRow, "Switch", function()
        ns.HandleSlash("quest switch")
    end, { width = 72, height = 20, primary = true })
    controls.questSwitch:SetPoint("LEFT", controls.questSkip, "RIGHT", 12, 0)
    Explain(controls.questSwitch, "Switch to the new upgrade",
        "Follow the upgrade your new level opened instead. Lit when one is on offer. Same as /beq quest switch.")

    local panelRow = CreateRow(frame, thisRow, "Quest panel",
        "Open shows the panel (and turns the quest on). Bring back lets skipped upgrades come up again.")
    controls.questOpen = Widgets.CreateButton(panelRow, "Open", function()
        ns.HandleSlash("quest")
    end, { width = 64, height = 20 })
    controls.questOpen:SetPoint("TOPLEFT", CONTROL_X, 0)
    Explain(controls.questOpen, "Open the quest panel",
        "Shows the upgrade quest panel, unfolded, and turns the quest on if it is off. Same as /beq quest.")
    controls.questReset = Widgets.CreateButton(panelRow, "Bring back", function()
        ns.HandleSlash("quest reset")
    end, { width = 84, height = 20 })
    controls.questReset:SetPoint("LEFT", controls.questOpen, "RIGHT", 12, 0)
    Explain(controls.questReset, "Bring back skipped upgrades",
        "Upgrades you skipped can be picked again. Same as /beq quest reset.")

    -- Which tab the panel shows, as clicking a tab or /beq quest vendor
    -- (quest, dungeon, crafted) does.
    local tabRow = CreateRow(frame, panelRow, "Quest tab",
        "Each kind of source keeps its own upgrade. Pick the one the panel shows.")
    controls.questTab = Widgets.CreateStepper(tabRow, {
        min = 1, max = 4, step = 1, value = 1,
        format = function(index)
            local tab = ns.UpgradeQuest and ns.UpgradeQuest.TABS[index]
            return tab and tab.name or "?"
        end,
        onChange = function(index)
            local tab = ns.UpgradeQuest and ns.UpgradeQuest.TABS[index]
            if tab then ns.HandleSlash("quest " .. tab.key) end
        end,
    })
    controls.questTab:SetWidth(170)
    controls.questTab:SetPoint("TOPLEFT", CONTROL_X, 0)

    local anchor = tabRow
    for _, entry in ipairs(HUNTING) do
        local key, redraw = entry[1], entry[5]
        local row = CreateRow(frame, anchor, entry[2], entry[3])
        controls[key] = Widgets.CreateCheckbox(row, entry[4], function(checked)
            ns.db[key] = checked
            local module = redraw and ns[redraw]
            if module and module.OnTrackingChanged then pcall(module.OnTrackingChanged, module) end
        end, true)
        controls[key]:SetPoint("TOPLEFT", CONTROL_X, -2)
        anchor = row
    end
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
    controls.upgradeChat:SetChecked(ns.db.upgradeChat ~= false)
    for _, entry in ipairs(HUNTING) do
        controls[entry[1]]:SetChecked(ns.db[entry[1]] ~= false)
    end
    controls.upgradeQuest:SetChecked(ns.db.upgradeQuest == true)
    -- Dimmed while there is nothing for them to do; still clickable, so a
    -- click says why.
    local quest = ns.UpgradeQuest
    local on = quest and quest:IsEnabled()
    controls.questSkip:SetAlpha(on and quest:Current() and 1 or 0.45)
    controls.questSwitch:SetAlpha(on and quest:Offer() and 1 or 0.45)
    if quest then
        for index, tab in ipairs(quest.TABS) do
            if tab.key == quest:Tab() then controls.questTab:SetValue(index, true) end
        end
    end

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

--- The upgrade quest changed (picked, skipped, an offer made): relight its
--- buttons.
function SettingsUI:OnUpgradeQuestChanged()
    self:Refresh()
end

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
