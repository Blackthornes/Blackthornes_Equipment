-- Blackthornes Equipment -- UI/DungeonQuestsWindow.lua
-- Dungeon Quests (the owner said build it, 2026-10-20, from a mockup): the
-- dungeons down the left, each with how many of its quests are done, and
-- the one picked shows its quests: Done, In Log or To Do, who starts each
-- and where, its level and its reward (green with the gain when it is an
-- upgrade). Follow points the quest arrow, Show the Way puts the game's map
-- pin where it starts. Opened with /beq dungeons, the gear window's
-- Dungeon Quests button or Settings.
--
-- What it shows is DungeonQuests:Build(), built again only on Refresh:
-- when it opens, a tick box changes, or a burst of quest log events ends
-- while it shows. Rows are filled again only when their text moves.

local _, ns = ...
local L = ns.L

local DQUI = ns.NewModule("DungeonQuestsUI")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Motion = ns.Motion

local NAME = "BlackthornesEquipmentDungeonQuests"
local WIDTH, HEIGHT = 780, 520
local PADDING = 18
local RIM = 6
local TOP = 44
local BAR = 30
local LEFT_WIDTH = 230
local DUNGEON_ROW = 40
local DUNGEON_ROWS = 10
local QUEST_ROW = 38
local QUEST_ROWS = 8
local HEAD = 50
local COLUMNS = 22
local FOOT = 42
local STATUS_WIDTH, LEVEL_WIDTH, REWARD_WIDTH = 82, 44, 190

DQUI.DUNGEON_ROWS, DQUI.QUEST_ROWS = DUNGEON_ROWS, QUEST_ROWS

local LOOKS = {
    done = { L["Done"], "good", "muted" },
    log = { L["In Log"], "accentHi", "text" },
    todo = { L["To Do"], "muted", "text" },
}

local function Paint(texture, key, alpha)
    texture:SetColorTexture(Theme.Unpack(key, alpha))
end

--- The house list row: dark glass by place, a fine line under it, the gold
--- light under the mouse, and the picked one lit with a gold left edge.
local function GlassRow(parent, index, height)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(height)
    row.index = index
    row.background = Theme.Fill(row, index % 2 == 0 and "glassAlt" or "glass")
    row.rule = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.rule:SetPoint("BOTTOMLEFT")
    row.rule:SetPoint("BOTTOMRIGHT")
    row.rule:SetHeight(1)
    row.rule:SetColorTexture(Theme.Unpack("border", 0.6))
    row.edge = row:CreateTexture(nil, "ARTWORK")
    row.edge:SetPoint("TOPLEFT")
    row.edge:SetPoint("BOTTOMLEFT")
    row.edge:SetWidth(3)
    Paint(row.edge, "accentHi")
    row.edge:Hide()
    Widgets.RowLight(row)
    row:SetScript("OnEnter", function(self)
        Motion:Blend(self, "hover", 1, 0.12, function(p) Widgets.SetRowLight(self, p) end)
        if self.onHover then self.onHover(self) end
    end)
    row:SetScript("OnLeave", function(self)
        Motion:Blend(self, "hover", 0, 0.18, function(p) Widgets.SetRowLight(self, p) end)
        GameTooltip:Hide()
    end)
    return row
end

local function SetPicked(row, picked)
    if row.background and row.background.SetColorTexture then
        row.background:SetColorTexture(Theme.Unpack(picked and "glassActive"
            or (row.index % 2 == 0 and "glassAlt" or "glass")))
    end
    row.edge:SetShown(picked == true)
end

local function Levels(dungeon)
    if dungeon.forever and not dungeon.low then return L["New on Forever"] end
    if not dungeon.low then return "" end
    return L.Format("Levels %d to %d", dungeon.low, dungeon.high or dungeon.low)
end

