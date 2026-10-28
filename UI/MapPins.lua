-- Blackthornes Equipment -- UI/MapPins.lua
-- Pins on the world map where each tracked upgrade comes from: the vendor,
-- the quest giver, or the trainer who teaches a crafted piece. The upgrade
-- quest's next place to go gets one too.
--
-- A pin is the item's own icon in a gold ring with a soft glow, the size of
-- the game's own pins at any zoom. Hover one for the item and where it is;
-- click it to put the game's map pin there. Only hunts with an exact spot
-- get one, and only on the map of their zone. Drawn as plain frames on the
-- map's canvas, the way Farmer draws its gathering markers, and every map
-- call is in a pcall: a map this cannot read simply shows no pins. Switched
-- off with the "Map pins" setting (`mapPins`).
--
-- Show on Map also lays a bigger marker on the spot (a player found the
-- game's own pin hard to see, 2026-10-28): the upgrade's icon in a wide gold
-- ring with two waves going out for a few seconds, then a slow glow, the
-- place's name under it. Effects Subtle keeps a still glow, Off holds still.
-- It goes when the game's pin is taken off or another place is shown.

local _, ns = ...
local L = ns.L

local MapPins = ns.NewModule("MapPins")

local Theme = ns.Theme

local SIZE = 22
local STEP = 0.2
local ROUND = [[Interface\CharacterFrame\TempPortraitAlphaMask]]

MapPins.SPOT_SIZE = 34
MapPins.WAVE_FOR = 4       -- seconds the waves run after a Show on Map
MapPins.WAVE_TIME = 1.6    -- seconds one wave takes to go out
MapPins.WAVE_GROW = 2.6    -- how far a wave grows, times the ring
MapPins.SPOT_ICON = [[Interface\Icons\INV_Misc_Map_01]]

function MapPins:IsEnabled()
    return not (ns.db and ns.db.mapPins == false)
end

local function Number(value)
    local ok, copy = pcall(function() return tonumber(value) end)
    return ok and copy or nil
end

--- What the world map is showing: { canvas, mapID, name, scale, width,
--- height }, or nil when it is shut or cannot be read.
function MapPins:View()
    local map = _G.WorldMapFrame
    if type(map) ~= "table" then return nil end
    local okShown, shown = pcall(map.IsShown, map)
    if not (okShown and shown) then return nil end

    local canvas
    if type(map.GetCanvas) == "function" then
        local ok, value = pcall(map.GetCanvas, map)
        if ok then canvas = value end
    end
    canvas = canvas or (map.ScrollContainer and map.ScrollContainer.Child)
    if type(canvas) ~= "table" then return nil end

    local mapID
    if type(map.GetMapID) == "function" then
        local ok, value = pcall(map.GetMapID, map)
        if ok then mapID = Number(value) end
    end
    if not mapID then return nil end

    local name
    local info = _G.C_Map and _G.C_Map.GetMapInfo
    if type(info) == "function" then
        local ok, value = pcall(function()
            local data = info(mapID)
            if type(data) == "table" and type(data.name) == "string" then return data.name .. "" end
        end)
        if ok then name = value end
    end

    local scale = 1
    local scroll = map.ScrollContainer
    if type(scroll) == "table" and type(scroll.GetCanvasScale) == "function" then
        local ok, value = pcall(scroll.GetCanvasScale, scroll)
        scale = ok and Number(value) or 1
    end
    if not scale or scale <= 0 then scale = 1 end

    local okW, width = pcall(canvas.GetWidth, canvas)
    local okH, height = pcall(canvas.GetHeight, canvas)
    width, height = okW and Number(width), okH and Number(height)
    if not (width and height and width > 0 and height > 0) then return nil end

    return { canvas = canvas, mapID = mapID, name = name, scale = scale, width = width, height = height }
end

--- The hunts with an exact spot on the map named `zone`.
function MapPins:HuntsOn(zone)
    local list = {}
    if not (zone and ns.Tracking) then return list end
    for _, hunt in ipairs(ns.Tracking:List()) do
        local place = hunt.place
        if place and place.zone == zone and place.x and place.y and not hunt.got then
            list[#list + 1] = hunt
        end
    end
    -- The upgrade quest's next place to go, when it has an exact spot.
    local quest = ns.UpgradeQuest and ns.UpgradeQuest:IsEnabled() and ns.UpgradeQuest:Current()
    local spot = quest and ns.UpgradeQuest:NextPlace()
    if spot and spot.zone == zone and spot.x and spot.y then
        list[#list + 1] = {
            link = quest.link, quest = true,
            place = { zone = spot.zone, x = spot.x, y = spot.y, name = spot.name,
                text = spot.name and L.Format("Upgrade quest: go to %s", spot.name) or L["Upgrade quest"] },
        }
    end
    return list
end

function MapPins:MakePin(canvas)
    local pin = CreateFrame("Button", nil, canvas)
    pin:SetSize(SIZE, SIZE)

    local glow = pin:CreateTexture(nil, "BACKGROUND")
    glow:SetPoint("CENTER")
    glow:SetSize(SIZE + 14, SIZE + 14)
    glow:SetTexture(ROUND)
    glow:SetVertexColor(Theme.Unpack("good"))
    glow:SetAlpha(0.45)
    pcall(glow.SetBlendMode, glow, "ADD")

    local ring = pin:CreateTexture(nil, "BORDER")
    ring:SetPoint("CENTER")
    ring:SetSize(SIZE, SIZE)
    ring:SetTexture(ROUND)
    ring:SetVertexColor(Theme.Unpack("accent"))

    local icon = pin:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("CENTER")
    icon:SetSize(SIZE - 5, SIZE - 5)
    pcall(icon.SetMask, icon, ROUND)
    pin.icon = icon

    pin:SetScript("OnEnter", function(self)
        local hunt = self.hunt
        if not hunt then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        pcall(GameTooltip.SetHyperlink, GameTooltip, hunt.link)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(hunt.quest and L["Upgrade quest"] or L["Tracked upgrade"], Theme.Unpack("accent"))
        if hunt.place.text then GameTooltip:AddLine(ns.Tracking.PlaceText(hunt.place), Theme.Unpack("text")) end
        GameTooltip:AddLine(L["Click to pin it on your map"], Theme.Unpack("muted"))
        GameTooltip:Show()
    end)
    pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pin:SetScript("OnClick", function(self)
        if self.hunt and ns.Waypoints then ns.Waypoints:Pin(self.hunt.place) end
    end)
    return pin
end

--- Lay the big marker on `place` ({ zone, x, y }), showing `icon` and the
--- name `name` under it. Called by Waypoints:Show once the game's pin is set.
function MapPins:Spotlight(place, icon, name)
    if not (type(place) == "table" and place.zone and place.x and place.y) then
        self.spotlight = nil
    else
        local shown = name or place.name
        if not shown and ns.Waypoints and ns.Waypoints.ShowZone then shown = ns.Waypoints.ShowZone(place.zone) end
        local now = type(_G.GetTime) == "function" and _G.GetTime() or 0
        self.spotlight = { place = place, icon = icon or self.SPOT_ICON, name = shown, at = now }
    end
    self:OnTrackingChanged()
end

--- The marker's look `age` seconds after it was laid, by the effects level:
--- { glow, waves = { { size, alpha }, ... } }. Waves only on Full, for
--- WAVE_FOR seconds; then the glow breathes. Subtle keeps a still glow.
function MapPins.SpotLook(age, level)
    local look = { glow = 0.5, waves = {} }
    if level == "off" then return look end
    if level ~= "full" then
        look.glow = 0.55
        return look
    end
    age = math.max(0, age or 0)
    if age < MapPins.WAVE_FOR then
        look.glow = 0.7
        for wave = 0, 1 do
            local start = wave * MapPins.WAVE_TIME / 2
            if age >= start then
                local t = ((age - start) % MapPins.WAVE_TIME) / MapPins.WAVE_TIME
                look.waves[#look.waves + 1] = {
                    size = MapPins.SPOT_SIZE * (1 + (MapPins.WAVE_GROW - 1) * t),
                    alpha = 0.7 * (1 - t),
                }
            end
        end
    else
        look.glow = 0.45 + 0.25 * math.sin((age - MapPins.WAVE_FOR) * 2.4)
    end
    return look
end

function MapPins:MakeSpot(canvas)
    local size = self.SPOT_SIZE
    local spot = CreateFrame("Frame", nil, canvas)
    spot:SetSize(size, size)
    pcall(spot.EnableMouse, spot, false)

    local glow = spot:CreateTexture(nil, "BACKGROUND")
    glow:SetPoint("CENTER")
    glow:SetSize(size + 26, size + 26)
    glow:SetTexture(ROUND)
    glow:SetVertexColor(Theme.Unpack("accent"))
    pcall(glow.SetBlendMode, glow, "ADD")
    spot.glow = glow

    spot.waves = {}
    for index = 1, 2 do
        local wave = spot:CreateTexture(nil, "BACKGROUND", nil, 1)
        wave:SetPoint("CENTER")
        wave:SetSize(size, size)
        wave:SetTexture(ROUND)
        wave:SetVertexColor(Theme.Unpack("accent"))
        pcall(wave.SetBlendMode, wave, "ADD")
        wave:Hide()
        spot.waves[index] = wave
    end

    local ring = spot:CreateTexture(nil, "BORDER")
    ring:SetPoint("CENTER")
    ring:SetSize(size, size)
    ring:SetTexture(ROUND)
    ring:SetVertexColor(Theme.Unpack("accent"))

    local icon = spot:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("CENTER")
    icon:SetSize(size - 6, size - 6)
    pcall(icon.SetMask, icon, ROUND)
    spot.icon = icon

    local label = Theme.CreateLabel(spot, "normal", "accent", "CENTER")
    label:SetPoint("TOP", spot, "BOTTOM", 0, -3)
    pcall(label.SetShadowOffset, label, 1, -1)
    pcall(label.SetShadowColor, label, 0, 0, 0, 1)
    spot.label = label

    spot:SetScript("OnUpdate", function(frame) MapPins:Animate(frame) end)
    return spot
end

--- One frame of the marker's motion; runs only while it shows.
function MapPins:Animate(spot)
    local light = self.spotlight
    if not light then return end
    local level = ns.Motion and ns.Motion.Level and ns.Motion.Level() or "full"
    local now = type(_G.GetTime) == "function" and _G.GetTime() or 0
    local look = MapPins.SpotLook(now - (light.at or now), level)
    spot.glow:SetAlpha(look.glow)
    for index, wave in ipairs(spot.waves) do
        local shape = look.waves[index]
        if shape then
            wave:SetSize(shape.size, shape.size)
            wave:SetAlpha(shape.alpha)
            wave:Show()
        else
            wave:Hide()
        end
    end
end

--- Whether the game's own pin is still on the map. A client that won't say
--- keeps the marker.
function MapPins.PinStillSet()
    local map = _G.C_Map
    if type(map) ~= "table" or type(map.HasUserWaypoint) ~= "function" then return true end
    local ok, has = pcall(map.HasUserWaypoint)
    if not ok then return true end
    return has == true
end

function MapPins:DrawSpot(view, zone, level, scale)
    local light = self.spotlight
    local place = light and light.place
    if not (view and place and place.zone == zone) then
        if self.spot then self.spot:Hide() end
        return
    end
    local spot = self.spot
    if not spot or spot.canvas ~= view.canvas then
        if spot then spot:Hide() end
        spot = self:MakeSpot(view.canvas)
        spot.canvas = view.canvas
        self.spot = spot
    end
    spot.icon:SetTexture(light.icon or self.SPOT_ICON)
    spot.label:SetText(light.name or "")
    spot:SetScale(scale)
    spot:SetFrameLevel(level + 2)
    spot:ClearAllPoints()
    spot:SetPoint("CENTER", view.canvas, "TOPLEFT",
        place.x / 100 * view.width / scale, -place.y / 100 * view.height / scale)
    self:Animate(spot)
    spot:Show()
end

function MapPins:Draw()
    -- The big marker answers a click, so it shows with "Map pins" off too.
    local enabled = self:IsEnabled()
    local view = (enabled or self.spotlight) and self:View() or nil

    local key = view and ("%d:%s:%s:%s:%d:%s"):format(view.mapID, view.scale, view.width, view.height,
        self.version or 0, tostring(enabled)) or "none"
    if key == self.key then return end
    self.key = key

    -- The hunts are only gathered again for a new map or a change to them:
    -- the upgrade quest's next place reads the quest log and bags, and a
    -- zoom changes the scale five times a second while the map is open, so
    -- a zoom only re-places the pins it has.
    local huntsKey = view and ("%d:%s:%d:%s"):format(view.mapID, tostring(view.name), self.version or 0,
        tostring(enabled)) or "none"
    if huntsKey ~= self.huntsKey or not self.hunts then
        self.huntsKey = huntsKey
        self.zone = view and (ns.Waypoints and ns.Waypoints:DataZone(view.name, view.mapID) or view.name)
        self.hunts = view and enabled and self:HuntsOn(self.zone) or {}
    end
    local hunts = self.hunts

    self.pins = self.pins or {}
    for _, pin in ipairs(self.pins) do pin:Hide() end
    if not view then
        if self.spot then self.spot:Hide() end
        return
    end

    local okLevel, level = pcall(view.canvas.GetFrameLevel, view.canvas)
    level = (okLevel and Number(level) or 1) + 20
    local scale = 1 / view.scale
    self:DrawSpot(view, self.zone, level, scale)
    if #hunts == 0 then return end

    for index, hunt in ipairs(hunts) do
        local pin = self.pins[index]
        if not pin or pin.canvas ~= view.canvas then
            pin = self:MakePin(view.canvas)
            pin.canvas = view.canvas
            self.pins[index] = pin
        end
        pin.hunt = hunt
        pin.icon:SetTexture(Theme.ItemIcon(hunt.link) or [[Interface\Icons\INV_Misc_QuestionMark]])
        pin:SetScale(scale)
        pin:SetFrameLevel(level)
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", view.canvas, "TOPLEFT",
            hunt.place.x / 100 * view.width / scale, -hunt.place.y / 100 * view.height / scale)
        pin:Show()
    end
end

function MapPins:OnUpgradeQuestChanged()
    self:OnTrackingChanged()
end

function MapPins:OnTrackingChanged()
    self.version = (self.version or 0) + 1
    self.key = nil
end

function MapPins:Step(elapsed)
    self.since = (self.since or 0) + (elapsed or 0)
    if self.since < STEP then return end
    self.since = 0
    -- The marker goes with the game's pin: taken off on the map, or reached.
    if self.spotlight and not MapPins.PinStillSet() then self:Spotlight(nil) end
    local ok, err = pcall(self.Draw, self)
    if not ok then ns.Debug("map pins:", tostring(err)) end
end

function MapPins:OnEnable()
    local driver = CreateFrame("Frame", nil, UIParent)
    driver:SetScript("OnUpdate", function(_, elapsed) MapPins:Step(elapsed) end)
    driver:Show()
    self.driver = driver
end
