-- Blackthornes Equipment -- UI/MainWindow.lua
-- The gear window. Since 2026-10-22 (a player asked for fewer windows, the
-- owner approved the mockup) it is one window with Where to get upgrades
-- (UI/FinderWindow.lua): what you wear down the left, the upgrades for the
-- slot picked on the right, with what you own first. This module keeps the
-- names the rest of the addon calls (UI:Show, UI:Refresh, the header's
-- buttons) and reads the upgrades you own for that window.

local _, ns = ...
local L = ns.L

local UI = ns.NewModule("UI")

local Compare = ns.Compare
local Weights = ns.Weights

-- The slots in the order the character sheet runs down them.
local SLOTS = {
    { 1, L["Head"] }, { 2, L["Neck"] }, { 3, L["Shoulder"] }, { 15, L["Back"] },
    { 5, L["Chest"] }, { 9, L["Wrist"] }, { 10, L["Hands"] }, { 6, L["Waist"] },
    { 7, L["Legs"] }, { 8, L["Feet"] }, { 11, L["Ring"] }, { 12, L["Ring"] },
    { 13, L["Trinket"] }, { 14, L["Trinket"] }, { 16, L["Main hand"] },
    { 17, L["Off hand"] }, { 18, L["Ranged"] },
}

UI.SLOTS = SLOTS

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

--- The one window is the finder's; its parts are kept here by their old
--- names too.
function UI:Build()
    local FinderUI = ns.FinderUI
    if not FinderUI then return nil end
    local frame = FinderUI:Build()
    self.frame = frame
    self.specLabel, self.footer = FinderUI.specLabel, FinderUI.footer
    self.versionLabel, self.hint = FinderUI.versionLabel, FinderUI.hint
    self.tabStrip = FinderUI.tabStrip
    return frame
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

--- The upgrades you own already, by slot: the best in your bags
--- (Compare.BestInBags), else better gear in your bank or on another of
--- your characters (Alts:BetterElsewhere). Each `{ link, where, result }`,
--- `where` "bags", "bank" or a character's GUID. Keeps what the Training
--- drawer reads (untrained weapons in the bags).
function UI:ReadBags()
    local owned = {}
    local spec = Weights:CurrentSpec()
    local best, elsewhere = {}, {}
    if spec then
        local ok, found = pcall(Compare.BestInBags, Compare)
        if ok and type(found) == "table" then best = found end
        if ns.Alts then
            local okOther, other = pcall(ns.Alts.BetterElsewhere, ns.Alts)
            if okOther and type(other) == "table" then elsewhere = other end
        end
    end

    local upgrades, untrained, keys = 0, {}, {}
    for _, entry in ipairs(SLOTS) do
        local slot = entry[1]
        local pick = best[slot]
        local other = not pick and elsewhere[slot] or nil
        if pick then
            upgrades = upgrades + 1
            owned[slot] = { { link = pick.link, where = "bags", result = pick.result or {} } }
            if pick.result and pick.result.skill then
                untrained[#untrained + 1] = { link = pick.link, skill = pick.result.skill }
                keys[#keys + 1] = pick.link
            end
        elseif other then
            owned[slot] = { { link = other.link, where = other.where, result = other.result or {} } }
        end
    end

    self.upgrades = upgrades
    self.untrained = untrained
    self.untrainedKey = table.concat(keys, ",")
    self:OnTrainingToggled()
    if ns.TrainingDrawer then ns.TrainingDrawer:Refresh() end
    return owned
end

--- Redraw the window.
-- @return how many slots have an upgrade waiting in the bags
function UI:Refresh()
    if not (self.frame and self.frame:IsShown()) then return 0 end
    if ns.FinderUI then ns.FinderUI:Refresh() end
    return self.upgrades or 0
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

--- Refresh once a burst of events settles.
function UI:RefreshSoon()
    if ns.FinderUI then ns.FinderUI:RefreshSoon() end
end

--------------------------------------------------------------------------------
-- Visibility
--------------------------------------------------------------------------------

function UI:Show()
    if not self:Build() then return end
    ns.FinderUI:Show()
end

--- Settings, Dungeon Quests or Dungeon Loot shown in the window's place,
--- from its tab.
local function StandInAsTab()
    local names = ns.FinderUI and ns.FinderUI.STAND_INS or { settings = "SettingsUI" }
    for _, name in pairs(names) do
        local module = ns[name]
        local frame = module and rawget(module, "frame")
        if frame and rawget(module, "asTab") then
            local ok, shown = pcall(frame.IsShown, frame)
            if ok and shown then return module end
        end
    end
    return nil
end

function UI:Hide()
    if ns.FinderUI then ns.FinderUI:Hide() end
    local standIn = StandInAsTab()
    if standIn then standIn:Hide() end
end

function UI:IsShown()
    return (self.frame ~= nil and self.frame:IsShown()) or StandInAsTab() ~= nil
end

function UI:Toggle()
    if self:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

ns.RegisterCommand("window", L["open the gear window (so does /beq on its own)"], function()
    UI:Toggle()
end)
