-- Blackthornes Equipment -- UI/InspectGear.lua
-- Another Player's Gear (improvement 8, the owner said build it,
-- 2026-11-26, from the mockup). Inspect a player of your class and a
-- window beside the game's inspect window lists what they wear that would
-- be an upgrade for you, where you can get it, and a Track button. Green
-- arrows sit on those slots of the inspect window, the same arrows as on
-- the bags. A line at the foot puts their gear rating beside yours.
--
-- `/beq probe looks` showed how Forever answers: INSPECT_READY brings the
-- item IDs, the full links come a moment later. So the gear is read again
-- a few times, a second apart, until every slot with an item has a link.
-- Only gear your class can wear is judged, and only pieces you can get
-- (Finder:SourcesFor) are listed, so other faction quest gear is left out.
-- Nothing about the other player is saved, sent or shared; the list goes
-- when the inspect window shuts. "Other Players' Gear:" on the Gear page
-- (`otherPlayersGear`, off unless ticked; never rename it).

local _, ns = ...
local L = ns.L

local InspectGear = ns.NewModule("InspectGear")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Motion = ns.Motion

local WIDTH = 330
local HEAD = 64
local ROW = 52
local ICON = 32
local FOOT = 30
local ROWS = 10
-- Reading again for links that have not come yet: this many tries, this
-- far apart.
local TRIES = 6
local WAIT = 1

InspectGear.TRIES, InspectGear.WAIT = TRIES, WAIT

-- The inspect window's slot buttons, by the slot they show.
InspectGear.BUTTONS = {
    [1] = "InspectHeadSlot", [2] = "InspectNeckSlot", [3] = "InspectShoulderSlot", [15] = "InspectBackSlot",
    [5] = "InspectChestSlot", [9] = "InspectWristSlot", [10] = "InspectHandsSlot", [6] = "InspectWaistSlot",
    [7] = "InspectLegsSlot", [8] = "InspectFeetSlot", [11] = "InspectFinger0Slot", [12] = "InspectFinger1Slot",
    [13] = "InspectTrinket0Slot", [14] = "InspectTrinket1Slot", [16] = "InspectMainHandSlot",
    [17] = "InspectSecondaryHandSlot", [18] = "InspectRangedSlot",
}

-- Sheet order, for the list.
InspectGear.SLOTS = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18 }

function InspectGear:IsOn()
    return ns.db ~= nil and ns.db.otherPlayersGear == true
end

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
    return nil
end

local function ItemID(link)
    return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

--------------------------------------------------------------------------------
-- Reading and judging
--------------------------------------------------------------------------------

--- The unit's gear: { [slot] = link }, and how many slots hold an item
--- whose link has not come yet.
function InspectGear.ReadGear(unit)
    local gear, waiting = {}, 0
    for _, slot in ipairs(InspectGear.SLOTS) do
        local link = Call(_G.GetInventoryItemLink, unit, slot)
        if type(link) == "string" then
            gear[slot] = link
        else
            local id = Call(_G.GetInventoryItemID, unit, slot)
            if type(id) == "number" and id > 0 then waiting = waiting + 1 end
        end
    end
    return gear, waiting
end

--- The finder's own pick for an item, when its last scan has one: it
--- carries the sources as the rest of the addon shows them.
local function ScanPick(found, slot, itemID)
    local lists = type(found) == "table" and type(found.all) == "table" and found.all or nil
    if not lists then return nil end
    for _, other in ipairs({ slot, slot == 11 and 12 or slot == 12 and 11 or slot == 13 and 14
        or slot == 14 and 13 or nil }) do
        for _, pick in ipairs(lists[other] or {}) do
            if pick.itemID == itemID then return pick end
        end
    end
end

