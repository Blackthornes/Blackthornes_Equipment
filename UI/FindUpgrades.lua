-- Blackthornes Equipment -- UI/FindUpgrades.lua
-- Find Upgrades, the Equipment window's second tab (rework step 3, the
-- owner approved the mockup 2026-11-22): every upgrade to go and get, for
-- every slot, in one list that sorts and narrows. The filters stay down
-- the left. A click on a row fills the sheet on the right with every place
-- to get that item and what can be done with it, in place of the old
-- list's long hover.
--
-- It takes the place of the gear list of the old Upgrades tab
-- (UI/FinderWindow.lua). The filters are the same saved choices
-- (`finderSourcesOff`, `finderGetNow`, `finderZoneOnly`, `finderAhead`,
-- `soloQuestsOnly`, `questLevelsAbove`), set through the same calls, so
-- the upgrade quest and the character sheet still agree with what shows
-- here. New: `findSlot`, the slot the list is narrowed to (nil for all).
--
-- Nothing here judges gear. The page reads the finder's scan
-- (Logic/Finder.lua), made a slice per frame, and every click, sort, tick
-- box and letter typed only sorts or narrows what was read. Only the rows
-- in view are drawn. Nothing runs while the page is hidden.

local _, ns = ...
local L = ns.L

local Find = ns.NewModule("FindUpgrades")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Finder = ns.Finder

local PAD = 18
local WIDTH = 1040
-- Judge Gear As and Find, along the top.
local TOP_ROW = 34
local FOOTER = 30
local GAP = 10
-- The filters' column at its least and most; it grows to hold its
-- longest words (German runs longer).
local LEFT_MIN, LEFT_MAX = 184, 236
-- The side sheet.
local SHEET = 270

-- The list: its headings, and a row at its shortest. A row grows to show
-- its words in full.
local HEAD = 22
local ROW_MIN = 30
local ICON = 22
local TEXT_X = ICON + 14
local SCROLL = 10
local SLOT_WIDTH = 70
local WHERE_WIDTH = 124
local LEVEL_WIDTH = 38
local GAIN_WIDTH = 78
-- Each of the two gain columns (MAIN and OFF) while an Off Spec is picked.
local DUAL_GAIN = 62
local CELL_GAP = 6
-- Rows built: more than the tallest list holds at their shortest.
local ROWS = 22
-- Lines the mouse wheel moves.
local WHEEL = 3

-- The sheet lists this many places at most, then "and N more".
local SHEET_SOURCES = 12

local MAIN_HAND = 16
-- The Reputation box's key in `finderSourcesOff` (FinderUI.REP).
local REP = "rep"
local HIDDEN_STRIP = 28
local BAR_WIDTH = 56

local function Colored(key, text)
    local r, g, b = Theme.Unpack(key)
    return ("|cff%02x%02x%02x%s|r"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
        math.floor(b * 255 + 0.5), text)
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
    local lines = 0
    for part in (text .. "\n"):gmatch("(.-)\n") do
        lines = lines + math.max(1, math.ceil(Theme.TextWidth(size, part) / math.max(1, width)))
    end
    return lines * ((Theme.sizes[size] or 10) + 2)
end

--- The house's small triangle, for a sorted heading and a gain.
local function Arrow(parent, size)
    local arrow = parent:CreateTexture(nil, "OVERLAY")
    if ns.Titanforged then arrow:SetTexture(ns.Titanforged.MEDIA .. "SortArrow") end
    arrow:SetSize(size, size)
    pcall(arrow.SetTexCoord, arrow, 0, 1, 1, 0)
    return arrow
end