--- The line under the dungeon's name on the right.
function DQUI.Where(dungeon)
    if dungeon.forever then return L["New on Forever. Quests you have seen show here."] end
    local zone = dungeon.door
    if not dungeon.low then return zone or "" end
    if not zone then return Levels(dungeon) .. "." end
    if ns.DungeonQuests.CITIES[zone] then
        return L.Format("%s. Levels %d to %d.", zone, dungeon.low, dungeon.high or dungeon.low)
    end
    return L.Format("Door in %s. Levels %d to %d.", zone, dungeon.low, dungeon.high or dungeon.low)
end

--------------------------------------------------------------------------------
-- Building it
--------------------------------------------------------------------------------

function DQUI:Build()
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame", NAME, UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    Theme.Fill(frame, "window")
    if ns.Titanforged then
        local trim = ns.Titanforged:Dress(frame, {
            title = L["Dungeon Quests"],
            portrait = true,
            close = function() DQUI:Hide() end,
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
        DQUI:SavePosition()
    end)

    -- The house size grip under the bottom right corner (Widgets.WindowGrip),
    -- saved as `dungeonQuestsScale`.
    self.sizeGrip = Widgets.WindowGrip(frame, "dungeonQuestsScale", function()
        DQUI:SavePosition()
    end)
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, NAME) end
    self.frame = frame
    self.dungeonOffset, self.questOffset = 0, 0

    self:BuildBar()
    self:BuildDungeons()
    self:BuildQuests()
    frame:Hide()
    return frame
end

--- The top line: the count of all quests done, a gold bar and the boxes.
function DQUI:BuildBar()
    local frame = self.frame
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetPoint("TOPLEFT", 58, -TOP + 6)
    bar:SetPoint("TOPRIGHT", -PADDING, -TOP + 6)
    bar:SetHeight(BAR)

    local label = Theme.CreateLabel(bar, "normal", "muted")
    label:SetPoint("LEFT", 0, 0)
    label:SetText(L["Your dungeon quests:"])
    local total = Theme.CreateLabel(bar, "large", "accentHi")
    total:SetPoint("LEFT", label, "RIGHT", 10, 0)
    self.total = total

    local myLevel = Widgets.CreateCheckbox(bar, L["My Level Only"], function(checked)
        ns.DungeonQuests:SetMyLevelOnly(checked)
    end, ns.DungeonQuests.MyLevelOnly())
    myLevel:SetPoint("RIGHT", 0, 0)
    self.myLevel = myLevel
    local hideDone = Widgets.CreateCheckbox(bar, L["Hide Done"], function(checked)
        ns.DungeonQuests:SetHideDone(checked)
    end, ns.DungeonQuests.HideDone())
    hideDone:SetPoint("RIGHT", myLevel, "LEFT", -18, 0)
    self.hideDone = hideDone

    local track = CreateFrame("Frame", nil, bar)
    track:SetPoint("LEFT", total, "RIGHT", 14, 0)
    track:SetPoint("RIGHT", hideDone, "LEFT", -18, 0)
    track:SetHeight(10)
    Theme.Fill(track, "well")
    Theme.Border(track, "metal")
    local fill = track:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMLEFT", 1, 1)
    fill:SetWidth(1)
    Theme.SetGradientAlpha(fill, "HORIZONTAL", "accent", 0.9, 1)
    self.track, self.fill = track, fill
    track:SetScript("OnSizeChanged", function() DQUI:FillBar() end)
end

local function Well(parent)
    local well = Theme.CreatePanel(parent, "panel", "border")
    Theme.Recess(well)
    return well
end

local function Heading(parent, text, colorKey)
    local label = Theme.CreateLabel(parent, "tiny", colorKey or "muted")
    label:SetText(text)
    return label
end

