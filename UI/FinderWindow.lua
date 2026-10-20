-- Blackthornes Equipment -- UI/FinderWindow.lua
-- The "Where to get upgrades" window: the slots down the left, each with
-- how many upgrades it has, and for the slot picked every piece a vendor
-- sells, a quest gives, a dungeon or raid drops or a crafter makes that
-- beats what is worn, best first, and where to go for it (a player asked,
-- 2026-10-20, for a list per slot and a choice of sources). Tick boxes
-- pick the sources; "Only what I can get now" leaves out gear that waits
-- on a reputation or on a craft nobody of yours can make yet. The stepper
-- looks a few levels ahead; "This zone only" keeps the list to the zone the
-- character is in. Click a row to follow it as the upgrade quest
-- (Logic/UpgradeQuest.lua), right-click to track it (Logic/Tracking.lua),
-- Alt-click to pin its spot on the map (Logic/Waypoints.lua).
--
-- Opened from the gear window's "Find upgrades" button and /beq find. Built
-- like the gear window (same header, palette and rows). Logic/Finder.lua does
-- the looking; this only lays it out, and scans again as the server answers
-- about items the client had not seen yet.

local _, ns = ...
local L = ns.L

local FinderUI = ns.NewModule("FinderUI")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Motion = ns.Motion
local Finder = ns.Finder
local Weights = ns.Weights

local PADDING = 18
local HEADER = 36

-- The metal rim (UI/Titanforged.lua) reaches this far in from the edge;
-- the header sits inside it.
local RIM = 6
local FILTERS = 30
-- The quest filters' row, under the source buttons.
local QUEST_ROW = 28
local ROW_HEIGHT = 50
local VISIBLE = 9
local FOOTER = 48
local WIDTH = 900

-- The slots down the left, and the gap between them and the list.
local SLOT_COLUMN = 150
local COLUMN_GAP = 10
-- The list's own heading: the slot, what is worn there, and the order.
local LIST_HEAD = 30

-- The line under each item wraps onto a second line rather than being cut.
-- Wrapping breaks at spaces, so a little of each line goes unused.
local SOURCE_LINES = 2
local WRAP_SLACK = 60

local GAIN_WIDTH = 120
-- Queue it, under the gain on crafted rows.
local QUEUE_WIDTH = 64
local ICON = 28
local TEXT_X = ICON + 18
local SCROLL_WIDTH = 4

-- Where the list starts, and how wide its rows are.
local LIST_X = PADDING + SLOT_COLUMN + COLUMN_GAP
local INNER = WIDTH - LIST_X - PADDING - SCROLL_WIDTH - 6

-- Some gear is sold by a dozen vendors; the tooltip lists this many.
local TOOLTIP_SOURCES = 8

local HEIGHT = HEADER + 10 + FILTERS + QUEST_ROW + 8 + LIST_HEAD + VISIBLE * ROW_HEIGHT + FOOTER

-- The tag in front of a source, in its own colour.
local KIND_COLORS = { vendor = "accent", quest = "quest", dungeon = "dungeon", craft = "craft" }

-- A tick box for each kind of source, in this order. Raids are dungeon
-- drops from a raid (FinderUI.SourceKind).
local SOURCE_BOXES = {
    { "vendor", L["Vendor"] }, { "quest", L["Quest"] }, { "dungeon", L["Dungeons"] },
    { "raid", L["Raids"] }, { "craft", L["Crafted"] },
}
FinderUI.SOURCE_BOXES = SOURCE_BOXES

-- The slots down the left, in character sheet order: { slot, name, the
-- second slot }. Both rings are one line, and both trinkets.
local SLOT_GROUPS = {
    { 1, L["Head"] }, { 2, L["Neck"] }, { 3, L["Shoulder"] }, { 15, L["Back"] },
    { 5, L["Chest"] }, { 9, L["Wrist"] }, { 10, L["Hands"] }, { 6, L["Waist"] },
    { 7, L["Legs"] }, { 8, L["Feet"] }, { 11, L["Rings"], 12 }, { 13, L["Trinkets"], 14 },
    { 16, L["Main hand"] }, { 17, L["Off hand"] }, { 18, L["Ranged"] },
}
FinderUI.SLOT_GROUPS = SLOT_GROUPS

-- The line a slot is shown on, by slot.
local GROUP_OF = {}
for _, group in ipairs(SLOT_GROUPS) do
    GROUP_OF[group[1]] = group[1]
    if group[3] then GROUP_OF[group[3]] = group[1] end
end
FinderUI.GROUP_OF = GROUP_OF