local function Tip(frame, title, words, anchor)
    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, anchor or "ANCHOR_RIGHT")
        GameTooltip:AddLine(title, Theme.Unpack("accent"))
        if words then GameTooltip:AddLine(words, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

--------------------------------------------------------------------------------
-- The saved choices
--------------------------------------------------------------------------------

--- The slots a list can be narrowed to: { slot, name, the second slot }
--- (UI/FinderWindow.lua), both rings one line and both trinkets.
local function Groups()
    return ns.FinderUI and ns.FinderUI.SLOT_GROUPS or {}
end

--- The slot the list keeps to (a group's first slot), or nil for every
--- slot. Saved account wide as `findSlot`.
function Find:Slot()
    local saved = tonumber(ns.db and ns.db.findSlot)
    if not saved then return nil end
    for _, group in ipairs(Groups()) do
        if group[1] == saved then return saved end
    end
    return nil
end

--- Narrow the list to a slot (either ring for Rings), or nil for all.
function Find:SetSlot(slot)
    if not ns.db then return end
    local FinderUI = ns.FinderUI
    slot = tonumber(slot)
    ns.db.findSlot = slot and FinderUI and FinderUI.GROUP_OF[slot] or nil
    self.offset = 0
    if self.slotChoice then self.slotChoice:SetValue(self:SlotIndex(), true) end
    self:Narrow()
end

--- The slot drop-down's place: 0 for All Slots, else the group's.
function Find:SlotIndex()
    local slot = self:Slot()
    for index, group in ipairs(Groups()) do
        if group[1] == slot then return index end
    end
    return 0
end

function Find.SlotText(index)
    local group = Groups()[index]
    return group and group[2] or L["All Slots"]
end

--- How many levels ahead the list plans (the old window's `finderAhead`).
function Find:Ahead()
    return ns.FinderUI and ns.FinderUI:Ahead() or 0
end

--- "Up to my level", "Up to 4 Above Mine" or "Any".
function Find.QuestLevelsText(value)
    if (value or 0) >= Finder.QUEST_LEVELS_ANY then return L["Any"] end
    if (value or 0) <= 0 then return L["Up to my level"] end
    return L.Format("Up to %d Above Mine", value)
end

--------------------------------------------------------------------------------
-- Reading
--------------------------------------------------------------------------------

--- Lay a scan out as one line an upgrade, every slot together: read once
--- a scan, and every sort and filter after reads this. Ignored upgrades
--- are left out. A piece shown under two slots (a one-hander that beats
--- both hands) keeps a line for each, since its gain differs.
function Find:Read(found, off)
    local state = { found = found, off = off, lines = {}, ignored = 0 }
    if not found then return state end
    local quest = ns.UpgradeQuest
    local skipped = quest and quest:Skipped() or {}
    local all = type(found.all) == "table" and found.all or found.slots or {}
    -- The Off Spec's scan (Logic/OffSpec.lua): its picks join the Main
    -- Spec's line for the same item, or make a line of their own.
    local offAll = type(off) == "table" and (type(off.all) == "table" and off.all or off.slots) or nil
    for order, group in ipairs(Groups()) do
        local seen, byItem = {}, {}
        for _, slot in ipairs({ group[1], group[3] }) do
            for _, pick in ipairs(all[slot] or {}) do
                if not seen[pick.itemID] then
                    seen[pick.itemID] = true
                    if skipped[pick.itemID] then
                        state.ignored = state.ignored + 1
                    else
                        local line = {
                            pick = pick, main = pick, group = group[1], slotName = group[2], order = order,
                            key = pick.itemID .. ":" .. group[1], index = #state.lines + 1,
                        }
                        byItem[pick.itemID] = line
                        state.lines[#state.lines + 1] = line
                    end
                end
            end
        end
        if offAll then
            local offSeen = {}
            for _, slot in ipairs({ group[1], group[3] }) do
                for _, pick in ipairs(offAll[slot] or {}) do
                    if not offSeen[pick.itemID] and not skipped[pick.itemID] then
                        offSeen[pick.itemID] = true
                        local line = byItem[pick.itemID]
                        if line then
                            line.off = pick
                        elseif not seen[pick.itemID] then
                            line = {
                                pick = pick, off = pick, group = group[1], slotName = group[2], order = order,
                                key = pick.itemID .. ":" .. group[1], index = #state.lines + 1,
                            }
                            byItem[pick.itemID] = line
                            state.lines[#state.lines + 1] = line
                        end
                    end
                end
            end
        end
    end
    -- Two one-handers (or one and a shield) that beat the two-hander worn
    -- (Finder:MakePairs): one line each, under the main hand.
    local mainOrder = 0
    for order, group in ipairs(Groups()) do
        if group[1] == MAIN_HAND then mainOrder = order end
    end
    for _, pick in ipairs(type(found.pairs) == "table" and found.pairs or {}) do
        local partner = pick.pair
        if partner and not skipped[pick.itemID] and not skipped[partner.itemID] then
            state.lines[#state.lines + 1] = {
                pick = pick, main = pick, pair = partner, group = MAIN_HAND, slotName = L["Both Hands"],
                order = mainOrder, key = "pair:" .. pick.itemID .. ":" .. partner.itemID,
                index = #state.lines + 1,
            }
        end
    end
    return state
end

--- Is an Off Spec picked and its list in? Then the list shows two gain
--- columns, unless Show picks one.
function Find:Dual()
    return self.state ~= nil and self.state.off ~= nil
end

--- What Show picks: "both", "main" or "off". "both" while no Off Spec is
--- picked. Kept for the session.
function Find:ShowWhich()
    if not (ns.OffSpec and ns.OffSpec:On()) then return "both" end
    return self.show or "both"
end

function Find:SetShow(which)
    self.show = which
    self.offset = 0
    self:SyncShow()
    self:Narrow()
end

--- A line's words, in small letters, for the Find box: the item, and each
--- place's boss, vendor, dungeon, quest, zone and profession. Made once.
function Find.Hay(line)
    if line.hay then return line.hay end
    local FinderUI = ns.FinderUI
    local parts = { FinderUI.ItemName(line.pick) }
    local all = {}
    for _, source in ipairs(line.pick.sources or {}) do all[#all + 1] = source end
    if line.pair then
        parts[#parts + 1] = FinderUI.ItemName(line.pair)
        for _, source in ipairs(line.pair.sources or {}) do all[#all + 1] = source end
    end
    for _, source in ipairs(all) do
        for _, key in ipairs({ "name", "dungeon", "zone", "title", "profession" }) do
            local value = source[key]
            if type(value) == "string" then
                parts[#parts + 1] = value
                if key == "zone" or key == "dungeon" then
                    local shown = Finder.ShownZone(value)
                    if shown and shown ~= value then parts[#parts + 1] = shown end
                end
            end
        end
    end
    line.hay = table.concat(parts, "\n"):lower()
    return line.hay
end

--- The lines the filters let through, each with the sources that pass as
--- `sources`, and how many upgrades each kind of source has.
-- @return shown lines (unsorted), counts by kind
function Find:Filtered(state)
    local FinderUI, quest = ns.FinderUI, ns.UpgradeQuest
    local here = FinderUI:Here(state.found)
    local inZone = quest and quest.InZone
    local getNow = FinderUI:GetNowOnly()
    local slot = self:Slot()
    local find = self.find and self.find ~= "" and self.find or nil
    local on, counts = {}, {}
    for _, entry in ipairs(FinderUI.SOURCE_BOXES) do
        on[entry[1]] = FinderUI:SourceOn(entry[1])
        counts[entry[1]] = 0
    end
    local repOn = FinderUI:SourceOn(REP)
    counts[REP] = 0
    -- Rows the Reputation box hides, for the line under the list.
    self.repHidden = 0

    local shown = {}
    -- A pair's partner needs a place the filters let through too.
    local function Passes(source, pick)
        return (not getNow or FinderUI.GetsNow(source, pick))
            and (not here or not inZone or inZone(source, here))
            and on[FinderUI.SourceKind(source)] ~= false
            and (source.kind ~= "auction" or ns.AuctionGear:Affords(source))
    end
    for _, line in ipairs(state.lines) do
        local pick = line.pick
        local sources, kinds = {}, {}
        if line.pair then
            local partner = {}
            for _, source in ipairs(line.pair.sources or {}) do
                if Passes(source, pick) then partner[#partner + 1] = source end
            end
            line.pairSources = partner
        end
        for _, source in ipairs(pick.sources or {}) do
            if (not getNow or FinderUI.GetsNow(source, pick))
                and (not here or not inZone or inZone(source, here)) then
                local kind = FinderUI.SourceKind(source)
                if not kinds[kind] then
                    kinds[kind] = true
                    counts[kind] = (counts[kind] or 0) + 1
                end
                -- The auction house: only what you can pay for, within
                -- Auction Price.
                if on[kind] ~= false and (kind ~= "auction" or ns.AuctionGear:Affords(source)) then
                    sources[#sources + 1] = source
                end
            end
        end
        if line.pair and #line.pairSources == 0 then sources = {} end
        line.sources = sources
        if pick.rep and next(kinds) then counts[REP] = counts[REP] + 1 end
        if pick.rep and not repOn then sources = {} end
        local which = self:ShowWhich()
        local wanted = which == "both" or (which == "main" and line.main ~= nil)
            or (which == "off" and line.off ~= nil)
        if wanted and (not slot or line.group == slot)
            and (not find or Find.Hay(line):find(find, 1, true)) then
            if #sources > 0 then
                shown[#shown + 1] = line
            elseif pick.rep and not repOn and #line.sources > 0 then
                self.repHidden = self.repHidden + 1
            end
        end
    end
    return shown, counts
end

--- What a line sorts by under a heading; nil sorts last.
function Find.SortValue(line, key)
    local FinderUI = ns.FinderUI
    local pick = line.pick
    if key == "item" then return FinderUI.ItemName(pick):lower() end
    if key == "slot" then return line.order end
    if key == "where" then
        local where = FinderUI.WhereOf(line)
        return where and where:lower() or nil
    end
    if key == "level" then
        if line.level == nil then line.level = FinderUI.LevelOf(pick) or false end
        return line.level or nil
    end
    -- MAIN sorts by the Main Spec's gain, OFF by the Off Spec's; with Show
    -- on Off Spec the one column is the Off Spec's.
    local lead = line.main
    if key == "off" or (line.showOff and key == "gain") then lead = line.off end
    if not (line.main or line.off) then lead = pick end
    if not lead then return nil end
    if lead.result and lead.result.empty then return math.huge end
    return lead.result and Finder.Shown(lead.result) or nil
end

--- `lines` in the order the list shows them: by the heading clicked, the
--- biggest gain first until one is. Gear that waits on a standing comes
--- last under Gain, as the mockup has it.
function Find:Sorted(lines)
    local key, flip = self.sortKey or "gain", self.sortFlip == true
    local keyed = {}
    for index, line in ipairs(lines) do
        line.showOff = self:ShowWhich() == "off" or nil
        keyed[index] = { line = line, value = Find.SortValue(line, key),
            waits = (key == "gain" or key == "off") and line.pick.needs ~= nil }
    end
    table.sort(keyed, function(a, b)
        if a.waits ~= b.waits then return not a.waits end
        local va, vb = a.value, b.value
        if va ~= vb then
            if va == nil then return false end
            if vb == nil then return true end
            if key == "gain" or key == "off" then return va > vb end
            return va < vb
        end
        return a.line.index < b.line.index
    end)
    local sorted = {}
    for index, entry in ipairs(keyed) do
        sorted[flip and (#keyed - index + 1) or index] = entry.line
    end
    return sorted
end

--- A heading clicked: sort by it; a second click turns it round, and a
--- third goes back to the biggest gain first.
function Find:SortBy(key)
    if (self.sortKey or "gain") ~= key then
        self.sortKey, self.sortFlip = key, false
    elseif not self.sortFlip then
        self.sortFlip = true
    else
        self.sortKey, self.sortFlip = nil, false
    end
    self.offset = 0
    self:Narrow()
end

--------------------------------------------------------------------------------
-- The filters, down the left
--------------------------------------------------------------------------------

--- Every source ticked, every slot, any zone and nothing typed: the Show
--- All button. The quest switches stay: the upgrade quest shares them.
function Find:ShowAll()
    local FinderUI = ns.FinderUI
    if not (ns.db and FinderUI) then return end
    ns.db.finderSourcesOff = nil
    ns.db.finderGetNow = false
    ns.db.finderZoneOnly = false
    ns.db.findSlot = nil
    ns.db.findAuctionMost = nil
    self.find = nil
    if self.findBox then self.findBox:SetText("") end
    self.offset = 0
    self:SyncFilters()
    self:Narrow()
    FinderUI.TellQuest()
end

--- The tick boxes and drop-downs as the saved choices stand.
function Find:SyncFilters()
    local FinderUI = ns.FinderUI
    if not (self.page and FinderUI) then return end
    for _, box in ipairs(self.sourceBoxes) do box:SetChecked(FinderUI:SourceOn(box.kind)) end
    self.zoneBox:SetChecked(FinderUI:ZoneOnly())
    self.soloBox:SetChecked(Finder:SoloOnly())
    self.nowBox:SetChecked(FinderUI:GetNowOnly())
    self.slotChoice:SetValue(self:SlotIndex(), true)
    self.questLevels:SetValue(FinderUI:QuestLevelsValue(), true)
    self.aheadChoice:SetValue(self:Ahead(), true)
    if self.mostChoice then self.mostChoice:SetValue(Find.MostIndex(), true) end
end

local function Heading(parent, text, y)
    local label = Theme.CreateLabel(parent, "tiny", "gilt")
    label:SetPoint("TOPLEFT", 12, y)
    label:SetText(text)
    return label
end

--- How wide the filters' column must be for its longest words.
local function LeftWidth()
    local FinderUI = ns.FinderUI
    local widest = 0
    local function Take(size, text, extra)
        widest = math.max(widest, Theme.TextWidth(size, text) + extra)
    end
    for _, entry in ipairs(FinderUI.SOURCE_BOXES) do Take("small", entry[2], 24 + 40) end
    Take("small", L["Reputation"], 24 + 40)
    for _, text in ipairs({ L["This Zone Only"], L["Solo Quests Only"], L["Only What I Can Get Now"] }) do
        Take("small", text, 24)
    end
    for value = 0, Finder.QUEST_LEVELS_ANY do Take("small", Find.QuestLevelsText(value), 30) end
    for index = 0, #Groups() do Take("small", Find.SlotText(index), 30) end
    return math.max(LEFT_MIN, math.min(LEFT_MAX, math.ceil(widest) + 24))
end

function Find:BuildFilters(width)
    local FinderUI = ns.FinderUI
    local panel = Theme.CreatePanel(self.body, "panel", "border")
    panel:SetPoint("TOPLEFT", 0, 0)
    panel:SetPoint("BOTTOMLEFT", 0, 0)
    panel:SetWidth(width)
    Theme.Recess(panel)
    self.filters = panel
    local inner = width - 24

    -- FROM: a tick box for each kind of source, with how many it has.
    local y = -10
    Heading(panel, L["FROM"], y)
    y = y - 18
    self.sourceBoxes, self.sourceCounts = {}, {}
    for _, entry in ipairs(FinderUI.SOURCE_BOXES) do
        local kind = entry[1]
        -- The Auction House box needs Tradeskills' scans; without it, no box.
        if kind == "auction" and not Find.AuctionOn() then
        else
        local box = Widgets.CreateCheckbox(panel, entry[2], function(checked)
            FinderUI:SetSource(kind, checked)
            Find.offset = 0
            Find:Narrow()
        end, FinderUI:SourceOn(kind))
        box.kind = kind
        box:SetPoint("TOPLEFT", 12, y)
        local count = Theme.CreateLabel(panel, "small", "muted", "RIGHT")
        count:SetPoint("TOPRIGHT", -12, y - 3)
        self.sourceBoxes[#self.sourceBoxes + 1] = box
        self.sourceCounts[kind] = count
        y = y - 22
        end
    end
    -- Reputation: gear a faction's quartermaster sells. Not a kind of
    -- place but a kind of gear, so it hides whole rows; ticked until
    -- unticked, like the rest (`finderSourcesOff.rep`).
    local rep = Widgets.CreateCheckbox(panel, L["Reputation"], function(checked)
        FinderUI:SetSource(REP, checked)
        Find.offset = 0
        Find:Narrow()
    end, FinderUI:SourceOn(REP))
    rep.kind = REP
    rep:SetPoint("TOPLEFT", 12, y)
    local repCount = Theme.CreateLabel(panel, "small", "muted", "RIGHT")
    repCount:SetPoint("TOPRIGHT", -12, y - 3)
    self.sourceBoxes[#self.sourceBoxes + 1] = rep
    self.sourceCounts[REP] = repCount
    y = y - 22

    -- SLOT: every slot, or one.
    y = y - 8
    Heading(panel, L["SLOT"], y)
    y = y - 18
    local slot = Widgets.CreateChoice(panel, {
        min = 0, max = #Groups(), step = 1, value = self:SlotIndex(), width = inner,
        format = function(index) return Find.SlotText(index) end,
        onChange = function(index)
            local group = Groups()[index]
            Find:SetSlot(group and group[1] or nil)
        end,
    })
    slot:SetPoint("TOPLEFT", 12, y)
    self.slotChoice = slot
    y = y - 30

    -- AUCTION PRICE: the most you would pay, and how old the prices are.
    if Find.AuctionOn() then
        local AG = ns.AuctionGear
        y = y - 8
        Heading(panel, L["AUCTION PRICE"], y)
        y = y - 18
        local most = Widgets.CreateChoice(panel, {
            min = 1, max = #AG.MOST, step = 1, value = Find.MostIndex(), width = inner,
            format = function(index) return Find.MostText(index) end,
            onChange = function(index)
                AG:SetMost(AG.MOST[index])
                Find.offset = 0
                Find:Narrow()
            end,
        })
        most:SetPoint("TOPLEFT", 12, y)
        self.mostChoice = most
        y = y - 28
        local age = Theme.CreateLabel(panel, "small", "dim")
        age:SetPoint("TOPLEFT", 12, y)
        age:SetWidth(inner)
        age:SetJustifyH("LEFT")
        if age.SetWordWrap then age:SetWordWrap(true) end
        self.auctionAge = age
        y = y - 32
    end

    -- NARROW IT DOWN: the old window's switches, each with its own words.
    y = y - 8
    Heading(panel, L["NARROW IT DOWN"], y)
    y = y - 18
    local zone = Widgets.CreateCheckbox(panel, L["This Zone Only"], function(checked)
        FinderUI:SetZoneOnly(checked)
        Find.offset = 0
        Find:Narrow()
    end, FinderUI:ZoneOnly())
    zone:SetPoint("TOPLEFT", 12, y)
    Tip(zone, L["This Zone Only"], L["Only upgrades from the zone you're in, plus dungeon drops and gear you can make. The list changes as you travel."])
    self.zoneBox = zone
    y = y - 22
    -- Solo Quests Only and Quest Level are the upgrade quest's too
    -- (Finder:QuestFilterChanged tells this page, and it looks again).
    local solo = Widgets.CreateCheckbox(panel, L["Solo Quests Only"], function(checked)
        Finder:SetSoloOnly(checked)
    end, Finder:SoloOnly())
    solo:SetPoint("TOPLEFT", 12, y)
    Tip(solo, L["Solo Quests Only"], L["Hides quests that need a group, and the quests after them. Elite kills count as group quests."])
    self.soloBox = solo
    y = y - 22
    local now = Widgets.CreateCheckbox(panel, L["Only What I Can Get Now"], function(checked)
        FinderUI:SetGetNowOnly(checked)
        Find.offset = 0
        Find:Narrow()
    end, FinderUI:GetNowOnly())
    now:SetPoint("TOPLEFT", 12, y)
    self.nowBox = now
    y = y - 28

    local levelLabel = Theme.CreateLabel(panel, "small", "muted")
    levelLabel:SetPoint("TOPLEFT", 12, y)
    levelLabel:SetText(L["Quest Level:"])
    y = y - 16
    local questLevels = Widgets.CreateChoice(panel, {
        min = 0, max = Finder.QUEST_LEVELS_ANY, step = 1, value = FinderUI:QuestLevelsValue(), width = inner,
        format = function(value) return Find.QuestLevelsText(value) end,
        onChange = function(value) Finder:SetQuestLevelsAbove(value) end,
    })
    questLevels:SetPoint("TOPLEFT", 12, y)
    Tip(questLevels, L["Quest Level:"], L["How far above your level a quest can be."])
    self.questLevels = questLevels
    y = y - 32

    -- Plan Ahead: gear up to ten levels on, in amber.
    local aheadLabel = Theme.CreateLabel(panel, "small", "muted")
    aheadLabel:SetPoint("TOPLEFT", 12, y)
    aheadLabel:SetText(L["Plan Ahead:"])
    y = y - 16
    local ahead = Widgets.CreateChoice(panel, {
        min = 0, max = 10, step = 1, value = self:Ahead(), width = inner,
        format = function(value) return FinderUI.AheadText(value) end,
        onChange = function(value)
            if ns.db then ns.db.finderAhead = value end
            Find.offset = 0
            Find:Refresh()
        end,
    })
    ahead:SetPoint("TOPLEFT", 12, y)
    self.aheadChoice = ahead

    local all = Widgets.CreateButton(panel, L["Show All"], function() Find:ShowAll() end,
        { width = math.max(90, Theme.TextWidth("normal", L["Show All"]) + 28), height = 22 })
    all:SetPoint("BOTTOMLEFT", 12, 12)
    self.showAll = all
end

--- Can the auction house be read (Tradeskills loaded with its call)?
function Find.AuctionOn()
    return ns.AuctionGear ~= nil and ns.AuctionGear:On()
end

--- Auction Price's place: 1 Any, 2 Up to 1g, 3 Up to 5g, 4 Up to 20g.
function Find.MostIndex()
    local AG = ns.AuctionGear
    local most = AG and AG:Most()
    for index, copper in ipairs(AG and AG.MOST or {}) do
        if copper == most then return index end
    end
    return 1
end

function Find.MostText(index)
    if index == 2 then return L["Up to 1g"] end
    if index == 3 then return L["Up to 5g"] end
    if index == 4 then return L["Up to 20g"] end
    return L["Any"]
end

--- "Prices are from your last scan, 2 hours ago."
function Find.AuctionAgeText()
    local AG = ns.AuctionGear
    local ago = AG and AG.Ago(AG:LastScan())
    if not ago then return "" end
    return L.Format("Prices are from your last scan, %s ago.", ago)
end

--- The count beside each source's tick box.
function Find:PaintCounts(counts)
    for kind, label in pairs(self.sourceCounts) do
        local count = counts and counts[kind] or 0
        label:SetText(counts and tostring(count) or "")
        label:SetTextColor(Theme.Unpack(count > 0 and "text" or "dim"))
    end
end

--------------------------------------------------------------------------------
-- The list
--------------------------------------------------------------------------------

function Find:BuildHeads(itemWidth)
    local list = self.list
    -- From the row's right edge, as the rows lay their columns.
    local gainRight = 8
    local levelRight = gainRight + GAIN_WIDTH + CELL_GAP
    local whereRight = levelRight + LEVEL_WIDTH + CELL_GAP
    local slotRight = whereRight + WHERE_WIDTH + CELL_GAP
    self.columns = { gainRight = gainRight, levelRight = levelRight, whereRight = whereRight,
        slotRight = slotRight, item = itemWidth, baseItem = itemWidth, dual = false, gainWidth = GAIN_WIDTH }
    local heads = {
        { key = "item", text = L["ITEM"], left = TEXT_X },
        { key = "slot", text = L["SLOT"], right = slotRight, width = SLOT_WIDTH },
        { key = "where", text = L["WHERE"], right = whereRight, width = WHERE_WIDTH },
        { key = "level", text = L["LEVEL"], right = levelRight, width = LEVEL_WIDTH },
        { key = "gain", text = L["GAIN"], right = gainRight, width = GAIN_WIDTH, justify = "RIGHT" },
        { key = "off", text = L["OFF"], right = gainRight, width = DUAL_GAIN, justify = "RIGHT" },
    }
    self.heads = {}
    for _, head in ipairs(heads) do
        local button = CreateFrame("Button", nil, list)
        button:SetHeight(HEAD)
        if head.left then
            button:SetPoint("TOPLEFT", 1 + head.left, 0)
            button:SetWidth(itemWidth)
        else
            button:SetPoint("TOPRIGHT", -(1 + SCROLL + head.right), 0)
            button:SetWidth(head.width)
        end
        local label = Theme.CreateLabel(button, "tiny", "heading", head.justify)
        local arrow = Arrow(button, 8)
        if head.justify == "RIGHT" then
            label:SetPoint("RIGHT", 0, 0)
            arrow:SetPoint("RIGHT", label, "LEFT", -4, 0)
        else
            label:SetPoint("LEFT", 0, 0)
            arrow:SetPoint("LEFT", label, "RIGHT", 4, 0)
        end
        label:SetText(head.text)
        arrow:Hide()
        button.label, button.arrow, button.key, button.left = label, arrow, head.key, head.left
        button:SetScript("OnClick", function(self) Find:SortBy(self.key) end)
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(L["Click a heading to sort. Click it again to flip the order, and a third time for best first."], 1, 1, 1, true)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        if head.key == "off" then button:Hide() end
        self.heads[#self.heads + 1] = button
    end
end

--- Lay the columns for one gain column or two (MAIN and OFF), from the
--- row's right edge. Only when that changes.
function Find:LayColumns(dual)
    local columns = self.columns
    if not columns or columns.dual == dual then return end
    columns.dual = dual
    local gainWidth = dual and DUAL_GAIN or GAIN_WIDTH
    local offRight = 8
    local gainRight = dual and (offRight + DUAL_GAIN + CELL_GAP) or 8
    local levelRight = gainRight + gainWidth + CELL_GAP
    local whereRight = levelRight + LEVEL_WIDTH + CELL_GAP
    local slotRight = whereRight + WHERE_WIDTH + CELL_GAP
    columns.gainRight, columns.levelRight, columns.whereRight, columns.slotRight = gainRight, levelRight,
        whereRight, slotRight
    columns.gainWidth = gainWidth
    columns.item = columns.baseItem - (dual and (DUAL_GAIN * 2 + CELL_GAP - GAIN_WIDTH) or 0)
    local spots = {
        slot = { slotRight, SLOT_WIDTH }, where = { whereRight, WHERE_WIDTH },
        level = { levelRight, LEVEL_WIDTH }, gain = { gainRight, gainWidth }, off = { offRight, DUAL_GAIN },
    }
    for _, head in ipairs(self.heads or {}) do
        local spot = spots[head.key]
        if spot then
            head:ClearAllPoints()
            head:SetPoint("TOPRIGHT", -(1 + SCROLL + spot[1]), 0)
            head:SetWidth(spot[2])
        elseif head.left then
            head:SetWidth(columns.item)
        end
        if head.key == "off" then head:SetShown(dual) end
    end
    for _, row in ipairs(self.rows or {}) do
        for key, spot in pairs(spots) do
            local cell = rawget(row, key)
            if cell then
                cell:ClearAllPoints()
                cell:SetPoint("TOPRIGHT", -spot[1], -8)
                cell:SetWidth(spot[2])
            end
        end
        row.off:SetShown(dual)
        row.item:SetWidth(columns.item)
    end
end

function Find:PaintHeads()
    local key, flip = self.sortKey or "gain", self.sortFlip == true
    -- MAIN and OFF with two columns; with Show on one spec the one column
    -- is named for it; GAIN with no Off Spec.
    local which, dual = self:ShowWhich(), self:Dual()
    for _, head in ipairs(self.heads) do
        if head.key == "gain" then
            local words = L["GAIN"]
            if dual and which == "both" then words = L["MAIN"]
            elseif dual and which == "main" then words = L["MAIN"]
            elseif dual and which == "off" then words = L["OFF"] end
            head.label:SetText(words)
        end
    end
    for _, head in ipairs(self.heads) do
        local sorted = head.key == key
        head.label:SetTextColor(Theme.Unpack(sorted and "text" or "heading"))
        head.arrow:SetShown(sorted)
        if sorted then
            -- Gain starts with the biggest; the rest start at the top.
            local down = (key == "gain" or key == "off") ~= flip
            pcall(head.arrow.SetTexCoord, head.arrow, 0, 1, down and 0 or 1, down and 1 or 0)
        end
    end
end

--- A row's dark glass: picked, under the mouse, or at rest.
function Find:PaintRow(row)
    local line = rawget(row, "line")
    local picked = line and line.key == self.picked
    local over = rawget(row, "over") == true
    row.background:SetColorTexture(Theme.Unpack(picked and "glassActive" or over and "glassHover" or row.restKey))
    row.edge:SetShown(picked or over)
    row.edge:SetColorTexture(Theme.Unpack(picked and "accentHi" or "accent"))
end

function Find:BuildRow(index)
    local columns = self.columns
    local row = CreateFrame("Button", nil, self.list)
    row:SetHeight(ROW_MIN)
    row.restKey = index % 2 == 0 and "glassAlt" or "glass"
    row.background = Theme.Fill(row, row.restKey)
    local under = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    under:SetPoint("BOTTOMLEFT")
    under:SetPoint("BOTTOMRIGHT")
    under:SetHeight(1)
    under:SetColorTexture(Theme.Unpack("border", 0.6))
    local edge = row:CreateTexture(nil, "ARTWORK")
    edge:SetPoint("TOPLEFT")
    edge:SetPoint("BOTTOMLEFT")
    edge:SetWidth(3)
    edge:Hide()
    row.edge = edge

    local icon = Theme.CreateItemIcon(row, ICON)
    icon:SetPoint("TOPLEFT", 8, -4)
    row.icon = icon
    local item = Theme.CreateLabel(row, "normal", "text")
    item:SetPoint("TOPLEFT", TEXT_X, -8)
    item:SetWidth(columns.item)
    item:SetWordWrap(true)
    row.item = item

    local function Cell(size, key, right, width, justify)
        local label = Theme.CreateLabel(row, size, key, justify)
        label:SetPoint("TOPRIGHT", -right, -8)
        label:SetWidth(width)
        label:SetWordWrap(true)
        return label
    end
    row.slot = Cell("small", "muted", columns.slotRight, SLOT_WIDTH)
    row.where = Cell("small", "text", columns.whereRight, WHERE_WIDTH)
    row.level = Cell("small", "text", columns.levelRight, LEVEL_WIDTH)
    row.gain = Cell("normal", "good", columns.gainRight, GAIN_WIDTH, "RIGHT")
    row.off = Cell("normal", "offSpec", 8, DUAL_GAIN, "RIGHT")
    row.off:Hide()
    -- A thin bar under the gain: how big it is next to the others shown.
    local track = row:CreateTexture(nil, "ARTWORK")
    track:SetPoint("TOPRIGHT", row.gain, "BOTTOMRIGHT", 0, -4)
    track:SetSize(BAR_WIDTH, 3)
    track:SetColorTexture(Theme.Unpack("well"))
    row.barTrack = track
    local fill = row:CreateTexture(nil, "OVERLAY")
    fill:SetPoint("TOPLEFT", track, "TOPLEFT")
    fill:SetSize(1, 3)
    row.barFill = fill

    row:SetScript("OnEnter", function(self)
        self.over = true
        Find:PaintRow(self)
        local line = rawget(self, "line")
        if line and type(line.pick.link) == "string" then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            pcall(GameTooltip.SetHyperlink, GameTooltip, line.pick.link)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        self.over = false
        Find:PaintRow(self)
        GameTooltip:Hide()
    end)
    row:SetScript("OnClick", function(self, mouse) Find:RowClicked(self, mouse) end)
    if row.RegisterForClicks then row:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    row:Hide()
    return row
end

--- The gain a row shows, as the old list words it.
function Find.GainText(pick)
    local result = pick.result or {}
    local gain = result.empty and L["empty slot"]
        or result.percent and ("%+d%%"):format(math.floor(result.percent + 0.5)) or L["better"]
    local train = ns.WeaponSkills and ns.WeaponSkills:NeedsTraining(pick.link)
    if train then return L.Format("Train: %s", gain), "loss" end
    local later = pick.needs or pick.at or pick.remote or ns.Crafting.WearWaits(pick)
    return gain, later and "warn" or "good"
end

--- How full a gain's bar is, 0 to 1, against the biggest shown. An empty
--- slot fills it; nil hides the bar (no percent to show).
function Find.BarShare(pick, most)
    local result = pick and pick.result
    if not result then return nil end
    if result.empty then return 1 end
    local percent = tonumber(result.percent)
    if not percent or percent <= 0 then return nil end
    if not most or most <= 0 then return 1 end
    return math.max(0.04, math.min(1, percent / most))
end

--- Fill a row with a line.
-- @return the row's height
function Find:FillRow(row, line)
    local FinderUI, quest = ns.FinderUI, ns.UpgradeQuest
    local pick = line.pick
    row.line = line
    -- What the row's menu and its clicks read (FinderUI.PickMenu).
    row.pick = {
        link = pick.link, sources = line.sources, itemID = pick.itemID, needs = pick.needs,
        result = pick.result, roll = pick.roll, at = pick.at, gain = pick.gain,
    }
    Theme.SetItemIcon(row.icon, pick.link)

    local name = ns.Items.ShowLink(pick.link)
    if line.pair then name = name .. " + " .. ns.Items.ShowLink(line.pair.link) end
    if quest and quest:IsFollowing(pick.itemID) then name = name .. "  " .. Colored("good", L["Following"]) end
    if ns.Tracking and ns.Tracking:IsTracked(pick.itemID) then
        name = name .. "  " .. Colored("accent", L["Tracking"])
    end
    -- With two gain columns, a row that helps only one spec says so.
    if self:Dual() and self:ShowWhich() == "both" then
        if line.main and not line.off then
            name = name .. "\n" .. Colored("muted", L["Main only"])
        elseif line.off and not line.main then
            name = name .. "\n" .. Colored("offSpec", L["Off only"])
        end
    end
    if line.pair then name = name .. "\n" .. Colored("accent", L["Pair"]) end
    -- Gear only a crafter can wear says the skill, in amber while you
    -- lack it.
    local wear = ns.Crafting.WearText(pick)
    if wear then
        name = name .. "\n" .. Colored(ns.Crafting.WearWaits(pick) and "warn" or "muted", wear)
    end
    row.item:SetText(name)
    row.slot:SetText(line.slotName or "")

    -- Where: the first place's kind and where it is. Gear that waits on a
    -- standing says so in amber; gear that waits on a level has its level
    -- in amber.
    local source = line.sources[1]
    local where = source and FinderUI.WhereOf(line) or ""
    where = FinderUI.MarkZone(where or "", quest and quest.Zone())
    if source then where = Colored(FinderUI.KIND_COLORS[source.kind] or "text", Finder.Label(source)) .. "  " .. where end
    -- A pair: where each of the two comes from.
    local partner = line.pair and line.pairSources and line.pairSources[1]
    if partner then
        local other = FinderUI.WhereOf({ sources = line.pairSources }) or ""
        other = FinderUI.MarkZone(other, quest and quest.Zone())
        where = where .. "\n+ " .. Colored(FinderUI.KIND_COLORS[partner.kind] or "text", Finder.Label(partner))
            .. "  " .. other
    end
    if pick.needs then
        where = Colored("warn", L.Format("Needs %s with %s", pick.needs.standing, pick.needs.faction))
    end
    row.where:SetText(where)

    if line.level == nil then line.level = FinderUI.LevelOf(pick) or false end
    row.level:SetText(line.level and tostring(line.level) or "")
    row.level:SetTextColor(Theme.Unpack(pick.at and "warn" or "text"))

    -- The gain: the Main Spec's, then the Off Spec's in blue. A dash where
    -- a spec gains nothing. With Show on Off Spec the one column is its.
    local dual, which = self:Dual(), self:ShowWhich()
    local first = line.main
    if dual and which == "off" then first = line.off end
    if not dual then first = pick end
    local gain, tone = "\226\128\147", "dim"
    if first then
        gain, tone = Find.GainText(first)
        if first == line.off and first ~= line.main and tone == "good" then tone = "offSpec" end
    end
    row.gain:SetText(gain)
    row.gain:SetTextColor(Theme.Unpack(tone))
    local share = first and Find.BarShare(first, self.mostPercent) or nil
    row.barTrack:SetShown(share ~= nil)
    row.barFill:SetShown(share ~= nil)
    if share then
        row.barFill:SetWidth(math.max(1, math.floor(BAR_WIDTH * share + 0.5)))
        row.barFill:SetColorTexture(Theme.Unpack(tone, 0.85))
    end
    local offShown = dual and which == "both"
    if offShown then
        local offGain, offTone = "\226\128\147", "dim"
        if line.off then
            offGain, offTone = Find.GainText(line.off)
            if offTone == "good" then offTone = "offSpec" end
        end
        row.off:SetText(offGain)
        row.off:SetTextColor(Theme.Unpack(offTone))
    end
    row.off:SetShown(offShown)

    local gainWidth = self.columns.gainWidth or GAIN_WIDTH
    local height = math.max(TextHeight(row.item, "normal", self.columns.item),
        TextHeight(row.where, "small", WHERE_WIDTH), TextHeight(row.gain, "normal", gainWidth),
        offShown and TextHeight(row.off, "normal", DUAL_GAIN) or 0,
        TextHeight(row.slot, "small", SLOT_WIDTH))
    height = math.max(ROW_MIN, math.ceil(height + 16))
    row:SetHeight(height)
    row:Show()
    self:PaintRow(row)
    return height
end

--- Draw the rows in view, from the line scrolled to. Nothing is read or
--- sorted here.
function Find:Draw()
    if not self.rows then return end
    local lines = self.shown or {}
    local offset = math.max(0, math.min(self.offset or 0, math.max(0, #lines - 1)))
    self.offset = offset
    local area = self.listArea or 500
    local used, count, full = 0, 0, false
    for index, row in ipairs(self.rows) do
        local line = not full and lines[offset + index] or nil
        if line then
            local height = self:FillRow(row, line)
            if index > 1 and used + height > area then
                full = true
                line = nil
            else
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", self.list, "TOPLEFT", 1, -(HEAD + used))
                row:SetPoint("TOPRIGHT", self.list, "TOPRIGHT", -(1 + SCROLL), -(HEAD + used))
                used = used + height
                count = count + 1
            end
        end
        if not line then
            row.line, row.pick = nil, nil
            row:Hide()
        end
        if rawget(row, "over") == true and not line then GameTooltip:Hide() end
    end
    self.inView = count
    -- The last line shows: the wheel goes no further down.
    self.atEnd = offset + count >= #lines
    self.room = area - used

    local total = #lines
    if total > count and count > 0 then
        local size = math.max(16, area * count / total)
        local top = (area - size) * math.min(1, offset / math.max(1, total - count))
        self.thumb:SetHeight(size)
        self.thumb:ClearAllPoints()
        self.thumb:SetPoint("TOPRIGHT", self.list, "TOPRIGHT", -3, -(HEAD + top))
        self.thumb:Show()
        self.track:Show()
    else
        self.thumb:Hide()
        self.track:Hide()
    end
end

--- The mouse wheel: a few lines up or down, never past the last line.
function Find:ScrollBy(steps)
    local lines = self.shown or {}
    if steps > 0 and self.atEnd then return end
    local before = self.offset or 0
    self.offset = math.max(0, math.min(math.max(0, #lines - 1), before + steps))
    if self.offset == before then return end
    self:Draw()
    -- Stepped past the end: come back up while a row's room stays empty.
    local tries = 0
    while steps > 0 and self.atEnd and (self.room or 0) >= ROW_MIN and self.offset > before + 1 and tries < WHEEL do
        self.offset = self.offset - 1
        tries = tries + 1
        self:Draw()
    end
end

function Find:BuildList(left, width)
    local list = Theme.CreatePanel(self.body, "panel", "border")
    list:SetPoint("TOPLEFT", left, 0)
    list:SetPoint("BOTTOMLEFT", left, 0)
    list:SetWidth(width)
    Theme.Recess(list)
    self.list = list

    local itemWidth = width - 2 - SCROLL - TEXT_X - 8 - GAIN_WIDTH - LEVEL_WIDTH - WHERE_WIDTH - SLOT_WIDTH
        - CELL_GAP * 4
    self:BuildHeads(itemWidth)
    local rule = Theme.CreateDivider(list, "border")
    rule:SetPoint("TOPLEFT", 1, -(HEAD - 1))
    rule:SetPoint("TOPRIGHT", -1, -(HEAD - 1))

    self.rows = {}
    for index = 1, ROWS do self.rows[index] = self:BuildRow(index) end

    local track = list:CreateTexture(nil, "ARTWORK")
    track:SetPoint("TOPRIGHT", -3, -HEAD)
    track:SetPoint("BOTTOMRIGHT", -3, 2)
    track:SetWidth(4)
    track:SetColorTexture(Theme.Unpack("well"))
    track:Hide()
    self.track = track
    local thumb = list:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(4)
    thumb:SetColorTexture(Theme.Unpack("accent", 0.7))
    thumb:Hide()
    self.thumb = thumb

    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        Find:ScrollBy(delta > 0 and -WHEEL or WHEEL)
    end)

    -- Under the rows, while the Reputation box hides some: how many, and
    -- a word that ticks it again.
    local hidden = CreateFrame("Frame", nil, list)
    hidden:SetPoint("BOTTOMLEFT", 1, 1)
    hidden:SetPoint("BOTTOMRIGHT", -1, 1)
    hidden:SetHeight(HIDDEN_STRIP)
    local hiddenRule = hidden:CreateTexture(nil, "ARTWORK")
    hiddenRule:SetPoint("TOPLEFT")
    hiddenRule:SetPoint("TOPRIGHT")
    hiddenRule:SetHeight(1)
    hiddenRule:SetColorTexture(Theme.Unpack("border", 0.6))
    local hiddenText = Theme.CreateLabel(hidden, "small", "muted")
    hiddenText:SetPoint("LEFT", 12, 0)
    hidden.text = hiddenText
    local showThem = CreateFrame("Button", nil, hidden)
    local showLabel = Theme.CreateLabel(showThem, "small", "accent")
    showLabel:SetPoint("LEFT")
    showLabel:SetText(L["Show them"])
    showThem.label = showLabel
    local underline = showThem:CreateTexture(nil, "ARTWORK")
    underline:SetPoint("BOTTOMLEFT", showLabel, "BOTTOMLEFT", 0, -2)
    underline:SetPoint("BOTTOMRIGHT", showLabel, "BOTTOMRIGHT", 0, -2)
    underline:SetHeight(1)
    underline:SetColorTexture(Theme.Unpack("accent", 0.8))
    showThem:SetSize(Theme.TextWidth("small", L["Show them"]) + 4, HIDDEN_STRIP - 6)
    showThem:SetPoint("LEFT", hiddenText, "RIGHT", 10, 0)
    showThem:SetScript("OnClick", function() Find:ShowReputation() end)
    hidden.button = showThem
    hidden:Hide()
    self.repStrip = hidden

    local empty = Widgets.CreateEmpty(list, { width = width - 60 })
    empty:SetPoint("TOP", list, "TOP", 0, -(HEAD + 60))
    empty:Hide()
    self.empty = empty
end

--- How tall the rows' part of the list is.
function Find:MeasureList()
    local ok, height = pcall(self.list.GetHeight, self.list)
    if ok and type(height) == "number" and height > HEAD + ROW_MIN then
        self.listArea = height - HEAD - 2
        if self.repStrip and self.repStrip:IsShown() then self.listArea = self.listArea - HIDDEN_STRIP end
    end
end

--- "3 upgrades from reputation vendors are hidden. Show them", while the
--- Reputation box hides any of the rows the other filters let through.
function Find.RepHiddenText(count)
    if (count or 0) <= 0 then return nil end
    if count == 1 then return L["1 upgrade from a reputation vendor is hidden."] end
    return L.Format("%d upgrades from reputation vendors are hidden.", count)
end

function Find:PaintRepStrip()
    local strip = self.repStrip
    if not strip then return end
    local words = Find.RepHiddenText(self.repHidden)
    strip.text:SetText(words or "")
    strip:SetShown(words ~= nil)
end

--- "Show them": tick the Reputation box again.
function Find:ShowReputation()
    local FinderUI = ns.FinderUI
    if not FinderUI then return end
    FinderUI:SetSource(REP, true)
    self.offset = 0
    self:SyncFilters()
    self:Narrow()
end

--------------------------------------------------------------------------------
-- Clicks
--------------------------------------------------------------------------------

--- A click on a row picks it for the sheet. The game's own clicks still
--- work: Shift links it, Ctrl tries it on, Alt pins it on the map, and a
--- right-click opens the menu the old list had.
function Find:RowClicked(row, mouse)
    local line = rawget(row, "line")
    if not line then return end
    local FinderUI = ns.FinderUI
    local pick = line.pick
    if mouse == "RightButton" then
        self:Pick(line.key)
        FinderUI:OpenRowMenu(row)
        return
    end
    local okAlt, alt = pcall(function() return IsAltKeyDown() == true end)
    if okAlt and alt then
        local place = FinderUI.Place(pick)
        if place and ns.Waypoints then ns.Waypoints:Show(place, place.name, Theme.ItemIcon(pick.link)) end
        return
    end
    if Widgets.ItemTryOn(nil, pick.link) then return end
    if type(IsModifiedClick) == "function" and type(ChatEdit_InsertLink) == "function" then
        local ok, chatLink = pcall(IsModifiedClick, "CHATLINK")
        if ok and chatLink then
            pcall(ChatEdit_InsertLink, pick.link)
            return
        end
    end
    self:Pick(line.key)
end

--- Show a line on the sheet and light its row. Nothing is read again.
function Find:Pick(key)
    self.picked = key
    for _, row in ipairs(self.rows or {}) do
        if Shown(row) then self:PaintRow(row) end
    end
    self:PaintSheet()
end

--- The line picked, among those showing.
function Find:PickedLine()
    for _, line in ipairs(self.shown or {}) do
        if line.key == self.picked then return line end
    end
    return nil
end

--------------------------------------------------------------------------------
-- The side sheet
--------------------------------------------------------------------------------

--- A pick's places, those in the zone you stand in first, then as the
--- finder had them. Every place, whatever the tick boxes say.
function Find.Places(pick, zone)
    local quest = ns.UpgradeQuest
    local zoneOf = quest and quest.SourceZone
    local near, far = {}, {}
    for _, source in ipairs(pick.sources or {}) do
        -- A dungeon or a craft counts as in every zone for This Zone
        -- Only; here only a place that is in this zone comes first.
        local here = zone and zoneOf and zoneOf(source) == zone
        if here then near[#near + 1] = source else far[#far + 1] = source end
    end
    for _, source in ipairs(far) do near[#near + 1] = source end
    return near
end

--- One place in words: its kind and where, then what comes first and
--- what a craft takes, each on a line of its own.
function Find.PlaceText(pick, source, zone)
    local FinderUI = ns.FinderUI
    local text = FinderUI.SourceLine(source, zone)
    if source.after then text = text .. "\n" .. Colored("muted", (L.Format("    after %s", source.after):gsub("^%s+", ""))) end
    if source.kind == "craft" and ns.Crafting then
        local materials = ns.Crafting:MaterialsText(pick.itemID)
        if type(materials) == "string" and materials ~= "" then
            text = text .. "\n" .. L.Format("Materials: %s", materials)
        end
    end
    return text
end

--- The sheet's lines for an auction house source: "Lowest price: 4g 20s",
--- "2 for sale at your last scan, 2 hours ago.", "You have 11g 4s."
function Find.AuctionLines(source)
    local lines = {}
    local price = Finder.Money(source.price)
    if price then lines[#lines + 1] = L.Format("Lowest price: %s", price) end
    local ago = ns.AuctionGear and ns.AuctionGear.Ago(source.at or source.seen)
    if source.count and ago then
        lines[#lines + 1] = Colored("muted", L.Format("%d for sale at your last scan, %s ago.", source.count, ago))
    end
    local held = Finder.Money(Finder.MoneyHeld())
    if held then lines[#lines + 1] = L.Format("You have %s.", held) end
    return lines
end

--- The auction house source of a line, from its filtered sources, or nil.
function Find.AuctionSource(line)
    for _, source in ipairs(line.sources or line.pick.sources or {}) do
        if source.kind == "auction" then return source end
    end
    return nil
end

--- Search the auction house for it, through Tradeskills (open the auction
--- house first). Chat says why when it can't.
function Find.SearchAuction(itemID)
    local ts = _G.BlackthornesTS
    local butler = type(ts) == "table" and ts.Butler
    if not (type(butler) == "table" and type(butler.SearchAuctions) == "function") then return false end
    local ok, done, why = pcall(butler.SearchAuctions, butler, { { itemID = itemID, count = 1 } })
    if ok and not done and type(why) == "string" and why ~= "" then ns.Print(why) end
    return ok and done == true
end

--- What the sheet's buttons do for a pick: { key, text, run, primary,
--- dimmed, tip }, in the order they show.
function Find:Actions(line)
    local FinderUI, quest = ns.FinderUI, ns.UpgradeQuest
    local pick = line.pick
    local actions = {}
    local auction = Find.AuctionSource(line)
    local can, why
    if quest then can, why = quest.CanFollow(pick) end
    -- On the auction house and no quest to make of it: Search leads.
    if quest and not (auction and not can) then
        actions[#actions + 1] = { key = "quest", text = L["Make It My Quest"], primary = true,
            dimmed = not can, why = why,
            tip = L["It becomes your upgrade quest, with steps to get it. A green Quest tag marks it here."],
            run = function() FinderUI:Follow(pick) end }
    end
    if auction then
        actions[#actions + 1] = { key = "search", text = L["Search the Auction House"], primary = #actions == 0,
            run = function() Find.SearchAuction(pick.itemID) end }
    end
    if ns.Tracking then
        local tracked = ns.Tracking:IsTracked(pick.itemID)
        actions[#actions + 1] = { key = "track", text = tracked and L["Stop Tracking"] or L["Track"],
            run = function() ns.Tracking:Toggle(pick) end }
    end
    local place = FinderUI.Place(pick)
    if place and ns.Waypoints then
        actions[#actions + 1] = { key = "map", text = L["Show on Map"], run = function()
            ns.Waypoints:Show(place, place.name, Theme.ItemIcon(pick.link))
        end }
    end
    local queue = ns.TradeskillsQueue
    local craft = queue and queue:Available() and queue.CraftSource(pick.sources) or nil
    if craft then
        actions[#actions + 1] = { key = "queue", text = L["Queue It"], run = function()
            queue:Queue(craft)
            Find:PaintSheet()
        end }
    end
    if quest and quest.Ignore then
        actions[#actions + 1] = { key = "ignore", text = L["Ignore"],
            tip = L["Skips it on this character and picks the next best one. Bring it back with Ignored in Settings."],
            run = function() quest:Ignore(pick.itemID) end }
    end
    return actions
end

function Find:BuildSheet(left, width)
    -- It takes what room is left: more when the window is wider than a
    -- page needs (inside the one window, or when another tab asks for it).
    local sheet = Theme.CreatePanel(self.body, "panel", "border")
    sheet:SetPoint("TOPLEFT", left, 0)
    sheet:SetPoint("BOTTOMRIGHT", 0, 0)
    Theme.Recess(sheet)
    self.sheet = sheet
    self.sheetWidth = width
    local inner = width - 24

    -- Everything on it, so an empty list shows a bare sheet.
    local hold = CreateFrame("Frame", nil, sheet)
    hold:SetAllPoints(sheet)
    self.sheetHold = hold

    local icon = Theme.CreateItemIcon(hold, 36)
    icon:SetPoint("TOPLEFT", 12, -12)
    self.sheetIcon = icon
    local name = Theme.CreateLabel(hold, "large", "text")
    name:SetPoint("TOPLEFT", 58, -12)
    name:SetWidth(inner - 46)
    name:SetWordWrap(true)
    self.sheetName = name
    local kind = Theme.CreateLabel(hold, "small", "muted")
    kind:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
    kind:SetWidth(inner - 46)
    kind:SetWordWrap(true)
    self.sheetKind = kind

    local gain = Theme.CreateLabel(hold, "title", "good")
    self.sheetGain = gain
    local arrow = Arrow(hold, 12)
    arrow:SetPoint("RIGHT", gain, "LEFT", -4, 0)
    self.sheetArrow = arrow
    -- The Off Spec's gain under it, when the row helps both specs.
    local offGain = Theme.CreateLabel(hold, "title", "offSpec")
    offGain:Hide()
    self.sheetOffGain = offGain
    -- What it would replace, and what it waits on.
    local notes = Theme.CreateLabel(hold, "small", "muted")
    notes:SetWidth(inner)
    notes:SetWordWrap(true)
    self.sheetNotes = notes

    local rule = Theme.CreateDivider(hold, "border")
    self.sheetRule = rule
    local heading = Theme.CreateLabel(hold, "tiny", "gilt")
    heading:SetText(L["WHERE TO GET IT"])
    self.sheetHeading = heading

    self.sheetPlaces = {}
    for index = 1, SHEET_SOURCES do
        local label = Theme.CreateLabel(hold, "small", "text")
        label:SetWidth(inner)
        label:SetWordWrap(true)
        label:Hide()
        self.sheetPlaces[index] = label
    end
    local more = Theme.CreateLabel(hold, "small", "muted")
    more:Hide()
    self.sheetMore = more

    -- Why it can't be a quest yet, over the buttons.
    local why = Theme.CreateLabel(hold, "small", "warn")
    why:SetWidth(inner)
    why:SetWordWrap(true)
    why:Hide()
    self.sheetWhy = why

    self.sheetButtons = {}
    for index = 1, 5 do
        local button
        button = Widgets.CreateButton(hold, " ", function()
            local action = rawget(button, "action")
            if action and action.run then action.run() end
        end, { width = 100, height = 22, primary = index == 1 })
        button:HookScript("OnEnter", function(self)
            local action = rawget(self, "action")
            if not (action and action.tip) then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(action.text, Theme.Unpack("accent"))
            GameTooltip:AddLine(action.tip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        button:HookScript("OnLeave", function() GameTooltip:Hide() end)
        button:Hide()
        self.sheetButtons[index] = button
    end
end

--- The sheet's words wrap at its width as it stands now.
function Find:FitSheet()
    local ok, width = pcall(self.sheet.GetWidth, self.sheet)
    if not (ok and type(width) == "number" and width >= SHEET) then width = SHEET end
    width = math.floor(width)
    if width == self.sheetFit then return end
    self.sheetFit, self.sheetWidth = width, width
    local inner = width - 24
    self.sheetName:SetWidth(inner - 46)
    self.sheetKind:SetWidth(inner - 46)
    self.sheetNotes:SetWidth(inner)
    self.sheetWhy:SetWidth(inner)
    for _, label in ipairs(self.sheetPlaces) do label:SetWidth(inner) end
end

--- Lay the sheet's buttons from its foot up: the gold one across the
--- top, the rest two to a line, each as wide as the longest label.
-- @return how much of the sheet's foot they take
function Find:PlaceButtons(actions)
    local sheet = self.sheetHold
    local inner = self.sheetWidth - 24
    local buttons = self.sheetButtons
    local primary, rest = nil, {}
    for _, action in ipairs(actions) do
        if action.primary then primary = action else rest[#rest + 1] = action end
    end
    local widest = 0
    for _, action in ipairs(rest) do widest = math.max(widest, Theme.TextWidth("normal", action.text) + 24) end
    local half = math.floor((inner - 8) / 2)
    local perLine = widest <= half and 2 or 1
    local each = perLine == 2 and half or inner
    local lines = math.ceil(#rest / perLine) + (primary and 1 or 0)

    for _, button in ipairs(buttons) do
        button.action = nil
        button:Hide()
    end
    local used = 0
    local function Place(button, action, x, line, width)
        button.action = action
        button:SetText(action.text)
        button:SetWidth(width)
        button:SetDimmed(action.dimmed == true)
        button:ClearAllPoints()
        button:SetPoint("BOTTOMLEFT", sheet, "BOTTOMLEFT", 12 + x, 12 + (lines - line) * 28)
        button:Show()
    end
    local line = 1
    if primary then
        Place(buttons[1], primary, 0, 1, inner)
        line = 2
    end
    for index, action in ipairs(rest) do
        local button = buttons[index + 1]
        if button then
            local column = (index - 1) % perLine
            Place(button, action, column * (each + 8), line + math.floor((index - 1) / perLine), each)
        end
    end
    used = lines * 28 + 12
    return used, primary
end

--- Fill the sheet with the line picked: the item, its gain over what is
--- worn, every place to get it, and its buttons.
function Find:PaintSheet()
    if not self.sheet then return end
    local line = self:PickedLine()
    self.sheetHold:SetShown(line ~= nil)
    if not line then return end
    local FinderUI, quest, Items = ns.FinderUI, ns.UpgradeQuest, ns.Items
    local pick = line.pick
    local hold = self.sheetHold
    self:FitSheet()
    local inner = self.sheetWidth - 24
    local zone = quest and quest.Zone() or nil

    Theme.SetItemIcon(self.sheetIcon, pick.link)
    local sheetName = Items.ShowLink(pick.link)
    if line.pair then sheetName = sheetName .. " + " .. Items.ShowLink(line.pair.link) end
    self.sheetName:SetText(sheetName)
    local kind = line.slotName or ""
    local okInfo, _, _, _, _, _, _, subType = pcall(function()
        local info = (_G.C_Item and _G.C_Item.GetItemInfo) or _G.GetItemInfo
        return info(pick.link or pick.itemID)
    end)
    if okInfo and type(subType) == "string" and subType ~= "" then kind = kind .. ", " .. subType end
    self.sheetKind:SetText(kind)
    local headHeight = math.max(36, TextHeight(self.sheetName, "large", inner - 46) + 3
        + TextHeight(self.sheetKind, "small", inner - 46))
    local y = 12 + headHeight + 12

    -- The gain; with an Off Spec, one line for each spec it helps.
    local dual = self:Dual()
    local gainPick = line.main or line.off or pick
    local gain, tone = Find.GainText(gainPick)
    if dual and gainPick == line.off and tone == "good" then tone = "offSpec" end
    if dual then gain = (line.main and L["Main Spec:"] or L["Off Spec:"]) .. " " .. gain end
    self.sheetGain:SetText(gain)
    self.sheetGain:SetTextColor(Theme.Unpack(tone))
    pcall(self.sheetArrow.SetVertexColor, self.sheetArrow, Theme.Unpack(tone))
    self.sheetGain:ClearAllPoints()
    self.sheetGain:SetPoint("TOPLEFT", hold, "TOPLEFT", 12 + 16, -y)
    y = y + (Theme.sizes.title or 16) + 6
    local offGain = self.sheetOffGain
    if offGain then
        if dual and line.main and line.off then
            local words, offTone = Find.GainText(line.off)
            if offTone == "good" then offTone = "offSpec" end
            offGain:SetText(L["Off Spec:"] .. " " .. words)
            offGain:SetTextColor(Theme.Unpack(offTone))
            offGain:ClearAllPoints()
            offGain:SetPoint("TOPLEFT", hold, "TOPLEFT", 12 + 16, -y)
            offGain:Show()
            y = y + (Theme.sizes.title or 16) + 6
        else
            offGain:Hide()
        end
    end

    -- What it takes the place of, then what it waits on.
    local notes = {}
    local wornSlot = pick.result and pick.result.slot or line.group
    local worn = Items:Equipped(wornSlot)
    if worn then notes[#notes + 1] = L.Format("You wear: %s", Items.ShowLink(worn)) end
    if quest and quest:IsFollowing(pick.itemID) then notes[#notes + 1] = Colored("good", L["Following"]) end
    if pick.needs then notes[#notes + 1] = Colored("warn", Finder.NeedsText(pick.needs)) end
    if pick.at then notes[#notes + 1] = Colored("warn", L.Format("You can wear it from level %d", pick.at)) end
    local wear = ns.Crafting.WearText(pick)
    if wear then notes[#notes + 1] = Colored(ns.Crafting.WearWaits(pick) and "warn" or "muted", wear) end
    local roll = Finder.RollText(pick)
    if roll then notes[#notes + 1] = Colored("good", roll) end
    -- On the auction house: its price at the last scan, how many, and the
    -- gold you carry.
    local auction = Find.AuctionSource(line)
    if auction then
        for _, words in ipairs(Find.AuctionLines(auction)) do notes[#notes + 1] = words end
    end
    self.sheetNotes:SetText(table.concat(notes, "\n"))
    self.sheetNotes:ClearAllPoints()
    self.sheetNotes:SetPoint("TOPLEFT", hold, "TOPLEFT", 12, -y)
    y = y + TextHeight(self.sheetNotes, "small", inner) + 10

    self.sheetRule:ClearAllPoints()
    self.sheetRule:SetPoint("TOPLEFT", hold, "TOPLEFT", 1, -y)
    self.sheetRule:SetPoint("TOPRIGHT", hold, "TOPRIGHT", -1, -y)
    y = y + 9
    self.sheetHeading:ClearAllPoints()
    self.sheetHeading:SetPoint("TOPLEFT", hold, "TOPLEFT", 12, -y)
    y = y + 18

    -- The buttons, from the foot up, and why it can't be a quest yet.
    local actions = self:Actions(line)
    self.actions = actions
    local foot, primary = self:PlaceButtons(actions)
    if primary and primary.dimmed and primary.why then
        self.sheetWhy:SetText(L.Format("Not a quest yet: %s", primary.why))
        self.sheetWhy:ClearAllPoints()
        self.sheetWhy:SetPoint("BOTTOMLEFT", hold, "BOTTOMLEFT", 12, foot + 4)
        self.sheetWhy:Show()
        foot = foot + TextHeight(self.sheetWhy, "small", inner) + 8
    else
        self.sheetWhy:Hide()
    end

    -- Every place that fits above the buttons, then how many more.
    local okHeight, height = pcall(hold.GetHeight, hold)
    if not (okHeight and type(height) == "number" and height > 200) then height = 560 end
    local room = height - foot - 18
    local places = Find.Places(pick, zone)
    -- A pair: the main hand's places, then its partner's.
    local whose = {}
    if line.pair then
        for index = 1, #places do whose[index] = pick end
        for _, source in ipairs(Find.Places(line.pair, zone)) do
            places[#places + 1] = source
            whose[#places] = line.pair
        end
    end
    self.places = places
    local shown = 0
    for index, label in ipairs(self.sheetPlaces) do
        local source = places[index]
        label:Hide()
        if source and shown == index - 1 then
            local owner = whose[index] or pick
            local text = Find.PlaceText(owner, source, zone)
            if line.pair then text = Items.ShowLink(owner.link) .. "\n" .. text end
            label:SetText(text)
            local tall = TextHeight(label, "small", inner)
            if index == 1 or y + tall <= room then
                label:ClearAllPoints()
                label:SetPoint("TOPLEFT", hold, "TOPLEFT", 12, -y)
                label:Show()
                y = y + tall + 8
                shown = index
            end
        end
    end
    self.placesShown = shown
    if #places > shown then
        self.sheetMore:SetText(L.Format("and %d more", #places - shown))
        self.sheetMore:ClearAllPoints()
        self.sheetMore:SetPoint("TOPLEFT", hold, "TOPLEFT", 12, -y)
        self.sheetMore:Show()
    else
        self.sheetMore:Hide()
    end
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

function Find:SyncSpec()
    local FinderUI = ns.FinderUI
    if not (self.specChoice and FinderUI) then return end
    FinderUI.SyncSpecChoices(self.specChoice, self.offChoice)
    self:SyncShow()
end

--- Show: Both, Main Spec or Off Spec, only while an Off Spec is picked;
--- the picked one lit green. Find moves up beside them or the drop-downs.
function Find:SyncShow()
    local hold = self.showHold
    if not hold then return end
    local on = ns.OffSpec and ns.OffSpec:On() or false
    hold:SetShown(on)
    local which = self:ShowWhich()
    for key, button in pairs(self.showButtons or {}) do
        button:SetLabelColor(key == which and "good" or "gilt")
    end
    self.findLabel:ClearAllPoints()
    self.findLabel:SetPoint("LEFT", on and hold or self.offChoice, "RIGHT", 16, 0)
    -- The note on the right makes room while Show is there.
    self.note:SetShown(not on)
end

function Find:Build(area)
    if self.page then return self.page end
    local FinderUI = ns.FinderUI
    if not (area and FinderUI) then return nil end

    local page = CreateFrame("Frame", nil, area)
    page:SetAllPoints(area)
    Theme.Fill(page, "window")
    page:Hide()
    self.page = page

    -- Along the top: Main Spec and Off Spec (the same choices as Settings),
    -- Show while an Off Spec is picked, Find, and when the list was made.
    local judge = Theme.CreateLabel(page, "small", "muted")
    judge:SetPoint("TOPLEFT", PAD, -14)
    judge:SetText(L["Main Spec:"])
    local spec = FinderUI.MainSpecChoice(page, 150)
    spec:SetPoint("LEFT", judge, "RIGHT", 8, 0)
    self.specChoice = spec

    local offLabel = Theme.CreateLabel(page, "small", "muted")
    offLabel:SetPoint("LEFT", spec, "RIGHT", 16, 0)
    offLabel:SetText(L["Off Spec:"])
    local off = FinderUI.OffSpecChoice(page, 120)
    off:SetPoint("LEFT", offLabel, "RIGHT", 8, 0)
    self.offChoice = off

    local hold = CreateFrame("Frame", nil, page)
    hold:SetHeight(20)
    hold:SetPoint("LEFT", off, "RIGHT", 16, 0)
    local showLabel = Theme.CreateLabel(hold, "small", "muted")
    showLabel:SetPoint("LEFT", 0, 0)
    showLabel:SetText(L["Show:"])
    local width = Theme.TextWidth("small", L["Show:"]) + 8
    local anchor
    self.showButtons = {}
    for _, entry in ipairs({ { "both", L["Both"] }, { "main", L["Main Spec"] }, { "off", L["Off Spec"] } }) do
        local button = Widgets.CreateButton(hold, entry[2], function() Find:SetShow(entry[1]) end,
            { width = math.max(44, Theme.TextWidth("normal", entry[2]) + 20), height = 20 })
        if anchor then
            button:SetPoint("LEFT", anchor, "RIGHT", 4, 0)
        else
            button:SetPoint("LEFT", showLabel, "RIGHT", 8, 0)
        end
        local okWidth, buttonWidth = pcall(button.GetWidth, button)
        width = width + (okWidth and type(buttonWidth) == "number" and buttonWidth or 60) + 4
        self.showButtons[entry[1]] = button
        anchor = button
    end
    hold:SetWidth(width)
    hold:Hide()
    self.showHold = hold

    local findLabel = Theme.CreateLabel(page, "small", "muted")
    findLabel:SetPoint("LEFT", off, "RIGHT", 16, 0)
    findLabel:SetText(L["Find:"])
    self.findLabel = findLabel
    local box = Widgets.CreateSearchBox(page, L["Item or place"], function(text)
        Find.find = type(text) == "string" and text:lower():gsub("^%s+", ""):gsub("%s+$", "") or nil
        Find.offset = 0
        Find:Narrow()
    end)
    box:SetWidth(180)
    box:SetPoint("LEFT", findLabel, "RIGHT", 8, 0)
    self.findBox = box

    local note = Theme.CreateLabel(page, "small", "dim", "RIGHT")
    note:SetPoint("TOPRIGHT", -PAD, -14)
    self.note = note

    local body = CreateFrame("Frame", nil, page)
    body:SetPoint("TOPLEFT", PAD, -(TOP_ROW + 8))
    body:SetPoint("BOTTOMRIGHT", -PAD, FOOTER + 4)
    self.body = body

    local left = LeftWidth()
    local listWidth = WIDTH - PAD * 2 - left - SHEET - GAP * 2
    self:BuildFilters(left)
    self:BuildList(left + GAP, listWidth)
    self:BuildSheet(left + GAP + listWidth + GAP, SHEET)

    -- The footer: how many show and how many the filters hide, then the
    -- version on the right.
    local rule = Theme.CreateDivider(page, "border")
    rule:SetPoint("BOTTOMLEFT", PAD, FOOTER - 2)
    rule:SetPoint("BOTTOMRIGHT", -PAD, FOOTER - 2)
    local footer = Theme.CreateLabel(page, "small", "muted")
    footer:SetPoint("BOTTOMLEFT", PAD, 10)
    self.footer = footer
    local version = Theme.CreateLabel(page, "tiny", "dim", "RIGHT")
    version:SetPoint("BOTTOMRIGHT", -PAD, 10)
    version:SetText(ns.VersionLabel and ns.VersionLabel() or "")
    return page
end

--------------------------------------------------------------------------------
-- Looking and drawing
--------------------------------------------------------------------------------

--- "42 upgrades you can go and get. Your filters hide 6 more."
function Find.FooterText(shown, total, waiting, amber, specs, onSale)
    local parts = {}
    -- Both specs: "19 upgrades for Retribution, 11 for Protection."
    if specs then
        parts[#parts + 1] = L.Format("%d upgrades for %s, %d for %s.", specs[1], specs[2], specs[3], specs[4])
    elseif shown == 1 then
        parts[#parts + 1] = L["1 upgrade you can go and get."]
    elseif shown > 1 then
        parts[#parts + 1] = L.Format("%d upgrades you can go and get.", shown)
    end
    -- "4 are on the auction house."
    if (onSale or 0) == 1 then
        parts[#parts + 1] = L["1 is on the auction house."]
    elseif (onSale or 0) > 1 then
        parts[#parts + 1] = L.Format("%d are on the auction house.", onSale)
    end
    local hidden = math.max(0, total - shown)
    if hidden == 1 then
        parts[#parts + 1] = L["Your filters hide 1 more."]
    elseif hidden > 1 then
        parts[#parts + 1] = L.Format("Your filters hide %d more.", hidden)
    end
    if amber then parts[#parts + 1] = Colored("warn", L["Amber gear is for later: it says what it waits on."]) end
    if (waiting or 0) > 0 then
        parts[#parts + 1] = Colored("dim", (L.Format("  Still asking the server about %d items.", waiting):gsub("^%s+", "")))
    end
    return table.concat(parts, "  ")
end

--- What an empty list says, and the button under it.
function Find:PaintEmpty(state, total)
    local FinderUI = ns.FinderUI
    local found = state.found
    local empty = self.empty
    if #self.shown > 0 then
        empty:Hide()
        return
    end
    if not found then
        if state.why == "noweights" then
            empty:SetText(L.Format("There are no stat weights for %s yet.",
                ns.Weights:PlayerClass() or L["this class"]))
        elseif state.why then
            empty:SetText(L["Your level and faction aren't known yet. Try again in a moment."])
        else
            empty:SetText(L["Looking for your next upgrade..."])
        end
    elseif ns.Alts and ns.Alts:PlayerSkipped() then
        empty:SetText(L["Upgrades are skipped for this character. Untick it in Settings, or type /beq skip off."])
    elseif total == 0 and (found.waiting or 0) > 0 then
        empty:SetText(L["Asking the server about the gear on offer..."])
    elseif total > 0 then
        local here = FinderUI:Here(found)
        local words = total == 1 and L["Your filters hide 1 more."] or L.Format("Your filters hide %d more.", total)
        if here then words = L.Format("Nothing in %s beats what you wear.", here) .. " " .. words end
        empty:Set(words, L["Show All"], function() Find:ShowAll() end)
    else
        empty:SetText(L["Nothing on offer beats what you wear right now."])
    end
    empty:Show()
end

--- Filter and sort what was read, and draw it: for a tick box, a slot, a
--- heading or a letter typed. No gear is judged and no scan is made.
function Find:Narrow()
    local state = self.state
    if not (self.page and state) then return end
    self:LayColumns(self:Dual() and self:ShowWhich() == "both")
    local shown, counts = self:Filtered(state)
    self.shown = self:Sorted(shown)
    -- The biggest gain shown, for the bars under the gains.
    local most = 0
    for _, line in ipairs(self.shown) do
        local lead = line.main or line.off or line.pick
        if self:ShowWhich() == "off" then lead = line.off or lead end
        local percent = lead and lead.result and tonumber(lead.result.percent)
        if percent and percent > most then most = percent end
    end
    self.mostPercent = most
    self:PaintCounts(state.found and counts or nil)
    if self.auctionAge then self.auctionAge:SetText(Find.AuctionAgeText()) end
    self:PaintHeads()
    self:PaintRepStrip()
    self:MeasureList()

    -- The row picked stays picked while it shows; else the top row is.
    if not self:PickedLine() then self.picked = self.shown[1] and self.shown[1].key or nil end
    self:Draw()
    self:PaintSheet()

    local amber = false
    for _, line in ipairs(self.shown) do
        local pick = line.pick
        if pick.needs or pick.at or pick.remote or ns.Crafting.WearWaits(pick) then
            amber = true
            break
        end
    end
    self:PaintEmpty(state, #state.lines)
    local specs
    if self:Dual() and self:ShowWhich() == "both" then
        local mains, offs = 0, 0
        for _, line in ipairs(self.shown) do
            if line.main then mains = mains + 1 end
            if line.off then offs = offs + 1 end
        end
        local main, _, class = ns.Weights:MainSpec()
        specs = { mains, ns.Weights:SpecName(class, main) or "", offs, ns.OffSpec:Name() or "" }
    end
    local onSale = 0
    for _, line in ipairs(self.shown) do
        if Find.AuctionSource(line) then onSale = onSale + 1 end
    end
    self.footer:SetText(Find.FooterText(#self.shown, #state.lines, state.found and state.found.waiting, amber,
        specs, onSale))
end

--- Draw a scan (nil before the first one is in, with why it failed).
function Find:Present(found, why)
    if not self.page then return nil end
    self.lastFound, self.lastWhy = found, why
    local off = ns.OffSpec and ns.OffSpec:On() and self.offFound or nil
    local state = self:Read(found, off)
    state.why = why
    self.state = state
    self:SyncSpec()
    self.note:SetText(found and L["Updated when your gear changed"] or "")
    self:Narrow()
    return state
end

--- What a scan that plans ahead was made from: looked for again only when
--- one of these moved.
function Find:AheadKey(ahead)
    return ahead .. "|" .. tostring(Finder:JudgeKey()) .. "|" .. tostring(Finder.changes or 0)
end

--- Look and draw. For now, the finder's own scan when it is up to date,
--- else one made a slice per frame while what shows stays. Planning
--- ahead needs a scan of its own, kept until gear, level or a setting
--- changes.
--- The Off Spec's list for these choices (Logic/OffSpec.lua): kept when
--- still fresh, else made a slice per frame and drawn when it is in, the
--- last one showing meanwhile. Nothing with Off Spec on None.
function Find:LookOff(ahead)
    if not (ns.OffSpec and ns.OffSpec:On()) then
        self.offFound, self.offFor = nil, nil
        return
    end
    local kept = Finder:OffFound(ahead)
    if kept then
        self.offFound, self.offFor = kept, ahead
        return
    end
    if self.offFor ~= ahead then self.offFound = ahead == 0 and Finder:OffLatest() or nil end
    Finder:ScanOff(ahead, function(off)
        if not Find:IsShown() or Find:Ahead() ~= ahead then return end
        if off then Find.offFound, Find.offFor = off, ahead end
        if Find.lastFound then Find:Present(Find.lastFound, Find.lastWhy) end
    end)
end

function Find:Refresh()
    if not self:IsShown() then return nil end
    local ahead = self:Ahead()
    self:LookOff(ahead)
    if ahead <= 0 then
        local found = Finder:Fresh()
        if found then return self:Present(found) end
        if not self.state or (self.state.found and self.state.found.reach ~= self.state.found.player.level) then
            self:Present(Finder.latest)
        end
        Finder:ScanInBackground(function(scan, why)
            if not Find:IsShown() or Find:Ahead() > 0 then return end
            Find:Present(scan, why)
            -- Gear changed, or item answers came in, while it ran: look
            -- once more. Each scan clears the mark, so this stops.
            if Finder.stale and not Finder.background then Find:RefreshSoon() end
        end)
        return self.state
    end

    local key = self:AheadKey(ahead)
    if self.aheadFound and self.aheadKey == key then return self:Present(self.aheadFound) end
    if not self.state then self:Present(nil) end
    -- One for these choices is under way already.
    if self.slicing == key and Finder.sliced == self.slicedJob then return self.state end
    self.slicing = key
    Finder:ScanSliced(nil, ahead, function(found, why)
        Find.slicing = nil
        if found then Find.aheadFound, Find.aheadKey = found, key end
        if not Find:IsShown() or Find:Ahead() ~= ahead then return end
        Find:Present(found, why)
        -- Something moved while it ran: look once more.
        if Find:AheadKey(ahead) ~= key then Find:RefreshSoon() end
    end)
    self.slicedJob = Finder.sliced
    return self.state
end

--- Once for a burst of events, and only while the page shows.
function Find:RefreshSoon()
    if not self:IsShown() or self.pending then return end
    self.pending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0.5, function()
            Find.pending = false
            Find:Refresh()
        end)
    else
        self.pending = false
        self:Refresh()
    end
end

--- Draw the rows in view and the sheet again: a tag or a price moved, no
--- gear did. Once for a burst.
function Find:RedrawSoon()
    if not self:IsShown() or self.redrawPending then return end
    local after = C_Timer and C_Timer.After
    local function Run()
        Find.redrawPending = false
        if not Find:IsShown() then return end
        Find:Draw()
        Find:PaintSheet()
    end
    if type(after) ~= "function" then return Run() end
    self.redrawPending = true
    after(0.1, Run)
end

function Find:OnTrackingChanged()
    self:RedrawSoon()
end

--- The upgrade quest changed. It says so often (bags, the quest log, a
--- new zone), so the page moves only when the quests followed or the
--- ignored list did.
function Find:OnUpgradeQuestChanged()
    if not self:IsShown() then return end
    local quest = ns.UpgradeQuest
    if not quest then return end
    local ignored, followed = 0, {}
    for _ in pairs(quest:Skipped()) do ignored = ignored + 1 end
    if quest:IsEnabled() then
        for _, entry in pairs(quest:Quests()) do
            if type(entry) == "table" and entry.itemID then followed[#followed + 1] = entry.itemID end
        end
        table.sort(followed)
    end
    local mark = table.concat(followed, ",")
    if ignored ~= self.ignoredSeen then
        self.ignoredSeen, self.followedSeen = ignored, mark
        if self.state then self:Present(self.state.found, self.state.why) end
    elseif mark ~= self.followedSeen then
        self.followedSeen = mark
        self:RedrawSoon()
    end
end

--- Solo Quests Only or Quest Level changed, here, on the quest panel or
--- in Settings.
function Find:OnQuestFilterChanged()
    if not self.page then return end
    self:SyncFilters()
    self.offset = 0
    self:Refresh()
end

--- Is the page on screen? Not while its window is closed or folded, so
--- nothing here runs then.
function Find:IsShown()
    local page = self.page
    if not Shown(page) then return false end
    local ok, visible = pcall(page.IsVisible, page)
    if ok and type(visible) == "boolean" then return visible end
    return true
end

function Find:Show()
    if not self.page then return end
    local was = self:IsShown()
    self.page:Show()
    -- The old tabs' memory of which list was up: gear, not enchants.
    if ns.db and ns.db.finderShow == "enchant" then ns.db.finderShow = "all" end
    if not was then
        self.offset = 0
        self:SyncFilters()
        local quest = ns.UpgradeQuest
        if quest then
            local ignored = 0
            for _ in pairs(quest:Skipped()) do ignored = ignored + 1 end
            self.ignoredSeen = ignored
        end
    end
    self:Refresh()
end

function Find:Hide()
    if self.page then self.page:Hide() end
end

local EVENTS = {
    "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP", "QUEST_TURNED_IN", "TRAIT_CONFIG_UPDATED",
    "ZONE_CHANGED_NEW_AREA",
}

function Find:OnEnable()
    for _, event in ipairs(EVENTS) do
        ns.RegisterEvent(self, event, self.RefreshSoon)
    end
    -- A stack growing or shrinking changes no upgrade; gear coming or
    -- going does.
    ns.RegisterEvent(self, "BAG_UPDATE_DELAYED", function()
        if type(Finder.CarriedMoved) ~= "function" or Finder:CarriedMoved("findUpgrades") then
            Find:RefreshSoon()
        end
    end)
    -- Only a vendor's "need ... more" moves with the money: the sheet and
    -- the rows in view, once it settles.
    ns.RegisterEvent(self, "PLAYER_MONEY", function() Find:RedrawSoon() end)
    -- While the page is up the finder keeps asking the server about gear
    -- it has not seen, and the page looks again once the answers are in.
    local before = Finder.keepAsking
    Finder.keepAsking = function()
        if Find:IsShown() then return true end
        return type(before) == "function" and before() or false
    end
    if type(Finder.WatchAnswers) == "function" then
        Finder:WatchAnswers(function(again, done)
            if again or done then Find:RefreshSoon() end
        end)
    end
end

if ns.GearWindow then ns.GearWindow:AddPage("find", Find) end
