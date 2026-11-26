-- Blackthornes Equipment -- UI/MyGear.lua
-- My Gear, the page the Equipment window opens on (UI/GearWindow.lua;
-- rework step 2, the owner approved the mockup, 2026-11-22).
--
-- Along the top, up to three cards say what to do next: put on what is in
-- your bags, go and get the best piece, visit the trainer. A card with
-- nothing to do is left out. Under them the character's slots are laid out
-- as on the game's character sheet, each with what is worn and a green
-- arrow where something better waits (amber for later: a level, a
-- reputation, a crafter still to find). A ring between them shows the gear
-- rating. Click a slot and the right side shows it: what you own that
-- beats it, the best enchant for it, and the top three pieces to go and
-- get. List swaps the figure for rows that sort.
--
-- Nothing here judges gear. It reads the finder's shared scan
-- (Finder:Fresh, else Finder:ScanInBackground, a slice per frame), the
-- bags as the old gear window read them (UI:ReadBags), the kept enchant
-- plans (Enchants:Line) and the kept training plan. A click on a slot or a
-- heading only draws again from what was read. Nothing runs while the
-- page is hidden, and bursts of events fold into one look.

local _, ns = ...
local L = ns.L

local MyGear = ns.NewModule("MyGear")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Motion = ns.Motion
local Finder = ns.Finder
local Weights = ns.Weights

local PAD = 18
-- The room the page is laid out in; a wider window gives the rest to the
-- slot's side.
local WIDTH = 1040

local CARDS_TOP = 10
local CARD_HEIGHT = 60
local CARD_GAP = 10
local CARD_WIDTH = math.floor((WIDTH - PAD * 2 - CARD_GAP * 2) / 3)

local FOOTER = 30
-- Switch Gear's row above the cards (Logic/SwitchGear.lua), only while an
-- Off Spec is picked.
local SWITCH = 34
-- The figure's side, and the gap before the slot's side.
local LEFT = 566
local GAP = 12
local VIEW_ROW = 28

-- One slot on the figure.
local SLOT_WIDTH = 190
local SLOT_HEIGHT = 50
local ICON = 38
-- The ring of dots in the middle.
local RING = 54
local DOTS = 48

-- One line of the list view, and its columns.
local LIST_HEAD = 22
local LIST_ROW = 24
local LIST_SLOT = 96
local LIST_WORN = 220

-- The slot's side: its head, then rows that grow to fit.
local HEAD = 56
local ROW_MIN = 40
local ROW_ICON = 28
local ROW_TEXT = ROW_ICON + 20
local GAIN_WIDTH = 96
local HEADING_ROW = 24
local ROWS = 12
-- How many pieces to go and get a slot shows; See All has the rest.
local TOP = 3

MyGear.TOP = TOP

local MAIN_HAND, OFF_HAND = 16, 17

-- The figure: seven down the left, seven down the right, three along the
-- foot, as the game's character sheet has them.
local LEFT_SLOTS = { 1, 2, 3, 15, 5, 9, 10 }
local RIGHT_SLOTS = { 6, 7, 8, 11, 12, 13, 14 }
local FOOT_SLOTS = { 16, 17, 18 }

--- Every slot in sheet order, { slot, name } (UI/MainWindow.lua).
local function Slots()
    return ns.UI and ns.UI.SLOTS or {}
end

local function Colored(key, text)
    local r, g, b = Theme.Unpack(key)
    return ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, text)
end

local function Shown(frame)
    if not frame then return false end
    local ok, shown = pcall(frame.IsShown, frame)
    return ok and shown == true
end

--- How tall a label's text runs at its width: the client's answer, else a
--- measure of its words.
local function TextHeight(label, size, width)
    local text = label:GetText() or ""
    if text == "" then return 0 end
    local ok, height = pcall(label.GetStringHeight, label)
    if ok and type(height) == "number" and height > 0 then return height end
    local lines = math.max(1, math.ceil(Theme.TextWidth(size, text) / math.max(1, width)))
    return lines * ((Theme.sizes[size] or 10) + 2)
end

--- Does a piece wait on something (a level, a reputation, a crafter)? Then
--- it shows in amber, as in the old list.
function MyGear.Later(pick)
    return (pick.needs or pick.at or pick.remote or ns.Crafting.WearWaits(pick)) and true or false
end

--- The gain a slot's badge shows: "+14%", or "+" for an empty slot.
function MyGear.Badge(result)
    if type(result) ~= "table" then return "" end
    local shown = Finder.Shown(result)
    if shown then return ("%+d%%"):format(shown) end
    return "+"
end

--- The gain a row shows, as the old list words it.
local function Gain(result)
    result = result or {}
    if result.empty then return L["empty slot"] end
    if result.percent then return ("%+d%%"):format(math.floor(result.percent + 0.5)) end
    return L["better"]
end

--------------------------------------------------------------------------------
-- Reading
--------------------------------------------------------------------------------

--- Lay out what the page shows from a finder scan (nil before the first):
--- per slot what is worn, what you own that beats it, the best enchant and
--- the pieces to go and get, then the cards. Read once a look; every draw
--- after reads this.
--- The better pieces in the bags by slot, judged once for each scan: gear
--- coming or going makes a new scan, so asking again judges nothing. The
--- character sheet's arrows read it too (UI/SlotUpgrades.lua).
function MyGear:Owned(found)
    local owned = found and self.bagsFor == found and self.bags or nil
    if owned then return owned end
    owned = {}
    if ns.UI and ns.UI.ReadBags then
        local ok, read = pcall(ns.UI.ReadBags, ns.UI)
        if ok and type(read) == "table" then owned = read end
    end
    self.bagsFor, self.bags = found, owned
    return owned
end

--- The test Find Upgrades' filters make (its From boxes, Only What I Can
--- Get Now and This Zone Only), so My Gear and the character sheet show
--- what that list shows. Nil when FinderShared is not loaded.
function MyGear.Filter(found)
    local FinderUI = ns.FinderUI
    if not (FinderUI and FinderUI.SourceFilter) then return nil end
    return FinderUI:SourceFilter(found)
end

--- A pick with only the sources the filters let through, or nil when none
--- pass. A copy: the scan's own pick is left whole for the other pages.
local function Passing(pick, pass)
    if not pass then return pick end
    local sources = pass(pick)
    if #sources == 0 then return nil end
    if #sources == #(pick.sources or {}) then return pick end
    local copy = {}
    for key, value in pairs(pick) do copy[key] = value end
    copy.sources = sources
    return copy
end

--- A slot's pieces to go and get, from a scan: those to wear now, then
--- those for later, each best first and at most TOP. Only those Find
--- Upgrades' filters let through (`pass`, from MyGear.Filter).
function MyGear.Picks(found, slot, skipped, pass)
    local now, later = {}, {}
    for _, whole in ipairs(found and found.all and found.all[slot] or {}) do
        local pick = not (skipped and skipped[whole.itemID]) and Passing(whole, pass) or nil
        if pick then
            if MyGear.Later(pick) then
                if #later < TOP then later[#later + 1] = pick end
            else
                if #now < TOP then now[#now + 1] = pick end
            end
            if #now >= TOP then break end
        end
    end
    return now, later
end

--- A slot's mark: what you own comes first, then the best to get now
--- (both green), then the best for later (amber).
function MyGear.Mark(mine, now, later)
    if mine then return mine.result, "good" end
    if now then return now.result, "good" end
    if later then return later.result, "warn" end
    return nil, nil
end

--- The slots with a green mark, { [slot] = true }, for the character
--- sheet's arrows: the same answer the figure shows.
function MyGear:GreenSlots(found)
    local quest = ns.UpgradeQuest
    local skipped = quest and quest:Skipped() or {}
    local owned = self:Owned(found)
    local pass = MyGear.Filter(found)
    local green = {}
    for _, entry in ipairs(Slots()) do
        local slot = entry[1]
        local now, later = MyGear.Picks(found, slot, skipped, pass)
        local _, tone = MyGear.Mark((owned[slot] or {})[1], now[1], later[1])
        if tone == "good" then green[slot] = true end
    end
    return green
end

