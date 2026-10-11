-- Blackthornes Equipment -- UI/Settings.lua
-- The settings window: every switch the addon has, in one place.
--
-- Built the way Tradeskills' Settings tab is (UI/SettingsPages.lua), as in
-- Pets and Farmer: pages picked along the top, two columns of rows a page,
-- a row being [label .. control] on one line, and what it does in the row's
-- tooltip or, with Show descriptions ticked, underneath it.
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
local COLUMN_GAP = 18
-- Where the controls start: room for a label like "Minimap button" in the
-- game's font, which runs wider than it looks.
local CONTROL_X = 150

local TITLE = "Blackthornes Equipment"

-- The pages along the top (UI/SettingsPages.lua), as Tradeskills' Settings
-- tab has them. Every setting kept its saved name; only its place moved.
local PAGES = {
    { key = "gear", text = "GEAR",
      tip = "How gear is judged, and the arrows, tooltip lines and chat lines that say so" },
    { key = "hunts", text = "UPGRADE HUNTS",
      tip = "Where to get upgrades, tracking them, map pins and the banner" },
    { key = "quest", text = "UPGRADE QUEST",
      tip = "The upgrade quest, its panel and the arrow that points the way" },
    { key = "general", text = "GENERAL",
      tip = "The minimap button, window positions, text size and help" },
}

--------------------------------------------------------------------------------
-- Layout helpers
--------------------------------------------------------------------------------

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

--- A row whose button runs a /beq command, so every command has a button
--- here (a house rule).
local function CommandRow(pages, page, column, label, description, buttonText, command, opts)
    local row = pages:Row(page, column, label, description)
    local button = Widgets.CreateButton(row, buttonText, function()
        ns.HandleSlash(command)
    end, { width = 100, height = 20, primary = opts and opts.primary })
    button:SetPoint("TOPLEFT", CONTROL_X, 0)
    return row, button
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
    { "questArrowX", "questArrowY" },
    { "ignoredPoint", "ignoredRelativePoint", "ignoredX", "ignoredY" },
}

--- Put every Equipment window back where it started: the gear window, this
--- one, the stat weights, the upgrade finder, the upgrade tracker and the
--- upgrade quest. Only
--- the saved spots are cleared; nothing else is touched.
function SettingsUI:ResetPositions()
    for _, keys in ipairs(POSITION_KEYS) do
        for _, key in ipairs(keys) do ns.db[key] = nil end
    end
    for _, module in ipairs({ self, ns.UI, ns.WeightsUI, ns.FinderUI, ns.TrackerPanel, ns.QuestPanel, ns.QuestArrowUI, ns.IgnoredUI }) do
        if module and module.frame and module.RestorePosition then module:RestorePosition() end
    end
end
--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

function SettingsUI:Build()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "BlackthornesEquipmentSettings", UIParent)
    frame:SetSize(COLUMN_WIDTH * 2 + COLUMN_GAP + PADDING * 2, 600)
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

    self.pages = ns.SettingsPages.New(frame, {
        pages = PAGES,
        top = HEADER + 4,
        bottom = 40,
        padding = PADDING,
        columnWidth = COLUMN_WIDTH,
        columnGap = COLUMN_GAP,
        controlX = CONTROL_X,
        db = function() return ns.db end,
    })
    self:BuildGear()
    self:BuildHunts()
    self:BuildQuest()
    self:BuildGeneral()
    self.pages:Fit()

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

--- A tick box on `row` that saves `key` and calls `after` when it changes.
local function Tick(row, text, key, initial, after)
    local box = Widgets.CreateCheckbox(row, text, function(checked)
        ns.db[key] = checked
        if after then after(checked) end
    end, initial)
    box:SetPoint("TOPLEFT", CONTROL_X, -2)
    return box
end

