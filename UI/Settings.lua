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
local L = ns.L

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
-- Where the controls start: room for a label like "Upgrade Arrows:" in the
-- game's font, which runs wider than it looks. A longer one wraps.
local CONTROL_X = 150

local TITLE = "Blackthornes Equipment"

-- The pages along the top (UI/SettingsPages.lua), as Tradeskills' Settings
-- tab has them. Every setting kept its saved name; only its place moved.
local PAGES = {
    { key = "gear", text = L["GEAR"],
      tip = L["How gear is judged, and the arrows, tooltip lines and chat lines that say so"] },
    { key = "hunts", text = L["UPGRADE HUNTS"],
      tip = L["Where to get upgrades, tracking them, map pins and the banner"] },
    { key = "quest", text = L["UPGRADE QUEST"],
      tip = L["The upgrade quest, its panel and the arrow that points the way"] },
    { key = "general", text = L["GENERAL"],
      tip = L["Window positions, text size and help"] },
    { key = "about", text = L["ABOUT"],
      tip = L["How these addons are made, the version, the Discord and the other Blackthornes addons"] },
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

--- A row whose button runs a /beq command. Commands that only print to
--- chat, or only do what a panel already does, are typed and have no row
--- (the owner, 2026-10-15).
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
        return L.Format("There are no stat weights for %s yet.", class or L["this class"])
    end

    local name = ns.Weights:SpecName(class, spec)
    if why == "picked" then
        return L.Format("Judging gear as %s because you picked it. Auto goes back to your talents.", name)
    elseif why == "talents" then
        return L.Format("Judging gear as %s, the tree with most of your talent points.", name)
    end
    return L.Format("Judging gear as %s until your talents say otherwise.", name)
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
    -- About (UI/About.lua): the note on how the addons are made, then the
    -- version, the Discord and the other Blackthornes addons.
    if ns.About then
        local pages = self.pages
        pages:Section("about", 1, L["HOW THESE ADDONS ARE MADE"])
        local note = pages:Place("about", 1, ns.About:Note(pages.pages.about.content, COLUMN_WIDTH))
        pages:Searchable("about", note, note.words)
        pages:Section("about", 2, L["ABOUT"])
        local info = pages:Place("about", 2, ns.About:Info(pages.pages.about.content, COLUMN_WIDTH))
        pages:Searchable("about", info, info.words)
    end
    self.pages:Fit()

    local footer = Theme.CreateLabel(frame, "tiny", "dim")
    footer:SetPoint("BOTTOMLEFT", PADDING, 14)
    footer:SetPoint("BOTTOMRIGHT", -PADDING, 14)
    footer:SetText(L["Changes save as you make them."])
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
    subtitle:SetText(L["Settings"])

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

    pages:Section("gear", 1, L["JUDGING GEAR"])

    local specRow = pages:Row("gear", 1, L["Judge Gear As:"], function() return SettingsUI:SpecHint() end)
    controls.spec = Widgets.CreateStepper(specRow, {
        min = 1, max = #SettingsUI:SpecChoices(), step = 1, value = 1,
        format = function(index)
            local choices, specs = SettingsUI:SpecChoices()
            local key = choices[index]
            if key == "auto" or not key then return L["Auto"] end
            return ns.Weights.Label(specs[key].name)
        end,
        onChange = function(index)
            local choices = SettingsUI:SpecChoices()
            SettingsUI:SetSpec(choices[index] or "auto")
        end,
    })
    controls.spec:SetWidth(150)
    controls.spec:SetPoint("TOPLEFT", CONTROL_X, 0)
    self.specRow = specRow

    local weightsRow = pages:Row("gear", 1, L["Stat Weights:"],
        L["How much each stat counts for any class and spec."])
    controls.weights = Widgets.CreateButton(weightsRow, L["Change"], function()
        if ns.WeightsUI then ns.WeightsUI:Show() end
    end, { width = 120, height = 20 })
    controls.weights:SetPoint("TOPLEFT", CONTROL_X, 0)
    self.weightsRow = weightsRow

    local tooltipRow = pages:Row("gear", 1, L["Tooltip Line:"],
        L["Says if gear beats what you wear."])
    controls.tooltip = Tick(tooltipRow, L["Show"], "tooltipLine", true)

    local arrowRow = pages:Row("gear", 1, L["Upgrade Arrows:"],
        L["A green arrow on upgrades you can wear now."])
    controls.arrows = Tick(arrowRow, L["Show"], "bagArrows", true, function()
        if ns.BagIcons then pcall(ns.BagIcons.Refresh, ns.BagIcons) end
        if ns.QuestRewards then pcall(ns.QuestRewards.Refresh, ns.QuestRewards) end
        if ns.LootRolls then pcall(ns.LootRolls.Refresh, ns.LootRolls) end
        if ns.MoreMarks then
            pcall(ns.MoreMarks.RefreshMerchant, ns.MoreMarks)
            pcall(ns.MoreMarks.RefreshLoot, ns.MoreMarks)
        end
    end)

    local coinRow = pages:Row("gear", 1, L["Sell Coins:"],
        L["A gold coin on bag gear that's no upgrade and sells to a vendor."])
    controls.sellCoins = Tick(coinRow, L["Show"], "bagSellCoins", true, function()
        if ns.BagIcons then pcall(ns.BagIcons.Refresh, ns.BagIcons) end
    end)

    local takeRow = pages:Row("gear", 1, L["Take Reward Button:"],
        L["A button under the quest window takes the best reward."])
    controls.rewardButton = Tick(takeRow, L["Show"], "rewardButton", true, function()
        if ns.QuestRewards then pcall(ns.QuestRewards.UpdateTake, ns.QuestRewards) end
    end)

    local chatRow = pages:Row("gear", 1, L["Upgrades in Chat:"],
        L["A chat line when an upgrade lands in your bags."])
    controls.upgradeChat = Tick(chatRow, L["On"], "upgradeChat", true)
    self.chatRow = chatRow

    local autoRow = pages:Row("gear", 1, L["Put On Upgrades:"],
        L["Puts an upgrade on as soon as you get it. Gear that would bind waits for your click."])
    controls.autoEquip = Tick(autoRow, L["On"], "autoEquip", false)

    -- Characters skipped for upgrades (a player asked, the owner agreed
    -- 2026-10-14): pick one by its whole name, then tick it.
    pages:Section("gear", 1, L["YOUR CHARACTERS"])
    local pickRow = pages:Row("gear", 1, L["Character:"],
        L["Each character shows here after it logs in with Equipment."])
    controls.skipPicker = SettingsUI.CharacterPicker(pickRow, CONTROL_X, function() SettingsUI:RefreshSkip() end)

    local skipRow = pages:Row("gear", 1, L["Skip Upgrades:"],
        function() return SettingsUI:SkipHint() end)
    controls.skipUpgrades = Widgets.CreateCheckbox(skipRow, L["Skip"], function(checked)
        local entry = controls.skipPicker:GetEntry()
        if entry and ns.Alts then ns.Alts:SetSkipped(entry.key, checked) end
    end, false)
    controls.skipUpgrades:SetPoint("TOPLEFT", CONTROL_X, -2)
    self.skipRow = skipRow

    pages:Section("gear", 2, L["GEAR WINDOW"])

    local windowRow = pages:Row("gear", 2, L["Gear Window:"], "")
    controls.openWindow = Widgets.CreateButton(windowRow, L["Open"], function()
        ns.HandleSlash("window")
    end, { width = 100, height = 20, primary = true })
    controls.openWindow:SetPoint("TOPLEFT", CONTROL_X, 0)

    pages:Section("gear", 2, L["BAGS AND TOOLTIPS"])

    local gamepadRow = pages:Row("gear", 2, L["Hide Controller Bag Button:"],
        L["Hides the controller button over your backpack's sort button."])
    controls.hideGamepadBag = Tick(gamepadRow, L["On"], "hideGamepadBag", true, function()
        if ns.BagIcons then pcall(ns.BagIcons.ApplyGamepadBag, ns.BagIcons) end
    end)

    local suffixRow = pages:Row("gear", 2, L["Random Roll Names:"],
        L["Adds a green's roll, like of the Monkey, to its tooltip."])
    controls.suffixLine = Tick(suffixRow, L["Show"], "suffixLine", true)

    local altRow = pages:Row("gear", 2, L["Upgrades for Alts:"],
        L["Names the other character an item helps most."])
    controls.altTooltipLine = Tick(altRow, L["Show"], "altTooltipLine", true)

    local enchantRow = pages:Row("gear", 2, L["Best Enchant:"],
        L["Names the best enchant for a piece you wear."])
    controls.enchantTooltip = Tick(enchantRow, L["Show"], "enchantTooltip", true, function()
        if ns.Tooltip and ns.Tooltip.ForgetLines then ns.Tooltip.ForgetLines() end
    end)

    local weaponsRow, weaponsButton = CommandRow(pages, "gear", 2, L["Untrained Weapons:"],
        function() return SettingsUI:WeaponsHint() end, L["Show"], "weapons show")
    controls.weapons = weaponsButton
    self.weaponsRow = weaponsRow

    pages:Section("gear", 2, L["CLASS TRAINING"])

    local trainingRow = pages:Row("gear", 2, L["Class Training:"],
        L["The Training button shows spells you can learn and their cost. Visit a class trainer once so prices show."])
    controls.classTraining = Widgets.CreateCheckbox(trainingRow, L["Show"], function(checked)
        ns.ClassTraining:SetOn(checked)
        if not checked and ns.TrainingDrawer then ns.TrainingDrawer:Hide() end
    end, ns.ClassTraining:IsOn())
    controls.classTraining:SetPoint("TOPLEFT", CONTROL_X, -2)
end

--- Steps through the player's characters by whole name, wrapped rather
--- than cut short (Butler's picker). :SetEntries(list of { key, name }),
--- :GetEntry().
function SettingsUI.CharacterPicker(row, x, onChange)
    local picker = CreateFrame("Frame", nil, row)
    picker:SetSize(180, 24)
    picker:SetPoint("TOPLEFT", x, 0)
    picker.entries, picker.index = {}, 1

    local text = Theme.CreateLabel(picker, "small", "text", "CENTER")
    text:SetPoint("LEFT", 26, 0)
    text:SetPoint("RIGHT", -26, 0)
    text:SetWordWrap(true)

    local function Show()
        local count = #picker.entries
        picker.index = math.max(1, math.min(picker.index, math.max(1, count)))
        local entry = picker.entries[picker.index]
        text:SetText(entry and (entry.name or L["A character not seen yet"]) or L["No characters yet"])
        picker.prev:SetDimmed(picker.index <= 1)
        picker.next:SetDimmed(picker.index >= count)
    end

    local function Step(direction)
        local wanted = picker.index + direction
        if wanted < 1 or wanted > #picker.entries then return end
        picker.index = wanted
        Show()
        if onChange then onChange() end
    end

    picker.prev = Widgets.CreateButton(picker, "<", function() Step(-1) end, { width = 22, height = 20 })
    picker.prev:SetPoint("LEFT", 0, 0)
    picker.next = Widgets.CreateButton(picker, ">", function() Step(1) end, { width = 22, height = 20 })
    picker.next:SetPoint("RIGHT", 0, 0)

    function picker:SetEntries(entries)
        local current = self.entries[self.index]
        self.entries = entries
        self.index = 1
        for index, entry in ipairs(entries) do
            if current and entry.key == current.key then self.index = index end
        end
        Show()
    end

    function picker:GetEntry()
        return self.entries[self.index]
    end

    Show()
    return picker
end

--- What the Skip upgrades row says: what it does, and who is skipped.
function SettingsUI:SkipHint()
    local names = ns.Alts and ns.Alts:SkippedNames() or {}
    if #names == 0 then
        return L["Good for a crafting alt. It never hears about upgrades or gets your other characters' gear."]
    end
    return L.Format("Good for a crafting alt. It never hears about upgrades or gets your other characters' gear. Skipped now: %s.",
        table.concat(names, ", "))
end

--- The picker's characters and the tick for the one shown.
function SettingsUI:RefreshSkip()
    local controls = self.controls
    if not (controls and controls.skipPicker and ns.Alts) then return end
    controls.skipPicker:SetEntries(ns.Alts:Characters())
    local entry = controls.skipPicker:GetEntry()
    controls.skipUpgrades:SetChecked(entry ~= nil and ns.Alts:IsSkipped(entry.key))
    controls.skipUpgrades:SetAlpha(entry and 1 or 0.45)
    if self.skipRow then self.skipRow:SetDescription(self:SkipHint()) end
end

--- What the Untrained weapons row says: which types this character
--- ignores, if any.
function SettingsUI:WeaponsHint()
    local skills = ns.WeaponSkills
    local names = skills and skills:IgnoredNames() or {}
    if #names == 0 then
        return L["Weapons you haven't trained still show as upgrades, with where to learn them."]
    end
    return L.Format("Ignored until you train them: %s. Show brings them back.",
        table.concat(names, ", "))
end

-- The upgrade hunt switches: saved key, page column, label, what it does,
-- the tick box's words, and the module to tell when it changes.
local HUNTING = {
    { "slotUpgrades", 1, L["Character Sheet:"],
        L["Hover a gear slot to see its upgrades."], L["Show"] },
    { "upgradeToast", 1, L["Upgrade Banner:"], "", L["Show"] },
    { "showTracker", 2, L["Upgrade Tracker:"],
        L["The panel of upgrades you're tracking."], L["Show"], "TrackerPanel" },
    { "mapPins", 2, L["Map Pins:"],
        L["Shows where each tracked upgrade comes from."], L["Show"], "MapPins" },
}

--- Upgrade hunts: finding upgrades on the left, tracking them on the right.
function SettingsUI:BuildHunts()
    local controls = self.controls
    local pages = self.pages

    pages:Section("hunts", 1, L["FINDING UPGRADES"])

    local _, findButton = CommandRow(pages, "hunts", 1, L["Where to Get Upgrades:"], "",
        L["Open"], "find", { primary = true })
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

    pages:Section("hunts", 2, L["TRACKING"])

    HuntRow(HUNTING[3])
    HuntRow(HUNTING[4])
end

--- The upgrade quest on the left, the arrow that leads there on the right.
function SettingsUI:BuildQuest()
    local controls = self.controls
    local pages = self.pages

    pages:Section("quest", 1, L["UPGRADE QUEST"])

    -- Off unless the player turns it on, unlike the switches on the other
    -- pages.
    local questRow = pages:Row("quest", 1, L["Upgrade Quest:"],
        L["A quest for your best next upgrade, with steps to get it."])
    controls.upgradeQuest = Widgets.CreateCheckbox(questRow, L["On"], function(checked)
        if ns.UpgradeQuest then ns.UpgradeQuest:SetEnabled(checked) end
    end, false)
    controls.upgradeQuest:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Ignore, Switch and the tab to show are on the panel itself, and stay
    -- typed (/beq quest ignore, switch, vendor...); the owner, 2026-10-15.
    local panelRow = pages:Row("quest", 1, L["Quest Panel:"],
        L["Ignored lists upgrades you skipped, so you can bring them back."])
    self.questPanelRow = panelRow
    controls.questOpen = Widgets.CreateButton(panelRow, L["Open"], function()
        ns.HandleSlash("quest")
    end, { width = 64, height = 20 })
    controls.questOpen:SetPoint("TOPLEFT", CONTROL_X, 0)
    -- The list of ignored upgrades, each with Restore, and Restore all
    -- (UI/IgnoredWindow.lua).
    controls.questReset = Widgets.CreateButton(panelRow, L["Ignored"], function()
        ns.HandleSlash("quest ignored")
    end, { width = 84, height = 20 })
    controls.questReset:SetPoint("LEFT", controls.questOpen, "RIGHT", 12, 0)

    -- The upgrade quest panel's size, as its gold corner grip and /beq quest
    -- size set it (the owner asked 2026-10-07). The size in use is lit green.
    local questSizeRow = pages:Row("quest", 1, L["Panel Size:"], "")
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
        button.scale = size.scale
        controls.questSizes[#controls.questSizes + 1] = button
        previous = button
    end

    -- Two switches that are also tick boxes on the quest panel: Solo only
    -- (the same as in Where to get upgrades) and Zone swap, the panel's
    -- "Change on a new zone" (the owner asked 2026-10-08), side by side.
    local soloRow = pages:Row("quest", 1, L["Quest Filters:"],
        L["Solo Only skips group quests. Zone Swap picks new quests in each new zone while This Zone Only is ticked."])
    controls.soloQuests = Widgets.CreateCheckbox(soloRow, L["Solo Only"], function(checked)
        if ns.Finder then ns.Finder:SetSoloOnly(checked) end
    end, false)
    controls.soloQuests:SetPoint("TOPLEFT", CONTROL_X, -2)
    controls.questZoneSwap = Widgets.CreateCheckbox(soloRow, L["Zone Swap"], function(checked)
        if ns.UpgradeQuest then ns.UpgradeQuest:SetZoneSwap(checked) end
    end, true)
    -- Past the first box however long its words run (German runs longer).
    controls.questZoneSwap:SetPoint("TOPLEFT", CONTROL_X + math.max(92, controls.soloQuests:GetWidth() + 12), -2)

    -- The panel's "Current step only" (the owner asked 2026-10-13).
    local stepsRow = pages:Row("quest", 1, L["Current Step Only:"],
        L["The panel shows only the step to do now."])
    controls.questStepOnly = Widgets.CreateCheckbox(stepsRow, L["On"], function(checked)
        if ns.UpgradeQuest then ns.UpgradeQuest:SetStepOnly(checked) end
    end, false)
    controls.questStepOnly:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- The quest arrow, as the Arrow button on the quest panel and /beq
    -- arrow switch it, and /beq arrow check and next as buttons.
    pages:Section("quest", 2, L["QUEST ARROW"])

    local arrowRow = pages:Row("quest", 2, L["Quest Arrow:"],
        L["Points the way to the quest's next place. Click a step to aim it."])
    controls.questArrow = Widgets.CreateCheckbox(arrowRow, L["Show"], function(checked)
        if ns.QuestArrow then ns.QuestArrow:SetOn(checked) end
    end, false)
    controls.questArrow:SetPoint("TOPLEFT", CONTROL_X, -2)
    controls.questArrowCheck = Widgets.CreateButton(arrowRow, L["Check"], function()
        ns.HandleSlash("arrow check")
    end, { width = 64, height = 20 })
    controls.questArrowCheck:SetPoint("TOPLEFT", CONTROL_X + math.max(96, controls.questArrow:GetWidth() + 12), 0)
    Explain(controls.questArrowCheck, L["Check the quest arrow"],
        L["Lists in chat what the arrow can read where you stand."])

    local _, nextButton = CommandRow(pages, "quest", 2, L["Next Place:"],
        L["Points the arrow at the next step's place."],
        L["Next"], "arrow next")
    controls.questArrowNext = nextButton

    -- TomTom's arrow instead of the dial, when TomTom is installed.
    local tomtomRow = pages:Row("quest", 2, L["Use TomTom:"],
        L["With TomTom installed, its arrow shows the way instead."])
    controls.useTomTom = Widgets.CreateCheckbox(tomtomRow, L["On"], function(checked)
        if ns.TomTom then ns.TomTom:SetOn(checked) end
    end, true)
    controls.useTomTom:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- The panel's Quest log tab (UI/QuestLogTab.lua) and its two tick boxes.
    pages:Section("quest", 2, L["QUEST LOG"])

    local logRow = pages:Row("quest", 2, L["Quest Log:"],
        L["Your quests on a tab of the quest panel."])
    controls.questLogOpen = Widgets.CreateButton(logRow, L["Show"], function()
        ns.HandleSlash("quest log")
    end, { width = 64, height = 20 })
    controls.questLogOpen:SetPoint("TOPLEFT", CONTROL_X, 0)
    controls.questLogTracked = Widgets.CreateCheckbox(logRow, L["Tracked Only"], function(checked)
        if ns.QuestLogUI then ns.QuestLogUI:SetTrackedOnly(checked) end
    end, false)
    controls.questLogTracked:SetPoint("TOPLEFT", CONTROL_X + math.max(76, controls.questLogOpen:GetWidth() + 12), -2)

    local trackerRow = pages:Row("quest", 2, L["Hide Game's Tracker:"],
        L["Hides the game's quest tracker while the panel is up."])
    controls.hideQuestTracker = Widgets.CreateCheckbox(trackerRow, L["On"], function(checked)
        if ns.QuestLogUI then ns.QuestLogUI:SetHidesTracker(checked) end
    end, false)
    controls.hideQuestTracker:SetPoint("TOPLEFT", CONTROL_X, -2)
end

--- General: windows and text on the left, help and problems on the right.
function SettingsUI:BuildGeneral()
    local controls = self.controls
    local pages = self.pages

    pages:Section("general", 1, L["WINDOWS"])

    -- The minimap button always shows (the owner, 2026-10-15); a saved
    -- minimapHidden is kept but no longer read.
    local positionRow = pages:Row("general", 1, L["Window Positions:"],
        L["Reset the UI windows to their defaults."])
    local reset = Widgets.CreateButton(positionRow, L["Set Default"], function()
        SettingsUI:ResetPositions()
        ns.Print(L["UI windows set to defaults."])
    end, { width = 100, height = 20 })
    reset:SetPoint("TOPLEFT", CONTROL_X, 0)
    controls.resetPositions = reset

    -- Bigger letters in the same windows, as Tradeskills has. Every size
    -- is read as text is drawn, so it waits for /reload.
    local textRow = pages:Row("general", 1, L["Text Size:"], "")
    controls.textSize = ns.SettingsPages.TextSizeControl(textRow, CONTROL_X, function() return ns.db end)

    -- Asked 2026-10-10: the game's own look for players who would rather
    -- the windows matched the rest of their screen. Read at login, so it
    -- waits for /reload as Text size does. See UI/BlizzardLook.lua. A
    -- stepper, as Text size is: this addon's Widgets have no dropdown.
    local styleRow = pages:Row("general", 1, L["Window Style:"], "")
    controls.windowStyle = self:WindowStyleControl(styleRow)

    pages:Section("general", 2, L["ADVANCED"])

    local debugRow = pages:Row("general", 2, L["Debug:"],
        L["Extra chat messages to help track down a problem."])
    controls.debug = Tick(debugRow, L["On"], "debug", false)

    -- Core/SisterNote.lua: one chat line, once, naming the Blackthornes
    -- addons the player does not have. Off here is off in all of them.
    local sistersRow = pages:Row("general", 2, L["Sister Addons:"],
        L["Says once in chat which Blackthornes addons you don't have."])
    controls.sisters = Widgets.CreateCheckbox(sistersRow, L["On"], function(checked)
        ns.SisterNote:SetOn(checked)
    end, true)
    controls.sisters:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- UI/WhatsNew.lua: one window after an update for every Blackthornes
    -- addon. Off here is off in all of them, as the sister note is.
    local _, whatsNewButton = CommandRow(pages, "general", 2, L["What's New:"], "",
        L["Open"], "whatsnew")
    controls.whatsnew = whatsNewButton

    local whatsNewRow = pages:Row("general", 2, L["What's New After Updates:"],
        L["Opens What's New the first time you play after an update."])
    controls.whatsNewPopup = Widgets.CreateCheckbox(whatsNewRow, L["On"], function(checked)
        ns.WhatsNew:SetOn(checked)
    end, true)
    controls.whatsNewPopup:SetPoint("TOPLEFT", CONTROL_X, -2)

    local whatsNewMotionRow = pages:Row("general", 2, L["What's New Motion:"], "")
    controls.whatsNewMotion = Widgets.CreateCheckbox(whatsNewMotionRow, L["On"], function(checked)
        ns.WhatsNew:SetMotionOn(checked)
    end, true)
    controls.whatsNewMotion:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- /beq perf and /beq perf clear as buttons.
    local speedRow = pages:Row("general", 2, L["Speed Check:"],
        L["If the game hitches, lists in chat what took longest."])
    controls.perfShow = Widgets.CreateButton(speedRow, L["Show"], function()
        ns.HandleSlash("perf")
    end, { width = 64, height = 20 })
    controls.perfShow:SetPoint("TOPLEFT", CONTROL_X, 0)
    controls.perfClear = Widgets.CreateButton(speedRow, L["Clear"], function()
        ns.HandleSlash("perf clear")
    end, { width = 64, height = 20 })
    controls.perfClear:SetPoint("LEFT", controls.perfShow, "RIGHT", 12, 0)
    Explain(controls.perfClear, L["Start the count again"],
        L["The next Show counts from now."])

    local _, probeButton = CommandRow(pages, "general", 2, L["Client Check:"],
        L["Lists in chat what the game lets Equipment read."],
        L["Check"], "probe")
    controls.probe = probeButton
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
    reload = Widgets.CreateButton(row, L["Reload"], function()
        if ReloadUI then ReloadUI() end
    end, { width = 60, height = 20 })
    ns.SettingsPages.ReloadUnder(row, stepper, reload)
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
    controls.debug:SetChecked(ns.db.debug == true)
    controls.sisters:SetChecked(ns.SisterNote:IsOn())
    controls.whatsNewPopup:SetChecked(ns.WhatsNew:IsOn())
    controls.whatsNewMotion:SetChecked(ns.WhatsNew:IsMotionOn())
    controls.tooltip:SetChecked(ns.db.tooltipLine ~= false)
    controls.arrows:SetChecked(ns.db.bagArrows ~= false)
    controls.sellCoins:SetChecked(ns.db.bagSellCoins ~= false)
    controls.hideGamepadBag:SetChecked(ns.db.hideGamepadBag ~= false)
    controls.upgradeChat:SetChecked(ns.db.upgradeChat ~= false)
    controls.autoEquip:SetChecked(ns.db.autoEquip == true)
    controls.rewardButton:SetChecked(ns.db.rewardButton ~= false)
    controls.suffixLine:SetChecked(ns.db.suffixLine ~= false)
    controls.altTooltipLine:SetChecked(ns.db.altTooltipLine ~= false)
    controls.enchantTooltip:SetChecked(ns.db.enchantTooltip ~= false)
    self:RefreshSkip()
    controls.classTraining:SetChecked(ns.ClassTraining:IsOn())
    for _, entry in ipairs(HUNTING) do
        controls[entry[1]]:SetChecked(ns.db[entry[1]] ~= false)
    end
    controls.upgradeQuest:SetChecked(ns.db.upgradeQuest == true)
    controls.questArrow:SetChecked(ns.db.questArrow == true)
    controls.useTomTom:SetChecked(ns.db.useTomTom ~= false)
    controls.questLogTracked:SetChecked(ns.db.questLogTrackedOnly == true)
    controls.hideQuestTracker:SetChecked(ns.db.hideQuestTracker == true)
    self:RefreshQuestSize()
    if self.weaponsRow then self.weaponsRow:SetDescription(self:WeaponsHint()) end
    controls.soloQuests:SetChecked(ns.db.soloQuestsOnly == true)
    controls.questZoneSwap:SetChecked(ns.db.upgradeQuestZoneSwap ~= false)
    controls.questStepOnly:SetChecked(ns.db.upgradeQuestStepOnly == true)
    local quest = ns.UpgradeQuest
    if quest and self.questPanelRow then
        local count = 0
        for _ in pairs(quest:Skipped()) do count = count + 1 end
        controls.questReset:SetText(count > 0 and L.Format("Ignored (%d)", count) or L["Ignored"])
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

--- The quest panel's size buttons: the one in use is lit green.
function SettingsUI:RefreshQuestSize()
    local panel = ns.QuestPanel
    if not (panel and self.questSizeRow) then return end
    local scale = panel:GetScale()
    for _, button in ipairs(self.controls.questSizes) do
        button:SetLabelColor(math.abs(button.scale - scale) < 0.005 and "good" or "gilt")
    end
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
    blurb:SetText(L["Equipment's settings have a window of their own."])

    local open = Widgets.CreateButton(panel, L["Open Equipment settings"], function()
        -- The game's panel is left open: hiding one of its frames from here
        -- would run its own code as this addon. Ours opens on top of it.
        SettingsUI:Show()
    end, { width = 190, height = 24 })
    open:SetPoint("TOPLEFT", blurb, "BOTTOMLEFT", 0, -14)

    local hint = Theme.CreateLabel(panel, "small", "muted")
    hint:SetPoint("TOPLEFT", open, "BOTTOMLEFT", 0, -10)
    hint:SetText(L["Or type /beq settings, or click the minimap button."])

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

ns.RegisterCommand("settings", L["open the settings window"], function()
    SettingsUI:Toggle()
end)

-- Common names for the same thing, so a guess works. Kept out of the help
-- list, which would otherwise print the same line three times.
ns.commands.options = ns.commands.settings
ns.commands.config = ns.commands.settings
