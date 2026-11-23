-- Blackthornes Equipment -- UI/UpgradeQuestTab.lua
-- Upgrade Quest, the Equipment window's third tab (rework step 4, the
-- owner approved the mockup 2026-11-22): one home for going after gear.
-- It takes the place of the old quest panel's five tabs and Options
-- button, the Upgrade Hunts panel's lists and the Ignored window.
--
-- Four views along the top:
--   Quest     each source's pick side by side on the left (Vendor, Quest,
--             Dungeons and Raids, Crafted, each with its gain); the one
--             picked on the right with why, what it asks of you, its
--             steps and Also Good.
--   Tracking  the upgrades tracked, with where to get each.
--   Done      the upgrades finished.
--   Ignored   the upgrades ignored, with Restore and Restore All.
-- The options the old panel kept behind a button are in plain view:
-- Upgrade Quest on or off, How You Gear Up, This Zone Only, Change on a
-- New Zone, Solo Quests Only, Quest Level, and whether the small panel
-- (UI/SmallPanel.lua) shows.
--
-- Every control sets the same saved choice, through the same call, as the
-- old panel did. New saved key: the character's `upgradeQuestDoneList`
-- (Logic/UpgradeQuest.lua), the upgrades finished from now on.
--
-- Nothing here judges gear or starts a scan: the page draws what the
-- upgrade quest, the tracker and the finder's last scan already hold, and
-- only while it shows.

local _, ns = ...
local L = ns.L

local Tab = ns.NewModule("QuestTab")

local Theme = ns.Theme
local Widgets = ns.Widgets

local PAD = 18
local WIDTH = 1040
local BAR = 30
local LEFT_SHARE = 0.36
local ROW = 30
local ICON = 22
local BIG_ICON = 34
local HEAD = 22
local MOST_STEPS = 14
local MOST_ROWS = 16
local MOST_CHIPS = 5
local MOST_ALSO = 2
local WHEEL = 3

local DONE_ICON = [[Interface\RaidFrame\ReadyCheck-Ready]]
local TURN_IN_ICON = [[Interface\GossipFrame\ActiveQuestIcon]]

local VIEWS = { "quest", "tracking", "done", "ignored" }
Tab.VIEWS = VIEWS

local function Colored(key, text)
    local r, g, b = Theme.Unpack(key)
    return ("|cff%02x%02x%02x%s|r"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
        math.floor(b * 255 + 0.5), text)
end

local function Shown(frame)
    if not frame then return false end
    local ok, shown = pcall(frame.IsShown, frame)
    return ok and shown == true
end

local function TextHeight(label, size, width)
    local text = label:GetText() or ""
    if text == "" then return 0 end
    local ok, height = pcall(label.GetStringHeight, label)
    if ok and type(height) == "number" and height > 0 then return height end
    local lines = 0
    for part in (text .. "\n"):gmatch("(.-)\n") do
        local plain = part:gsub("|H.-|h", ""):gsub("|h", "")
        lines = lines + math.max(1, math.ceil(Theme.TextWidth(size, plain) / math.max(1, width)))
    end
    return lines * ((Theme.sizes[size] or 10) + 2)
end

