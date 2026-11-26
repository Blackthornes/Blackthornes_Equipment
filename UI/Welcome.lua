-- Blackthornes Equipment -- UI/Welcome.lua
-- First Time Setup (the owner said build it, 2026-11-26, from the mockup
-- Docs/mockups/equipment-improve-6-first-time.html in the project files).
--
-- The first time a new player opens the Equipment window, one card lies
-- over its page and offers the best parts that start off: Upgrade Quest,
-- the Quest Arrow and Put On Upgrades, beside the spec picks and the two
-- upgrade marks that start on.
--
-- The rules it keeps:
--   * Big features still start off. A box is ticked only when the player
--     ticks it, and the five boxes change nothing until Done.
--   * Each box sets the same saved setting the Settings page does, through
--     the same calls. The spec drop-downs are the ones every page shows, so
--     they set the spec at once, as they do there.
--   * One new saved key, `welcomeSeen` (account wide, never rename it).
--     Core/Init.lua sets it true for any save that already held something,
--     so players who already use the addon never see the card. Skip and
--     Done both set it; closing the window leaves it, so the card waits for
--     the next open.
--   * `/beq welcome` opens it again.
--
-- Nothing here runs until the window shows a tab.

local _, ns = ...
local L = ns.L

local Welcome = ns.NewModule("Welcome")

local Theme = ns.Theme
local Widgets = ns.Widgets

local PAD = 30
local HEAD = 30
local ROW = 50
local LINE = 1
-- Kept above every page in the window's area.
local LIFT = 60

-- The five boxes: their key here, name, what each does, and how to read
-- and set the saved setting behind it. `get` answers the box's start;
-- `set` runs only on Done, and only when the box moved.
local BOXES = {
    { section = 2, key = "upgradeQuest", name = L["Upgrade Quest"],
        what = L["Picks your next upgrade and walks you to it, one step at a time."],
        get = function() return ns.UpgradeQuest ~= nil and ns.UpgradeQuest:IsEnabled() end,
        set = function(on)
            local quest = ns.UpgradeQuest
            if not quest then return end
            if on and quest.TurnOn then quest:TurnOn() else quest:SetEnabled(on) end
        end },
    { section = 2, key = "questArrow", name = L["Quest Arrow"],
        what = L["An arrow on your screen that points to the next step."],
        get = function() return ns.db.questArrow == true end,
        set = function(on)
            if ns.QuestArrow then ns.QuestArrow:SetOn(on) else ns.db.questArrow = on end
        end },
    { section = 2, key = "autoEquip", name = L["Put On Upgrades"],
        what = L["Puts on better gear from your bags for you. It never touches gear that would bind."],
        get = function() return ns.db.autoEquip == true end,
        set = function(on) ns.db.autoEquip = on end },
    { section = 3, key = "bagArrows", name = L["Green Arrows"],
        what = L["On bags, vendors, loot and quest rewards."],
        get = function() return ns.db.bagArrows ~= false end,
        set = function(on)
            ns.db.bagArrows = on
            local settings = ns.SettingsUI
            if settings and settings.RedrawArrows then settings.RedrawArrows() end
        end },
    { section = 3, key = "tooltipLine", name = L["Tooltip Lines"],
        what = L["A line on each item that says how much better it is."],
        get = function() return ns.db.tooltipLine ~= false end,
        set = function(on)
            -- The same as Settings' Tooltip Line stepper: on keeps the
            -- Shift or Always choice the player had.
            local Shift = ns.TooltipShift
            local isOn = ns.db.tooltipLine ~= false
            local function SetOn(value) ns.db.tooltipLine = value end
            if Shift and Shift.Apply then
                local mode = Shift.OFF
                if on then mode = Shift.Read("upgrade") and Shift.SHIFT or Shift.ALWAYS end
                Shift:Apply(mode, "upgrade", isOn, SetOn)
            else
                SetOn(on)
            end
            if ns.Tooltip and ns.Tooltip.ForgetLines then ns.Tooltip.ForgetLines() end
        end },
}
Welcome.BOXES = BOXES

local SECTIONS = {
    L["1. HOW DO YOU PLAY"],
    L["2. HOW MUCH HELP DO YOU WANT"],
    L["3. WHERE TO SHOW UPGRADES"],
}

-- Asked for by /beq welcome: shown even after it was seen.
Welcome.asked = false

--------------------------------------------------------------------------------
-- Whether it shows
--------------------------------------------------------------------------------

--- Has this save seen the card (or never needed it)?
function Welcome.Seen()
    return not (ns.db and ns.db.welcomeSeen == false)
end

--- Should the card lie over the window now?
function Welcome:Wanted()
    return self.asked or not Welcome.Seen()
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

