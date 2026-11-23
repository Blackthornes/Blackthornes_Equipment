-- Blackthornes Equipment -- UI/GearWindow.lua
-- The Equipment window (rework step 2, the owner approved the mockups,
-- 2026-11-22): one frame with a tab bar along its top and one page under
-- it. My Gear (UI/MyGear.lua) is the page it opens on.
--
-- Find Upgrades (UI/FindUpgrades.lua, step 3) is the second page. Upgrade
-- Quest (UI/UpgradeQuestTab.lua, step 4) is the third, Dungeons
-- (UI/DungeonsTab.lua) and Training (UI/TrainingTab.lua, step 5) come
-- next, and Settings (UI/Settings.lua) is last, at the right end.
--
-- Every tab is a page built here since step 6 (2026-11-23): the old
-- windows that were laid into the page area are gone. A key an old tab had
-- still opens the page that took its place (Gear.FORMER).
--
-- With "One Window:" ticked (UI/SharedWindow.lua) this frame is what
-- Equipment lays into the one window, without its own rim: the tab bar
-- stays along the top. Unticked, it wears the house frame and keeps the
-- spot and size the old gear window had (`finderPoint` and the rest,
-- `finderScale`), so nobody's window moves.
--
-- Nothing here runs while the window is closed.

local _, ns = ...
local L = ns.L

local Gear = ns.NewModule("GearWindow")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Motion = ns.Motion

-- The tab bar's height, and the gap under it.
local BAR = 28
local BAR_GAP = 2
-- In its own frame: the bar sits under the title plate, clear of the
-- portrait, and the page keeps inside the metal rim.
local TOP = 18
local SIDE = 6
local PORTRAIT_CLEAR = 58

Gear.BAR = BAR + BAR_GAP
-- What its own frame adds round a page: the rim at the sides, and the
-- plate's room, the tab bar and the rim top to bottom.
Gear.CHROME_WIDTH = SIDE * 2
Gear.CHROME_HEIGHT = TOP + BAR + BAR_GAP + SIDE

-- The tabs, left to right; Settings is always last, at the right end.
local TABS = {
    { key = "gear", text = L["My Gear"] },
    { key = "find", text = L["Find Upgrades"] },
    { key = "quest", text = L["Upgrade Quest"] },
    { key = "instances", text = L["Dungeons"] },
    -- Wide enough for the count its name carries ("Training (12)").
    { key = "training", text = L["Training"],
        width = math.max(92, Theme.TextWidth("normal", L.Format("Training (%d)", 88)) + 28) },
    { key = "settings", text = L["Settings"], right = true },
}
Gear.TABS = TABS

local IS_TAB = {}
for _, tab in ipairs(TABS) do IS_TAB[tab.key] = true end

-- The keys the old tabs had, and the page that shows what each showed: the
-- old gear list is Find Upgrades, the Enchants tab is My Gear (the best
-- enchant is on each slot), Dungeon Quests and Dungeon Loot are Dungeons.
-- The one window and the swap gem may still ask by an old key.
Gear.FORMER = { upgrades = "find", enchant = "gear", dungeons = "instances", loot = "instances" }

-- The room a page has, the same on every tab, so the window never jumps as
-- the tabs are clicked: what the old gear list took, or more when a page
-- says it needs it (Gear:Need).
Gear.WIDTH, Gear.HEIGHT = 1040, 668
Gear.needs = {}

-- The page a tab built here shows: { key = module }, each with Build(area),
-- Show(), Hide() and IsShown(). Later steps add theirs.
Gear.pages = {}

-- The one window's area while this frame is laid into it, else nil.
Gear.hostArea = nil
-- The tab to show when the one window lays this frame in.
Gear.wanted = nil
-- The tab showing.
Gear.tab = nil

local function Shown(frame)
    if not frame then return false end
    local ok, shown = pcall(frame.IsShown, frame)
    return ok and shown == true
end

local function Size(frame)
    local okW, width = pcall(frame.GetWidth, frame)
    local okH, height = pcall(frame.GetHeight, frame)
    return okW and type(width) == "number" and width or nil, okH and type(height) == "number" and height or nil
end

