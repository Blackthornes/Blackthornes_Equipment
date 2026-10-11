-- Blackthornes Equipment -- Logic/Waypoints.lua
-- "Show on map": the game's own map pin on where an upgrade comes from.
--
-- The finder's places are a zone name and a spot on that zone's map (from
-- Classic data). The map ID for the zone is found from the client's own map
-- list rather than a table typed here, so a map Forever numbers differently
-- still works: from the map the character is on, up to the top, then down
-- through every zone under it until one carries the name. A client in
-- another language names its maps in that language, so there Classic's map
-- IDs stand in (Waypoints.ZONE_MAPS, below).
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

--------------------------------------------------------------------------------
-- Zone names on a client in another language
--
-- The data names zones in English ("Elwynn Forest"); a German client names
-- them in German ("Wald von Elwynn"), so a name alone never matches there.
-- These are Classic's map IDs for the zones the data names, the same IDs
-- the tests and Farmer use (Elwynn Forest 1429, Dun Morogh 1426). They are
-- only asked on a client that is not English, and always after the name:
-- an English client works exactly as before, and an ID Forever numbers
-- differently only means the name is used, as it always was.
--------------------------------------------------------------------------------

Waypoints.ZONE_MAPS = {
    ["Durotar"] = 1411, ["Mulgore"] = 1412, ["The Barrens"] = 1413, ["Kalimdor"] = 1414,
    ["Eastern Kingdoms"] = 1415, ["Alterac Mountains"] = 1416, ["Arathi Highlands"] = 1417,
    ["Badlands"] = 1418, ["Blasted Lands"] = 1419, ["Tirisfal Glades"] = 1420,
    ["Silverpine Forest"] = 1421, ["Western Plaguelands"] = 1422, ["Eastern Plaguelands"] = 1423,
    ["Hillsbrad Foothills"] = 1424, ["The Hinterlands"] = 1425, ["Dun Morogh"] = 1426,
    ["Searing Gorge"] = 1427, ["Burning Steppes"] = 1428, ["Elwynn Forest"] = 1429,
    ["Deadwind Pass"] = 1430, ["Duskwood"] = 1431, ["Loch Modan"] = 1432,
    ["Redridge Mountains"] = 1433, ["Stranglethorn Vale"] = 1434, ["Swamp of Sorrows"] = 1435,
    ["Westfall"] = 1436, ["Wetlands"] = 1437, ["Teldrassil"] = 1438, ["Darkshore"] = 1439,
    ["Ashenvale"] = 1440, ["Thousand Needles"] = 1441, ["Stonetalon Mountains"] = 1442,
    ["Desolace"] = 1443, ["Feralas"] = 1444, ["Dustwallow Marsh"] = 1445, ["Tanaris"] = 1446,
    ["Azshara"] = 1447, ["Felwood"] = 1448, ["Un'Goro Crater"] = 1449, ["Moonglade"] = 1450,
    ["Silithus"] = 1451, ["Winterspring"] = 1452, ["Stormwind City"] = 1453,
    ["Orgrimmar"] = 1454, ["Ironforge"] = 1455, ["Thunder Bluff"] = 1456,
    ["Darnassus"] = 1457, ["Undercity"] = 1458, ["Alterac Valley"] = 1459,
}

-- The two continents are never a zone the character is "in".
local CONTINENTS = { [1414] = true, [1415] = true }

--- Is the client English? Nil from GetLocale counts as English, so nothing
--- changes on a client that will not say.
function Waypoints.English()
    local locale = Plain(Read(_G.GetLocale))
    return locale == nil or locale:sub(1, 2) == "en"
end

-- [map ID] = the data's name, and the names the data knows, built once.
local namesByMap, knownNames

local function Known(name)
    if not knownNames then
        knownNames = {}
        for zone in pairs(Waypoints.ZONE_MAPS) do knownNames[zone] = true end
        local dungeons = ns.Sources and ns.Sources.DUNGEONS
        for _, dungeon in pairs(type(dungeons) == "table" and dungeons or {}) do
            if type(dungeon[1]) == "string" then knownNames[dungeon[1]] = true end
            if type(dungeon[4]) == "string" then knownNames[dungeon[4]] = true end
        end
    end
    return knownNames[name] == true
end

local function NameOfMap(mapID)
    if not namesByMap then
        namesByMap = {}
        for zone, id in pairs(Waypoints.ZONE_MAPS) do
            if not CONTINENTS[id] then namesByMap[id] = zone end
        end
    end
    return namesByMap[mapID]
end

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

--- The data's name for a map and the maps it sits in (a cave's map sits in
--- its zone), or nil when none of them is a zone the data knows.
function Waypoints:DataNameOfMap(mapID)
    for _ = 1, 8 do
        if not mapID or mapID <= 0 then return nil end
        local name = NameOfMap(mapID)
        if name then return name end
        local _, parent = Info(mapID)
        mapID = parent
    end
    return nil
end

-- What each of the client's own zone names was found to be, for a client
-- that is not English: one name always means the same zone.
local translated = {}

--- The data's name for a zone the client names in its own language
--- (GetRealZoneText, a map's name). `mapID` is the map it names, when the
--- caller has it; else the character's dungeon, or the map they are on and
--- the maps it sits in. On an English client, or for a name the data
--- already knows, the name as given.
function Waypoints:DataZone(name, mapID)
    if type(name) ~= "string" or name == "" then return name end
    if Known(name) or Waypoints.English() then return name end
    local key = mapID and (name .. "|" .. mapID) or name
    if translated[key] then return translated[key] end

    local found
    if mapID then
        -- That very map: a spot on a cave's own map is not one on its zone's.
        found = NameOfMap(mapID)
    else
        -- Inside a dungeon: the instance's own ID, which the data's
        -- dungeons are keyed by ("389" Ragefire Chasm).
        local ok, kind, instanceID = pcall(function()
            local values = { _G.GetInstanceInfo() }
            return values[2], values[8]
        end)
        local dungeons = ns.Sources and ns.Sources.DUNGEONS
        kind = ok and Plain(kind) or nil
        if kind and kind ~= "none" and type(dungeons) == "table" and Number(instanceID) then
            local dungeon = dungeons[tostring(Number(instanceID))]
            found = dungeon and dungeon[1]
        end
        if not found then
            local map = Map()
            found = self:DataNameOfMap(map and Number(Read(map.GetBestMapForUnit, "player")))
        end
    end
    if found then translated[key] = found end
    return found or name
end

--- The map ID of a zone, by its name, or nil. Kept once found.
function Waypoints:MapFor(zone)
    if type(zone) ~= "string" or zone == "" then return nil end
    self.found = self.found or {}
    if self.found[zone] then return self.found[zone] end

    local map = Map()
    local top = TopMap()
    -- A miss is kept for the map it was looked for from: from another
    -- continent (or out of an instance) the zone may well be found.
    local missKey = top and (top .. "|" .. zone)
    if missKey and self.found[missKey] == false then return nil end
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

    -- A client in another language names its maps in that language: then
    -- Classic's map ID for the zone, when the client knows that map.
    if not mapID and map and Waypoints.ZONE_MAPS[zone] and not Waypoints.English() then
        local id = Waypoints.ZONE_MAPS[zone]
        if type(Read(map.GetMapInfo, id)) == "table" then mapID = id end
    end

    -- Only a search that ran is kept: on a loading screen or a taxi the
    -- client has no map yet, and that must not hide the zone until /reload.
    if map and top then
        if mapID then self.found[zone] = mapID else self.found[missKey] = false end
    end
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