--- The pieces of `gear` that would be upgrades for you, each
--- { slot, link, itemID, result, sources }, biggest gain first. Only
--- pieces you can wear and can get.
function InspectGear.Upgrades(gear)
    local Compare, Finder = ns.Compare, ns.Finder
    local found = Finder and Finder.latest
    local player = type(found) == "table" and found.player
        or (Finder and Call(Finder.Player, Finder))
    local list, seen = {}, {}
    for _, slot in ipairs(InspectGear.SLOTS) do
        local link = gear[slot]
        local itemID = ItemID(link)
        if itemID and not seen[itemID] then
            seen[itemID] = true
            local result = Call(Compare.Judge, Compare, link)
            if type(result) == "table" and result.verdict == "upgrade" then
                local pick = ScanPick(found, slot, itemID)
                local sources = pick and pick.sources
                if not sources and player then sources = Call(Finder.SourcesFor, Finder, itemID, player) end
                if type(sources) == "table" and #sources > 0 then
                    list[#list + 1] = { slot = slot, link = link, itemID = itemID, result = result,
                        sources = sources, needs = pick and pick.needs, at = pick and pick.at }
                end
            end
        end
    end
    table.sort(list, function(a, b)
        local pa, pb = tonumber(a.result.percent) or 1000, tonumber(b.result.percent) or 1000
        if a.result.empty then pa = 1000 end
        if b.result.empty then pb = 1000 end
        if pa ~= pb then return pa > pb end
        return a.slot < b.slot
    end)
    return list
end

--- Their gear rating, worked out the way yours is (UpgradeQuest:GearRating):
--- each slot's score against the best you know of for it, your own or an
--- upgrade on offer. nil when your weights can't score their gear.
function InspectGear.TheirRating(gear)
    local Compare, quest = ns.Compare, ns.UpgradeQuest
    if not (Compare and quest and quest.RATINGS) then return nil end
    local weights = ns.Weights and Call(ns.Weights.ForPlayer, ns.Weights)
    if type(weights) ~= "table" then return nil end
    local found = ns.Finder and ns.Finder.latest
    local sum, slots, scored = 0, 0, 0
    for slot = 1, 18 do
        if slot ~= 4 then
            slots = slots + 1
            local theirs = gear[slot] and tonumber((Call(Compare.ScoreOf, Compare, gear[slot], weights))) or 0
            if theirs > 0 then scored = scored + 1 end
            local mine = tonumber((Call(Compare.ScoreOf, Compare, Call(_G.GetInventoryItemLink, "player", slot), weights))) or 0
            local best = mine
            local top = type(found) == "table" and type(found.all) == "table" and found.all[slot]
            local pick = top and top[1]
            if pick and pick.result and tonumber(pick.result.percent) and mine > 0 then
                best = math.max(best, mine * (1 + pick.result.percent / 100))
            end
            best = math.max(best, theirs)
            sum = sum + (best > 0 and theirs / best or 1)
        end
    end
    if scored == 0 then return nil end
    local value = sum / math.max(slots, 1)
    for _, rating in ipairs(quest.RATINGS) do
        if not rating.below or value < rating.below then return rating end
    end
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

local function Light(row, p)
    row.background:SetColorTexture(Motion.Mix(row.restKey, "glassHover", p))
    row.edge:SetColorTexture(Theme.Unpack("accentHi", p))
end

function InspectGear:BuildRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW)
    row.restKey = index % 2 == 0 and "glassAlt" or "glass"
    row.background = Theme.Fill(row, row.restKey)
    local line = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetHeight(1)
    line:SetColorTexture(Theme.Unpack("border", 0.6))
    local edge = row:CreateTexture(nil, "ARTWORK")
    edge:SetPoint("TOPLEFT")
    edge:SetPoint("BOTTOMLEFT")
    edge:SetWidth(2)
    edge:SetColorTexture(Theme.Unpack("accentHi", 0))
    row.edge = edge

    local icon = Theme.CreateItemIcon(row, ICON)
    icon:SetPoint("LEFT", 10, 0)
    row.icon = icon
    local name = Theme.CreateLabel(row, "normal", "text")
    name:SetPoint("TOPLEFT", ICON + 18, -8)
    name:SetPoint("RIGHT", row, "RIGHT", -78, 0)
    name:SetWordWrap(true)
    row.name = name
    local under = Theme.CreateLabel(row, "tiny", "muted")
    under:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
    under:SetPoint("RIGHT", row, "RIGHT", -78, 0)
    under:SetWordWrap(true)
    row.under = under
    local gain = Theme.CreateLabel(row, "normal", "good", "RIGHT")
    gain:SetPoint("TOPRIGHT", -10, -8)
    row.gain = gain
    local track = Widgets.CreateButton(row, L["Track"], function()
        local piece = rawget(row, "piece")
        if piece and ns.FinderUI then ns.FinderUI:Follow(piece) end
    end, { width = math.max(60, Theme.TextWidth("normal", L["Track"]) + 20), height = 20 })
    track:SetPoint("BOTTOMRIGHT", -10, 6)
    row.track = track

    row:SetScript("OnEnter", function(self)
        Motion:Blend(self, "hover", 1, 0.12, function(p) Light(self, p) end)
        local piece = rawget(self, "piece")
        if piece then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            pcall(GameTooltip.SetHyperlink, GameTooltip, piece.link)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        Motion:Blend(self, "hover", 0, 0.18, function(p) Light(self, p) end)
        GameTooltip:Hide()
    end)
    -- Shift-click links it, Ctrl-click tries it on, as every item row does.
    row:SetScript("OnClick", function(self)
        local piece = rawget(self, "piece")
        if piece then Widgets.ItemClick(nil, piece.link) end
    end)
    row:Hide()
    return row
