-- Blackthornes Equipment -- UI/QuestLogTab.lua
-- What the small panel's Log (UI/SmallPanel.lua) needs beside the list it
-- draws itself: the character's quests as the game's tracker shows them
-- (the owner asked 2026-10-10: one place for every quest, with the same
-- clicks).
--
--   * "Tracked Only" and "Hide Game's Tracker", and their saved choices.
--   * A quest's right-click menu: Show on map, Point the arrow here, Track
--     or Untrack, Open in quest log, Share with party, Abandon quest.
--   * A button for a quest's item to use.
--   * The green mark on a quest whose reward is an upgrade.
--
-- The list itself was a tab on the old upgrade quest panel; rework step 6
-- (2026-11-23) took that panel out, and the small panel lists the quests.
--
-- Nothing of the game's tracker is moved, re-parented, hidden or shown.
-- "Hiding" it is ns.Veil (UI/Veil.lua): see-through, its lines no longer
-- taking the mouse, caught again after a burst of quest events, and put back
-- when the panel closes. Never Hide or Show: that runs the game's own code
-- as this addon and taints Edit Mode. A protected line waits for combat to
-- end.
--
-- Quest item buttons are secure buttons (using an item is protected), so
-- they are kept outside the panel and placed over their row by screen
-- position, as Pets' Feed button is: the panel stays free to move, fold and
-- close in combat. In combat they cannot be moved, shown or hidden, so a
-- button whose row moved fades out until the fight ends and then comes back
-- in its place.

local _, ns = ...
local L = ns.L

local QuestLogUI = ns.NewModule("QuestLogUI")

local Theme = ns.Theme

local ITEM = 30
QuestLogUI.ITEM = ITEM
local MOST_ITEMS = 8

local function InCombat()
    local fn = _G.InCombatLockdown
    if type(fn) ~= "function" then return false end
    local ok, value = pcall(fn)
    return ok and value == true
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

--- "Tracked only": list only tracked quests. Account wide, off unless ticked.
function QuestLogUI:TrackedOnly()
    return ns.db ~= nil and ns.db.questLogTrackedOnly == true
end

function QuestLogUI:SetTrackedOnly(on)
    if not ns.db then return end
    ns.db.questLogTrackedOnly = on and true or false
    self:Changed()
end

--- "Hide the game's quest tracker" while the panel is up. Account wide, off
--- unless ticked.
function QuestLogUI:HidesTracker()
    return ns.db ~= nil and ns.db.hideQuestTracker == true
end

function QuestLogUI:SetHidesTracker(on)
    if not ns.db then return end
    ns.db.hideQuestTracker = on and true or false
    self:ApplyTracker()
    self:Changed()
end

--- Settings, the panel's tick boxes and the menu all go through here.
function QuestLogUI:Changed()
    if ns.SmallPanel and ns.SmallPanel.frame then ns.SmallPanel:Refresh() end
    if ns.SettingsUI and ns.SettingsUI.Refresh then ns.SettingsUI:Refresh() end
end

--------------------------------------------------------------------------------
-- The upgrade mark
--------------------------------------------------------------------------------

--- The green mark for a quest whose reward is an upgrade ("+6% Head"),
--- from the finder's last scan only (UpgradeQuest:RewardMark), or nil.
function QuestLogUI.MarkText(questID)
    local quest = ns.UpgradeQuest
    if not (questID and quest and quest.RewardMark) then return nil end
    local ok, mark = pcall(quest.RewardMark, quest, questID)
    if not ok or type(mark) ~= "table" then return nil end
    local slot = ns.Enchants and ns.Enchants.SlotName and ns.Enchants.SlotName(mark.slot) or ""
    if mark.empty or (mark.percent or 0) <= 0 then
        return slot ~= "" and slot or nil
    end
    local percent = math.floor(mark.percent + 0.5)
    if slot == "" then return ("+%d%%"):format(percent) end
    return L.Format("+%d%% %s", percent, slot)
end