local function Tip(frame, title, words)
    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(title, Theme.Unpack("accent"))
        if words then GameTooltip:AddLine(words, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Logic() return ns.UpgradeQuest end

local function QuestOn()
    local logic = Logic()
    return logic ~= nil and logic:IsEnabled()
end

--------------------------------------------------------------------------------
-- What it shows
--------------------------------------------------------------------------------

function Tab:View()
    local view = self.view
    for _, key in ipairs(VIEWS) do
        if key == view then return key end
    end
    return "quest"
end

function Tab:SetView(view)
    self.view = view
    self.offset = 0
    self:Refresh()
end

--- The upgrades finished: the upgrade quest's (kept from this version on)
--- and the tracker's, the newest first, one line an item and day.
function Tab.DoneLines()
    local lines, seen = {}, {}
    local function Add(list, hunt)
        for _, done in ipairs(list or {}) do
            if type(done) == "table" and done.itemID then
                local key = tostring(done.itemID) .. "|" .. tostring(math.floor((tonumber(done.done) or 0) / 60))
                if not seen[key] then
                    seen[key] = true
                    lines[#lines + 1] = { itemID = done.itemID, link = done.link, at = tonumber(done.done) or 0,
                        gain = done.gain, hunt = hunt }
                end
            end
        end
    end
    Add(ns.charDB and ns.charDB.upgradeQuestDoneList, false)
    Add(ns.Tracking and ns.Tracking:Done(), true)
    table.sort(lines, function(a, b)
        if a.at ~= b.at then return a.at > b.at end
        return a.itemID < b.itemID
    end)
    return lines
end

--- How many each view holds, for its chip.
function Tab.Counts()
    local logic = Logic()
    local ignored = 0
    if logic then
        for _ in pairs(logic:Skipped()) do ignored = ignored + 1 end
    end
    local done = math.max(logic and logic:DoneCount() or 0, #Tab.DoneLines())
    return { tracking = ns.Tracking and ns.Tracking:Count() or 0, done = done, ignored = ignored }
end

--- "+21%" for a tracked or finished item, from the finder's last scan.
local function GainOf(itemID)
    return ns.SmallPanel and ns.SmallPanel.GainOf(itemID) or nil
end

--- What the item takes the place of: "over Whirlwind Axe, Main Hand".
function Tab.OverText(quest)
    local slotName = ns.Enchants and ns.Enchants.SlotName and ns.Enchants.SlotName(quest.slot) or ""
    local worn = quest.slot and ns.Items.Equipped and ns.Items:Equipped(quest.slot)
    if worn then
        local name = ns.Items.ShowLink(worn)
        if slotName ~= "" then return L.Format("over %s, %s", name, slotName) end
        return L.Format("over %s", name)
    end
    return slotName
end

--- The chips for a quest: what the upgrade quest already says it asks,
--- and Needs a group for a dungeon or raid.
function Tab.Chips(quest)
    local chips = {}
    local logic = Logic()
    for _, chip in ipairs(logic and logic:Chips(quest) or {}) do chips[#chips + 1] = chip end
    local kind = quest.source and quest.source.kind
    if kind == "dungeon" or kind == "raid" then chips[#chips + 1] = { text = L["Needs a group"], met = false, plain = true } end
    return chips
end

--------------------------------------------------------------------------------
-- Building: shared pieces
--------------------------------------------------------------------------------

local function Glass(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row.restKey = index % 2 == 0 and "glassAlt" or "glass"
    row.background = Theme.Fill(row, row.restKey)
    local under = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    under:SetPoint("BOTTOMLEFT")
    under:SetPoint("BOTTOMRIGHT")
    under:SetHeight(1)
    under:SetColorTexture(Theme.Unpack("border", 0.6))
    local edge = row:CreateTexture(nil, "ARTWORK")
    edge:SetPoint("TOPLEFT")
    edge:SetPoint("BOTTOMLEFT")
    edge:SetWidth(3)
    edge:Hide()
    row.edge = edge
    if row.RegisterForClicks then row:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    return row
end

local function Paint(row)
    local picked = rawget(row, "picked") == true
    local over = rawget(row, "over") == true
    row.background:SetColorTexture(Theme.Unpack(picked and "glassActive" or over and "glassHover" or row.restKey))
    row.edge:SetShown(picked or over)
    row.edge:SetColorTexture(Theme.Unpack(picked and "accentHi" or "accent"))
end

local function Hover(row, tip)
    row:SetScript("OnEnter", function(self)
        self.over = true
        Paint(self)
        if tip then tip(self) end
    end)
    row:SetScript("OnLeave", function(self)
        self.over = false
        Paint(self)
        GameTooltip:Hide()
    end)
end

local function ItemTip(row)
    local link = rawget(row, "link")
    if type(link) ~= "string" then return end
    Widgets.ItemTooltip(row, rawget(row, "itemID"), link, "ANCHOR_RIGHT")
end

local function Heading(parent, text, justify)
    local label = Theme.CreateLabel(parent, "tiny", "accent", justify)
    label:SetText(text)
    return label
end

local function Panel(parent)
    local panel = Theme.CreatePanel(parent, "panel", "border")
    return panel
end

--- A button as wide as its words need.
local function Button(parent, text, run, primary)
    return Widgets.CreateButton(parent, text, run,
        { width = math.max(60, Theme.TextWidth("small", text) + 24), height = 22, primary = primary })
end

--------------------------------------------------------------------------------
-- Building: the two bars of choices
--------------------------------------------------------------------------------

function Tab:BuildBars(page)
    local logic, finder = Logic(), ns.Finder

    -- The views, as chips with their counts.
    local specs = {}
    for _, key in ipairs(VIEWS) do specs[#specs + 1] = { key = key, text = Tab.ViewText(key, 0) } end
    local views = Widgets.CreateViewTabs(page, specs, function(key) Tab:SetView(key) end,
        { selected = "quest" })
    views:SetPoint("TOPLEFT", PAD, -12)
    self.views = views

    -- How You Gear Up, then Upgrade Quest on or off, from the right.
    local styles = logic.STYLES
    local words = {}
    for index, style in ipairs(styles) do words[index] = style.label end
    local style = Widgets.CreateChoice(page, {
        min = 1, max = #styles, step = 1, value = 1,
        format = function(index) return words[index] or "" end,
        onChange = function(index)
            local pick = styles[index]
            if pick then logic:SetStyle(pick.key) end
            Tab:Sync()
        end,
    })
    if ns.SettingsPages and ns.SettingsPages.FitStepper then ns.SettingsPages.FitStepper(style, words) end
    style:SetPoint("TOPRIGHT", -PAD, -10)
    self.styleChoice = style
    local styleLabel = Theme.CreateLabel(page, "small", "muted", "RIGHT")
    styleLabel:SetPoint("RIGHT", style, "LEFT", -8, 0)
    styleLabel:SetText(L["How You Gear Up:"])
    style:HookScript("OnEnter", function(self)
        local lines = logic.StyleLines(logic:Style())
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L["How You Gear Up:"], Theme.Unpack("accent"))
        if #lines > 0 then
            GameTooltip:AddLine(L["This sets:"], 1, 1, 1)
            for _, line in ipairs(lines) do GameTooltip:AddLine("  " .. line, 1, 1, 1) end
        end
        GameTooltip:Show()
    end)
    style:HookScript("OnLeave", function() GameTooltip:Hide() end)

    local on = Widgets.CreateCheckbox(page, L["On"], function(checked)
        if checked then logic:TurnOn() else logic:TurnOff() end
    end, QuestOn())
    on:SetPoint("RIGHT", styleLabel, "LEFT", -22, 0)
    self.onBox = on
    local onLabel = Theme.CreateLabel(page, "small", "muted", "RIGHT")
    onLabel:SetPoint("RIGHT", on, "LEFT", -8, 0)
    onLabel:SetText(L["Upgrade Quest:"])

    -- The second bar: what the quest may pick from, then the panel.
    local y = -(12 + BAR + 4)
    local zone = Widgets.CreateCheckbox(page, L["This Zone Only"], function(checked)
        logic:SetZoneOnly(checked)
        logic:BoxChanged("zone", checked)
        Tab:Sync()
    end, logic:ZoneOnly())
    zone:SetPoint("TOPLEFT", PAD, y)
    Tip(zone, L["This Zone Only"], L["Only upgrades from the zone you're in, plus dungeon drops and gear you can make. The list changes as you travel."])
    self.zoneBox = zone

    local swap = Widgets.CreateCheckbox(page, L["Change on a New Zone"], function(checked)
        logic:SetZoneSwap(checked)
    end, logic:ZoneSwap())
    swap:SetPoint("LEFT", zone, "RIGHT", 18, 0)
    self.swapBox = swap

    local solo = Widgets.CreateCheckbox(page, L["Solo Quests Only"], function(checked)
        if finder then finder:SetSoloOnly(checked) end
        logic:BoxChanged("solo", checked)
        Tab:Sync()
    end, finder and finder:SoloOnly() or false)
    solo:SetPoint("LEFT", swap, "RIGHT", 18, 0)
    Tip(solo, L["Solo Quests Only"], L["Hides quests that need a group, and the quests after them. Elite kills count as group quests."])
    self.soloBox = solo

    local levelLabel = Theme.CreateLabel(page, "small", "muted")
    levelLabel:SetPoint("LEFT", solo, "RIGHT", 22, 0)
    levelLabel:SetText(L["Quest Level:"])
    local FinderUI = ns.FinderUI
    local levels = Widgets.CreateChoice(page, {
        min = 0, max = finder and finder.QUEST_LEVELS_ANY or 11, step = 1,
        value = FinderUI and FinderUI:QuestLevelsValue() or 0, width = 150,
        format = function(value) return FinderUI and FinderUI.QuestLevelsText(value) or tostring(value) end,
        onChange = function(value) if finder then finder:SetQuestLevelsAbove(value) end end,
    })
    levels:SetPoint("LEFT", levelLabel, "RIGHT", 8, 0)
    Tip(levels, L["Quest Level:"], L["How far above your level a quest can be."])
    self.levelChoice = levels

    local show = Widgets.CreateCheckbox(page, L["Show"], function(checked)
        if ns.SmallPanel then ns.SmallPanel:SetOff(not checked) end
    end, not (ns.SmallPanel and ns.SmallPanel:IsOff()))
    show:SetPoint("TOPRIGHT", -PAD, y)
    self.panelBox = show
    local showLabel = Theme.CreateLabel(page, "small", "muted", "RIGHT")
    showLabel:SetPoint("RIGHT", show, "LEFT", -8, 0)
    showLabel:SetText(L["Panel:"])

    local rule = Theme.CreateDivider(page, "border")
    rule:SetPoint("TOPLEFT", PAD, y - 26)
    rule:SetPoint("TOPRIGHT", -PAD, y - 26)
    return -(y - 26) + 8
end

--- A view's chip: its name, and how many it holds.
function Tab.ViewText(key, count)
    local name = key == "quest" and L["Quest"] or key == "tracking" and L["Tracking"]
        or key == "done" and L["Done"] or L["Ignored"]
    if key ~= "quest" and (count or 0) > 0 then return ("%s %d"):format(name, count) end
    return name
end

--- Put every box and choice in step with what is saved.
function Tab:Sync()
    if not self.page then return end
    local logic, finder, FinderUI = Logic(), ns.Finder, ns.FinderUI
    self.onBox:SetChecked(QuestOn())
    local now = logic:Style()
    for index, style in ipairs(logic.STYLES) do
        if style.key == now.key then self.styleChoice:SetValue(index, true) end
    end
    local zoneOnly = logic:ZoneOnly()
    self.zoneBox:SetChecked(zoneOnly)
    self.swapBox:SetChecked(logic:ZoneSwap())
    if self.swapBox.SetDisabled then self.swapBox:SetDisabled(not zoneOnly) end
    self.soloBox:SetChecked(finder and finder:SoloOnly() or false)
    if FinderUI then self.levelChoice:SetValue(FinderUI:QuestLevelsValue(), true) end
    self.panelBox:SetChecked(not (ns.SmallPanel and ns.SmallPanel:IsOff()))
end

--------------------------------------------------------------------------------
-- Building: the Quest view
--------------------------------------------------------------------------------

function Tab:BuildSourceRow(index, tab)
    local row = Glass(self.sources, index)
    row.tabKey = tab.key
    row.icon = Theme.CreateItemIcon(row, ICON)
    row.icon:SetPoint("TOPLEFT", 8, -8)
    row.source = Theme.CreateLabel(row, "tiny", tab.color or "accent")
    row.source:SetPoint("TOPLEFT", ICON + 16, -6)
    row.source:SetText(tab.name)
    row.gain = Theme.CreateLabel(row, "normal", "good", "RIGHT")
    row.gain:SetPoint("TOPRIGHT", -10, -12)
    row.item = Theme.CreateLabel(row, "normal", "text")
    row.item:SetPoint("TOPLEFT", ICON + 16, -20)
    row.item:SetWordWrap(true)
    Hover(row, ItemTip)
    row:SetScript("OnClick", function(self)
        local logic = Logic()
        if not QuestOn() then return end
        logic:SelectTab(self.tabKey)
    end)
    row:Hide()
    return row
end

function Tab:BuildStepRow(index)
    local row = Glass(self.detail, index)
    row.check = row:CreateTexture(nil, "ARTWORK")
    row.check:SetSize(14, 14)
    row.check:SetPoint("TOPLEFT", 10, -7)
    row.check:SetTexture(DONE_ICON)
    row.now = row:CreateTexture(nil, "ARTWORK")
    row.now:SetSize(12, 12)
    row.now:SetPoint("TOPLEFT", 11, -8)
    if ns.Titanforged then row.now:SetTexture(ns.Titanforged.MEDIA .. "SortArrow") end
    pcall(row.now.SetRotation, row.now, math.pi / 2)
    pcall(row.now.SetVertexColor, row.now, Theme.Unpack("accent"))
    row.turnIn = row:CreateTexture(nil, "ARTWORK")
    row.turnIn:SetSize(14, 14)
    row.turnIn:SetPoint("TOPLEFT", 10, -7)
    row.turnIn:SetTexture(TURN_IN_ICON)
    row.dot = row:CreateTexture(nil, "ARTWORK")
    row.dot:SetSize(4, 4)
    row.dot:SetPoint("TOPLEFT", 15, -12)
    row.dot:SetColorTexture(Theme.Unpack("dim"))
    row.text = Theme.CreateLabel(row, "normal", "text")
    row.text:SetPoint("TOPLEFT", 34, -7)
    row.text:SetWordWrap(true)
    row.note = Theme.CreateLabel(row, "small", "muted")
    row.note:SetWordWrap(true)
    row.map = Button(row, L["Show on Map"], function()
        if ns.SmallPanel then ns.SmallPanel:ShowOnMap() end
    end)
    row.map:SetPoint("TOPRIGHT", -8, -4)
    row.map:Hide()
    Hover(row, function(self)
        if type(rawget(self, "place")) ~= "table" or rawget(self, "isNow") then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Point the quest arrow here"], Theme.Unpack("accent"))
        GameTooltip:Show()
    end)
    row:SetScript("OnClick", function(self)
        local index, place = rawget(self, "stepIndex"), rawget(self, "place")
        if type(place) == "table" and index and ns.QuestArrow then ns.QuestArrow:Aim(index) end
    end)
    row:Hide()
    return row
end

function Tab:BuildAlsoRow(index)
    local row = Glass(self.detail, index)
    row:SetHeight(ROW)
    row.icon = Theme.CreateItemIcon(row, ICON)
    row.icon:SetPoint("LEFT", 8, 0)
    row.switch = Button(row, L["Switch"], function()
        local pick = rawget(row, "pick")
        local logic = Logic()
        if pick and logic.CanFollow(pick) then logic:Follow(pick) end
    end)
    row.switch:SetPoint("RIGHT", -8, 0)
    row.gain = Theme.CreateLabel(row, "normal", "good", "RIGHT")
    row.gain:SetPoint("RIGHT", row.switch, "LEFT", -12, 0)
    row.item = Theme.CreateLabel(row, "normal", "text")
    row.item:SetPoint("LEFT", ICON + 16, 0)
    row.item:SetPoint("RIGHT", row.gain, "LEFT", -8, 0)
    Hover(row, ItemTip)
    row:Hide()
    return row
end

function Tab:BuildQuestView(body)
    local logic = Logic()
    local view = CreateFrame("Frame", nil, body)
    view:SetAllPoints(body)
    self.questView = view

    local leftWidth = math.floor((WIDTH - PAD * 2) * LEFT_SHARE)
    local rightWidth = WIDTH - PAD * 2 - leftWidth - 10
    self.leftWidth, self.rightWidth = leftWidth, rightWidth

    -- On the left: each source's pick, to compare without flipping tabs.
    local sources = Panel(view)
    sources:SetPoint("TOPLEFT", 0, 0)
    sources:SetPoint("BOTTOMLEFT", 0, 0)
    sources:SetWidth(leftWidth)
    self.sources = sources
    local head = Heading(sources, L["YOUR BEST FROM EACH SOURCE"])
    head:SetPoint("TOPLEFT", 10, -7)
    local gainHead = Heading(sources, L["GAIN"], "RIGHT")
    gainHead:SetPoint("TOPRIGHT", -10, -7)
    self.sourceRows = {}
    for index, tab in ipairs(logic.TABS) do self.sourceRows[index] = self:BuildSourceRow(index, tab) end
    local note = Theme.CreateLabel(sources, "small", "muted")
    note:SetWidth(leftWidth - 20)
    note:SetWordWrap(true)
    note:SetText(L["Each source keeps its own pick. Click one to work on it."])
    self.sourceNote = note

    -- On the right: the pick, why, what it asks, its steps, Also Good.
    local detail = Panel(view)
    detail:SetPoint("TOPLEFT", leftWidth + 10, 0)
    detail:SetPoint("BOTTOMRIGHT", 0, 0)
    self.detail = detail

    local icon = Theme.CreateItemIcon(detail, BIG_ICON)
    icon:SetPoint("TOPLEFT", 12, -12)
    self.icon = icon
    local hit = CreateFrame("Button", nil, detail)
    hit:SetAllPoints(icon)
    hit:SetScript("OnEnter", function(self) ItemTip(self) end)
    hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    hit:SetScript("OnClick", function(self)
        Widgets.ItemClick(rawget(self, "itemID"), rawget(self, "link"))
    end)
    self.iconHit = hit

    local ignore = Button(detail, L["Ignore"], function() ns.HandleSlash("quest ignore") end)
    ignore:SetPoint("TOPRIGHT", -12, -16)
    Tip(ignore, L["Ignore this upgrade"], L["Skips it on this character and picks the next best one. Bring it back with Ignored in Settings."])
    self.ignoreButton = ignore
    local arrow = Button(detail, L["Arrow"], function()
        if ns.QuestArrow then ns.HandleSlash(ns.QuestArrow.IsOn() and "arrow off" or "arrow on") end
    end)
    arrow:SetPoint("RIGHT", ignore, "LEFT", -6, 0)
    Tip(arrow, L["Quest arrow"], L["Points the way to the quest's next place. Click a step to aim it."])
    self.arrowButton = arrow
    local queue = Button(detail, L["Queue It"], function()
        local quest = QuestOn() and Logic():Current()
        local tsq = ns.TradeskillsQueue
        if quest and tsq and quest.source then tsq:Queue(quest.source) end
        Tab:Refresh()
    end)
    queue:SetPoint("RIGHT", arrow, "LEFT", -6, 0)
    queue:Hide()
    self.queueButton = queue

    local buttons = ignore:GetWidth() + arrow:GetWidth() + queue:GetWidth() + 36
    local textWidth = rightWidth - 24 - BIG_ICON - 10 - buttons
    self.headWidth = textWidth
    local name = Theme.CreateLabel(detail, "large", "text")
    name:SetPoint("TOPLEFT", 12 + BIG_ICON + 10, -12)
    name:SetWidth(textWidth)
    name:SetWordWrap(true)
    self.name = name
    local gain = Theme.CreateLabel(detail, "normal", "good")
    gain:SetWidth(textWidth)
    gain:SetWordWrap(true)
    self.gain = gain
    local why = Theme.CreateLabel(detail, "small", "muted")
    why:SetWidth(rightWidth - 24)
    why:SetWordWrap(true)
    self.why = why

    self.chips = {}
    for index = 1, MOST_CHIPS do
        local chip = Widgets.CreateChip(detail, "", nil, { height = 18 })
        chip:EnableMouse(false)
        chip:Hide()
        self.chips[index] = chip
    end

    self.stepsHead = Heading(detail, L["STEPS"])
    self.alsoHead = Heading(detail, L["ALSO GOOD"])
    self.stepRows = {}
    for index = 1, MOST_STEPS do self.stepRows[index] = self:BuildStepRow(index) end
    self.alsoRows = {}
    for index = 1, MOST_ALSO do self.alsoRows[index] = self:BuildAlsoRow(index) end

    -- With no quest on this source, or the upgrade quest off.
    local empty = Theme.CreateLabel(detail, "normal", "muted")
    empty:SetPoint("TOPLEFT", 16, -18)
    empty:SetWidth(rightWidth - 32)
    empty:SetWordWrap(true)
    self.empty = empty
    local turnOn = Button(detail, L["Turn it on"], function() Logic():TurnOn() end, true)
    turnOn:Hide()
    self.turnOn = turnOn
    local pickOne = Button(detail, L["Find Upgrades"], function()
        if ns.FinderUI and ns.FinderUI.OpenFind then ns.FinderUI.OpenFind() end
    end)
    pickOne:Hide()
    self.pickOne = pickOne
end

--------------------------------------------------------------------------------
-- Building: the lists (Tracking, Done, Ignored)
--------------------------------------------------------------------------------

function Tab:BuildListRow(index)
    local row = Glass(self.list, index)
    row.icon = Theme.CreateItemIcon(row, ICON)
    row.icon:SetPoint("TOPLEFT", 8, -4)
    row.item = Theme.CreateLabel(row, "normal", "text")
    row.item:SetPoint("TOPLEFT", ICON + 16, -8)
    row.item:SetWordWrap(true)
    row.slot = Theme.CreateLabel(row, "small", "muted")
    row.slot:SetWordWrap(true)
    row.where = Theme.CreateLabel(row, "small", "text")
    row.where:SetWordWrap(true)
    row.gain = Theme.CreateLabel(row, "normal", "good", "RIGHT")
    row.second = Button(row, L["Stop Tracking"], function()
        local run = rawget(row, "runSecond")
        if run then run() end
    end)
    row.second:SetPoint("TOPRIGHT", -8, -4)
    row.first = Button(row, L["Show on Map"], function()
        local run = rawget(row, "runFirst")
        if run then run() end
    end)
    row.first:SetPoint("RIGHT", row.second, "LEFT", -6, 0)
    Hover(row, ItemTip)
    row:SetScript("OnClick", function(self, mouse)
        local link = rawget(self, "link")
        if mouse ~= "RightButton" then Widgets.ItemClick(rawget(self, "itemID"), link) end
    end)
    row:Hide()
    return row
end

function Tab:BuildListView(body)
    local view = CreateFrame("Frame", nil, body)
    view:SetAllPoints(body)
    view:Hide()
    self.listView = view

    local heads = CreateFrame("Frame", nil, view)
    heads:SetPoint("TOPLEFT", 0, 0)
    heads:SetPoint("TOPRIGHT", 0, 0)
    heads:SetHeight(HEAD)
    Theme.Fill(heads, "header")
    self.heads = heads

    -- The cells, from the right: the buttons, the gain, where, the slot.
    local stop, map = L["Stop Tracking"], L["Show on Map"]
    local restore = L["Restore"]
    local buttons = math.max(Theme.TextWidth("small", stop) + Theme.TextWidth("small", map) + 48 + 6,
        Theme.TextWidth("small", restore) + 24) + 16
    local full = WIDTH - PAD * 2
    local columns = { buttons = buttons, gain = 80, where = 300, slot = 90 }
    columns.gainRight = buttons
    columns.whereRight = columns.gainRight + columns.gain + 8
    columns.slotRight = columns.whereRight + columns.where + 8
    columns.item = full - columns.slotRight - columns.slot - 8 - (ICON + 16)
    self.columns = columns

    self.headLabels = {
        item = Heading(heads, L["ITEM"]),
        slot = Heading(heads, L["SLOT"]),
        where = Heading(heads, L["WHERE"]),
        gain = Heading(heads, L["GAIN"], "RIGHT"),
    }
    self.headLabels.item:SetPoint("LEFT", ICON + 16, 0)
    self.headLabels.slot:SetPoint("LEFT", heads, "RIGHT", -(columns.slotRight + columns.slot), 0)
    self.headLabels.where:SetPoint("LEFT", heads, "RIGHT", -(columns.whereRight + columns.where), 0)
    self.headLabels.gain:SetPoint("RIGHT", heads, "RIGHT", -columns.gainRight, 0)

    local restoreAll = Button(heads, L["Restore All"], function()
        local logic = Logic()
        if logic then logic:RestoreAll() end
    end)
    restoreAll:SetPoint("RIGHT", -8, 0)
    restoreAll:SetHeight(18)
    Tip(restoreAll, L["Restore All"], L["Lets every ignored upgrade be picked again."])
    self.restoreAll = restoreAll

    local list = CreateFrame("Frame", nil, view)
    list:SetPoint("TOPLEFT", 0, -HEAD)
    list:SetPoint("BOTTOMRIGHT", 0, 22)
    Theme.Fill(list, "well")
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta) Tab:ScrollBy(-delta * WHEEL) end)
    self.list = list
    self.rows = {}
    for index = 1, MOST_ROWS do
        local row = self:BuildListRow(index)
        row.slot:SetPoint("TOPRIGHT", -columns.slotRight, -9)
        row.slot:SetWidth(columns.slot)
        row.where:SetPoint("TOPRIGHT", -columns.whereRight, -9)
        row.where:SetWidth(columns.where)
        row.gain:SetPoint("TOPRIGHT", -columns.gainRight, -8)
        row.gain:SetWidth(columns.gain)
        row.item:SetWidth(columns.item)
        self.rows[index] = row
    end

    local none = Theme.CreateLabel(list, "normal", "muted")
    none:SetPoint("TOPLEFT", 16, -18)
    none:SetWidth(full - 32)
    none:SetWordWrap(true)
    self.none = none

    local foot = Theme.CreateLabel(view, "small", "muted")
    foot:SetPoint("BOTTOMLEFT", 2, 4)
    foot:SetWidth(full - 4)
    self.foot = foot
end

function Tab:Build(area)
    if self.page then return self.page end
    if not (area and Logic()) then return nil end

    local page = CreateFrame("Frame", nil, area)
    page:SetAllPoints(area)
    Theme.Fill(page, "window")
    page:Hide()
    self.page = page

    local top = self:BuildBars(page)
    local body = CreateFrame("Frame", nil, page)
    body:SetPoint("TOPLEFT", PAD, -top)
    body:SetPoint("BOTTOMRIGHT", -PAD, 14)
    self.body = body
    self.bodyTop = top
    self:BuildQuestView(body)
    self:BuildListView(body)
    return page
end

--------------------------------------------------------------------------------
-- Drawing: the Quest view
--------------------------------------------------------------------------------

local function BodyHeight(self)
    local ok, height = pcall(self.page.GetHeight, self.page)
    if not (ok and type(height) == "number" and height > 200) then height = 620 end
    return height - self.bodyTop - 14
end

function Tab:PaintSources()
    local logic = Logic()
    local on = QuestOn()
    local picked = on and logic:Tab() or nil
    local y, shown = HEAD + 4, 0
    local width = self.leftWidth
    for index, tab in ipairs(logic.TABS) do
        local row = self.sourceRows[index]
        if logic:TabShown(tab.key) then
            shown = shown + 1
            local quest = on and logic:QuestOn(tab.key) or nil
            row.restKey = shown % 2 == 0 and "glassAlt" or "glass"
            row.picked = tab.key == picked
            row.link, row.itemID = quest and quest.link or nil, quest and quest.itemID or nil
            local gain = quest and quest.howMuch or ""
            row.gain:SetText(gain)
            local itemWidth = width - ICON - 16 - 10 - Theme.TextWidth("normal", gain) - 8
            row.item:SetWidth(itemWidth)
            if quest then
                Theme.SetItemIcon(row.icon, quest.link)
                row.item:SetText(ns.Items.ShowLink(quest.link) or "?")
                row.item:SetTextColor(Theme.Unpack("text"))
            else
                row.icon:Hide()
                local state = on and logic.states[tab.key] or nil
                -- Off, a source has nothing to say yet.
                row.item:SetText(not on and "" or state == "waiting" and L["Looking for your next upgrade..."]
                    or logic.NONE[tab.key] or L["No upgrade to chase right now."])
                row.item:SetTextColor(Theme.Unpack("muted"))
            end
            local height = math.max(ICON + 16, 20 + TextHeight(row.item, "normal", itemWidth) + 8)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 1, -y)
            row:SetPoint("TOPRIGHT", -1, -y)
            row:SetHeight(height)
            Paint(row)
            row:Show()
            y = y + height
        else
            row:Hide()
        end
    end
    self.sourceNote:ClearAllPoints()
    self.sourceNote:SetPoint("TOPLEFT", 10, -(y + 10))
end

local function HideDetail(self)
    self.icon:Hide()
    self.iconHit:Hide()
    self.name:Hide()
    self.gain:Hide()
    self.why:Hide()
    self.arrowButton:Hide()
    self.ignoreButton:Hide()
    self.queueButton:Hide()
    self.stepsHead:Hide()
    self.alsoHead:Hide()
    for _, chip in ipairs(self.chips) do chip:Hide() end
    for _, row in ipairs(self.stepRows) do row:Hide() end
    for _, row in ipairs(self.alsoRows) do row:Hide() end
end

--- A step's second line in the window: its note, then the quest's
--- objectives with their counts when the step is a quest in the log.
local function StepNote(step, now)
    local lines = {}
    if step.note and not step.done then lines[#lines + 1] = step.note end
    if now and type(step.progress) == "table" and ns.QuestLog then
        for _, line in ipairs(ns.QuestLog.ObjectiveLines(step.progress)) do
            lines[#lines + 1] = Colored(line.color or "text", line.text)
        end
    end
    return table.concat(lines, "\n")
end

function Tab:PaintDetail()
    local logic = Logic()
    local on = QuestOn()
    local quest = on and logic:Current() or nil
    self.turnOn:Hide()
    self.pickOne:Hide()
    if not quest then
        HideDetail(self)
        local text
        if not on then
            text = L["Equipment can pick your next gear upgrade and walk you to it step by step, like a quest, with an arrow showing the way. It's off until you turn it on."]
        elseif logic.state == "waiting" then
            text = L["Looking for your next upgrade..."]
        else
            text = logic.NONE[logic:Tab()] or L["No upgrade to chase right now."]
        end
        self.empty:SetText(text)
        self.empty:Show()
        local below = 18 + TextHeight(self.empty, "normal", self.rightWidth - 32) + 12
        local button = not on and self.turnOn or (logic.state ~= "waiting" and self.pickOne) or nil
        if button then
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", 16, -below)
            button:Show()
        end
        return
    end
    self.empty:Hide()

    local width = self.rightWidth
    Theme.SetItemIcon(self.icon, quest.link)
    self.iconHit.link, self.iconHit.itemID = quest.link, quest.itemID
    self.iconHit:Show()
    self.name:SetText(ns.Items.ShowLink(quest.link) or "?")
    self.name:Show()
    local nameHeight = TextHeight(self.name, "large", self.headWidth)
    local gain = Colored("good", quest.howMuch or "")
    local over = Tab.OverText(quest)
    if over ~= "" then gain = gain .. "  " .. Colored("muted", over) end
    if ns.WeaponSkills and ns.WeaponSkills:NeedsTraining(quest.link) then
        gain = gain .. "  " .. Colored("loss", L["Train"])
    end
    self.gain:SetText(gain)
    self.gain:ClearAllPoints()
    self.gain:SetPoint("TOPLEFT", 12 + BIG_ICON + 10, -(12 + nameHeight + 3))
    self.gain:Show()
    local y = 12 + math.max(BIG_ICON, nameHeight + 3 + TextHeight(self.gain, "normal", self.headWidth)) + 8

    self.ignoreButton:Show()
    self.arrowButton:SetLabelColor(ns.QuestArrow and ns.QuestArrow.IsOn() and "good" or "gilt")
    self.arrowButton:Show()
    local source = quest.source
    local tsq = ns.TradeskillsQueue
    if source and source.kind == "craft" and tsq and tsq:Available() then
        self.queueButton:SetText(tsq:Label(quest.itemID or source.itemID, source))
        self.queueButton:Show()
    else
        self.queueButton:Hide()
    end

    local why = logic.WhyText(quest)
    if why then
        self.why:SetText(why)
        self.why:ClearAllPoints()
        self.why:SetPoint("TOPLEFT", 12, -y)
        self.why:Show()
        y = y + TextHeight(self.why, "small", width - 24) + 8
    else
        self.why:Hide()
    end

    -- What it asks of you: green once met.
    local chips = Tab.Chips(quest)
    local x, line = 12, 0
    for index, chip in ipairs(self.chips) do
        local spec = chips[index]
        if spec then
            local chipWidth = math.max(34, Theme.TextWidth("tiny", spec.text) + 16)
            if x + chipWidth > width - 12 and x > 12 then
                x, line = 12, line + 1
            end
            chip.label:SetText(spec.text)
            chip:SetWidth(chipWidth)
            chip.label:SetTextColor(Theme.Unpack(spec.met and "good" or spec.plain and "text" or "warn"))
            chip:ClearAllPoints()
            chip:SetPoint("TOPLEFT", x, -(y + line * 22))
            chip:Show()
            x = x + chipWidth + 6
        else
            chip:Hide()
        end
    end
    if #chips > 0 then y = y + (line + 1) * 22 + 6 end

    -- The steps, the one to do now lit.
    self.stepsHead:ClearAllPoints()
    self.stepsHead:SetPoint("TOPLEFT", 12, -y)
    self.stepsHead:Show()
    y = y + 16
    local steps, current = logic:Steps(quest)
    local shown = 0
    for index, row in ipairs(self.stepRows) do
        local step = steps[index]
        if step then
            shown = shown + 1
            local now = index == current and not step.done
            local place = not step.done and type(step.place) == "table" and step.place.zone and step.place or nil
            row.stepIndex, row.place, row.isNow, row.picked = index, place, now, now
            row.restKey = shown % 2 == 0 and "glassAlt" or "glass"
            local turnIn = now and step.turnIn
            row.check:SetShown(step.done)
            row.turnIn:SetShown(turnIn and true or false)
            row.now:SetShown(now and not turnIn)
            row.dot:SetShown(not step.done and not now)
            local map = now and place ~= nil
            row.map:SetShown(map)
            local textWidth = width - 34 - 12 - (map and row.map:GetWidth() + 10 or 0)
            row.text:SetWidth(textWidth)
            row.text:SetText(step.text or "")
            row.text:SetTextColor(Theme.Unpack(step.done and "muted" or "text"))
            local height = 7 + TextHeight(row.text, "normal", textWidth)
            local note = StepNote(step, now)
            if note ~= "" then
                row.note:SetWidth(textWidth)
                row.note:SetText(note)
                row.note:ClearAllPoints()
                row.note:SetPoint("TOPLEFT", 34, -(height + 2))
                row.note:Show()
                height = height + 2 + TextHeight(row.note, "small", textWidth)
            else
                row.note:Hide()
            end
            height = math.max(ROW, height + 8)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 1, -y)
            row:SetPoint("TOPRIGHT", -1, -y)
            row:SetHeight(height)
            Paint(row)
            row:Show()
            y = y + height
        else
            row:Hide()
        end
    end

    -- Also Good: the next picks for the same slot.
    local also = logic:AlsoGood(quest)
    if #also == 0 then
        self.alsoHead:Hide()
        for _, row in ipairs(self.alsoRows) do row:Hide() end
        return
    end
    y = y + 10
    self.alsoHead:ClearAllPoints()
    self.alsoHead:SetPoint("TOPLEFT", 12, -y)
    self.alsoHead:Show()
    y = y + 16
    for index, row in ipairs(self.alsoRows) do
        local entry = also[index]
        if entry then
            local pick = entry.pick
            row.pick, row.link, row.itemID = pick, pick.link, pick.itemID
            Theme.SetItemIcon(row.icon, pick.link)
            row.item:SetText(ns.Items.ShowLink(pick.link) or "?")
            local percent = pick.result and tonumber(pick.result.percent)
            row.gain:SetText(percent and ("%+d%%"):format(math.floor(percent + 0.5)) or "")
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 1, -y)
            row:SetPoint("TOPRIGHT", -1, -y)
            Paint(row)
            row:Show()
            y = y + ROW
        else
            row:Hide()
        end
    end
end

--------------------------------------------------------------------------------
-- Drawing: the lists
--------------------------------------------------------------------------------

--- The lines a list view shows, and what it says with none.
function Tab:ListLines(view)
    local logic = Logic()
    if view == "tracking" then
        local lines = {}
        for _, hunt in ipairs(ns.Tracking and ns.Tracking:List() or {}) do
            local place = hunt.place
            local line = { itemID = hunt.itemID, link = hunt.link,
                slot = ns.Enchants and ns.Enchants.SlotName(hunt.slot) or "",
                where = hunt.got and Colored("good", L["In your bags: put it on"])
                    or (place and ns.Tracking.PlaceText(place)) or "",
                gain = GainOf(hunt.itemID) }
            if place and place.x and ns.Waypoints then
                line.first = { text = L["Show on Map"], run = function()
                    ns.Waypoints:Show(place, place.name, Theme.ItemIcon(hunt.link))
                end }
            end
            line.second = { text = L["Stop Tracking"], run = function() ns.Tracking:Untrack(hunt.itemID) end }
            lines[#lines + 1] = line
        end
        return lines, L["Nothing tracked yet. Track an upgrade in Find Upgrades to see it here."]
    end
    if view == "done" then
        local lines = {}
        for _, done in ipairs(Tab.DoneLines()) do
            lines[#lines + 1] = { itemID = done.itemID, link = done.link, gain = done.gain, slot = "", where = "" }
        end
        return lines, L["No upgrades done yet."]
    end
    local lines = {}
    for _, item in ipairs(logic:IgnoredList()) do
        lines[#lines + 1] = { itemID = item.itemID, link = item.link or item.name, slot = "", where = "",
            second = { text = L["Restore"], run = function() logic:Restore(item.itemID) end } }
    end
    return lines, L["Nothing ignored. Upgrades you ignore are listed here, where you can restore them."]
end

function Tab:PaintList(view)
    local lines, none = self:ListLines(view)
    self.lines = lines
    local tracking = view == "tracking"
    self.headLabels.slot:SetShown(tracking)
    self.headLabels.where:SetShown(tracking)
    self.headLabels.gain:SetShown(view ~= "ignored")
    self.restoreAll:SetShown(view == "ignored" and #lines > 0)

    local room = BodyHeight(self) - HEAD - 22
    local offset = math.max(0, math.min(self.offset or 0, math.max(0, #lines - 1)))
    self.offset = offset
    local y, shown, last = 0, 0, offset
    for index, row in ipairs(self.rows) do
        local line = lines[index + offset]
        row:Hide()
        if line and shown == index - 1 then
            row.link, row.itemID = line.link, line.itemID
            row.restKey = index % 2 == 0 and "glassAlt" or "glass"
            Theme.SetItemIcon(row.icon, line.link)
            row.item:SetText(ns.Items.ShowLink(line.link) or "?")
            row.slot:SetText(line.slot or "")
            row.where:SetText(line.where or "")
            row.gain:SetText(line.gain or "")
            for _, name in ipairs({ "first", "second" }) do
                local spec, button = line[name], row[name]
                row[name == "first" and "runFirst" or "runSecond"] = spec and spec.run or nil
                if spec then
                    button:SetText(spec.text)
                    button:SetWidth(math.max(60, Theme.TextWidth("small", spec.text) + 24))
                    button:Show()
                else
                    button:Hide()
                end
            end
            local height = math.max(ROW, 8 + math.max(TextHeight(row.item, "normal", self.columns.item),
                TextHeight(row.where, "small", self.columns.where)) + 8)
            if index == 1 or y + height <= room then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -y)
                row:SetPoint("TOPRIGHT", 0, -y)
                row:SetHeight(height)
                Paint(row)
                row:Show()
                y = y + height
                shown = index
                last = index + offset
            end
        end
    end
    self.none:SetShown(#lines == 0)
    self.none:SetText(none)
    local foot = ""
    if #lines > shown and shown > 0 then
        foot = L.Format("%d to %d of %d. Scroll for more.", offset + 1, last, #lines)
    elseif view == "done" and Logic():DoneCount() > 0 then
        local count = Logic():DoneCount()
        foot = count == 1 and L["1 upgrade done"] or L.Format("%d upgrades done", count)
    end
    self.foot:SetText(foot)
end

function Tab:ScrollBy(steps)
    if self:View() == "quest" or not self.lines then return end
    local before = self.offset or 0
    self.offset = math.max(0, math.min(before + steps, math.max(0, #self.lines - 1)))
    if self.offset ~= before then self:PaintList(self:View()) end
end

--------------------------------------------------------------------------------
-- Looking and drawing
--------------------------------------------------------------------------------

function Tab:Refresh()
    if not self:IsShown() then return nil end
    self:Sync()
    local counts = Tab.Counts()
    for _, key in ipairs(VIEWS) do self.views:SetTabText(key, Tab.ViewText(key, counts[key])) end
    local view = self:View()
    self.views:Select(view, true)
    self.questView:SetShown(view == "quest")
    self.listView:SetShown(view ~= "quest")
    if view == "quest" then
        self:PaintSources()
        self:PaintDetail()
    else
        self:PaintList(view)
    end
    return view
end

--- Once for a burst, and only while the page shows.
function Tab:RefreshSoon()
    if not self:IsShown() or self.pending then return end
    local after = C_Timer and C_Timer.After
    if type(after) ~= "function" then return self:Refresh() end
    self.pending = true
    after(0.1, function()
        Tab.pending = false
        Tab:Refresh()
    end)
end

function Tab:OnUpgradeQuestChanged() self:RefreshSoon() end
function Tab:OnTrackingChanged() self:RefreshSoon() end
function Tab:OnQuestArrowChanged() self:RefreshSoon() end
function Tab:OnQuestFilterChanged() self:RefreshSoon() end

function Tab:IsShown()
    local page = self.page
    if not Shown(page) then return false end
    local ok, visible = pcall(page.IsVisible, page)
    if ok and type(visible) == "boolean" then return visible end
    return true
end

function Tab:Show()
    if not self.page then return end
    self.page:Show()
    self:Refresh()
end

function Tab:Hide()
    if self.page then self.page:Hide() end
end

--- Open the Equipment window on this tab, on a view when one is named.
function Tab:Open(view)
    if view then self.view, self.offset = view, 0 end
    if ns.GearWindow then ns.GearWindow:Open("quest") end
    if view then self:Refresh() end
end

function Tab:OnEnable()
    -- An ignored upgrade drawn as "Item 123" takes its name once the
    -- client sends it.
    ns.Items:WatchNames(function() Tab:RefreshSoon() end)
    ns.RegisterEvent(self, "PLAYER_MONEY", function()
        if Tab:IsShown() and Tab:View() == "quest" then Tab:RefreshSoon() end
    end)
end

if ns.GearWindow then ns.GearWindow:AddPage("quest", Tab) end