--- Gear: how it is judged on the left; the gear window, the bags and the
--- tooltip on the right.
function SettingsUI:BuildGear()
    local controls = self.controls
    local pages = self.pages

    pages:Section("gear", 1, "JUDGING GEAR")

    local specRow = pages:Row("gear", 1, "Judge gear as", function() return SettingsUI:SpecHint() end)
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

    local weightsRow = pages:Row("gear", 1, "Stat weights",
        "How much each stat counts when gear is judged. Change them for any class and spec. Same as /beq weights.")
    controls.weights = Widgets.CreateButton(weightsRow, "Change weights", function()
        if ns.WeightsUI then ns.WeightsUI:Show() end
    end, { width = 120, height = 20 })
    controls.weights:SetPoint("TOPLEFT", CONTROL_X, 0)
    self.weightsRow = weightsRow

    local tooltipRow = pages:Row("gear", 1, "Tooltip line",
        "Whether gear beats what you wear, and where to learn a weapon skill.")
    controls.tooltip = Tick(tooltipRow, "Show it", "tooltipLine", true)

    local arrowRow = pages:Row("gear", 1, "Upgrade arrows",
        "A green arrow on upgrades you can wear now: in your bags, on the best quest reward and on loot up for a roll.")
    controls.arrows = Tick(arrowRow, "Show them", "bagArrows", true, function()
        if ns.BagIcons then pcall(ns.BagIcons.Refresh, ns.BagIcons) end
        if ns.QuestRewards then pcall(ns.QuestRewards.Refresh, ns.QuestRewards) end
        if ns.LootRolls then pcall(ns.LootRolls.Refresh, ns.LootRolls) end
        if ns.MoreMarks then
            pcall(ns.MoreMarks.RefreshMerchant, ns.MoreMarks)
            pcall(ns.MoreMarks.RefreshLoot, ns.MoreMarks)
        end
    end)

    local coinRow = pages:Row("gear", 1, "Sell coins",
        "A gold coin on gear in your bags that is not an upgrade and is worth selling to a vendor: white gear, and soulbound green or better gear when you can't disenchant it. Never on gathering tools.")
    controls.sellCoins = Tick(coinRow, "Show them", "bagSellCoins", true, function()
        if ns.BagIcons then pcall(ns.BagIcons.Refresh, ns.BagIcons) end
    end)

    local chatRow = pages:Row("gear", 1, "Upgrade in chat",
        "One line in chat when an upgrade you can wear now lands in your bags.")
    controls.upgradeChat = Tick(chatRow, "Say so", "upgradeChat", true)
    self.chatRow = chatRow

    pages:Section("gear", 2, "GEAR WINDOW")

    local windowRow = pages:Row("gear", 2, "Gear window",
        "What you wear and how each piece scores. Same as /beq window, or /beq on its own.")
    controls.openWindow = Widgets.CreateButton(windowRow, "Open it", function()
        ns.HandleSlash("window")
    end, { width = 100, height = 20, primary = true })
    controls.openWindow:SetPoint("TOPLEFT", CONTROL_X, 0)

    local _, bagsButton = CommandRow(pages, "gear", 2, "Gear in your bags",
        "Judges every piece of gear in your bags against what you wear, in chat. Same as /beq bags.",
        "Judge it", "bags")
    controls.bags = bagsButton

    pages:Section("gear", 2, "BAGS AND TOOLTIPS")

    local gamepadRow = pages:Row("gear", 2, "Bag sort button",
        "Hide the controller bag button that covers the sort button on the combined backpack.")
    controls.hideGamepadBag = Tick(gamepadRow, "Hide it", "hideGamepadBag", true, function()
        if ns.BagIcons then pcall(ns.BagIcons.ApplyGamepadBag, ns.BagIcons) end
    end)

    local suffixRow = pages:Row("gear", 2, "Random roll names",
        "Names a green's random roll on its tooltip (of the Monkey), which Forever leaves off.")
    controls.suffixLine = Tick(suffixRow, "Show them", "suffixLine", true)
end

