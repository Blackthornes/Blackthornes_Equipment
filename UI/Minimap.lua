-- Blackthornes Equipment -- UI/Minimap.lua
-- The minimap button.
--
-- Ported from Farmer, which ported it from Tradeskills, so the three behave
-- the same: drag it round the ring, click it to open, right-click for
-- settings. The orbit radius comes from the minimap's real size rather than
-- an assumed one, because a fixed radius only clears the ring on a default
-- 140px minimap.
--
-- A left-click opens the gear window, a right-click the settings. The
-- tooltip says which spec gear is being judged for.

local _, ns = ...

local MinimapButton = ns.NewModule("MinimapButton")

local Theme = ns.Theme

-- A little further round than Farmer's and Tradeskills' 200 degrees, so the
-- three buttons do not start stacked on one another.
local DEFAULT_ANGLE = math.rad(230)
local ICON = [[Interface\Icons\INV_Chest_Chain]]

--- What a left-click does: the main window once there is one, the settings
--- page until then.
function MinimapButton:Open()
    if ns.UI and ns.UI.Toggle then
        ns.UI:Toggle()
    elseif ns.SettingsUI then
        ns.SettingsUI:Toggle()
    end
end

--- The tooltip's line about the spec, or nil for a class with no weights.
function MinimapButton:SpecLine()
    local Weights = ns.Weights
    if not Weights then return nil end

    local ok, spec, _, class = pcall(Weights.CurrentSpec, Weights)
    if not ok then return nil end
    if not spec then
        return ("No stat weights for %s yet"):format(class or "this class")
    end
    return "Judging gear as " .. Weights.SPECS[class][spec].name
end

function MinimapButton:Build()
    if self.button or not Minimap then return self.button end

    local button = CreateFrame("Button", "BlackthornesEquipmentMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetPoint("CENTER")
    background:SetColorTexture(Theme.Unpack("window"))

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("CENTER")
    icon:SetTexture(ICON)
    icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture([[Interface\Minimap\MiniMap-TrackingBorder]])

    -- The game's own round glow under the mouse, as every minimap button has.
    if button.SetHighlightTexture then
        pcall(button.SetHighlightTexture, button,
            [[Interface\Minimap\UI-Minimap-ZoomButton-Highlight]], "ADD")
    end

    -- The icon swells a little under the mouse and dips when pressed.
    local function IconSize(size)
        icon:SetSize(size, size)
    end
    button:SetScript("OnMouseDown", function() IconSize(16) end)
    button:SetScript("OnMouseUp", function()
        local target = 18 + 2 * ns.Motion:Value(button, "hover")
        ns.Motion:Run(button, "press", 0.2, function(p) IconSize(16 + (target - 16) * p) end,
            { ease = ns.Motion.EaseOutBack })
    end)

    local function GetOrbitRadius()
        local size = Minimap:GetWidth()
        if not size or size <= 0 then size = 140 end

        return (size / 2) + (ns.db and ns.db.minimapGap or 16)
    end

    local function UpdatePosition(angle)
        local radius = GetOrbitRadius()

        button:ClearAllPoints()
        button:SetPoint("CENTER", Minimap, "CENTER",
            math.cos(angle) * radius, math.sin(angle) * radius)
    end

    button.UpdatePosition = UpdatePosition
    UpdatePosition((ns.db and ns.db.minimapAngle) or DEFAULT_ANGLE)

    button:SetMovable(true)
    button:RegisterForDrag("LeftButton")

    button:SetScript("OnDragStart", function(self)
        self.dragging = true
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()

            local newAngle = math.atan2((cy / scale) - my, (cx / scale) - mx)
            UpdatePosition(newAngle)

            if ns.db then ns.db.minimapAngle = newAngle end
        end)
    end)

    button:SetScript("OnDragStop", function(self)
        self.dragging = false
        self:SetScript("OnUpdate", nil)
    end)

    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" and ns.SettingsUI then
            ns.SettingsUI:Toggle()
        else
            MinimapButton:Open()
        end
    end)

    button:SetScript("OnEnter", function(self)
        ns.Motion:Blend(self, "hover", 1, 0.12, function(v) IconSize(18 + 2 * v) end)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Blackthornes Equipment")

        local specLine = MinimapButton:SpecLine()
        if specLine then GameTooltip:AddLine(specLine, 0.78, 0.64, 0.30) end

        if ns.UI and ns.UI.Toggle then
            GameTooltip:AddLine("Click to open", 0.7, 0.7, 0.7)
            GameTooltip:AddLine("Right-click for settings", 0.7, 0.7, 0.7)
        else
            GameTooltip:AddLine("Click for settings", 0.7, 0.7, 0.7)
        end
        GameTooltip:AddLine("Drag to move it round the minimap", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function(self)
        ns.Motion:Blend(self, "hover", 0, 0.18, function(v) IconSize(18 + 2 * v) end)
        GameTooltip:Hide()
    end)

    self.button = button
    self.lastMinimapWidth = Minimap:GetWidth()

    self:ApplyVisibility()
    return button
end

--- Re-seat the button at its stored angle, using the current radius.
function MinimapButton:Reposition()
    local button = self.button
    if not button or not button.UpdatePosition then return end

    button.UpdatePosition((ns.db and ns.db.minimapAngle) or DEFAULT_ANGLE)
    self.lastMinimapWidth = Minimap and Minimap:GetWidth()
end

function MinimapButton:ApplyVisibility()
    local button = self.button
    if not button then return end

    if ns.db and ns.db.minimapHidden then
        button:Hide()
    else
        button:Show()
    end
end

--- Show or hide the button. Returns true when it ends up visible.
function MinimapButton:Toggle()
    if ns.db then
        ns.db.minimapHidden = not ns.db.minimapHidden
    end

    self:ApplyVisibility()
    return not (ns.db and ns.db.minimapHidden)
end

function MinimapButton:OnEnable()
    self:Build()

    -- The minimap's final size is not always settled at login, and other addons
    -- resize it afterwards, so re-seat the button once things have calmed down.
    if C_Timer and C_Timer.After then
        C_Timer.After(1, function() MinimapButton:Reposition() end)
    end

    -- Cheap enough to check, and catches a minimap resized at any point.
    if C_Timer and C_Timer.NewTicker then
        self.ticker = C_Timer.NewTicker(5, function()
            if Minimap and MinimapButton.lastMinimapWidth ~= Minimap:GetWidth() then
                MinimapButton:Reposition()
            end
        end)
    end
end

ns.RegisterCommand("minimap", "show or hide the minimap button", function()
    if MinimapButton:Toggle() then
        ns.Print("minimap button shown.")
    else
        ns.Print("minimap button hidden. /beq minimap brings it back.")
    end
end)
