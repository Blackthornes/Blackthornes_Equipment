-- Blackthornes Equipment -- UI/Settings.lua
-- The Settings tab of the Equipment window (UI/GearWindow.lua): every
-- switch the addon has, in one place.
--
-- A page of that window since rework step 6 (2026-11-23): it has no frame,
-- rim or spot of its own. Built on UI/SettingsPages.lua as in the sister
-- addons: two columns of rows a page, a row being [label .. control] on one
-- line, and what it does in the row's tooltip or, with Show descriptions
-- ticked, underneath it. Here the pages are picked from a list down the
-- left (SettingsUI:Rail), not along the top; the shared file is unchanged.
--
-- Stat Weights (UI/WeightsPage.lua) and Characters (UI/CharactersPage.lua)
-- are pages of it. Open it with /beq settings, a click on the Settings tab,
-- or from the game's own Options > AddOns list. Nothing here deletes
-- anything but Forget on the Characters page, which asks first.

local _, ns = ...
local L = ns.L

local SettingsUI = ns.NewModule("SettingsUI")

local Theme = ns.Theme
local Widgets = ns.Widgets

local PADDING = 18
-- The list of pages down the left.
local RAIL = 150
local RAIL_ROW = 26

local COLUMN_GAP = 18
-- Two columns in the room every page of the Equipment window has, beside
-- the list of pages; set again as the page is built.
local COLUMN_WIDTH = 330
local function TabColumnWidth()
    local width = ns.GearWindow and ns.GearWindow.WIDTH
    if type(width) ~= "number" then return COLUMN_WIDTH end
    return math.floor((width - RAIL - PADDING * 2 - COLUMN_GAP) / 2)
end
-- Where the controls start: room for a label like "Upgrade Arrows:" in the
-- game's font, which runs wider than it looks. A longer one wraps.
local CONTROL_X = 150

local TITLE = "Blackthornes Equipment"

-- The pages, top to bottom. Every setting kept its saved name; only its
-- place moved. This addon's own pages first, then the ones every
-- Blackthornes addon has, in the house order. A saved page from before
-- still opens: "gear", "quest", "general", "all" and "about" kept their
-- keys.
local PAGES = {
    { key = "gear", text = L["GEAR"],
      tip = L["How gear is judged, and the arrows, tooltip lines and chat lines that say so"] },
    { key = "weights", text = L["STAT WEIGHTS"] },
    { key = "quest", text = L["UPGRADE QUEST"],
      tip = L["The upgrade quest, its panel and the arrow that points the way"] },
    { key = "characters", text = L["CHARACTERS"] },
    { key = "tooltips", text = L["TOOLTIPS"] },
    { key = "general", text = L["WINDOWS"],
      tip = L["Window size and how much the panels let the world show through"] },
    -- Reached by the one window's gear while One Window is on, so it is
    -- left off the list then.
    { key = "all", text = L["ALL ADDONS"] },
    { key = "about", text = L["ABOUT"],
      tip = L["How these addons are made, the version, the Discord and the other Blackthornes addons"] },
}
SettingsUI.PAGES = PAGES
SettingsUI.RAIL = RAIL

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

--- The Off Spec keys this character can pick from, "none" first.
function SettingsUI:OffSpecChoices()
    local choices = { "none" }
    local class = ns.Weights:PlayerClass()
    local specs = class and ns.Weights.SPECS[class]
    if specs then
        for _, key in ipairs(specs.order) do choices[#choices + 1] = key end
    end
    return choices, specs
end

--- Pick the Off Spec (`key`, or "none"). Logic/OffSpec.lua.
function SettingsUI:SetOffSpec(key)
    if ns.OffSpec then ns.OffSpec:Set(key ~= "none" and key or nil) end
    self:Refresh()
end

--- The Off Spec drop-down's index for the saved pick.
function SettingsUI:OffSpecIndex()
    local choices = self:OffSpecChoices()
    local picked = ns.charDB and ns.charDB.offSpec
    for i, key in ipairs(choices) do
        if key == picked then return i end
    end
    return 1
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
    { "gearSheetSpot" },
    { "trackerPoint", "trackerRelativePoint", "trackerX", "trackerY" },
    { "questPoint", "questRelativePoint", "questX", "questY" },
    { "questArrowX", "questArrowY" },
    { "ignoredPoint", "ignoredRelativePoint", "ignoredX", "ignoredY" },
    { "dungeonQuestsPoint", "dungeonQuestsRelPoint", "dungeonQuestsX", "dungeonQuestsY" },
    { "dungeonLootPoint", "dungeonLootRelPoint", "dungeonLootX", "dungeonLootY" },
}

