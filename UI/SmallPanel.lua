-- Blackthornes Equipment -- UI/SmallPanel.lua
-- The small panel (rework step 4, the owner approved the mockup
-- 2026-11-22, asking that it "not take up much space and be easily
-- readable"): the one panel that stays on screen while you play. It takes
-- the place of the old upgrade quest panel and the Upgrade Hunts panel,
-- which rework step 6 took out; the menu choices, the map pin and the size
-- words they kept live here now.
--
-- 250 wide. One thin bar holds the tabs (Quest, Tracking, Log), a small
-- gold button right after them that opens the Upgrade Quest tab (the owner
-- asked 2026-11-23, from a mockup), the fold gem and the red close gem.
-- There is no title bar, footer or button row.
--   Quest     the upgrade, the step to do now and five marks for how far
--             along it is. A click on the step opens every step; a click
--             again closes them.
--   Tracking  the upgrades tracked, one line each.
--   Log       the character's quests, one line each, with a count, a
--             check, or the gain when its reward is an upgrade.
-- One line per thing; a long name wraps and nothing is cut short. What
-- else there is to say waits on the hover. Arrow, Show on Map, Ignore and
-- the options are on the right-click menu and on the Upgrade Quest tab
-- (UI/UpgradeQuestTab.lua).
--
-- The fold gem folds it to one line, the step to do now. A right-click on
-- the gem folds it into a round button (UI/FoldWindow.lua). The red gem
-- turns the upgrade quest off and keeps its quests, as before.
--
-- Saved, all as the old panel kept them, so nobody's panel moves:
-- `questPoint`, `questRelativePoint`, `questX`, `questY`, `questScaleAt`,
-- `questScale`, `questPanelSeeThrough`. New: `questPanelOff` (Panel: Show
-- unticked), `questPanelLine` (folded to one line), `questPanelSteps`
-- (every step open), all account wide, and the character's `panelTab`.
-- The Log tab is still the character's `questLogTab`.
--
-- Nothing here judges gear or starts a scan. It draws what the upgrade
-- quest, the tracker and the quest log already hold, and only while shown.

local _, ns = ...
local L = ns.L

local Panel = ns.NewModule("SmallPanel")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Motion = ns.Motion

local WIDTH = 250
local BAR = 24
local PAD = 8
local ICON = 20
local ROW_ICON = 17
local MARK = 12
local GEM = 15
local OPEN_SIZE = 18
local OPEN_ICON = [[Interface\Icons\INV_Scroll_03]]
local MARKS = 5
local MARK_HEIGHT = 4
local MOST_STEPS = 14
local MOST_ROWS = 8
local SCALE_MIN, SCALE_MAX = 50, 150

Panel.WIDTH = WIDTH
Panel.MARKS = MARKS

local DONE_ICON = [[Interface\RaidFrame\ReadyCheck-Ready]]
local TURN_IN_ICON = [[Interface\GossipFrame\ActiveQuestIcon]]

local VIEWS = { "quest", "tracking", "log" }

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

--- How tall a label's words run at its width: the client's answer, else a
--- measure of the words.
local function TextHeight(label, size, width)
    local text = label:GetText() or ""
    if text == "" then return 0 end
    local ok, height = pcall(label.GetStringHeight, label)
    if ok and type(height) == "number" and height > 0 then return height end
    local plain = text:gsub("|H.-|h", ""):gsub("|h", "")
    local lines = math.max(1, math.ceil(Theme.TextWidth(size, plain) / math.max(1, width)))
    return lines * ((Theme.sizes[size] or 12) + 2)
end

local function InCombat()
    return ns.Worker ~= nil and ns.Worker.InCombat() == true
end

--------------------------------------------------------------------------------
-- What it shows
--------------------------------------------------------------------------------

local function QuestOn()
    return ns.UpgradeQuest ~= nil and ns.UpgradeQuest:IsEnabled()
end

local function HuntCount()
    return ns.Tracking and ns.Tracking:Count() or 0
end

--- Is the panel wanted on screen? While the upgrade quest is on, or while
--- anything is tracked and "Upgrade Tracker:" is ticked. Never with
--- "Panel: Show" unticked, and not once its red gem put it away.
function Panel:Wanted()
    if not ns.db then return false end
    if ns.db.questPanelOff == true then return false end
    if QuestOn() then return true end
    if self.closed then return false end
    return ns.db.showTracker ~= false and HuntCount() > 0
end

--- "Panel: Show" on the Upgrade Quest tab.
function Panel:IsOff()
    return ns.db ~= nil and ns.db.questPanelOff == true
end

function Panel:SetOff(off)
    if not ns.db then return end
    ns.db.questPanelOff = off and true or nil
    self.closed = nil
    self:Refresh()
    if ns.QuestTab and ns.QuestTab.Sync then ns.QuestTab:Sync() end
end

--- The tab showing: "quest", "tracking" or "log". With the upgrade quest
--- off there is no Quest tab.
function Panel:View()
    local char = ns.charDB
    local view = "quest"
    if char and char.questLogTab == true then
        view = "log"
    elseif char and char.panelTab == "tracking" then
        view = "tracking"
    end
    if view == "quest" and not QuestOn() then view = "tracking" end
    return view
end

function Panel:SetView(view)
    local char = ns.charDB
    if not char then return end
    char.questLogTab = view == "log" and true or nil
    char.panelTab = view == "tracking" and "tracking" or nil
    self.offset = 0
    if ns.QuestLogUI then ns.QuestLogUI:CloseMenu() end
    if view == "log" then self.logDirty = true end
    self:Refresh()
    if ns.SettingsUI and ns.SettingsUI.Refresh then pcall(ns.SettingsUI.Refresh, ns.SettingsUI) end
end

--- Folded to one line?
function Panel:OneLine()
    return ns.db ~= nil and ns.db.questPanelLine == true
end

function Panel:SetOneLine(on)
    if not ns.db then return end
    ns.db.questPanelLine = on and true or nil
    self:Refresh()
end

--- Is every step open?
function Panel:StepsOpen()
    return ns.db ~= nil and ns.db.questPanelSteps == true
end

function Panel:SetStepsOpen(on)
    if not ns.db then return end
    ns.db.questPanelSteps = on and true or nil
    self:Refresh()
end

--- How many of the five marks are done, and whether one is under way.
function Panel.MarksFor(done, total)
    if not total or total <= 0 then return 0, false end
    if done >= total then return MARKS, false end
    local lit = math.floor(done * MARKS / total)
    return math.min(lit, MARKS - 1), true
end

--- An item's gain from the finder's last scan, as "+18%", or nil. Read
--- only: nothing is judged for it.
function Panel.GainOf(itemID)
    local found = ns.Finder and ns.Finder.latest
    if type(found) ~= "table" or type(found.all) ~= "table" then return nil end
    if Panel.gainsOf ~= found then
        local gains = {}
        for _, list in pairs(found.all) do
            for _, pick in ipairs(list) do
                local result = pick.result
                local percent = result and tonumber(result.percent)
                if pick.itemID and percent and not gains[pick.itemID] then
                    gains[pick.itemID] = ("%+d%%"):format(math.floor(percent + 0.5))
                end
            end
        end
        Panel.gainsOf, Panel.gains = found, gains
    end
    return Panel.gains[itemID]
end

--- What a quest's line in the Log shows on its right: the gain when its
--- reward is an upgrade, a check once it is ready, else its count.
-- @return text, colour key, or nil
function Panel.LogMark(quest)
    local logic = ns.UpgradeQuest
    local mark = logic and quest.questID and logic.RewardMark and logic:RewardMark(quest.questID)
    if type(mark) == "table" and not mark.empty and (tonumber(mark.percent) or 0) > 0 then
        return ("+%d%%"):format(mark.percent), "good"
    end
    if quest.failed then return nil end
    if quest.complete then return "check", "good" end
    local objectives = quest.objectives or {}
    local open, done = nil, 0
    for _, objective in ipairs(objectives) do
        if objective.done then done = done + 1 else open = open or objective end
    end
    if #objectives == 1 and open then
        local count = type(open.text) == "string" and open.text:match("(%d+%s*/%s*%d+)")
        if count then return (count:gsub("%s", "")), "text" end
    end
    if #objectives > 1 then return ("%d/%d"):format(done, #objectives), "text" end
    return nil
end

local function HereZone()
    for _, name in ipairs({ "GetRealZoneText", "GetZoneText" }) do
        local fn = _G[name]
        if type(fn) == "function" then
            local ok, zone = pcall(fn)
            if ok and type(zone) == "string" and zone ~= "" then return zone end
        end
    end
    return nil
end

--- An arrow aimed at a quest that has left the log lets it go. An aim with
--- no quest (the weapon master) never came from the log, so it stays.
function Panel:ForgetGone()
    local arrow = ns.QuestArrow
    local free = arrow and arrow:FreeQuest()
    local data = self.logData
    if not (free and free.questID ~= nil and data and data.how) then return end
    for _, zone in ipairs(data.zones or {}) do
        for _, quest in ipairs(zone.quests or {}) do
            if quest.questID == free.questID and quest.title == free.title then return end
        end
    end
    arrow:ForgetQuest(free.questID)
end

--- The quests the Log lists: the ones in the zone you are in first, then
--- the rest in the log's order. Only tracked ones with Tracked Only on.
function Panel:LogLines()
    if self.logDirty ~= false or not self.logData then
        self.logData = ns.QuestLog and ns.QuestLog:Read() or { zones = {} }
        self.logDirty = false
        self:ForgetGone()
    end
    local trackedOnly = ns.QuestLogUI and ns.QuestLogUI:TrackedOnly()
    local here = HereZone()
    local first, rest = {}, {}
    for _, zone in ipairs(self.logData.zones or {}) do
        for _, quest in ipairs(zone.quests or {}) do
            if not trackedOnly or quest.tracked then
                local list = (here and zone.title == here) and first or rest
                list[#list + 1] = quest
            end
        end
    end
    for _, quest in ipairs(rest) do first[#first + 1] = quest end
    return first
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

--- The gold triangle that marks the step to do now.
local function Marker(parent)
    local mark = parent:CreateTexture(nil, "ARTWORK")
    mark:SetSize(MARK, MARK)
    if ns.Titanforged then mark:SetTexture(ns.Titanforged.MEDIA .. "SortArrow") end
    pcall(mark.SetRotation, mark, math.pi / 2)
    pcall(mark.SetVertexColor, mark, Theme.Unpack("accent"))
    return mark
end

--- A dark glass line: `glass` and `glassAlt` in turn, a fine line under
--- it, a gold edge under the mouse or when picked.
local function Glass(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row.restKey = index % 2 == 0 and "glassAlt" or "glass"
    row.background = Theme.Fill(row, row.restKey)
    local under = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    under:SetPoint("BOTTOMLEFT")
    under:SetPoint("BOTTOMRIGHT")
    under:SetHeight(1)
    under:SetColorTexture(Theme.Unpack("border", 0.6))
    row.under = under
    local edge = row:CreateTexture(nil, "ARTWORK")
    edge:SetPoint("TOPLEFT")
    edge:SetPoint("BOTTOMLEFT")
    edge:SetWidth(3)
    edge:Hide()
    row.edge = edge
    if row.RegisterForClicks then row:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    if ns.SeeThrough then
        ns.SeeThrough:AddGlass("panel", row.background)
        ns.SeeThrough:AddGlass("panel", under)
    end
    return row
end

local function PaintGlass(row)
    local picked = rawget(row, "picked") == true
    local over = rawget(row, "over") == true
    row.background:SetColorTexture(Theme.Unpack(picked and "glassActive" or over and "glassHover" or row.restKey))
    row.edge:SetShown(picked or over)
    row.edge:SetColorTexture(Theme.Unpack(picked and "accentHi" or "accent"))
end

function Panel:BuildTab(key)
    local tab = CreateFrame("Button", nil, self.bar)
    tab:SetHeight(BAR)
    tab.key = key
    tab.label = Theme.CreateLabel(tab, "small", "muted", "CENTER")
    tab.label:SetPoint("CENTER", 0, 0)
    tab.line = tab:CreateTexture(nil, "ARTWORK")
    tab.line:SetPoint("BOTTOMLEFT", 2, 0)
    tab.line:SetPoint("BOTTOMRIGHT", -2, 0)
    tab.line:SetHeight(2)
    tab.line:SetColorTexture(Theme.Unpack("accentHi"))
    tab.line:Hide()
    tab:SetScript("OnClick", function(self) Panel:SetView(self.key) end)
    tab:SetScript("OnEnter", function(self)
        if Panel:View() ~= self.key then self.label:SetTextColor(Theme.Unpack("text")) end
    end)
    tab:SetScript("OnLeave", function(self)
        if Panel:View() ~= self.key then self.label:SetTextColor(Theme.Unpack("muted")) end
    end)
    return tab
end

--- The small gold button after the tabs: opens the Upgrade Quest tab.
function Panel:BuildOpenButton()
    local button = CreateFrame("Button", nil, self.bar)
    button:SetSize(OPEN_SIZE, OPEN_SIZE)
    button.fill = Theme.Fill(button, "header")
    Theme.Border(button, "accent")
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 2, -2)
    button.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    button.icon:SetTexture(OPEN_ICON)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button:SetScript("OnClick", function()
        GameTooltip:Hide()
        Panel:OpenTab()
    end)
    button:SetScript("OnEnter", function(self)
        Theme.SetBorderColor(self, "accentHi")
        self.fill:SetColorTexture(Theme.Unpack("glassHover"))
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Upgrade Quest"], Theme.Unpack("accent"))
        GameTooltip:AddLine(L["Opens the Upgrade Quest tab."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function(self)
        Theme.SetBorderColor(self, "accent")
        self.fill:SetColorTexture(Theme.Unpack("header"))
        GameTooltip:Hide()
    end)
    return button
end

function Panel:BuildStepRow(index)
    local row = Glass(self.body, index)
    row.index = index
    row.check = row:CreateTexture(nil, "ARTWORK")
    row.check:SetSize(MARK, MARK)
    row.check:SetPoint("TOPLEFT", PAD, -5)
    row.check:SetTexture(DONE_ICON)
    row.now = Marker(row)
    row.now:SetPoint("TOPLEFT", PAD, -5)
    row.dot = row:CreateTexture(nil, "ARTWORK")
    row.dot:SetSize(4, 4)
    row.dot:SetPoint("TOPLEFT", PAD + 4, -9)
    row.dot:SetColorTexture(Theme.Unpack("dim"))
    row.text = Theme.CreateLabel(row, "normal", "text")
    row.text:SetPoint("TOPLEFT", PAD + MARK + 6, -4)
    row.text:SetWidth(WIDTH - PAD * 2 - MARK - 6)
    row.text:SetWordWrap(true)
    row:SetScript("OnEnter", function(self)
        self.over = true
        PaintGlass(self)
        Panel:StepTip(self)
    end)
    row:SetScript("OnLeave", function(self)
        self.over = false
        PaintGlass(self)
        GameTooltip:Hide()
    end)
    row:SetScript("OnClick", function(self, mouse) Panel:StepClicked(self, mouse) end)
    row:Hide()
    return row
end

function Panel:BuildListRow(index)
    local row = Glass(self.body, index)
    row.icon = Theme.CreateItemIcon(row, ROW_ICON)
    row.icon:SetPoint("TOPLEFT", PAD, -4)
    row.text = Theme.CreateLabel(row, "normal", "text")
    row.text:SetWordWrap(true)
    row.mark = Theme.CreateLabel(row, "normal", "good", "RIGHT")
    row.mark:SetPoint("TOPRIGHT", -PAD, -5)
    row.check = row:CreateTexture(nil, "ARTWORK")
    row.check:SetSize(MARK, MARK)
    row.check:SetPoint("TOPRIGHT", -PAD, -5)
    row.check:SetTexture(DONE_ICON)
    row.check:Hide()
    row:SetScript("OnEnter", function(self)
        self.over = true
        PaintGlass(self)
        Panel:ListTip(self)
    end)
    row:SetScript("OnLeave", function(self)
        self.over = false
        PaintGlass(self)
        GameTooltip:Hide()
    end)
    row:SetScript("OnClick", function(self, mouse) Panel:ListClicked(self, mouse) end)
    row:Hide()
    return row
end

function Panel:Build()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "BlackthornesEquipmentPanel", UIParent)
    frame:SetSize(WIDTH, BAR)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame.fill = Theme.Fill(frame, "window")
    Theme.Border(frame, "borderLit")
    Theme.Halo(frame, 10, 0.14)
    self.frame = frame

    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
        if ns.QuestLogUI then
            ns.QuestLogUI.dragging = true
            ns.QuestLogUI:PlaceItems()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        Panel:SavePosition()
        if ns.QuestLogUI then
            ns.QuestLogUI.dragging = nil
            ns.QuestLogUI:PlaceItemsSoon()
        end
    end)
    frame:SetScript("OnMouseUp", function(_, mouse)
        if mouse == "RightButton" then Panel:OpenMenu() end
    end)
    -- The Log tab's item buttons and the game's tracker go with the panel.
    frame:HookScript("OnShow", function()
        if ns.QuestLogUI then ns.QuestLogUI:OnPanelShown(true) end
    end)
    frame:HookScript("OnHide", function()
        if ns.QuestLogUI then ns.QuestLogUI:OnPanelShown(false) end
        Panel:HideOffer()
    end)
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta) Panel:ScrollBy(-delta) end)

    -- The one thin bar: the tabs on the left, the two gems on the right.
    local bar = Theme.CreatePanel(frame, "header", false)
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("TOPRIGHT")
    bar:SetHeight(BAR)
    bar:EnableMouse(false)
    self.bar = bar
    self.tabs = {}
    for _, key in ipairs(VIEWS) do self.tabs[key] = self:BuildTab(key) end
    self.openTab = self:BuildOpenButton()

    -- The gems ride on a holder of their own, so the fold gem can stay on
    -- the one line when the bar is gone.
    local holder = CreateFrame("Frame", nil, frame)
    holder:SetPoint("TOPRIGHT")
    holder:SetSize(GEM * 2 + 14, BAR)
    self.gemHolder = holder
    local gems = Widgets.CreatePanelGems(holder, {
        size = GEM,
        onClose = function() Panel:Close() end,
    })
    self.gems = gems
    if gems.fold.RegisterForClicks then gems.fold:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    gems.fold:SetScript("OnClick", function(_, mouse)
        GameTooltip:Hide()
        if mouse == "RightButton" then
            Panel:ToRound()
        else
            Panel:SetOneLine(not Panel:OneLine())
        end
    end)
    gems.fold:HookScript("OnEnter", function()
        GameTooltip:AddLine(L["Right-click to fold it into a round button."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    gems.close:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Close the upgrade quest"], Theme.Unpack("accent"))
        GameTooltip:AddLine(L["Your quests stay saved. Bring it back with Upgrade quest in the gear window, or Shift-click the minimap button."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    if ns.FoldWindow and ns.FoldWindow.Join then
        ns.FoldWindow:Join(frame, {
            key = "Panel", title = L["Upgrade Quest"],
            pill = function()
                local rating = ns.UpgradeQuest and ns.UpgradeQuest:GearRating()
                return rating and rating.waiting and rating.waiting > 0 and tostring(rating.waiting) or nil
            end,
            onToggle = function(folded) if not folded then Panel:Refresh() end end,
        })
    end

    local body = CreateFrame("Frame", nil, frame)
    body:SetPoint("TOPLEFT", 0, -BAR)
    body:SetPoint("TOPRIGHT", 0, -BAR)
    body:SetHeight(1)
    self.body = body

    -- The upgrade: its icon, its name and its gain.
    local item = CreateFrame("Button", nil, body)
    item:SetPoint("TOPLEFT", 0, 0)
    item:SetPoint("TOPRIGHT", 0, 0)
    if item.RegisterForClicks then item:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    item.icon = Theme.CreateItemIcon(item, ICON)
    item.icon:SetPoint("TOPLEFT", PAD, -6)
    item.gain = Theme.CreateLabel(item, "large", "good", "RIGHT")
    item.gain:SetPoint("TOPRIGHT", -PAD, -8)
    item.name = Theme.CreateLabel(item, "large", "text")
    item.name:SetPoint("TOPLEFT", PAD + ICON + 7, -8)
    item.name:SetWordWrap(true)
    item:SetScript("OnEnter", function(self)
        local quest = rawget(self, "quest")
        if not quest then return end
        Widgets.ItemTooltip(self, quest.itemID, quest.link, "ANCHOR_LEFT")
    end)
    item:SetScript("OnLeave", function() GameTooltip:Hide() end)
    item:SetScript("OnClick", function(self, mouse)
        if mouse == "RightButton" then return Panel:OpenMenu() end
        local quest = rawget(self, "quest")
        if quest and Widgets.ItemClick(quest.itemID, quest.link) then return end
        Panel:OpenTab()
    end)
    self.item = item

    -- The step to do now: the biggest, brightest line.
    local step = CreateFrame("Button", nil, frame)
    if step.RegisterForClicks then step:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    step.now = Marker(step)
    step.now:SetPoint("TOPLEFT", PAD, -4)
    step.turnIn = step:CreateTexture(nil, "ARTWORK")
    step.turnIn:SetSize(MARK + 2, MARK + 2)
    step.turnIn:SetPoint("TOPLEFT", PAD - 1, -3)
    step.turnIn:SetTexture(TURN_IN_ICON)
    step.turnIn:Hide()
    step.text = Theme.CreateLabel(step, "large", "text")
    step.text:SetPoint("TOPLEFT", PAD + MARK + 6, -2)
    step.text:SetWordWrap(true)
    step:SetScript("OnEnter", function(self) Panel:StepTip(self) end)
    step:SetScript("OnLeave", function() GameTooltip:Hide() end)
    step:SetScript("OnClick", function(self, mouse) Panel:StepClicked(self, mouse) end)
    self.step = step

    -- Five marks for how far along the quest is.
    self.marks = {}
    local markWidth = (WIDTH - PAD * 2 - (MARKS - 1) * 3) / MARKS
    for index = 1, MARKS do
        local mark = body:CreateTexture(nil, "ARTWORK")
        mark:SetSize(markWidth, MARK_HEIGHT)
        self.marks[index] = mark
    end

    -- What it says with nothing to show.
    local empty = Theme.CreateLabel(body, "normal", "muted")
    empty:SetPoint("TOPLEFT", PAD, -8)
    empty:SetWidth(WIDTH - PAD * 2)
    empty:SetWordWrap(true)
    self.empty = empty

    self.stepRows = {}
    for index = 1, MOST_STEPS do self.stepRows[index] = self:BuildStepRow(index) end
    self.rows = {}
    for index = 1, MOST_ROWS do self.rows[index] = self:BuildListRow(index) end

    -- More lines than rows: the wheel moves the list, and a thin gold
    -- thumb down the right edge shows where it is.
    local thumb = frame:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(3)
    thumb:SetColorTexture(Theme.Unpack("borderLit"))
    thumb:Hide()
    self.thumb = thumb

    -- The size grip: 50% to 150%, the size the old panel kept.
    Widgets.ApplySize(frame, self:SizePercent(), SCALE_MIN, SCALE_MAX)
    self.grip = Widgets.CreateSizeGrip(frame, {
        name = "panel", min = SCALE_MIN, max = SCALE_MAX,
        get = function() return Panel:SizePercent() end,
        save = function(percent)
            if ns.db then ns.db.questScale = percent / 100 end
            if ns.SettingsUI and ns.SettingsUI.Refresh then pcall(ns.SettingsUI.Refresh, ns.SettingsUI) end
        end,
        done = function()
            Panel:SavePosition()
            if ns.QuestLogUI then ns.QuestLogUI:PlaceItemsSoon() end
        end,
    })
    pcall(self.grip.SetAlpha, self.grip, 0.45)
    self.grip:HookScript("OnEnter", function(self) pcall(self.SetAlpha, self, 1) end)
    self.grip:HookScript("OnLeave", function(self) pcall(self.SetAlpha, self, 0.45) end)

    self:RestorePosition()
    if ns.SeeThrough then
        ns.SeeThrough:AddGlass("panel", frame.fill)
        ns.SeeThrough:AddGlass("panel", bar.background)
        ns.SeeThrough:Attach("panel", frame)
    end
    frame:Hide()
    return frame
end

--------------------------------------------------------------------------------
-- What the old panel kept: the menu's choices, the map pin and the size
-- words. Moved here when rework step 6 took the old panel out.
--------------------------------------------------------------------------------

-- The sizes Settings' Panel Size and /beq quest size name.
Panel.SIZES = {
    { key = "small", text = L["Small"], scale = 0.8 },
    { key = "normal", text = L["Normal"], scale = 1 },
    { key = "large", text = L["Large"], scale = 1.2 },
}

--- The quest level stepper's place: 0 to 10 levels up, or 11 for any.
function Panel.QuestLevelsValue()
    local finder = ns.Finder
    if not finder then return 4 end
    return finder:QuestLevelsAbove() or finder.QUEST_LEVELS_ANY
end

--- Its words, as Where to get upgrades says them.
function Panel.QuestLevelsText(value)
    if ns.FinderUI and ns.FinderUI.QuestLevelsText then return ns.FinderUI.QuestLevelsText(value) end
    return tostring(value)
end

--- The lines the right-click menu shares with Settings and the Upgrade
--- Quest tab, each ticked as it stands. A click changes it.
function Panel:OptionLines()
    local quest, finder = ns.UpgradeQuest, ns.Finder
    local lines = {}
    if quest then
        local zoneOnly = quest:ZoneOnly()
        lines[#lines + 1] = { text = L["This Zone Only"], checked = zoneOnly,
            run = function()
                quest:SetZoneOnly(not zoneOnly)
                quest:BoxChanged("zone", not zoneOnly)
            end }
        local swap = quest:ZoneSwap()
        lines[#lines + 1] = { text = L["Change on a New Zone"], checked = swap, disabled = not zoneOnly,
            run = function() quest:SetZoneSwap(not swap) end }
    end
    if finder then
        local solo = finder:SoloOnly()
        lines[#lines + 1] = { text = L["Solo Quests Only"], checked = solo,
            run = function()
                finder:SetSoloOnly(not solo)
                if quest then quest:BoxChanged("solo", not solo) end
            end }
    end
    if quest then
        local stepOnly = quest:StepOnly()
        lines[#lines + 1] = { text = L["Current Step Only"], checked = stepOnly,
            run = function() quest:SetStepOnly(not stepOnly) end }
    end
    if quest and quest.STYLES then
        -- How You Gear Up: one pick sets the boxes and the tab order (card D).
        local style = quest:Style()
        lines[#lines + 1] = { text = L["How You Gear Up:"] .. " " .. (style.label or L["Anything"]),
            run = function() Panel:OpenStyles() end }
    end
    if finder then
        lines[#lines + 1] = { text = L["Quest Level:"] .. " " .. Panel.QuestLevelsText(Panel.QuestLevelsValue()),
            run = function() Panel:OpenLevels() end }
    end
    lines[#lines + 1] = { text = L["Settings"], run = function()
        -- Opened on the Upgrade quest page (UI/SettingsPages.lua).
        if ns.db then ns.db.settingsPage = "quest" end
        if ns.SettingsUI then ns.SettingsUI:Show() end
    end }
    return lines
end

--- Quest Level's choices, the one set ticked.
function Panel:LevelLines()
    local finder = ns.Finder
    if not finder then return {} end
    local now = Panel.QuestLevelsValue()
    local lines = {}
    for value = 0, finder.QUEST_LEVELS_ANY or 11 do
        lines[#lines + 1] = { text = Panel.QuestLevelsText(value), checked = value == now,
            run = function() finder:SetQuestLevelsAbove(value) end }
    end
    return lines
end

--- How You Gear Up's choices, the one picked ticked, then what it sets.
function Panel:StyleLines()
    local quest = ns.UpgradeQuest
    if not (quest and quest.STYLES) then return {} end
    local now = quest:Style()
    local lines = {}
    for _, style in ipairs(quest.STYLES) do
        lines[#lines + 1] = { text = style.label, checked = style.key == now.key,
            run = function() quest:SetStyle(style.key) end }
    end
    local sets = quest.StyleLines(now)
    if sets and #sets > 0 then
        lines[#lines + 1] = { text = L["This sets:"], disabled = true }
        for _, line in ipairs(sets) do lines[#lines + 1] = { text = "  " .. line, disabled = true } end
    end
    return lines
end

function Panel:OpenStyles()
    if not ns.RowMenu then return end
    local function Open() ns.RowMenu:Open(Panel:StyleLines(), { title = L["How You Gear Up:"] }) end
    if C_Timer and C_Timer.After then C_Timer.After(0, Open) else Open() end
end

function Panel:OpenLevels()
    if not ns.RowMenu then return end
    -- The menu closes as a line runs; open the levels once it has.
    local function Open() ns.RowMenu:Open(Panel:LevelLines(), { title = L["Quest Level:"] }) end
    if C_Timer and C_Timer.After then C_Timer.After(0, Open) else Open() end
end

function Panel:ShowOnMap()
    local place = ns.UpgradeQuest and ns.UpgradeQuest:NextPlace()
    if not (place and ns.Waypoints) then return false end
    -- A spot gets the big marker on it; only a zone, a "Somewhere in ZONE"
    -- marker in its middle. Either way the arrow shows the way when the
    -- game won't take its own pin.
    local quest = ns.UpgradeQuest.Current and ns.UpgradeQuest:Current()
    local icon = quest and quest.link and Theme.ItemIcon(quest.link)
    return ns.Waypoints:Show(place, place.name, icon)
end

--- A frame's own scale, or 1 when it cannot say.
function Panel.ScaleOf(frame)
    local ok, scale = pcall(function() return frame:GetScale() end)
    if ok and type(scale) == "number" and scale > 0 then return scale end
    return 1
end

--- How much to multiply a saved offset by, taken at `saved` size and put
--- back at `now`.
function Panel.PositionFactor(saved, now)
    saved = tonumber(saved) or 1
    now = tonumber(now) or 1
    if saved <= 0 or now <= 0 then return 1 end
    return saved / now
end

--- The name of a size, "Small (80%)", or "87%" for one dragged to.
function Panel.ScaleText(scale)
    local percent = math.floor((tonumber(scale) or 1) * 100 + 0.5)
    for _, size in ipairs(Panel.SIZES) do
        if math.floor(size.scale * 100 + 0.5) == percent then
            return ("%s (%d%%)"):format(size.text, percent)
        end
    end
    return ("%d%%"):format(percent)
end

--- "small", "normal", "large", "80", "80%" or "0.8" as a size, or nil.
function Panel.ParseSize(text)
    text = (text or ""):lower():gsub("%s", ""):gsub("%%$", "")
    if text == "" then return nil end
    for _, size in ipairs(Panel.SIZES) do
        if size.key == text then return size.scale end
    end
    local number = tonumber(text)
    if not number or number <= 0 then return nil end
    -- 80 means 80%; 0.8 means the same.
    if number > 5 then number = number / 100 end
    return number
end

--- The size the panel is drawn at, 0.5 to 1.5: the saved one, in bounds.
function Panel:GetScale()
    return self:SizePercent() / 100
end

--- Save a size and draw the panel at it. Returns the size it ended up at.
function Panel:SetPanelScale(value)
    value = tonumber(value) or 1
    local scale = Widgets.ClampSize(value * 100, SCALE_MIN, SCALE_MAX) / 100
    if ns.db then ns.db.questScale = scale end
    self:ApplyScale()
    if ns.SettingsUI and ns.SettingsUI.Refresh then ns.SettingsUI:Refresh() end
    return scale
end

--- A tracked upgrade's right-click menu (the house row menu).
function Panel:HuntMenu(hunt)
    if not (hunt and ns.RowMenu) then return end
    local lines = {}
    if hunt.place and hunt.place.x and ns.Waypoints then
        lines[#lines + 1] = { text = L["Show on Map"], run = function()
            ns.Waypoints:Show(hunt.place, hunt.place.name)
        end }
    end
    if not hunt.done and ns.Tracking then
        lines[#lines + 1] = { text = L["Stop Tracking"], run = function()
            ns.Tracking:Untrack(hunt.itemID)
        end }
    end
    return ns.RowMenu:Open(lines, { title = ns.Items and ns.Items.ShowLink(hunt.link) or nil })
end

--------------------------------------------------------------------------------
-- Size and spot
--------------------------------------------------------------------------------

function Panel:SizePercent()
    return Widgets.ClampSize(((ns.db and tonumber(ns.db.questScale)) or 1) * 100, SCALE_MIN, SCALE_MAX)
end

--- Draw the panel at the saved size, its top left corner where it was.
function Panel:ApplyScale()
    local frame = self.frame
    if not frame then return end
    local old = Panel.ScaleOf(frame)
    local ok, left, top = pcall(function() return frame:GetLeft(), frame:GetTop() end)
    Widgets.ApplySize(frame, self:SizePercent(), SCALE_MIN, SCALE_MAX)
    local scale = Panel.ScaleOf(frame)
    if math.abs(old - scale) < 0.001 then return end
    if ok and type(left) == "number" and type(top) == "number" then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * old / scale, top * old / scale)
        self:SavePosition()
    else
        self:RestorePosition()
    end
    if ns.QuestLogUI then ns.QuestLogUI:PlaceItemsSoon() end
end

function Panel:SavePosition()
    if not (ns.db and self.frame) then return end
    local point, _, relativePoint, x, y = self.frame:GetPoint()
    ns.db.questPoint, ns.db.questRelativePoint = point, relativePoint
    ns.db.questX, ns.db.questY = x, y
    ns.db.questScaleAt = Panel.ScaleOf(self.frame)
end

function Panel:RestorePosition()
    local frame = self.frame
    if not frame then return end
    local db = ns.db or {}
    frame:ClearAllPoints()
    if not (db.questX and db.questY) then
        -- Never dragged: the next free place on the shared right shelf.
        local sw = ns.SharedWindow
        if sw and sw.ShelfPlace and sw.ShelfPlace(frame, "upgradequest.equipment", {
            shelf = "right",
            free = function() local d = ns.db or {}; return not (d.questX and d.questY) end,
            place = function() Panel:RestorePosition() end,
        }) then return end
    end
    local factor = Panel.PositionFactor(db.questX and db.questScaleAt or 1, Panel.ScaleOf(frame))
    frame:SetPoint(db.questPoint or "RIGHT", UIParent, db.questRelativePoint or "RIGHT",
        (db.questX or -40) * factor, (db.questY or -120) * factor)
end

--------------------------------------------------------------------------------
-- Filling: the bar
--------------------------------------------------------------------------------

function Panel:FillBar(view, line)
    local bar, holder, gems = self.bar, self.gemHolder, self.gems
    bar:SetShown(not line)
    gems:SetFolded(line)
    gems.close:SetShown(not line)
    gems.fold:ClearAllPoints()
    holder:ClearAllPoints()
    if line then
        holder:SetPoint("TOPRIGHT")
        holder:SetPoint("BOTTOMRIGHT")
        holder:SetWidth(GEM + 10)
        gems.fold:SetPoint("RIGHT", holder, "RIGHT", -5, 0)
        return
    end
    holder:SetPoint("TOPRIGHT")
    holder:SetSize(GEM * 2 + 14, BAR)
    gems.fold:SetPoint("RIGHT", gems.close, "LEFT", -4, 0)

    local hunts = HuntCount()
    local words = {
        quest = L["Quest"],
        tracking = hunts > 0 and ("%s %d"):format(L["Tracking"], hunts) or L["Tracking"],
        log = L["Log"],
    }
    local x = 2
    for _, key in ipairs(VIEWS) do
        local tab = self.tabs[key]
        if key == "quest" and not QuestOn() then
            tab:Hide()
        else
            tab.label:SetText(words[key])
            tab:SetWidth(Theme.TextWidth("small", words[key]) + 14)
            tab:ClearAllPoints()
            tab:SetPoint("LEFT", bar, "LEFT", x, 0)
            tab.label:SetTextColor(Theme.Unpack(key == view and "accentHi" or "muted"))
            tab.line:SetShown(key == view)
            tab:Show()
            x = x + tab:GetWidth()
        end
    end
    local open = self.openTab
    if open then
        open:ClearAllPoints()
        open:SetPoint("LEFT", bar, "LEFT", x + 4, 0)
        open:Show()
    end
end

--------------------------------------------------------------------------------
-- Filling: Quest
--------------------------------------------------------------------------------

--- What the Quest tab says with no quest to show.
function Panel.EmptyText()
    local logic = ns.UpgradeQuest
    if not logic then return "" end
    if logic.state == "waiting" then
        if InCombat() then return L["Your next upgrade comes after the fight."] end
        return L["Looking for your next upgrade..."]
    end
    return logic.NONE[logic:Tab()] or L["No upgrade to chase right now."]
end

--- The quest's steps and the one to do now (the last when none is left).
local function QuestSteps(quest)
    local steps, current = ns.UpgradeQuest:Steps(quest)
    local done = 0
    for _, step in ipairs(steps) do
        if step.done then done = done + 1 end
    end
    local index = math.max(1, math.min(current or 1, #steps))
    return steps, index, done
end

local function HideQuestParts(self)
    self.item:Hide()
    self.step:Hide()
    for _, mark in ipairs(self.marks) do mark:Hide() end
    for _, row in ipairs(self.stepRows) do row:Hide() end
end

--- Lay the step to do now out at `y` under `parent`'s top.
local function PlaceStep(self, parent, y, step, index, width)
    local row = self.step
    row:SetParent(parent)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
    row:SetWidth(width)
    local turnIn = step.turnIn and not step.done
    row.now:SetShown(not turnIn)
    row.turnIn:SetShown(turnIn and true or false)
    row.text:SetWidth(width - PAD * 2 - MARK - 6)
    row.text:SetText(step.text or "")
    row.stepIndex = index
    row.place = not step.done and type(step.place) == "table" and step.place.zone and step.place or nil
    row.note = step.note
    row.isNow = true
    local height = math.max(MARK + 4, TextHeight(row.text, "large", width - PAD * 2 - MARK - 6)) + 6
    row:SetHeight(height)
    row:Show()
    return height
end

function Panel:FillQuest()
    local logic = ns.UpgradeQuest
    local quest = logic:Current()
    self.thumb:Hide()
    for _, row in ipairs(self.rows) do row:Hide() end
    if not quest then
        HideQuestParts(self)
        self.item.quest = nil
        self.empty:SetText(Panel.EmptyText())
        self.empty:Show()
        return TextHeight(self.empty, "normal", WIDTH - PAD * 2) + 16
    end
    self.empty:Hide()

    local item = self.item
    item.quest = quest
    Theme.SetItemIcon(item.icon, quest.link)
    local gain = quest.howMuch or ""
    if ns.WeaponSkills and ns.WeaponSkills:NeedsTraining(quest.link) then
        gain = L.Format("Train: %s", gain)
        item.gain:SetTextColor(Theme.Unpack("loss"))
    else
        item.gain:SetTextColor(Theme.Unpack("good"))
    end
    item.gain:SetText(gain)
    local nameWidth = WIDTH - PAD * 2 - ICON - 7 - Theme.TextWidth("large", gain) - 8
    item.name:SetWidth(nameWidth)
    item.name:SetText(ns.Items.ShowLink(quest.link) or "?")
    local itemHeight = math.max(ICON, TextHeight(item.name, "large", nameWidth)) + 9
    item:SetHeight(itemHeight)
    item:Show()

    local steps, current, done = QuestSteps(quest)
    local y = itemHeight
    for _, row in ipairs(self.stepRows) do row:Hide() end
    if self:StepsOpen() and #steps > 0 then
        self.step:Hide()
        local shown = 0
        for index, step in ipairs(steps) do
            local row = self.stepRows[index]
            if not row then break end
            shown = shown + 1
            local now = index == current and not step.done
            row.stepIndex = index
            row.isNow = now
            row.note = step.note
            row.place = not step.done and type(step.place) == "table" and step.place.zone and step.place or nil
            row.picked = now
            row.restKey = shown % 2 == 0 and "glassAlt" or "glass"
            row.check:SetShown(step.done)
            row.now:SetShown(now)
            row.dot:SetShown(not step.done and not now)
            row.text:SetText(step.text or "")
            row.text:SetTextColor(Theme.Unpack(step.done and "muted" or "text"))
            local height = math.max(MARK + 2, TextHeight(row.text, "normal", WIDTH - PAD * 2 - MARK - 6)) + 8
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -y)
            row:SetPoint("TOPRIGHT", 0, -y)
            row:SetHeight(height)
            PaintGlass(row)
            row:Show()
            y = y + height
        end
        for _, mark in ipairs(self.marks) do mark:Hide() end
        return y
    end

    local now = steps[current]
    if now then
        y = y + PlaceStep(self, self.body, y, now, current, WIDTH)
    else
        self.step:Hide()
    end
    -- The five marks: green for what is done, gold for the one under way.
    local lit, under = Panel.MarksFor(done, #steps)
    local markWidth = (WIDTH - PAD * 2 - (MARKS - 1) * 3) / MARKS
    for index, mark in ipairs(self.marks) do
        mark:ClearAllPoints()
        mark:SetPoint("TOPLEFT", self.body, "TOPLEFT", PAD + (index - 1) * (markWidth + 3), -(y + 1))
        local key = index <= lit and "good" or (under and index == lit + 1) and "accentHi" or "border"
        mark:SetColorTexture(Theme.Unpack(key))
        mark:Show()
    end
    return y + MARK_HEIGHT + 8
end

--- Folded to one line: the step to do now, and the gem that opens it.
function Panel:FillLine()
    HideQuestParts(self)
    self.empty:Hide()
    self.thumb:Hide()
    for _, row in ipairs(self.rows) do row:Hide() end
    local width = WIDTH - GEM - 10
    local quest = QuestOn() and ns.UpgradeQuest:Current() or nil
    local step
    if quest then
        local steps, current = QuestSteps(quest)
        step = steps[current]
        if step then return PlaceStep(self, self.frame, 3, step, current, width) + 3 end
    end
    local text
    if QuestOn() then
        text = Panel.EmptyText()
    else
        text = ("%s %d"):format(L["Tracking"], HuntCount())
    end
    return PlaceStep(self, self.frame, 3, { text = text, done = true }, nil, width) + 3
end

--------------------------------------------------------------------------------
-- Filling: Tracking and Log
--------------------------------------------------------------------------------

--- The first line shown, kept inside the list.
local function Offset(offset, total)
    return math.max(0, math.min(tonumber(offset) or 0, math.max(0, total - MOST_ROWS)))
end

function Panel:PlaceThumb(offset, total, top, height)
    local thumb = self.thumb
    if total <= MOST_ROWS or height <= 0 then
        thumb:Hide()
        return
    end
    local size = math.max(10, height * MOST_ROWS / total)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -1,
        -(top + (height - size) * offset / math.max(1, total - MOST_ROWS)))
    thumb:SetHeight(size)
    thumb:Show()
end

--- Lay `lines` out in the rows, each filled by `fill(row, line)`.
-- @return how tall they came out
function Panel:FillRows(lines, fill, none)
    HideQuestParts(self)
    self.item.quest = nil
    local offset = Offset(self.offset, #lines)
    self.offset = offset
    local y, shown = 0, 0
    for index, row in ipairs(self.rows) do
        local line = lines[index + offset]
        row.line = line
        if line then
            shown = shown + 1
            row.restKey = shown % 2 == 0 and "glassAlt" or "glass"
            local height = fill(row, line)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -y)
            row:SetPoint("TOPRIGHT", 0, -y)
            row:SetHeight(height)
            PaintGlass(row)
            row:Show()
            y = y + height
        else
            row:Hide()
        end
    end
    if shown == 0 then
        self.empty:SetText(none)
        self.empty:Show()
        self.thumb:Hide()
        return TextHeight(self.empty, "normal", WIDTH - PAD * 2) + 16
    end
    self.empty:Hide()
    self:PlaceThumb(offset, #lines, BAR, y)
    return y
end

--- A row's words and its mark on the right; returns the row's height.
local function FillLine(row, link, text, mark, markKey)
    local left = PAD
    if link then
        Theme.SetItemIcon(row.icon, link)
        left = PAD + ROW_ICON + 6
    else
        row.icon:Hide()
    end
    local check = mark == "check"
    row.check:SetShown(check)
    row.mark:SetText(check and "" or mark or "")
    row.mark:SetTextColor(Theme.Unpack(markKey or "good"))
    local markWidth = check and MARK or Theme.TextWidth("normal", mark or "")
    local width = WIDTH - left - PAD - markWidth - (markWidth > 0 and 8 or 0)
    row.text:ClearAllPoints()
    row.text:SetPoint("TOPLEFT", left, -5)
    row.text:SetWidth(width)
    row.text:SetText(text)
    return math.max(ROW_ICON, TextHeight(row.text, "normal", width)) + 9
end

function Panel:FillTracking()
    local lines = ns.Tracking and ns.Tracking:List() or {}
    return self:FillRows(lines, function(row, hunt)
        row.kind = "hunt"
        row.picked = false
        local mark, key = Panel.GainOf(hunt.itemID), "good"
        if hunt.got then mark = "check" end
        return FillLine(row, hunt.link, ns.Items.ShowLink(hunt.link) or "?", mark, key)
    end, L["Nothing tracked yet."])
end

function Panel:FillLog()
    local lines = self:LogLines()
    local free = ns.QuestArrow and ns.QuestArrow.IsOn() and ns.QuestArrow:FreeQuest()
    return self:FillRows(lines, function(row, quest)
        row.kind = "quest"
        row.picked = free and free.questID == quest.questID and free.title == quest.title or false
        local mark, key = Panel.LogMark(quest)
        local height = FillLine(row, quest.item and quest.item.link, Colored("gilt", quest.title or ""), mark, key)
        return height
    end, L["No quests to show."])
end

function Panel:ScrollBy(steps)
    if self:OneLine() or self:View() == "quest" then return end
    local before = self.offset or 0
    self.offset = before + steps
    self:Refresh()
end

--- Where the Log's item buttons belong (UI/QuestLogTab.lua places them):
--- one for each quest in view that hands out an item to use.
function Panel:ItemSpots(most)
    local spots = {}
    if not (self.frame and Shown(self.frame)) or self:OneLine() or self:View() ~= "log" then return spots end
    local size = ns.QuestLogUI and ns.QuestLogUI.ITEM or ROW_ICON
    for _, row in ipairs(self.rows) do
        local quest = rawget(row, "line")
        if #spots >= (most or 6) then break end
        if Shown(row) and rawget(row, "kind") == "quest" and type(quest) == "table" and quest.item then
            local ok, left, top, scale = pcall(function()
                return row.icon:GetLeft(), row.icon:GetTop(),
                    row.icon:GetEffectiveScale() / UIParent:GetEffectiveScale()
            end)
            if ok and type(left) == "number" and type(top) == "number" and type(scale) == "number" and scale > 0 then
                -- The button is drawn at the icon's size, over it.
                local shrink = ROW_ICON / size
                spots[#spots + 1] = { row = { quest = quest },
                    spot = { left = left / shrink, top = top / shrink, scale = scale * shrink } }
            end
        end
    end
    return spots
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

function Panel:Refresh()
    if not self:Wanted() then
        if self.frame then self.frame:Hide() end
        self:HideOffer()
        return
    end
    self:Build()
    local frame = self.frame
    -- Folded into its round button: nothing to draw until it opens.
    if ns.FoldWindow and ns.FoldWindow:IsFolded(frame) then return end

    local view = self:View()
    local line = self:OneLine()
    self:FillBar(view, line)
    self.body:SetShown(not line)

    local height
    if line then
        height = self:FillLine()
    else
        self.step:SetParent(self.body)
        if view == "quest" then
            height = BAR + self:FillQuest()
        elseif view == "tracking" then
            height = BAR + self:FillTracking()
        else
            height = BAR + self:FillLog()
        end
    end
    frame:SetHeight(height)
    if ns.SeeThrough then ns.SeeThrough:Grew("panel", frame) end

    if not Shown(frame) then
        frame:Show()
        Motion:Open(frame)
    end
    if ns.QuestLogUI then ns.QuestLogUI:PlaceItemsSoon() end
    self:FillOffer()

    -- A step just ticked off: the panel's edge flares green.
    local logic = ns.UpgradeQuest
    if logic and logic.stepDone then
        logic.stepDone = nil
        self:Cheer()
    end
end

--- Once for a burst, and only while the panel shows.
function Panel:RefreshSoon()
    if not Shown(self.frame) or self.pending then return end
    local after = C_Timer and C_Timer.After
    if type(after) ~= "function" then return self:Refresh() end
    self.pending = true
    after(0.2, function()
        Panel.pending = false
        if Shown(Panel.frame) then Panel:Refresh() end
    end)
end

--- The panel's edge flares green and settles back, with the quest sound.
function Panel:Cheer()
    local frame = self.frame
    if not frame then return end
    local rest = rawget(frame, "haloRest") or 0.14
    Motion:Run(frame, "cheer", 0.9, function(p)
        Theme.SetHalo(frame, 0.6 + (rest - 0.6) * p, p < 1 and "good" or "accent")
    end)
    if type(_G.PlaySound) == "function" and not (ns.Muted and ns.Muted()) then
        local kit = _G.SOUNDKIT and _G.SOUNDKIT.UI_QUEST_OBJECTIVE_COMPLETE
        pcall(_G.PlaySound, kit or 6197, "Master")
    end
end

--------------------------------------------------------------------------------
-- Clicks, hovers and the menu
--------------------------------------------------------------------------------

--- Open the Upgrade Quest tab of the Equipment window.
function Panel:OpenTab(view)
    if ns.QuestTab and ns.QuestTab.Open then return ns.QuestTab:Open(view) end
    if ns.GearWindow then ns.GearWindow:Open("quest") end
end

function Panel:StepTip(row)
    local note, place = rawget(row, "note"), rawget(row, "place")
    GameTooltip:SetOwner(row, "ANCHOR_LEFT")
    local text = row.text:GetText()
    GameTooltip:AddLine(text or "", 1, 1, 1, true)
    if type(note) == "string" and note ~= "" then GameTooltip:AddLine(note, 0.9, 0.9, 0.9, true) end
    if type(place) == "table" and not rawget(row, "isNow") then
        GameTooltip:AddLine(L["Point the quest arrow here"], Theme.Unpack("accent"))
    end
    GameTooltip:Show()
end

--- The step to do now opens and closes the list of steps. Another step
--- with a place aims the quest arrow at it, as before.
function Panel:StepClicked(row, mouse)
    if mouse == "RightButton" then return self:OpenMenu() end
    GameTooltip:Hide()
    if self:OneLine() then return self:SetOneLine(false) end
    local index, place = rawget(row, "stepIndex"), rawget(row, "place")
    if not rawget(row, "isNow") and type(place) == "table" and index and ns.QuestArrow then
        ns.QuestArrow:Aim(index)
        return
    end
    self:SetStepsOpen(not self:StepsOpen())
end

function Panel:ListTip(row)
    local line, kind = rawget(row, "line"), rawget(row, "kind")
    if type(line) ~= "table" then return end
    GameTooltip:SetOwner(row, "ANCHOR_LEFT")
    if kind == "hunt" then
        pcall(GameTooltip.SetHyperlink, GameTooltip, line.link)
        GameTooltip:AddLine(" ")
        if line.got then
            GameTooltip:AddLine(L["In your bags: put it on"], Theme.Unpack("good"))
        elseif line.place and line.place.text then
            GameTooltip:AddLine(ns.Tracking.PlaceText(line.place), 1, 1, 1, true)
        end
        if line.place and line.place.x then
            GameTooltip:AddLine(L["Click to pin it on your map"], Theme.Unpack("dim"))
        end
        GameTooltip:AddLine(L["Right-click to stop tracking"], Theme.Unpack("dim"))
    else
        GameTooltip:AddLine(line.title or "", Theme.Unpack("gilt"))
        for _, each in ipairs(ns.QuestLog.ObjectiveLines(line)) do
            local r, g, b = Theme.Unpack(each.color or "text")
            GameTooltip:AddLine(each.text, r, g, b, true)
        end
        local mark = ns.QuestLogUI and ns.QuestLogUI.MarkText(line.questID)
        if mark then GameTooltip:AddLine(mark, Theme.Unpack("good")) end
        GameTooltip:AddLine(L["Click to open it in your quest log."], Theme.Unpack("dim"))
    end
    GameTooltip:Show()
end

function Panel:ListClicked(row, mouse)
    local line, kind = rawget(row, "line"), rawget(row, "kind")
    if type(line) ~= "table" then return end
    GameTooltip:Hide()
    if kind == "hunt" then
        if mouse == "RightButton" then
            Panel:HuntMenu(line)
            return
        end
        if Widgets.ItemClick(line.itemID, line.link) then return end
        if line.place and line.place.x and ns.Waypoints then
            ns.Waypoints:Show(line.place, line.place.name, Theme.ItemIcon(line.link))
        end
        return
    end
    local ui = ns.QuestLogUI
    if not ui then return end
    if mouse == "RightButton" then return ui:OpenMenu(line) end
    ui:Act("open", line)
end

--- The right-click menu: what the old panel's buttons and Options did.
function Panel:MenuLines()
    local lines = {}
    local logic = ns.UpgradeQuest
    local quest = QuestOn() and logic:Current() or nil
    if quest then
        if logic:NextPlace() then
            lines[#lines + 1] = { text = L["Show on Map"], run = function()
                Panel:ShowOnMap()
            end }
        end
        local on = ns.QuestArrow and ns.QuestArrow.IsOn()
        lines[#lines + 1] = { text = L["Arrow"], checked = on, run = function()
            ns.HandleSlash(on and "arrow off" or "arrow on")
        end }
        lines[#lines + 1] = { text = L["Ignore"], run = function() ns.HandleSlash("quest ignore") end }
    end
    if QuestOn() then
        for _, line in ipairs(Panel:OptionLines()) do
            -- The steps open and close with a click here.
            if line.text ~= L["Current Step Only"] and line.text ~= L["Settings"] then lines[#lines + 1] = line end
        end
    end
    local ui = ns.QuestLogUI
    if ui then
        local tracked = ui:TrackedOnly()
        lines[#lines + 1] = { text = L["Tracked Only"], checked = tracked, run = function()
            ui:SetTrackedOnly(not tracked)
        end }
        local hides = ui:HidesTracker()
        lines[#lines + 1] = { text = (L["Hide Game's Tracker:"]:gsub("%s*[:\239\188\154]+%s*$", "")), checked = hides,
            run = function() ui:SetHidesTracker(not hides) end }
    end
    lines[#lines + 1] = { text = L["Upgrade Quest"], run = function() Panel:OpenTab() end }
    return lines
end

function Panel:OpenMenu()
    if not ns.RowMenu then return nil end
    return ns.RowMenu:Open(self:MenuLines(), { title = L["Options"] })
end

--- The red gem: the upgrade quest goes off, its quests kept. With the
--- quest off already, the panel is put away until a hunt changes.
function Panel:Close()
    self.closed = true
    if QuestOn() then
        ns.UpgradeQuest:TurnOff()
    else
        self:Refresh()
    end
end

--- Fold the whole panel into its round button.
function Panel:ToRound()
    if not (self.frame and ns.FoldWindow) then return false end
    return ns.FoldWindow:Fold(self.frame)
end

--- Open the panel full: out of its round button and its one line.
function Panel:Unfold()
    self.closed = nil
    if ns.db then ns.db.questPanelLine = nil end
    if self.frame and ns.FoldWindow and ns.FoldWindow:IsFolded(self.frame) then
        ns.FoldWindow:Unfold(self.frame)
    end
    self:Refresh()
end

--------------------------------------------------------------------------------
-- New Upgrade Unlocked
--------------------------------------------------------------------------------

local OFFER_WIDTH = 290

function Panel:BuildOffer()
    if self.offer then return self.offer end
    local box = CreateFrame("Frame", "BlackthornesEquipmentOffer", UIParent)
    box:SetSize(OFFER_WIDTH, 120)
    box:SetFrameStrata("MEDIUM")
    box:SetClampedToScreen(true)
    box:EnableMouse(true)
    Theme.Fill(box, "window")
    Theme.Border(box, "borderLit")
    Theme.Halo(box, 10, 0.3, "accent")

    local head = Theme.CreatePanel(box, "header", false)
    head:SetPoint("TOPLEFT")
    head:SetPoint("TOPRIGHT")
    head:SetHeight(24)
    local title = Theme.CreateLabel(head, "large", "gilt", "CENTER")
    title:SetPoint("CENTER")
    title:SetText(L["New Upgrade Unlocked"])

    box.icon = Theme.CreateItemIcon(box, ICON)
    box.icon:SetPoint("TOPLEFT", 12, -32)
    box.gain = Theme.CreateLabel(box, "normal", "good", "RIGHT")
    box.gain:SetPoint("TOPRIGHT", -12, -35)
    box.name = Theme.CreateLabel(box, "normal", "text")
    box.name:SetPoint("TOPLEFT", 12 + ICON + 8, -35)
    box.name:SetWordWrap(true)
    box.text = Theme.CreateLabel(box, "small", "muted")
    box.text:SetWidth(OFFER_WIDTH - 24)
    box.text:SetWordWrap(true)

    local switchText, keepText = L["Switch"], L["Keep Current"]
    local width = math.max(Theme.TextWidth("normal", switchText), Theme.TextWidth("normal", keepText)) + 28
    box.switch = Widgets.CreateButton(box, switchText, function()
        if ns.UpgradeQuest then ns.UpgradeQuest:SwitchToOffer() end
    end, { width = width, height = 22, primary = true })
    box.keep = Widgets.CreateButton(box, keepText, function()
        if ns.UpgradeQuest then ns.UpgradeQuest:KeepCurrent() end
    end, { width = width, height = 22 })
    box.switch:SetPoint("BOTTOMRIGHT", box, "BOTTOM", -4, 12)
    box.keep:SetPoint("BOTTOMLEFT", box, "BOTTOM", 4, 12)
    box:Hide()
    self.offer = box
    return box
end

function Panel:HideOffer()
    if self.offer then self.offer:Hide() end
end

--- The upgrade a level opened, in a small window over the panel, with
--- Switch and Keep Current.
function Panel:FillOffer()
    local logic = ns.UpgradeQuest
    local offer = QuestOn() and logic:Offer() or nil
    if not (offer and offer.pick and Shown(self.frame)) then return self:HideOffer() end
    local box = self:BuildOffer()
    local link = offer.pick.link or "?"
    Theme.SetItemIcon(box.icon, link)
    local gain = offer.howMuch or ""
    box.gain:SetText(gain)
    local nameWidth = OFFER_WIDTH - 24 - ICON - 8 - Theme.TextWidth("normal", gain) - 8
    box.name:SetWidth(nameWidth)
    box.name:SetText(ns.Items.ShowLink(link))
    local itemHeight = math.max(ICON, TextHeight(box.name, "normal", nameWidth) + 6)
    box.text:SetText(offer.level
        and L.Format("New upgrade on offer at level %d", offer.level)
        or L["New upgrade on offer"])
    box.text:ClearAllPoints()
    box.text:SetPoint("TOPLEFT", 12, -(32 + itemHeight + 6))
    local textHeight = TextHeight(box.text, "small", OFFER_WIDTH - 24)
    box:SetHeight(32 + itemHeight + 6 + textHeight + 12 + 22 + 12)
    box:ClearAllPoints()
    box:SetPoint("BOTTOMRIGHT", self.frame, "TOPRIGHT", 0, 8)
    pcall(box.SetScale, box, Panel.ScaleOf(self.frame))
    if not Shown(box) then
        box:Show()
        Motion:Run(box, "offer", 0.9, function(p)
            Theme.SetHalo(box, 0.7 + (0.3 - 0.7) * p, "accent")
        end)
    end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

function Panel:OnUpgradeQuestChanged()
    if QuestOn() then self.closed = nil end
    self:Refresh()
end

function Panel:OnQuestArrowChanged()
    if Shown(self.frame) then self:Refresh() end
end

function Panel:OnTrackingChanged()
    self.closed = nil
    self:Refresh()
end

--- The quest log changed: read it again once the burst is over, and only
--- while the Log shows.
function Panel:LogChanged()
    self.logDirty = true
    if not Shown(self.frame) or self:OneLine() or self:View() ~= "log" then return end
    self:RefreshSoon()
end

function Panel:OnEnable()
    self:Refresh()
    for _, event in ipairs({ "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "QUEST_ACCEPTED",
        "UNIT_QUEST_LOG_CHANGED", "QUEST_REMOVED", "QUEST_TURNED_IN", "ZONE_CHANGED_NEW_AREA" }) do
        ns.RegisterEvent(self, event, function(_, _, unit)
            if event == "UNIT_QUEST_LOG_CHANGED" and unit ~= "player" then return end
            Panel:LogChanged()
        end)
    end
    -- "Your next upgrade comes after the fight." gives way once it ends.
    ns.RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
        if Shown(Panel.frame) and Panel:View() == "quest" then Panel:RefreshSoon() end
    end)
    -- A vendor quest's "need ... more" moves with the money.
    ns.RegisterEvent(self, "PLAYER_MONEY", function()
        if not (Shown(Panel.frame) and QuestOn()) then return end
        local quest = ns.UpgradeQuest:Current()
        if quest and quest.source and quest.source.kind == "vendor" then Panel:RefreshSoon() end
    end)
    -- A name drawn plain takes its rarity colour once the client sends it.
    ns.Items:WatchNames(function() Panel:RefreshSoon() end)
end
