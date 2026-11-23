-- Blackthornes Equipment -- UI/GearWindow.lua
-- The Equipment window (rework step 2, the owner approved the mockups,
-- 2026-11-22): one frame with a tab bar along its top and one page under
-- it. My Gear (UI/MyGear.lua) is the page it opens on.
--
-- The tabs not rebuilt yet (Upgrades, Enchants, Dungeon Quests, Dungeon
-- Loot, Settings) still show their old windows, laid into this window's
-- page area bare of their own rim, gems, grip and hanging tabs: the same
-- way they sat in the one Blackthornes window before
-- (UI/FinderWindow.lua, FinderUI:LayIn). Each later step of the rework
-- swaps one of them for a page built here, and its old window goes.
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
-- `old` names a tab whose page is still its old window.
local TABS = {
    { key = "gear", text = L["My Gear"] },
    { key = "upgrades", text = L["Upgrades"], old = true },
    { key = "enchant", text = L["Enchants"], old = true },
    { key = "dungeons", text = L["Dungeon Quests"], old = true },
    { key = "loot", text = L["Dungeon Loot"], old = true },
    { key = "settings", text = L["Settings"], old = true, right = true },
}
Gear.TABS = TABS

local OLD = {}
for _, tab in ipairs(TABS) do OLD[tab.key] = tab.old or false end

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
    return ns.FinderUI and ns.FinderUI.One() or nil
end

--- A page built here joins under its tab's key.
function Gear:AddPage(key, module)
    self.pages[key] = module
    if self.frame and module.Build then module:Build(self.area) end
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

--- The room a page needs: what the old tabs share, so the window never
--- jumps as the tabs are clicked.
function Gear:PageSize()
    local FinderUI = ns.FinderUI
    if FinderUI and FinderUI.TabSize then return FinderUI:TabSize() end
    return 1040, 668
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

    -- The old tabs' windows live in the page area from here on.
    local FinderUI = ns.FinderUI
    if FinderUI then
        FinderUI.oneArea = area
        for _, each in ipairs(FinderUI:TabFrames()) do FinderUI:LayIn(each) end
    end
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

--- The old windows of the tabs, each hidden; their hiding closes nothing.
function Gear:HideOld()
    local FinderUI = ns.FinderUI
    if not FinderUI then return end
    local was = FinderUI.switching
    FinderUI.switching = true
    for _, each in ipairs(FinderUI:TabFrames()) do
        if Shown(each) then pcall(each.Hide, each) end
    end
    FinderUI.switching = was
end

function Gear:HidePages(except)
    for key, module in pairs(self.pages) do
        if key ~= except and module.Hide then module:Hide() end
    end
end

--- Show a tab's page. An old tab shows its old window in the page area.
function Gear:ShowTab(key)
    if not self.frame then return end
    if OLD[key] == nil then key = "gear" end
    self.tab = key
    if self.strip then self.strip:Select(key) end
    if OLD[key] then
        self:HidePages()
        local FinderUI = ns.FinderUI
        if not FinderUI then return end
        local was = self.driving
        self.driving = true
        local ok, err = pcall(FinderUI.ShowTab, FinderUI, key)
        self.driving = was
        if not ok then error(err, 0) end
        return
    end
    self:HideOld()
    self:HidePages(key)
    local module = self.pages[key]
    if module and module.Show then module:Show() end
end

--- Open the window on a tab (My Gear when none is named), in the one
--- window when "One Window:" is ticked, else in its own frame.
function Gear:Open(key)
    key = key or "gear"
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
    self:HideOld()
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
