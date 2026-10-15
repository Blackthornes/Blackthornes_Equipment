-- Blackthornes Equipment -- UI/MainWindow.lua
-- The gear window: every slot, what is worn in it, and the biggest upgrade
-- for it sitting in the bags.
--
-- It is what a click on the minimap button and a bare /beq open. Built like
-- the settings window (same header, palette and row heights) so the two read
-- as one set. It only shows: equipping is left to the player, because
-- putting on a bind-on-equip item binds it, and that cannot be undone.

local _, ns = ...
local L = ns.L

local UI = ns.NewModule("UI")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Compare = ns.Compare
local Items = ns.Items
local Weights = ns.Weights

local Motion = ns.Motion

local PADDING = 18
local HEADER = 36

-- The metal rim (UI/Titanforged.lua) reaches this far in from the edge;
-- the header sits inside it.
local RIM = 6
local ROW_HEIGHT = 24
local COLUMN_HEADS = 22
local FOOTER = 48

local ICON = 18
local SLOT_X, WORN_X, BEST_X = 0, 78, 300
local GAIN_WIDTH = 104
local WIDTH = 640

-- The slots in the order the character sheet runs down them.
local SLOTS = {
    { 1, L["Head"] }, { 2, L["Neck"] }, { 3, L["Shoulder"] }, { 15, L["Back"] },
    { 5, L["Chest"] }, { 9, L["Wrist"] }, { 10, L["Hands"] }, { 6, L["Waist"] },
    { 7, L["Legs"] }, { 8, L["Feet"] }, { 11, L["Ring"] }, { 12, L["Ring"] },
    { 13, L["Trinket"] }, { 14, L["Trinket"] }, { 16, L["Main hand"] },
    { 17, L["Off hand"] }, { 18, L["Ranged"] },
}

local HEIGHT = HEADER + 12 + COLUMN_HEADS + #SLOTS * ROW_HEIGHT + FOOTER

UI.SLOTS = SLOTS

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

--- An item's icon and name, showing its tooltip under the mouse. A
--- shift-click puts the item's link in chat, as anywhere in the game.
local function CreateItemCell(parent, width)
    local cell = CreateFrame("Button", nil, parent)
    cell:SetSize(width, ROW_HEIGHT)

    local icon = Theme.CreateItemIcon(cell, ICON)
    icon:SetPoint("LEFT", 0, 0)
    cell.icon = icon

    local text = Theme.CreateLabel(cell, "small", "text")
    text:SetPoint("LEFT", ICON + 6, 0)
    text:SetWidth(width - ICON - 6)
    cell.text = text

    cell:SetScript("OnEnter", function(self)
        local row = parent
        if row and row.Light then Motion:Blend(row, "hover", 1, 0.12, row.Light) end
        if type(self.link) ~= "string" then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        pcall(GameTooltip.SetHyperlink, GameTooltip, self.link)
        if self.elsewhere then GameTooltip:AddLine(self.elsewhere, Theme.Unpack("accent")) end
        if self.wears and not self.elsewhere then GameTooltip:AddLine(L["Click to put it on"], Theme.Unpack("good")) end
        GameTooltip:Show()
    end)
    cell:SetScript("OnLeave", function(self)
        local row = parent
        if row and row.Light then Motion:Blend(row, "hover", 0, 0.18, row.Light) end
        GameTooltip:Hide()
    end)
    cell:SetScript("OnClick", function(self)
        if type(self.link) ~= "string" then return end
        if type(IsModifiedClick) == "function" and type(ChatEdit_InsertLink) == "function" then
            local ok, chatLink = pcall(IsModifiedClick, "CHATLINK")
            if ok and chatLink then
                pcall(ChatEdit_InsertLink, self.link)
                return
            end
        end
        -- A click on an upgrade in the bags puts it on.
        if self.wears and not self.elsewhere and ns.Wear then ns.Wear:PutOn(self.link) end
    end)
    return cell
end