--- The copy of the one window that draws it, or nil.
function Gear.One()
    local SharedWindow = ns.SharedWindow
    if not (SharedWindow and SharedWindow.Drawer) then return nil end
    local ok, drawer = pcall(SharedWindow.Drawer)
    local api = ok and type(drawer) == "table" and drawer.api or nil
    return type(api) == "table" and api or nil
end

--- A page built here joins under its tab's key.
function Gear:AddPage(key, module)
    self.pages[key] = module
    if self.frame and module.Build then module:Build(self.area) end
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

--- The room a page has: the usual, or the most any page asked for.
function Gear:PageSize()
    local width, height = Gear.WIDTH, Gear.HEIGHT
    for _, need in pairs(self.needs) do
        if type(need[1]) == "number" and need[1] > width then width = need[1] end
        if type(need[2]) == "number" and need[2] > height then height = need[2] end
    end
    return math.ceil(width), math.ceil(height)
end

--- A page says how much room it needs; nil for either keeps the usual.
--- The window grows when that moves the size the pages share.
function Gear:Need(key, width, height)
    local beforeWidth, beforeHeight = self:PageSize()
    self.needs[key] = { width, height }
    local afterWidth, afterHeight = self:PageSize()
    if beforeWidth == afterWidth and beforeHeight == afterHeight then return end
    if self.frame then self:Grow() end
end

--- Where the bar and the page sit: under the plate and inside the rim in
--- its own frame, edge to edge inside the one window.
function Gear:Lay()
    local frame, bar, area = self.frame, self.bar, self.area
    if not frame then return end
    local own = self.hostArea == nil
    local top, side, tabX = own and TOP or 0, own and SIDE or 0, own and PORTRAIT_CLEAR or 0
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", side, -top)
    bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -side, -top)
    bar:SetHeight(BAR)
    local strip = self.strip
    if strip then
        strip:ClearAllPoints()
        strip:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", tabX, 0)
        local width = Size(frame)
        if width and width > 0 and strip.SetRoom then
            strip:SetRoom(width - side * 2 - tabX - (own and 12 or 0))
        end
    end
    area:ClearAllPoints()
    area:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -BAR_GAP)
    area:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -side, side)
end

function Gear:Build()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "BlackthornesEquipmentWindow", UIParent)
    local width, height = self:PageSize()
    frame:SetWidth(width + Gear.CHROME_WIDTH)
    frame:SetHeight(height + Gear.CHROME_HEIGHT)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    Theme.Fill(frame, "window")

    -- The house frame (UI/Titanforged.lua): gold rim, the name on its
    -- plate, the portrait and the red close gem.
    if ns.Titanforged then
        local trim = ns.Titanforged:Dress(frame, {
            title = "Blackthornes Equipment",
            portrait = true,
            close = function() Gear:Close() end,
        })
        local left, right, top, bottom = ns.Titanforged.Reach(trim)
        if frame.SetClampRectInsets then frame:SetClampRectInsets(-left, right, top, -bottom) end
    else
        Theme.Border(frame, "borderLit")
    end
    Theme.Halo(frame, 12, 0.14)

    -- The fold gem left of the close gem, and the swap gem left of that.
    if ns.FoldWindow then
        ns.FoldWindow:Add(frame, { key = "Gear", onToggle = function(folded)
            if not folded then Gear:Refresh() end
        end })
    end
    if ns.SharedWindow and ns.SharedWindow.AddSwap then ns.SharedWindow.AddSwap(frame, "equipment") end

    -- Dragged, it keeps its spot; nothing else places it meanwhile.
    frame:SetScript("OnDragStart", function(self)
        if Gear.hostArea then return end
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        if Gear.hostArea then return end
        self:StopMovingOrSizing()
        if ns.db then ns.db.finderMoved = true end
        Gear:SavePosition()
    end)

    -- The house size grip, saved as `finderScale` as the old window's was.
    self.sizeGrip = Widgets.WindowGrip(frame, "finderScale", function()
        if ns.db then ns.db.finderMoved = true end
        Gear:SavePosition()
    end)

    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "BlackthornesEquipmentWindow")
    end
    -- Closed by Escape, the pages go with it. Inside the one window that
    -- window says when Equipment goes (Gear:Leave): folded into its round
    -- button it hides this frame too, and shows it again as it was.
    frame:SetScript("OnHide", function()
        if not Gear.hostArea then Gear:Closed() end
    end)

    local bar = CreateFrame("Frame", nil, frame)
    self.bar = bar
    -- A fine gold line under the tabs, bright at the left.
    local rule = bar:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    rule:SetHeight(1)
    Theme.SetGradientAlpha(rule, "HORIZONTAL", "accent", 0.6, 0.05)

    local area = CreateFrame("Frame", nil, frame)
    area.blackthornesGear = true
    self.area = area

    self.frame = frame
    self.strip = Widgets.CreateTabStrip(bar, TABS, function(key)
        Gear:ShowTab(key)
    end, { width = width - PORTRAIT_CLEAR - 12, spread = true })
    self:Lay()

    for _, module in pairs(self.pages) do
        if module.Build then module:Build(area) end
    end

    frame:Hide()
    return frame