function DQUI:BuildDungeons()
    local frame = self.frame
    local top = TOP + BAR + 4
    local well = Well(frame)
    well:SetPoint("TOPLEFT", PADDING, -top)
    well:SetPoint("BOTTOMLEFT", PADDING, PADDING)
    well:SetWidth(LEFT_WIDTH)
    well:EnableMouseWheel(true)
    well:SetScript("OnMouseWheel", function(_, delta) DQUI:ScrollDungeons(-delta) end)
    local title = Heading(well, L["DUNGEONS"])
    title:SetPoint("TOPLEFT", 12, -8)
    self.dungeonWell = well

    self.dungeonRows = {}
    for index = 1, DUNGEON_ROWS do
        local row = GlassRow(well, index, DUNGEON_ROW)
        row:SetPoint("TOPLEFT", 1, -(COLUMNS + (index - 1) * DUNGEON_ROW))
        row:SetPoint("TOPRIGHT", -1, -(COLUMNS + (index - 1) * DUNGEON_ROW))
        row.count = Theme.CreateLabel(row, "normal", "text", "RIGHT")
        row.count:SetPoint("RIGHT", -10, 0)
        row.name = Theme.CreateLabel(row, "normal", "text")
        row.name:SetPoint("TOPLEFT", 12, -5)
        row.name:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
        row.levels = Theme.CreateLabel(row, "tiny", "muted")
        row.levels:SetPoint("BOTTOMLEFT", 12, 6)
        row:SetScript("OnClick", function(self)
            if self.dungeon then DQUI:Pick(self.dungeon.key) end
        end)
        row:Hide()
        self.dungeonRows[index] = row
    end
end