local function Head(parent, text, y, width)
    local band = CreateFrame("Frame", nil, parent)
    band:SetPoint("TOPLEFT", 0, y)
    band:SetSize(width, HEAD)
    local fill = band:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(band)
    Theme.SetGradientAlpha(fill, "HORIZONTAL", "accent", 0.12, 0)
    local rule = Theme.CreateDivider(band, "border")
    rule:SetPoint("BOTTOMLEFT")
    rule:SetWidth(width)
    local label = Theme.CreateLabel(band, "tiny", "accent")
    label:SetPoint("LEFT", 14, 0)
    label:SetText(text)
    band.label = label
    return band
end

local function Paint(row)
    local over = rawget(row, "over") == true
    row.background:SetColorTexture(Theme.Unpack(over and "glassHover" or row.restKey))
    row.edge:SetShown(over)
end

--- One box's row: dark glass, its name and what it does under it. A click
--- anywhere on the row ticks the box.
local function BoxRow(parent, entry, place, y, width)
    local row = CreateFrame("Button", nil, parent)
    row:SetPoint("TOPLEFT", PAD - 14, y)
    row:SetSize(width - (PAD - 14) * 2, ROW)
    row.restKey = place % 2 == 1 and "glass" or "glassAlt"
    row.background = row:CreateTexture(nil, "BACKGROUND")
    row.background:SetAllPoints(row)
    local line = row:CreateTexture(nil, "BORDER")
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetHeight(LINE)
    line:SetColorTexture(Theme.Unpack("border", 0.6))
    local edge = row:CreateTexture(nil, "OVERLAY")
    edge:SetPoint("TOPLEFT")
    edge:SetPoint("BOTTOMLEFT")
    edge:SetWidth(2)
    edge:SetColorTexture(Theme.Unpack("accentHi"))
    row.edge = edge

    local box = Widgets.CreateCheckbox(row, entry.name, nil, false)
    box:SetPoint("TOPLEFT", 14, -8)
    pcall(box.label.SetFont, box.label, Theme.FONT, Theme.sizes.normal, "")
    box:SetWidth((box.label:GetStringWidth() or 80) + 24)
    row.box = box

    local what = Theme.CreateLabel(row, "small", "muted")
    what:SetPoint("TOPLEFT", 34, -28)
    what:SetPoint("RIGHT", row, "RIGHT", -14, 0)
    what:SetJustifyH("LEFT")
    what:SetWordWrap(true)
    what:SetText(entry.what)
    row.what = what

    row:SetScript("OnClick", function()
        local click = box:GetScript("OnClick")
        if click then click(box) end
    end)
    local function Over(on)
        row.over = on
        Paint(row)
    end
    row:SetScript("OnEnter", function() Over(true) end)
    row:SetScript("OnLeave", function() Over(false) end)
    if box.HookScript then
        pcall(box.HookScript, box, "OnEnter", function() Over(true) end)
        pcall(box.HookScript, box, "OnLeave", function() Over(false) end)
    end
    Paint(row)
    return row
end

