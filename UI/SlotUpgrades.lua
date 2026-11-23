-- Blackthornes Equipment -- UI/SlotUpgrades.lua
-- Upgrades on the character sheet: a green arrow on every gear slot with
-- something better (the same arrow as the bags); hover a slot and its
-- tooltip lists the best upgrades on offer for it and where they come
-- from; Alt-click a slot and My Gear opens on it, beside the sheet
-- (rework step 7; the small floating panel is gone).
--
-- The picks are the upgrade finder's (Finder:Latest, scanned again only
-- when the gear, level or bags change), so the sheet, My Gear and the bag
-- arrows always agree. A ring or trinket slot's tooltip shows the picks
-- for both of the pair. Only the slot buttons' scripts are hooked, after
-- the game's own, so nothing the game does with a slot (equipping, using a
-- trinket) changes. Nothing here runs while the sheet is shut. Switched
-- off with the "Character Sheet:" setting (`slotUpgrades`).

local _, ns = ...
local L = ns.L

local SlotUpgrades = ns.NewModule("SlotUpgrades")

local Theme = ns.Theme

local SLOT_BUTTONS = {
    "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot", "CharacterBackSlot",
    "CharacterChestSlot", "CharacterWristSlot", "CharacterHandsSlot", "CharacterWaistSlot",
    "CharacterLegsSlot", "CharacterFeetSlot", "CharacterFinger0Slot", "CharacterFinger1Slot",
    "CharacterTrinket0Slot", "CharacterTrinket1Slot", "CharacterMainHandSlot",
    "CharacterSecondaryHandSlot", "CharacterRangedSlot",
}

-- Rings and trinkets are a pair: either slot shows the picks for both.
local PAIRS = { [11] = { 11, 12 }, [12] = { 11, 12 }, [13] = { 13, 14 }, [14] = { 13, 14 } }

local SLOT_NAMES = {
    [1] = L["Head"], [2] = L["Neck"], [3] = L["Shoulder"], [5] = L["Chest"], [6] = L["Waist"], [7] = L["Legs"],
    [8] = L["Feet"], [9] = L["Wrist"], [10] = L["Hands"], [11] = L["Rings"], [12] = L["Rings"], [13] = L["Trinkets"],
    [14] = L["Trinkets"], [15] = L["Back"], [16] = L["Main hand"], [17] = L["Off hand"], [18] = L["Ranged"],
}

local SHOWN = 3

function SlotUpgrades:IsEnabled()
    return not (ns.db and ns.db.slotUpgrades == false)
end

local function Colored(key, text)
    local r, g, b = Theme.Unpack(key)
    return ("|cff%02x%02x%02x%s|r"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
        math.floor(b * 255 + 0.5), text)
end

--- How much better, short: "+12%", "empty slot", "better", with the level
--- it waits on when planning ahead.
function SlotUpgrades.Gain(pick)
    local result = pick.result or {}
    local text = L["better"]
    if result.empty then
        text = L["empty slot"]
    elseif result.percent then
        text = ("%+d%%"):format(math.floor(result.percent + 0.5))
    end
    if SlotUpgrades.Train(pick) then text = L.Format("Train: %s", text) end
    return text
end

--- Does a pick need a weapon skill not learned yet? Then its gain is red.
function SlotUpgrades.Train(pick)
    return ns.WeaponSkills ~= nil and ns.WeaponSkills:NeedsTraining(pick.link)
end

--- The colour key for a pick's gain.
function SlotUpgrades.GainKey(pick)
    if SlotUpgrades.Train(pick) then return "loss" end
    return (pick.needs or pick.remote) and "warn" or "good"
end

