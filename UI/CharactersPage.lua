-- Blackthornes Equipment -- UI/CharactersPage.lua
-- The Characters page of Settings (rework step 6, 2026-11-23): every
-- character that has logged in with Equipment, one to a row, with its
-- level and class, a Skip Upgrades tick and Forget.
--
-- It was the Your Characters section of the Gear page, a drop-down and two
-- rows. What it does is the same and so is what it saves: the tick is
-- Alts:SetSkipped (a crafting alt never hears about upgrades), Forget is
-- Alts:Forget (for a character that was deleted), and Forget still asks
-- first: one click turns the row to "Forget this one" and Confirm for a
-- few seconds. The character playing can never be forgotten, and neither
-- can anyone while the client won't say who is playing (Alts:CanForget).
--
-- A character is its GUID here, as everywhere; its whole name is only what
-- the row shows, never shortened.

local _, ns = ...
local L = ns.L

local Characters = ns.NewModule("CharactersPage")

local Theme = ns.Theme
local Widgets = ns.Widgets

Characters.KEY = "characters"

local HEAD = 24
local ROW_HEIGHT = 28
local FOOT = 44
local PAD = 10

-- How long a row waits on Confirm, in seconds.
Characters.FORGET_ARMED = 4

-- The columns: where each starts, as a share of the width.
local CLASS_AT, SKIP_AT, FORGET_AT = 0.42, 0.62, 0.80

-- Sorted by a column's heading: "name", "class" or "skip", and which way.
-- Session only. Unsorted, the character playing is first, then by name.
Characters.sortBy = nil
Characters.sortDown = false

--------------------------------------------------------------------------------
-- What is listed
--------------------------------------------------------------------------------

--- A character's "38 Warrior", from its note, or "" when it has none.
function Characters.ClassText(key)
    local note = ns.Alts and ns.Alts:Notes()[key]
    if type(note) ~= "table" then return "" end
    local class = ns.WeightsPage and ns.WeightsPage.ClassName(note.class) or nil
    local level = tonumber(note.level)
    if level and class then return ("%d %s"):format(level, class) end
    return class or (level and tostring(level)) or ""
end

--- The characters in the order shown: { key, name, me, class, skipped }.
function Characters:List()
    local alts = ns.Alts
    if not alts then return {} end
    local list = alts:Characters()
    for place, entry in ipairs(list) do
        entry.place = place
        entry.class = Characters.ClassText(entry.key)
        entry.skipped = alts:IsSkipped(entry.key)
    end
    local by = self.sortBy
    if not by then return list end
    local down = self.sortDown
    local function Value(entry)
        if by == "class" then return entry.class:gsub("^%d+%s*", ""):lower() end
        if by == "skip" then return entry.skipped and "0" or "1" end
        return (entry.name or "~"):lower()
    end
    table.sort(list, function(a, b)
        local av, bv = Value(a), Value(b)
        if av ~= bv then
            if down then return av > bv end
            return av < bv
        end
        return a.place < b.place
    end)
    return list
end

--- A heading was clicked: sort by it, or the other way when it already is.
function Characters:SortBy(by)
    if self.sortBy == by then
        self.sortDown = not self.sortDown
    else
        self.sortBy, self.sortDown = by, false
    end
    self:Refresh()
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

local function Paint(row)
    local over = rawget(row, "over") == true
    row.background:SetColorTexture(Theme.Unpack(over and "glassHover" or row.restKey or "glass"))
    row.edge:SetShown(over)
end