--- Build the card in the window's page area.
function Welcome:Build(area)
    if self.frame then return self.frame end
    local card = CreateFrame("Frame", nil, area)
    card:SetAllPoints(area)
    card:SetFrameLevel((area:GetFrameLevel() or 0) + LIFT)
    card:EnableMouse(true)
    Theme.Fill(card, "panel")
    self.frame = card

    local width = (ns.GearWindow and ns.GearWindow.WIDTH) or 1040

    local title = Theme.CreateLabel(card, "title", "gilt")
    title:SetPoint("TOPLEFT", PAD, -24)
    title:SetText(L["Welcome to Equipment"])
    pcall(title.SetFont, title, Theme.FONT, Theme.sizes.title + 4, "")
    self.title = title

    local sub = Theme.CreateLabel(card, "normal", "muted")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    sub:SetPoint("RIGHT", card, "RIGHT", -PAD, 0)
    sub:SetJustifyH("LEFT")
    sub:SetWordWrap(true)
    sub:SetText(L["Three quick picks and you are set. You can change them later in Settings."])
    self.sub = sub

    local body = CreateFrame("Frame", nil, card)
    body:SetPoint("TOPLEFT", card, "TOPLEFT", 0, -80)
    body:SetPoint("RIGHT", card, "RIGHT")
    body:SetHeight(1)
    self.body = body

    local y = 0
    self.heads, self.rows = {}, {}

    -- 1. How you play: the Main Spec and Off Spec drop-downs every page shows.
    self.heads[1] = Head(body, SECTIONS[1], y, width)
    y = y - HEAD - 12
    local FinderUI = ns.FinderUI
    local mainLabel = Theme.CreateLabel(body, "normal", "heading")
    mainLabel:SetPoint("TOPLEFT", PAD, y - 6)
    mainLabel:SetText(L["Main Spec:"])
    if FinderUI and FinderUI.MainSpecChoice then
        local main = FinderUI.MainSpecChoice(body, 170)
        main:SetPoint("LEFT", mainLabel, "RIGHT", 10, 0)
        self.mainChoice = main
        local offLabel = Theme.CreateLabel(body, "normal", "heading")
        offLabel:SetPoint("LEFT", main, "RIGHT", 24, 0)
        offLabel:SetText(L["Off Spec:"])
        local off = FinderUI.OffSpecChoice(body, 150)
        off:SetPoint("LEFT", offLabel, "RIGHT", 10, 0)
        self.offChoice = off
    end
    y = y - 40

    -- 2. and 3.: the boxes, in dark glass rows under their heads.
    local section, place = 1, 0
    for _, entry in ipairs(BOXES) do
        if entry.section ~= section then
            section = entry.section
            place = 0
            y = y - 6
            self.heads[section] = Head(body, SECTIONS[section], y, width)
            y = y - HEAD - 6
        end
        place = place + 1
        local row = BoxRow(body, entry, place, y, width)
        row.entry = entry
        self.rows[#self.rows + 1] = row
        y = y - ROW
    end

    local done = Widgets.CreateButton(card, L["Done"], function() Welcome:Done() end,
        { primary = true, width = math.max(96, Theme.TextWidth("normal", L["Done"]) + 40), height = 30 })
    done:SetPoint("TOPRIGHT", body, "TOPRIGHT", -(PAD - 14), y - 18)
    self.doneButton = done
    local skip = Widgets.CreateButton(card, L["Skip"], function() Welcome:Skip() end,
        { width = math.max(96, Theme.TextWidth("normal", L["Skip"]) + 40), height = 30 })
    skip:SetPoint("RIGHT", done, "LEFT", -12, 0)
    self.skipButton = skip

    card:Hide()
    return card
end

--------------------------------------------------------------------------------
-- Showing
--------------------------------------------------------------------------------

--- Every box and drop-down as the settings stand now.
function Welcome:Sync()
    for _, row in ipairs(self.rows or {}) do
        local ok, on = pcall(row.entry.get)
        row.box:SetChecked(ok and on == true)
    end
    local FinderUI = ns.FinderUI
    if self.mainChoice and FinderUI and FinderUI.SyncSpecChoices then
        pcall(FinderUI.SyncSpecChoices, self.mainChoice, self.offChoice)
    end
end

--- The window showed a tab (UI/GearWindow.lua): lay the card over it when
--- it is wanted.
function Welcome:Offer()
    local Gear = ns.GearWindow
    if not (Gear and Gear.area and Gear:IsShown()) then return false end
    if not self:Wanted() then
        if self.frame then self.frame:Hide() end
        return false
    end
    local fresh = not self.frame
    self:Build(Gear.area)
    if fresh or not self.frame:IsShown() then self:Sync() end
    self.frame:Show()
    return true
end

--- Is the card up?
function Welcome:IsShown()
    local frame = self.frame
    if not frame then return false end
    local ok, shown = pcall(frame.IsShown, frame)
    local Gear = ns.GearWindow
    return ok and shown == true and Gear ~= nil and Gear:IsShown()
end

local function Close()
    if ns.db then ns.db.welcomeSeen = true end
    Welcome.asked = false
    if Welcome.frame then Welcome.frame:Hide() end
    if ns.SettingsUI and ns.SettingsUI.Refresh then pcall(ns.SettingsUI.Refresh, ns.SettingsUI) end
    if ns.GearWindow and ns.GearWindow.Refresh then pcall(ns.GearWindow.Refresh, ns.GearWindow) end
end

--- Skip: change nothing more, and never show the card by itself again.
function Welcome:Skip()
    Close()
end

--- Done: each box that moved sets its setting, as Settings would.
function Welcome:Done()
    for _, row in ipairs(self.rows or {}) do
        local entry = row.entry
        local ok, was = pcall(entry.get)
        local want = row.box:GetChecked() == true
        if not ok or (was == true) ~= want then
            local fine, err = pcall(entry.set, want)
            if not fine and geterrorhandler then geterrorhandler()(err) end
        end
    end
    Close()
end

--- /beq welcome: open the window with the card on it.
function Welcome:Open()
    self.asked = true
    local Gear = ns.GearWindow
    if not Gear then return end
    if Gear:IsShown() then
        self:Offer()
    else
        Gear:Open()
    end
end

ns.RegisterCommand("welcome", L["open the welcome card again"], function()
    Welcome:Open()
end)