end

function InspectGear:Build()
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame", "BlackthornesEquipmentInspectGear", UIParent)
    frame:SetSize(WIDTH, HEAD + FOOT + ROW)
    frame:SetFrameStrata("HIGH")
    pcall(frame.SetClampedToScreen, frame, true)
    pcall(frame.EnableMouse, frame, true)
    Theme.Fill(frame, "window")
    if ns.Titanforged and ns.Titanforged.Dress then
        pcall(ns.Titanforged.Dress, ns.Titanforged, frame, { close = function() frame:Hide() end })
    else
        Theme.Border(frame, "borderLit")
    end
    frame:Hide()
    self.frame = frame

    local title = Theme.CreateLabel(frame, "large", "accent")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetPoint("RIGHT", frame, "RIGHT", -40, 0)
    title:SetWordWrap(true)
    self.title = title
    local heading = Theme.CreateLabel(frame, "tiny", "gilt")
    heading:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    heading:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
    heading:SetWordWrap(true)
    self.heading = heading

    self.rows = {}
    for index = 1, ROWS do
        local row = self:BuildRow(frame, index)
        row:SetPoint("TOPLEFT", 2, -(HEAD + (index - 1) * ROW))
        row:SetPoint("TOPRIGHT", -2, -(HEAD + (index - 1) * ROW))
        self.rows[index] = row
    end

    local foot = Theme.CreateLabel(frame, "small", "muted")
    foot:SetPoint("BOTTOMLEFT", 16, 10)
    foot:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
    foot:SetWordWrap(true)
    self.foot = foot
    return frame
end

--- How much better, short: "+12%", "empty slot" or "better".
function InspectGear.Gain(result)
    if result.empty then return L["empty slot"] end
    if result.percent then return ("%+d%%"):format(math.floor(result.percent + 0.5)) end
    return L["better"]
end

--- Draw the window from the pieces found.
function InspectGear:Paint(name, list, theirs)
    local frame = self:Build()
    self.title:SetText(L.Format("%s wears", name or ""))
    local count = #list
    local heading = count == 1 and L["1 piece would be an upgrade for you"]
        or L.Format("%d pieces would be upgrades for you", count)
    self.heading:SetText(heading:upper())
    local FinderUI = ns.FinderUI
    for index, row in ipairs(self.rows) do
        local piece = list[index]
        row.piece = piece or false
        if piece then
            Theme.SetItemIcon(row.icon, piece.link)
            row.name:SetText(ns.Items.ShowLink(piece.link))
            row.under:SetText(FinderUI and FinderUI.SourceLine(piece.sources[1]) or "")
            row.gain:SetText(InspectGear.Gain(piece.result))
            row:Show()
        else
            row:Hide()
        end
    end
    local yours = ns.UpgradeQuest and Call(ns.UpgradeQuest.GearRating, ns.UpgradeQuest)
    local mine = yours and yours.rating and yours.rating.label
    if theirs and mine then
        self.foot:SetText(L.Format("Their gear rating: %s. Yours: %s.", theirs.label, mine))
    else
        self.foot:SetText("")
    end
    local shown = math.min(count, ROWS)
    frame:SetHeight(HEAD + math.max(shown, 0) * ROW + FOOT + 6)
    self:Place()
    frame:Show()
end

--- Beside the game's inspect window, the way My Gear stands beside the
--- character sheet.
function InspectGear:Place()
    local inspect = rawget(_G, "InspectFrame")
    local frame = self.frame
    if not (frame and inspect) then return end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", inspect, "TOPRIGHT", 14, 0)
end