function DQUI:BuildQuests()
    local frame = self.frame
    local top = TOP + BAR + 4
    local well = Well(frame)
    well:SetPoint("TOPLEFT", PADDING + LEFT_WIDTH + 12, -top)
    well:SetPoint("BOTTOMRIGHT", -PADDING, PADDING)
    well:EnableMouseWheel(true)
    well:SetScript("OnMouseWheel", function(_, delta) DQUI:ScrollQuests(-delta) end)
    self.questWell = well

    local name = Theme.CreateLabel(well, "large", "accentHi")
    name:SetPoint("TOPLEFT", 14, -10)
    self.dungeonName = name
    local count = Theme.CreateLabel(well, "normal", "accentHi", "RIGHT")
    count:SetPoint("TOPRIGHT", -14, -12)
    self.dungeonCount = count
    local where = Theme.CreateLabel(well, "small", "muted")
    where:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
    where:SetPoint("RIGHT", -14, 0)
    self.dungeonWhere = where
    local rule = well:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("TOPLEFT", 1, -HEAD)
    rule:SetPoint("TOPRIGHT", -1, -HEAD)
    rule:SetHeight(1)
    Paint(rule, "border", 0.8)

    local status = Heading(well, L["STATUS"])
    status:SetPoint("TOPLEFT", 14, -(HEAD + 6))
    local quest = Heading(well, L["QUEST"])
    quest:SetPoint("TOPLEFT", 14 + STATUS_WIDTH, -(HEAD + 6))
    local reward = Heading(well, L["REWARD"])
    reward:SetPoint("TOPLEFT", well, "TOPRIGHT", -14 - REWARD_WIDTH, -(HEAD + 6))
    local level = Heading(well, L["LEVEL"])
    level:SetJustifyH("CENTER")
    level:SetWidth(LEVEL_WIDTH)
    level:SetPoint("TOPRIGHT", well, "TOPRIGHT", -14 - REWARD_WIDTH - 6, -(HEAD + 6))

    local first = HEAD + COLUMNS
    self.questRows = {}
    for index = 1, QUEST_ROWS do
        local row = GlassRow(well, index, QUEST_ROW)
        row:SetPoint("TOPLEFT", 1, -(first + (index - 1) * QUEST_ROW))
        row:SetPoint("TOPRIGHT", -1, -(first + (index - 1) * QUEST_ROW))
        row.mark = CreateFrame("Frame", nil, row)
        row.mark:SetSize(14, 14)
        row.mark:SetPoint("LEFT", 13, 0)
        Theme.Border(row.mark, "muted")
        row.markText = Theme.CreateLabel(row.mark, "tiny", "good", "CENTER")
        row.markText:SetPoint("CENTER", 0, 0)
        row.status = Theme.CreateLabel(row, "small", "muted")
        row.status:SetPoint("LEFT", row.mark, "RIGHT", 6, 0)
        row.reward = CreateFrame("Frame", nil, row)
        row.reward:SetPoint("TOPRIGHT", -13, 0)
        row.reward:SetPoint("BOTTOMRIGHT", -13, 0)
        row.reward:SetWidth(REWARD_WIDTH)
        row.icon = Theme.CreateItemIcon(row.reward, 20)
        row.icon:SetPoint("LEFT", 0, 0)
        row.rewardName = Theme.CreateLabel(row.reward, "small", "text")
        row.rewardName:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.rewardName:SetPoint("RIGHT", 0, 0)
        row.rewardName:SetWordWrap(true)
        row.level = Theme.CreateLabel(row, "normal", "text", "CENTER")
        row.level:SetWidth(LEVEL_WIDTH)
        row.level:SetPoint("RIGHT", row.reward, "LEFT", -6, 0)
        row.name = Theme.CreateLabel(row, "normal", "text")
        row.name:SetPoint("TOPLEFT", 13 + STATUS_WIDTH, -4)
        row.name:SetPoint("RIGHT", row.level, "LEFT", -6, 0)
        row.from = Theme.CreateLabel(row, "tiny", "muted")
        row.from:SetPoint("BOTTOMLEFT", 13 + STATUS_WIDTH, 5)
        row.from:SetPoint("RIGHT", row.level, "LEFT", -6, 0)
        row:SetScript("OnClick", function(self)
            if self.quest then DQUI:PickQuest(self.quest.questID) end
        end)
        row.onHover = function(self)
            local quest = self.quest
            if not (quest and quest.reward and quest.reward > 0) then return end
            if not self.reward:IsMouseOver() then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            pcall(GameTooltip.SetHyperlink, GameTooltip, ("item:%d"):format(quest.reward))
            GameTooltip:Show()
        end
        row:Hide()
        self.questRows[index] = row
    end

    -- The foot: where the picked quest starts, and the two buttons.
    local way = Widgets.CreateButton(well, L["Show the Way"], function()
        local quest = DQUI:PickedQuest()
        if quest then ns.DungeonQuests:ShowTheWay(quest) end
    end, { width = 110, height = 24, primary = true })
    way:SetPoint("BOTTOMRIGHT", -12, 10)
    self.wayButton = way
    local follow = Widgets.CreateButton(well, L["Follow"], function()
        local quest = DQUI:PickedQuest()
        if quest then ns.DungeonQuests:Follow(quest) end
    end, { width = 80, height = 24 })
    follow:SetPoint("RIGHT", way, "LEFT", -8, 0)
    self.followButton = follow
    local foot = Theme.CreateLabel(well, "small", "muted")
    foot:SetPoint("BOTTOMLEFT", 14, 16)
    foot:SetPoint("RIGHT", follow, "LEFT", -10, 0)
    foot:SetWordWrap(true)
    self.foot = foot
    local footRule = well:CreateTexture(nil, "ARTWORK")
    footRule:SetPoint("BOTTOMLEFT", 1, FOOT)
    footRule:SetPoint("BOTTOMRIGHT", -1, FOOT)
    footRule:SetHeight(1)
    Paint(footRule, "border", 0.8)

    local empty = Theme.CreateLabel(well, "small", "muted")
    empty:SetPoint("TOPLEFT", 14, -(first + 10))
    empty:SetPoint("RIGHT", -14, 0)
    empty:SetWordWrap(true)
    self.empty = empty
end

--------------------------------------------------------------------------------
-- Filling it in
--------------------------------------------------------------------------------

function DQUI:Showing()
    return self.frame ~= nil and self.frame:IsShown()
end

function DQUI:Refresh()
    if not self:Showing() then return end
    local ok, data = pcall(ns.DungeonQuests.Build, ns.DungeonQuests)
    self.data = ok and data or { dungeons = {}, done = 0, all = 0 }
    if self.hideDone and self.hideDone.SetChecked then self.hideDone:SetChecked(ns.DungeonQuests.HideDone()) end
    if self.myLevel and self.myLevel.SetChecked then self.myLevel:SetChecked(ns.DungeonQuests.MyLevelOnly()) end
    local picked = self:Picked()
    if not picked and self.data.dungeons[1] then
        -- The first one with something left to do, else the first.
        for _, dungeon in ipairs(self.data.dungeons) do
            if dungeon.done < dungeon.all then picked = dungeon break end
        end
        picked = picked or self.data.dungeons[1]
        if ns.db then ns.db.dungeonQuestsPick = picked.key end
    end
    self:Fill()
