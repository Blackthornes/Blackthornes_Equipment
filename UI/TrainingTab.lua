-- Blackthornes Equipment -- UI/TrainingTab.lua
-- Training, the Equipment window's fifth tab (rework step 5, the owner
-- approved the mockup 2026-11-22). Class training was a drawer hanging off
-- the side of the window. It has a tab now, and the tab's name carries the
-- count, so the player knows when a trip to the trainer is due. Weapon
-- skills join it, since both end at a trainer.
--
--   The left   TRAIN NOW and COMING SOON: each spell with its level and
--              cost. A right-click skips one; Show Skipped lists the
--              skipped ones to bring back. Character: shows what another
--              of the player's characters has waiting, as last seen.
--   The right  WEAPON SKILLS: every skill the class can learn, known or
--              not, with the weapon master in this side's cities and Show
--              the Way. A skill an upgrade waits on says so.
--
-- What it reads is the drawer's own: Logic/ClassTraining.lua's plan (kept
-- until a spell, a price or the level changes) and Logic/WeaponSkills.lua.
-- Nothing here judges gear or starts a scan. No new saved key: Show
-- Skipped is for the session.

local _, ns = ...
local L = ns.L

local Train = ns.NewModule("TrainingTab")

local Theme = ns.Theme
local Widgets = ns.Widgets

Train.KEY = "training"
-- It stands in for the Training drawer: the old header's Training button
-- opens this tab. A suite that tests the drawer sets env.OLD_PANELS, which
-- clears this.
Train.standsIn = true

local PAD = 18
local WIDTH = 1040
local LEFT_SHARE = 0.60
local ROW = 26
local HEAD = 22
local ICON = 20
local MOST_LINES = 26
local MOST_SKILLS = 16
local WHEEL = 3
local FOOT = 22
local NOTE = 30

local COST_WIDTH = 150
local LEVEL_WIDTH = 60
local GAP = 8

local DONE_ICON = [[Interface\RaidFrame\ReadyCheck-Ready]]

local function Shown(frame)
    if not frame then return false end
    local ok, shown = pcall(frame.IsShown, frame)
    return ok and shown == true
end

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

local function Training() return ns.ClassTraining end

--------------------------------------------------------------------------------
-- What it shows
--------------------------------------------------------------------------------

--- How many spells wait at the trainer for the character playing: the
--- number the tab's name carries. 0 while class training is off.
function Train.Count()
    local training = Training()
    if not (training and training:IsOn()) then return 0 end
    local ok, plan = pcall(training.Plan, training)
    return ok and type(plan) == "table" and #plan.ready or 0
end

--- The tab's name: "Training", or "Training (4)" with spells waiting.
function Train.TabText()
    local count = Train.Count()
    return count > 0 and L.Format("Training (%d)", count) or L["Training"]
end