end

--------------------------------------------------------------------------------
-- Size and spot
--------------------------------------------------------------------------------

--- Grow to hold the page size every tab shares: the one window while this
--- frame is in it, else this frame.
function Gear:Grow()
    local frame = self.frame
    if not frame then return end
    local width, height = self:PageSize()
    local host = self.hostArea
    if not host then
        local oldWidth = Size(frame)
        frame:SetWidth(width + Gear.CHROME_WIDTH)
        frame:SetHeight(height + Gear.CHROME_HEIGHT)
        if oldWidth ~= width + Gear.CHROME_WIDTH then self:Lay() end
        return
    end
    local one = host:GetParent()
    if not one then return end
    height = height + BAR + BAR_GAP
    local hostWidth, hostHeight = Size(host)
    local oneWidth, oneHeight = Size(one)
    if hostWidth and oneWidth and hostWidth > 0 and hostWidth < width then
        one:SetWidth(oneWidth + (width - hostWidth))
    end
    if hostHeight and oneHeight and hostHeight > 0 and hostHeight < height then
        one:SetHeight(oneHeight + (height - hostHeight))
    end
    if ns.SharedWindow and ns.SharedWindow.Fit then ns.SharedWindow.Fit(one) end
    self:Lay()
end

function Gear:SavePosition()
    if not (ns.db and self.frame) or self.hostArea then return end
    local point, _, relativePoint, x, y = self.frame:GetPoint()
    ns.db.finderPoint, ns.db.finderRelativePoint = point, relativePoint
    ns.db.finderX, ns.db.finderY = x, y
end

--- Where it was left; else where the first gear window was; else the middle.
function Gear:RestorePosition()
    if not self.frame or self.hostArea then return end
    local db = ns.db or {}
    self.frame:ClearAllPoints()
    if db.finderPoint then
        self.frame:SetPoint(db.finderPoint, UIParent, db.finderRelativePoint or db.finderPoint,
            db.finderX or 0, db.finderY or 0)
    elseif db.point then
        self.frame:SetPoint(db.point, UIParent, db.relativePoint or db.point, db.x or 0, db.y or 0)
    else
        self.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    end
end

--------------------------------------------------------------------------------
-- Tabs
--------------------------------------------------------------------------------

--- Is the window up, in its own frame or in the one window?
function Gear:IsShown()
    return Shown(self.frame)
end

function Gear:HidePages(except)
    for key, module in pairs(self.pages) do
        if key ~= except and module.Hide then module:Hide() end
    end
end

--- The tab a key names: itself, the page an old tab's key became, or My
--- Gear for a key nobody knows.
function Gear.TabFor(key)
    key = Gear.FORMER[key] or key
    return IS_TAB[key] and key or "gear"
end

--- Show a tab's page. `driving` is set meanwhile, so a page whose own Show
--- opens this window knows the window asked.
function Gear:ShowTab(key)
    if not self.frame then return end
    key = Gear.TabFor(key)
    self.tab = key
    if self.strip then self.strip:Select(key) end
    self:HidePages(key)
    local module = self.pages[key]
    if not (module and module.Show) then return end
    local was = self.driving
    self.driving = true
    local ok, err = pcall(module.Show, module)
    self.driving = was
    if not ok then error(err, 0) end
end

