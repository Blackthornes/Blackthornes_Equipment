-- Blackthornes Equipment -- UI/LevelUpCard.lua
-- The Level Up card (the owner said build it from the mockup
-- equipment-improve-5-level-up, 2026-11-26).
--
-- A level is when a player most wants to know what changed. Once per
-- level, after the fight ends, one card sums it up: a heavier armor you
-- can wear now, the upgrades already in your bags, the new upgrades that
-- level opened, and the spells to train. Only lines with something to say
-- show; a level with nothing new shows no card.
--
-- It stands on the shared top shelf until dragged, then keeps its spot
-- (`windowSpots["equipment.levelup"]`, through SharedWindow.KeepSpot). A
-- click anywhere else fades it, and its red close gem shuts it. Its own
-- switch, "Level Up Card:" on the Gear page (`levelUpCard`, on unless
-- switched off). The level it last showed for is kept per character
-- (`levelUpCardShown`), so a reload never shows it twice. It plays no
-- sound and follows Effects (Full, Subtle, Off).
--
-- Nothing here judges gear: it reads the finder's shared scan after the
-- level (Finder:Fresh, else Finder:ScanInBackground, which rests in a
-- fight) and My Gear's reading of it (MyGear:Read).

local _, ns = ...
local L = ns.L

local Card = ns.NewModule("LevelUpCard")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Motion = ns.Motion
local Finder = ns.Finder

local WIDTH = 440
local PAD = 22
local ROW_GAP = 10
local STEP = 26
local BUTTON_H = 24
local SPOT_KEY = "equipment.levelup"

Card.WIDTH = WIDTH
Card.SPOT_KEY = SPOT_KEY
-- Seconds after the level before looking: the game settles the new level
-- and the gear it opens first.
Card.SETTLE = 1

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

local function InFight()
    local fn = _G.InCombatLockdown
    if type(fn) ~= "function" then return false end
    local ok, fighting = pcall(fn)
    return ok and fighting == true
end

local function TextHeight(label, fallback)
    local ok, height = pcall(label.GetStringHeight, label)
    if ok and type(height) == "number" and height > 0 then return height end
    local text = label:GetText()
    return (text and text ~= "") and fallback or 0
end

--- Is the card switched on? On unless switched off.
function Card:IsOn()
    return not (ns.db and ns.db.levelUpCard == false)
end

--------------------------------------------------------------------------------
-- What the card says
--------------------------------------------------------------------------------

--- The armor a class learns between two levels: "Plate" for a warrior
--- going 39 to 40. Nil when none opens.
function Card.ArmorOpened(class, from, to)
    local Weights = ns.Weights
    if not (Weights and Weights.CanUse and class) then return nil end
    local opened
    for _, sub in ipairs({ MAIL, PLATE }) do
        local ok, can, at = pcall(Weights.CanUse, Weights, class, ARMOR, sub, "INVTYPE_CHEST")
        if ok and can and type(at) == "number" and at > from and at <= to then opened = sub end
    end
    if not opened then return nil end
    local Road = ns.GearRoad
    if Road and Road.ArmorName then return Road.ArmorName(opened) end
    return opened == PLATE and L["Plate"] or L["Mail"]
end

--- An armor name as it reads mid-sentence: "plate". German keeps its
--- capital, as nouns do there.
function Card.ArmorWord(name)
    local ok, locale = pcall(_G.GetLocale)
    if ok and locale == "deDE" then return name end
    return name:lower()
end

--- The upgrades to go and get that the levels from `from` + 1 to `to`
--- opened: wearable now, needing one of those levels. Only what Find
--- Upgrades' filters let through, and never an ignored piece.
-- @return how many, and the best of them
function Card.NewPicks(found, from, to)
    local MyGear, FinderUI = ns.MyGear, ns.FinderUI
    if not (found and found.all and FinderUI and FinderUI.LevelOf) then return 0, nil end
    local quest = ns.UpgradeQuest
    local skipped = quest and quest.Skipped and quest:Skipped() or {}
    local pass = MyGear and MyGear.Filter and MyGear.Filter(found) or nil
    local seen, count, best, bestShown = {}, 0, nil, nil
    for _, entry in ipairs(ns.UI and ns.UI.SLOTS or {}) do
        for _, pick in ipairs(found.all[entry[1]] or {}) do
            local id = pick.itemID
            local passes = not pass or #pass(pick) > 0
            local later = MyGear and MyGear.Later and MyGear.Later(pick)
            if id and not seen[id] and not skipped[id] and passes and not later then
                local level = FinderUI.LevelOf(pick)
                if type(level) == "number" and level > from and level <= to then
                    seen[id] = true
                    count = count + 1
                    local shown = Finder.Shown(pick.result) or 1000
                    if not bestShown or shown > bestShown then best, bestShown = pick, shown end
                end
            end
        end
    end
    return count, best