function UI:Build()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "BlackthornesEquipmentWindow", UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")

    Theme.Fill(frame, "window")

    -- The house frame: a gold rim with corner gems, the shield in a round
    -- portrait, the name on a plate and a red close gem (UI/Titanforged.lua).
    if ns.Titanforged then
        local trim = ns.Titanforged:Dress(frame, {
            title = "Blackthornes Equipment",
            portrait = true,
            close = function() UI:Hide() end,
        })

        -- Kept on the screen whole: the portrait and plate reach out past
        -- the top left, the close gem past the top right.
        local left, right, top, bottom = ns.Titanforged.Reach(trim)
        if frame.SetClampRectInsets then frame:SetClampRectInsets(-left, right, top, -bottom) end
    else
        Theme.Border(frame, "borderLit")
    end

    -- The house glow round the outside, flaring as the window opens.
    Theme.Halo(frame, 12, 0.14)

    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        UI:SavePosition()
    end)

    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "BlackthornesEquipmentWindow")
    end

    self.frame = frame
    self:BuildHeader()
    self:BuildRows()

    -- Where to go for an upgrade that is not in the bags yet. Down here
    -- rather than in the header, where the spec line needs the room.
    local find = Widgets.CreateButton(frame, L["Find upgrades"], function()
        if ns.FinderUI then ns.FinderUI:Toggle() end
    end, { width = 100, height = 24, primary = true })
    find:SetPoint("BOTTOMRIGHT", -PADDING, 12)
    self.findButton = find

    local footer = Theme.CreateLabel(frame, "normal", "muted")
    footer:SetPoint("BOTTOMLEFT", PADDING, 26)
    footer:SetPoint("BOTTOMRIGHT", find, "BOTTOMLEFT", -10, 14)
    self.footer = footer

    -- The installed version, small and faint at the end of the hint's line
    -- beside Find upgrades, so a player can see at a glance which one they
    -- run.
    local version = Theme.CreateLabel(frame, "tiny", "dim", "RIGHT")
    version:SetPoint("BOTTOMRIGHT", find, "BOTTOMLEFT", -10, -1)
    version:SetText(ns.VersionLabel())
    self.versionLabel = version

    local hint = Theme.CreateLabel(frame, "tiny", "dim")
    hint:SetPoint("BOTTOMLEFT", PADDING, 11)
    hint:SetPoint("BOTTOMRIGHT", version, "BOTTOMLEFT", -12, 0)
    hint:SetText(L["Hover an item for its tooltip. Click an upgrade to put it on."])
    self.hint = hint

    frame:Hide()
    return frame
end

