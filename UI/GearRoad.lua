-- Blackthornes Equipment -- UI/GearRoad.lua
-- Gear Road, My Gear's third view (the owner said build it from the
-- mockup equipment-improve-4-gear-road, 2026-11-26).
--
-- The levels ahead on one gold line, from now to level 60. Each stop is a
-- level where something big opens: a heavier armor, a dungeon's gear, a
-- clutch of new pieces. A stop shows its best one or two pieces and how
-- many more it has; a click lists every piece under the line. The last
-- stop is the goal: the best piece for each slot before raids, with a bar
-- for the slots already done.
--
-- Nothing here judges gear. One finder scan that looks ahead to level 60
-- (Finder:Build with `ahead`, a slice per frame on the frame worker) is
-- read into stops once, and kept until the gear, the level or a setting
-- changes (the key Find Upgrades' Plan Ahead uses). The scan reuses the
-- kept verdicts and passes by gear the engine's gear list says this class
-- can never use. Clicking a stop only draws again. Nothing runs while the
-- view is hidden.
--
-- A slot's road keeps only the pieces that beat everything before them:
-- a helm at 44 shows only if it beats the best helm up to 43, so each
-- stop is a real step up.

local _, ns = ...
local L = ns.L

local Road = ns.NewModule("GearRoad")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Motion = ns.Motion
local Finder = ns.Finder

local MAX_LEVEL = 60
-- Stops between Now and the goal, at most.
local MIDDLE = 4
-- Pieces a stop shows on the line; the rest are counted.
local SHOWN = 2

local LINE_TOP = 6
local DOT = 30
local CARD_TOP = LINE_TOP + DOT + 4
local CARD_GAP = 8
local CARD_MIN = 120
local PAD = 10
local HEAD = 24
local ROW = 36
local ICON = 24
local BAR = 96
local GAIN = 64

Road.MAX_LEVEL = MAX_LEVEL
Road.MIDDLE = MIDDLE

local ARMOR, MAIL, PLATE = 4, 3, 4

local function Colored(key, text)
    local r, g, b = Theme.Unpack(key)
    return ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, text)
end

local function Shown(frame)
    if not frame then return false end
    local ok, shown = pcall(frame.IsShown, frame)
    return ok and shown == true
end

local function TextHeight(label, fallback)
    local ok, height = pcall(label.GetStringHeight, label)
    if ok and type(height) == "number" and height > 0 then return height end
    local text = label:GetText()
    return (text and text ~= "") and fallback or 0
end

--- Every slot the road walks, { slot, name }, in the character sheet's
--- order (UI/MainWindow.lua).
local function Slots()
    return ns.UI and ns.UI.SLOTS or {}
end

--- Does a piece wait on something (a level, a reputation, a crafter)?
--- Then it shows in amber, as everywhere else.
local function Later(pick)
    if ns.MyGear and ns.MyGear.Later then return ns.MyGear.Later(pick) end
    return (pick.needs or pick.at or pick.remote) and true or false
end

--- The percent a pick shows, or nil for an empty slot.
local function Percent(pick)
    return Finder.Shown and Finder.Shown(pick.result) or nil
end

local function GainText(pick)
    local result = pick.result or {}
    if result.empty then return L["empty slot"] end
    local shown = Percent(pick)
    if shown then return ("%+d%%"):format(shown) end
    return L["better"]
end

--- Best first: an empty slot (no percent), then the bigger percent.
local function Better(a, b)
    local pa, pb = Percent(a.pick), Percent(b.pick)
    if (pa == nil) ~= (pb == nil) then return pa == nil end
    if pa and pa ~= pb then return pa > pb end
    return (a.pick.itemID or 0) < (b.pick.itemID or 0)
end

--- The level a heavier armor opens for this class, and its kind: plate
--- for a warrior at 40, mail for a hunter at 40. Nil when none is ahead.
function Road.ArmorAhead(class, level)
    local Weights = ns.Weights
    if not (Weights and Weights.CanUse and class) then return nil end
    local best, kind
    for _, sub in ipairs({ MAIL, PLATE }) do
        local ok, can, at = pcall(Weights.CanUse, Weights, class, ARMOR, sub, "INVTYPE_CHEST")
        if ok and can and type(at) == "number" and at > level and at <= MAX_LEVEL then
            best, kind = at, sub
        end
    end
    return best, kind
