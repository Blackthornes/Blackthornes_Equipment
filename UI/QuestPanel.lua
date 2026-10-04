-- Blackthornes Equipment -- UI/QuestPanel.lua
-- The upgrade quest's panel, like a quest in the quest tracker: the item
-- with how much better it is, a progress bar, and the steps to get it, the
-- one to do now lit gold and the ones done ticked green.
--
-- Show on map pins the next place to go; Skip leaves this upgrade for the
-- next best; Other ways opens Where to get upgrades. Shift-click the item
-- to link it in chat. The panel is there while the "Upgrade quest" setting
-- (`upgradeQuest`, off unless turned on) is, folds to its header with "-",
-- and can be dragged anywhere; the spot is kept with the other window
-- positions.

local _, ns = ...

local QuestPanel = ns.NewModule("QuestPanel")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Motion = ns.Motion

local WIDTH = 300
local HEADER = 28
local PAD = 10
local ICON = 36
local MARK = 14
local STEP_GAP = 6
local MOST_STEPS = 8
local FOOTER = 34
local BAR = 4

local QUEST_ICON = [[Interface\GossipFrame\AvailableQuestIcon]]
local DONE_ICON = [[Interface\RaidFrame\ReadyCheck-Ready]]
local NOW_ICON = [[Interface\GossipFrame\AvailableQuestIcon]]

-- The colour each kind of source is tagged in, as in the upgrade finder.
local KIND_COLOR = { vendor = "accent", quest = "quest", dungeon = "dungeon", craft = "craft" }

local function Colored(key, text)
    local r, g, b = Theme.Unpack(key)
    return ("|cff%02x%02x%02x%s|r"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
        math.floor(b * 255 + 0.5), text)
end

function QuestPanel:IsEnabled()
    return ns.UpgradeQuest ~= nil and ns.UpgradeQuest:IsEnabled()
end

--------------------------------------------------------------------------------
-- Measuring wrapped text
--------------------------------------------------------------------------------

--- How many lines `text` wraps to in `width` pixels at a label size,
--- measured word by word the way the game wraps it.
function QuestPanel.Lines(size, text, width)
    if type(text) ~= "string" or text == "" then return 0 end
    -- A link's hidden part takes no room; its [Name] does.
    local plain = text:gsub("|H.-|h", ""):gsub("|h", "")
    local lines, line = 1, ""
    for word in plain:gmatch("%S+") do
        local try = line == "" and word or (line .. " " .. word)
        if line ~= "" and Theme.TextWidth(size, try) > width then
            lines = lines + 1
            line = word
        else
            line = try
        end
    end
    return lines
end

local LINE_HEIGHT = { tiny = 12, small = 13, normal = 14 }

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

--- A button's tooltip: what it does, in clear white on the dark tooltip.
local function Explain(button, title, text)
    button:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(title, Theme.Unpack("accent"))
        if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    button:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

function QuestPanel:BuildStep(index)
    local row = CreateFrame("Frame", nil, self.body)
    row:SetWidth(WIDTH - PAD * 2)
    row.background = Theme.Fill(row, "rowActive", 0)
    -- The step to do now glows gold round its edge.
    Theme.Halo(row, 4, 0)

    local mark = row:CreateTexture(nil, "ARTWORK")
    mark:SetSize(MARK, MARK)
    mark:SetPoint("TOPLEFT", 4, -3)
    row.mark = mark

    local number = Theme.CreateLabel(row, "small", "muted", "CENTER")
    number:SetPoint("TOPLEFT", 2, -3)
    number:SetWidth(MARK + 4)
    row.number = number

    local text = Theme.CreateLabel(row, "small", "text")
    text:SetPoint("TOPLEFT", MARK + 10, -3)
    text:SetWidth(WIDTH - PAD * 2 - MARK - 16)
    text:SetWordWrap(true)
    row.text = text

    local note = Theme.CreateLabel(row, "tiny", "muted")
    note:SetWidth(WIDTH - PAD * 2 - MARK - 16)
    note:SetWordWrap(true)
    row.note = note
    row.textWidth = WIDTH - PAD * 2 - MARK - 16

    row:Hide()
    return row
end

