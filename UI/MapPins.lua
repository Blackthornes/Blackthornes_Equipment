-- Blackthornes Equipment -- UI/MapPins.lua
-- Pins on the world map where each tracked upgrade comes from: the vendor,
-- the quest giver, or the trainer who teaches a crafted piece.
--
-- A pin is the item's own icon in a gold ring with a soft glow, the size of
-- the game's own pins at any zoom. Hover one for the item and where it is;
-- click it to put the game's map pin there. Only hunts with an exact spot
-- get one, and only on the map of their zone. Drawn as plain frames on the
-- map's canvas, the way Farmer draws its gathering markers, and every map
-- call is in a pcall: a map this cannot read simply shows no pins. Switched
-- off with the "Map pins" setting (`mapPins`).

local _, ns = ...

local MapPins = ns.NewModule("MapPins")

local Theme = ns.Theme

local SIZE = 22
local STEP = 0.2
local ROUND = [[Interface\CharacterFrame\TempPortraitAlphaMask]]

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
        GameTooltip:AddLine("Tracked upgrade", Theme.Unpack("accent"))
        if hunt.place.text then GameTooltip:AddLine(hunt.place.text, Theme.Unpack("text")) end
        GameTooltip:AddLine("Click to pin it on your map", Theme.Unpack("muted"))
        GameTooltip:Show()
    end)
    pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pin:SetScript("OnClick", function(self)
        if self.hunt and ns.Waypoints then ns.Waypoints:Pin(self.hunt.place) end
    end)
    return pin
end

function MapPins:Draw()
    local view = self:IsEnabled() and self:View() or nil
    local hunts = view and self:HuntsOn(view.name) or {}

    local key = view and ("%d:%s:%s:%s:%d"):format(view.mapID, view.scale, view.width, view.height,
        self.version or 0) or "none"
    if key == self.key then return end
    self.key = key

    self.pins = self.pins or {}
    for _, pin in ipairs(self.pins) do pin:Hide() end
    if not view or #hunts == 0 then return end

    local okLevel, level = pcall(view.canvas.GetFrameLevel, view.canvas)
    level = (okLevel and Number(level) or 1) + 20
    local scale = 1 / view.scale

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

function MapPins:OnTrackingChanged()
    self.version = (self.version or 0) + 1
    self.key = nil
end

function MapPins:Step(elapsed)
    self.since = (self.since or 0) + (elapsed or 0)
    if self.since < STEP then return end
    self.since = 0
    local ok, err = pcall(self.Draw, self)
    if not ok then ns.Debug("map pins:", tostring(err)) end
end

function MapPins:OnEnable()
    local driver = CreateFrame("Frame", nil, UIParent)
    driver:SetScript("OnUpdate", function(_, elapsed) MapPins:Step(elapsed) end)
    driver:Show()
    self.driver = driver
end