--------------------------------------------------------------------------------
-- What a click or a menu line does to a quest
--------------------------------------------------------------------------------

function QuestLogUI:Act(what, quest)
    local log = ns.QuestLog
    if what == "open" then return log:Open(quest) end
    if not quest then return false end
    if what == "map" then return log:ShowOnMap(quest) end
    if what == "arrow" then
        local arrow = ns.QuestArrow
        local free = arrow and arrow.IsOn() and arrow:FreeQuest()
        -- Pointing at this one already: back to the upgrade quest.
        -- Only the log quest is let go: moving on to another tab would take
        -- the panel off the Quest log tab.
        if free and free.questID == quest.questID and free.title == quest.title then
            arrow.free = nil
            arrow:Changed(true)
            self:Changed()
            return true
        end
        local ok = log:Aim(quest)
        self:Changed()
        return ok
    end
    if what == "track" or what == "untrack" then
        local ok = log:SetTracked(quest, what == "track")
        self:LogChanged()
        return ok
    end
    if what == "share" then return log:Share(quest) end
    if what == "abandon" then return log:Abandon(quest) end
    return false
end

--------------------------------------------------------------------------------
-- The right-click menu
--------------------------------------------------------------------------------

local MENU_WIDTH = 176
local MENU_ROW = 20

function QuestLogUI:BuildMenu()
    if self.menu then return self.menu end
    local menu = CreateFrame("Frame", "BlackthornesEquipmentQuestMenu", UIParent)
    menu:SetFrameStrata("DIALOG")
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu:SetWidth(MENU_WIDTH)
    Theme.Fill(menu, "window")
    Theme.Border(menu, "accent", 0.9)
    Theme.Halo(menu, 8, 0.3, "accent")
    menu.title = Theme.CreateLabel(menu, "small", "gilt")
    menu.title:SetPoint("TOPLEFT", 12, -8)
    menu.title:SetWidth(MENU_WIDTH - 24)
    -- A long quest title wraps rather than ending in "...".
    menu.title:SetWordWrap(true)
    menu.title:SetJustifyV("TOP")
    menu.line = menu:CreateTexture(nil, "ARTWORK")
    menu.line:SetPoint("TOPLEFT", 10, -26)
    menu.line:SetSize(MENU_WIDTH - 20, 1)
    menu.line:SetColorTexture(Theme.Unpack("metal", 0.7))
    menu.entries = {}
    -- Escape closes it, as it does the game's menus.
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "BlackthornesEquipmentQuestMenu") end
    menu:Hide()
    self.menu = menu
    return menu
end

local function MenuEntry(menu, index)
    local entry = menu.entries[index]
    if entry then return entry end
    entry = CreateFrame("Button", nil, menu)
    entry:SetSize(MENU_WIDTH - 8, MENU_ROW)
    entry.wash = entry:CreateTexture(nil, "BACKGROUND")
    entry.wash:SetAllPoints(entry)
    entry.wash:SetColorTexture(Theme.Unpack("accent", 0.18))
    entry.wash:Hide()
    entry.label = Theme.CreateLabel(entry, "small", "text")
    entry.label:SetPoint("LEFT", 8, 0)
    entry:SetScript("OnEnter", function(self) self.wash:Show() end)
    entry:SetScript("OnLeave", function(self) self.wash:Hide() end)
    entry:SetScript("OnClick", function(self)
        local quest = menu.quest
        QuestLogUI:CloseMenu()
        if quest and self.action then QuestLogUI:Act(self.action, quest) end
    end)
    menu.entries[index] = entry
    return entry
end