end

--- An armor kind's name in the client's words, else ours.
function Road.ArmorName(sub)
    local info = _G.GetItemSubClassInfo or (_G.C_Item and _G.C_Item.GetItemSubClassInfo)
    if type(info) == "function" then
        local ok, name = pcall(info, ARMOR, sub)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    return sub == PLATE and L["Plate"] or L["Mail"]
end

--- Where a pick comes from, in a word or two: the dungeon's name, else
--- the kind of source ("Vendor", "Quest", "Crafted").
function Road.Short(pick)
    local source = pick.sources and pick.sources[1]
    if not source then return "" end
    if source.kind == "dungeon" and source.dungeon then
        return Finder.ShownZone and Finder.ShownZone(source.dungeon) or source.dungeon
    end
    return Finder.Label and Finder.Label(source) or ""
end

--------------------------------------------------------------------------------
-- Reading
--------------------------------------------------------------------------------

--- Only the From boxes of Find Upgrades: the road shows gear for later on
--- purpose, so Only What I Can Get Now and This Zone Only don't apply.
local function KindPass()
    local FinderUI = ns.FinderUI
    if not (FinderUI and FinderUI.KindFilter) then return nil end
    return FinderUI:KindFilter()
end

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

--- Each slot's road: the pieces, lowest level first, that beat every
--- piece before them. { { pick, slot, name, level }, ... } per slot.
function Road.Steps(found, level, pass, skipped)
    local steps = {}
    for _, entry in ipairs(Slots()) do
        local slot = entry[1]
        local picks = {}
        for _, whole in ipairs(found and found.all and found.all[slot] or {}) do
            local pick = not (skipped and skipped[whole.itemID]) and Passing(whole, pass) or nil
            if pick then picks[#picks + 1] = pick end
        end
        table.sort(picks, function(a, b)
            local la, lb = a.at or level, b.at or level
            if la ~= lb then return la < lb end
            if (a.gain or 0) ~= (b.gain or 0) then return (a.gain or 0) > (b.gain or 0) end
            return (a.itemID or 0) < (b.itemID or 0)
        end)
        local best, road = nil, {}
        for _, pick in ipairs(picks) do
            local gain = pick.gain or 0
            if best == nil or gain > best then
                best = gain
                road[#road + 1] = { pick = pick, slot = slot, name = entry[2], level = pick.at or level }
            end
        end
        steps[slot] = road
    end
    return steps
end

--- One stop: its level, what kind it is and its pieces, best first, one
--- per slot (the best that slot reaches by this stop).
local function NewStop(level, kind)
    return { level = level, kind = kind, steps = {}, bySlot = {} }
end

local function Add(stop, step)
    local had = stop.bySlot[step.slot]
    if had and (had.pick.gain or 0) >= (step.pick.gain or 0) then return end
    stop.bySlot[step.slot] = step
end

local function Finish(stop)
    local list = {}
    for _, entry in ipairs(Slots()) do
        local step = stop.bySlot[entry[1]]
        if step then list[#list + 1] = step end
    end
    table.sort(list, Better)
    stop.steps = list
    stop.bySlot = nil
    return stop
end

--- The road from a scan that looks ahead to level 60.
-- @return { level, stops = { stop, ... }, done, total } or nil before a scan.
--   A stop is { level, kind ("now", "armor", "dungeon", "level", "goal"),
--   name (the armor or dungeon), steps = { { pick, slot, name, level } } }.
function Road.Read(found, player, pass, skipped)
    if not (found and player) then return nil end
    local level = player.level or 1
    local steps = Road.Steps(found, level, pass, skipped)

    -- The levels ahead with a step, and how much each brings.
    local byLevel, score = {}, {}
    for _, road in pairs(steps) do
        for _, step in ipairs(road) do
            local at = step.level
            if at > level and at < MAX_LEVEL then
                byLevel[at] = byLevel[at] or {}
                table.insert(byLevel[at], step)
                score[at] = (score[at] or 0) + (Percent(step.pick) or 100)
            end
        end
    end
    local armorAt, armorKind = Road.ArmorAhead(player.class, level)
    local ranked = {}
    for at in pairs(byLevel) do
        ranked[#ranked + 1] = at
        if at == armorAt then score[at] = score[at] + 1e6 end
    end
    table.sort(ranked, function(a, b)
        if score[a] ~= score[b] then return score[a] > score[b] end
        return a < b
    end)
    local chosen = {}
    for index = 1, math.min(MIDDLE, #ranked) do chosen[#chosen + 1] = ranked[index] end
    table.sort(chosen)

    local stops = { NewStop(level, "now") }
    for _, at in ipairs(chosen) do stops[#stops + 1] = NewStop(at, "level") end
    local goal = level < MAX_LEVEL and NewStop(MAX_LEVEL, "goal") or nil

    -- Each step joins the first stop at or after its level; Now takes what
    -- can be worn today.
    for _, road in pairs(steps) do
        for _, step in ipairs(road) do
            local into
            if step.level <= level then
                into = stops[1]
            else
                for index = 2, #stops do
                    if stops[index].level >= step.level then
                        into = stops[index]
                        break
                    end
                end
            end
            if into then Add(into, step) end
            if goal then Add(goal, step) end
        end
    end

    -- What each stop is called: a heavier armor first, else the dungeon
    -- its best piece comes from, else its level.
    for index = 2, #stops do
        local stop = Finish(stops[index])
        if stop.level == armorAt then
            stop.kind, stop.name = "armor", Road.ArmorName(armorKind)
        else
            local top = stop.steps[1]
            local source = top and top.pick.sources and top.pick.sources[1]
            if source and source.kind == "dungeon" and source.dungeon and not source.raid then
                stop.kind, stop.name = "dungeon", Road.Short(top.pick)
            end
        end
    end
    Finish(stops[1])

    -- The goal: the best piece for each slot before raids. A slot with
    -- nothing ahead of what is worn is done.
    local total, done = 0, 0
    for _, entry in ipairs(Slots()) do
        total = total + 1
        if #(steps[entry[1]] or {}) == 0 then done = done + 1 end
    end
    if goal then
        Finish(goal)
        -- In slot order, as a list to work down.
        local order = {}
        for index, entry in ipairs(Slots()) do order[entry[1]] = index end
        table.sort(goal.steps, function(a, b) return (order[a.slot] or 0) < (order[b.slot] or 0) end)
        stops[#stops + 1] = goal
    end
    return { level = level, stops = stops, done = done, total = total }
end

--- A stop's heading on the line: "NOW", "PLATE OPENS", "ULDAMAN",
--- "LEVEL 44" or "YOUR GOAL".
function Road.Head(stop)
    if stop.kind == "now" then return L["NOW"] end
    if stop.kind == "goal" then return L["YOUR GOAL"] end
    if stop.kind == "armor" then return L.Format("%s OPENS", stop.name:upper()) end
    if stop.kind == "dungeon" then return stop.name:upper() end
    return L.Format("Level %d", stop.level):upper()
end

--- The heading over a stop's list: "LEVEL 40, PLATE OPENS".
function Road.ListHead(stop)
    if stop.kind == "now" then return L["NOW"] end
    if stop.kind == "level" then return Road.Head(stop) end
    return L.Format("Level %d", stop.level):upper() .. ", " .. Road.Head(stop)
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

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

--- One piece on a stop's card: its name, its gain with an arrow, and
--- where it comes from.
local function BuildPiece(card)
    local piece = {}
    piece.name = Theme.CreateLabel(card, "small", "text")
    piece.name:SetWordWrap(true)
    piece.arrow = UpArrow(card, 9)
    piece.gain = Theme.CreateLabel(card, "small", "good")
    piece.under = Theme.CreateLabel(card, "tiny", "muted")
    piece.under:SetWordWrap(true)
    return piece
end

function Road:BuildCard(index)
    local holder = self.frame
    local card = CreateFrame("Button", nil, holder)
    card.background = Theme.Fill(card, "glass")
    Theme.Border(card, "border")
    card.index = index

    local dot = CreateFrame("Frame", nil, holder)
    dot:SetSize(DOT, DOT)
    dot.background = Theme.Fill(dot, "glassActive")
    Theme.Border(dot, "metal")
    dot.number = Theme.CreateLabel(dot, "normal", "gilt", "CENTER")
    dot.number:SetPoint("CENTER", 0, 0)
    card.dot = dot

    card.head = Theme.CreateLabel(card, "tiny", "gilt")
    card.head:SetPoint("TOPLEFT", PAD, -PAD)
    card.head:SetWordWrap(true)
    card.pieces = { BuildPiece(card), BuildPiece(card) }
    card.more = Theme.CreateLabel(card, "small", "text")
    card.more:SetWordWrap(true)
    card.bar = CreateFrame("Frame", nil, card)
    card.bar:SetHeight(8)
    card.bar.background = Theme.Fill(card.bar, "glassAlt")
    Theme.Border(card.bar, "border")
    card.bar.fill = card.bar:CreateTexture(nil, "ARTWORK")
    card.bar.fill:SetPoint("TOPLEFT", 1, -1)
    card.bar.fill:SetPoint("BOTTOMLEFT", 1, 1)
    card.bar.fill:SetColorTexture(Theme.Unpack("accent"))
    card.bar:Hide()

    local function Light(p)
        local rest = rawget(card, "picked") and "glassActive" or "glass"
        card.background:SetColorTexture(Motion.Mix(rest, "glassHover", p))
        if not rawget(card, "picked") then
            Theme.SetBorderColor(card, p > 0.5 and "accent" or "border")
        end
    end
    card.Light = Light
    card:SetScript("OnEnter", function(self) Motion:Blend(self, "hover", 1, 0.12, Light) end)
    card:SetScript("OnLeave", function(self) Motion:Blend(self, "hover", 0, 0.18, Light) end)
    card:SetScript("OnClick", function(self) Road:Pick(self.index) end)
    card:Hide()
    dot:Hide()
    return card
end

--- A row of a stop's list: icon, name, slot, where, a bar for the gain,
--- the gain, and Make It My Quest. Dark glass.
function Road:BuildRow(index)
    local list = self.list
    local row = CreateFrame("Button", nil, list)
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

    row.icon = Theme.CreateItemIcon(row, ICON)
    row.icon:SetPoint("LEFT", 10, 0)
    row.item = Theme.CreateLabel(row, "normal", "text")
    row.item:SetPoint("LEFT", 10 + ICON + 10, 0)
    row.item:SetWordWrap(true)
    row.slotLabel = Theme.CreateLabel(row, "small", "muted")
    row.where = Theme.CreateLabel(row, "small", "muted")
    row.where:SetWordWrap(true)

    row.button = Widgets.CreateButton(row, L["Make It My Quest"], function()
        local pick = rawget(row, "pick")
        if not pick then return end
        local quest = ns.UpgradeQuest
        local can, why = true, nil
        if quest and quest.CanFollow then can, why = quest.CanFollow(pick) end
        if can then
            if ns.FinderUI then ns.FinderUI:Follow(pick) end
        elseif why then
            ns.Print(L.Format("Not a quest yet: %s", why))
        end
    end, { width = math.max(110, Theme.TextWidth("small", L["Make It My Quest"]) + 24), height = 22 })
    row.button:SetPoint("RIGHT", -10, 0)

    row.gain = Theme.CreateLabel(row, "normal", "good", "RIGHT")
    row.gain:SetPoint("RIGHT", row.button, "LEFT", -10, 0)
    row.gain:SetWidth(GAIN)
    row.arrow = UpArrow(row, 10)
    row.bar = CreateFrame("Frame", nil, row)
    row.bar:SetSize(BAR, 6)
    row.bar:SetPoint("RIGHT", row.gain, "LEFT", -10, 0)
    row.bar.background = Theme.Fill(row.bar, "glassAlt")
    row.bar.fill = row.bar:CreateTexture(nil, "ARTWORK")
    row.bar.fill:SetPoint("TOPLEFT")
    row.bar.fill:SetPoint("BOTTOMLEFT")

    local function Light(p)
        row.background:SetColorTexture(Motion.Mix(row.restKey, "glassHover", p))
        row.edge:SetColorTexture(Theme.Unpack("accentHi", p))
    end
    row:SetScript("OnEnter", function(self)
        Motion:Blend(self, "hover", 1, 0.12, Light)
        if ns.FinderUI then ns.FinderUI.ShowRowTooltip(self) end
    end)
    row:SetScript("OnLeave", function(self)
        Motion:Blend(self, "hover", 0, 0.18, Light)
        GameTooltip:Hide()
    end)
    -- The clicks every gear row takes: follow, link, try on, the menu.
    row:SetScript("OnClick", function(self, mouse)
        if ns.FinderUI then ns.FinderUI.RowClicked(self, mouse) end
    end)
    if row.RegisterForClicks then row:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    row:Hide()
    return row
end

--- Build the view inside `parent` (My Gear's body), under its View row.
function Road:Build(parent, top)
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -top)
    frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    frame:Hide()
    self.frame = frame

    -- The gold line the stops sit on.
    local line = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
    line:SetHeight(2)
    line:SetPoint("TOPLEFT", 0, -(LINE_TOP + DOT / 2 - 1))
    line:SetPoint("TOPRIGHT", 0, -(LINE_TOP + DOT / 2 - 1))
    line:SetColorTexture(Theme.Unpack("accent", 0.8))
    self.line = line

    self.cards = {}
    for index = 1, MIDDLE + 2 do self.cards[index] = self:BuildCard(index) end

    -- The list under the line.
    local list = CreateFrame("Frame", nil, frame)
    list:SetPoint("BOTTOMLEFT", 0, 0)
    list:SetPoint("BOTTOMRIGHT", 0, 0)
    self.list = list
    local head = CreateFrame("Frame", nil, list)
    head:SetHeight(HEAD)
    head:SetPoint("TOPLEFT")
    head:SetPoint("TOPRIGHT")
    Theme.Fill(head, "glassActive")
    head.label = Theme.CreateLabel(head, "tiny", "gilt")
    head.label:SetPoint("LEFT", 12, 0)
    self.listHead = head
    self.empty = Theme.CreateLabel(list, "normal", "muted")
    self.empty:SetPoint("TOPLEFT", 12, -(HEAD + 12))
    self.empty:SetWordWrap(true)
    self.rows = {}
    self.offset = 0
    if list.EnableMouseWheel then list:EnableMouseWheel(true) end
    list:SetScript("OnMouseWheel", function(_, delta)
        Road:Scroll(delta > 0 and -1 or 1)
    end)
    return frame
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

local function Width(frame, fallback)
    local ok, width = pcall(frame.GetWidth, frame)
    if ok and type(width) == "number" and width > 50 then return width end
    return fallback
end

--- Fill one piece on a card and lay it under `anchor`.
local function SetPiece(piece, step, anchor, width, card)
    if not step then
        piece.name:Hide()
        piece.arrow:Hide()
        piece.gain:Hide()
        piece.under:Hide()
        return anchor
    end
    local pick = step.pick
    local tone = Later(pick) and "warn" or "good"
    piece.name:SetWidth(width)
    piece.name:SetText(ns.Items.ShowLink(pick.link))
    piece.name:ClearAllPoints()
    piece.name:SetPoint("TOPLEFT", anchor, anchor == card.head and "BOTTOMLEFT" or "BOTTOMLEFT", 0, -6)
    piece.name:Show()
    piece.arrow:ClearAllPoints()
    piece.arrow:SetPoint("TOPLEFT", piece.name, "BOTTOMLEFT", 0, -3)
    Tint(piece.arrow, tone)
    piece.arrow:Show()
    piece.gain:SetText(GainText(pick))
    piece.gain:SetTextColor(Theme.Unpack(tone))
    piece.gain:ClearAllPoints()
    piece.gain:SetPoint("LEFT", piece.arrow, "RIGHT", 3, 0)
    piece.gain:Show()
    piece.under:SetWidth(width)
    piece.under:SetText(Road.Short(pick))
    piece.under:ClearAllPoints()
    piece.under:SetPoint("TOPLEFT", piece.arrow, "BOTTOMLEFT", 0, -3)
    piece.under:Show()
    return piece.under
end

local function CardHeight(card)
    local height = PAD + TextHeight(card.head, 10)
    for _, piece in ipairs(card.pieces) do
        if Shown(piece.name) then
            height = height + 6 + TextHeight(piece.name, 12) + 3 + 12 + 3 + TextHeight(piece.under, 10)
        end
    end
    if Shown(card.more) then height = height + 6 + TextHeight(card.more, 12) end
    if Shown(card.bar) then height = height + 8 + 8 end
    return height + PAD
end

function Road:PaintCard(card, stop, x, width)
    card.stop = stop
    card.dot.number:SetText(tostring(stop.level))
    card.dot:ClearAllPoints()
    card.dot:SetPoint("TOP", self.frame, "TOPLEFT", x + width / 2, -LINE_TOP)
    card.dot:Show()
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, -CARD_TOP)
    card:SetWidth(width)
    local inner = width - PAD * 2
    card.head:SetWidth(inner)
    card.head:SetText(Road.Head(stop))

    local anchor = card.head
    card.bar:Hide()
    if stop.kind == "goal" then
        for _, piece in ipairs(card.pieces) do SetPiece(piece, nil, anchor, inner, card) end
        local road = self.road
        card.more:SetWidth(inner)
        card.more:SetText(L["Best gear before raids"] .. "\n"
            .. Colored("muted", L.Format("%d of %d slots done", road.done, road.total)))
        card.more:ClearAllPoints()
        card.more:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
        card.more:Show()
        card.bar:ClearAllPoints()
        card.bar:SetPoint("TOPLEFT", card.more, "BOTTOMLEFT", 0, -8)
        card.bar:SetWidth(inner)
        local share = road.total > 0 and road.done / road.total or 0
        card.bar.fill:SetWidth(math.max(1, (inner - 2) * share))
        card.bar.fill:SetShown(share > 0)
        card.bar:Show()
    else
        for index, piece in ipairs(card.pieces) do
            anchor = SetPiece(piece, index <= SHOWN and stop.steps[index] or nil, anchor, inner, card)
        end
        local more = #stop.steps - SHOWN
        card.more:ClearAllPoints()
        card.more:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
        card.more:SetWidth(inner)
        if #stop.steps == 0 then
            card.more:SetText(Colored("muted", L["Nothing on offer beats what you wear right now."]))
            card.more:Show()
        elseif more > 0 then
            card.more:SetText(L.Format("%d more pieces", more))
            card.more:Show()
        else
            card.more:SetText("")
            card.more:Hide()
        end
    end
    card:Show()
end

--- Light the picked stop's card.
function Road:PaintPicked()
    for index, card in ipairs(self.cards) do
        local picked = index == self.picked and Shown(card)
        card.picked = picked
        card.background:SetColorTexture(Theme.Unpack(picked and "glassActive" or "glass"))
        Theme.SetBorderColor(card, picked and "accentHi" or "border")
    end
end

--- Draw the line and its stops from the road (nil while the scan runs).
function Road:Paint()
    if not self.frame then return end
    local road = self.road
    for _, card in ipairs(self.cards) do
        card:Hide()
        card.dot:Hide()
    end
    if not road then
        self.line:Hide()
        self.list:ClearAllPoints()
        self.list:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, 0)
        self.list:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", 0, 0)
        self.listHead:Hide()
        self.empty:SetText(L["Looking for your next upgrade..."])
        self.empty:Show()
        for _, row in ipairs(self.rows) do row:Hide() end
        return
    end
    self.line:Show()
    self.listHead:Show()
    local total = Width(self.frame, 1004)
    local count = #road.stops
    local width = math.floor((total - CARD_GAP * (count - 1)) / count)
    local tallest = CARD_MIN
    for index, stop in ipairs(road.stops) do
        local card = self.cards[index]
        self:PaintCard(card, stop, (index - 1) * (width + CARD_GAP), width)
        tallest = math.max(tallest, CardHeight(card))
    end
    tallest = math.ceil(tallest)
    for index = 1, count do self.cards[index]:SetHeight(tallest) end
    if not (self.picked and self.picked <= count) then self.picked = 1 end
    self:PaintPicked()

    self.list:ClearAllPoints()
    self.list:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, -(CARD_TOP + tallest + 10))
    self.list:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", 0, 0)
    self:PaintList()
end

--- A stop clicked: its pieces fill the list. Nothing is read again.
function Road:Pick(index)
    if not (self.road and self.road.stops[index]) then return end
    self.picked = index
    self.offset = 0
    self:PaintPicked()
    self:PaintList()
end

function Road:Scroll(step)
    local stop = self.road and self.road.stops[self.picked or 1]
    if not stop then return end
    local room = self:RowsInView()
    local most = math.max(0, #stop.steps - room)
    self.offset = math.max(0, math.min(most, (self.offset or 0) + step))
    self:PaintList()
end

function Road:RowsInView()
    local ok, height = pcall(self.list.GetHeight, self.list)
    if not ok or type(height) ~= "number" or height <= HEAD then height = HEAD + ROW * 7 end
    return math.max(1, math.floor((height - HEAD) / ROW))
end

--- The picked stop's pieces, a row each, in dark glass.
function Road:PaintList()
    local stop = self.road and self.road.stops[self.picked or 1]
    if not stop then return end
    self.listHead.label:SetText(Road.ListHead(stop))
    local steps = stop.steps
    self.empty:SetShown(#steps == 0)
    self.empty:SetText(L["Nothing on offer beats what you wear right now."])
    local width = Width(self.list, Width(self.frame, 1004))
    local room = self:RowsInView()
    local top = 0
    for _, step in ipairs(steps) do
        local percent = Percent(step.pick)
        if percent and percent > top then top = percent end
    end
    local offset = math.max(0, math.min(self.offset or 0, math.max(0, #steps - room)))
    self.offset = offset
    for index = 1, math.max(room, #self.rows) do
        local step = index <= room and steps[offset + index] or nil
        local row = self.rows[index]
        if step and not row then
            row = self:BuildRow(index)
            self.rows[index] = row
        end
        if row then self:FillRow(row, step, index, width, top) end
    end
end

function Road:FillRow(row, step, index, width, top)
    if not step then
        row.pick = nil
        row:Hide()
        return
    end
    local pick = step.pick
    row.pick = {
        link = pick.link, sources = pick.sources, itemID = pick.itemID, needs = pick.needs,
        result = pick.result, roll = pick.roll, at = pick.at, gain = pick.gain,
    }
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", self.list, "TOPLEFT", 0, -(HEAD + (index - 1) * ROW))
    row:SetPoint("TOPRIGHT", self.list, "TOPRIGHT", 0, -(HEAD + (index - 1) * ROW))
    Theme.SetItemIcon(row.icon, pick.link)

    local tone = Later(pick) and "warn" or "good"
    local right = 10 + Width(row.button, 120) + 10 + GAIN + 10 + BAR + 12
    local left = 10 + ICON + 10
    local nameWidth = math.floor((width - left - right) * 0.34)
    local slotWidth = 90
    row.item:SetWidth(nameWidth)
    row.item:SetText(ns.Items.ShowLink(pick.link))
    row.slotLabel:ClearAllPoints()
    row.slotLabel:SetPoint("LEFT", row, "LEFT", left + nameWidth + 10, 0)
    row.slotLabel:SetWidth(slotWidth)
    row.slotLabel:SetText(step.name or "")
    row.where:ClearAllPoints()
    row.where:SetPoint("LEFT", row, "LEFT", left + nameWidth + 10 + slotWidth + 10, 0)
    row.where:SetWidth(math.max(60, width - right - (left + nameWidth + 10 + slotWidth + 10)))
    local source = pick.sources and pick.sources[1]
    local where = source and ns.FinderUI and ns.FinderUI.SourceLine(source) or ""
    if pick.needs then
        where = Colored("warn", L.Format("Needs %s with %s", pick.needs.standing, pick.needs.faction)) .. "  " .. where
    elseif pick.at then
        where = Colored("warn", L.Format("You can wear it from level %d", pick.at)) .. "  " .. where
    end
    row.where:SetText(where)

    local percent = Percent(pick)
    local share = top > 0 and percent and percent / top or 1
    row.bar.fill:SetWidth(math.max(1, BAR * math.min(1, share)))
    row.bar.fill:SetColorTexture(Theme.Unpack(tone))
    row.gain:SetText(GainText(pick))
    row.gain:SetTextColor(Theme.Unpack(tone))
    Tint(row.arrow, tone)
    row.arrow:ClearAllPoints()
    row.arrow:SetPoint("RIGHT", row.gain, "RIGHT",
        -(math.min(GAIN, Theme.TextWidth("normal", row.gain:GetText() or "")) + 4), 0)

    local quest = ns.UpgradeQuest
    local can = true
    if quest and quest.CanFollow then can = quest.CanFollow(pick) and true or false end
    if row.button.SetDimmed then row.button:SetDimmed(not can) end
    row:Show()
end

--------------------------------------------------------------------------------
-- Looking
--------------------------------------------------------------------------------

--- What the kept road was read from: how far ahead, the verdicts' key and
--- every change since (the key Find Upgrades' Plan Ahead keeps its scan by).
function Road:Key(ahead)
    return ahead .. "|" .. tostring(Finder:JudgeKey()) .. "|" .. tostring(Finder.changes or 0)
end

function Road:IsShown()
    local frame = self.frame
    if not Shown(frame) then return false end
    if ns.MyGear and not ns.MyGear:IsShown() then return false end
    local ok, visible = pcall(frame.IsVisible, frame)
    if ok and type(visible) == "boolean" then return visible end
    return true
end

--- Read the scan into stops and draw.
function Road:Present(found)
    local player = found and found.player or Finder:Player()
    local quest = ns.UpgradeQuest
    local skipped = quest and quest.Skipped and quest:Skipped() or {}
    self.road = Road.Read(found, player, KindPass(), skipped)
    self:Paint()
    return self.road
end

--- Look and draw: the kept scan while nothing changed, else one made a
--- slice per frame while what shows stays.
function Road:Refresh()
    if not self:IsShown() then return nil end
    local player = Finder:Player()
    if not player then return self:Present(nil) end
    local ahead = math.max(0, MAX_LEVEL - (player.level or MAX_LEVEL))
    local key = self:Key(ahead)
    -- Kept: read again (a From box may have changed), judging nothing.
    if self.found and self.key == key then return self:Present(self.found) end
    if not self.road then self:Present(nil) end
    if self.making == key then return self.road end
    self.making = key
    local job = {}
    self.job = job
    ns.Worker:Run(function(pause) return Finder:Build(nil, ahead, pause, true) end, function(found)
        if Road.job ~= job then return end
        Road.job, Road.making = nil, nil
        if found then Road.found, Road.key = found, key end
        if not Road:IsShown() then return end
        Road:Present(found)
        -- Something moved while it ran: look once more.
        if Road:Key(ahead) ~= key and ns.MyGear then ns.MyGear:RefreshSoon() end
    end)
    return self.road
end

function Road:Show()
    if not self.frame then return end
    self.frame:Show()
    self:Refresh()
end

function Road:Hide()
    if self.frame then self.frame:Hide() end
end