end

function DQUI:Picked()
    local key = ns.db and ns.db.dungeonQuestsPick
    for _, dungeon in ipairs(self.data and self.data.dungeons or {}) do
        if dungeon.key == key then return dungeon end
    end
    return nil
end

function DQUI:PickedQuest()
    local dungeon = self:Picked()
    for _, quest in ipairs(dungeon and dungeon.quests or {}) do
        if quest.questID == self.questPick then return quest end
    end
    return nil
end

function DQUI:Pick(key)
    if ns.db then ns.db.dungeonQuestsPick = key end
    self.questPick, self.questOffset = nil, 0
    self:Fill()
end

function DQUI:PickQuest(questID)
    self.questPick = questID
    self:FillQuests()
end

function DQUI:ScrollDungeons(rows)
    local total = self.data and #self.data.dungeons or 0
    self.dungeonOffset = math.min(math.max(0, total - DUNGEON_ROWS), math.max(0, self.dungeonOffset + rows))
    self:FillDungeons()
end

function DQUI:ScrollQuests(rows)
    local dungeon = self:Picked()
    local total = dungeon and #dungeon.quests or 0
    self.questOffset = math.min(math.max(0, total - QUEST_ROWS), math.max(0, self.questOffset + rows))
    self:FillQuests()
end

function DQUI:Fill()
    local data = self.data
    local toDo = math.max(0, data.all - data.done)
    self.total:SetText(toDo == 1 and L["1 still to do"] or L.Format("%d still to do", toDo))
    self.share = data.all > 0 and data.done / data.all or 0
    self:FillBar()
    self:FillDungeons()
    self:FillQuests()
end

--- The gold bar, again whenever its track gets its width.
function DQUI:FillBar()
    local share = self.share or 0
    local width = self.track:GetWidth()
    width = (type(width) == "number" and width or 0) - 2
    self.fill:SetWidth(math.max(1, width * share))
    self.fill:SetShown(share > 0 and width > 0)
end

function DQUI:FillDungeons()
    local picked = self:Picked()
    for index, row in ipairs(self.dungeonRows) do
        local dungeon = self.data.dungeons[self.dungeonOffset + index]
        row.dungeon = dungeon
        if dungeon then
            local on = picked ~= nil and dungeon.key == picked.key
            row.name:SetText(dungeon.name)
            row.name:SetTextColor(Theme.Unpack(on and "accentHi" or "text"))
            row.levels:SetText(Levels(dungeon))
            row.count:SetText(("%d/%d"):format(dungeon.done, dungeon.all))
            row.count:SetTextColor(Theme.Unpack(dungeon.all > 0 and dungeon.done == dungeon.all and "good" or "text"))
            SetPicked(row, on)
            row:Show()
        else
            row:Hide()
        end
    end
end

local function RewardText(itemID)
    local items = ns.Items
    local name = items and items.Call and items.Call({ "C_Item.GetItemNameByID", "GetItemInfo" }, itemID)
    if type(name) ~= "string" then return nil end
    return name
end