--- The menu's lines for a quest: { text, action, color }.
function QuestLogUI:MenuFor(quest)
    local log = ns.QuestLog
    local list = { { L["Show on Map"], "map" } }
    if log.Place(quest) or (ns.Waypoints and quest.zone and ns.Waypoints:MapFor(quest.zone)) then
        list[#list + 1] = { L["Point the arrow here"], "arrow" }
    end
    list[#list + 1] = quest.tracked and { L["Untrack"], "untrack" } or { L["Track"], "track" }
    list[#list + 1] = { L["Open in quest log"], "open" }
    if log:CanShare(quest) then list[#list + 1] = { L["Share with party"], "share" } end
    list[#list + 1] = { L["Abandon quest"], "abandon", "loss" }
    return list
end

function QuestLogUI:OpenMenu(quest)
    local menu = self:BuildMenu()
    menu.quest = quest
    menu.title:SetText(quest.title)
    -- The line and the entries sit under however many lines the title took.
    local okHeight, titleHeight = pcall(menu.title.GetStringHeight, menu.title)
    titleHeight = okHeight and tonumber(titleHeight) or 0
    titleHeight = math.max(titleHeight, Theme.sizes.small or 12)
    menu.line:ClearAllPoints()
    menu.line:SetPoint("TOPLEFT", 10, -(titleHeight + 15))
    local list = self:MenuFor(quest)
    local y = titleHeight + 21
    for index, item in ipairs(list) do
        local entry = MenuEntry(menu, index)
        entry.action = item[2]
        entry.label:SetText(item[1])
        entry.label:SetTextColor(Theme.Unpack(item[3] or "text"))
        entry:ClearAllPoints()
        entry:SetPoint("TOPLEFT", 4, -y)
        entry.wash:Hide()
        entry:Show()
        y = y + MENU_ROW
    end
    for index = #list + 1, #menu.entries do menu.entries[index]:Hide() end
    menu:SetHeight(y + 6)

    -- Where the click was, a little in so the first line is under the cursor.
    menu:ClearAllPoints()
    local cx, cy = GetCursorPosition()
    local okScale, scale = pcall(UIParent.GetEffectiveScale, UIParent)
    if cx and cy and okScale and type(scale) == "number" and scale > 0 then
        menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cx / scale - 12, cy / scale + 12)
    else
        menu:SetPoint("CENTER", UIParent, "CENTER")
    end
    menu:Show()
end

function QuestLogUI:CloseMenu()
    if self.menu and self.menu:IsShown() then self.menu:Hide() end
end

--- A click anywhere else closes the menu.
function QuestLogUI:OnMouseDown()
    local menu = self.menu
    if not (menu and menu:IsShown()) then return end
    local over = false
    if type(_G.MouseIsOver) == "function" then
        local ok, value = pcall(_G.MouseIsOver, menu)
        over = ok and value == true
    else
        local ok, value = pcall(menu.IsMouseOver, menu)
        over = ok and value == true
    end
    if not over then menu:Hide() end
end

--------------------------------------------------------------------------------
-- Quest item buttons
--------------------------------------------------------------------------------

local function NewItemButton(index)
    local button = CreateFrame("Button", "BlackthornesEquipmentQuestItem" .. index, UIParent,
        "SecureActionButtonTemplate")
    button:SetSize(ITEM, ITEM)
    button:SetFrameStrata("MEDIUM")
    button:RegisterForClicks("AnyUp", "AnyDown")
    button:SetAttribute("type", "item")
    Theme.Fill(button, "panel")
    Theme.Border(button, "accent", 0.9)
    Theme.Halo(button, 5, 0.3, "accent")
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 1, -1)
    button.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.count = Theme.CreateLabel(button, "tiny", "text", "RIGHT")
    button.count:SetPoint("BOTTOMRIGHT", -2, 2)
    local ok, cooldown = pcall(CreateFrame, "Cooldown", nil, button, "CooldownFrameTemplate")
    if ok and cooldown then
        cooldown:SetAllPoints(button.icon)
        button.cooldown = cooldown
    end
    button:HookScript("OnEnter", function(hovered)
        -- A button faded in combat (PlaceItems) has no row under it.
        if not hovered.link or hovered:GetAlpha() == 0 then return end
        GameTooltip:SetOwner(hovered, "ANCHOR_LEFT")
        pcall(GameTooltip.SetHyperlink, GameTooltip, hovered.link)
        GameTooltip:AddLine(L["Click to use it."], Theme.Unpack("accent"))
        GameTooltip:Show()
    end)
    button:HookScript("OnLeave", function() GameTooltip:Hide() end)
    button:Hide()
    return button
end

--- An item button's cooldown swirl, from the bags' cooldown for the item.
local function ShowCooldown(button)
    local cooldown = rawget(button, "cooldown")
    if not (cooldown and button.itemID) then return end
    local get = (type(_G.C_Container) == "table" and _G.C_Container.GetItemCooldown) or _G.GetItemCooldown
    if type(get) ~= "function" then return end
    local ok, start, duration, enable = pcall(get, button.itemID)
    if ok and tonumber(start) and tonumber(duration) and pcall(cooldown.SetCooldown, cooldown, start, duration,
        enable) then
        return
    end
end

--- Put each quest's item button over its row, and put the others away.
--- In combat nothing secure can move, show or hide: a button whose row has
--- moved fades out instead, until the fight ends.
function QuestLogUI:PlaceItems()
    self.items = self.items or {}
    local wanted = {}
    -- The small panel's Log (UI/SmallPanel.lua) says where its rows are.
    local small = ns.SmallPanel
    if small and not self.dragging then wanted = small:ItemSpots(MOST_ITEMS) end
    local over = small and small.frame

    if InCombat() then
        for index, button in ipairs(self.items) do
            local want = wanted[index]
            local same = want and button:IsShown() and button.link == want.row.quest.item.link
                and button.at and math.abs(button.at.left - want.spot.left) < 0.5
                and math.abs(button.at.top - want.spot.top) < 0.5
            pcall(button.SetAlpha, button, same and 1 or 0)
        end
        self.placeAfterCombat = true
        return
    end

    for index, want in ipairs(wanted) do
        local button = self.items[index]
        if not button then
            button = NewItemButton(index)
            self.items[index] = button
        end
        local item = want.row.quest.item
        if button.link ~= item.link then
            button.link = item.link
            button.itemID = item.itemID
            button:SetAttribute("item", item.itemID and ("item:%d"):format(item.itemID) or item.link)
            button.icon:SetTexture(item.texture or (Theme.ItemIcon and Theme.ItemIcon(item.link)))
        end
        button.count:SetText(item.charges and item.charges > 1 and tostring(item.charges) or "")
        button:SetScale(want.spot.scale)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", want.spot.left, want.spot.top)
        pcall(button.SetFrameLevel, button, (over and over:GetFrameLevel() or 1) + 40)
        button.at = want.spot
        button:SetAlpha(1)
        button:Show()
        ShowCooldown(button)
    end
    for index = #wanted + 1, #self.items do
        local button = self.items[index]
        button:Hide()
        button.at = nil
    end
    self.placeAfterCombat = nil
end

--- Place the buttons now, on the next frame (once the game has laid out
--- what just moved), and once the panel has settled (it rises into place
--- as it opens). Each wait is booked once, however often this is asked.
function QuestLogUI:PlaceItemsSoon()
    self:PlaceItems()
    local after = C_Timer and C_Timer.After
    for _, wait in ipairs({ 0, 0.35 }) do
        local flag = "placing" .. wait
        if not self[flag] then
            self[flag] = true
            local function Later()
                QuestLogUI[flag] = false
                QuestLogUI:PlaceItems()
            end
            if after then after(wait, Later) else Later() end
        end
    end
end

function QuestLogUI:OnCooldowns()
    for _, button in ipairs(self.items or {}) do
        if button:IsShown() then ShowCooldown(button) end
    end
end

--------------------------------------------------------------------------------
-- The game's tracker
--------------------------------------------------------------------------------

-- The tracker on a retail client, and on a classic one.
QuestLogUI.TRACKERS = { "ObjectiveTrackerFrame", "QuestWatchFrame" }

-- The tracker is never hidden with Hide: that would run the game's own
-- OnHide code as this addon, and the tracker is an Edit Mode frame, so the
-- taint ends up in Edit Mode's layout (UI/Veil.lua says more). It is made
-- see-through and stops taking the mouse instead, and the game goes on
-- running it as before.

--- Should the game's tracker be out of sight now: the setting on and the
--- panel up?
function QuestLogUI:WantsTrackerHidden()
    local panel = ns.SmallPanel
    return self:HidesTracker() and panel and panel.frame ~= nil and panel.frame:IsShown() == true
end

--- Is a tracker out of sight through this addon?
function QuestLogUI:TrackerHidden(name)
    local frame = rawget(_G, name)
    return type(frame) == "table" and ns.Veil:Covers(frame)
end

--- Put the game's tracker out of sight or bring it back, as the setting and
--- the panel say.
function QuestLogUI:ApplyTracker()
    local hide = self:WantsTrackerHidden()
    for _, name in ipairs(self.TRACKERS) do
        local frame = rawget(_G, name)
        if type(frame) == "table" then
            local done
            if hide then
                done = ns.Veil:Cover(frame)
            else
                done = ns.Veil:Uncover(frame)
            end
            if not done then self.trackerAfterCombat = true end
        end
    end
end

--- The game may add lines to the tracker while it is out of sight: catch
--- them once the burst of quest events is over.
function QuestLogUI:TrackerChanged()
    if self.trackerPending or not self:WantsTrackerHidden() then return end
    self.trackerPending = true
    local function Later()
        QuestLogUI.trackerPending = false
        QuestLogUI:ApplyTracker()
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.2, Later) else Later() end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

--- Is the small panel's Log on screen?
function QuestLogUI:Showing()
    local panel = ns.SmallPanel
    return panel ~= nil and panel.frame ~= nil and panel.frame:IsShown() == true
        and panel:View() == "log" and not panel:OneLine()
end

--- The log changed (a quest tracked or untracked here): the small panel
--- reads it again once the burst is over.
function QuestLogUI:LogChanged()
    if ns.SmallPanel then ns.SmallPanel:LogChanged() end
end

--- The panel was shown or hidden (closed, or the upgrade quest turned off).
function QuestLogUI:OnPanelShown(shown)
    if not shown then self:CloseMenu() end
    self:ApplyTracker()
    self:PlaceItems()
end

function QuestLogUI:OnEnable()
    for _, event in ipairs({ "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "QUEST_ACCEPTED",
        "UNIT_QUEST_LOG_CHANGED" }) do
        ns.RegisterEvent(self, event, function(_, _, unit)
            if event == "UNIT_QUEST_LOG_CHANGED" and unit ~= "player" then return end
            QuestLogUI:TrackerChanged()
        end)
    end
    for _, event in ipairs({ "QUEST_REMOVED", "QUEST_TURNED_IN" }) do
        ns.RegisterEvent(self, event, function(_, _, questID)
            local id = tonumber(questID)
            if id and ns.QuestArrow then ns.QuestArrow:ForgetQuest(id) end
        end)
    end
    -- Just before combat locks secure frames: put the buttons where they
    -- belong. After it: catch up on anything that had to wait.
    ns.RegisterEvent(self, "PLAYER_REGEN_DISABLED", function() QuestLogUI:PlaceItems() end)
    ns.RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
        if QuestLogUI.placeAfterCombat then QuestLogUI:PlaceItems() end
        if QuestLogUI.trackerAfterCombat then
            QuestLogUI.trackerAfterCombat = nil
            QuestLogUI:ApplyTracker()
        end
    end)
    ns.RegisterEvent(self, "BAG_UPDATE_COOLDOWN", function() QuestLogUI:OnCooldowns() end)
    ns.RegisterEvent(self, "GLOBAL_MOUSE_DOWN", function() QuestLogUI:OnMouseDown() end)
    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function() QuestLogUI:ApplyTracker() end)
    self:ApplyTracker()
end
