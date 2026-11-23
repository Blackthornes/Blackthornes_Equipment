-- Blackthornes Equipment -- UI/MainWindow.lua
-- The names the rest of the addon has always called the gear window by
-- (UI:Show, UI:Refresh, UI:Toggle) and the read of the upgrades you own.
-- The window itself is UI/GearWindow.lua (the tab bar and its pages); the
-- old gear list and its windows went in rework step 6 (2026-11-23).

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

--- The upgrades you own already, by slot: the best in your bags
--- (Compare.BestInBags), else better gear in your bank or on another of
--- your characters (Alts:BetterElsewhere). Each `{ link, where, result }`,
--- `where` "bags", "bank" or a character's GUID. Keeps what the Training
--- tab reads (untrained weapons in the bags).
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
    if ns.TrainingTab and ns.TrainingTab.RefreshSoon and self.lastUntrained ~= self.untrainedKey then
        self.lastUntrained = self.untrainedKey
        ns.TrainingTab:RefreshSoon()
    end
    return owned
end

--- Redraw the window.
-- @return how many slots have an upgrade waiting in the bags
function UI:Refresh()
    if ns.GearWindow then ns.GearWindow:Refresh() end
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

--- Refresh once a burst of events settles.
function UI:RefreshSoon()
    if ns.MyGear then ns.MyGear:RefreshSoon() end
    if ns.DungeonsTab then ns.DungeonsTab:RefreshSoon() end
end

--------------------------------------------------------------------------------
-- Visibility
--------------------------------------------------------------------------------

--- Open the Equipment window (UI/GearWindow.lua) on My Gear.
function UI:Show()
    if ns.GearWindow then ns.GearWindow:Open() end
end

function UI:Hide()
    if ns.GearWindow then ns.GearWindow:Close() end
end

function UI:IsShown()
    return ns.GearWindow ~= nil and ns.GearWindow:IsShown()
end

-- The window's key, under Options, Keybindings, AddOns (Bindings.xml).
-- No key is set for the player. It does what /beq on its own does, so
-- with the one window on it opens or closes this addon's tab.
_G.BINDING_HEADER_BLACKTHORNESEQUIPMENT = "Blackthornes Equipment"
_G.BINDING_NAME_BLACKTHORNESEQUIPMENT_TOGGLE = L["Open or close the window"]

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