function DQUI:FillQuests()
    local dungeon = self:Picked()
    if not dungeon then
        self.dungeonName:SetText("")
        self.dungeonWhere:SetText("")
        self.dungeonCount:SetText("")
        self.empty:SetText(L["Pick a quest to see where it starts."])
    else
        self.dungeonName:SetText(dungeon.name)
        self.dungeonWhere:SetText(DQUI.Where(dungeon))
        self.dungeonCount:SetText(("%d/%d"):format(dungeon.done, dungeon.all))
        self.empty:SetText("")
    end
    local quests = dungeon and dungeon.quests or {}
    for index, row in ipairs(self.questRows) do
        local quest = quests[self.questOffset + index]
        row.quest = quest
        if quest then
            local look = LOOKS[quest.status] or LOOKS.todo
            row.status:SetText(look[1])
            row.status:SetTextColor(Theme.Unpack(look[2]))
            row.markText:SetText(quest.status == "done" and "+" or quest.status == "log" and "!" or "")
            row.markText:SetTextColor(Theme.Unpack(look[2]))
            Theme.SetBorderColor(row.mark, look[2])
            row.name:SetText(quest.title)
            row.name:SetTextColor(Theme.Unpack(look[3]))
            row.from:SetText(ns.DungeonQuests.From(quest))
            row.level:SetText((quest.level or 0) > 0 and tostring(quest.level) or "")
            local reward = (quest.reward or 0) > 0 and quest.reward or nil
            if reward then
                Theme.SetItemIcon(row.icon, ("item:%d"):format(reward))
                local name = RewardText(reward) or ""
                local r, g, b = Theme.QualityColor(("item:%d"):format(reward))
                if r then row.rewardName:SetTextColor(r, g, b) else row.rewardName:SetTextColor(Theme.Unpack("text")) end
                local advice = ns.Butler and ns.Butler.Advise and select(2, pcall(ns.Butler.Advise, ns.Butler, reward))
                if type(advice) == "table" and advice.upgrade and advice.gain then
                    name = ("%s |c%s+%d%%|r"):format(name, ns.COLORS.upgrade, advice.gain)
                end
                row.rewardName:SetText(name)
            else
                Theme.SetItemIcon(row.icon, nil)
                row.rewardName:SetText("")
            end
            SetPicked(row, quest.questID == self.questPick)
            row:Show()
        else
            row:Hide()
        end
    end
    local quest = self:PickedQuest()
    local place = quest and ns.DungeonQuests.Place(quest)
    if quest then
        local text = ns.DungeonQuests.From(quest)
        if place then text = ("%s (%s, %s)"):format(text, place.x, place.y) end
        self.foot:SetText(text)
    else
        self.foot:SetText(L["Pick a quest to see where it starts."])
    end
    for _, button in ipairs({ self.followButton, self.wayButton }) do
        button:SetAlpha(place and 1 or 0.45)
        if button.SetEnabled then button:SetEnabled(place ~= nil) end
    end
end

--------------------------------------------------------------------------------
-- Showing it
--------------------------------------------------------------------------------

function DQUI:SavePosition()
    if not (ns.db and self.frame) then return end
    local point, _, relativePoint, x, y = self.frame:GetPoint()
    ns.db.dungeonQuestsPoint, ns.db.dungeonQuestsRelPoint = point, relativePoint
    ns.db.dungeonQuestsX, ns.db.dungeonQuestsY = x, y
end

function DQUI:RestorePosition()
    local db = ns.db or {}
    self.frame:ClearAllPoints()
    self.frame:SetPoint(db.dungeonQuestsPoint or "CENTER", UIParent,
        db.dungeonQuestsRelPoint or "CENTER", db.dungeonQuestsX or 0, db.dungeonQuestsY or 0)
end

function DQUI:Show()
    self:Build()
    if not self.frame:IsShown() then
        self:RestorePosition()
        self.frame:Show()
        if Motion and Motion.Open then Motion:Open(self.frame) end
    end
    self:Refresh()
end

function DQUI:Hide()
    if self.frame then self.frame:Hide() end
end

function DQUI:Toggle()
    if self:Showing() then self:Hide() else self:Show() end
end

function DQUI:OnEnable()
    ns.RegisterEvent(self, "GET_ITEM_INFO_RECEIVED", function()
        if not DQUI:Showing() or DQUI.itemPending then return end
        DQUI.itemPending = true
        local after = _G.C_Timer and _G.C_Timer.After
        if type(after) ~= "function" then
            DQUI.itemPending = false
            DQUI:FillQuests()
            return
        end
        after(0.2, function()
            DQUI.itemPending = false
            if DQUI:Showing() then DQUI:FillQuests() end
        end)
    end)
end
