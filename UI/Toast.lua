-- Blackthornes Equipment -- UI/Toast.lua
-- A banner near the top of the screen when something worth a cheer happens:
-- an upgrade lands in the bags, a tracked upgrade is got, a hunt is done.
--
-- House style: the dark shell with the gold halo, the item's icon in its
-- quality colour, a title in gold and the item below. It drops in, glows,
-- waits, and fades. Click it to open the upgrade finder; the X closes it.
-- An upgrade in the bags gets a Put it on button (Logic/Wear.lua). A banner
-- can carry its own buttons instead (`actions`, up to two, each { text, fn }),
-- in a row along its foot: an untrained weapon's Show the trainer and Ignore.
-- Several at once wait their turn. Switched off with the "Upgrade banner"
-- setting (`upgradeToast`); the chat line has its own switch.

local _, ns = ...
local L = ns.L

local Toast = ns.NewModule("Toast")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Motion = ns.Motion

local WIDTH = 330
local HEIGHT = 64
local ICON = 40
local SHOWN_FOR = 6
local QUEUE_MOST = 4
local ACTIONS_MOST = 2
-- The row of a banner's own buttons adds this much height.
local ACTION_ROW = 24

function Toast:IsEnabled()
    return not (ns.db and ns.db.upgradeToast == false)
end

function Toast:Build()
    if self.frame then return self.frame end

    local frame = CreateFrame("Button", "BlackthornesEquipmentToast", UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -150)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    Theme.Window(frame)
    Theme.AccentStripe(frame, 3)

    local icon = Theme.CreateItemIcon(frame, ICON)
    icon:SetPoint("LEFT", 12, 0)
    self.icon = icon

    local title = Theme.CreateLabel(frame, "small", "accent")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -1)
    title:SetWidth(WIDTH - ICON - 60)
    self.title = title

    local item = Theme.CreateLabel(frame, "normal", "text")
    item:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    item:SetWidth(WIDTH - ICON - 40)
    self.item = item

    local text = Theme.CreateLabel(frame, "tiny", "muted")
    text:SetPoint("TOPLEFT", item, "BOTTOMLEFT", 0, -3)
    text:SetWidth(WIDTH - ICON - 40)
    self.text = text

    local close = Widgets.CreateButton(frame, "X", function() Toast:Dismiss() end,
        { width = 18, height = 16, danger = true })
    close:SetPoint("TOPRIGHT", -6, -6)

    -- An upgrade in the bags can be put on from here, out of combat.
    local wear = Widgets.CreateButton(frame, L["Put it on"], function()
        local link = rawget(Toast, "link")
        if link and ns.Wear:PutOn(link) then Toast:Dismiss() end
    end, { width = 76, height = 18, primary = true })
    wear:SetPoint("BOTTOMRIGHT", -6, 6)
    wear:Hide()
    self.wear = wear

    -- A banner's own buttons, right to left along its foot.
    self.actions = {}
    for index = 1, ACTIONS_MOST do
        local button = Widgets.CreateButton(frame, "", function(button)
            local fn = button.fn
            Toast:Dismiss()
            if type(fn) == "function" then pcall(fn) end
        end, { width = 60, height = 18, primary = index == 1 })
        if index == 1 then
            button:SetPoint("BOTTOMRIGHT", -6, 6)
        else
            button:SetPoint("RIGHT", self.actions[index - 1], "LEFT", -6, 0)
        end
        button:Hide()
        self.actions[index] = button
    end

    frame:SetScript("OnClick", function()
        if ns.FinderUI then ns.FinderUI:Show() end
        Toast:Dismiss()
    end)
    frame:SetScript("OnEnter", function(self)
        Toast.hovered = true
        local link = rawget(Toast, "link")
        if link and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            pcall(GameTooltip.SetHyperlink, GameTooltip, link)
            GameTooltip:AddLine(L["Click to open Where to get upgrades"], Theme.Unpack("muted"))
            GameTooltip:Show()
        end
    end)
    frame:SetScript("OnLeave", function()
        Toast.hovered = false
        if GameTooltip then GameTooltip:Hide() end
    end)

    frame:Hide()
    self.frame = frame
    return frame
end

--- Show a banner: { title, link, text }. Waits behind one already showing.
function Toast:Show(banner)
    if not self:IsEnabled() or type(banner) ~= "table" then return false end
    self.queue = self.queue or {}
    if self.frame and self.frame:IsShown() then
        if #self.queue < QUEUE_MOST then self.queue[#self.queue + 1] = banner end
        return true
    end
    self:Present(banner)
    return true
end

function Toast:Present(banner)
    self:Build()
    self.link = banner.link
    -- The mouse left with the last banner, even if the client said nothing.
    self.hovered = false
    self.title:SetText(banner.title or "")
    self.item:SetText(ns.Items.ShowLink(banner.link) or "")
    self.text:SetText(banner.text or "")
    Theme.SetItemIcon(self.icon, banner.link)
    local actions = type(banner.actions) == "table" and banner.actions or {}
    local wears = #actions == 0 and banner.wear == true and banner.link ~= nil and ns.Wear ~= nil
        and (ns.Wear:Can(banner.link)) == true
    self.wear:SetShown(wears)
    for index, button in ipairs(self.actions) do
        local action = actions[index]
        if type(action) == "table" and action.text then
            button:SetText(action.text)
            button.fn = action.fn
            button:Show()
        else
            button.fn = nil
            button:Hide()
        end
    end
    -- The last line stops short of Put it on; a row of buttons sits below.
    self.text:SetWidth(WIDTH - ICON - 40 - (wears and 84 or 0))
    self.frame:SetHeight(HEIGHT + (#actions > 0 and ACTION_ROW or 0))
    -- A long weapon name ("Ignore Two-Handed Swords") widens the banner
    -- rather than squeezing a label.
    local row = 12
    for _, button in ipairs(self.actions) do
        if button:IsShown() then row = row + (tonumber(button:GetWidth()) or 0) + 6 end
    end
    self.frame:SetWidth(math.max(WIDTH, row))

    self.frame:SetAlpha(1)
    self.frame:Show()
    -- Drops in from a little above, its gold edge flaring as it lands.
    Motion:Open(self.frame, -12)
    if type(_G.PlaySound) == "function" then
        local kit = _G.SOUNDKIT and _G.SOUNDKIT.UI_EPICLOOT_TOAST
        pcall(_G.PlaySound, kit or 31578, "Master")
    end

    self.shownAt = 0
    if not self.ticker then
        self.ticker = CreateFrame("Frame", nil, self.frame)
        self.ticker:SetScript("OnUpdate", function(_, elapsed) Toast:Step(elapsed) end)
    end
end

--- Count down, but not while the mouse is on it; then fade.
function Toast:Step(elapsed)
    if not (self.frame and self.frame:IsShown()) or self.hovered then return end
    self.shownAt = (self.shownAt or 0) + (elapsed or 0)
    if self.shownAt >= SHOWN_FOR and not self.fading then
        self.fading = true
        Motion:Run(self.frame, "fade", 0.4, function(p) self.frame:SetAlpha(1 - p) end,
            { done = function() Toast:Dismiss() end })
    end
end

--- Close the banner, and show the next one waiting.
function Toast:Dismiss()
    -- A fade still running would dim, then close, the next banner.
    Motion:Stop(self.frame, "fade")
    self.fading = false
    if self.frame then self.frame:Hide() end
    local queue = self.queue or {}
    local nextBanner = table.remove(queue, 1)
    if nextBanner then self:Present(nextBanner) end
end