--- Put every Equipment window back where it started: the Equipment
--- window, the small panel and the quest arrow. Only the saved spots are
--- cleared (the old windows' too); nothing else is touched. Laid into the
--- one window, the Equipment window stays there.
function SettingsUI:ResetPositions()
    for _, keys in ipairs(POSITION_KEYS) do
        for _, key in ipairs(keys) do ns.db[key] = nil end
    end
    for _, module in ipairs({ ns.GearWindow, ns.SmallPanel, ns.QuestArrowUI }) do
        if module and module.frame and module.RestorePosition then
            module:RestorePosition()
        end
    end
end

--- Every Blackthornes window back where it started, in every addon loaded
--- (the owner, 2026-11-12): the one window, its docked spots, the small
--- windows and each addon's own. Settings and data stay the same.
function SettingsUI:ResetAllWindows()
    local shared = ns.SharedWindow
    if shared and shared.ResetAllSpots then
        shared.ResetAllSpots()
    else
        SettingsUI:ResetPositions()
    end
    ns.Print(L["Every window is back in its first spot."])
end

if ns.SharedWindow and ns.SharedWindow.AddSpotReset then
    ns.SharedWindow.AddSpotReset("Equipment", function() SettingsUI:ResetPositions() end)
end

--------------------------------------------------------------------------------
-- Equipment Settings: Set Default (the owner said build it, 2026-11-23)
--------------------------------------------------------------------------------

--- Every saved key a Settings control writes, and only those. Data, window
--- spots and the ALL ADDONS choices the five addons share are left out on
--- purpose. tools/test_restoredefaults.lua clicks every control and fails
--- if one writes a key missing here.
SettingsUI.SETTING_KEYS = {
    "altTooltipLine", "arrowRoute", "autoEquip", "bagArrows", "bagSellCoins",
    "classTraining", "dropsTooltip", "enchantTooltip", "finderAhead",
    "finderGetNow", "finderScale", "finderShow", "finderZoneOnly",
    "hideQuestTracker", "mapPins", "questArrow", "questArrowSize",
    "questLevelsAbove", "questLogTrackedOnly", "questScale", "rewardButton",
    "settingsDescriptions", "showTracker", "slotUpgrades", "soloQuestsOnly",
    "suffixLine", "swapAtDoors", "tooltipLine", "tooltipShift", "upgradeChat",
    "upgradeQuest", "upgradeQuestBiggest", "upgradeQuestStepOnly",
    "upgradeQuestStyle", "upgradeQuestZoneOnly", "upgradeQuestZoneSwap",
    "upgradeToast", "useTomTom",
}

--- The same, for keys saved for one character.
SettingsUI.CHAR_SETTING_KEYS = {
    "bestArmorOnly", "hideUntrainedWeapons", "ignoredWeaponTypes", "spec", "offSpec",
}

--- How long the red Confirm waits for the second click, in seconds.
SettingsUI.CONFIRM_WAIT = 4

--- Puts every Equipment setting back to how it started, then reloads the
--- game's interface so every window reads them again. Saved data stays.
function SettingsUI:RestoreDefaults()
    local db, defaults = ns.db, ns.DEFAULTS or {}
    if type(db) ~= "table" then return false end
    for _, key in ipairs(SettingsUI.SETTING_KEYS) do
        local value = defaults[key]
        if type(value) == "table" and CopyTable then value = CopyTable(value) end
        db[key] = value
    end
    if type(ns.charDB) == "table" then
        local charDefaults = ns.CHAR_DEFAULTS or {}
        for _, key in ipairs(SettingsUI.CHAR_SETTING_KEYS) do
            ns.charDB[key] = charDefaults[key]
        end
    end

    -- Said after the reload, once.
    db.settingsRestored = true
    if type(ReloadUI) == "function" then
        ReloadUI()
    else
        self:SayRestored()
    end
    return true
end

--- The chat line after Set Default, said once.
function SettingsUI:SayRestored()
    if not (ns.db and ns.db.settingsRestored) then return end
    ns.db.settingsRestored = nil
    ns.Print(L["Every Equipment setting is back to how it started."])
end

--- A button that turns red and says Confirm on the first click, and runs
--- `onConfirm` on a second click within CONFIRM_WAIT seconds.
function SettingsUI.ConfirmButton(parent, text, onConfirm, width)
    local button, armedAt
    local function Now()
        if type(GetTime) ~= "function" then return nil end
        local ok, now = pcall(GetTime)
        return ok and type(now) == "number" and now or nil
    end
    local function Arm(on, at)
        button.armed, armedAt = on, at
        button:SetText(on and L["Confirm"] or text)
        -- Red words while it waits for the second click.
        if button.SetLabelColor then button:SetLabelColor(on and "loss" or nil) end
    end
    button = Widgets.CreateButton(parent, text, function()
        local now = Now()
        if button.armed and (not armedAt or not now
            or now - armedAt <= SettingsUI.CONFIRM_WAIT) then
            Arm(false, nil)
            onConfirm()
            return
        end
        Arm(true, now)
        if now and C_Timer and type(C_Timer.After) == "function" then
            pcall(C_Timer.After, SettingsUI.CONFIRM_WAIT, function()
                local later = Now()
                if button.armed and armedAt and later
                    and later - armedAt >= SettingsUI.CONFIRM_WAIT then
                    Arm(false, nil)
                end
            end)
        end
    end, { width = width, height = 20 })
    button.armed = false
    return button
end
--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

--- The list of pages down the left, in place of the shared file's switch
--- along the top: each name a dark glass row, the one showing lit with a
--- gold left edge. Done on this one set of pages, so the file every addon
--- shares stays as it is.
function SettingsUI:Rail(pages)
    local frame = self.frame
    local opts = pages.opts
    local top = opts.top + pages:BarHeight() + 14

    local rail = CreateFrame("Frame", nil, frame)
    rail:SetPoint("TOPLEFT", 0, -top)
    rail:SetPoint("BOTTOMLEFT", 0, opts.bottom or 0)
    rail:SetWidth(RAIL)
    Theme.Fill(rail, "glass")
    local side = rail:CreateTexture(nil, "ARTWORK")
    side:SetPoint("TOPRIGHT")
    side:SetPoint("BOTTOMRIGHT")
    side:SetWidth(1)
    side:SetColorTexture(Theme.Unpack("border", 0.6))
    self.rail = rail

    for _, part in ipairs(pages.switch) do
        local button = part.button
        button:SetParent(rail)
        button:SetWidth(RAIL - 1)
        button:SetHeight(RAIL_ROW)
        part.back = Theme.Fill(button, "glass")
        local under = button:CreateTexture(nil, "BACKGROUND", nil, 1)
        under:SetPoint("BOTTOMLEFT")
        under:SetPoint("BOTTOMRIGHT")
        under:SetHeight(1)
        under:SetColorTexture(Theme.Unpack("border", 0.6))
        -- The gold line that sat under the name stands down its left.
        part.underline:ClearAllPoints()
        part.underline:SetPoint("TOPLEFT")
        part.underline:SetPoint("BOTTOMLEFT")
        part.underline:SetWidth(3)
        part.edge = button:CreateTexture(nil, "ARTWORK")
        part.edge:SetPoint("TOPLEFT")
        part.edge:SetPoint("BOTTOMLEFT")
        part.edge:SetWidth(3)
        part.edge:SetColorTexture(Theme.Unpack("accent"))
        part.edge:Hide()
        part.glow:Hide()
        part.label:ClearAllPoints()
        part.label:SetPoint("LEFT", 12, 0)
        part.label:SetPoint("RIGHT", -6, 0)
        part.label:SetJustifyH("LEFT")
    end

    -- One under the other, the hidden ones skipped. Never more than one
    -- line of bar, so the pages never move.
    pages.LayoutSwitch = function(list)
        local place = 0
        for _, part in ipairs(list.switch) do
            local hidden = list:Hidden(part.key)
            part.button:SetShown(not hidden)
            if not hidden then
                part.button:ClearAllPoints()
                part.button:SetPoint("TOPLEFT", rail, "TOPLEFT", 0, -place * RAIL_ROW)
                place = place + 1
                part.place = place
            end
        end
        list.lines = 1
        return false
    end

    -- The window is as wide as the list, the two columns and the bar's
    -- search box and tick box need.
    pages.BarWidth = function(list)
        return math.max(RAIL + opts.padding * 2 + opts.columnWidth * 2 + opts.columnGap,
            opts.padding * 2 + list:ToolsWidth())
    end

    local paint = pages.Paint
    pages.Paint = function(list)
        paint(list)
        local current = list:Current()
        for _, part in ipairs(list.switch) do
            local active = part.key == current
            local over = part.hovered == true and not active
            part.glow:Hide()
            part.back:SetColorTexture(Theme.Unpack(active and "glassActive" or over and "glassHover"
                or ((part.place or 1) % 2 == 0 and "glassAlt" or "glass")))
            part.edge:SetShown(over)
        end
    end

    -- Stat Weights and Characters draw their own page: each is put in step
    -- as it is shown, by a click here or by SettingsUI:Refresh.
    local show = pages.Show
    function pages:Show(key)
        show(self, key)
        local module = self.shown == "weights" and ns.WeightsPage
            or self.shown == "characters" and ns.CharactersPage
        if module and module.Refresh then module:Refresh() end
    end

    -- The pages sit right of the list.
    pages.view:ClearAllPoints()
    pages.view:SetPoint("TOPLEFT", RAIL, -top)
    pages.view:SetPoint("BOTTOMRIGHT", 0, opts.bottom or 0)
    pages:LayoutSwitch()
end

--- Build the page in the Equipment window's page area. Asked without one,
--- the window is built first, which builds this.
function SettingsUI:Build(area)
    if self.frame then return self.frame end
    local Gear = ns.GearWindow
    if not area then
        if not Gear then return nil end
        Gear:Build()
        if self.frame then return self.frame end
        area = Gear.area
    end

    COLUMN_WIDTH = TabColumnWidth()
    local frame = CreateFrame("Frame", "BlackthornesEquipmentSettings", area)
    frame:SetAllPoints(area)
    Theme.Fill(frame, "window")
    frame:Hide()

    self.frame = frame
    self.controls = {}

    self.pages = ns.SettingsPages.New(frame, {
        pages = PAGES,
        top = 4,
        bottom = 30,
        padding = PADDING,
        columnWidth = COLUMN_WIDTH,
        columnGap = COLUMN_GAP,
        controlX = CONTROL_X,
        db = function() return ns.db end,
    })
    self:Rail(self.pages)
    self:BuildGear()
    self:BuildQuest()
    self:BuildTooltips()
    self:BuildGeneral()
    -- Stat Weights and Characters draw their own page.
    local pages = self.pages
    local wide = COLUMN_WIDTH * 2 + COLUMN_GAP
    if ns.WeightsPage then ns.WeightsPage:Build(pages, "weights", wide) end
    if ns.CharactersPage then ns.CharactersPage:Build(pages, "characters", wide) end
    -- About (UI/About.lua): the note on how the addons are made, then the
    -- version, the Discord and the other Blackthornes addons.
    if ns.About then
        pages:Section("about", 1, L["HOW THESE ADDONS ARE MADE"])
        local note = pages:Place("about", 1, ns.About:Note(pages.pages.about.content, COLUMN_WIDTH))
        pages:Searchable("about", note, note.words)
        pages:Section("about", 2, L["ABOUT"])
        local info = pages:Place("about", 2, ns.About:Info(pages.pages.about.content, COLUMN_WIDTH))
        pages:Searchable("about", info, info.words)
        self:BuildShareBox()
    end
    -- The pages ask the Equipment window for the width they need; a page
    -- taller than the window scrolls, so the window never grows taller.
    local fit = pages.Fit
    pages.Fit = function(page)
        fit(page)
        if Gear and page.need then Gear:Need("settings", page.need[1], nil) end
    end
    pages:Fit()

    local footer = Theme.CreateLabel(frame, "tiny", "dim")
    footer:SetPoint("BOTTOMLEFT", PADDING, 10)
    footer:SetPoint("BOTTOMRIGHT", -PADDING, 10)
    footer:SetText(L["Changes save as you make them."])
    self.footer = footer

    return frame
end

-- Logic/Contribute.lua: vendors and quest rewards sent to help the
-- shipped data, off until ticked, and offered only where it can send
-- (North America). Its words wrap under the box, since they run long.
function SettingsUI:BuildShareBox()
    if not (ns.Contribute and ns.Contribute:InRegion()) then return end
    local pages = self.pages
    local text = L["Share your data with Blackthornes to improve the Equipment AddOn."]
    local holder = CreateFrame("Frame", nil, pages.pages.about.content)
    holder:SetSize(COLUMN_WIDTH, 36)
    local box = Widgets.CreateCheckbox(holder, text, function(checked)
        ns.Contribute:SetOn(checked)
        SettingsUI:Refresh()
    end, false)
    box:SetPoint("TOPLEFT", 0, -2)
    box:SetWidth(COLUMN_WIDTH)
    box.label:ClearAllPoints()
    box.label:SetPoint("TOPLEFT", box, "TOPLEFT", 20, -1)
    box.label:SetWidth(COLUMN_WIDTH - 24)
    box.label:SetJustifyH("LEFT")
    if box.label.SetWordWrap then box.label:SetWordWrap(true) end
    local ok, tall = pcall(box.label.GetStringHeight, box.label)
    tall = ok and tonumber(tall) or 0
    if tall < 14 then tall = 28 end
    box:SetHeight(math.max(18, tall + 2))
    holder:SetHeight(math.max(18, tall + 2) + 6)
    pages:Place("about", 2, holder, -14)
    pages:Searchable("about", holder, text)
    self.controls.shareData = box
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

--- Off, Shift or Always for a tooltip line on `row` (UI/TooltipShift.lua).
--- Whether the line is on stays in `key`, saved as the tick box saved it;
--- only the Shift choice is new. `stepper:Sync()` reads it back silently.
local function ShiftStepper(row, key, lineKey)
    local Shift = ns.TooltipShift
    local function IsOn() return ns.db[key] ~= false end
    local stepper = Widgets.CreateChoice(row, {
        min = 0, max = 2, step = 1, value = Shift:Mode(IsOn(), lineKey),
        format = function(value) return Shift.NAMES[value] end,
        onChange = function(value)
            Shift:Apply(value, lineKey, IsOn(), function(on) ns.db[key] = on end)
            -- The kept lines were worked out with the old setting.
            if ns.Tooltip and ns.Tooltip.ForgetLines then ns.Tooltip.ForgetLines() end
        end,
    })
    ns.SettingsPages.FitStepper(stepper, Shift.NAMES)
    stepper:SetPoint("TOPLEFT", CONTROL_X, -2)
    function stepper:Sync()
        self:SetValue(Shift:Mode(IsOn(), lineKey), true)
    end
    return stepper
end

--- Gear: what shows on screen on the left, how gear is judged on the right.
function SettingsUI:BuildGear()
    local controls = self.controls
    local pages = self.pages

    -- Every on/off box for something on screen, in one grid (the owner,
    -- 2026-11-16). Each box keeps its saved key.
    self:BuildShowGrid()

    pages:Section("gear", 2, L["JUDGING GEAR"])

    local specRow = pages:Row("gear", 2, L["Main Spec:"], function() return SettingsUI:SpecHint() end)
    controls.spec = Widgets.CreateChoice(specRow, {
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

    -- The Off Spec (Logic/OffSpec.lua): starts on None, saved per character.
    local offRow = pages:Row("gear", 2, L["Off Spec:"], L["Pick None to turn it off. Starts on None."])
    controls.offSpec = Widgets.CreateChoice(offRow, {
        min = 1, max = #SettingsUI:OffSpecChoices(), step = 1, value = SettingsUI:OffSpecIndex(),
        format = function(index)
            local choices, specs = SettingsUI:OffSpecChoices()
            local key = choices[index]
            if key == "none" or not key or not specs or not specs[key] then return L["None"] end
            return ns.Weights.Label(specs[key].name)
        end,
        onChange = function(index)
            local choices = SettingsUI:OffSpecChoices()
            SettingsUI:SetOffSpec(choices[index] or "none")
        end,
    })
    controls.offSpec:SetWidth(150)
    controls.offSpec:SetPoint("TOPLEFT", CONTROL_X, 0)

    -- Saved per character, since the armor a class wears is its own.
    local armorRow = pages:Row("gear", 2, L["Best Armor Only:"],
        L["Only shows armor of the heaviest kind you can wear. Cloaks, rings, necks and trinkets still show."])
    controls.bestArmorOnly = Widgets.CreateCheckbox(armorRow, L["On"], function(checked)
        if ns.Compare then ns.Compare:SetBestArmorOnly(checked) end
    end, ns.Compare and ns.Compare.BestArmorOnly() or false)
    controls.bestArmorOnly:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Show or Hide for this character (a player's report, 2026-10-20: one
    -- Show button that only cleared the banner's ignored types read as
    -- broken). Hide also covers any type ignored from a banner; Show clears
    -- both.
    local weaponsRow = pages:Row("gear", 2, L["Untrained Weapons:"],
        function() return SettingsUI:WeaponsHint() end)
    local weaponNames = { [0] = L["Hide"], [1] = L["Show"] }
    local function WeaponsShown()
        local skills = ns.WeaponSkills
        return (skills and skills:AnyHidden()) and 0 or 1
    end
    controls.weapons = Widgets.CreateChoice(weaponsRow, {
        min = 0, max = 1, step = 1, value = WeaponsShown(),
        format = function(value) return weaponNames[value] end,
        onChange = function(value)
            local skills = ns.WeaponSkills
            if not skills then return end
            if value == 1 then skills:ShowAll(true) else skills:HideAll(true) end
            weaponsRow:SetDescription(SettingsUI:WeaponsHint())
        end,
    })
    ns.SettingsPages.FitStepper(controls.weapons, weaponNames)
    controls.weapons:SetPoint("TOPLEFT", CONTROL_X, -2)
    function controls.weapons:Sync()
        self:SetValue(WeaponsShown(), true)
    end
    self.weaponsRow = weaponsRow
end

--- Tooltips: the lines Equipment adds to an item's tooltip, each Off, on
--- Shift or Always, as every Blackthornes addon has them.
function SettingsUI:BuildTooltips()
    local controls = self.controls
    local pages = self.pages

    pages:Section("tooltips", 1, L["TOOLTIPS"])

    local tooltipRow = pages:Row("tooltips", 1, L["Tooltip Line:"],
        L["Says if gear beats what you wear."])
    controls.tooltip = ShiftStepper(tooltipRow, "tooltipLine", "upgrade")

    local suffixRow = pages:Row("tooltips", 1, L["Random Roll Names:"],
        L["Adds a green's roll, like of the Monkey, to its tooltip."])
    controls.suffixLine = ShiftStepper(suffixRow, "suffixLine", "suffix")

    local altRow = pages:Row("tooltips", 1, L["Upgrades for Alts:"],
        L["Names the other character an item helps most."])
    controls.altTooltipLine = ShiftStepper(altRow, "altTooltipLine", "alt")

    local enchantRow = pages:Row("tooltips", 2, L["Best Enchant:"],
        L["Names the best enchant for a piece you wear."])
    controls.enchantTooltip = ShiftStepper(enchantRow, "enchantTooltip", "enchant")

    local dropsRow = pages:Row("tooltips", 2, L["Boss Drops:"], nil)
    controls.dropsTooltip = ShiftStepper(dropsRow, "dropsTooltip", "drops")
end

--- What the Untrained weapons row says: which types this character
--- ignores, if any.
function SettingsUI:WeaponsHint()
    local skills = ns.WeaponSkills
    if skills and skills:HidesAll() then
        return L["Weapons you haven't trained don't show as upgrades until you train them."]
    end
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
        L["Hover a gear slot to see its upgrades."], L["Show"], "SlotUpgrades" },
    { "upgradeToast", 1, L["Upgrade Banner:"], "", L["Show"] },
    { "showTracker", 2, L["Upgrade Tracker:"],
        L["The panel of upgrades you're tracking."], L["Show"], "SmallPanel" },
    { "mapPins", 2, L["Map Pins:"],
        L["Shows where each tracked upgrade comes from."], L["Show"], "MapPins" },
}

--- "Upgrade Arrows:" changed: redraw every arrow it covers, in the bags,
--- on quest rewards, loot rolls, vendors and loot. The welcome card's Green
--- Arrows box calls it too (UI/Welcome.lua).
function SettingsUI.RedrawArrows()
    if ns.BagIcons then pcall(ns.BagIcons.Refresh, ns.BagIcons) end
    if ns.QuestRewards then pcall(ns.QuestRewards.Refresh, ns.QuestRewards) end
    if ns.LootRolls then pcall(ns.LootRolls.Refresh, ns.LootRolls) end
    if ns.MoreMarks then
        pcall(ns.MoreMarks.RefreshMerchant, ns.MoreMarks)
        pcall(ns.MoreMarks.RefreshLoot, ns.MoreMarks)
    end
end

--- A box's name in the grid: its Settings label without the colon.
function SettingsUI.GridName(label)
    local name = tostring(label or ""):gsub("%s*\239\188\154%s*$", "")  -- the wide colon
    return (name:gsub("%s*:%s*$", ""))
end

--- SHOW ON SCREEN: the on/off boxes for everything Equipment draws, two to a
--- line, each on its own saved key as before. What a box does is its
--- tooltip.
function SettingsUI:BuildShowGrid()
    local controls = self.controls
    local pages = self.pages
    pages:Section("gear", 1, L["SHOW ON SCREEN"])

    local function Plain(key, initial, after)
        return function(parent, text)
            return Widgets.CreateCheckbox(parent, text, function(checked)
                ns.db[key] = checked
                if after then after(checked) end
            end, initial)
        end
    end
    local function Hunt(entry)
        local redraw = entry[6]
        return { entry[1], entry[3], entry[4], Plain(entry[1], true, function()
            -- "Upgrade Tracker:" is the small panel's Tracking tab.
            local module = redraw and ns[redraw]
            if module and module.OnTrackingChanged then pcall(module.OnTrackingChanged, module) end
        end) }
    end

    -- { control, label, what it does, make(parent, text) }; the left
    -- column top to bottom, then the right.
    local cells = {
        { "arrows", L["Upgrade Arrows:"], L["A green arrow on upgrades you can wear now."],
          Plain("bagArrows", true, SettingsUI.RedrawArrows) },
        { "sellCoins", L["Sell Coins:"], L["A gold coin on bag gear that's no upgrade and sells to a vendor."],
          Plain("bagSellCoins", true, function()
              if ns.BagIcons then pcall(ns.BagIcons.Refresh, ns.BagIcons) end
          end) },
        { "rewardButton", L["Take Reward Button:"], L["A button under the quest window takes the best reward."],
          Plain("rewardButton", true, function()
              if ns.QuestRewards then pcall(ns.QuestRewards.UpdateTake, ns.QuestRewards) end
          end) },
        { "upgradeChat", L["Upgrades in Chat:"], L["A chat line when an upgrade lands in your bags."],
          Plain("upgradeChat", true) },
        Hunt(HUNTING[1]),
        Hunt(HUNTING[2]),
        Hunt(HUNTING[3]),
        Hunt(HUNTING[4]),
        -- Off unless the player turns it on, unlike the rest.
        { "upgradeQuest", L["Upgrade Quest:"], L["A quest for your best next upgrade, with steps to get it."],
          function(parent, text)
              return Widgets.CreateCheckbox(parent, text, function(checked)
                  if ns.UpgradeQuest then ns.UpgradeQuest:SetEnabled(checked) end
              end, false)
          end },
        { "questArrow", L["Quest Arrow:"], L["Points the way to the quest's next place. Click a step to aim it."],
          function(parent, text)
              return Widgets.CreateCheckbox(parent, text, function(checked)
                  if ns.QuestArrow then ns.QuestArrow:SetOn(checked) end
              end, false)
          end },
        { "classTraining", L["Class Training:"],
          L["The Training tab shows spells you can learn and their cost. Visit a class trainer once so prices show."],
          function(parent, text)
              return Widgets.CreateCheckbox(parent, text, function(checked)
                  ns.ClassTraining:SetOn(checked)
              end, ns.ClassTraining:IsOn())
          end },
        -- Off unless ticked.
        { "autoEquip", L["Put On Upgrades:"],
          L["Puts an upgrade on as soon as you get it. Gear that would bind waits for your click."],
          Plain("autoEquip", false) },
        -- Switch Gear's dungeon door card (Logic/SwitchGear.lua); off
        -- unless ticked.
        { "swapAtDoors", L["Ask at Dungeon Doors:"],
          L["At a dungeon's door, a card offers to put on your Off Spec gear."],
          Plain("swapAtDoors", false) },
    }

    local width = pages.opts.columnWidth
    local half = math.floor(width / 2)
    local content = pages.pages.gear.content
    local lines = math.ceil(#cells / 2)
    self.showGrid = {}
    for line = 1, lines do
        local row = CreateFrame("Frame", nil, content)
        row:SetSize(width, 24)
        row.fixedHeight = 24
        pages:Place("gear", 1, row)
        self.showGrid[line] = row
        for side, index in ipairs({ line, line + lines }) do
            local cell = cells[index]
            if cell then
                local name = SettingsUI.GridName(cell[2])
                local box = cell[4](row, name)
                box:SetPoint("TOPLEFT", (side - 1) * half, -3)
                -- A long name in another language wraps in its half.
                local room = half - 28
                if Theme.TextWidth("small", name) > room then
                    box.label:SetWidth(room)
                    box.label:SetWordWrap(true)
                    box:SetWidth(half - 4)
                    row.fixedHeight = 36
                    row:SetHeight(36)
                end
                if cell[3] and cell[3] ~= "" then Explain(box, name, cell[3]) end
                controls[cell[1]] = box
                box.gridName = name
                pages:Searchable("gear", row, name .. " " .. (cell[3] or ""))
            end
        end
    end
end

--- The upgrade quest on the left, the arrow that leads there on the right.
function SettingsUI:BuildQuest()
    local controls = self.controls
    local pages = self.pages

    pages:Section("quest", 1, L["UPGRADE QUEST"])

    -- Ignore, Switch and the tab to show are on the panel itself, and stay
    -- typed (/beq quest ignore, switch, vendor...); the owner, 2026-10-15.
    -- The list of ignored upgrades, each with Restore, and Restore all, is
    -- on the Upgrade Quest tab.
    local panelRow = pages:Row("quest", 1, L["Quest Panel:"],
        L["Ignored lists upgrades you skipped, so you can bring them back."])
    self.questPanelRow = panelRow
    controls.questReset = Widgets.CreateButton(panelRow, L["Ignored"], function()
        ns.HandleSlash("quest ignored")
    end, { width = 84, height = 20 })
    controls.questReset:SetPoint("TOPLEFT", CONTROL_X, 0)

    -- The upgrade quest panel's size, as its gold corner grip and /beq quest
    -- size set it (the owner asked 2026-10-07). The size in use is lit green.
    local questSizeRow = pages:Row("quest", 1, L["Panel Size:"], "")
    self.questSizeRow = questSizeRow
    controls.questSizes = {}
    local previous
    for _, size in ipairs(ns.SmallPanel and ns.SmallPanel.SIZES or {}) do
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

    -- How You Gear Up (the upgrade quest mockups, card B): one pick that
    -- sets the quest's boxes. Its hover says which boxes it sets.
    local styles = ns.UpgradeQuest and ns.UpgradeQuest.STYLES or {}
    local function StyleDescription(style)
        local lines = ns.UpgradeQuest and ns.UpgradeQuest.StyleLines(style) or {}
        if #lines == 0 then return "" end
        return L["This sets:"] .. " " .. table.concat(lines, ", ")
    end
    local styleRow = pages:Row("quest", 1, L["How You Gear Up:"], "")
    controls.questStyleRow = styleRow
    controls.questStyle = Widgets.CreateChoice(styleRow, {
        min = 1, max = math.max(1, #styles), step = 1, value = 1,
        format = function(index) return styles[index] and styles[index].label or L["Anything"] end,
        onChange = function(index)
            local style = styles[index]
            if style and ns.UpgradeQuest then ns.UpgradeQuest:SetStyle(style.key) end
            if style and styleRow.SetDescription then styleRow:SetDescription(StyleDescription(style)) end
        end,
    })
    local styleWords = {}
    for index, style in ipairs(styles) do styleWords[index] = style.label end
    ns.SettingsPages.FitStepper(controls.questStyle, styleWords)
    controls.questStyle:SetPoint("TOPLEFT", CONTROL_X, -2)
    SettingsUI.StyleDescription = StyleDescription

    -- Biggest Upgrade First (the owner asked 2026-11-23): each tab picks
    -- the biggest % gain, off unless ticked.
    local biggestRow = pages:Row("quest", 1, L["Biggest Upgrade First:"],
        L["Picks the upgrade with the biggest % gain on each tab, even when it's far away or harder to get."])
    controls.questBiggest = Widgets.CreateCheckbox(biggestRow, L["On"], function(checked)
        if ns.UpgradeQuest then ns.UpgradeQuest:SetBiggestFirst(checked) end
    end, false)
    controls.questBiggest:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- The quest arrow, as the Arrow button on the quest panel and /beq
    -- arrow switch it, and /beq arrow next as a button. /beq arrow check is
    -- typed only (the owner, 2026-10-23).
    pages:Section("quest", 2, L["ARROW"])

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

    -- A trip step by step to a far place (Logic/Travel.lua), on unless
    -- unticked.
    local routeRow = pages:Row("quest", 2, L["Guide Me:"],
        L["When the place is in another zone or across the sea, the arrow leads you there step by step."])
    controls.arrowRoute = Widgets.CreateCheckbox(routeRow, L["On"], function(checked)
        if ns.Travel then ns.Travel:SetOn(checked) end
    end, true)
    controls.arrowRoute:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- How big the whole arrow is drawn, 100% unless picked (the owner,
    -- 2026-10-26). The arrow keeps its spot.
    local arrowSizeRow = pages:Row("quest", 2, L["Arrow Size:"], nil)
    controls.arrowSize = Widgets.CreateChoice(arrowSizeRow, {
        min = 50, max = 100, step = 25, value = 100,
        format = function(percent) return ("%d%%"):format(percent) end,
        onChange = function(percent)
            if ns.QuestArrowUI then ns.QuestArrowUI:SetSize(percent) end
        end,
    })
    ns.SettingsPages.FitStepper(controls.arrowSize, { "50%", "75%", "100%" })
    controls.arrowSize:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- The small panel's Quest log tab (UI/QuestLogTab.lua): open it, keep
    -- it to tracked quests, and hide the game's own tracker meanwhile.
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

    -- The rows every Blackthornes addon shares, in the same order (the
    -- unified look, card 13), then this addon's own.
    -- All Addons: the rows every Blackthornes addon shares, shown once in
    -- the one window behind its gear (the owner said build it,
    -- 2026-11-16). General keeps this addon's own. No setting was renamed
    -- and no saved choice changed.
    pages:Section("all", 1, L["ALL BLACKTHORNES ADDONS"])
    pages:Section("general", 1, L["WINDOWS"])

    -- Asked 2026-10-10: the game's own look for players who would rather
    -- the windows matched the rest of their screen. Read at login, so it
    -- waits for /reload as Text size does. See UI/BlizzardLook.lua. A
    -- stepper, as Text size is: this addon's Widgets have no dropdown.
    local styleRow = pages:Row("all", 1, L["Window Style:"], "")
    controls.windowStyle = self:WindowStyleControl(styleRow)

    -- Bigger letters in the same windows, as Tradeskills has. Every size
    -- is read as text is drawn, so it waits for /reload.
    local textRow = pages:Row("all", 1, L["Text Size:"], "")
    controls.textSize = ns.SettingsPages.TextSizeControl(textRow, CONTROL_X, function() return ns.db end)

    -- The Equipment window's size, the one its grip saves.
    local sizeRow = pages:Row("general", 1, L["Window Size:"], nil)
    controls.windowScale = ns.SettingsPages.WindowSizeControl(sizeRow, CONTROL_X,
        function() return ns.db and ns.db.finderScale end,
        function(percent)
            if not ns.db then return end
            ns.db.finderScale = percent
            -- Laid into the one window, that window's own size holds.
            local Gear = ns.GearWindow
            if Gear and Gear.frame and not Gear.hostArea and Widgets.ApplySize then
                Widgets.ApplySize(Gear.frame, percent)
            end
        end)

    -- How much the windows move: they rise in, glow and glint at Full,
    -- only fade at Subtle and stay still at Off. Full until picked.
    local effectsRow = pages:Row("all", 1, L["Effects:"], nil)
    local Motion = ns.Motion
    local effectNames = { full = L["Full"], subtle = L["Subtle"], off = L["Off"] }
    local function EffectIndex()
        local level = Motion.Level()
        for index, name in ipairs(Motion.LEVELS) do
            if name == level then return index end
        end
        return 1
    end
    controls.effects = Widgets.CreateChoice(effectsRow, {
        min = 1, max = #Motion.LEVELS, step = 1, value = EffectIndex(),
        format = function(index) return effectNames[Motion.LEVELS[index]] end,
        onChange = function(index) Motion.SetLevel(Motion.LEVELS[index]) end,
    })
    controls.effects:SetPoint("TOPLEFT", CONTROL_X, 0)
    controls.effectsIndex = EffectIndex

    -- Quiets every sound every Blackthornes addon plays (UI/SharedChoices.lua,
    -- a player asked, 2026-11-12). Off unless ticked; ticked in one is ticked in all.
    local muteRow = pages:Row("all", 1, L["Mute All Sounds:"], nil)
    controls.muteSounds = Widgets.CreateCheckbox(muteRow, L["On"], function(checked)
        SettingsUI:SetMuteSounds(checked)
    end, false)
    controls.muteSounds:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- One minimap button for every Blackthornes addon (UI/SharedMinimap.lua,
    -- the owner, 2026-10-28): ticked unless unticked, the same in all five.
    local combineRow = pages:Row("all", 1, L["Combine Addon Buttons:"], nil)
    controls.combineButtons = Widgets.CreateCheckbox(combineRow, L["On"], function(checked)
        if ns.SharedMinimap then ns.SharedMinimap.SetCombined(checked) end
    end, true)
    controls.combineButtons:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- One window for every Blackthornes addon (UI/SharedWindow.lua, the
    -- owner, 2026-10-30): off unless ticked, the same in all five. Ticked or
    -- not, Settings opens again where it now belongs.
    local oneRow = pages:Row("all", 1, L["One Window:"], nil)
    controls.oneWindow = Widgets.CreateCheckbox(oneRow, L["On"], function(checked)
        SettingsUI:SetOneWindow(checked)
    end, false)
    controls.oneWindow:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- The minimap button always shows (the owner, 2026-10-15); a saved
    -- minimapHidden is kept but no longer read.
    local positionRow = pages:Row("all", 1, L["Window Locations:"],
        L["Puts every Blackthornes window back where it started. Your settings and data stay the same."])
    local reset = Widgets.CreateButton(positionRow, L["Set Default"], function()
        SettingsUI:ResetAllWindows()
    end, { width = 100, height = 20 })
    reset:SetPoint("TOPLEFT", CONTROL_X, 0)
    controls.resetPositions = reset

    local restoreRow = pages:Row("all", 1, L["Equipment Settings:"],
        L["Puts every Equipment setting back to how it started. Your gear, characters and stat weights stay. So do your window locations and the choices on this page."])
    controls.restoreDefaults = SettingsUI.ConfirmButton(restoreRow, L["Set Default"], function()
        SettingsUI:RestoreDefaults()
    end, reset:GetWidth() or 100)
    controls.restoreDefaults:SetPoint("TOPLEFT", CONTROL_X, 0)


    -- Debug, the speed check and the client check are typed only (/beq
    -- debug, perf, probe; the owner, 2026-10-23): players don't need them.

    -- Core/SisterNote.lua: one chat line, once, naming the Blackthornes
    -- addons the player does not have. Off here is off in all of them.
    local sistersRow = pages:Row("all", 1, L["Sister Addons:"],
        L["Says once in chat which Blackthornes addons you don't have."])
    controls.sisters = Widgets.CreateCheckbox(sistersRow, L["On"], function(checked)
        ns.SisterNote:SetOn(checked)
    end, true)
    controls.sisters:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- UI/WhatsNew.lua: one window after an update for every Blackthornes
    -- addon. Off here is off in all of them, as the sister note is.
    pages:Section("all", 2, L["WHAT'S NEW"])
    local _, whatsNewButton = CommandRow(pages, "all", 2, L["What's New:"], "",
        L["Open"], "whatsnew")
    controls.whatsnew = whatsNewButton

    -- One drop-down for the two What's New boxes (UI/SettingsPages.lua).
    local afterRow = pages:Row("all", 2, L["After Updates:"],
        L["Opens What's New the first time you play after an update."])
    controls.whatsNewAfter = ns.SettingsPages.AfterUpdatesControl(afterRow, CONTROL_X,
        function() return ns.WhatsNew end)

    -- The two panels that stay up while you play let the world show through
    -- (UI/SeeThrough.lua, card 14 of the unified look): Off unless picked.
    pages:Section("general", 2, L["TRANSPARENT"])
    controls.seeThrough = {}
    local see = ns.SeeThrough
    for _, spec in ipairs({ { "hunts", L["Upgrade Hunts:"] }, { "quest", L["Upgrade Quest:"] } }) do
        local id = spec[1]
        local row = pages:Row("general", 2, spec[2], nil)
        local names = see and see.Names() or { [0] = L["Off"] }
        local choice = Widgets.CreateChoice(row, {
            min = 0, max = see and #see.LEVELS or 0, step = 1, value = see and see:Level(id) or 0,
            format = function(level) return names[level] end,
            onChange = function(level) if see then see:Set(id, level) end end,
        })
        ns.SettingsPages.FitStepper(choice, names)
        choice:SetPoint("TOPLEFT", CONTROL_X, -2)
        controls.seeThrough[id] = choice
    end
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
    local stepper = Widgets.CreateChoice(row, {
        min = 1, max = #styles, step = 1,
        format = function(value) return self.WINDOW_STYLE_LABELS[styles[value]] end,
        onChange = function(value)
            ns.db.windowStyle = styles[value]
            if ns.SharedChoices then ns.SharedChoices:Changed("windowStyle", styles[value]) end
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
    if controls.shareData then controls.shareData:SetChecked(ns.db.shareData == true) end
    controls.sisters:SetChecked(ns.SisterNote:IsOn())
    controls.whatsNewAfter:Sync()
    controls.tooltip:Sync()
    controls.arrows:SetChecked(ns.db.bagArrows ~= false)
    controls.sellCoins:SetChecked(ns.db.bagSellCoins ~= false)
    controls.upgradeChat:SetChecked(ns.db.upgradeChat ~= false)
    controls.autoEquip:SetChecked(ns.db.autoEquip == true)
    controls.swapAtDoors:SetChecked(ns.db.swapAtDoors == true)
    controls.bestArmorOnly:SetChecked(ns.Compare.BestArmorOnly())
    controls.rewardButton:SetChecked(ns.db.rewardButton ~= false)
    controls.suffixLine:Sync()
    controls.altTooltipLine:Sync()
    controls.enchantTooltip:Sync()
    controls.dropsTooltip:Sync()
    controls.classTraining:SetChecked(ns.ClassTraining:IsOn())
    for _, entry in ipairs(HUNTING) do
        controls[entry[1]]:SetChecked(ns.db[entry[1]] ~= false)
    end
    controls.upgradeQuest:SetChecked(ns.db.upgradeQuest == true)
    controls.questArrow:SetChecked(ns.db.questArrow == true)
    controls.useTomTom:SetChecked(ns.db.useTomTom ~= false)
    controls.arrowRoute:SetChecked(ns.db.arrowRoute ~= false)
    controls.arrowSize:SetValue(ns.QuestArrowUI and ns.QuestArrowUI.Size() or 100, true)
    controls.questLogTracked:SetChecked(ns.db.questLogTrackedOnly == true)
    controls.hideQuestTracker:SetChecked(ns.db.hideQuestTracker == true)
    self:RefreshQuestSize()
    if self.weaponsRow then self.weaponsRow:SetDescription(self:WeaponsHint()) end
    controls.weapons:Sync()
    controls.soloQuests:SetChecked(ns.db.soloQuestsOnly == true)
    controls.questZoneSwap:SetChecked(ns.db.upgradeQuestZoneSwap ~= false)
    controls.questBiggest:SetChecked(ns.db.upgradeQuestBiggest == true)
    if controls.questStyle and ns.UpgradeQuest then
        local now = ns.UpgradeQuest:Style()
        for index, style in ipairs(ns.UpgradeQuest.STYLES) do
            if style.key == now.key then controls.questStyle:SetValue(index, true) end
        end
        if controls.questStyleRow.SetDescription then
            controls.questStyleRow:SetDescription(SettingsUI.StyleDescription(now))
        end
    end
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
    if controls.offSpec then controls.offSpec:SetValue(self:OffSpecIndex(), true) end

    controls.textSize:Sync()
    controls.windowStyle:Sync()
    controls.combineButtons:SetChecked(not ns.SharedMinimap or ns.SharedMinimap.Combined())
    local One = ns.GearWindow and ns.GearWindow.One()
    controls.oneWindow:SetChecked(One ~= nil and One.On() == true)
    controls.effects:SetValue(controls.effectsIndex(), true)
    controls.muteSounds:SetChecked(ns.Muted ~= nil and ns.Muted() == true)
    if ns.SeeThrough then
        for id, choice in pairs(controls.seeThrough or {}) do choice:SetValue(ns.SeeThrough:Level(id), true) end
    end
    controls.windowScale:Sync()
    -- In the one window, All Addons is behind its gear, not on the switch.
    self.pages:SetHidden("all", One ~= nil and One.On() == true)
    self.pages:Refresh()
end

--- Open Settings on the All Addons page (the one window's gear).
function SettingsUI:ShowAllAddons()
    self:Show("all")
end

--- The quest panel's size buttons: the one in use is lit green.
function SettingsUI:RefreshQuestSize()
    local panel = ns.SmallPanel
    if not (panel and panel.GetScale and self.questSizeRow) then return end
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

--------------------------------------------------------------------------------
-- Visibility
--------------------------------------------------------------------------------

--- Is the Settings page up and its window open?
function SettingsUI:IsShown()
    local frame = self.frame
    if not frame then return false end
    local ok, shown = pcall(frame.IsShown, frame)
    if not (ok and shown == true) then return false end
    local okSeen, seen = pcall(frame.IsVisible, frame)
    if okSeen and type(seen) == "boolean" then return seen end
    return true
end

--- Show Settings, on `page` when one is named. Asked by anything but the
--- Equipment window, it opens that window on its Settings tab, which shows
--- this (Gear.driving).
function SettingsUI:Show(page)
    local Gear = ns.GearWindow
    if page then self.wantPage = page end
    if Gear and not Gear.driving then
        Gear:Open("settings")
        return
    end
    self:Build()
    if not self.frame then return end
    self.frame:Show()
    local want = self.wantPage
    self.wantPage = nil
    if want and self.pages and self.pages.pages[want] then self.pages:Show(want) end
    self:Refresh()
end

--- Tick or untick "One Window:" in every loaded addon, and open Settings
--- again in the one window, or in the Equipment window's own frame.
function SettingsUI:SetOneWindow(on)
    local Gear = ns.GearWindow
    local One = Gear and Gear.One()
    if not One then return end
    local inside = Gear.hostArea ~= nil
    local showing = self:IsShown()
    One.SetOn(on)
    if on and not inside and showing then
        -- The Equipment window closes in its own place and opens again in
        -- the one window, on Settings.
        Gear:Close()
        self:Show()
    elseif not on and inside then
        self:Show()
    end
end

--- The page goes; the Equipment window stays (it calls this as it changes
--- tabs and as it closes).
function SettingsUI:Hide()
    if self.frame then self.frame:Hide() end
end

--- /beq settings: open on Settings, or close the window when it is there.
function SettingsUI:Toggle()
    if self:IsShown() then
        if ns.GearWindow then ns.GearWindow:Close() else self:Hide() end
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
    self:SayRestored()
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
-- Mute All Sounds: kept in this addon's own save as muteSounds and
-- muteSoundsAt (never rename them) and told to every sister.
function SettingsUI:SetMuteSounds(on)
    on = on and true or false
    local at = ns.SharedChoices and ns.SharedChoices:SetMute(on) or nil
    if ns.db then
        ns.db.muteSounds = on
        ns.db.muteSoundsAt = at
    end
    if self:IsShown() then pcall(self.Refresh, self) end
end

ns.RegisterCommand("mute", L["turn every Blackthornes sound off or back on (on/off)"], function(arg)
    arg = ((arg or ""):match("^%s*(.-)%s*$") or ""):lower()
    local on
    if arg == "on" then on = true
    elseif arg == "off" then on = false
    else on = not (ns.Muted and ns.Muted()) end
    SettingsUI:SetMuteSounds(on)
    ns.Print(on and L["All Blackthornes sounds are off. /beq mute off turns them back on."]
        or L["Blackthornes sounds are back on."])
end)

ns.commands.options = ns.commands.settings
ns.commands.config = ns.commands.settings

--------------------------------------------------------------------------------
-- Choices every Blackthornes addon shares (UI/SharedChoices.lua): a change
-- made in a sister is written here the way this addon writes it itself.
--------------------------------------------------------------------------------

if ns.SharedChoices then
    ns.SharedChoices:Join("Equipment", function(choice, value)
        if not ns.db then return end
        if choice == "textSize" then
            if ns.Theme.TEXT_STEPS and ns.Theme.TEXT_STEPS[value] then ns.db.textSize = value end
        elseif choice == "windowStyle" then
            if value == "titanforged" or value == "blizzard" then ns.db.windowStyle = value end
        elseif choice == "effects" then
            if value == "full" or value == "subtle" or value == "off" then ns.Motion.SetLevel(value) end
        elseif choice == "useTomTom" then
            if ns.TomTom then ns.TomTom:SetOn(value and true or false) end
        elseif choice == "arrowRoute" then
            if ns.Travel then ns.Travel:SetOn(value and true or false) end
        elseif choice == "arrowSize" then
            if ns.QuestArrowUI then ns.QuestArrowUI:SetSize(value) end
        elseif choice == "muteSounds" then
            ns.db.muteSounds = value and true or false
            ns.db.muteSoundsAt = ns.SharedChoices.board.mute.at
        end
        if ns.SettingsUI and ns.SettingsUI.Refresh and ns.SettingsUI.frame and ns.SettingsUI.frame:IsShown() then pcall(ns.SettingsUI.Refresh, ns.SettingsUI) end
    end, function()
        if not ns.db then return nil end
        return ns.db.muteSounds == true, ns.db.muteSoundsAt
    end)
end

ns.RegisterCommand("windows", L["put every Blackthornes window back where it started (reset)"], function(arg)
    arg = ((arg or ""):match("^%s*(.-)%s*$") or ""):lower()
    if arg == "reset" then
        SettingsUI:ResetAllWindows()
    else
        ns.Print(L["Type /beq windows reset to put every window back in its first spot."])
    end
end)

-- A window folded into its round button before step 6 opens Settings.
if ns.FoldWindow and ns.FoldWindow.Opener then
    ns.FoldWindow:Opener("Settings", { open = function() SettingsUI:Show() end })
end

if ns.GearWindow then ns.GearWindow:AddPage("settings", SettingsUI) end