function MyGear:Read(found, off)
    local Items, FinderUI = ns.Items, ns.FinderUI
    local quest = ns.UpgradeQuest
    local skipped = quest and quest:Skipped() or {}
    -- The bags are judged once for each scan: gear coming or going makes
    -- a new scan, so opening the page again judges nothing.
    local owned = self:Owned(found)
    local pass = MyGear.Filter(found)

    local state = { slots = {}, ready = {}, upgrades = 0, enchants = 0, found = found }
    local readySeen = {}
    local bestShown
    for _, entry in ipairs(Slots()) do
        local slot = entry[1]
        local info = { slot = slot, name = entry[2], link = Items and Items:Equipped(slot) or nil,
            owned = owned[slot] or {}, picks = {} }

        -- The pieces to go and get: those you can wear now first, then
        -- those for later, each best first as the finder sorted them.
        local now, later = MyGear.Picks(found, slot, skipped, pass)
        for _, pick in ipairs(now) do info.picks[#info.picks + 1] = pick end
        for _, pick in ipairs(later) do
            if #info.picks < TOP then info.picks[#info.picks + 1] = pick end
        end
        info.now, info.later = now[1], later[1]

        -- The slot's mark: what you own comes first, then the best to get.
        info.mark, info.tone = MyGear.Mark(info.owned[1], info.now, info.later)
        if info.tone == "good" then state.upgrades = state.upgrades + 1 end
        -- Nothing for the Main Spec, but something to wear now for the Off
        -- Spec (Logic/OffSpec.lua): the blue mark.
        if off then
            local offNow = MyGear.Picks(off, slot, skipped, pass)
            info.offPicks = offNow
            if not info.mark and offNow[1] then
                info.mark, info.tone, info.offNow = offNow[1].result, "offSpec", offNow[1]
            end
        end

        for _, piece in ipairs(info.owned) do
            if FinderUI and FinderUI.CanPutOn(piece) and not readySeen[piece.link] then
                readySeen[piece.link] = true
                state.ready[#state.ready + 1] = piece.link
            end
        end

        if ns.Enchants then
            local ok, line = pcall(ns.Enchants.Line, ns.Enchants, slot)
            if ok and type(line) == "table" then
                info.enchant = line
                state.enchants = state.enchants + 1
            end
        end

        -- The best piece to go and get, of every slot: the second card.
        local pick = info.now
        if pick and not pick.mainToo and quest and quest.CanFollow(pick) then
            local shown = Finder.Shown(pick.result) or 1000
            if not bestShown or shown > bestShown then
                bestShown, state.next = shown, pick
            end
        end

        state.slots[slot] = info
    end

    -- An empty off hand under a two-hander is no gap.
    local off, main = state.slots[OFF_HAND], state.slots[MAIN_HAND]
    if off and not off.link and main and main.link and Items then
        local info = Items:Info(main.link)
        if info and info.equipLoc == "INVTYPE_2HWEAPON" then off.held = true end
    end

    local training = ns.ClassTraining
    if training and training:IsOn() then
        local ok, plan = pcall(training.Plan, training)
        if ok and type(plan) == "table" and #plan.ready > 0 then
            state.training = { count = #plan.ready,
                cost = training.CostText(plan.cost or 0, plan.unknown or 0, #plan.ready) }
        end
    end

    if quest and quest.GearRating then
        local ok, rating = pcall(quest.GearRating, quest)
        if ok and type(rating) == "table" then state.rating = rating end
    end
    return state
end

--- The slot to show: the one clicked, else the first with something
--- better, else the first.
function MyGear:ChooseSlot(state)
    -- Asked for from the character sheet: that slot, once.
    local asked = self.asked
    self.asked = nil
    if asked and state.slots[asked] then return asked end
    if self.slot and state.slots[self.slot] then return self.slot end
    for _, entry in ipairs(Slots()) do
        if state.slots[entry[1]] and state.slots[entry[1]].tone == "good" then return entry[1] end
    end
    for _, entry in ipairs(Slots()) do
        if state.slots[entry[1]] and state.slots[entry[1]].mark then return entry[1] end
    end
    local first = Slots()[1]
    return first and first[1] or 1
end

--------------------------------------------------------------------------------
-- The cards
--------------------------------------------------------------------------------

local function BuildCard(parent, primary)
    local card = Theme.CreatePanel(parent, "panel", primary and "accent" or "border")
    card:SetSize(CARD_WIDTH, CARD_HEIGHT)
    Theme.TopSheen(card, 0.05)

    -- Its place in the order: 1, 2, 3.
    local step = CreateFrame("Frame", nil, card)
    step:SetSize(24, 24)
    step:SetPoint("LEFT", 12, 0)
    step.background = Theme.Fill(step, "glassActive")
    Theme.Border(step, "metal")
    local number = Theme.CreateLabel(step, "large", "gilt", "CENTER")
    number:SetPoint("CENTER", 0, 0)
    card.number = number

    local icon = Theme.CreateItemIcon(card, 30)
    icon:SetPoint("LEFT", step, "RIGHT", 10, 0)
    card.icon = icon

    local heading = Theme.CreateLabel(card, "tiny", "gilt")
    card.heading = heading
    local line = Theme.CreateLabel(card, "normal", "text")
    line:SetWordWrap(true)
    card.line = line

    local button = Widgets.CreateButton(card, "", function(self)
        local run = rawget(card, "run")
        if run then run(self) end
    end, { width = 104, height = 24, primary = primary })
    button:SetPoint("RIGHT", -12, 0)
    card.button = button

    card:Hide()
    return card
end

--- Fill a card and size its line to the room left. `item` puts an item's
--- icon before the words.
local function SetCard(card, heading, line, label, run, item)
    card.heading:SetText(heading)
    card.line:SetText(line)
    card.button:SetText(label)
    card.run = run
    local width = math.max(104, Theme.TextWidth("normal", label) + 28)
    card.button:SetWidth(width)
    Theme.SetItemIcon(card.icon, item)
    local left = 12 + 24 + 10 + (item and 40 or 0)
    card.heading:ClearAllPoints()
    card.heading:SetPoint("TOPLEFT", left, -12)
    card.line:ClearAllPoints()
    card.line:SetPoint("TOPLEFT", left, -26)
    card.line:SetWidth(CARD_WIDTH - left - width - 22)
end

function MyGear:BuildCards()
    self.cards = {
        ready = BuildCard(self.page, true),
        next = BuildCard(self.page, false),
        trainer = BuildCard(self.page, false),
    }
end

--- The cards as the state has them, left to right, numbered in order.
-- @return how many show
function MyGear:PaintCards(state)
    local cards = self.cards
    local shown = {}

    local ready = #state.ready
    if ready > 0 then
        SetCard(cards.ready, L["READY NOW"],
            ready == 1 and L["1 upgrade in your bags."] or L.Format("%d upgrades in your bags.", ready),
            ready == 1 and L["Put It On"] or L["Put Them On"], function() MyGear:PutThemOn() end)
        shown[#shown + 1] = cards.ready
    end

    local pick = state.next
    if pick then
        local tone = MyGear.Later(pick) and "warn" or "good"
        SetCard(cards.next, L["NEXT TO GO GET"],
            ns.Items.ShowLink(pick.link) .. "  " .. Colored(tone, Gain(pick.result)),
            L["Show Me How"], function() MyGear:ShowMeHow() end, pick.link)
        cards.next.pick = pick
        shown[#shown + 1] = cards.next
    end

    local training = state.training
    if training then
        local words = training.count == 1 and L["1 spell to train."]
            or L.Format("%d spells to train.", training.count)
        SetCard(cards.trainer, L["AT THE TRAINER"], words .. "  " .. training.cost,
            L["Show the Way"], function()
                if ns.ClassTraining then ns.ClassTraining:ShowTheWay() end
            end)
        shown[#shown + 1] = cards.trainer
    end

    for _, card in pairs(cards) do card:Hide() end
    for index, card in ipairs(shown) do
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", self.page, "TOPLEFT", PAD + (index - 1) * (CARD_WIDTH + CARD_GAP),
            -(CARDS_TOP + self:SwitchRoom()))
        card.number:SetText(tostring(index))
        card:Show()
    end
    self.cardsShown = #shown
    return #shown
end

--------------------------------------------------------------------------------
-- Switch Gear (Logic/SwitchGear.lua): which spec's gear is on, and one
-- button that puts the other's on. Shows only while an Off Spec is picked.
--------------------------------------------------------------------------------

local function SpecButton(parent, which)
    return Widgets.CreateButton(parent, "", function()
        local state = MyGear.switchState
        if state and state.go == which and ns.SwitchGear then ns.SwitchGear:Go(which) end
    end, { width = 120, height = 22 })
end

function MyGear:BuildSwitch()
    local bar = CreateFrame("Frame", nil, self.page)
    bar:SetPoint("TOPLEFT", self.page, "TOPLEFT", PAD, -CARDS_TOP)
    bar:SetPoint("TOPRIGHT", self.page, "TOPRIGHT", -PAD, -CARDS_TOP)
    bar:SetHeight(SWITCH - 8)
    bar:Hide()
    self.switchBar = bar

    local wearing = Theme.CreateLabel(bar, "small", "gilt")
    wearing:SetPoint("LEFT", 2, 0)
    wearing:SetText(L["Wearing:"])
    local main = SpecButton(bar, "main")
    main:SetPoint("LEFT", wearing, "RIGHT", 8, 0)
    local off = SpecButton(bar, "off")
    off:SetPoint("LEFT", main, "RIGHT", 4, 0)
    self.switchMain, self.switchOff = main, off

    local go = Widgets.CreateButton(bar, "", function()
        if ns.SwitchGear then ns.SwitchGear:Go() end
    end, { width = 150, height = 24, primary = true })
    go:SetPoint("RIGHT", 0, 0)
    go:SetScript("OnEnter", function(self) MyGear:SwitchTooltip(self) end)
    go:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    self.switchGo = go

    local count = Theme.CreateLabel(bar, "small", "muted", "RIGHT")
    count:SetPoint("RIGHT", go, "LEFT", -12, 0)
    self.switchCount = count
end

--- The room the row takes above the cards: none while it is hidden.
function MyGear:SwitchRoom()
    return Shown(self.switchBar) and SWITCH or 0
end

--- Every piece that will change, in a tooltip: "Head: Green Iron Helm ->
--- Helm of Sample Guarding".
function MyGear:SwitchTooltip(owner)
    local state = self.switchState
    if not (state and GameTooltip) then return end
    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOMLEFT")
    local count = #state.steps
    GameTooltip:AddLine(count == 1 and L["1 piece will change"] or L.Format("%d pieces will change", count),
        Theme.Unpack("gilt"))
    local names = {}
    for _, entry in ipairs(Slots()) do names[entry[1]] = entry[2] end
    local twoHander = false
    pcall(function()
        local held = ns.Items:Info(ns.Items:WornNow(MAIN_HAND))
        twoHander = held and held.equipLoc == "INVTYPE_2HWEAPON" or false
    end)
    local show = ns.Items.ShowLink
    for _, step in ipairs(state.steps) do
        local from = step.from and show(step.from)
            or (step.slot == OFF_HAND and twoHander and L["Held by your two-hander"]) or L["Empty"]
        GameTooltip:AddDoubleLine(names[step.slot] or "", (from or "") .. "  >  " .. (show(step.to) or ""),
            Theme.Unpack("muted"))
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Equipment picks the best pieces you carry for each spec. There is nothing to save or set up."],
        Theme.Unpack("muted"))
    GameTooltip:Show()
end

--- Fill the row from where things stand. A row that comes or goes moves
--- the cards and the slots under it.
function MyGear:PaintSwitch()
    if not self.switchBar then return end
    local SwitchGear = ns.SwitchGear
    local state = SwitchGear and self:IsShown() and SwitchGear:State() or nil
    self.switchState = state
    local was = Shown(self.switchBar)
    self.switchBar:SetShown(state ~= nil)
    if state then
        local mainName = Weights:SpecName(Weights:PlayerClass(), (Weights:MainSpec())) or ""
        local offName = ns.OffSpec:Name() or ""
        self.switchMain:SetText(L.Format("Main Spec (%s)", mainName))
        self.switchOff:SetText(L.Format("Off Spec (%s)", offName))
        self.switchMain:SetLabelColor(state.on == "main" and "good" or "gilt")
        self.switchOff:SetLabelColor(state.on == "off" and "good" or "gilt")
        local count = #state.steps
        local busy = SwitchGear:Busy()
        self.switchGo:SetShown(state.go ~= nil and not busy)
        if state.go then
            self.switchGo:SetText(L.Format("Put On %s Gear", state.go == "off" and offName or mainName))
        end
        if busy then
            self.switchCount:SetText(L["They go on after the fight."])
        elseif state.go then
            self.switchCount:SetText(count == 1 and L["1 piece will change"] or L.Format("%d pieces will change", count))
        else
            self.switchCount:SetText("")
        end
    end
    if was ~= (state ~= nil) and self.state and not self.painting then
        self:PlaceBody(self:PaintCards(self.state))
    end
end

--- Put on every upgrade in the bags that needs no training, one after the
--- other (Logic/Wear.lua). In a fight they wait for its end.
function MyGear:PutThemOn()
    local state = self.state
    if not (state and ns.Wear) then return 0 end
    return ns.Wear:PutOnAll(state.ready)
end

--- Follow the second card's piece as the upgrade quest, as a click on its
--- row in the list does.
function MyGear:ShowMeHow()
    local pick = self.state and self.state.next
    if pick and ns.FinderUI then ns.FinderUI:Follow(pick) end
end

--------------------------------------------------------------------------------
-- The figure
--------------------------------------------------------------------------------

--- An upgrade arrow: the house's small triangle, pointing up.
local function UpArrow(parent, size)
    local arrow = parent:CreateTexture(nil, "OVERLAY")
    if ns.Titanforged then arrow:SetTexture(ns.Titanforged.MEDIA .. "SortArrow") end
    arrow:SetSize(size, size)
    pcall(arrow.SetTexCoord, arrow, 0, 1, 1, 0)
    return arrow
end

local function Tint(texture, key)
    pcall(texture.SetVertexColor, texture, Theme.Unpack(key))
end

--- One slot on the figure: its icon with the gain on it and an arrow at
--- its corner, the slot's name and what is worn. `mirror` puts the icon at
--- the right, for the right-hand column.
function MyGear:BuildSlot(parent, slot, mirror)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(SLOT_WIDTH, SLOT_HEIGHT)
    button.slot = slot
    button.background = Theme.Fill(button, "glassActive")
    button.background:Hide()
    Theme.Border(button, "accent")
    for _, edge in ipairs(rawget(button, "borderTextures") or {}) do edge:Hide() end

    local near, far = mirror and "RIGHT" or "LEFT", mirror and "LEFT" or "RIGHT"
    local sign = mirror and -1 or 1

    -- An empty slot keeps its place: a dark well with a fine edge.
    local well = CreateFrame("Frame", nil, button)
    well:SetSize(ICON, ICON)
    well:SetPoint(near, sign * 6, 0)
    Theme.Fill(well, "well")
    Theme.Border(well, "border")
    local icon = Theme.CreateItemIcon(button, ICON)
    icon:SetPoint("CENTER", well, "CENTER", 0, 0)
    button.icon = icon

    -- The gain, on a dark strip along the icon's foot.
    local strip = CreateFrame("Frame", nil, button)
    strip:SetSize(ICON - 2, 13)
    strip:SetPoint("BOTTOM", well, "BOTTOM", 0, 1)
    pcall(strip.SetFrameLevel, strip, (button:GetFrameLevel() or 1) + 3)
    Theme.Fill(strip, "well", 0.85)
    local gain = Theme.CreateLabel(strip, "tiny", "good", "CENTER")
    gain:SetPoint("CENTER", 0, 0)
    button.strip, button.gain = strip, gain

    local arrow = UpArrow(strip, 12)
    arrow:SetPoint("CENTER", well, "TOPRIGHT", -2, -2)
    button.arrow = arrow

    local label = Theme.CreateLabel(button, "tiny", "muted", mirror and "RIGHT" or "LEFT")
    label:SetPoint("TOP" .. near, button, "TOP" .. near, sign * (ICON + 14), -8)
    label:SetWidth(SLOT_WIDTH - ICON - 20)
    button.label = label
    local name = Theme.CreateLabel(button, "small", "text", mirror and "RIGHT" or "LEFT")
    name:SetPoint("TOP" .. near, label, "BOTTOM" .. near, 0, -2)
    name:SetWidth(SLOT_WIDTH - ICON - 20)
    name:SetWordWrap(true)
    button.name = name
    button.far = far

    button:SetScript("OnEnter", function(self)
        self.over = true
        MyGear:PaintSlotLight(self)
        local link = rawget(self, "link")
        if type(link) == "string" then
            GameTooltip:SetOwner(self, mirror and "ANCHOR_LEFT" or "ANCHOR_RIGHT")
            pcall(GameTooltip.SetHyperlink, GameTooltip, link)
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function(self)
        self.over = false
        MyGear:PaintSlotLight(self)
        GameTooltip:Hide()
    end)
    button:SetScript("OnClick", function(self)
        -- The gear worn there: Shift-click links it, Ctrl-click tries it on.
        local link = rawget(self, "link")
        if type(link) == "string" and Widgets.ItemClick(nil, link) then return end
        MyGear:PickSlot(self.slot)
    end)
    return button
end

--- A slot's frame: gold when picked, a soft light under the mouse.
function MyGear:PaintSlotLight(button)
    local picked = button.slot == self.slot
    local over = rawget(button, "over") == true
    button.background:SetShown(picked or over)
    button.background:SetColorTexture(Theme.Unpack(picked and "glassActive" or "glassHover"))
    for _, edge in ipairs(rawget(button, "borderTextures") or {}) do edge:SetShown(picked) end
end

--- One slot as the state has it.
function MyGear:PaintSlot(button, info)
    info = info or {}
    button.link = info.link or false
    button.label:SetText(info.name or "")
    Theme.SetItemIcon(button.icon, info.link)
    if info.link then
        button.name:SetText(ns.FinderUI and ns.FinderUI.ItemText(info.link) or info.link)
    elseif info.held then
        button.name:SetText(Colored("dim", L["Held by your two-hander"]))
    else
        button.name:SetText(Colored("dim", L["Empty"]))
    end
    local mark = info.mark
    button.strip:SetShown(mark ~= nil)
    button.arrow:SetShown(mark ~= nil)
    if mark then
        button.gain:SetText(MyGear.Badge(mark))
        button.gain:SetTextColor(Theme.Unpack(info.tone))
        Tint(button.arrow, info.tone)
    end
    self:PaintSlotLight(button)
end

--- The ring of dots: gold as far round as the rating reaches, from the
--- top, the rest dim.
local function PaintRing(dots, share)
    local lit = math.floor(#dots * math.max(0, math.min(1, share)) + 0.5)
    for index, dot in ipairs(dots) do
        if index <= lit then
            dot:SetColorTexture(Theme.Unpack("accentHi"))
        else
            dot:SetColorTexture(Theme.Unpack("border", 0.9))
        end
    end
end

function MyGear:BuildFigure()
    local figure = CreateFrame("Frame", nil, self.left)
    figure:SetPoint("TOPLEFT", 0, -VIEW_ROW)
    figure:SetPoint("BOTTOMRIGHT", 0, 0)
    self.figure = figure

    self.slotButtons = {}
    for index, slot in ipairs(LEFT_SLOTS) do
        local button = self:BuildSlot(figure, slot, false)
        button:SetPoint("TOPLEFT", 0, -(index - 1) * SLOT_HEIGHT)
        self.slotButtons[slot] = button
    end
    for index, slot in ipairs(RIGHT_SLOTS) do
        local button = self:BuildSlot(figure, slot, true)
        button:SetPoint("TOPRIGHT", 0, -(index - 1) * SLOT_HEIGHT)
        self.slotButtons[slot] = button
    end
    local footTop = -(#LEFT_SLOTS * SLOT_HEIGHT + 8)
    local footLeft = math.floor((LEFT - #FOOT_SLOTS * SLOT_WIDTH) / 2)
    for index, slot in ipairs(FOOT_SLOTS) do
        local button = self:BuildSlot(figure, slot, false)
        button:SetPoint("TOPLEFT", footLeft + (index - 1) * SLOT_WIDTH, footTop)
        self.slotButtons[slot] = button
    end

    -- The middle: the rating in its ring, who this is, the spec gear is
    -- judged as, and what the arrows' colours mean.
    local middle = CreateFrame("Frame", nil, figure)
    middle:SetPoint("TOP", figure, "TOP", 0, 0)
    middle:SetSize(LEFT - SLOT_WIDTH * 2, #LEFT_SLOTS * SLOT_HEIGHT)
    self.middle = middle

    local centerY = -(RING + 14)
    local dots = {}
    for index = 1, DOTS do
        local angle = (index - 0.5) / DOTS * 2 * math.pi
        local dot = middle:CreateTexture(nil, "ARTWORK")
        dot:SetSize(3, 3)
        dot:SetPoint("CENTER", middle, "TOP", math.sin(angle) * RING, centerY + math.cos(angle) * RING)
        dots[index] = dot
    end
    self.dots = dots

    local ringHead = Theme.CreateLabel(middle, "tiny", "muted", "CENTER")
    ringHead:SetPoint("CENTER", middle, "TOP", 0, centerY + 22)
    ringHead:SetText(L["YOUR GEAR"])
    local rating = Theme.CreateLabel(middle, "title", "text", "CENTER")
    rating:SetPoint("CENTER", middle, "TOP", 0, centerY)
    self.ratingLabel = rating
    local count = Theme.CreateLabel(middle, "tiny", "good", "CENTER")
    count:SetPoint("CENTER", middle, "TOP", 0, centerY - 22)
    self.countLabel = count

    local who = Theme.CreateLabel(middle, "normal", "text", "CENTER")
    who:SetPoint("TOP", middle, "TOP", 0, centerY - RING - 16)
    who:SetWidth(LEFT - SLOT_WIDTH * 2 - 8)
    who:SetWordWrap(true)
    self.whoLabel = who
    local level = Theme.CreateLabel(middle, "small", "muted", "CENTER")
    level:SetPoint("TOP", who, "BOTTOM", 0, -4)
    self.levelLabel = level

    local judge = Theme.CreateLabel(middle, "small", "gilt", "CENTER")
    judge:SetPoint("TOP", level, "BOTTOM", 0, -16)
    judge:SetText(L["Main Spec:"])
    local FinderUI = ns.FinderUI
    local spec = FinderUI.MainSpecChoice(middle, 150)
    spec:SetPoint("TOP", judge, "BOTTOM", 0, -6)
    self.specChoice = spec
    local offLabel = Theme.CreateLabel(middle, "small", "gilt", "CENTER")
    offLabel:SetPoint("TOP", spec, "BOTTOM", 0, -10)
    offLabel:SetText(L["Off Spec:"])
    local off = FinderUI.OffSpecChoice(middle, 150)
    off:SetPoint("TOP", offLabel, "BOTTOM", 0, -6)
    self.offChoice = off

    -- The key: green to wear now, blue for the Off Spec (while one is
    -- picked), amber for later.
    local keys = { { "good", L["Wear it now"] }, { "offSpec", L["Off Spec"] }, { "warn", L["For later"] } }
    local anchor = off
    self.keyWords = {}
    for index, key in ipairs(keys) do
        local words = Theme.CreateLabel(middle, "tiny", "muted", "CENTER")
        words:SetPoint("TOP", anchor, "BOTTOM", 6, index == 1 and -16 or -6)
        words:SetText(key[2])
        local arrow = UpArrow(middle, 10)
        arrow:SetPoint("RIGHT", words, "LEFT", -4, 0)
        Tint(arrow, key[1])
        self.keyWords[key[1]] = { words = words, arrow = arrow }
        anchor = words
    end
end

--- The spec drop-down as the character's choice stands (the old header's
--- way: UI/FinderWindow.lua, FinderUI:SyncSpec).
function MyGear:SyncSpec()
    local choice, FinderUI = self.specChoice, ns.FinderUI
    if not (choice and FinderUI) then return end
    FinderUI.SyncSpecChoices(choice, self.offChoice)
    -- The blue key shows only while an Off Spec is picked.
    local key = self.keyWords and self.keyWords.offSpec
    if key then
        local on = ns.OffSpec and ns.OffSpec:On() or false
        key.words:SetText(on and L["Off Spec"] or "")
        key.arrow:SetShown(on)
    end
end

--- The character's name as the game shows it, and "Level 38 Warrior".
local function Who()
    local name, class
    pcall(function()
        local guid = ns.Alts and ns.Alts.PlayerGUID()
        name = guid and ns.Alts:NameOf(guid) or nil
        class = _G.UnitClass and (_G.UnitClass("player")) or nil
    end)
    local level = ns.Items and ns.Items:PlayerLevel()
    local line = ""
    if level and type(class) == "string" then
        line = L.Format("Level %d %s", level, class)
    elseif level then
        line = L.Format("Level %d", level)
    end
    return type(name) == "string" and name or "", line
end

function MyGear:PaintFigure(state)
    for slot, button in pairs(self.slotButtons) do
        self:PaintSlot(button, state.slots[slot])
    end
    local rating = state.rating
    if rating and rating.rating then
        self.ratingLabel:SetText(rating.rating.label or "")
        PaintRing(self.dots, (rating.score or 0) / 100)
    else
        self.ratingLabel:SetText("")
        PaintRing(self.dots, 0)
    end
    local count = state.upgrades
    self.countLabel:SetText(count == 1 and L["1 upgrade"] or count > 1 and L.Format("%d upgrades", count) or "")
    local name, line = Who()
    self.whoLabel:SetText(name)
    self.levelLabel:SetText(line)
    self:SyncSpec()
end

--------------------------------------------------------------------------------
-- The list
--------------------------------------------------------------------------------

local HEADS = {
    { key = "slot", text = L["SLOT"], x = 10 },
    { key = "worn", text = L["YOU WEAR"], x = 10 + LIST_SLOT },
    { key = "best", text = L["BEST UPGRADE"], x = 10 + LIST_SLOT + LIST_WORN },
}

--- What a slot's line sorts by under a heading; nil sorts last.
function MyGear.SortValue(info, key, order)
    if key == "worn" then
        local name = type(info.link) == "string" and info.link:match("%[(.-)%]")
        return name and name:lower() or nil
    end
    if key == "best" then
        if not info.mark then return nil end
        -- Wear-it-now before later, each best first.
        local shown = Finder.Shown(info.mark) or 1000
        return (info.tone == "good" and 100000 or 0) + shown
    end
    return order
end

--- The slots in the order the list shows them: sheet order, or by the
--- heading clicked (`flip` the other way round), empty values last.
function MyGear:Sorted(state)
    local key, flip = self.sortKey or "slot", self.sortFlip == true
    local lines = {}
    for order, entry in ipairs(Slots()) do
        local info = state.slots[entry[1]]
        if info then lines[#lines + 1] = { info = info, order = order, value = MyGear.SortValue(info, key, order) } end
    end
    -- Best Upgrade starts with the biggest; names and slots start at the top.
    local down = (key == "best") ~= flip
    table.sort(lines, function(a, b)
        if (a.value == nil) ~= (b.value == nil) then return a.value ~= nil end
        if a.value ~= b.value and a.value ~= nil then
            if down then return a.value > b.value end
            return a.value < b.value
        end
        return a.order < b.order
    end)
    return lines
end

--- A heading clicked: sort by it, a second click turns it round.
function MyGear:SortBy(key)
    if self.sortKey == key or (not self.sortKey and key == "slot") then
        self.sortFlip = not self.sortFlip
    else
        self.sortKey, self.sortFlip = key, false
    end
    if self.state then self:PaintList(self.state) end
end

function MyGear:BuildList()
    local list = CreateFrame("Frame", nil, self.left)
    list:SetPoint("TOPLEFT", 0, -VIEW_ROW)
    list:SetPoint("BOTTOMRIGHT", 0, 0)
    list:Hide()
    self.list = list

    local well = Theme.CreatePanel(list, "panel", "border")
    well:SetPoint("TOPLEFT", 0, 0)
    well:SetPoint("TOPRIGHT", 0, 0)
    well:SetHeight(LIST_HEAD + #Slots() * LIST_ROW + 4)
    Theme.Recess(well)

    self.heads = {}
    for _, head in ipairs(HEADS) do
        local button = CreateFrame("Button", nil, list)
        button:SetSize(Theme.TextWidth("tiny", head.text) + 20, LIST_HEAD)
        button:SetPoint("TOPLEFT", head.x, 0)
        local label = Theme.CreateLabel(button, "tiny", "heading")
        label:SetPoint("LEFT", 0, 0)
        label:SetText(head.text)
        button.label = label
        local arrow = UpArrow(button, 8)
        arrow:SetPoint("LEFT", label, "RIGHT", 4, 0)
        arrow:Hide()
        button.arrow = arrow
        button.key = head.key
        button:SetScript("OnClick", function(self) MyGear:SortBy(self.key) end)
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(L["Click a heading to sort. Click it again to flip the order, and a third time for best first."], 1, 1, 1, true)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        self.heads[#self.heads + 1] = button
    end

    self.listRows = {}
    for index = 1, #Slots() do
        local row = CreateFrame("Button", nil, list)
        row:SetHeight(LIST_ROW)
        row:SetPoint("TOPLEFT", 2, -(LIST_HEAD + (index - 1) * LIST_ROW))
        row:SetPoint("TOPRIGHT", -2, -(LIST_HEAD + (index - 1) * LIST_ROW))
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
        edge:SetWidth(3)
        edge:Hide()
        row.edge = edge

        local slot = Theme.CreateLabel(row, "small", "text")
        slot:SetPoint("LEFT", 8, 0)
        slot:SetWidth(LIST_SLOT - 8)
        row.slotLabel = slot
        local worn = Theme.CreateLabel(row, "small", "text")
        worn:SetPoint("LEFT", 8 + LIST_SLOT, 0)
        worn:SetWidth(LIST_WORN - 10)
        row.worn = worn
        local gain = Theme.CreateLabel(row, "small", "good", "RIGHT")
        gain:SetPoint("RIGHT", -8, 0)
        gain:SetWidth(52)
        row.gain = gain
        local best = Theme.CreateLabel(row, "small", "text")
        best:SetPoint("LEFT", 8 + LIST_SLOT + LIST_WORN, 0)
        best:SetPoint("RIGHT", gain, "LEFT", -6, 0)
        row.best = best

        row:SetScript("OnEnter", function(self)
            self.over = true
            MyGear:PaintListRow(self)
            local link = rawget(self, "link")
            if type(link) == "string" then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                pcall(GameTooltip.SetHyperlink, GameTooltip, link)
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function(self)
            self.over = false
            MyGear:PaintListRow(self)
            GameTooltip:Hide()
        end)
        row:SetScript("OnClick", function(self)
            local link = rawget(self, "link")
            if type(link) == "string" and Widgets.ItemClick(nil, link) then return end
            if rawget(self, "slot") then MyGear:PickSlot(self.slot) end
        end)
        self.listRows[index] = row
    end
end

--- A list line's dark glass: picked, under the mouse, or at rest.
function MyGear:PaintListRow(row)
    local picked = rawget(row, "slot") == self.slot
    local over = rawget(row, "over") == true
    row.background:SetColorTexture(Theme.Unpack(picked and "glassActive" or over and "glassHover" or row.restKey))
    row.edge:SetShown(picked or over)
    row.edge:SetColorTexture(Theme.Unpack(picked and "accentHi" or "accent"))
end

--- The name of the piece a slot's mark stands for.
local function BestName(info)
    local FinderUI = ns.FinderUI
    local link = (info.owned[1] and info.owned[1].link) or (info.now and info.now.link)
        or (info.later and info.later.link) or (info.offNow and info.offNow.link)
    return link and FinderUI and FinderUI.ItemText(link) or ""
end

function MyGear:PaintList(state)
    local key = self.sortKey or "slot"
    for _, head in ipairs(self.heads) do
        local sorted = head.key == key and (key ~= "slot" or self.sortFlip == true)
        head.label:SetTextColor(Theme.Unpack(sorted and "text" or "heading"))
        head.arrow:SetShown(sorted)
        if sorted then
            local down = (key == "best") ~= (self.sortFlip == true)
            pcall(head.arrow.SetTexCoord, head.arrow, 0, 1, down and 0 or 1, down and 1 or 0)
        end
    end
    local lines = self:Sorted(state)
    for index, row in ipairs(self.listRows) do
        local line = lines[index]
        local info = line and line.info
        if info then
            row.slot, row.link = info.slot, info.link or false
            row.slotLabel:SetText(info.name or "")
            if info.link then
                row.worn:SetText(ns.FinderUI.ItemText(info.link))
            else
                row.worn:SetText(Colored("dim", info.held and L["Held by your two-hander"] or L["Empty"]))
            end
            row.best:SetText(BestName(info))
            row.gain:SetText(info.mark and MyGear.Badge(info.mark) or "")
            row.gain:SetTextColor(Theme.Unpack(info.tone or "good"))
            row:Show()
            self:PaintListRow(row)
        else
            row.slot = false
            row:Hide()
        end
    end
end

local VIEWS = { figure = true, list = true, road = true }

--- Figure, List or Road (`myGearView`, account wide; Figure unless another
--- was picked).
function MyGear:View()
    local view = ns.db and ns.db.myGearView
    if view == "road" and not ns.GearRoad then return "figure" end
    return VIEWS[view] and view or "figure"
end

function MyGear:SetView(view)
    if ns.db then ns.db.myGearView = VIEWS[view] and view or "figure" end
    self:PaintView()
    if self:View() == "road" then
        ns.GearRoad:Show()
        self.footer:SetText(L["Amber gear is for later. The road only lists gear your class can wear."])
        return
    end
    if self.state then
        self:PlaceBody(self:PaintCards(self.state))
        if self:View() == "list" then self:PaintList(self.state) else self:PaintFigure(self.state) end
        self:PaintSide(self.state)
        self.footer:SetText(MyGear.FooterText(self.state))
    else
        self:Refresh()
    end
end

--- Gear Road takes the whole body: no cards, no slot side.
function MyGear:PaintView()
    local view = self:View()
    local road = view == "road"
    self.figure:SetShown(view == "figure")
    self.list:SetShown(view == "list")
    self.side:SetShown(not road)
    self.hint:SetText(road and L["Click a stop to see every piece it opens."] or L["Click a slot"])
    self.hint:ClearAllPoints()
    if road then
        self.hint:SetPoint("TOPRIGHT", self.body, "TOPRIGHT", -4, -7)
        for _, card in pairs(self.cards) do card:Hide() end
        self:PlaceBody(0)
    else
        self.hint:SetPoint("TOPRIGHT", self.left, "TOPRIGHT", -4, -7)
    end
    if ns.GearRoad then
        if road then ns.GearRoad.frame:Show() else ns.GearRoad:Hide() end
    end
    self.figureButton:SetLabelColor(view == "figure" and "good" or "gilt")
    self.listButton:SetLabelColor(view == "list" and "good" or "gilt")
    if self.roadButton then self.roadButton:SetLabelColor(road and "good" or "gilt") end
end

--------------------------------------------------------------------------------
-- The slot's side
--------------------------------------------------------------------------------

function MyGear:BuildRow(index)
    local side = self.side
    local row = CreateFrame("Button", nil, side)
    row:SetHeight(ROW_MIN)
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

    local icon = Theme.CreateItemIcon(row, ROW_ICON)
    icon:SetPoint("TOPLEFT", 10, -6)
    row.icon = icon

    local item = Theme.CreateLabel(row, "normal", "text")
    item:SetPoint("TOPLEFT", ROW_TEXT, -7)
    item:SetWordWrap(true)
    row.item = item
    local under = Theme.CreateLabel(row, "tiny", "muted")
    under:SetPoint("TOPLEFT", item, "BOTTOMLEFT", 0, -3)
    under:SetWordWrap(true)
    row.under = under

    local gain = Theme.CreateLabel(row, "normal", "good", "RIGHT")
    gain:SetPoint("TOPRIGHT", -10, -7)
    gain:SetWidth(GAIN_WIDTH)
    gain:SetWordWrap(true)
    row.gain = gain
    local arrow = UpArrow(row, 10)
    row.arrow = arrow

    -- The row's one button: Put It On, Queue It or Show the Way.
    local button = Widgets.CreateButton(row, "", function(self)
        local run = rawget(row, "run")
        if run then run(self) end
    end, { width = 78, height = 20 })
    button:SetPoint("BOTTOMRIGHT", -10, 6)
    button:Hide()
    row.button = button
    local gold = Widgets.CreateButton(row, L["Put It On"], function()
        local owned = rawget(row, "owned")
        if owned and ns.Wear then ns.Wear:PutOn(owned.link) end
    end, { width = 78, height = 20, primary = true })
    gold:SetPoint("BOTTOMRIGHT", -10, 6)
    gold:Hide()
    row.putOn = gold

    local heading = Theme.CreateLabel(row, "tiny", "gilt")
    heading:SetPoint("LEFT", 12, 0)
    heading:Hide()
    row.headingLabel = heading

    local function Light(p)
        row.background:SetColorTexture(Motion.Mix(row.restKey, "glassHover", p))
        row.edge:SetColorTexture(Theme.Unpack("accentHi", p))
    end
    row:SetScript("OnEnter", function(self)
        self.over = true
        if rawget(self, "heading") then return end
        Motion:Blend(self, "hover", 1, 0.12, Light)
        if ns.FinderUI then ns.FinderUI.ShowRowTooltip(self) end
    end)
    row:SetScript("OnLeave", function(self)
        self.over = false
        Motion:Blend(self, "hover", 0, 0.18, Light)
        GameTooltip:Hide()
    end)
    -- The clicks the old list's rows take: follow, put on, link, try on,
    -- and the right-click menu.
    row:SetScript("OnClick", function(self, mouse)
        if ns.FinderUI then ns.FinderUI.RowClicked(self, mouse) end
    end)
    if row.RegisterForClicks then row:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    row:Hide()
    return row
end

function MyGear:BuildSide()
    local side = Theme.CreatePanel(self.body, "panel", "border")
    side:SetPoint("TOPLEFT", LEFT + GAP, 0)
    side:SetPoint("BOTTOMRIGHT", 0, 0)
    Theme.Recess(side)
    self.side = side

    local icon = Theme.CreateItemIcon(side, 36)
    icon:SetPoint("TOPLEFT", 12, -10)
    self.headIcon = icon
    local heading = Theme.CreateLabel(side, "tiny", "gilt")
    heading:SetPoint("TOPLEFT", 60, -12)
    self.headLabel = heading
    local name = Theme.CreateLabel(side, "large", "text")
    name:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -5)
    name:SetPoint("RIGHT", side, "RIGHT", -12, 0)
    self.headName = name
    local rule = Theme.CreateDivider(side, "border")
    rule:SetPoint("TOPLEFT", 1, -HEAD)
    rule:SetPoint("TOPRIGHT", -1, -HEAD)

    self.rows = {}
    for index = 1, ROWS do self.rows[index] = self:BuildRow(index) end

    local empty = Theme.CreateLabel(side, "small", "muted", "CENTER")
    empty:SetPoint("TOP", side, "TOP", 0, -(HEAD + 40))
    empty:SetWordWrap(true)
    empty:Hide()
    self.empty = empty

    -- See All for Head: the Upgrades tab, on this slot.
    local all = Widgets.CreateButton(side, "", function() MyGear:SeeAll() end, { width = 140, height = 22 })
    all:Hide()
    self.seeAll = all
end

--- The lines a slot's side shows: what you own, the best enchant, then
--- the pieces to go and get.
function MyGear.Lines(info)
    local lines = {}
    if #info.owned > 0 then
        lines[#lines + 1] = { heading = L["IN YOUR BAGS"] }
        for _, piece in ipairs(info.owned) do lines[#lines + 1] = { owned = piece } end
    end
    if info.enchant then
        lines[#lines + 1] = { heading = L["BEST ENCHANT"] }
        lines[#lines + 1] = { enchant = info.enchant }
    end
    if #info.picks > 0 then
        lines[#lines + 1] = { heading = L["TO GO AND GET"] }
        for _, pick in ipairs(info.picks) do lines[#lines + 1] = { pick = pick } end
    end
    if info.offPicks and #info.offPicks > 0 then
        lines[#lines + 1] = { heading = L["Off Spec"]:upper() }
        for _, pick in ipairs(info.offPicks) do lines[#lines + 1] = { pick = pick, off = true } end
    end
    return lines
end

--- Fill one row of the slot's side.
-- @return its height
function MyGear:FillRow(row, line, width)
    row.pick, row.owned, row.enchant, row.heading, row.run = nil, false, nil, false, nil
    row.button:Hide()
    row.putOn:Hide()
    row.arrow:Hide()
    row.headingLabel:Hide()
    row.background:SetColorTexture(Theme.Unpack(row.restKey))
    if not line then
        row:Hide()
        return 0
    end
    row:Show()
    if line.heading then
        row.heading = true
        Theme.SetItemIcon(row.icon, nil)
        row.item:SetText("")
        row.under:SetText("")
        row.gain:SetText("")
        row.headingLabel:SetText(line.heading)
        row.headingLabel:Show()
        row:SetHeight(HEADING_ROW)
        return HEADING_ROW
    end

    local FinderUI = ns.FinderUI
    local textWidth = width - ROW_TEXT - GAIN_WIDTH - 20
    row.item:SetWidth(textWidth)
    row.under:SetWidth(textWidth)
    local tone, buttonShown = "good", false

    if line.owned then
        local piece = line.owned
        local result = piece.result or {}
        row.owned = piece
        Theme.SetItemIcon(row.icon, piece.link)
        row.item:SetText(ns.Items.ShowLink(piece.link))
        row.under:SetText(piece.where ~= "bags" and ns.UI and ns.UI.WhereText(piece.where) or "")
        local gain = Gain(result)
        if result.skill then
            gain = L.Format("Train: %s", gain)
            tone = "loss"
        end
        row.gain:SetText(gain)
        if FinderUI.CanPutOn(piece) then
            row.putOn:Show()
            buttonShown = true
        end
    elseif line.enchant then
        local Enchants = ns.Enchants
        local enchant = line.enchant
        local pick, source = enchant.pick, enchant.source
        row.enchant = enchant
        Theme.SetItemIcon(row.icon, enchant.plan and enchant.plan.link)
        row.item:SetText(Enchants:ShownName(pick.recipeID) or "")
        row.under:SetText(Enchants:Describe(source, Finder.Money) or "")
        row.gain:SetText(pick.percent and ("%+d%%"):format(math.floor(pick.percent + 0.5)) or L["better"])
        local state = source and source.state
        if state == "skill" or state == "other" then tone = "warn" end
        if Enchants:CanQueue() then
            row.button:SetText(L["Queue It"])
            row.run = function() Enchants:Queue(pick.recipeID) end
            row.button:Show()
            buttonShown = true
        elseif (state == "learn" or state == "skill") and Enchants:CanShowTheWay(pick.recipeID) then
            row.button:SetText(L["Show the Way"])
            row.run = function()
                if not Enchants:ShowTheWay(pick.recipeID) then
                    ns.Print(L["Couldn't find where to learn it."])
                end
            end
            row.button:Show()
            buttonShown = true
        end
    else
        local pick = line.pick
        row.pick = {
            link = pick.link, sources = pick.sources, itemID = pick.itemID, needs = pick.needs,
            result = pick.result, roll = pick.roll, at = pick.at, gain = pick.gain,
        }
        Theme.SetItemIcon(row.icon, pick.link)
        row.item:SetText(ns.Items.ShowLink(pick.link))
        local under = pick.sources and pick.sources[1] and FinderUI.SourceLine(pick.sources[1]) or ""
        if pick.needs then
            under = Colored("warn", L.Format("Needs %s with %s", pick.needs.standing, pick.needs.faction))
                .. "  " .. under
        elseif pick.at then
            under = Colored("warn", L.Format("You can wear it from level %d", pick.at)) .. "  " .. under
        end
        row.under:SetText(under)
        local gain = Gain(pick.result)
        local train = ns.WeaponSkills and ns.WeaponSkills:NeedsTraining(pick.link)
        if train then
            gain = L.Format("Train: %s", gain)
            tone = "loss"
        elseif MyGear.Later(pick) then
            tone = "warn"
        elseif line.off then
            tone = "offSpec"
        end
        row.gain:SetText(gain)
    end

    row.gain:SetTextColor(Theme.Unpack(tone))
    Tint(row.arrow, tone)
    row.arrow:ClearAllPoints()
    row.arrow:SetPoint("RIGHT", row.gain, "RIGHT", -(math.min(GAIN_WIDTH, Theme.TextWidth("normal", row.gain:GetText() or "")) + 4), 0)
    row.arrow:Show()

    local underHeight = TextHeight(row.under, "tiny", textWidth)
    local height = 7 + TextHeight(row.item, "normal", textWidth) + (underHeight > 0 and underHeight + 3 or 0) + 8
    local right = 7 + TextHeight(row.gain, "normal", GAIN_WIDTH) + (buttonShown and 4 + 20 + 6 or 8)
    height = math.max(ROW_MIN, math.ceil(math.max(height, right)))
    row:SetHeight(height)
    return height
end

--- The slot picked, on the right: what is worn, then its lines.
function MyGear:PaintSide(state)
    local info = state.slots[self.slot]
    if not info then return end
    local side = self.side
    local okWidth, width = pcall(side.GetWidth, side)
    if not (okWidth and type(width) == "number" and width > 100) then width = WIDTH - PAD * 2 - LEFT - GAP end

    self.headLabel:SetText(L["YOU WEAR"] .. "  " .. Colored("muted", info.name or ""))
    Theme.SetItemIcon(self.headIcon, info.link)
    if info.link then
        self.headName:SetText(ns.Items.ShowLink(info.link))
    else
        self.headName:SetText(Colored("dim", info.held and L["Held by your two-hander"] or L["Empty"]))
    end

    local lines = MyGear.Lines(info)
    self.lines = lines
    local used = HEAD + 1
    for index, row in ipairs(self.rows) do
        local height = self:FillRow(row, lines[index], width - 2)
        if lines[index] then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", side, "TOPLEFT", 1, -used)
            row:SetPoint("TOPRIGHT", side, "TOPRIGHT", -1, -used)
            used = used + height
        end
    end

    if #lines == 0 then
        local words
        if not state.found then
            words = L["Looking for your next upgrade..."]
        elseif ns.Alts and ns.Alts:PlayerSkipped() then
            words = L["Upgrades are skipped for this character. Untick it in Settings, or type /beq skip off."]
        else
            words = L["Nothing on offer beats what you wear here."]
        end
        self.empty:SetWidth(width - 40)
        self.empty:SetText(words)
        self.empty:Show()
    else
        self.empty:Hide()
    end

    if #info.picks > 0 then
        local label = L.Format("See All for %s", info.name or "")
        self.seeAll:SetText(label)
        self.seeAll:SetWidth(math.max(120, Theme.TextWidth("normal", label) + 28))
        self.seeAll:ClearAllPoints()
        self.seeAll:SetPoint("TOPLEFT", side, "TOPLEFT", 12, -(used + 10))
        self.seeAll:Show()
    else
        self.seeAll:Hide()
    end
end

--- See All: Find Upgrades, narrowed to the slot picked here.
function MyGear:SeeAll()
    local Find, Gear = ns.FindUpgrades, ns.GearWindow
    if not (Find and Gear and self.slot) then return end
    Gear:ShowTab("find")
    Find:SetSlot(self.slot)
end

--- A slot clicked: light it and show it on the right. Nothing is read
--- again.
function MyGear:PickSlot(slot)
    local state = self.state
    if not (state and state.slots[slot]) then return end
    self.slot = slot
    if self:View() == "list" then
        for _, row in ipairs(self.listRows) do
            if Shown(row) then self:PaintListRow(row) end
        end
    else
        for _, button in pairs(self.slotButtons) do self:PaintSlotLight(button) end
    end
    self:PaintSide(state)
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

function MyGear:Build(area)
    if self.page then return self.page end
    if not area then return nil end

    local page = CreateFrame("Frame", nil, area)
    page:SetAllPoints(area)
    Theme.Fill(page, "window")
    page:Hide()
    self.page = page

    self:BuildCards()
    self:BuildSwitch()

    -- Everything under the cards: it moves up when no card shows.
    local body = CreateFrame("Frame", nil, page)
    self.body = body

    local left = CreateFrame("Frame", nil, body)
    left:SetPoint("TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", 0, 0)
    left:SetWidth(LEFT)
    self.left = left

    -- View: Figure or List, and what a click does.
    local view = Theme.CreateLabel(left, "small", "gilt")
    view:SetPoint("TOPLEFT", 2, -5)
    view:SetText(L["View:"])
    local figureButton = Widgets.CreateButton(left, L["Figure"], function() MyGear:SetView("figure") end,
        { width = math.max(60, Theme.TextWidth("normal", L["Figure"]) + 24), height = 20 })
    figureButton:SetPoint("LEFT", view, "RIGHT", 8, 0)
    local listButton = Widgets.CreateButton(left, L["List"], function() MyGear:SetView("list") end,
        { width = math.max(52, Theme.TextWidth("normal", L["List"]) + 24), height = 20 })
    listButton:SetPoint("LEFT", figureButton, "RIGHT", 6, 0)
    self.figureButton, self.listButton = figureButton, listButton
    if ns.GearRoad then
        local roadButton = Widgets.CreateButton(left, L["Road"], function() MyGear:SetView("road") end,
            { width = math.max(52, Theme.TextWidth("normal", L["Road"]) + 24), height = 20 })
        roadButton:SetPoint("LEFT", listButton, "RIGHT", 6, 0)
        self.roadButton = roadButton
    end
    local hint = Theme.CreateLabel(left, "tiny", "muted", "RIGHT")
    hint:SetPoint("TOPRIGHT", -4, -7)
    hint:SetText(L["Click a slot"])
    self.hint = hint

    self:BuildFigure()
    self:BuildList()
    self:BuildSide()
    if ns.GearRoad then ns.GearRoad:Build(body, VIEW_ROW) end

    -- The footer: how much waits on the left, the version on the right.
    local rule = Theme.CreateDivider(page, "border")
    rule:SetPoint("BOTTOMLEFT", PAD, FOOTER - 2)
    rule:SetPoint("BOTTOMRIGHT", -PAD, FOOTER - 2)
    local footer = Theme.CreateLabel(page, "small", "muted")
    footer:SetPoint("BOTTOMLEFT", PAD, 10)
    self.footer = footer
    local version = Theme.CreateLabel(page, "tiny", "dim", "RIGHT")
    version:SetPoint("BOTTOMRIGHT", -PAD, 10)
    version:SetText(ns.VersionLabel and ns.VersionLabel() or "")
    self.versionLabel = version

    self:PaintView()
    return page
end

--- The body sits under the cards, or at the top when none shows.
function MyGear:PlaceBody(cards)
    local top = (cards > 0 and (CARDS_TOP + CARD_HEIGHT + 10) or CARDS_TOP) + self:SwitchRoom()
    if self.bodyTop == top then return end
    self.bodyTop = top
    self.body:ClearAllPoints()
    self.body:SetPoint("TOPLEFT", self.page, "TOPLEFT", PAD, -top)
    self.body:SetPoint("BOTTOMRIGHT", self.page, "BOTTOMRIGHT", -PAD, FOOTER + 4)
end

--- "11 slots have an upgrade. 3 have a better enchant."
function MyGear.FooterText(state)
    if not state.found then return L["Looking for your next upgrade..."] end
    local parts = {}
    local slots, enchants = state.upgrades, state.enchants
    if slots == 1 then
        parts[#parts + 1] = L["1 slot has an upgrade."]
    elseif slots > 1 then
        parts[#parts + 1] = L.Format("%d slots have an upgrade.", slots)
    end
    if enchants == 1 then
        parts[#parts + 1] = L["1 has a better enchant."]
    elseif enchants > 1 then
        parts[#parts + 1] = L.Format("%d have a better enchant.", enchants)
    end
    if #parts == 0 then return L["Nothing on offer beats what you wear right now."] end
    return table.concat(parts, " ")
end

--------------------------------------------------------------------------------
-- Looking and drawing
--------------------------------------------------------------------------------

--- Draw the page from a scan (nil before the first one is in).
function MyGear:Present(found)
    if not self.page then return nil end
    self.lastFound = found
    local off = ns.OffSpec and ns.OffSpec:On() and self.offFound or nil
    local state = self:Read(found, off)
    self.state = state
    self.slot = self:ChooseSlot(state)
    self.painting = true
    pcall(self.PaintSwitch, self)
    self.painting = false
    -- Gear Road draws from its own scan (UI/GearRoad.lua).
    if self:View() == "road" then return state end
    self:PlaceBody(self:PaintCards(state))
    if self:View() == "list" then self:PaintList(state) else self:PaintFigure(state) end
    self:PaintSide(state)
    self.footer:SetText(MyGear.FooterText(state))
    return state
end

--- Look and draw: the finder's scan when it is up to date, else what
--- shows stays while a new one is made a slice per frame.
--- The Off Spec's scan (Logic/OffSpec.lua), kept while fresh, else made
--- a slice per frame and drawn when in. Nothing with Off Spec on None.
function MyGear:LookOff()
    if not (ns.OffSpec and ns.OffSpec:On()) then
        self.offFound = nil
        return
    end
    local kept = Finder:OffFound(0)
    if kept then
        self.offFound = kept
        return
    end
    self.offFound = self.offFound or Finder:OffLatest()
    Finder:ScanOff(0, function(off)
        if not MyGear:IsShown() then return end
        if off then MyGear.offFound = off end
        if MyGear.lastFound then MyGear:Present(MyGear.lastFound) end
    end)
end

function MyGear:Refresh()
    if not self:IsShown() then return nil end
    if self:View() == "road" then
        self.footer:SetText(L["Amber gear is for later. The road only lists gear your class can wear."])
        return ns.GearRoad:Refresh()
    end
    self:LookOff()
    local found = Finder:Fresh()
    if found then return self:Present(found) end
    if not self.state then self:Present(Finder.latest) end
    Finder:ScanInBackground(function(scan)
        if not MyGear:IsShown() then return end
        MyGear:Present(scan)
        -- Gear changed, or the item answers came in, while the scan ran:
        -- look once more. Each scan clears the mark, so this stops as
        -- soon as a scan runs with nothing changing under it.
        if Finder.stale and not Finder.background then MyGear:RefreshSoon() end
    end)
    return self.state
end

--- Once for a burst of events, and only while the page shows.
function MyGear:RefreshSoon()
    if not self:IsShown() or self.pending then return end
    self.pending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0.5, function()
            MyGear.pending = false
            MyGear:Refresh()
        end)
    else
        self.pending = false
        self:Refresh()
    end
end

--- Draw again from what was read: a tag or a button changed, no gear did.
function MyGear:Redraw()
    if self:IsShown() and self.state then self:PaintSide(self.state) end
end

function MyGear:OnTrackingChanged()
    self:Redraw()
end

function MyGear:OnUpgradeQuestChanged()
    self:Redraw()
end

--- Is the page on screen? Not while its window is closed or folded, so
--- nothing here runs then.
function MyGear:IsShown()
    local page = self.page
    if not Shown(page) then return false end
    local ok, visible = pcall(page.IsVisible, page)
    if ok and type(visible) == "boolean" then return visible end
    return true
end

--- Open on a slot (an Alt-click on the character sheet). The window is
--- already on My Gear, or about to be: the next draw starts on this slot.
function MyGear:Ask(slot)
    self.asked = slot
    -- A slot shows on the figure or the list, not on the road.
    if self:View() == "road" and self.page then self:SetView("figure") end
    if self:IsShown() and self.state and self.state.slots[slot] then
        self.asked = nil
        self:PickSlot(slot)
    end
end

function MyGear:Show()
    if not self.page then return end
    local was = self:IsShown()
    self.page:Show()
    -- A new look starts on the first slot with something better.
    if not was then self.slot = nil end
    self:Refresh()
end

function MyGear:Hide()
    if self.page then self.page:Hide() end
end

local EVENTS = {
    "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP", "QUEST_TURNED_IN", "TRAIT_CONFIG_UPDATED",
    "ZONE_CHANGED_NEW_AREA",
}

function MyGear:OnEnable()
    for _, event in ipairs(EVENTS) do
        ns.RegisterEvent(self, event, self.RefreshSoon)
    end
    -- A stack growing or shrinking changes no upgrade; gear coming or
    -- going does.
    ns.RegisterEvent(self, "BAG_UPDATE_DELAYED", function()
        if type(Finder.CarriedMoved) ~= "function" or Finder:CarriedMoved("myGear") then
            MyGear:RefreshSoon()
        end
    end)
    -- While the page is up the finder keeps asking the server about gear
    -- it has not seen, as it does for the old list, and the page looks
    -- again once the answers are in.
    local before = Finder.keepAsking
    Finder.keepAsking = function()
        if MyGear:IsShown() then return true end
        return type(before) == "function" and before() or false
    end
    if type(Finder.WatchAnswers) == "function" then
        Finder:WatchAnswers(function(again, done)
            if again or done then MyGear:RefreshSoon() end
        end)
    end
end

if ns.GearWindow then ns.GearWindow:AddPage("gear", MyGear) end