-- The upgrade hunt switches: saved key, page column, label, what it does,
-- the tick box's words, and the module to tell when it changes.
local HUNTING = {
    { "slotUpgrades", 1, "Character sheet",
        "Hover a gear slot for the upgrades on offer for it; Alt-click it to track one.", "Show them" },
    { "upgradeToast", 1, "Upgrade banner",
        "A glowing banner when an upgrade lands in your bags, or a tracked one is got.", "Show it" },
    { "showTracker", 2, "Upgrade tracker",
        "The panel of upgrades you are tracking. Right-click a row in Where to get upgrades to track it.",
        "Show it", "TrackerPanel" },
    { "mapPins", 2, "Map pins",
        "Pins on the world map where each tracked upgrade comes from.", "Show them", "MapPins" },
}

--- Upgrade hunts: finding upgrades on the left, tracking them on the right.
function SettingsUI:BuildHunts()
    local controls = self.controls
    local pages = self.pages

    pages:Section("hunts", 1, "FINDING UPGRADES")

    local _, findButton = CommandRow(pages, "hunts", 1, "Where to get upgrades",
        "Upgrades from vendors, quests, dungeons and crafting, best first. Same as /beq find.",
        "Open it", "find", { primary = true })
    controls.find = findButton

    local function HuntRow(entry)
        local key, column, redraw = entry[1], entry[2], entry[6]
        local row = pages:Row("hunts", column, entry[3], entry[4])
        controls[key] = Tick(row, entry[5], key, true, function()
            local module = redraw and ns[redraw]
            if module and module.OnTrackingChanged then pcall(module.OnTrackingChanged, module) end
        end)
    end

    HuntRow(HUNTING[1])
    HuntRow(HUNTING[2])

    pages:Section("hunts", 2, "TRACKING")

    HuntRow(HUNTING[3])
    local _, trackedButton = CommandRow(pages, "hunts", 2, "Tracked upgrades",
        "Lists in chat the upgrades you are tracking and where each comes from. Same as /beq tracked.",
        "List them", "tracked")
    controls.tracked = trackedButton
    HuntRow(HUNTING[4])
end