function QuestPanel:Build()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "BlackthornesEquipmentQuest", UIParent)
    frame:SetSize(WIDTH, HEADER)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    Theme.Window(frame)
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        QuestPanel:SavePosition()
    end)

    local header = Theme.CreatePanel(frame, "header", false)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(HEADER)
    Theme.HouseHeader(header, 16)
    header:EnableMouse(false)

    local badge = header:CreateTexture(nil, "ARTWORK")
    badge:SetSize(18, 18)
    badge:SetPoint("LEFT", 8, 0)
    badge:SetTexture(QUEST_ICON)

    local fold = Widgets.CreateButton(header, "-", function() QuestPanel:ToggleFold() end,
        { width = 20, height = 18 })
    fold:SetPoint("RIGHT", -5, 0)
    Explain(fold, "Fold", "Shrink the panel to its header. Click again to open it.")
    self.foldButton = fold

    local progress = Theme.CreateLabel(header, "tiny", "text", "RIGHT")
    progress:SetPoint("RIGHT", fold, "LEFT", -8, 0)
    self.progress = progress

    local title = Theme.CreateLabel(header, "small", "accent")
    title:SetPoint("LEFT", badge, "RIGHT", 6, 0)
    title:SetText("Upgrade quest")
    self.title = title

    -- Everything under the header, hidden when folded.
    local body = CreateFrame("Frame", nil, frame)
    body:SetPoint("TOPLEFT", 0, -HEADER)
    body:SetPoint("TOPRIGHT", 0, -HEADER)
    body:SetHeight(1)
    self.body = body

    -- The item: hover for its tooltip, shift-click to link it.
    local item = CreateFrame("Button", nil, body)
    item:SetPoint("TOPLEFT", PAD, -PAD)
    item:SetSize(WIDTH - PAD * 2, ICON)
    item:SetScript("OnEnter", function(self)
        local quest = ns.UpgradeQuest and ns.UpgradeQuest:Current()
        if not quest then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        pcall(GameTooltip.SetHyperlink, GameTooltip, quest.link)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Shift-click to link it in chat", 1, 1, 1)
        GameTooltip:Show()
    end)
    item:SetScript("OnLeave", function() GameTooltip:Hide() end)
    item:SetScript("OnClick", function()
        local quest = ns.UpgradeQuest and ns.UpgradeQuest:Current()
        if not quest then return end
        if type(IsModifiedClick) == "function" and type(ChatEdit_InsertLink) == "function" then
            local ok, chatLink = pcall(IsModifiedClick, "CHATLINK")
            if ok and chatLink then pcall(ChatEdit_InsertLink, quest.link) end
        end
    end)
    self.item = item

    local icon = Theme.CreateItemIcon(item, ICON)
    icon:SetPoint("LEFT", 0, 0)
    -- A green glow behind the upgrade's icon.
    Theme.Halo(icon, 6, 0.35, "good")
    self.icon = icon

    local name = Theme.CreateLabel(item, "normal", "text")
    name:SetPoint("TOPLEFT", ICON + 10, -2)
    name:SetWidth(WIDTH - PAD * 2 - ICON - 12)
    name:SetWordWrap(true)
    self.name = name

    local gain = Theme.CreateLabel(item, "tiny", "good")
    gain:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
    gain:SetWidth(WIDTH - PAD * 2 - ICON - 12)
    self.gain = gain

    -- How far along: gold filling to green.
    local track = body:CreateTexture(nil, "ARTWORK")
    track:SetPoint("TOPLEFT", item, "BOTTOMLEFT", 0, -8)
    track:SetSize(WIDTH - PAD * 2, BAR)
    track:SetColorTexture(Theme.Unpack("row"))
    self.track = track
    local fill = body:CreateTexture(nil, "OVERLAY")
    fill:SetPoint("TOPLEFT", track, "TOPLEFT")
    fill:SetSize(1, BAR)
    fill:SetColorTexture(Theme.Unpack("good"))
    pcall(Theme.SetGradientAlpha, fill, "HORIZONTAL", "good", 0.55, 1)
    self.fill = fill

    local empty = Theme.CreateLabel(body, "small", "text")
    empty:SetPoint("TOPLEFT", PAD, -PAD)
    empty:SetWidth(WIDTH - PAD * 2)
    empty:SetWordWrap(true)
    self.empty = empty

    self.steps = {}
    for index = 1, MOST_STEPS do self.steps[index] = self:BuildStep(index) end

    local map = Widgets.CreateButton(body, "Show on map", function() QuestPanel:ShowOnMap() end,
        { width = 96, height = 22, primary = true })
    Explain(map, "Show on map", "Put the game's map pin on the next place to go, with its arrow pointing the way.")
    self.mapButton = map

    local other = Widgets.CreateButton(body, "Other ways", function()
        if ns.FinderUI then ns.FinderUI:Show() end
    end, { width = 80, height = 22 })
    Explain(other, "Other ways", "Open Where to get upgrades for every upgrade on offer.")
    self.otherButton = other

    local skip = Widgets.CreateButton(body, "Skip", function()
        if ns.UpgradeQuest then ns.UpgradeQuest:Skip() end
    end, { width = 56, height = 22 })
    Explain(skip, "Skip this upgrade", "Leave it and get a quest for the next best one. /beq quest reset brings skipped ones back.")
    self.skipButton = skip

    self.frame = frame
    self:RestorePosition()
    frame:Hide()
    return frame