--- The characters to pick from: the one playing first, then the others on
--- this realm and side with spells waiting. { guid, name, other }.
function Train:Characters()
    local training = Training()
    local player = training.Player()
    local list = { { guid = player.guid, name = player.name or "?" } }
    local ok, others = pcall(training.Others, training)
    for _, other in ipairs(ok and others or {}) do
        list[#list + 1] = { guid = other.guid, name = other.name or "?", other = other }
    end
    return list
end

--- The character picked: nil for the one playing, else the other's note.
function Train:Other()
    if not self.who then return nil end
    for _, entry in ipairs(self:Characters()) do
        if entry.guid == self.who and entry.other then return entry.other end
    end
    self.who = nil
    return nil
end

--- What another character has waiting, as spells: its noted spell IDs
--- looked up in its class's list. { ready = { spells }, cost, unknown }.
function Train.OtherPlan(other)
    local training = Training()
    local data = training:Data()
    local note = data.characters[other.guid]
    local list = ns.CLASS_SPELLS and other.class and ns.CLASS_SPELLS[other.class]
    local plan = { ready = {}, next = {}, skipped = {}, cost = 0, unknown = 0 }
    if type(note) ~= "table" or type(list) ~= "table" then return plan end
    local want = {}
    for _, id in ipairs(note.ready or {}) do
        if not data.notTaught[id] then want[id] = true end
    end
    for _, entry in ipairs(list) do
        if want[entry[1]] then
            local cost, guess = training.PriceOf(entry[1], data.prices)
            plan.ready[#plan.ready + 1] = { id = entry[1], level = entry[2], rank = entry[3], entry = entry,
                cost = cost, guess = guess }
        end
    end
    plan.cost, plan.unknown = training.Sum(plan.ready)
    return plan
end

--- The left side's lines, top to bottom: { kind = "head" | "spell" |
--- "note", text, spell, soon, skipped }.
function Train:Lines()
    local training = Training()
    local lines = {}
    local other = self:Other()
    if not other and not training:IsOn() then
        lines[1] = { kind = "note", text = L["Class training is turned off in Settings."] }
        return lines, { ready = {}, next = {}, skipped = {}, cost = 0, unknown = 0 }
    end
    local plan = other and Train.OtherPlan(other) or training:Plan()
    lines[#lines + 1] = { kind = "head", text = L["TRAIN NOW"] }
    if #plan.ready == 0 then
        lines[#lines + 1] = { kind = "note", text = L["Nothing to train at your level."] }
    end
    for _, spell in ipairs(plan.ready) do lines[#lines + 1] = { kind = "spell", spell = spell } end
    if not other and plan.nextLevel and #plan.next > 0 then
        lines[#lines + 1] = { kind = "head", text = L["COMING SOON"] }
        for _, spell in ipairs(plan.next) do lines[#lines + 1] = { kind = "spell", spell = spell, soon = true } end
    end
    if not other and self.showSkipped and #plan.skipped > 0 then
        lines[#lines + 1] = { kind = "head", text = L["SKIPPED"] }
        for _, spell in ipairs(plan.skipped) do
            lines[#lines + 1] = { kind = "spell", spell = spell, skipped = true }
        end
    end
    return lines, plan
end

--- The weapon skills an upgrade waits on, by the data's name for each:
--- from the bags (the gear window's read) and the finder's last scan.
function Train.Waited()
    local waited = {}
    for _, weapon in ipairs(ns.UI and ns.UI.untrained or {}) do
        if weapon.skill then waited[weapon.skill] = true end
    end
    local found = ns.Finder and ns.Finder.latest
    for _, list in pairs(type(found) == "table" and type(found.all) == "table" and found.all or {}) do
        for _, pick in ipairs(list) do
            local skill = type(pick.result) == "table" and pick.result.skill
            if skill then waited[skill] = true end
        end
    end
    return waited
end

--- The right side's lines: { name, known, sub, subclassID, way }.
function Train:Skills()
    local skills = ns.WeaponSkills
    local lines = {}
    if not skills then return lines end
    local ok, all = pcall(skills.All, skills)
    local waited = Train.Waited()
    for _, skill in ipairs(ok and all or {}) do
        local line = { name = skill.name, known = skill.known, subclassID = skill.subclassID }
        if not skill.known then
            local cities = {}
            for index, city in ipairs(skill.cities) do cities[index] = ns.Finder.ShownZone(city) end
            local where = skills.CityList(cities)
            local parts = {}
            if skill.from then
                parts[1] = L.Format("Learn at level %d from the weapon master in %s.", skill.from, where)
            else
                parts[1] = L.Format("Learn from the weapon master in %s.", where)
            end
            if waited[skill.skill] then parts[2] = L["An upgrade waits on it."] end
            line.sub = table.concat(parts, " ")
            line.waited = waited[skill.skill] == true
            line.way = #skill.cities > 0
        end
        lines[#lines + 1] = line
    end
    return lines
end

--- The foot's left line: "4 spells to train now. 4 more at level 40."
function Train.FootText(plan)
    local count = #plan.ready
    local now = count == 0 and L["Nothing to train now."] or count == 1 and L["1 spell to train now."]
        or L.Format("%d spells to train now.", count)
    local soon = #(plan.next or {})
    if soon == 0 or not plan.nextLevel then return now end
    return now .. " " .. (soon == 1 and L.Format("1 more at level %d.", plan.nextLevel)
        or L.Format("%d more at level %d.", soon, plan.nextLevel))
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

local function Glass(parent, index)
    local row = CreateFrame("Button", nil, parent)
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
    if row.RegisterForClicks then row:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    return row
end

local function Paint(row)
    local over = rawget(row, "over") == true and rawget(row, "plain") ~= true
    row.background:SetColorTexture(Theme.Unpack(rawget(row, "headed") and "header"
        or over and "glassHover" or row.restKey))
    row.edge:SetShown(over)
    row.edge:SetColorTexture(Theme.Unpack("accent"))
end

local function Heading(parent, text, justify)
    local label = Theme.CreateLabel(parent, "tiny", "heading", justify)
    label:SetText(text)
    return label
end

local function Button(parent, text, run, height)
    return Widgets.CreateButton(parent, text, run,
        { width = math.max(60, Theme.TextWidth("small", text) + 24), height = height or 22 })
end

function Train:BuildBar(page)
    local label = Theme.CreateLabel(page, "small", "muted")
    label:SetPoint("TOPLEFT", PAD, -14)
    label:SetText(L["Character:"])
    local who = Widgets.CreateDropdown(page, { { text = "?", value = "me" } }, function(value)
        Train.who = value ~= "me" and value or nil
        Train.offset = 0
        Train:Refresh()
    end, { width = 220 })
    who:SetPoint("LEFT", label, "RIGHT", 8, 0)
    self.whoChoice = who

    local way = Button(page, L["Show the Way"], function()
        local training = Training()
        if training then training:ShowTheWay() end
    end)
    way:SetPoint("TOPRIGHT", -PAD, -10)
    self.wayButton = way
    way:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L["Show the Way"], Theme.Unpack("accent"))
        GameTooltip:AddLine(rawget(Train, "trainerLine") or "", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    way:HookScript("OnLeave", function() GameTooltip:Hide() end)

    local have = Theme.CreateLabel(page, "small", "muted", "RIGHT")
    have:SetPoint("RIGHT", way, "LEFT", -16, 0)
    self.haveLabel = have
    local cost = Theme.CreateLabel(page, "normal", "text", "RIGHT")
    cost:SetPoint("RIGHT", have, "LEFT", -16, 0)
    self.costLabel = cost

    local rule = Theme.CreateDivider(page, "border")
    rule:SetPoint("TOPLEFT", PAD, -44)
    rule:SetPoint("TOPRIGHT", -PAD, -44)
    return 52
end

function Train:BuildLeft(body, width)
    local left = Theme.CreatePanel(body, "well", "border")
    left:SetPoint("TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", 0, FOOT)
    left:SetWidth(width)
    self.left = left
    self.leftWidth = width

    local heads = CreateFrame("Frame", nil, left)
    heads:SetPoint("TOPLEFT", 1, -1)
    heads:SetPoint("TOPRIGHT", -1, -1)
    heads:SetHeight(HEAD)
    Theme.Fill(heads, "header")
    local costRight = 10
    local levelRight = costRight + COST_WIDTH + GAP
    self.columns = { cost = costRight, level = levelRight,
        name = width - levelRight - LEVEL_WIDTH - GAP - (ICON + 18) }
    Heading(heads, L["SPELL"]):SetPoint("LEFT", ICON + 18, 0)
    Heading(heads, L["LEVEL"]):SetPoint("LEFT", heads, "RIGHT", -(levelRight + LEVEL_WIDTH), 0)
    Heading(heads, L["COST"], "RIGHT"):SetPoint("RIGHT", -costRight, 0)

    local list = CreateFrame("Frame", nil, left)
    list:SetPoint("TOPLEFT", 1, -1 - HEAD)
    list:SetPoint("BOTTOMRIGHT", -1, NOTE)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta) Train:Scroll(-delta * WHEEL) end)
    self.list = list
    self.rows = {}
    local columns = self.columns
    for index = 1, MOST_LINES do
        local row = Glass(list, index)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(ICON, ICON)
        row.icon:SetPoint("TOPLEFT", 8, -3)
        pcall(row.icon.SetTexCoord, row.icon, 0.08, 0.92, 0.08, 0.92)
        row.name = Theme.CreateLabel(row, "normal", "text")
        row.name:SetWordWrap(true)
        row.level = Theme.CreateLabel(row, "small", "muted")
        row.level:SetPoint("TOPRIGHT", -columns.level, -7)
        row.level:SetWidth(LEVEL_WIDTH)
        row.cost = Theme.CreateLabel(row, "small", "text", "RIGHT")
        row.cost:SetPoint("TOPRIGHT", -columns.cost, -7)
        row.cost:SetWidth(COST_WIDTH)
        row.cost:SetWordWrap(true)
        row:SetScript("OnEnter", function(self)
            self.over = true
            Paint(self)
            Train:SpellTip(self)
        end)
        row:SetScript("OnLeave", function(self)
            self.over = false
            Paint(self)
            GameTooltip:Hide()
        end)
        row:SetScript("OnClick", function(self, mouse)
            local line = rawget(self, "line")
            if mouse == "RightButton" and line and line.kind == "spell" then Train:Skip(line) end
        end)
        row:Hide()
        self.rows[index] = row
    end

    -- Under the list: how to skip, how many are skipped, and the way back.
    local note = Theme.CreateLabel(left, "small", "muted")
    note:SetPoint("BOTTOMLEFT", 12, 9)
    self.skipNote = note
    local show = Button(left, L["Show Skipped"], function()
        Train.showSkipped = not Train.showSkipped
        Train:Refresh()
    end, 20)
    show:SetPoint("BOTTOMRIGHT", -8, 5)
    self.skippedButton = show
    self.skippedWidth = math.max(Theme.TextWidth("small", L["Show Skipped"]),
        Theme.TextWidth("small", L["Hide Skipped"])) + 24
    show:SetWidth(self.skippedWidth)
end

function Train:BuildRight(body, left)
    local right = Theme.CreatePanel(body, "well", "border")
    right:SetPoint("TOPLEFT", left + 8, 0)
    right:SetPoint("BOTTOMRIGHT", 0, FOOT)
    self.right = right
    local width = WIDTH - PAD * 2 - left - 8
    self.rightWidth = width

    local heads = CreateFrame("Frame", nil, right)
    heads:SetPoint("TOPLEFT", 1, -1)
    heads:SetPoint("TOPRIGHT", -1, -1)
    heads:SetHeight(HEAD)
    Theme.Fill(heads, "header")
    Heading(heads, L["WEAPON SKILLS"]):SetPoint("LEFT", 12, 0)

    local list = CreateFrame("Frame", nil, right)
    list:SetPoint("TOPLEFT", 1, -1 - HEAD)
    list:SetPoint("BOTTOMRIGHT", -1, 1)
    self.skillList = list
    self.skillRows = {}
    local wayWidth = math.max(80, Theme.TextWidth("small", L["Show the Way"]) + 24)
    self.wayWidth = wayWidth
    for index = 1, MOST_SKILLS do
        local row = Glass(list, index)
        row.plain = true
        row.mark = row:CreateTexture(nil, "ARTWORK")
        row.mark:SetSize(14, 14)
        row.mark:SetPoint("TOPLEFT", 10, -6)
        row.mark:SetTexture(DONE_ICON)
        -- A skill still to learn: a small dim square where the tick will go.
        row.ring = row:CreateTexture(nil, "ARTWORK")
        row.ring:SetSize(6, 6)
        row.ring:SetPoint("TOPLEFT", 14, -10)
        row.ring:SetColorTexture(Theme.Unpack("dim"))
        row.name = Theme.CreateLabel(row, "normal", "text")
        row.name:SetPoint("TOPLEFT", 32, -6)
        row.name:SetWordWrap(true)
        row.sub = Theme.CreateLabel(row, "small", "muted")
        row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
        row.sub:SetWordWrap(true)
        row.known = Theme.CreateLabel(row, "small", "muted", "RIGHT")
        row.known:SetPoint("TOPRIGHT", -10, -7)
        row.known:SetText(L["Known"])
        row.way = Button(row, L["Show the Way"], function()
            local line = rawget(row, "line")
            if line and ns.WeaponSkills then ns.WeaponSkills:ShowMasterOf(line.subclassID) end
        end, 20)
        row.way:SetWidth(wayWidth)
        row.way:SetPoint("TOPRIGHT", -8, -4)
        row:Hide()
        self.skillRows[index] = row
    end
    local none = Theme.CreateLabel(list, "normal", "muted")
    none:SetPoint("TOPLEFT", 12, -12)
    none:SetWidth(width - 26)
    none:SetWordWrap(true)
    self.skillNote = none
end

function Train:Build(area)
    if self.page then return self.page end
    if not (area and Training()) then return nil end

    local page = CreateFrame("Frame", nil, area)
    page:SetAllPoints(area)
    Theme.Fill(page, "window")
    page:Hide()
    self.page = page

    local top = self:BuildBar(page)
    local body = CreateFrame("Frame", nil, page)
    body:SetPoint("TOPLEFT", PAD, -top)
    body:SetPoint("BOTTOMRIGHT", -PAD, 12)
    self.body, self.bodyTop = body, top
    local left = math.floor((WIDTH - PAD * 2) * LEFT_SHARE)
    self:BuildLeft(body, left)
    self:BuildRight(body, left)

    local foot = Theme.CreateLabel(body, "small", "muted")
    foot:SetPoint("BOTTOMLEFT", 2, 3)
    self.foot = foot
    local hint = Theme.CreateLabel(body, "small", "muted", "RIGHT")
    hint:SetPoint("BOTTOMRIGHT", -2, 3)
    hint:SetText(L["Prices are the trainer's own once you have visited one."])
    self.hint = hint
    return page
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

local function Room(self, taken)
    local ok, height = pcall(self.page.GetHeight, self.page)
    if not (ok and type(height) == "number" and height > 200) then height = 620 end
    return height - self.bodyTop - 12 - FOOT - taken
end

--- The game's own spell tooltip, then what it costs and how to skip it.
function Train:SpellTip(row)
    local line = rawget(row, "line")
    local spell = line and line.kind == "spell" and line.spell
    if not spell then return end
    local training = Training()
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local ok = type(GameTooltip.SetSpellByID) == "function" and pcall(GameTooltip.SetSpellByID, GameTooltip, spell.id)
    if not ok then GameTooltip:AddLine(row.name:GetText() or "", 1, 1, 1) end
    local words
    if not spell.cost then
        words = L["No price yet. Visit a class trainer once to see it."]
    elseif spell.guess then
        words = L.Format("Usually %s. Visit your trainer once for the real price.", training.Money(spell.cost))
    else
        words = L.Format("Costs %s at the trainer", training.Money(spell.cost))
    end
    GameTooltip:AddLine(words, Theme.Unpack("muted"))
    if not self:Other() then
        GameTooltip:AddLine(line.skipped and L["Right-click to bring it back."]
            or L["Right-click to skip this spell."], Theme.Unpack("good"))
    end
    GameTooltip:Show()
end

function Train:PaintLine(row, line, index)
    local training = Training()
    local columns = self.columns
    row.line = line
    row.headed = line.kind == "head"
    row.plain = line.kind ~= "spell"
    row.restKey = index % 2 == 0 and "glassAlt" or "glass"
    row.icon:SetShown(line.kind == "spell")
    row.level:SetText("")
    row.cost:SetText("")
    row.name:ClearAllPoints()
    if line.kind == "head" then
        row.name:SetPoint("TOPLEFT", 12, -5)
        row.name:SetWidth(self.leftWidth - 24)
        row.name:SetFont(Theme.FONT, Theme.sizes.tiny, "")
        row.name:SetTextColor(Theme.Unpack("accent"))
        row.name:SetText(line.text)
        return HEAD
    end
    row.name:SetFont(Theme.FONT, Theme.sizes.normal, "")
    if line.kind == "note" then
        row.name:SetPoint("TOPLEFT", 12, -6)
        row.name:SetWidth(self.leftWidth - 24)
        row.name:SetTextColor(Theme.Unpack("muted"))
        row.name:SetText(line.text)
        return math.max(ROW, 6 + TextHeight(row.name, "normal", self.leftWidth - 24) + 6)
    end
    local spell = line.spell
    row.icon:SetTexture(training.Icon(spell.entry))
    row.icon:SetAlpha((line.soon or line.skipped) and 0.6 or 1)
    row.name:SetPoint("TOPLEFT", ICON + 18, -6)
    row.name:SetWidth(columns.name)
    row.name:SetTextColor(Theme.Unpack((line.soon or line.skipped) and "muted" or "text"))
    row.name:SetText(training.Label(spell.entry))
    row.level:SetText(tostring(spell.level or ""))
    row.cost:SetText(spell.cost and training.Money(spell.cost) or L["Not priced yet"])
    return math.max(ROW, 6 + math.max(TextHeight(row.name, "normal", columns.name),
        TextHeight(row.cost, "small", COST_WIDTH)) + 6)
end

function Train:PaintLines(lines)
    self.lines = lines
    local room = Room(self, HEAD + 2 + NOTE)
    local offset = math.max(0, math.min(self.offset or 0, math.max(0, #lines - 1)))
    self.offset = offset
    local y, shown = 0, 0
    for index, row in ipairs(self.rows) do
        local line = lines[index + offset]
        row:Hide()
        row.line = nil
        if line and shown == index - 1 then
            local height = self:PaintLine(row, line, index)
            if index == 1 or y + height <= room then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -y)
                row:SetPoint("TOPRIGHT", 0, -y)
                row:SetHeight(height)
                Paint(row)
                row:Show()
                y = y + height
                shown = index
            else
                row.line = nil
            end
        end
    end
    self.linesShown = shown
end

function Train:PaintSkills()
    local other = self:Other()
    local lines = other and {} or self:Skills()
    self.skills = lines
    local room = Room(self, HEAD + 2)
    local y = 0
    for index, row in ipairs(self.skillRows) do
        local line = lines[index]
        row:Hide()
        row.line = line
        if line then
            local way = not line.known and line.way == true
            local width = self.rightWidth - 32 - 12 - (way and self.wayWidth + 8 or 70)
            row.mark:SetShown(line.known)
            row.ring:SetShown(not line.known)
            row.known:SetShown(line.known)
            row.way:SetShown(way)
            row.name:SetWidth(width)
            row.name:SetText(line.name)
            row.name:SetTextColor(Theme.Unpack(line.waited and "warn" or "text"))
            row.sub:SetWidth(width)
            row.sub:SetText(line.sub or "")
            local height = 6 + TextHeight(row.name, "normal", width) + 6
            if line.sub then height = height + 2 + TextHeight(row.sub, "small", width) end
            height = math.max(ROW, height)
            if index == 1 or y + height <= room then
                row.restKey = index % 2 == 0 and "glassAlt" or "glass"
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -y)
                row:SetPoint("TOPRIGHT", 0, -y)
                row:SetHeight(height)
                Paint(row)
                row:Show()
                y = y + height
            end
        end
    end
    local note = ""
    if other then
        note = L["Weapon skills show for the character you are playing."]
    elseif #lines == 0 then
        note = L["The game has not said which weapon skills you know yet."]
    end
    self.skillNote:SetText(note)
    self.skillNote:SetShown(note ~= "")
end

--- The Character: list as it stands, the one picked showing.
function Train:SyncWho()
    local options = {}
    for _, entry in ipairs(self:Characters()) do
        options[#options + 1] = { text = entry.name, value = entry.other and entry.guid or "me" }
    end
    local who = self.whoChoice
    who:SetOptions(options)
    who:SetValue(self:Other() and self.who or "me")
end

function Train:Refresh()
    if not self:IsShown() then return nil end
    local training = Training()
    self:SyncWho()
    local other = self:Other()
    local lines, plan = self:Lines()
    self:PaintLines(lines)
    self:PaintSkills()

    -- Along the top: what it costs, what you carry, the way there.
    local count = #plan.ready
    local on = other ~= nil or training:IsOn()
    self.costLabel:SetText(on and count > 0
        and L.Format("Train now: %s", training.CostText(plan.cost or 0, plan.unknown or 0, count)) or "")
    local held = not other and ns.Finder.MoneyHeld() or nil
    self.haveLabel:SetText(held and L.Format("You have %s", training.Money(held)) or "")
    local spot = not other and training:IsOn() and training:Nearest() or nil
    local where = training.Where(spot)
    self.wayButton:SetShown(not other and training:IsOn())
    if self.wayButton.SetDimmed then self.wayButton:SetDimmed(spot == nil) end
    self.trainerLine = where and L.Format("Your trainer: %s, %s.", spot.name or "?", where)
        or L["Open a class trainer once and its prices and location are remembered."]

    -- Under the list: skipping.
    local skipped = other and 0 or #plan.skipped
    local mine = not other and training:IsOn()
    local note = ""
    if mine then
        note = L["Right-click a spell to skip it."]
        if skipped > 0 then note = note .. " " .. L.Format("%d skipped.", skipped) end
    elseif other then
        note = L.Format("As last seen on %s, at level %d.", other.name or "?", other.level or 0)
    end
    self.skipNote:SetText(note)
    self.skippedButton:SetShown(mine and skipped > 0)
    self.skippedButton:SetText(self.showSkipped and L["Hide Skipped"] or L["Show Skipped"])
    self.skippedButton:SetWidth(self.skippedWidth)

    local foot = on and Train.FootText(plan) or ""
    if #lines > self.linesShown and self.linesShown > 0 then
        foot = foot .. " " .. L.Format("%d to %d of %d. Scroll for more.", self.offset + 1,
            self.offset + self.linesShown, #lines)
    end
    self.foot:SetText(foot)
    return plan
end

--------------------------------------------------------------------------------
-- Clicks
--------------------------------------------------------------------------------

--- Skip a spell (a right-click on it), or bring a skipped one back. It
--- leaves the lists and costs here and in Butler; nothing is bought or
--- forgotten. Only for the character playing.
function Train:Skip(line)
    local training = Training()
    if self:Other() or not (training and line.spell and line.spell.id) then return end
    training:SetSkipped(line.spell.id, not line.skipped)
    GameTooltip:Hide()
    self:Refresh()
end

function Train:Scroll(steps)
    local total = self.lines and #self.lines or 0
    local before = self.offset or 0
    self.offset = math.max(0, math.min(before + steps, math.max(0, total - 1)))
    if self.offset ~= before then self:Refresh() end
end

--------------------------------------------------------------------------------
-- Looking
--------------------------------------------------------------------------------

function Train:IsShown()
    local page = self.page
    if not Shown(page) then return false end
    local ok, visible = pcall(page.IsVisible, page)
    if ok and type(visible) == "boolean" then return visible end
    return true
end

--- The tab's name takes the count, whether or not the page shows.
function Train:PaintTab()
    local Gear = ns.GearWindow
    if Gear and Gear.SetTabText then Gear:SetTabText(Train.KEY, Train.TabText()) end
end

--- Once for a burst, and only while the page shows; the tab's name always.
function Train:RefreshSoon()
    if self.pending then return end
    local after = C_Timer and C_Timer.After
    if type(after) ~= "function" then
        self:PaintTab()
        return self:Refresh()
    end
    self.pending = true
    after(0.2, function()
        Train.pending = false
        Train:PaintTab()
        Train:Refresh()
    end)
end

function Train:OnTrackingChanged() end
function Train:OnUpgradeQuestChanged() end

function Train:Show()
    if not self.page then return end
    self.page:Show()
    self:PaintTab()
    self:Refresh()
end

function Train:Hide()
    if self.page then self.page:Hide() end
end

--- Open the Equipment window on this tab.
function Train:Open()
    if ns.GearWindow then ns.GearWindow:Open(Train.KEY) end
end

function Train:OnEnable()
    ns.RegisterEvent(self, "PLAYER_MONEY", function()
        if Train:IsShown() then Train:RefreshSoon() end
    end)
    -- A spell learned, a price seen or a skip comes through class
    -- training's own change call (UI/TrainingDrawer.lua passes it on), and
    -- a weapon skill learned through WeaponSkills:Look. Neither is read on
    -- every spell event.
    ns.RegisterEvent(self, "PLAYER_LEVEL_UP", function() Train:RefreshSoon() end)
    self:PaintTab()
end

if ns.GearWindow then ns.GearWindow:AddPage(Train.KEY, Train) end