end

--- What the card shows for a level up from `from` to `to`, from a scan.
-- @return { level, armor, ready = { links }, new, best, training } or nil
--   when there is nothing to say.
function Card.Read(found, from, to)
    if not found then return nil end
    local player = found.player or Finder:Player()
    local MyGear = ns.MyGear
    local state = MyGear and MyGear.Read and MyGear:Read(found) or { ready = {} }
    local new, best = Card.NewPicks(found, from, to)
    local read = {
        level = to,
        armor = player and Card.ArmorOpened(player.class, from, to) or nil,
        ready = state.ready or {},
        readState = state,
        new = new,
        best = best,
        training = state.training,
    }
    if not read.armor and #read.ready == 0 and new == 0 and not read.training then return nil end
    return read
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

--- One numbered line: its number, its words, a second line and a button.
function Card:BuildRow(index)
    local frame = self.frame
    local row = CreateFrame("Frame", nil, frame)
    row:SetWidth(WIDTH - PAD * 2)

    local step = CreateFrame("Frame", nil, row)
    step:SetSize(STEP, STEP)
    step:SetPoint("TOPLEFT", 0, -2)
    Theme.Fill(step, "glassActive")
    Theme.Border(step, "metal")
    row.number = Theme.CreateLabel(step, "large", "gilt", "CENTER")
    row.number:SetPoint("CENTER", 0, 0)

    row.line = Theme.CreateLabel(row, "normal", "text")
    row.line:SetPoint("TOPLEFT", STEP + 12, -4)
    row.line:SetWordWrap(true)
    row.under = Theme.CreateLabel(row, "small", "muted")
    row.under:SetPoint("TOPLEFT", row.line, "BOTTOMLEFT", 0, -4)
    row.under:SetWordWrap(true)

    row.button = Widgets.CreateButton(row, "", function()
        local run = rawget(row, "run")
        if run then run() end
    end, { width = 90, height = BUTTON_H, primary = true })
    row.button:SetPoint("TOPRIGHT", 0, 0)

    if index > 1 then
        local rule = Theme.CreateDivider(row, "border")
        rule:SetPoint("TOPLEFT", 0, ROW_GAP / 2 + 1)
        rule:SetPoint("TOPRIGHT", 0, ROW_GAP / 2 + 1)
    end
    row:Hide()
    return row
end

function Card:Build()
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame", "BlackthornesEquipmentLevelUp", UIParent)
    frame:SetSize(WIDTH, 200)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if not InFight() then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    Theme.Fill(frame, "window")
    if ns.Titanforged and ns.Titanforged.Dress then
        local ok, trim = pcall(ns.Titanforged.Dress, ns.Titanforged, frame, {
            close = function() Card:Hide() end,
        })
        if ok and trim and ns.Titanforged.Reach and frame.SetClampRectInsets then
            local left, right, top, bottom = ns.Titanforged.Reach(trim)
            frame:SetClampRectInsets(-left, right, top, -bottom)
        end
    else
        Theme.Border(frame, "accent")
    end
    if Theme.Halo then Theme.Halo(frame, 12, 0.18) end
    frame:Hide()
    self.frame = frame

    self.kicker = Theme.CreateLabel(frame, "tiny", "gilt", "CENTER")
    self.kicker:SetPoint("TOP", 0, -20)
    self.kicker:SetText(L["LEVEL UP"])
    self.title = Theme.CreateLabel(frame, 26, "gilt", "CENTER")
    self.title:SetPoint("TOP", self.kicker, "BOTTOM", 0, -8)
    self.armor = Theme.CreateLabel(frame, "normal", "text", "CENTER")
    self.armor:SetPoint("TOP", self.title, "BOTTOM", 0, -8)
    self.armor:SetWidth(WIDTH - PAD * 2)
    self.armor:SetWordWrap(true)
    self.rule = Theme.CreateDivider(frame, "border")

    self.rows = { self:BuildRow(1), self:BuildRow(2), self:BuildRow(3) }

    -- A click anywhere else fades it, as the game's menus close. Asked for
    -- only while it shows, inside a pcall: a client without the event keeps
    -- it until its close gem.
    frame:HookScript("OnShow", function(self) pcall(self.RegisterEvent, self, "GLOBAL_MOUSE_DOWN") end)
    frame:HookScript("OnHide", function(self) pcall(self.UnregisterEvent, self, "GLOBAL_MOUSE_DOWN") end)
    frame:SetScript("OnEvent", function(self)
        local ok, over = pcall(self.IsMouseOver, self)
        if ok and over then return end
        Card:FadeOut()
    end)

    -- Kept where it is dragged; else on the shared top shelf.
    local sw = ns.SharedWindow
    if sw and sw.KeepSpot then sw.KeepSpot(frame, SPOT_KEY) end
    return frame