end

--------------------------------------------------------------------------------
-- Filling it in
--------------------------------------------------------------------------------

--- The words under the item's name: how much better, and from where.
function QuestPanel.GainText(quest)
    local parts = {}
    if quest.howMuch then parts[#parts + 1] = quest.howMuch .. " over what you wear" end
    local source = quest.source
    if source and source.kind and ns.Finder then
        local label = ns.Finder.Label(source)
        if label ~= "" then parts[#parts + 1] = Colored(KIND_COLOR[source.kind] or "accent", label) end
    end
    return table.concat(parts, "  ")
end

--- Lay out one step, and say how tall it came out.
function QuestPanel:FillStep(row, index, step, current)
    row:ClearAllPoints()
    row.text:SetText(step.text)
    local lines = QuestPanel.Lines("small", step.text, row.textWidth)
    local height = 6 + lines * LINE_HEIGHT.small
    local now = index == current and not step.done

    if step.note and (now or not step.done) then
        row.note:SetText(step.note)
        row.note:SetPoint("TOPLEFT", MARK + 10, -(4 + lines * LINE_HEIGHT.small))
        row.note:Show()
        height = height + QuestPanel.Lines("tiny", step.note, row.textWidth) * LINE_HEIGHT.tiny + 2
    else
        row.note:Hide()
    end

    if step.done then
        row.mark:SetTexture(DONE_ICON)
        row.mark:Show()
        row.number:Hide()
        row.text:SetTextColor(Theme.Unpack("muted"))
    elseif now then
        row.mark:SetTexture(NOW_ICON)
        row.mark:Show()
        row.number:Hide()
        row.text:SetTextColor(Theme.Unpack("text"))
    else
        row.mark:Hide()
        row.number:SetText(("%d."):format(index))
        row.number:Show()
        row.text:SetTextColor(Theme.Unpack("muted"))
    end
    row.background:SetColorTexture(Theme.Unpack("rowActive", now and 0.55 or 0))
    Theme.SetHalo(row, now and 0.28 or 0, "accent")
    row.now = now

    row:SetHeight(height)
    row:Show()
    return height
end

function QuestPanel:Refresh()
    if not self:IsEnabled() then
        if self.frame then self.frame:Hide() end
        return
    end
    self:Build()

    local logic = ns.UpgradeQuest
    local quest = logic:Current()
    self.foldButton:SetText(self.folded and "+" or "-")
    self.body:SetShown(not self.folded)

    local steps, current = {}, 0
    if quest then steps, current = logic:Steps(quest) end
    local done = 0
    for _, step in ipairs(steps) do
        if step.done then done = done + 1 end
    end
    self.progress:SetText(quest and ("Step %d of %d"):format(math.min(current, #steps), #steps) or "")

    local height = HEADER
    if not self.folded then
        height = height + self:FillBody(quest, steps, current, done)
    end
    self.frame:SetHeight(height)

    if not self.frame:IsShown() then
        self.frame:Show()
        Motion:Open(self.frame)
    end

    -- A step just ticked off: the panel's edge flares green.
    if logic.stepDone then
        logic.stepDone = nil
        self:Cheer()
    end
end

--- Fill everything under the header; returns how tall it is.
function QuestPanel:FillBody(quest, steps, current, done)
    for _, row in ipairs(self.steps) do row:Hide() end

    if not quest then
        self.item:Hide()
        self.track:Hide()
        self.fill:Hide()
        self.mapButton:Hide()
        self.skipButton:Hide()
        local state = ns.UpgradeQuest.state
        local text
        if state == "waiting" then
            text = "Looking for your next upgrade..."
        else
            text = "No upgrade to chase right now. A new one comes up as you level, or open Other ways for gear that waits on a reputation."
        end
        self.empty:SetText(text)
        self.empty:Show()
        local lines = QuestPanel.Lines("small", text, WIDTH - PAD * 2)
        local y = PAD + lines * LINE_HEIGHT.small + 10
        self.otherButton:ClearAllPoints()
        self.otherButton:SetPoint("TOPLEFT", PAD, -y)
        self.otherButton:Show()
        local height = y + 22 + PAD
        self.body:SetHeight(height)
        return height
    end

    self.empty:Hide()
    self.item:Show()
    Theme.SetItemIcon(self.icon, quest.link)
    self.name:SetText(quest.link or "?")
    local nameLines = math.min(2, QuestPanel.Lines("normal", quest.link or "?", WIDTH - PAD * 2 - ICON - 12))
    self.gain:SetText(QuestPanel.GainText(quest))
    local itemHeight = math.max(ICON, 4 + nameLines * LINE_HEIGHT.normal + 3 + LINE_HEIGHT.tiny)
    self.item:SetHeight(itemHeight)

    self.track:Show()
    self.fill:Show()
    local share = #steps > 0 and done / #steps or 0
    self.fill:SetWidth(math.max(1, (WIDTH - PAD * 2) * share))

    local y = PAD + itemHeight + 8 + BAR + 10
    for index, step in ipairs(steps) do
        local row = self.steps[index]
        if not row then break end
        local stepHeight = self:FillStep(row, index, step, current)
        row:SetPoint("TOPLEFT", PAD, -y)
        y = y + stepHeight + STEP_GAP
    end

    -- Buttons along the bottom: Show on map only when there is a place.
    y = y + 4
    local place = ns.UpgradeQuest:NextPlace()
    self.mapButton:ClearAllPoints()
    self.otherButton:ClearAllPoints()
    self.skipButton:ClearAllPoints()
    self.skipButton:SetPoint("TOPRIGHT", -PAD, -y)
    self.skipButton:Show()
    self.otherButton:SetPoint("RIGHT", self.skipButton, "LEFT", -6, 0)
    self.otherButton:Show()
    if place then
        self.mapButton:SetPoint("TOPLEFT", PAD, -y)
        self.mapButton:Show()
    else
        self.mapButton:Hide()
    end

    local height = y + FOOTER - 4
    self.body:SetHeight(height)
    return height
end

--- The panel's edge flares green and settles back, with the quest sound.
function QuestPanel:Cheer()
    if not self.frame then return end
    local rest = self.frame.haloRest or 0.14
    Motion:Run(self.frame, "cheer", 0.9, function(p)
        Theme.SetHalo(self.frame, 0.6 + (rest - 0.6) * p, p < 1 and "good" or "accent")
    end)
    if type(_G.PlaySound) == "function" then
        local kit = _G.SOUNDKIT and _G.SOUNDKIT.UI_QUEST_OBJECTIVE_COMPLETE
        pcall(_G.PlaySound, kit or 6197, "Master")
    end
end

function QuestPanel:ShowOnMap()
    local place = ns.UpgradeQuest and ns.UpgradeQuest:NextPlace()
    if not (place and ns.Waypoints) then return false end
    if place.x and place.y then return ns.Waypoints:Show(place, place.name) end
    -- No exact spot, only a zone: open the map on it.
    local mapID = ns.Waypoints:MapFor(place.zone)
    if mapID and type(_G.OpenWorldMap) == "function" then
        pcall(_G.OpenWorldMap, mapID)
        return true
    end
    ns.Print(("head for %s."):format(place.zone))
    return false
end

function QuestPanel:ToggleFold()
    self.folded = not self.folded
    self:Refresh()
end

function QuestPanel:Unfold()
    self.folded = false
    self:Refresh()
end

function QuestPanel:OnUpgradeQuestChanged()
    self:Refresh()
end

--------------------------------------------------------------------------------
-- Position
--------------------------------------------------------------------------------

function QuestPanel:SavePosition()
    if not (ns.db and self.frame) then return end
    local point, _, relativePoint, x, y = self.frame:GetPoint()
    ns.db.questPoint, ns.db.questRelativePoint = point, relativePoint
    ns.db.questX, ns.db.questY = x, y
end

function QuestPanel:RestorePosition()
    if not self.frame then return end
    local db = ns.db or {}
    self.frame:ClearAllPoints()
    -- Below the upgrade tracker's starting spot, so the two do not overlap.
    self.frame:SetPoint(db.questPoint or "RIGHT", UIParent, db.questRelativePoint or "RIGHT",
        db.questX or -40, db.questY or -120)
end

function QuestPanel:OnEnable()
    self:Refresh()
end