--- A column heading that sorts by its column.
function Characters:Heading(x, text, by, tip)
    local panel = self.frame
    local button = CreateFrame("Button", nil, panel)
    button:SetPoint("TOPLEFT", x, 0)
    button:SetSize(Theme.TextWidth("tiny", text) + 16, HEAD - 4)
    local label = Theme.CreateLabel(button, "tiny", "heading")
    label:SetPoint("LEFT", 0, 0)
    label:SetText(text)
    button.label = label
    button.words = text
    button:SetScript("OnClick", function() Characters:SortBy(by) end)
    button:SetScript("OnEnter", function(self)
        label:SetTextColor(Theme.Unpack("accent"))
        if tip and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(text, Theme.Unpack("accent"))
            GameTooltip:AddLine(tip, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function()
        label:SetTextColor(Theme.Unpack("heading"))
        if GameTooltip then GameTooltip:Hide() end
    end)
    return button
end

--- Build the page on Settings' pages (UI/SettingsPages.lua), `width` wide.
function Characters:Build(pages, key, width)
    if self.frame then return self.frame end
    local page = pages and pages.pages[key or Characters.KEY]
    if not page then return nil end
    self.pages, self.key = pages, key or Characters.KEY
    self.width = width

    local panel = CreateFrame("Frame", nil, page.content)
    panel:SetSize(width, 200)
    panel.fixedHeight = 200
    pages:Place(self.key, 1, panel)
    self.frame = panel
    self.rows = {}

    local skipTip = L["Good for a crafting alt. It never hears about upgrades or gets your other characters' gear."]
    self.heads = {
        name = self:Heading(PAD, L["CHARACTER"], "name"),
        class = self:Heading(math.floor(width * CLASS_AT), L["CLASS"], "class"),
        skip = self:Heading(math.floor(width * SKIP_AT), L["SKIP UPGRADES"], "skip", skipTip),
    }

    local empty = Theme.CreateLabel(panel, "small", "muted")
    empty:SetPoint("TOPLEFT", PAD, -(HEAD + 8))
    empty:SetText(L["Each character shows here after it logs in with Equipment."])
    empty:Hide()
    self.empty = empty

    local foot = Theme.CreateLabel(panel, "small", "muted")
    foot:SetPoint("BOTTOMLEFT", PAD, 0)
    foot:SetPoint("BOTTOMRIGHT", -PAD, 0)
    foot:SetWordWrap(true)
    foot:SetJustifyH("LEFT")
    foot:SetJustifyV("BOTTOM")
    foot:SetHeight(FOOT - 8)
    foot:SetText(L["For a character you deleted. Equipment stops picking gear for it. It shows up again if it logs in."]
        .. " " .. L["The character you are playing can never be forgotten."])
    self.foot = foot

    pages:Searchable(self.key, panel, table.concat({ L["CHARACTERS"], L["CHARACTER"], L["CLASS"],
        L["SKIP UPGRADES"], L["Forget"], skipTip }, " "))
    return panel
end

--- One character's row: name, level and class, the Skip tick, and Forget.
function Characters:BuildRow(index)
    local panel, width = self.frame, self.width
    local row = CreateFrame("Button", nil, panel)
    row:SetSize(width, ROW_HEIGHT)
    row.restKey = "glass"
    row.background = Theme.Fill(row, "glass")
    local under = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    under:SetPoint("BOTTOMLEFT")
    under:SetPoint("BOTTOMRIGHT")
    under:SetHeight(1)
    under:SetColorTexture(Theme.Unpack("border", 0.6))
    row.edge = row:CreateTexture(nil, "ARTWORK")
    row.edge:SetPoint("TOPLEFT")
    row.edge:SetPoint("BOTTOMLEFT")
    row.edge:SetWidth(3)
    row.edge:SetColorTexture(Theme.Unpack("accent"))
    row.edge:Hide()

    local classX, skipX, forgetX = math.floor(width * CLASS_AT), math.floor(width * SKIP_AT),
        math.floor(width * FORGET_AT)

    -- The whole name; a long one wraps and the row grows for it.
    row.name = Theme.CreateLabel(row, "small", "text")
    row.name:SetPoint("LEFT", PAD, 0)
    row.name:SetJustifyH("LEFT")
    if row.name.SetWordWrap then row.name:SetWordWrap(true) end
    row.nameRoom = classX - PAD - 12

    row.tag = Theme.CreateLabel(row, "tiny", "accent")
    row.tag:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
    row.tag:SetText(L["Playing"])
    row.tag:Hide()

    row.class = Theme.CreateLabel(row, "small", "muted")
    row.class:SetPoint("LEFT", row, "LEFT", classX, 0)

    row.skip = Widgets.CreateCheckbox(row, "", function(checked)
        if row.key and ns.Alts then ns.Alts:SetSkipped(row.key, checked) end
    end, false)
    row.skip:SetPoint("LEFT", row, "LEFT", skipX, 0)

    local confirmWidth = math.max(70, Theme.TextWidth("small", L["Confirm"]) + 24,
        Theme.TextWidth("small", L["Forget"]) + 24)
    row.forget = Widgets.CreateButton(row, L["Forget"], function()
        Characters:ForgetClicked(row)
    end, { width = confirmWidth, height = 20 })
    row.forget:SetPoint("RIGHT", row, "RIGHT", -6, 0)

    -- "Forget this one" beside Confirm while the row waits for it.
    row.ask = Theme.CreateLabel(row, "small", "loss", "RIGHT")
    row.ask:SetPoint("RIGHT", row.forget, "LEFT", -8, 0)
    row.ask:SetText(L["Forget this one"])
    row.ask:Hide()
    row.forgetX = forgetX

    local function Over() row.over = true; Paint(row) end
    local function Out()
        local ok, over = pcall(row.IsMouseOver, row)
        if ok and over == true then return end
        row.over = false
        Paint(row)
    end
    row:SetScript("OnEnter", Over)
    row:SetScript("OnLeave", Out)
    for _, child in ipairs({ row.skip, row.forget }) do
        if child.HookScript then
            child:HookScript("OnEnter", Over)
            child:HookScript("OnLeave", Out)
        end
    end

    self.rows[index] = row
    return row
end

--------------------------------------------------------------------------------
-- Forget
--------------------------------------------------------------------------------

--- Turn a row's Forget to Confirm, or back.
function Characters:Arm(row, on)
    row.armed = on and true or false
    row.armedAt = on and (type(GetTime) == "function" and GetTime() or 0) or nil
    row.armedKey = on and row.key or nil
    row.forget:SetText(on and L["Confirm"] or L["Forget"])
    if row.forget.SetLabelColor then row.forget:SetLabelColor(on and "loss" or "gilt") end
    row.ask:SetShown(row.armed)
    if on and C_Timer and C_Timer.After then
        local at = row.armedAt
        C_Timer.After(self.FORGET_ARMED, function()
            if row.armed and row.armedAt == at then Characters:Arm(row, false) end
        end)
    end
end

--- First click asks for Confirm; the second forgets the row's character.
function Characters:ForgetClicked(row)
    local key = row.key
    if not (key and ns.Alts and ns.Alts:CanForget(key)) then
        self:Arm(row, false)
        return
    end
    -- A Confirm armed for another character starts over.
    if not row.armed or row.armedKey ~= key then
        self:Arm(row, true)
        return
    end
    self:Arm(row, false)
    local done = ns.Alts:Forget(key)
    if done then
        local name = type(done) == "string" and done or L["A character not seen yet"]
        ns.Print(L.Format("Equipment forgot %s.", name))
    end
    self:Refresh()
end

--------------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------------

--- Is the page the one Settings is showing?
function Characters:IsShown()
    local settings = ns.SettingsUI
    return self.frame ~= nil and settings ~= nil and settings:IsShown()
        and self.pages.shown == self.key
end

--- The headings: the one sorted by is gold, with which way.
function Characters:PaintHeads()
    for by, button in pairs(self.heads) do
        local text = rawget(button, "words") or ""
        local sorted = self.sortBy == by
        button.label:SetText(sorted and (text .. (self.sortDown and "  v" or "  ^")) or text)
        button:SetWidth(Theme.TextWidth("tiny", text) + 24)
    end
end

function Characters:Refresh()
    if not self:IsShown() then return end
    local alts = ns.Alts
    local list = self:List()
    self:PaintHeads()

    local y = HEAD
    for index, entry in ipairs(list) do
        local row = self.rows[index] or self:BuildRow(index)
        -- A Confirm waiting on another character does not carry over.
        if row.armed and row.armedKey ~= entry.key then self:Arm(row, false) end
        row.key = entry.key
        row.restKey = index % 2 == 0 and "glassAlt" or "glass"
        Paint(row)

        local name = entry.name or L["A character not seen yet"]
        row.name:SetWidth(0)
        row.name:SetText(name)
        local room = row.nameRoom - (entry.me and Theme.TextWidth("tiny", L["Playing"]) + 10 or 0)
        local tall = ROW_HEIGHT
        if Theme.TextWidth("small", name) > room then
            row.name:SetWidth(room)
            local ok, height = pcall(row.name.GetStringHeight, row.name)
            height = ok and tonumber(height) or 0
            tall = math.max(ROW_HEIGHT, math.ceil(height) + 12)
        end
        row.tag:SetShown(entry.me == true)
        row.class:SetText(entry.class)
        row.skip:SetChecked(entry.skipped == true)

        local can = alts ~= nil and alts:CanForget(entry.key)
        if not can and row.armed then self:Arm(row, false) end
        row.forget:SetShown(can)

        row:SetHeight(tall)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, -y)
        row:Show()
        y = y + tall
    end
    for index = #list + 1, #self.rows do
        local row = self.rows[index]
        if row.armed then self:Arm(row, false) end
        row.key = nil
        row:Hide()
    end
    self.empty:SetShown(#list == 0)
    if #list == 0 then y = y + ROW_HEIGHT end

    local height = y + 10 + FOOT
    self.frame.fixedHeight = height
    self.frame:SetHeight(height)
    if self.pages.UpdateScroll then self.pages:UpdateScroll() end
end

--- Open Settings on this page.
function Characters:Show()
    if ns.SettingsUI then ns.SettingsUI:Show(self.KEY) end
end
