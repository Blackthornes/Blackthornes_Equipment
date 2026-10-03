-- Blackthornes Equipment -- Logic/Waypoints.lua
-- "Show on map": the game's own map pin on where an upgrade comes from.
--
-- The finder's places are a zone name and a spot on that zone's map (from
-- Classic data). The map ID for the zone is found from the client's own map
-- list rather than a table typed here, so a map Forever numbers differently
-- still works: from the map the character is on, up to the top, then down
-- through every zone under it until one carries the name.
--
-- The pin itself is the game's: C_Map.SetUserWaypoint, then tracked so the
-- game draws its arrow to it. Every call is inside a pcall; a client without
-- them simply cannot pin, and the finder says so.

local _, ns = ...

local Waypoints = ns.NewModule("Waypoints")

local function Read(fn, ...)
    if type(fn) ~= "function" then return nil end
    local result = { pcall(fn, ...) }
    if not result[1] then return nil end
    return unpack(result, 2)
end

local function Plain(value)
    local ok, copy = pcall(function()
        if type(value) == "string" and value ~= "" then return value .. "" end
    end)
    return ok and copy or nil
end

local function Number(value)
    local ok, copy = pcall(function() return tonumber(value) end)
    return ok and copy or nil
end

local function Map() return type(_G.C_Map) == "table" and _G.C_Map or nil end

--- Can this client put a pin on the map at all?
function Waypoints:CanPin()
    local map = Map()
    return map ~= nil and type(map.SetUserWaypoint) == "function"
        and type(_G.UiMapPoint) == "table" and type(_G.UiMapPoint.CreateFromCoordinates) == "function"
end

--- A map's name and parent.
local function Info(mapID)
    local map = Map()
    local info = map and Read(map.GetMapInfo, mapID)
    if type(info) ~= "table" then return nil end
    local ok, name, parent = pcall(function() return info.name, info.parentMapID end)
    if not ok then return nil end
    return Plain(name), Number(parent)
end

--- The highest map above the one the character is on.
local function TopMap()
    local map = Map()
    local here = map and Number(Read(map.GetBestMapForUnit, "player"))
    if not here then return nil end
    local top = here
    for _ = 1, 10 do
        local _, parent = Info(top)
        if not parent or parent <= 0 then break end
        top = parent
    end
    return top
end

--- The map ID of a zone, by its name, or nil. Kept once found.
function Waypoints:MapFor(zone)
    if type(zone) ~= "string" or zone == "" then return nil end
    self.found = self.found or {}
    if self.found[zone] ~= nil then return self.found[zone] or nil end

    local map = Map()
    local top = TopMap()
    local mapID
    if map and top then
        local name = Info(top)
        if name == zone then mapID = top end
        -- Every map under the top one, zones and continents alike.
        local children = not mapID and Read(map.GetMapChildrenInfo, top, nil, true)
        if type(children) == "table" then
            for _, child in ipairs(children) do
                local ok, childName, childID = pcall(function() return child.name, child.mapID end)
                if ok and Plain(childName) == zone and Number(childID) then
                    mapID = Number(childID)
                    break
                end
            end
        end
    end

    self.found[zone] = mapID or false
    return mapID
end

--- Put the map pin on a place { zone, x, y } (x and y 0-100 on the zone's
--- map) and point the game's arrow at it.
-- @return true, or false and why ("nospot", "noclient", "nomap")
function Waypoints:Pin(place)
    if not (place and place.zone and place.x and place.y) then return false, "nospot" end
    if not self:CanPin() then return false, "noclient" end
    local mapID = self:MapFor(place.zone)
    if not mapID then return false, "nomap" end

    local ok = pcall(function()
        local point = _G.UiMapPoint.CreateFromCoordinates(mapID, place.x / 100, place.y / 100)
        _G.C_Map.SetUserWaypoint(point)
        local super = _G.C_SuperTrack
        if type(super) == "table" and type(super.SetSuperTrackedUserWaypoint) == "function" then
            super.SetSuperTrackedUserWaypoint(true)
        end
    end)
    if not ok then return false, "noclient" end
    return true
end

local WHY = {
    nospot = "no exact spot is known for that one",
    noclient = "this client cannot put a pin on the map",
    nomap = "the map for that zone could not be found",
}

--- Pin a place and say so in chat. `what` names it ("Corina Steele").
function Waypoints:Show(place, what)
    local ok, why = self:Pin(place)
    if ok then
        ns.Print(("pinned %s on your map: %s (%s, %s)"):format(what or place.name or "it",
            place.zone, place.x, place.y))
        -- Open the map on it, where the game lets an addon.
        local mapID = self:MapFor(place.zone)
        if type(_G.OpenWorldMap) == "function" then pcall(_G.OpenWorldMap, mapID) end
    else
        local where = place and place.zone and (" (" .. place.zone .. ")") or ""
        ns.Print(("can't pin %s%s: %s"):format(what or "that", where, WHY[why] or why))
    end
    return ok
end