--- The upgrade quest on the left, the arrow that leads there on the right.
function SettingsUI:BuildQuest()
    local controls = self.controls
    local pages = self.pages

    pages:Section("quest", 1, "UPGRADE QUEST")

    -- Off unless the player turns it on, unlike the switches on the other
    -- pages.
    local questRow = pages:Row("quest", 1, "Upgrade quest",
        "A quest for your best next upgrade, with the steps to go and get it.")
    controls.upgradeQuest = Widgets.CreateCheckbox(questRow, "Turn it on", function(checked)
        if ns.UpgradeQuest then ns.UpgradeQuest:SetEnabled(checked) end
    end, false)
    controls.upgradeQuest:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- The /beq quest commands as buttons, each doing just what its command
    -- does, chat line included.
    local thisRow = pages:Row("quest", 1, "This upgrade",
        "Ignore never offers it again and moves on to the next best. Switch takes the upgrade a level up opened.")
    controls.questSkip = Widgets.CreateButton(thisRow, "Ignore", function()
        ns.HandleSlash("quest ignore")
    end, { width = 64, height = 20 })
    controls.questSkip:SetPoint("TOPLEFT", CONTROL_X, 0)
    Explain(controls.questSkip, "Ignore this upgrade",
        "Never offer the upgrade you are following again on this character, and get a quest for the next best one. Ignored brings it back. Same as /beq quest ignore.")
    controls.questSwitch = Widgets.CreateButton(thisRow, "Switch", function()
        ns.HandleSlash("quest switch")
    end, { width = 72, height = 20, primary = true })
    controls.questSwitch:SetPoint("LEFT", controls.questSkip, "RIGHT", 12, 0)
    Explain(controls.questSwitch, "Switch to the new upgrade",
        "Follow the upgrade your new level opened instead. Lit when one is on offer. Same as /beq quest switch.")

    local panelRow = pages:Row("quest", 1, "Quest panel",
        "Open shows the panel (and turns the quest on). Ignored lists the upgrades you ignored, to restore them.")
    self.questPanelRow = panelRow
    controls.questOpen = Widgets.CreateButton(panelRow, "Open", function()
        ns.HandleSlash("quest")
    end, { width = 64, height = 20 })
    controls.questOpen:SetPoint("TOPLEFT", CONTROL_X, 0)
    Explain(controls.questOpen, "Open the quest panel",
        "Shows the upgrade quest panel, unfolded, and turns the quest on if it is off. Same as /beq quest.")
    -- The list of ignored upgrades, each with Restore, and Restore all
    -- (UI/IgnoredWindow.lua).
    controls.questReset = Widgets.CreateButton(panelRow, "Ignored", function()
        ns.HandleSlash("quest ignored")
    end, { width = 84, height = 20 })
    controls.questReset:SetPoint("LEFT", controls.questOpen, "RIGHT", 12, 0)
    Explain(controls.questReset, "Ignored upgrades",
        "Lists the upgrades you ignored on this character, to restore one or all of them. Same as /beq quest ignored.")

    -- The upgrade quest panel's size, as its gold corner grip and /beq quest
    -- size set it (the owner asked 2026-10-07). The size in use is lit green
    -- and named in the row's description, a dragged one by its percent.
    local questSizeRow = pages:Row("quest", 1, "Panel size", "")
    self.questSizeRow = questSizeRow
    controls.questSizes = {}
    local previous
    for _, size in ipairs(ns.QuestPanel and ns.QuestPanel.SIZES or {}) do
        local button = Widgets.CreateButton(questSizeRow, size.text, function()
            ns.HandleSlash("quest size " .. size.key)
        end, { width = 54, height = 20 })
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 6, 0)
        else
            button:SetPoint("TOPLEFT", CONTROL_X, 0)
        end
        Explain(button, ("%s quest panel"):format(size.text),
            ("Draws the upgrade quest panel at %d%%, text and all. Same as /beq quest size %s."):format(
                math.floor(size.scale * 100 + 0.5), size.key))
        button.scale = size.scale
        controls.questSizes[#controls.questSizes + 1] = button
        previous = button
    end

    -- Which tab the panel shows, as clicking a tab or /beq quest vendor
    -- (quest, dungeon, crafted) does.
    local tabRow = pages:Row("quest", 1, "Quest tab",
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

    -- Two switches that are also tick boxes on the quest panel: Solo only
    -- (the same as in Where to get upgrades) and Zone swap, the panel's
    -- "Change on a new zone" (the owner asked 2026-10-08), side by side.
    local soloRow = pages:Row("quest", 1, "Quest filters",
        "Solo only leaves out group, dungeon, raid and battleground quests. Zone swap lets This zone only change quests in a new zone.")
    controls.soloQuests = Widgets.CreateCheckbox(soloRow, "Solo only", function(checked)
        if ns.Finder then ns.Finder:SetSoloOnly(checked) end
    end, false)
    controls.soloQuests:SetPoint("TOPLEFT", CONTROL_X, -2)
    Explain(controls.soloQuests, "Solo quests only",
        "Leaves out quests that need a group, a dungeon, a raid or a battleground. The same switch as in Where to get upgrades and on the quest panel.")
    controls.questZoneSwap = Widgets.CreateCheckbox(soloRow, "Zone swap", function(checked)
        if ns.UpgradeQuest then ns.UpgradeQuest:SetZoneSwap(checked) end
    end, true)
    controls.questZoneSwap:SetPoint("TOPLEFT", CONTROL_X + 92, -2)
    Explain(controls.questZoneSwap, "Change on a new zone",
        "With This zone only ticked on the quest panel, entering a new zone swaps your quests for ones there. Untick it to keep them as you travel. The same switch as Change on a new zone on the panel.")

    -- The quest arrow, as the Arrow button on the quest panel and /beq
    -- arrow switch it, and /beq arrow check and next as buttons.
    pages:Section("quest", 2, "QUEST ARROW")

    local arrowRow = pages:Row("quest", 2, "Quest arrow",
        "A dial that points the way to the quest's next place. Click a step on the panel to aim it there. Also /beq arrow.")
    controls.questArrow = Widgets.CreateCheckbox(arrowRow, "Show it", function(checked)
        if ns.QuestArrow then ns.QuestArrow:SetOn(checked) end
    end, false)
    controls.questArrow:SetPoint("TOPLEFT", CONTROL_X, -2)
    controls.questArrowCheck = Widgets.CreateButton(arrowRow, "Check", function()
        ns.HandleSlash("arrow check")
    end, { width = 64, height = 20 })
    controls.questArrowCheck:SetPoint("TOPLEFT", CONTROL_X + 96, 0)
    Explain(controls.questArrowCheck, "Check the quest arrow",
        "Lists in chat what the arrow can read where you stand: your spot, your facing, the map. Same as /beq arrow check.")

    local _, nextButton = CommandRow(pages, "quest", 2, "Next place",
        "Points the arrow at the next place in the quest's steps. Same as /beq arrow next.",
        "Next", "arrow next")
    controls.questArrowNext = nextButton

    -- TomTom's arrow instead of the dial, when TomTom is installed.
    local tomtomRow = pages:Row("quest", 2, "Use TomTom",
        "With TomTom installed, its arrow points the way instead of this one. Same as /beq arrow tomtom.")
    controls.useTomTom = Widgets.CreateCheckbox(tomtomRow, "When installed", function(checked)
        if ns.TomTom then ns.TomTom:SetOn(checked) end
    end, true)
    controls.useTomTom:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- The panel's Quest log tab (UI/QuestLogTab.lua) and its two tick boxes.
    pages:Section("quest", 2, "QUEST LOG")

    local logRow = pages:Row("quest", 2, "Quest log",
        "Your quests on a tab of the quest panel, as the game's tracker shows them. Same as /beq quest log.")
    controls.questLogOpen = Widgets.CreateButton(logRow, "Show it", function()
        ns.HandleSlash("quest log")
    end, { width = 64, height = 20 })
    controls.questLogOpen:SetPoint("TOPLEFT", CONTROL_X, 0)
    Explain(controls.questLogOpen, "Show the quest log",
        "Opens the quest panel on its Quest log tab, and turns the upgrade quest on if it is off. Same as /beq quest log.")
    controls.questLogTracked = Widgets.CreateCheckbox(logRow, "Tracked only", function(checked)
        if ns.QuestLogUI then ns.QuestLogUI:SetTrackedOnly(checked) end
    end, false)
    controls.questLogTracked:SetPoint("TOPLEFT", CONTROL_X + 76, -2)
    Explain(controls.questLogTracked, "Tracked only",
        "The Quest log tab lists only the quests you track. The same tick box as on the tab.")

    local trackerRow = pages:Row("quest", 2, "Game's tracker",
        "Hides the game's own quest tracker while the quest panel is up, so your quests show in one place.")
    controls.hideQuestTracker = Widgets.CreateCheckbox(trackerRow, "Hide it", function(checked)
        if ns.QuestLogUI then ns.QuestLogUI:SetHidesTracker(checked) end
    end, false)
    controls.hideQuestTracker:SetPoint("TOPLEFT", CONTROL_X, -2)
end

--- General: windows and text on the left, help and problems on the right.
function SettingsUI:BuildGeneral()
    local controls = self.controls
    local pages = self.pages

    pages:Section("general", 1, "WINDOWS")

    local minimapRow = pages:Row("general", 1, "Minimap button",
        "Click it for the gear window, right-click for this page. Drag it to move it. Also /beq minimap.")
    controls.minimap = Widgets.CreateCheckbox(minimapRow, "Show it", function(checked)
        ns.db.minimapHidden = not checked
        if ns.MinimapButton then ns.MinimapButton:ApplyVisibility() end
    end, true)
    controls.minimap:SetPoint("TOPLEFT", CONTROL_X, -2)

    local positionRow = pages:Row("general", 1, "Window positions",
        "Moves every Equipment window, and the quest arrow, back where it started, if one ends up off screen.")
    local reset = Widgets.CreateButton(positionRow, "Put them back", function()
        SettingsUI:ResetPositions()
    end, { width = 100, height = 20 })
    reset:SetPoint("TOPLEFT", CONTROL_X, 0)

    -- Bigger letters in the same windows, as Tradeskills has. Every size
    -- is read as text is drawn, so it waits for /reload.
    local textRow = pages:Row("general", 1, "Text size",
        "Large and Larger add a point or two to all of this addon's text. Takes effect after /reload.")
    controls.textSize = ns.SettingsPages.TextSizeControl(textRow, CONTROL_X, function() return ns.db end)

    -- Asked 2026-10-10: the game's own look for players who would rather
    -- the windows matched the rest of their screen. Read at login, so it
    -- waits for /reload as Text size does. See UI/BlizzardLook.lua. A
    -- stepper, as Text size is: this addon's Widgets have no dropdown.
    local styleRow = pages:Row("general", 1, "Window style",
        "Titanforged is the house look, with a gold rim and glowing edges. Blizzard uses the game's own frames, red buttons and tick boxes. Takes effect after /reload.")
    controls.windowStyle = self:WindowStyleControl(styleRow)

    pages:Section("general", 2, "ADVANCED")

    local debugRow = pages:Row("general", 2, "Debug output",
        "Extra messages in chat, to help track down a problem.")
    controls.debug = Tick(debugRow, "Enabled", "debug", false)

    -- /beq perf and /beq perf clear as buttons.
    local speedRow = pages:Row("general", 2, "Speed check",
        "If the game hitches, Show lists in chat what Equipment spent longest on. Clear starts the count again.")
    controls.perfShow = Widgets.CreateButton(speedRow, "Show", function()
        ns.HandleSlash("perf")
    end, { width = 64, height = 20 })
    controls.perfShow:SetPoint("TOPLEFT", CONTROL_X, 0)
    Explain(controls.perfShow, "Show what took longest",
        "Lists in chat the slowest things Equipment did since you logged in or last cleared. Same as /beq perf.")
    controls.perfClear = Widgets.CreateButton(speedRow, "Clear", function()
        ns.HandleSlash("perf clear")
    end, { width = 64, height = 20 })
    controls.perfClear:SetPoint("LEFT", controls.perfShow, "RIGHT", 12, 0)
    Explain(controls.perfClear, "Start the count again",
        "Forgets the times so far, so the next Show covers only what happens from now. Same as /beq perf clear.")

    local _, probeButton = CommandRow(pages, "general", 2, "Client check",
        "Lists in chat which calls this client has, to help track down a problem. It only reads. Same as /beq probe.",
        "Check", "probe")
    controls.probe = probeButton

    local _, helpButton = CommandRow(pages, "general", 2, "Commands",
        "Lists every /beq command in chat. Same as /beq help.",
        "List them", "help")
    controls.help = helpButton
end

-- The window styles, in the order the stepper steps through them.
SettingsUI.WINDOW_STYLES = { "titanforged", "blizzard" }
SettingsUI.WINDOW_STYLE_LABELS = { titanforged = "Titanforged", blizzard = "Blizzard" }

--- The Window style stepper and its "Reload" button, shown while the
--- pick differs from what is drawn. Returns the stepper; stepper:Sync()
--- puts it back in step with the save.
function SettingsUI:WindowStyleControl(row)
    local styles = self.WINDOW_STYLES
    local Look = ns.BlizzardLook

    local function Drawn()
        return Look and Look.Style() or "titanforged"
    end

    local reload
    local stepper = Widgets.CreateStepper(row, {
        min = 1, max = #styles, step = 1,
        format = function(value) return self.WINDOW_STYLE_LABELS[styles[value]] end,
        onChange = function(value)
            ns.db.windowStyle = styles[value]
            reload:SetShown(styles[value] ~= Drawn())
        end,
    })
    ns.SettingsPages.FitStepper(stepper, self.WINDOW_STYLE_LABELS)
    stepper:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- ReloadUI is allowed from a click, and saves everything first.
    reload = Widgets.CreateButton(row, "Reload", function()
        if ReloadUI then ReloadUI() end
    end, { width = 60, height = 20 })
    ns.SettingsPages.ReloadUnder(row, stepper, reload)
    Explain(reload, "Reload", "Reload the interface so the new window style shows (/reload).")
    reload:Hide()
    stepper.reload = reload

    function stepper:Sync()
        local wanted = Look and Look.Wanted() or "titanforged"
        local index = 1
        for i, key in ipairs(styles) do
            if key == wanted then index = i end
        end
        self:SetValue(index, true)
        reload:SetShown(wanted ~= Drawn())
    end

    return stepper
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
    controls.sellCoins:SetChecked(ns.db.bagSellCoins ~= false)
    controls.hideGamepadBag:SetChecked(ns.db.hideGamepadBag ~= false)
    controls.upgradeChat:SetChecked(ns.db.upgradeChat ~= false)
    controls.suffixLine:SetChecked(ns.db.suffixLine ~= false)
    for _, entry in ipairs(HUNTING) do
        controls[entry[1]]:SetChecked(ns.db[entry[1]] ~= false)
    end
    controls.upgradeQuest:SetChecked(ns.db.upgradeQuest == true)
    controls.questArrow:SetChecked(ns.db.questArrow == true)
    controls.useTomTom:SetChecked(ns.db.useTomTom ~= false)
    controls.questLogTracked:SetChecked(ns.db.questLogTrackedOnly == true)
    controls.hideQuestTracker:SetChecked(ns.db.hideQuestTracker == true)
    self:RefreshQuestSize()
    controls.soloQuests:SetChecked(ns.db.soloQuestsOnly == true)
    controls.questZoneSwap:SetChecked(ns.db.upgradeQuestZoneSwap ~= false)
    -- Dimmed while there is nothing for them to do; still clickable, so a
    -- click says why.
    local quest = ns.UpgradeQuest
    local on = quest and quest:IsEnabled()
    controls.questSkip:SetAlpha(on and quest:Current() and 1 or 0.45)
    controls.questSwitch:SetAlpha(on and quest:Offer() and 1 or 0.45)
    if quest and self.questPanelRow then
        local count = 0
        for _ in pairs(quest:Skipped()) do count = count + 1 end
        controls.questReset:SetText(count > 0 and ("Ignored (%d)"):format(count) or "Ignored")
    end
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
    self.specRow:SetDescription(self:SpecHint())

    controls.textSize:Sync()
    controls.windowStyle:Sync()
    self.pages:Refresh()
end

--- The quest panel's size buttons and the line under them.
function SettingsUI:RefreshQuestSize()
    local panel = ns.QuestPanel
    if not (panel and self.questSizeRow) then return end
    local scale = panel:GetScale()
    for _, button in ipairs(self.controls.questSizes) do
        button:SetLabelColor(math.abs(button.scale - scale) < 0.005 and "good" or "gilt")
    end
    self.questSizeRow:SetDescription(("Now %s. Or drag the gold corner below the panel; right-click it for Normal."):format(
        panel.ScaleText(scale)))
end

--------------------------------------------------------------------------------
-- Position
--------------------------------------------------------------------------------

--- The upgrade quest changed (picked, skipped, an offer made): relight its
--- buttons.
function SettingsUI:OnUpgradeQuestChanged()
    self:Refresh()
end

--- "Solo quests only" was ticked or unticked in Where to get upgrades.
function SettingsUI:OnQuestArrowChanged()
    self:Refresh()
end

function SettingsUI:OnQuestFilterChanged()
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
        -- The game's panel is left open: hiding one of its frames from here
        -- would run its own code as this addon. Ours opens on top of it.
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