--- The green arrows on the inspect window's slots: on for each slot in
--- `marked`, off for the rest.
function InspectGear:Mark(marked)
    local icons = ns.BagIcons
    if not icons then return end
    for slot, name in pairs(self.BUTTONS) do
        local button = rawget(_G, name)
        if type(button) == "table" then
            local show = marked[slot] == true
            local arrow = show and icons:Arrow(button) or icons:ExistingArrow(button)
            if arrow then arrow:SetShown(show) end
        end
    end
end

--- Take it all down: the window, the arrows and what was read.
function InspectGear:Close()
    self.unit, self.guid, self.tries = nil, nil, 0
    if self.frame then self.frame:Hide() end
    self:Mark({})
end

--------------------------------------------------------------------------------
-- Looking
--------------------------------------------------------------------------------

--- The player the inspect window shows, when they are a player of your
--- class: unit, guid, name. nil otherwise.
function InspectGear.Who()
    local inspect = rawget(_G, "InspectFrame")
    local unit = type(inspect) == "table" and rawget(inspect, "unit") or "target"
    if type(unit) ~= "string" then return nil end
    if Call(_G.UnitIsPlayer, unit) ~= true then return nil end
    local _, mine = Call(_G.UnitClass, "player")
    local _, theirs = Call(_G.UnitClass, unit)
    if type(mine) ~= "string" or mine ~= theirs then return nil end
    local guid = Call(_G.UnitGUID, unit)
    local name = Call(_G.GetUnitName, unit, true) or Call(_G.UnitName, unit)
    return unit, guid, type(name) == "string" and name or ""
end

--- The inspect window opened, or the server answered: read their gear,
--- and read again a second later while links are still coming.
function InspectGear:Look()
    if not self:IsOn() then return self:Close() end
    local unit, guid, name = InspectGear.Who()
    if not unit then return self:Close() end
    if guid ~= self.guid then self.tries = 0 end
    self.unit, self.guid, self.name = unit, guid, name
    local gear, waiting = InspectGear.ReadGear(unit)
    -- No links yet: wait for them rather than show an empty list.
    if not next(gear) then
        self.tries = (self.tries or 0) + 1
        if waiting > 0 and self.tries < TRIES then self:LookSoon() end
        return
    end
    local list = InspectGear.Upgrades(gear)
    local marked = {}
    for _, piece in ipairs(list) do marked[piece.slot] = true end
    self:Mark(marked)
    self:Paint(name, list, InspectGear.TheirRating(gear))
    self.tries = (self.tries or 0) + 1
    if waiting > 0 and self.tries < TRIES then self:LookSoon() end
end

function InspectGear:LookSoon()
    if self.pending then return end
    local after = _G.C_Timer and _G.C_Timer.After
    if type(after) ~= "function" then return end
    self.pending = true
    after(WAIT, function()
        InspectGear.pending = false
        if InspectGear.unit then pcall(InspectGear.Look, InspectGear) end
    end)
end

--- The game's inspect window is made when first used; hook it then.
function InspectGear:Hook()
    local inspect = rawget(_G, "InspectFrame")
    if self.hooked or type(inspect) ~= "table" or type(inspect.HookScript) ~= "function" then return end
    self.hooked = true
    inspect:HookScript("OnShow", function() pcall(InspectGear.Look, InspectGear) end)
    inspect:HookScript("OnHide", function() pcall(InspectGear.Close, InspectGear) end)
end

--- "Other Players' Gear:" ticked or unticked.
function InspectGear:Changed()
    local inspect = rawget(_G, "InspectFrame")
    local ok, shown = pcall(function() return inspect and inspect:IsShown() end)
    if self:IsOn() and ok and shown then self:Look() else self:Close() end
end

function InspectGear:OnEnable()
    self:Hook()
    ns.RegisterEvent(self, "ADDON_LOADED", function(_, _, name)
        if name == "Blizzard_InspectUI" then InspectGear:Hook() end
    end)
    ns.RegisterEvent(self, "INSPECT_READY", function(_, _, guid)
        if not InspectGear:IsOn() then return end
        local inspect = rawget(_G, "InspectFrame")
        local ok, shown = pcall(function() return inspect and inspect:IsShown() end)
        if ok and shown and (guid == nil or InspectGear.guid == nil or guid == InspectGear.guid) then
            pcall(InspectGear.Look, InspectGear)
        end
    end)
end