function UI:BuildHeader()
    local frame = self.frame

    -- The window's name is on the plate across the top edge and the close
    -- gem sits on the top right corner (UI/Titanforged.lua), so the header
    -- holds the spec line, clear of the portrait on the left, and the
    -- Settings button. Both sit a little low, under the plate.
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", RIM, 0)
    header:SetPoint("TOPRIGHT", -RIM, 0)
    header:SetHeight(HEADER)

    local settings = Widgets.CreateButton(header, L["Settings"], function()
        if ns.SettingsUI then ns.SettingsUI:Toggle() end
    end, { width = 70, height = 20 })
    settings:SetPoint("RIGHT", -(PADDING + 6 - RIM), -4)

    -- Closes the upgrade quest, or brings it back with its quests as they
    -- were (the owner asked 2026-10-13 for an easy way to do both). Its
    -- label is green while the quest is up.
    local quest = Widgets.CreateButton(header, L["Upgrade quest"], function()
        if ns.UpgradeQuest then ns.UpgradeQuest:Toggle() end
    end, { width = 104, height = 20 })
    quest:SetPoint("RIGHT", settings, "LEFT", -6, 0)
    quest:HookScript("OnEnter", function(self)
        local on = ns.UpgradeQuest and ns.UpgradeQuest:IsEnabled()
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["Upgrade quest"], Theme.Unpack("accent"))
        GameTooltip:AddLine(on and L["Closes the upgrade quest. Your quests stay saved."]
            or L["Brings back the upgrade quest, with the steps to your next upgrade."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    quest:HookScript("OnLeave", function() GameTooltip:Hide() end)
    self.questButton = quest
    self:OnUpgradeQuestToggled()

    -- Opens the Training drawer beside the window (UI/TrainingDrawer.lua):
    -- class spells to train and what they cost. It says how many wait.
    local training = Widgets.CreateButton(header, L["Training"], function()
        if ns.TrainingDrawer then ns.TrainingDrawer:Toggle() end
    end, { width = 80, height = 20 })
    training:SetPoint("RIGHT", quest, "LEFT", -6, 0)
    training:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["Class training"], Theme.Unpack("accent"))
        GameTooltip:AddLine(L["Spells you can train, what they cost and where your trainer is."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    training:HookScript("OnLeave", function() GameTooltip:Hide() end)
    self.trainingButton = training
    self:OnTrainingToggled()

    -- Stops short of the buttons, so a long spec name never runs under
    -- them.
    local spec = Theme.CreateLabel(header, "small", "muted")
    spec:SetPoint("LEFT", 58 - RIM, -4)
    spec:SetPoint("RIGHT", training, "LEFT", -10, 0)
    self.specLabel = spec

    -- A gold rule under it, bright at the left and fading out to the right.
    local rule = header:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    rule:SetHeight(1)
    Theme.SetGradientAlpha(rule, "HORIZONTAL", "accent", 0.6, 0.05)
end

--- The Upgrade quest button's label: green while the quest is up.
function UI:OnUpgradeQuestToggled()
    local button = self.questButton
    if not (button and button.SetLabelColor) then return end
    local on = ns.UpgradeQuest ~= nil and ns.UpgradeQuest:IsEnabled()
    button:SetLabelColor(on and "good" or "gilt")
end

--- The Training button: how many spells wait, gold while there are some,
--- green while the drawer is open. Hidden while class training is off.
function UI:OnTrainingToggled()
    local button = self.trainingButton
    if not (button and button.SetText) then return end
    local training = ns.ClassTraining
    local on = training ~= nil and training:IsOn()
    button:SetShown(on)
    if not on then return end
    local count = #training:Plan().ready
    button:SetText(count > 0 and L.Format("Training (%d)", count) or L["Training"])
    local open = ns.TrainingDrawer ~= nil and ns.TrainingDrawer:IsShown()
    button:SetLabelColor(open and "good" or (count > 0 and "accentHi" or "gilt"))
end

function UI:BuildRows()
    local frame = self.frame
    local top = -(HEADER + 12)
    local inner = WIDTH - PADDING * 2

    local heads = { { SLOT_X, L["SLOT"] }, { WORN_X, L["WEARING"] }, { BEST_X, L["BEST IN BAGS"] } }
    for _, head in ipairs(heads) do
        local label = Theme.CreateLabel(frame, "tiny", "accent")
        label:SetPoint("TOPLEFT", PADDING + head[1], top - 4)
        label:SetText(head[2])
    end

    -- The rows sit sunk into the window, as the game's inset lists do.
    local well = Theme.CreatePanel(frame, "panel", "border")
    well:SetPoint("TOPLEFT", PADDING - 3, top - COLUMN_HEADS + 3)
    well:SetSize(inner + 6, #SLOTS * ROW_HEIGHT + 6)
    Theme.Recess(well)

    self.rows = {}
    for index, entry in ipairs(SLOTS) do
        local restKey = index % 2 == 0 and "glassAlt" or "glass"
        local row = CreateFrame("Frame", nil, frame)
        -- Above the well, whatever order the client draws siblings in.
        row:SetFrameLevel(well:GetFrameLevel() + 1)
        row:SetSize(inner, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", PADDING, top - COLUMN_HEADS - (index - 1) * ROW_HEIGHT)
        row.background = Theme.Fill(row, restKey)

        -- Dark glass: a fine line under each row.
        local line = row:CreateTexture(nil, "BACKGROUND", nil, 1)
        line:SetPoint("BOTTOMLEFT")
        line:SetPoint("BOTTOMRIGHT")
        line:SetHeight(1)
        line:SetColorTexture(Theme.Unpack("border", 0.6))

        -- A slot with an upgrade waiting gets a green edge and a faint green
        -- wash, so the eye finds it before reading anything.
        local wash = row:CreateTexture(nil, "BACKGROUND", nil, 2)
        wash:SetAllPoints(row)
        wash:Hide()
        row.wash = wash

        local edge = row:CreateTexture(nil, "ARTWORK")
        edge:SetPoint("TOPLEFT")
        edge:SetPoint("BOTTOMLEFT")
        edge:SetWidth(2)
        edge:SetColorTexture(Theme.Unpack("good"))
        edge:Hide()
        row.edge = edge

        local name = Theme.CreateLabel(row, "small", "muted")
        name:SetPoint("LEFT", SLOT_X + 8, 0)
        name:SetText(entry[2])

        local worn = CreateItemCell(row, BEST_X - WORN_X - 10)
        worn:SetPoint("LEFT", WORN_X, 0)

        local best = CreateItemCell(row, inner - BEST_X - GAIN_WIDTH - 10)
        best:SetPoint("LEFT", BEST_X, 0)
        best.wears = true

        local gain = Theme.CreateLabel(row, "small", "good", "RIGHT")
        gain:SetPoint("RIGHT", -8, 0)
        gain:SetWidth(GAIN_WIDTH)

        -- Under the mouse the row lights from the left: a soft gold wash
        -- fading across it (Titanforged). Hidden at rest.
        local hoverWash = row:CreateTexture(nil, "BACKGROUND", nil, 3)
        hoverWash:SetAllPoints(row)
        hoverWash:Hide()
        row.hoverWash = hoverWash

        -- The house hover's gold edge down the left, over the green one.
        local hoverEdge = row:CreateTexture(nil, "OVERLAY")
        hoverEdge:SetPoint("TOPLEFT")
        hoverEdge:SetPoint("BOTTOMLEFT")
        hoverEdge:SetWidth(2)
        hoverEdge:SetColorTexture(Theme.Unpack("accentHi"))
        hoverEdge:SetAlpha(0)

        function row.Light(p)
            row.background:SetColorTexture(Motion.Mix(restKey, "glassHover", p))
            Theme.LightGradient(hoverWash, "HORIZONTAL", "accent", 0.10, 0, p)
            hoverEdge:SetAlpha(p)
        end

        -- The whole row lights under the mouse, the slot name too.
        row:EnableMouse(true)
        row:SetScript("OnEnter", function() Motion:Blend(row, "hover", 1, 0.12, row.Light) end)
        row:SetScript("OnLeave", function() Motion:Blend(row, "hover", 0, 0.18, row.Light) end)

        self.rows[index] = {
            slot = entry[1], frame = row, worn = worn, best = best, gain = gain, name = name,
        }
    end
end

--------------------------------------------------------------------------------
-- Filling it in
--------------------------------------------------------------------------------

local function SetCell(cell, link, emptyText, colorKey)
    cell.link = link
    Theme.SetItemIcon(cell.icon, link)
    if link then
        cell.text:SetText(link)
        cell.text:SetTextColor(Theme.Unpack("text"))
        cell.text:SetPoint("LEFT", ICON + 6, 0)
    else
        cell.text:SetText(emptyText)
        cell.text:SetTextColor(Theme.Unpack(colorKey or "dim"))
        cell.text:SetPoint("LEFT", 0, 0)
    end
end

--- Light a row for an upgrade, flaring green the first time it shows.
local function MarkUpgrade(row, on, fresh)
    row.frame.edge:SetShown(on)
    row.frame.wash:SetShown(on)
    row.name:SetTextColor(Theme.Unpack(on and "text" or "muted"))
    if not on then
        Motion:Stop(row.frame, "flare")
        row.gain:SetAlpha(1)
        return
    end

    local function Wash(alpha)
        Theme.SetGradientAlpha(row.frame.wash, "HORIZONTAL", "good", alpha, 0)
    end
    if fresh then
        Motion:Run(row.frame, "flare", 0.8, function(p)
            Wash(0.34 - 0.24 * p)
            row.gain:SetAlpha(0.3 + 0.7 * p)
        end)
    else
        Wash(0.10)
    end
end

--- Put what is worn and what is in the bags into every row.
-- @return how many slots have an upgrade waiting
function UI:Refresh()
    if not (self.frame and self.frame:IsShown()) then return 0 end

    local spec, why, class = Weights:CurrentSpec()
    local best = {}
    if spec then
        local ok, found = pcall(Compare.BestInBags, Compare)
        if ok then best = found end
        self.specLabel:SetText(L.Format("judging gear as %s", Weights:SpecName(class, spec)))
    else
        self.specLabel:SetText("")
    end

    -- Better gear you own but do not carry: in your bank, or loose on
    -- another character (Alts:BetterElsewhere), for slots the bags leave
    -- empty-handed.
    local elsewhere = {}
    if spec and ns.Alts then
        local ok, found = pcall(ns.Alts.BetterElsewhere, ns.Alts)
        if ok then elsewhere = found end
    end

    local upgrades, owned = 0, 0
    -- Untrained weapons waiting as upgrades, for the Training drawer.
    local untrained, keys = {}, {}
    for _, row in ipairs(self.rows) do
        SetCell(row.worn, Items:Equipped(row.slot), "empty")

        local pick = best[row.slot]
        local other = not pick and elsewhere[row.slot] or nil
        row.best.elsewhere = nil
        if pick then
            upgrades = upgrades + 1
            SetCell(row.best, pick.link)
            -- An untrained weapon is shown, never offered to put on.
            local skill = pick.result.skill
            row.best.wears = not skill
            if skill then
                untrained[#untrained + 1] = { link = pick.link, skill = skill }
                keys[#keys + 1] = pick.link
                row.gain:SetText(L.Format("Train: %s", Compare:HowMuch(pick.result)))
                row.gain:SetTextColor(Theme.Unpack("loss"))
            else
                row.gain:SetText(Compare:HowMuch(pick.result))
                row.gain:SetTextColor(Theme.Unpack("good"))
            end
        elseif other then
            owned = owned + 1
            SetCell(row.best, other.link)
            row.best.elsewhere = UI.WhereText(other.where)
            row.best.text:SetText(UI.BestElsewhereText(row.best.text, other.link, other.where))
            row.gain:SetText(Compare:HowMuch(other.result))
            row.gain:SetTextColor(Theme.Unpack("accent"))
        else
            SetCell(row.best, nil, "-")
            row.gain:SetText("")
        end

        -- Flares only when this is news: a new pick, not every redraw.
        local shown = pick and pick.link or nil
        MarkUpgrade(row, shown ~= nil, shown ~= nil and shown ~= row.shown)
        row.shown = shown
    end

    if spec and Weights:IsCustom(class, spec) then
        self.hint:SetText(L["Judged by your own stat weights. Click an upgrade to put it on."])
    else
        self.hint:SetText(L["Hover an item for its tooltip. Click an upgrade to put it on."])
    end

    self.footer:SetTextColor(Theme.Unpack(upgrades > 0 and "good" or "muted"))
    if not spec then
        self.footer:SetText(L.Format("There are no stat weights for %s yet.", class or L["this class"]))
    elseif upgrades == 0 and ns.Alts and ns.Alts:PlayerSkipped() then
        self.footer:SetText(L["Upgrades are skipped for this character. Untick it in Settings, or type /beq skip off."])
    elseif upgrades == 0 and owned > 0 then
        self.footer:SetTextColor(Theme.Unpack("accent"))
        if owned == 1 then
            self.footer:SetText(L["Nothing in your bags beats what you wear, but you own 1 better piece elsewhere."])
        else
            self.footer:SetText(L.Format("Nothing in your bags beats what you wear, but you own %d better pieces elsewhere.", owned))
        end
    elseif upgrades == 0 then
        self.footer:SetText(L["Nothing in your bags beats what you wear."])
    elseif upgrades == 1 then
        self.footer:SetText(L["1 upgrade in your bags."])
    else
        self.footer:SetText(L.Format("%d upgrades in your bags.", upgrades))
    end
    self.upgrades = upgrades
    self.untrained = untrained
    self.untrainedKey = table.concat(keys, ",")
    self:OnTrainingToggled()
    if ns.TrainingDrawer then ns.TrainingDrawer:Refresh() end
    return upgrades
end

--- Where better gear is, for its tooltip: "In your bank" or "On Ana
--- Smith: mail it over".
function UI.WhereText(where)
    if where == "bank" then return L["In your bank. Take it out to wear it"] end
    local name = ns.Alts and ns.Alts:NameOf(where) or nil
    return L.Format("On %s. Mail it over to wear it", name or L["another of your characters"])
end

--- The same, short, beside the item: "bank" or the character's name.
function UI.ShortWhere(where)
    if where == "bank" then return L["in your bank"] end
    local name = ns.Alts and ns.Alts:NameOf(where) or nil
    return name and L.Format("on %s", name) or L["on an alt"]
end

--- The best cell's words for gear in the bank or on another character:
--- the link and "(on NAME)" when the whole name fits, else "(on an alt)",
--- so a last name is never cut short. The tooltip names the character.
function UI.BestElsewhereText(label, link, where)
    local text = ("%s |c%s(%s)|r"):format(link, ns.COLORS.accent, UI.ShortWhere(where))
    if where == "bank" or not Theme.TextWidth then return text end
    local ok, room = pcall(label.GetWidth, label)
    local okText, wide = pcall(Theme.TextWidth, "small", text)
    if ok and okText and type(room) == "number" and room > 0 and type(wide) == "number" and wide > room then
        return ("%s |c%s(%s)|r"):format(link, ns.COLORS.accent, L["on an alt"])
    end
    return text
end

--- Refresh once a burst of bag events settles.
function UI:RefreshSoon()
    if not (self.frame and self.frame:IsShown()) or self.pending then return end
    self.pending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0.2, function()
            UI.pending = false
            UI:Refresh()
        end)
    else
        self.pending = false
        self:Refresh()
    end
end

--------------------------------------------------------------------------------
-- Position and visibility
--------------------------------------------------------------------------------

function UI:SavePosition()
    if not (ns.db and self.frame) then return end
    local point, _, relativePoint, x, y = self.frame:GetPoint()
    ns.db.point, ns.db.relativePoint, ns.db.x, ns.db.y = point, relativePoint, x, y
end

function UI:RestorePosition()
    if not self.frame then return end
    local db = ns.db or {}
    self.frame:ClearAllPoints()
    self.frame:SetPoint(db.point or "CENTER", UIParent, db.relativePoint or "CENTER",
        db.x or 0, db.y or 40)
end

function UI:Show()
    self:Build()
    if not self.frame:IsShown() then
        self:RestorePosition()
        self.frame:Show()
        Motion:Open(self.frame)
        -- And a light runs round the portrait.
        if ns.Titanforged then ns.Titanforged:Opened(self.frame) end
    end
    self:Refresh()
    if ns.TrainingDrawer then ns.TrainingDrawer:WindowShown() end
end

function UI:Hide()
    if self.frame then self.frame:Hide() end
end

function UI:Toggle()
    if self.frame and self.frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

local EVENTS = {
    "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP",
    "GET_ITEM_INFO_RECEIVED", "TRAIT_CONFIG_UPDATED",
}

function UI:OnEnable()
    for _, event in ipairs(EVENTS) do
        ns.RegisterEvent(self, event, self.RefreshSoon)
    end
end

ns.RegisterCommand("window", L["open the gear window (so does /beq on its own)"], function()
    UI:Toggle()
end)