--- The best picks for an inventory slot (both of a pair), best first, as
--- the Equipment window's filters leave them (FinderUI:SourceFilter): each
--- pick shown is a copy carrying only the sources that pass. The second
--- answer is how many upgrades the filters hide.
function SlotUpgrades:PicksFor(slot)
    local found = ns.Finder and ns.Finder:Latest()
    if not found then return {}, 0 end
    local all = type(found.all) == "table" and found.all or found.slots or {}
    local Passing = ns.FinderUI and ns.FinderUI.SourceFilter and ns.FinderUI:SourceFilter(found)
    local picks, seen, hidden = {}, {}, 0
    for _, each in ipairs(PAIRS[slot] or { slot }) do
        for _, pick in ipairs(all[each] or {}) do
            if not seen[pick.itemID] then
                seen[pick.itemID] = true
                local sources = Passing and Passing(pick) or pick.sources
                if sources and #sources > 0 then
                    local copy = {}
                    for key, value in pairs(pick) do copy[key] = value end
                    copy.sources = sources
                    picks[#picks + 1] = copy
                else
                    hidden = hidden + 1
                end
            end
        end
    end
    table.sort(picks, ns.Finder.Order)
    for i = #picks, SHOWN + 1, -1 do picks[i] = nil end
    return picks, hidden
end

--------------------------------------------------------------------------------
-- The slot's tooltip
--------------------------------------------------------------------------------

local function LineCount(tooltip)
    local ok, count = pcall(tooltip.NumLines, tooltip)
    return ok and tonumber(count) or 0
end

--- Add the slot's upgrades to its tooltip. `picks` are the ones worked out
--- when the slot was hovered; the game redraws a slot's tooltip several
--- times a second, and the same lines go back on each time.
function SlotUpgrades:AddLines(tooltip, slot, picks, hidden)
    if not self:IsEnabled() or not SLOT_NAMES[slot] then return end
    if not picks then
        local ok, found, held = pcall(self.PicksFor, self, slot)
        if not ok then return end
        picks, hidden = found, held
    end
    hidden = tonumber(hidden) or 0

    tooltip:AddLine(" ")
    if #picks == 0 then
        local latest = ns.Finder and ns.Finder.latest
        if not latest and ns.Finder and ns.Finder:Scanning() then
            tooltip:AddLine(L["Looking for upgrades. Hover again in a moment"], Theme.Unpack("muted"))
        elseif latest and (latest.waiting or 0) > 0 then
            tooltip:AddLine(L["Still loading gear. Hover again in a moment"],
                Theme.Unpack("muted"))
        else
            tooltip:AddLine(L["Nothing on offer beats this yet"], Theme.Unpack("muted"))
            if hidden > 0 then
                tooltip:AddLine(SlotUpgrades.HiddenText(hidden), Theme.Unpack("dim"))
            end
        end
    else
        tooltip:AddLine(L["Upgrades on offer"], Theme.Unpack("accent"))
        for _, pick in ipairs(picks) do
            local gainKey = SlotUpgrades.GainKey(pick)
            if type(tooltip.AddDoubleLine) == "function" then
                local r, g, b = Theme.Unpack(gainKey)
                tooltip:AddDoubleLine(pick.link, SlotUpgrades.Gain(pick), 1, 1, 1, r, g, b)
            else
                tooltip:AddLine(ns.Items.ShowLink(pick.link) .. "  " .. Colored(gainKey, SlotUpgrades.Gain(pick)))
            end
            local source = pick.sources and pick.sources[1]
            if source and ns.FinderUI then
                tooltip:AddLine("    " .. ns.FinderUI.SourceLine(source), Theme.Unpack("muted"))
            end
        end
    end
    tooltip:AddLine(L["Alt-click to see this slot in My Gear"], Theme.Unpack("dim"))
    pcall(tooltip.Show, tooltip)
end

--- "Your filters hide 3 more.": the window's own words.
function SlotUpgrades.HiddenText(hidden)
    if hidden == 1 then return L["Your filters hide 1 more."] end
    return L.Format("Your filters hide %d more.", hidden)
end

--- A slot was hovered: work out its upgrades once and put them on.
function SlotUpgrades:OnSlotEnter(tooltip, button, slot)
    local ok, picks, hidden = pcall(self.PicksFor, self, slot)
    self.tip = { tooltip = tooltip, owner = button, slot = slot,
        picks = ok and picks or {}, hidden = ok and hidden or 0 }
    self:AddLines(tooltip, slot, self.tip.picks, self.tip.hidden)
    self.tip.lines = LineCount(tooltip)
end

--- Every frame the tooltip shows: when the game has redrawn the slot's
--- tooltip (which wipes added lines), put the upgrades back on.
function SlotUpgrades:Keep(tooltip)
    local tip = self.tip
    if not tip or tip.tooltip ~= tooltip or self.keeping then return end
    local okOwner, owner = pcall(tooltip.GetOwner, tooltip)
    local okShown, shown = pcall(tooltip.IsShown, tooltip)
    if not (okOwner and owner == tip.owner and okShown and shown) then
        self.tip = nil
        return
    end
    if LineCount(tooltip) >= (tip.lines or 0) then return end
    self.keeping = true
    pcall(self.AddLines, self, tooltip, tip.slot, tip.picks, tip.hidden)
    self.keeping = false
    tip.lines = LineCount(tooltip)
end

--------------------------------------------------------------------------------
-- The arrows on the slots
--------------------------------------------------------------------------------

--- Is the character sheet on screen? Only read, never shown or hidden.
function SlotUpgrades.SheetShown()
    local frame = rawget(_G, "CharacterFrame")
    if type(frame) ~= "table" or type(frame.IsVisible) ~= "function" then return false end
    local ok, shown = pcall(frame.IsVisible, frame)
    return ok and shown == true
end

--- Put the green arrow on every slot the scan has something better for,
--- and take it off the rest. The slots are the ones My Gear's figure marks
--- green (MyGear:GreenSlots), so the two always agree. Judges nothing new:
--- the scan and the bag pieces are the ones already kept.
function SlotUpgrades:Paint(found)
    local icons = ns.BagIcons
    if not icons then return 0 end
    local green = {}
    if self:IsEnabled() and found and ns.MyGear and ns.MyGear.GreenSlots then
        local ok, slots = pcall(ns.MyGear.GreenSlots, ns.MyGear, found)
        if ok and type(slots) == "table" then green = slots end
    end
    local count = 0
    for _, name in ipairs(SLOT_BUTTONS) do
        local button = rawget(_G, name)
        if type(button) == "table" then
            local ok, id = pcall(button.GetID, button)
            local show = ok and green[tonumber(id)] == true
            local arrow = show and icons:Arrow(button) or icons:ExistingArrow(button)
            if arrow then arrow:SetShown(show) end
            if show then count = count + 1 end
        end
    end
    return count
end

--- Look and mark, while the sheet shows: the finder's scan when it is up
--- to date, else the last one stays on show while a new one is made a
--- slice per frame.
function SlotUpgrades:Mark()
    if not SlotUpgrades.SheetShown() then return end
    local Finder = ns.Finder
    if not Finder then return end
    if not self:IsEnabled() then return self:Paint(nil) end
    local found = Finder:Fresh()
    if found then return self:Paint(found) end
    if Finder.latest then self:Paint(Finder.latest) end
    Finder:ScanInBackground(function(scan)
        if SlotUpgrades.SheetShown() then SlotUpgrades:Paint(scan) end
    end)
end

--- Once for a burst of events, and only while the sheet shows.
function SlotUpgrades:MarkSoon()
    if self.pending or not SlotUpgrades.SheetShown() then return end
    local after = _G.C_Timer and _G.C_Timer.After
    if type(after) ~= "function" then return self:Mark() end
    self.pending = true
    after(0.5, function()
        SlotUpgrades.pending = false
        pcall(SlotUpgrades.Mark, SlotUpgrades)
    end)
end

--- The "Character Sheet:" box was ticked or cleared.
function SlotUpgrades:OnTrackingChanged()
    self:Mark()
end

--- Alt-click a slot: My Gear opens on it, beside the sheet.
function SlotUpgrades:Open(slot, sheet)
    local window = ns.GearWindow
    if window and window.OpenBeside then window:OpenBeside(slot, sheet) end
end

--------------------------------------------------------------------------------
-- Hooks
--------------------------------------------------------------------------------

local function SlotOf(button)
    local ok, id = pcall(button.GetID, button)
    return ok and tonumber(id) or nil
end

local function AltDown()
    local ok, down = pcall(function() return IsAltKeyDown() == true end)
    return ok and down
end

function SlotUpgrades:Hook()
    self.hooked = self.hooked or {}
    for _, name in ipairs(SLOT_BUTTONS) do
        local button = _G[name]
        if type(button) == "table" and not self.hooked[button] and type(button.HookScript) == "function" then
            self.hooked[button] = true
            button:HookScript("OnEnter", function(slotButton)
                local slot = SlotOf(slotButton)
                if slot and GameTooltip and GameTooltip:IsShown() then
                    pcall(SlotUpgrades.OnSlotEnter, SlotUpgrades, GameTooltip, slotButton, slot)
                end
            end)
            button:HookScript("OnClick", function(slotButton)
                if not (SlotUpgrades:IsEnabled() and AltDown()) then return end
                local slot = SlotOf(slotButton)
                if slot then pcall(SlotUpgrades.Open, SlotUpgrades, slot) end
            end)
        end
    end
end

function SlotUpgrades:OnEnable()
    self:Hook()
    local tooltip = _G.GameTooltip
    if type(tooltip) == "table" and type(tooltip.HookScript) == "function" then
        pcall(tooltip.HookScript, tooltip, "OnUpdate", function(shown) SlotUpgrades:Keep(shown) end)
    end
    -- The character sheet may be made later on some clients.
    local frame = _G.CharacterFrame
    if type(frame) == "table" and type(frame.HookScript) == "function" then
        frame:HookScript("OnShow", function()
            SlotUpgrades:Hook()
            pcall(SlotUpgrades.Mark, SlotUpgrades)
        end)
    end
    -- Gear worn, gear in the bags or a level changes what is better. A
    -- stack growing or shrinking changes no upgrade. Nothing runs while
    -- the sheet is shut.
    for _, event in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP", "TRAIT_CONFIG_UPDATED" }) do
        ns.RegisterEvent(self, event, function() SlotUpgrades:MarkSoon() end)
    end
    ns.RegisterEvent(self, "BAG_UPDATE_DELAYED", function()
        if not SlotUpgrades.SheetShown() then return end
        local Finder = ns.Finder
        if not Finder or type(Finder.CarriedMoved) ~= "function" or Finder:CarriedMoved("sheet") then
            SlotUpgrades:MarkSoon()
        end
    end)
end