end

--- Has the player dragged it somewhere?
function Card:Dragged()
    local spots = ns.db and ns.db.windowSpots
    return type(spots) == "table" and type(spots[SPOT_KEY]) == "table"
end

--- On the shared top shelf until dragged (KeepSpot lays a dragged one).
function Card:Place()
    local frame = self.frame
    if not frame or self:Dragged() then return end
    local sw = ns.SharedWindow
    local placed = sw and sw.ShelfPlace and sw.ShelfPlace(frame, "upgrade.levelup", {
        free = function() return not Card:Dragged() end,
        place = function() Card:Place() end,
    })
    if not placed then
        frame:ClearAllPoints()
        frame:SetPoint("TOP", UIParent, "TOP", 0, -150)
    end
end

local function SetRow(row, line, under, label, run)
    local width = WIDTH - PAD * 2 - STEP - 12
    row.button:SetText(label)
    local buttonWidth = math.max(90, Theme.TextWidth("small", label) + 28)
    row.button:SetWidth(buttonWidth)
    row.run = run
    row.line:SetWidth(width - buttonWidth - 10)
    row.line:SetText(line)
    row.under:SetWidth(width - buttonWidth - 10)
    row.under:SetText(under or "")
    row.under:SetShown(under ~= nil and under ~= "")
    local height = 4 + TextHeight(row.line, 14)
    if under and under ~= "" then height = height + 4 + TextHeight(row.under, 12) end
    height = math.max(STEP + 4, BUTTON_H, math.ceil(height + 2))
    row:SetHeight(height)
    return height
end

--- Fill the card from what was read and lay it out.
function Card:Fill(read)
    self:Build()
    self.read = read
    self.title:SetText(L.Format("Level %d", read.level))
    local y = 20 + TextHeight(self.kicker, 10) + 8 + TextHeight(self.title, 26)
    if read.armor then
        self.armor:SetText(L.Format("You can wear %s now.", Card.ArmorWord(read.armor)))
        self.armor:Show()
        y = y + 8 + TextHeight(self.armor, 14)
    else
        self.armor:SetText("")
        self.armor:Hide()
    end
    y = y + 14
    self.rule:ClearAllPoints()
    self.rule:SetPoint("TOPLEFT", 1, -y)
    self.rule:SetPoint("TOPRIGHT", -1, -y)
    y = y + 14

    local lines = {}
    local ready = #read.ready
    if ready > 0 then
        lines[#lines + 1] = {
            ready == 1 and L["1 upgrade in your bags."] or L.Format("%d upgrades in your bags.", ready), nil,
            ready == 1 and L["Put It On"] or L["Put Them On"],
            function()
                if ns.MyGear and ns.MyGear.PutOnReady and read.readState then
                    ns.MyGear.PutOnReady(read.readState)
                elseif ns.Wear then
                    ns.Wear:PutOnAll(read.ready)
                end
            end,
        }
    end
    if read.new > 0 then
        local best = read.best
        local under
        if best then
            local shown = Finder.Shown(best.result)
            under = L.Format("Best: %s", ns.Items.ShowLink(best.link))
                .. (shown and ("  " .. Colored("good", ("%+d%%"):format(shown))) or "")
        end
        lines[#lines + 1] = {
            read.new == 1 and L["1 new upgrade to go and get."] or L.Format("%d new upgrades to go and get.", read.new),
            under, L["Show Me"],
            function()
                if ns.GearWindow then ns.GearWindow:Open("find") end
                Card:Hide()
            end,
        }
    end
    if read.training then
        local count = read.training.count
        local words = count == 1 and L["1 spell to train."] or L.Format("%d spells to train.", count)
        lines[#lines + 1] = {
            words .. "  " .. (read.training.cost or ""), nil, L["Show the Way"],
            function() if ns.ClassTraining then ns.ClassTraining:ShowTheWay() end end,
        }
    end

    for index, row in ipairs(self.rows) do
        local line = lines[index]
        if line then
            row.number:SetText(tostring(index))
            if index > 1 then y = y + ROW_GAP end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", PAD, -y)
            y = y + SetRow(row, line[1], line[2], line[3], line[4])
            row:Show()
        else
            row.run = nil
            row:Hide()
        end
    end
    self.lines = #lines
    self.frame:SetHeight(math.ceil(y + PAD))