-- Each slot's line runs the list's full height.
local SLOT_ROW = math.floor((LIST_HEAD + VISIBLE * ROW_HEIGHT) / #SLOT_GROUPS)

-- How many levels ahead the stepper can look.
local MOST_AHEAD = 10

--------------------------------------------------------------------------------
-- Text that fits
--------------------------------------------------------------------------------

--- `text` cut down with "..." until it fits in `width` pixels at `size`.
-- Measured, never guessed: the game's font runs wider than it looks.
-- Colour codes take no room and are kept whole, so a cut line keeps its
-- green zone, its source colour and its tags; a colour left open by the
-- cut is closed.
function FinderUI.Fit(size, text, width)
    if Theme.TextWidth(size, text) <= width then return text end

    -- The text as pieces: a colour code, a colour end, or one character.
    local pieces, visible = {}, 0
    local index = 1
    while index <= #text do
        local code = text:match("^|c%x%x%x%x%x%x%x%x", index)
        if code then
            pieces[#pieces + 1] = { code, open = true }
            index = index + #code
        elseif text:sub(index, index + 1) == "|r" then
            pieces[#pieces + 1] = { "|r", close = true }
            index = index + 2
        else
            -- A whole character, never half of one ("Zul'Farrak" is plain,
            -- but a name with an accent is two bytes).
            local char = text:match("^[\194-\244][\128-\191]*", index) or text:sub(index, index)
            pieces[#pieces + 1] = { char, char = true }
            visible = visible + 1
            index = index + #char
        end
    end

    -- The first `count` characters, with every code before them.
    local function Prefix(count)
        local out, seen, open = {}, 0, false
        for _, piece in ipairs(pieces) do
            if piece.char then
                if seen >= count then break end
                seen = seen + 1
            elseif piece.open then
                open = true
            elseif piece.close then
                open = false
            end
            out[#out + 1] = piece[1]
        end
        local cut = table.concat(out):gsub("%s+$", "")
        return cut, open
    end
    local function Line(count)
        local cut, open = Prefix(count)
        return cut .. "..." .. (open and "|r" or "")
    end

    local low, high = 0, visible
    while low < high do
        local mid = math.ceil((low + high) / 2)
        if Theme.TextWidth(size, Line(mid)) <= width then
            low = mid
        else
            high = mid - 1
        end
    end
    return Line(low)
end

local function Colored(key, text)
    local r, g, b = Theme.Unpack(key)
    return ("|cff%02x%02x%02x%s|r"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
        math.floor(b * 255 + 0.5), text)
end

--- The zone the character is in, named in green wherever `text` names it
--- as a whole word (a player asked, 2026-10-09: easier to spot what is
--- nearby).
function FinderUI.MarkZone(text, zone)
    if not (zone and text) or zone == "" then return text end
    local pattern = "%f[%w]" .. zone:gsub("[%%%^%$%(%)%.%[%]%*%+%-%?]", "%%%0") .. "%f[%W]"
    return (text:gsub(pattern, function(found) return Colored("good", found) end))
end

--- A source as one line: the coloured kind, then where, the zone the
--- character is in shown in green.
function FinderUI.SourceLine(source, zone)
    zone = zone or (ns.UpgradeQuest and ns.UpgradeQuest.Zone())
    local line = Colored(KIND_COLORS[source.kind] or "text", Finder.Label(source))
        .. "  " .. FinderUI.MarkZone(Finder:Describe(source), zone)
    -- Seen on Forever, the way Farmer marks what it has confirmed.
    if source.forever then line = line .. "  " .. Colored("good", "[Forever]") end
    return line
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

local function ShowEnchantTooltip(row, line)
    local Enchants = ns.Enchants
    local pick, source = line.pick, line.source
    local r, g, b = Theme.Unpack("text")
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(Enchants:ShownName(pick.recipeID) or "", Theme.Unpack("accent"))
    GameTooltip:AddLine(L.Format("For your %s", line.plan.link or Enchants.SlotName(line.slot)), r, g, b, true)
    GameTooltip:AddLine(L.Format("Gives %s", Enchants:Gives(pick.recipeID) or ""), Theme.Unpack("good"))
    if line.plan.current then
        GameTooltip:AddLine(L.Format("Now: %s", Enchants:EnchantName(line.plan.current)), r, g, b, true)
    else
        GameTooltip:AddLine(L["Nothing on it now"], r, g, b)
    end
    if pick.percent then
        GameTooltip:AddLine(L.Format("%d%% better for your spec", math.floor(pick.percent + 0.5)), Theme.Unpack("good"))
    end
    if line.soon then
        local wr, wg, wb = Theme.Unpack("warn")
        GameTooltip:AddLine(L["A better piece for this slot is in your upgrade list. This is the cheapest enchant still worth having until then."],
            wr, wg, wb, true)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["How to get it"], Theme.Unpack("accent"))
    GameTooltip:AddLine(Enchants:Describe(source, Finder.Money), r, g, b, true)
    local materials = Enchants:MaterialsText(pick.recipeID)
    if materials ~= "" then
        GameTooltip:AddLine(L.Format("Materials: %s", materials), r, g, b, true)
    end
    local place = (source and (source.state == "learn" or source.state == "skill"))
        and Enchants:WhereToLearn(pick.recipeID)
    if place and place.name then
        local where = place.zone and L.Format("Learn it from %s in %s", place.name, place.zone)
            or L.Format("Learn it from %s", place.name)
        GameTooltip:AddLine(where, r, g, b, true)
    end
    GameTooltip:Show()
end

local function ShowTooltip(row)
    local enchant = rawget(row, "enchant")
    if enchant then return ShowEnchantTooltip(row, enchant) end
    local pick = row.pick
    if not pick then return end

    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    pcall(GameTooltip.SetHyperlink, GameTooltip, pick.link)
    GameTooltip:AddLine(" ")
    if pick.needs then
        GameTooltip:AddLine(Finder.NeedsText(pick.needs), Theme.Unpack("warn"))
    end
    if pick.at then
        GameTooltip:AddLine(L.Format("You can wear it from level %d", pick.at), Theme.Unpack("warn"))
    end
    local roll = Finder.RollText(pick)
    if roll then
        local r, g, b = Theme.Unpack("good")
        GameTooltip:AddLine(roll, r, g, b, true)
    end
    GameTooltip:AddLine(L["Where to get it"], Theme.Unpack("accent"))
    for index, source in ipairs(pick.sources) do
        if index > TOOLTIP_SOURCES then
            GameTooltip:AddLine(L.Format("and %d more", #pick.sources - TOOLTIP_SOURCES),
                Theme.Unpack("muted"))
            break
        end
        GameTooltip:AddLine(FinderUI.SourceLine(source), Theme.Unpack("text"))
        if source.after then
            GameTooltip:AddLine(L.Format("    after %s", source.after), Theme.Unpack("muted"))
        end
        if source.kind == "craft" and ns.Crafting then
            -- Light, so it reads on the tooltip's dark background.
            local r, g, b = Theme.Unpack("text")
            GameTooltip:AddLine(L.Format("    Materials: %s", ns.Crafting:MaterialsText(pick.itemID)), r, g, b, true)
        end
    end
    GameTooltip:AddLine(" ")
    local quest = ns.UpgradeQuest
    if quest then
        local _, why = quest.CanFollow(pick)
        -- What a click does, said plainly: players took the green Quest
        -- tag it leaves for a mistake (2026-10-09).
        local r, g, b = Theme.Unpack("text")
        if quest:IsFollowing(pick.itemID) then
            GameTooltip:AddLine(L["Your upgrade quest: click to show it on the quest panel"], Theme.Unpack("good"))
            GameTooltip:AddLine(L["The green Quest tag marks it. To drop it, click Ignore on the quest panel."], r, g, b, true)
        elseif why then
            local wr, wg, wb = Theme.Unpack("warn")
            GameTooltip:AddLine(L.Format("Not a quest yet: %s", why), wr, wg, wb, true)
        else
            GameTooltip:AddLine(L["Click to follow it on the quest panel"], Theme.Unpack("good"))
            GameTooltip:AddLine(L["It becomes your upgrade quest, with steps to get it. A green Quest tag marks it here."], r, g, b, true)
        end
    end
    local tracked = ns.Tracking and ns.Tracking:IsTracked(pick.itemID)
    GameTooltip:AddLine(tracked and L["Right-click to stop tracking it"] or L["Right-click to track it"],
        Theme.Unpack("muted"))
    if FinderUI.Place(pick) then
        GameTooltip:AddLine(L["Alt-click to pin it on your map"], Theme.Unpack("muted"))
    end
    GameTooltip:Show()
end

function FinderUI:BuildRow(index)
    local inner = INNER
    local row = CreateFrame("Button", nil, self.frame)
    -- Above the well, whatever order the client draws siblings in.
    row:SetFrameLevel(self.well:GetFrameLevel() + 1)
    row:SetSize(inner, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", LIST_X, self.rowsTop - (index - 1) * ROW_HEIGHT)
    row.restKey = index % 2 == 0 and "glassAlt" or "glass"
    row.background = Theme.Fill(row, row.restKey)

    -- Dark glass: a fine line under each row.
    local line = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetHeight(1)
    line:SetColorTexture(Theme.Unpack("border", 0.6))

    -- A green edge that lights under the mouse.
    local edge = row:CreateTexture(nil, "ARTWORK")
    edge:SetPoint("TOPLEFT")
    edge:SetPoint("BOTTOMLEFT")
    edge:SetWidth(2)
    edge:SetColorTexture(Theme.Unpack("good", 0))
    row.edge = edge

    -- Under the mouse the row lights from the left too: a soft gold wash
    -- fading across it (Titanforged). Hidden at rest.
    local wash = row:CreateTexture(nil, "BACKGROUND", nil, 3)
    wash:SetAllPoints(row)
    wash:Hide()
    row.hoverWash = wash

    local icon = Theme.CreateItemIcon(row, ICON)
    icon:SetPoint("LEFT", 10, 0)
    row.icon = icon

    local item = Theme.CreateLabel(row, "normal", "text")
    item:SetPoint("TOPLEFT", TEXT_X, -6)
    item:SetWidth(inner - TEXT_X - GAIN_WIDTH - 8)
    row.item = item
    row.itemRoom = inner - TEXT_X - 8

    local gain = Theme.CreateLabel(row, "normal", "good", "RIGHT")
    gain:SetPoint("TOPRIGHT", -8, -6)
    gain:SetWidth(GAIN_WIDTH)
    row.gain = gain

    local source = Theme.CreateLabel(row, "tiny", "muted")
    source:SetPoint("TOPLEFT", TEXT_X, -23)
    source:SetWidth(inner - TEXT_X - 8)
    source:SetWordWrap(true)
    pcall(source.SetMaxLines, source, SOURCE_LINES)
    row.source = source
    row.sourceWidth = inner - TEXT_X - 8
    row.fullSourceWidth = row.sourceWidth

    -- Queue it, on crafted gear while Tradeskills is loaded: sends the craft,
    -- or what to buy, to Tradeskills' queue (Logic/TradeskillsQueue.lua).
    local queueIt = Widgets.CreateButton(row, L["Queue it"], function(self)
        local enchant = rawget(self, "enchant")
        if enchant and ns.Enchants then
            ns.Enchants:Queue(enchant.pick.recipeID)
            return
        end
        local craft = rawget(self, "source")
        if craft and ns.TradeskillsQueue then
            ns.TradeskillsQueue:Queue(craft)
            FinderUI:Draw()
        end
    end, { width = QUEUE_WIDTH, height = 18 })
    queueIt:SetPoint("BOTTOMRIGHT", -8, 5)
    queueIt:HookScript("OnEnter", function(self)
        local enchant = rawget(self, "enchant")
        if enchant and ns.Enchants then
            local source = enchant.source
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(L["Queue it"], Theme.Unpack("accent"))
            local known = source and (source.state == "known" or source.state == "alt")
            local text = known and L["Puts the enchant in Tradeskills' queue."]
                or (source and source.kit and source.state == "other") and L["Puts it on Tradeskills' shopping list."]
                or L["Puts its materials on Tradeskills' shopping list."]
            GameTooltip:AddLine(text, 1, 1, 1, true)
            GameTooltip:Show()
            return
        end
        local craft = rawget(self, "source")
        if not (craft and ns.TradeskillsQueue) then return end
        local title, text = ns.TradeskillsQueue:Explain(craft)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(title, Theme.Unpack("accent"))
        if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    queueIt:HookScript("OnLeave", function() GameTooltip:Hide() end)
    queueIt:Hide()
    row.queueIt = queueIt

    -- Show the way, on enchants still to learn: pins the trainer or vendor
    -- through Tradeskills.
    local showWay = Widgets.CreateButton(row, L["Show the way"], function(self)
        local enchant = rawget(self, "enchant")
        if not (enchant and ns.Enchants) then return end
        if not ns.Enchants:ShowTheWay(enchant.pick.recipeID) then
            ns.Print(L["Couldn't find where to learn it."])
        end
    end, { width = QUEUE_WIDTH, height = 18 })
    showWay:SetPoint("BOTTOMRIGHT", -8, 5)
    showWay:Hide()
    row.showWay = showWay

    local function Light(p)
        row.background:SetColorTexture(Motion.Mix(row.restKey, "glassHover", p))
        row.edge:SetColorTexture(Theme.Unpack(rawget(row, "edgeKey") or "good", p))
        Theme.LightGradient(wash, "HORIZONTAL", "accent", 0.10, 0, p)
    end

    row:SetScript("OnEnter", function(self)
        self.over = true
        Motion:Blend(self, "hover", 1, 0.12, Light)
        ShowTooltip(self)
    end)
    row:SetScript("OnLeave", function(self)
        self.over = false
        Motion:Blend(self, "hover", 0, 0.18, Light)
        GameTooltip:Hide()
    end)
    row:SetScript("OnClick", function(self, button)
        -- An enchant row's buttons do its work; Shift-click links its recipe.
        local enchant = rawget(self, "enchant")
        if enchant then
            if type(IsModifiedClick) == "function" and type(ChatEdit_InsertLink) == "function" then
                local ok, chatLink = pcall(IsModifiedClick, "CHATLINK")
                if ok and chatLink then
                    local okLink, link = pcall(function()
                        local spell = _G.C_Spell and _G.C_Spell.GetSpellLink
                        return spell and spell(enchant.pick.recipeID) or nil
                    end)
                    if okLink and link then pcall(ChatEdit_InsertLink, link) end
                end
            end
            return
        end
        local pick = self.pick
        if not pick then return end
        if button == "RightButton" then
            if ns.Tracking then ns.Tracking:Toggle(pick) end
            if rawget(self, "over") == true then ShowTooltip(self) end
            return
        end
        local okAlt, alt = pcall(function() return IsAltKeyDown() == true end)
        if okAlt and alt then
            local place = FinderUI.Place(pick)
            if place and ns.Waypoints then ns.Waypoints:Show(place, place.name) end
            return
        end
        if type(IsModifiedClick) == "function" and type(ChatEdit_InsertLink) == "function" then
            local ok, chatLink = pcall(IsModifiedClick, "CHATLINK")
            if ok and chatLink then
                pcall(ChatEdit_InsertLink, pick.link)
                return
            end
        end
        -- A plain click follows it on the upgrade quest panel (asked 2026-10-06).
        FinderUI:Follow(pick)
        if rawget(self, "over") == true then ShowTooltip(self) end
    end)
    if row.RegisterForClicks then row:RegisterForClicks("LeftButtonUp", "RightButtonUp") end

    row:Hide()
    return row
end

function FinderUI:Build()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "BlackthornesEquipmentFinder", UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    Theme.Fill(frame, "window")

    -- The house frame, as the gear window wears it (UI/Titanforged.lua).
    if ns.Titanforged then
        local trim = ns.Titanforged:Dress(frame, {
            title = L["Where to get upgrades"],
            portrait = true,
            close = function() FinderUI:Hide() end,
        })

        -- Kept on the screen whole: the portrait and plate reach out past
        -- the top left, the close gem past the top right.
        local left, right, top, bottom = ns.Titanforged.Reach(trim)
        if frame.SetClampRectInsets then frame:SetClampRectInsets(-left, right, top, -bottom) end
    else
        Theme.Border(frame, "borderLit")
    end
    Theme.Halo(frame, 12, 0.14)

    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if ns.db then ns.db.finderMoved = true end
        FinderUI:SavePosition()
    end)
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta) FinderUI:ScrollBy(-delta) end)

    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "BlackthornesEquipmentFinder")
    end

    self.frame = frame
    self:BuildHeader()
    self:BuildFilters()

    self.listTop = -(HEADER + 10 + FILTERS + QUEST_ROW + 8)
    self.rowsTop = self.listTop - LIST_HEAD
    local listHeight = LIST_HEAD + VISIBLE * ROW_HEIGHT

    self:BuildSlots(listHeight)

    -- The list sits sunk into the window, as the game's inset lists do.
    local well = Theme.CreatePanel(frame, "panel", "border")
    well:SetPoint("TOPLEFT", LIST_X - 3, self.listTop + 3)
    well:SetPoint("TOPRIGHT", -(PADDING - 3), self.listTop + 3)
    well:SetHeight(listHeight + 6)
    Theme.Recess(well)
    self.well = well

    self:BuildListHead()

    self.rows = {}
    for index = 1, VISIBLE do self.rows[index] = self:BuildRow(index) end

    -- A thin track down the right of the list, and a thumb that shows where
    -- in it the view is. On the well, or the well would hide them.
    local track = well:CreateTexture(nil, "ARTWORK")
    track:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING, self.rowsTop)
    track:SetSize(SCROLL_WIDTH, VISIBLE * ROW_HEIGHT)
    track:SetColorTexture(Theme.Unpack("rowAlt"))
    self.track = track

    local thumb = well:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(SCROLL_WIDTH)
    thumb:SetColorTexture(Theme.Unpack("accent", 0.8))
    -- The game's scroll knob in the Blizzard window style (UI/BlizzardLook.lua).
    -- The knob art needs more than the 4 px bar: it takes the 6 px gap
    -- beside the rows too, or it is squeezed to a smear.
    if ns.BlizzardLook and ns.BlizzardLook.Thumb(thumb) then thumb:SetWidth(SCROLL_WIDTH + 6) end
    self.thumb = thumb

    local empty = Theme.CreateLabel(well, "normal", "muted", "CENTER")
    empty:SetPoint("TOP", well, "TOP", 0, -(LIST_HEAD + 60))
    empty:SetWidth(INNER - 40)
    empty:SetWordWrap(true)
    self.empty = empty

    local footer = Theme.CreateLabel(frame, "small", "text")
    footer:SetPoint("BOTTOMLEFT", PADDING, 26)
    footer:SetWidth(WIDTH - PADDING * 2)
    self.footer = footer

    local hint = Theme.CreateLabel(frame, "tiny", "dim")
    hint:SetPoint("BOTTOMLEFT", PADDING, 10)
    hint:SetWidth(WIDTH - PADDING * 2)
    hint:SetText(L["Click a row to follow it. Right-click to track it."])
    self.hint = hint

    frame:Hide()
    return frame
end

--- The slots down the left: a dark glass line each, its name and how many
--- upgrades it has, the one picked lit gold. A click shows its list.
function FinderUI:BuildSlots(height)
    local frame = self.frame
    local column = Theme.CreatePanel(frame, "panel", "border")
    column:SetPoint("TOPLEFT", PADDING - 3, self.listTop + 3)
    column:SetSize(SLOT_COLUMN + 6, height + 6)
    Theme.Recess(column)
    self.slotWell = column

    self.slotButtons = {}
    for index, group in ipairs(SLOT_GROUPS) do
        local button = CreateFrame("Button", nil, frame)
        button:SetFrameLevel(column:GetFrameLevel() + 1)
        button:SetSize(SLOT_COLUMN, SLOT_ROW)
        button:SetPoint("TOPLEFT", PADDING, self.listTop - (index - 1) * SLOT_ROW)
        button.group = group[1]
        button.restKey = index % 2 == 0 and "glassAlt" or "glass"
        button.background = Theme.Fill(button, button.restKey)

        local line = button:CreateTexture(nil, "BACKGROUND", nil, 1)
        line:SetPoint("BOTTOMLEFT")
        line:SetPoint("BOTTOMRIGHT")
        line:SetHeight(1)
        line:SetColorTexture(Theme.Unpack("border", 0.6))

        -- Gold down the left of the one picked, and of the one under the mouse.
        local edge = button:CreateTexture(nil, "ARTWORK")
        edge:SetPoint("TOPLEFT")
        edge:SetPoint("BOTTOMLEFT")
        edge:SetWidth(3)
        edge:SetColorTexture(Theme.Unpack("accentHi"))
        edge:Hide()
        button.edge = edge

        -- How many, on a small gold-edged badge at the right.
        local badge = CreateFrame("Frame", nil, button)
        badge:SetSize(26, 16)
        badge:SetPoint("RIGHT", -8, 0)
        badge.background = Theme.Fill(badge, "glassActive")
        Theme.Border(badge, "metal")
        local count = Theme.CreateLabel(badge, "small", "accent", "CENTER")
        count:SetPoint("CENTER", 0, 0)
        button.badge, button.count = badge, count

        local name = Theme.CreateLabel(button, "normal", "text")
        name:SetPoint("LEFT", 12, 0)
        name:SetPoint("RIGHT", badge, "LEFT", -4, 0)
        name:SetText(group[2])
        button.name = name

        button:SetScript("OnEnter", function(self)
            self.over = true
            FinderUI:PaintSlot(self)
        end)
        button:SetScript("OnLeave", function(self)
            self.over = false
            FinderUI:PaintSlot(self)
        end)
        button:SetScript("OnClick", function(self) FinderUI:PickSlot(self.group) end)
        self.slotButtons[index] = button
    end
end

--- One slot's line as it stands: picked, under the mouse, or at rest, and
--- dim when it has nothing.
function FinderUI:PaintSlot(button)
    local picked = button.group == self.slot
    local over = rawget(button, "over") == true
    button.background:SetColorTexture(Theme.Unpack(picked and "glassActive" or over and "glassHover" or button.restKey))
    button.edge:SetShown(picked or over)
    button.edge:SetColorTexture(Theme.Unpack(picked and "accentHi" or "accent"))
    local some = (tonumber(button.count:GetText()) or 0) > 0
    button.name:SetTextColor(Theme.Unpack(picked and "accentHi" or some and "text" or "muted"))
    button.badge.background:SetColorTexture(Theme.Unpack(picked and "accent" or "glassActive"))
    button.count:SetTextColor(Theme.Unpack(picked and "ink" or some and "accent" or "dim"))
end

--- The heading over the list: the slot's name, what is worn there, and the
--- order the list runs in.
function FinderUI:BuildListHead()
    local well = self.well
    local head = CreateFrame("Frame", nil, self.frame)
    head:SetFrameLevel(well:GetFrameLevel() + 1)
    head:SetPoint("TOPLEFT", LIST_X, self.listTop)
    head:SetSize(INNER + SCROLL_WIDTH + 6, LIST_HEAD)

    local rule = head:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    rule:SetHeight(1)
    Theme.SetGradientAlpha(rule, "HORIZONTAL", "accent", 0.5, 0.05)

    local title = Theme.CreateLabel(head, "large", "accentHi")
    title:SetPoint("LEFT", 12, 0)
    self.listTitle = title

    local sort = Theme.CreateLabel(head, "small", "muted", "RIGHT")
    sort:SetPoint("RIGHT", -10, 0)
    sort:SetText(L.Format("Sort: %s", Colored("accent", L["Best first"])))
    self.sortLabel = sort

    local worn = Theme.CreateLabel(head, "small", "muted")
    worn:SetPoint("LEFT", title, "RIGHT", 12, 0)
    worn:SetPoint("RIGHT", sort, "LEFT", -12, 0)
    worn:SetWordWrap(false)
    self.wornLabel = worn
end

function FinderUI:BuildHeader()
    local frame = self.frame

    -- The window's name is on the plate and the close gem on the top right
    -- corner (UI/Titanforged.lua), so the header holds the spec line, clear
    -- of the portrait on the left and a little low, under the plate.
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", RIM, 0)
    header:SetPoint("TOPRIGHT", -RIM, 0)
    header:SetHeight(HEADER)

    local spec = Theme.CreateLabel(header, "small", "muted")
    spec:SetPoint("LEFT", 58 - RIM, -4)
    spec:SetPoint("RIGHT", -(PADDING + 16 - RIM), -4)
    self.specLabel = spec

    -- A gold rule under it, bright at the left and fading out to the right.
    local rule = header:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    rule:SetHeight(1)
    Theme.SetGradientAlpha(rule, "HORIZONTAL", "accent", 0.6, 0.05)
end

function FinderUI:BuildFilters()
    -- A few pixels lower than the header's foot, clear of the round
    -- portrait above it.
    local topY = -(HEADER + 13)
    local show = Theme.CreateLabel(self.frame, "small", "muted")
    show:SetPoint("TOPLEFT", PADDING, topY - 4)
    show:SetText(L["Show:"])
    self.showLabel = show

    -- The sources, a tick box each: any mix of them, saved as the ones
    -- turned off (`finderSourcesOff`), so a new kind shows until unticked.
    self.sourceBoxes = {}
    local previous = show
    for _, entry in ipairs(SOURCE_BOXES) do
        local kind = entry[1]
        local box = Widgets.CreateCheckbox(self.frame, entry[2], function(checked)
            FinderUI:SetSource(kind, checked)
        end, self:SourceOn(kind))
        box:SetPoint("LEFT", previous, "RIGHT", previous == show and 10 or 18, 0)
        box.kind = kind
        self.sourceBoxes[#self.sourceBoxes + 1] = box
        previous = box
    end

    -- Plan ahead: "Now", or a level up to MOST_AHEAD past the character's.
    local ahead = Widgets.CreateStepper(self.frame, {
        min = 0, max = MOST_AHEAD, step = 1, value = self:Ahead(),
        format = function(value) return FinderUI.AheadText(value) end,
        onChange = function(value)
            if ns.db then ns.db.finderAhead = value end
            FinderUI.offset = 0
            FinderUI:Refresh()
        end,
    })
    ahead:SetPoint("TOPRIGHT", -PADDING, -(HEADER + 14))
    self.ahead = ahead

    -- The Enchants view: enchants for what you wear, slot by slot. A second
    -- click goes back to gear; a gold bar under it while it shows.
    local enchants = Widgets.CreateButton(self.frame, L["Enchants"], function()
        FinderUI:SetFilter(not FinderUI:ShowingEnchants() and "enchant" or nil)
    end, { width = 80, height = 22 })
    enchants:SetPoint("RIGHT", ahead, "LEFT", -14, 0)
    local mark = enchants:CreateTexture(nil, "OVERLAY")
    mark:SetPoint("BOTTOMLEFT", 1, 1)
    mark:SetPoint("BOTTOMRIGHT", -1, 1)
    mark:SetHeight(2)
    mark:SetColorTexture(Theme.Unpack("accent"))
    enchants.mark = mark
    self.enchantsButton = enchants

    -- The second row: what to leave out on the left, how far above the
    -- character a quest may be on the right. The upgrade quest follows the
    -- quest filters too.
    local rowY = -(HEADER + 13 + FILTERS + 1)

    -- Leave out gear that waits on a reputation not reached yet, or on a
    -- craft nobody of yours can make yet.
    local now = Widgets.CreateCheckbox(self.frame, L["Only what I can get now"], function(checked)
        FinderUI:SetGetNowOnly(checked)
    end, self:GetNowOnly())
    now:SetPoint("TOPLEFT", PADDING, rowY - 1)
    self.getNow = now

    -- Only gear from the zone the character is in, as the upgrade quest
    -- panel's box of the same name does (each keeps its own setting).
    local zone = Widgets.CreateCheckbox(self.frame, L["This zone only"], function(checked)
        FinderUI:SetZoneOnly(checked)
    end, self:ZoneOnly())
    zone:SetPoint("LEFT", now, "RIGHT", 24, 0)
    zone:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L["This zone only"], Theme.Unpack("accent"))
        GameTooltip:AddLine(L["Only upgrades from the zone you're in, plus gear you can make. The list changes as you travel."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    zone:HookScript("OnLeave", function() GameTooltip:Hide() end)
    self.zone = zone

    -- Hide quests that need a group, a dungeon, a raid or a battleground.
    -- The same switch as in Settings.
    local solo = Widgets.CreateCheckbox(self.frame, L["Solo quests only"], function(checked)
        Finder:SetSoloOnly(checked)
    end, Finder:SoloOnly())
    solo:SetPoint("LEFT", zone, "RIGHT", 24, 0)
    solo:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L["Solo quests only"], Theme.Unpack("accent"))
        GameTooltip:AddLine(L["Hides quests that need a group, and the quests after them. Elite kills count as group quests."],
            1, 1, 1, true)
        GameTooltip:Show()
    end)
    solo:HookScript("OnLeave", function() GameTooltip:Hide() end)
    self.solo = solo

    local questLevels = Widgets.CreateStepper(self.frame, {
        min = 0, max = Finder.QUEST_LEVELS_ANY, step = 1, value = self:QuestLevelsValue(),
        format = function(value) return FinderUI.QuestLevelsText(value) end,
        onChange = function(value) Finder:SetQuestLevelsAbove(value) end,
    })
    questLevels:SetWidth(150)
    questLevels:SetPoint("TOPRIGHT", -PADDING, rowY)
    questLevels:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L["Quest level"], Theme.Unpack("accent"))
        GameTooltip:AddLine(L["How far above your level a quest can be."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    questLevels:HookScript("OnLeave", function() GameTooltip:Hide() end)
    self.questLevels = questLevels

    local levelLabel = Theme.CreateLabel(self.frame, "small", "muted", "RIGHT")
    levelLabel:SetPoint("RIGHT", questLevels, "LEFT", -10, 0)
    levelLabel:SetText(L["Quest level"])
    self.levelLabel = levelLabel
end

--- Is "Only what I can get now" ticked? Saved account wide as
--- `finderGetNow`, off unless ticked.
function FinderUI:GetNowOnly()
    return ns.db ~= nil and ns.db.finderGetNow == true
end

function FinderUI:SetGetNowOnly(on)
    if not ns.db then return end
    ns.db.finderGetNow = on and true or false
    if self.getNow then self.getNow:SetChecked(ns.db.finderGetNow) end
    self.offset = 0
    self:Redraw()
end

--- Can this source be used now? Not for gear that waits on a reputation
--- not reached, nor a craft that you or your other characters can't make
--- yet (one still to learn, or someone else's).
function FinderUI.GetsNow(source, pick)
    if pick.needs then return false end
    if source.kind == "craft" then return source.state == "known" or source.state == "alt" end
    return true
end

--- The tick box a source counts under: "raid" for a raid's drop, else its
--- kind.
function FinderUI.SourceKind(source)
    if source.kind == "dungeon" and source.raid then return "raid" end
    return source.kind
end

--- Is this kind of source ticked? Every kind is until unticked.
function FinderUI:SourceOn(kind)
    local off = ns.db and ns.db.finderSourcesOff
    return not (type(off) == "table" and off[kind] == true)
end

function FinderUI:SetSource(kind, on)
    if not ns.db then return end
    if type(ns.db.finderSourcesOff) ~= "table" then ns.db.finderSourcesOff = {} end
    ns.db.finderSourcesOff[kind] = (not on) or nil
    for _, box in ipairs(self.sourceBoxes or {}) do
        if box.kind == kind then box:SetChecked(on) end
    end
    self.offset = 0
    self:Redraw()
end

--- Draw again from the last scan, for a change that needs no new look (a
--- tick box, a slot): the scan holds every source, so only the lines move.
function FinderUI:Redraw()
    if not (self.frame and self.frame:IsShown()) then return end
    if self:ShowingEnchants() or not self.found then
        self:Refresh()
    else
        self:Present(self.found)
    end
end

--- Is "This zone only" ticked? Saved account wide as `finderZoneOnly`,
--- off unless ticked.
function FinderUI:ZoneOnly()
    return ns.db ~= nil and ns.db.finderZoneOnly == true
end

function FinderUI:SetZoneOnly(on)
    if not ns.db then return end
    ns.db.finderZoneOnly = on and true or false
    if self.zone then self.zone:SetChecked(ns.db.finderZoneOnly) end
    self.offset = 0
    self:Refresh()
end

--- The zone the list keeps to, or nil for anywhere.
function FinderUI:Here(found)
    if not self:ZoneOnly() then return nil end
    local quest = ns.UpgradeQuest
    return quest and quest.Zone() or (found and found.player and found.player.zone) or nil
end

--- "Solo quests only" changed, here or in Settings.
function FinderUI:OnQuestFilterChanged()
    if self.solo then self.solo:SetChecked(Finder:SoloOnly()) end
    if self.questLevels then self.questLevels:SetValue(self:QuestLevelsValue(), true) end
    self.offset = 0
    self:Refresh()
end

--- The quest level stepper's place: 0 to 10 levels up, or 11 for any.
function FinderUI:QuestLevelsValue()
    return Finder:QuestLevelsAbove() or Finder.QUEST_LEVELS_ANY
end

--- Its words: "Up to my level", "Up to +4" or "Any".
function FinderUI.QuestLevelsText(value)
    if (value or 0) >= Finder.QUEST_LEVELS_ANY then return L["Any"] end
    if (value or 0) <= 0 then return L["Up to my level"] end
    return L.Format("Up to +%d", value)
end

--- How many levels ahead the window looks (0 for now).
function FinderUI:Ahead()
    local value = tonumber(ns.db and ns.db.finderAhead) or 0
    return math.max(0, math.min(MOST_AHEAD, math.floor(value)))
end

--- The stepper's words: "Now", or "Level 27".
function FinderUI.AheadText(value)
    if (value or 0) <= 0 then return L["Now"] end
    local level = ns.Items and ns.Items:PlayerLevel()
    if not level then return L.Format("+%d levels", value) end
    return L.Format("Level %d", math.min(60, level + value))
end

--- Where a pick's first source with an exact spot is, for the map.
function FinderUI.Place(pick)
    for _, source in ipairs(pick and pick.sources or {}) do
        if source.zone and source.x and source.y then return source end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Filling it in
--------------------------------------------------------------------------------

--- The view showing: "enchant", or nil for gear. An older saved choice of
--- one source ("vendor" and the like) reads as gear: the tick boxes have
--- taken its place.
function FinderUI:Filter()
    if ns.db and ns.db.finderShow == "enchant" then return "enchant" end
    return nil
end

--- Is the Enchants view showing? It lists enchants for what you wear, not
--- gear, so it has no scan, no stepper and no quest filters.
function FinderUI:ShowingEnchants()
    return self:Filter() == "enchant"
end

--- Show enchants ("enchant") or gear (nil).
function FinderUI:SetFilter(kind)
    if ns.db then ns.db.finderShow = kind == "enchant" and "enchant" or "all" end
    self.offset = 0
    self:Refresh()
end

--- Each slot's lines, by the key of its line on the left (SLOT_GROUPS):
--- `{ lines, total }`, `total` every upgrade found for it and `lines` those
--- with a source the tick boxes, "Only what I can get now" and "This zone
--- only" let through, best first. Every pick, not only the few best: the
--- list for one slot runs as long as it needs.
function FinderUI:Groups(found)
    local groups = {}
    local here = self:Here(found)
    local inZone = ns.UpgradeQuest and ns.UpgradeQuest.InZone
    local getNow = self:GetNowOnly()
    local on = {}
    for _, entry in ipairs(SOURCE_BOXES) do on[entry[1]] = self:SourceOn(entry[1]) end
    local all = type(found.all) == "table" and found.all or found.slots or {}
    for _, group in ipairs(SLOT_GROUPS) do
        -- Both rings, or both trinkets, as one list: each item once.
        local picks, seen = {}, {}
        for _, slot in ipairs({ group[1], group[3] }) do
            for _, pick in ipairs(all[slot] or {}) do
                if not seen[pick.itemID] then
                    seen[pick.itemID] = true
                    picks[#picks + 1] = pick
                end
            end
        end
        if group[3] then table.sort(picks, Finder.Order) end
        local lines = {}
        for _, pick in ipairs(picks) do
            local sources = {}
            for _, source in ipairs(pick.sources or {}) do
                local kind = FinderUI.SourceKind(source)
                if on[kind] ~= false and (not getNow or FinderUI.GetsNow(source, pick))
                    and (not here or not inZone or inZone(source, here)) then
                    sources[#sources + 1] = source
                end
            end
            if #sources > 0 then lines[#lines + 1] = { pick = pick, sources = sources } end
        end
        groups[group[1]] = { lines = lines, total = #picks }
    end
    return groups
end

--- The slot to show: the one clicked this time the window is open, else the
--- one last clicked while it has something, else the first that does.
function FinderUI:ChooseSlot(groups)
    local saved = tonumber(ns.db and ns.db.finderSlot)
    if saved and GROUP_OF[saved] ~= saved then saved = nil end
    local slot = self.slot or saved
    local function Has(key) return groups[key] and #groups[key].lines > 0 end
    if not self.slotChosen and not (slot and Has(slot)) then
        for _, group in ipairs(SLOT_GROUPS) do
            if Has(group[1]) then
                slot = group[1]
                break
            end
        end
    end
    self.slot = slot or SLOT_GROUPS[1][1]
    return self.slot
end

--- A click on a slot down the left: show its list, and keep it for next time.
function FinderUI:PickSlot(key)
    if GROUP_OF[key] ~= key then return end
    self.slot = key
    self.slotChosen = true
    if ns.db then ns.db.finderSlot = key end
    self.offset = 0
    self:Redraw()
end

--- The slots' counts and which is picked. `groups` nil blanks the counts.
function FinderUI:PaintSlots(groups)
    for _, button in ipairs(self.slotButtons or {}) do
        local group = groups and groups[button.group]
        button.count:SetText(tostring(group and #group.lines or 0))
        self:PaintSlot(button)
    end
end

--- The list's heading: the slot's name and what is worn there.
function FinderUI:SetListHead(lines)
    local name, slot = "", self.slot
    for _, group in ipairs(SLOT_GROUPS) do
        if group[1] == slot then name = group[2] end
    end
    self.listTitle:SetText(name)
    -- For rings and trinkets, the one the best pick would replace.
    local first = lines and lines[1]
    local pick = first and (first.pick or (first.enchant and { result = { slot = first.enchant.slot } }))
    local wornSlot = pick and pick.result and pick.result.slot or slot
    local link = slot and ns.Items and ns.Items:Equipped(wornSlot)
    if link then
        self.wornLabel:SetText(L.Format("You wear: %s", ns.Items.ShowLink(link)))
    else
        self.wornLabel:SetText("")
    end
    self.sortLabel:SetShown(not self:ShowingEnchants())
end

local function Gain(result)
    if result.empty then return L["empty slot"] end
    if result.percent then return ("%+d%%"):format(math.floor(result.percent + 0.5)) end
    return L["better"]
end

function FinderUI:FillRow(row, line)
    row.enchant = nil
    row.showWay:Hide()
    row.queueIt.enchant = nil
    if not line then
        row.pick = nil
        row:Hide()
        return
    end
    if line.enchant then return self:FillEnchantRow(row, line.enchant) end

    row.pick = {
        link = line.pick.link, sources = line.sources, itemID = line.pick.itemID,
        needs = line.pick.needs, result = line.pick.result, roll = line.pick.roll, at = line.pick.at,
        gain = line.pick.gain,
    }
    Theme.SetItemIcon(row.icon, line.pick.link)
    row.item:SetText(ns.Items.ShowLink(line.pick.link))
    local gain = Gain(line.pick.result)
    -- A weapon whose skill is not learned yet says "Train" in red, so the
    -- weapon master comes first (a player asked, 2026-10-10).
    local train = ns.WeaponSkills and ns.WeaponSkills:NeedsTraining(line.pick.link)
    if train and line.pick.at then
        gain = L.Format("at %d, Train: %s", line.pick.at, gain)
    elseif train then
        gain = L.Format("Train: %s", gain)
    elseif line.pick.at then
        gain = L.Format("at %d: %s", line.pick.at, gain)
    end
    row.gain:SetText(gain)
    -- A long gain ("at 23, Train: empty slot") grows leftward rather than
    -- being cut; the item's name gives it the room.
    local gainWidth = math.max(GAIN_WIDTH, math.ceil(Theme.TextWidth("normal", gain or "")) + 4)
    row.gain:SetWidth(gainWidth)
    row.item:SetWidth(row.itemRoom - gainWidth)
    -- Gear that waits on a reputation, a level or a crafter is shown in
    -- amber, not green; gear that waits on a weapon trainer in red.
    row.edgeKey = (line.pick.needs or line.pick.at or line.pick.remote) and "warn" or "good"
    row.gain:SetTextColor(Theme.Unpack(train and "loss" or row.edgeKey))

    local text = FinderUI.SourceLine(line.sources[1])
    if ns.Tracking and ns.Tracking:IsTracked(line.pick.itemID) then
        text = Colored("accent", L["Tracking"]) .. "  " .. text
    end
    if ns.UpgradeQuest and ns.UpgradeQuest:IsFollowing(line.pick.itemID) then
        text = Colored("good", L["Quest"]) .. "  " .. text
    end
    if line.pick.needs then
        text = Colored("warn", L.Format("Needs %s with %s", line.pick.needs.standing,
            line.pick.needs.faction)) .. "  " .. text
    end
    -- Queue it on crafted gear, with the line under the name kept clear of it.
    local craft = ns.TradeskillsQueue and ns.TradeskillsQueue:Available()
        and ns.TradeskillsQueue.CraftSource(line.sources) or nil
    row.queueIt.source = craft
    if craft then
        row.queueIt:SetText(ns.TradeskillsQueue:Label(craft.itemID))
        row.queueIt:Show()
        -- The button grows to fit its words (German runs longer).
        row.sourceWidth = row.fullSourceWidth - math.max(QUEUE_WIDTH, row.queueIt:GetWidth() or 0) - 8
    else
        row.queueIt:Hide()
        row.sourceWidth = row.fullSourceWidth
    end
    row.source:SetWidth(row.sourceWidth)

    local more = #line.sources - 1
    local tail = more > 0 and L.Format("  +%d more", more) or ""
    local room = row.sourceWidth * SOURCE_LINES - WRAP_SLACK - Theme.TextWidth("tiny", tail)
    row.source:SetText(FinderUI.Fit("tiny", text, room) .. Colored("dim", tail))
    row:Show()
end

--- One row of the Enchants view: the slot, the piece you wear, the enchant
--- to get, how much better, and how to get it.
function FinderUI:FillEnchantRow(row, line)
    local Enchants = ns.Enchants
    local pick, source = line.pick, line.source
    row.pick = nil
    row.enchant = line
    Theme.SetItemIcon(row.icon, line.plan.link)
    row.item:SetText(Enchants:ShownName(pick.recipeID) or "")

    local gain = pick.percent and ("%+d%%"):format(math.floor(pick.percent + 0.5)) or L["better"]
    row.gain:SetText(gain)
    local gainWidth = math.max(GAIN_WIDTH, math.ceil(Theme.TextWidth("normal", gain)) + 4)
    row.gain:SetWidth(gainWidth)
    row.item:SetWidth(row.itemRoom - gainWidth)
    -- Amber while it needs more skill or someone else to make it.
    local state = source and source.state
    row.edgeKey = (state == "skill" or state == "other") and "warn" or "good"
    row.gain:SetTextColor(Theme.Unpack(row.edgeKey))

    local text = Enchants:Describe(source, Finder.Money)
    local now = line.plan.current and Enchants:EnchantName(line.plan.current) or nil
    text = text .. "  " .. (now and L.Format("Now: %s", now) or L["Nothing on it now"])
    if line.soon then
        text = Colored("warn", L["A better piece is coming, so this is a cheap one"]) .. "  " .. text
    end

    -- Queue it and Show the way, right to left, with the line kept clear.
    local used = 0
    if Enchants:CanQueue() then
        row.queueIt.enchant = line
        row.queueIt:SetText(L["Queue it"])
        row.queueIt:Show()
        used = math.max(QUEUE_WIDTH, row.queueIt:GetWidth() or 0) + 8
    else
        row.queueIt:Hide()
    end
    row.queueIt.source = nil
    if (state == "learn" or state == "skill") and Enchants:CanShowTheWay(pick.recipeID) then
        row.showWay:ClearAllPoints()
        if used > 0 then
            row.showWay:SetPoint("RIGHT", row.queueIt, "LEFT", -6, 0)
        else
            row.showWay:SetPoint("BOTTOMRIGHT", -8, 5)
        end
        row.showWay.enchant = line
        row.showWay:Show()
        used = used + (row.showWay:GetWidth() or QUEUE_WIDTH) + 6
    end
    row.sourceWidth = row.fullSourceWidth - used
    row.source:SetWidth(row.sourceWidth)
    row.source:SetText(FinderUI.Fit("tiny", text, row.sourceWidth * SOURCE_LINES - WRAP_SLACK))
    row:Show()
end

function FinderUI:ScrollBy(steps)
    local most = math.max(0, #(self.lines or {}) - VISIBLE)
    self.offset = math.max(0, math.min(most, (self.offset or 0) + steps))
    self:Draw()
end

function FinderUI:Draw()
    local lines = self.lines or {}
    local offset = self.offset or 0
    for index, row in ipairs(self.rows) do
        self:FillRow(row, lines[offset + index])
        -- Scrolled under a still mouse: the tooltip follows the new item.
        if rawget(row, "over") == true then
            if rawget(row, "pick") or rawget(row, "enchant") then ShowTooltip(row) else GameTooltip:Hide() end
        end
    end

    -- The thumb only shows when there is more than fits.
    local total = #lines
    if total > VISIBLE then
        local height = VISIBLE * ROW_HEIGHT
        local size = math.max(16, height * VISIBLE / total)
        local top = (height - size) * offset / (total - VISIBLE)
        self.thumb:SetHeight(size)
        self.thumb:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -PADDING, self.rowsTop - top)
        self.thumb:Show()
        self.track:Show()
    else
        self.thumb:Hide()
        self.track:Hide()
    end
end


--- Look again and redraw, at once: for opening the window and for clicks.
-- @return the scan, or nil when there was nothing to look with
function FinderUI:Refresh()
    if not (self.frame and self.frame:IsShown()) then return nil end
    -- A slower scan still under way would only draw something older.
    Finder.sliced = nil
    if self:ShowingEnchants() then return self:PresentEnchants() end
    return self:Present(Finder:Scan(nil, self:Ahead()))
end

--- Look again a slice per frame and redraw once done, keeping what shows
--- meanwhile: for the events that come in bursts while the window is open.
function FinderUI:RefreshInBackground()
    if not (self.frame and self.frame:IsShown()) then return end
    -- Enchants are kept by Logic/Enchants.lua: drawing them is cheap.
    if self:ShowingEnchants() then
        self:PresentEnchants()
        return
    end
    local ahead = self:Ahead()
    Finder:ScanSliced(nil, ahead, function(found, why)
        -- The window closed, or the view or the stepper moved, meanwhile.
        if not (FinderUI.frame and FinderUI.frame:IsShown()) then return end
        if FinderUI:ShowingEnchants() or FinderUI:Ahead() ~= ahead then return end
        FinderUI:Present(found, why)
    end)
end

--- The gold bar under Enchants while it shows, and the controls only gear
--- uses.
function FinderUI:MarkFilters()
    local enchants = self:ShowingEnchants()
    self.enchantsButton.mark:SetShown(enchants)
    self.enchantsButton:SetLabelColor(enchants and "accent" or "text")
    local gear = not enchants
    local controls = { self.showLabel, self.getNow, self.ahead, self.levelLabel, self.questLevels, self.solo, self.zone }
    for _, box in ipairs(self.sourceBoxes) do controls[#controls + 1] = box end
    for _, control in ipairs(controls) do control:SetShown(gear) end
    if gear then
        self.hint:SetText(L["Click a row to follow it. Right-click to track it."])
    elseif ns.Enchants and ns.Enchants:CanQueue() then
        self.hint:SetText(L["The best enchant for each piece you wear, for your spec. Queue it sends it to Tradeskills."])
    else
        self.hint:SetText(L["The best enchant for each piece you wear, for your spec."])
    end
end

--- Draw a scan.
function FinderUI:Present(found, why)
    self:MarkFilters()

    if not found then
        self.lines, self.groups = {}, nil
        self:Draw()
        self:PaintSlots(nil)
        self:SetListHead(nil)
        if why == "noweights" then
            self.empty:SetText(L.Format("There are no stat weights for %s yet.",
                Weights:PlayerClass() or L["this class"]))
        else
            self.empty:SetText(L["Your level and faction aren't known yet. Try again in a moment."])
        end
        self.empty:Show()
        self.footer:SetText("")
        self.specLabel:SetText("")
        return nil
    end

    local spec, _, class = Weights:CurrentSpec()
    local specName = spec and Weights:SpecName(class, spec) or ""
    if found.reach > found.player.level then
        self.specLabel:SetText(L.Format("%s, level %d, planning for %d", specName, found.player.level, found.reach))
    else
        self.specLabel:SetText(L.Format("%s, level %d", specName, found.player.level))
    end
    if self.ahead then self.ahead:SetValue(self:Ahead(), true) end

    local groups = self:Groups(found)
    self.groups = groups
    local group = groups[self:ChooseSlot(groups)]
    self.lines = group.lines
    local most = math.max(0, #self.lines - VISIBLE)
    self.offset = math.min(self.offset or 0, most)
    self:Draw()
    self:PaintSlots(groups)
    self:SetListHead(self.lines)

    local shown = #self.lines
    if shown == 0 then
        local here = self:Here(found)
        if ns.Alts and ns.Alts:PlayerSkipped() then
            self.empty:SetText(L["Upgrades are skipped for this character. Untick it in Settings, or type /beq skip off."])
        elseif found.count == 0 and found.waiting > 0 then
            self.empty:SetText(L["Asking the server about the gear on offer..."])
        elseif here then
            self.empty:SetText(L.Format("Nothing in %s beats what you wear. Untick This zone only to look anywhere.", here))
        else
            self.empty:SetText(L["Nothing on offer beats what you wear right now."])
        end
        self.empty:Show()
    else
        self.empty:Hide()
    end

    local text = L.Format("%d of %d upgrades shown for this slot", shown, group.total)
    if found.waiting > 0 then
        text = text .. Colored("muted", L.Format("  Still asking the server about %d items.", found.waiting))
    end
    self.footer:SetText(text)

    self.found = found
    return found
end

--- Draw the Enchants view: for the slot picked, the enchant that would make
--- the piece worn there better (Logic/Enchants.lua). The slots down the
--- left count 1 where one would.
function FinderUI:PresentEnchants()
    self:MarkFilters()
    local Enchants = ns.Enchants
    local plans = Enchants and Enchants:Plans()

    local spec, _, class = Weights:CurrentSpec()
    local specName = spec and Weights:SpecName(class, spec) or ""
    local level = ns.Items and ns.Items:PlayerLevel()
    self.specLabel:SetText(level and L.Format("%s, level %d", specName, level) or specName)

    local groups, count = {}, 0
    for _, group in ipairs(SLOT_GROUPS) do groups[group[1]] = { lines = {}, total = 0 } end
    if plans then
        for _, line in ipairs(Enchants:Lines()) do
            local group = groups[GROUP_OF[line.slot] or -1]
            if group then
                group.lines[#group.lines + 1] = { enchant = line }
                group.total = group.total + 1
                count = count + 1
            end
        end
    end
    self.groups = groups
    self.lines = groups[self:ChooseSlot(groups)].lines
    local most = math.max(0, #self.lines - VISIBLE)
    self.offset = math.min(self.offset or 0, most)
    self:Draw()
    self:PaintSlots(groups)
    self:SetListHead(self.lines)

    if #self.lines == 0 then
        if not plans then
            self.empty:SetText(L.Format("There are no stat weights for %s yet.",
                Weights:PlayerClass() or L["this class"]))
        elseif Enchants.missing then
            self.empty:SetText(L["Asking the server about the gear you wear..."])
        else
            self.empty:SetText(L["No enchant beats what's on your gear now."])
        end
        self.empty:Show()
    else
        self.empty:Hide()
    end

    if count == 1 then
        self.footer:SetText(L["1 piece you wear could use a better enchant."])
    elseif count > 1 then
        self.footer:SetText(L.Format("%d pieces you wear could use a better enchant.", count))
    else
        self.footer:SetText("")
    end
    self.found = nil
    return self.lines
end

--- Look again once a burst of events settles.
function FinderUI:RefreshSoon()
    if not (self.frame and self.frame:IsShown()) or self.pending then return end
    self.pending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0.5, function()
            FinderUI.pending = false
            FinderUI:RefreshInBackground()
        end)
    else
        self.pending = false
        self:RefreshInBackground()
    end
end

--------------------------------------------------------------------------------
-- Position and visibility
--------------------------------------------------------------------------------

function FinderUI:SavePosition()
    if not (ns.db and self.frame) then return end
    local point, _, relativePoint, x, y = self.frame:GetPoint()
    ns.db.finderPoint, ns.db.finderRelativePoint = point, relativePoint
    ns.db.finderX, ns.db.finderY = x, y
end

function FinderUI:RestorePosition()
    if not self.frame then return end
    local db = ns.db or {}
    self.frame:ClearAllPoints()
    -- Until it is dragged somewhere, it opens beside the gear window rather
    -- than over its title, far enough off that its portrait clears the gear
    -- window's close gem.
    local gear = ns.UI and ns.UI.frame
    local okShown, shown = pcall(function() return gear and gear:IsShown() end)
    if not db.finderMoved and okShown and shown then
        self.frame:SetPoint("TOPLEFT", gear, "TOPRIGHT", 30, 0)
        return
    end
    self.frame:SetPoint(db.finderPoint or "CENTER", UIParent, db.finderRelativePoint or "CENTER",
        db.finderX or 40, db.finderY or 20)
end

function FinderUI:Show()
    self:Build()
    if not self.frame:IsShown() then
        self:RestorePosition()
        self.offset = 0
        -- A new look: the slot last clicked if it has something, else the
        -- first that does.
        self.slot, self.slotChosen = nil, false
        self.frame:Show()
        Motion:Open(self.frame)
        -- And a light runs round the portrait.
        if ns.Titanforged then ns.Titanforged:Opened(self.frame) end
    end
    self:Refresh()
end

function FinderUI:Hide()
    if self.frame then self.frame:Hide() end
end

function FinderUI:Toggle()
    if self.frame and self.frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

function FinderUI:OnTrackingChanged()
    if self.frame and self.frame:IsShown() then self:Draw() end
end

function FinderUI:OnUpgradeQuestChanged()
    self:OnTrackingChanged()
end

--- Follow a row's pick on the upgrade quest panel, or say why it cannot be.
function FinderUI:Follow(pick)
    local logic = ns.UpgradeQuest
    if not logic then return nil end
    local quest, why = logic:Follow(pick)
    if quest then
        ns.Print(L.Format("following %s on the upgrade quest panel.", ns.Items.ShowLink(pick.link or quest.link)))
    else
        ns.Print(L.Format("%s can't be an upgrade quest yet: %s.", pick.link and ns.Items.ShowLink(pick.link) or L["that"], why or L["unknown"]))
    end
    return quest
end

local EVENTS = {
    "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP",
    "QUEST_TURNED_IN", "TRAIT_CONFIG_UPDATED", "BAG_UPDATE_DELAYED",
}

function FinderUI:OnEnable()
    for _, event in ipairs(EVENTS) do
        ns.RegisterEvent(self, event, self.RefreshSoon)
    end
    -- Only answers the finder asked for: the client loads items for chat
    -- links, the auction house and other addons all the time.
    ns.RegisterEvent(self, "GET_ITEM_INFO_RECEIVED", function(_, _, itemID)
        if Finder:Asked(itemID) then FinderUI:RefreshSoon() end
    end)
    -- A new zone has its own list while "This zone only" is ticked, and
    -- always its own green zone names and nearest-first order.
    ns.RegisterEvent(self, "ZONE_CHANGED_NEW_AREA", function()
        FinderUI:RefreshSoon()
    end)
    -- A name drawn plain (a material, a recipe) takes its rarity colour
    -- once the client sends it: redraw, no rescan.
    ns.Items:WatchNames(function()
        if FinderUI.frame and FinderUI.frame:IsShown() then FinderUI:Draw() end
    end)
    -- Only the "need ... more" on vendor rows changes: redraw, no rescan.
    ns.RegisterEvent(self, "PLAYER_MONEY", function()
        if FinderUI.frame and FinderUI.frame:IsShown() then FinderUI:Draw() end
    end)
end