--- A tab's name, changed after the strip was built (Training's count).
function Gear:SetTabText(key, text)
    for _, button in ipairs(self.strip and self.strip.tabs or {}) do
        if button.key == key and button.label then button.label:SetText(text) end
    end
end

--- Open the window on a tab (My Gear when none is named), in the one
--- window when "One Window:" is ticked, else in its own frame.
function Gear:Open(key)
    key = Gear.TabFor(key or "gear")
    self:Build()
    if not Shown(self.frame) then
        local One = Gear.One()
        if not self.hostArea and One and One.Hosts and One.Hosts("equipment") then
            self.wanted = key
            local ok, opened = pcall(One.Open, "equipment")
            self.wanted = nil
            if ok and opened and Shown(self.frame) then return end
        end
        self:RestorePosition()
        self:Grow()
        self.frame:Show()
        if not self.hostArea then
            Motion:Open(self.frame)
            if ns.Titanforged then ns.Titanforged:Opened(self.frame) end
        end
    end
    -- Asked for again while folded: open it full.
    if ns.FoldWindow and not self.hostArea then ns.FoldWindow:Unfold(self.frame) end
    self:ShowTab(key)
end

--- Close the window: the one window while this frame is in it.
function Gear:Close()
    if self.hostArea then
        local One = Gear.One()
        if One and One.Close then pcall(One.Close) end
        return
    end
    if self.frame then self.frame:Hide() end
    self:Closed()
end

--- The frame is hidden: its pages go too, so nothing of theirs runs.
function Gear:Closed()
    if self.closing then return end
    self.closing = true
    self:HidePages()
    self.closing = false
end

function Gear:Toggle()
    if self:IsShown() then self:Close() else self:Open() end
end

--- Redraw the page showing.
function Gear:Refresh()
    if not self:IsShown() then return end
    local module = self.tab and self.pages[self.tab]
    if module and module.Refresh then module:Refresh() end
end

--------------------------------------------------------------------------------
-- The one window
--------------------------------------------------------------------------------

-- What the frame wears in its own place, put away inside the one window.
local function Bare(frame, bare)
    local trim = rawget(frame, "titan")
    if trim and trim.SetShown then trim:SetShown(not bare) end
    local grip = rawget(Gear, "sizeGrip")
    if grip and grip.SetShown then grip:SetShown(not bare) end
end

--- The one window lays this frame in (host.enter).
function Gear:Enter(area)
    if not area then return end
    self:Build()
    local frame = self.frame
    self.hostArea = area
    if frame:GetParent() ~= area then frame:SetParent(area) end
    frame:ClearAllPoints()
    frame:SetAllPoints(area)
    frame:SetScale(1)
    Bare(frame, true)
    self:Lay()
    self:Grow()
    frame:Show()
    local key = self.wanted or self.tab or "gear"
    self.wanted = nil
    self:ShowTab(key)
end

--- The one window lets it go (host.leave): hidden, back in its own place.
function Gear:Leave()
    local frame = self.frame
    if not (frame and self.hostArea) then return end
    self.closing = true
    pcall(frame.Hide, frame)
    self.closing = false
    self:Closed()
    self.hostArea = nil
    frame:SetParent(UIParent)
    Bare(frame, false)
    self:RestorePosition()
    self:Grow()
    self:Lay()
    if Widgets.ApplySize and ns.db then Widgets.ApplySize(frame, ns.db.finderScale) end
end

--- What Equipment gives the one window when it joins (UI/Minimap.lua).
Gear.host = {
    enter = function(area) Gear:Enter(area) end,
    leave = function() Gear:Leave() end,
    -- For the swap gem (SharedWindow.AddSwap): the tab up now, open on a
    -- tab wherever Equipment now belongs, and close its own window.
    tab = function() return Gear:IsShown() and Gear.tab or nil end,
    show = function(key) Gear:Open(key) end,
    hide = function()
        if not Gear.hostArea and Gear:IsShown() then Gear:Close() end
    end,
}

-- Kept folded through a /reload, its round button opens it (UI/FoldWindow.lua).
if ns.FoldWindow and ns.FoldWindow.Opener then
    ns.FoldWindow:Opener("Gear", { open = function() Gear:Open() end })
end