end

--------------------------------------------------------------------------------
-- Showing
--------------------------------------------------------------------------------

local function Level()
    return Motion and Motion.Level and Motion.Level() or "full"
end

function Card:Show(read)
    if type(read) ~= "table" then return false end
    self:Fill(read)
    local frame = self.frame
    self:Place()
    if Motion then Motion:Stop(frame, "fade") end
    local level = Level()
    frame:SetAlpha(level == "off" and 1 or 0)
    frame:Show()
    if level ~= "off" and Motion then
        Motion:Run(frame, "fade", level == "full" and 0.35 or 0.2, function(p) frame:SetAlpha(p) end)
    else
        frame:SetAlpha(1)
    end
    return true
end

function Card:FadeOut()
    local frame = self.frame
    if not Shown(frame) then return end
    if Level() == "off" or not Motion then return self:Hide() end
    Motion:Run(frame, "fade", 0.3, function(p) frame:SetAlpha(1 - p) end,
        { done = function() Card:Hide() end })
end

function Card:Hide()
    local frame = self.frame
    if not frame then return end
    if Motion then Motion:Stop(frame, "fade") end
    frame:Hide()
    frame:SetAlpha(1)
end

--- Look at the scan for the level waiting, once the fight is over, and
--- show the card if it has something to say. The level counts as seen
--- either way, so it never comes back.
function Card:TryShow()
    local wait = self.pending
    if not wait or not self:IsOn() then
        self.pending = nil
        return false
    end
    if InFight() then return false end
    local found = Finder:Fresh()
    local player = found and found.player
    if not (found and player and (player.level or 0) >= wait.to) then
        if self.asking then return false end
        self.asking = true
        Finder:ScanInBackground(function(scan)
            Card.asking = nil
            if scan and Card.pending == wait and not InFight() then Card:Present(scan, wait) end
        end)
        return false
    end
    return self:Present(found, wait)
end

function Card:Present(found, wait)
    self.pending = nil
    if ns.charDB then ns.charDB.levelUpCardShown = wait.to end
    local read = Card.Read(found, wait.from, wait.to)
    if not read then return false end
    return self:Show(read)
end

--- The character went up a level (PLAYER_LEVEL_UP's first value is the
--- new level). Levels gained before the card shows add up to one card.
function Card:Note(level)
    if not tonumber(level) then
        local ok, now = pcall(_G.UnitLevel, "player")
        level = ok and now or 0
    end
    level = tonumber(level) or 0
    local from = self.level or (level - 1)
    self.level = math.max(self.level or 0, level)
    if level <= from or not self:IsOn() then return end
    local shown = ns.charDB and tonumber(ns.charDB.levelUpCardShown) or 0
    if level <= shown then return end
    self.pending = { from = self.pending and self.pending.from or from, to = level }
    if C_Timer and C_Timer.After then
        C_Timer.After(Card.SETTLE, function() Card:TryShow() end)
    else
        self:TryShow()
    end
end

function Card:OnEnable()
    local ok, level = pcall(_G.UnitLevel, "player")
    if ok and type(level) == "number" and level > 0 then self.level = level end
    ns.RegisterEvent(self, "PLAYER_LEVEL_UP", function(_, _, newLevel) Card:Note(newLevel) end)
    ns.RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
        if Card.pending then Card:TryShow() end
    end)
end
