-- Where a dungeon's door stands, learned as the player walks in (the owner
-- picked it, 2026-10-22). The data names the zone a door opens in, never
-- the spot, so the arrow and the upgrade quest could only aim at the
-- zone's middle. As the loading screen starts (PLAYER_LEAVING_WORLD) the
-- spot the character stands on is noted; if the next PLAYER_ENTERING_WORLD
-- finds them inside a dungeon the addon knows, that spot is kept for it,
-- account wide in dungeonDoors[key] = { spots = { { zone, x, y, at } } }
-- (never rename it). A hearth or a summon lands somewhere else, so a spot
-- is used only when it sits in the zone the data names for the door, or,
-- for a dungeon whose zone the data lacks, once two spots agree.

local _, ns = ...

local Doors = ns.NewModule("DungeonDoors")

-- How long the loading screen may take between leaving and arriving.
Doors.WAIT = 120
-- Spots kept a dungeon, newest replacing oldest.
Doors.KEEP = 5
-- Two spots this close (0 to 100 on the zone map) agree.
Doors.NEAR = 3

local function Number(value)
    local ok, copy = pcall(function()
        local n = tonumber(value)
        if n and n == n then return n + 0 end
    end)
    return ok and copy or nil
end

local function Now()
    local ok, now = pcall(function() return _G.GetTime() + 0 end)
    return ok and now or 0
end

local function Store()
    if type(ns.db) ~= "table" then return nil end
    if type(ns.db.dungeonDoors) ~= "table" then ns.db.dungeonDoors = {} end
    return ns.db.dungeonDoors
end

--- Note where the character stands as a loading screen starts.
function Doors:Leaving()
    self.leaving = nil
    local arrow = ns.QuestArrow
    if not (arrow and arrow.Here) or (arrow.Inside and arrow.Inside()) then return end
    local ok, here = pcall(arrow.Here, arrow)
    if not (ok and type(here) == "table" and type(here.zone) == "string" and here.zone ~= "") then return end
    local x, y = Number(here.x), Number(here.y)
    if not (x and y) then return end
    self.leaving = { zone = here.zone, x = x * 100, y = y * 100, at = Now() }
end

--- After the loading screen: inside a dungeon just now, keep the spot.
function Doors:Arrived()
    local spot = self.leaving
    self.leaving = nil
    if not spot or Now() - spot.at > Doors.WAIT then return false end
    local key = ns.DungeonQuests and ns.DungeonQuests.Inside()
    if not key then return false end
    return self:Keep(key, spot.zone, spot.x, spot.y)
end

function Doors:Keep(key, zone, x, y)
    local store = Store()
    if not (store and key and zone and x and y) then return false end
    local entry = type(store[key]) == "table" and store[key] or { spots = {} }
    if type(entry.spots) ~= "table" then entry.spots = {} end
    store[key] = entry
    table.insert(entry.spots, { zone = zone,
        x = math.floor(x * 10 + 0.5) / 10, y = math.floor(y * 10 + 0.5) / 10,
        at = Number(pcall(_G.time) and _G.time()) })
    while #entry.spots > Doors.KEEP do table.remove(entry.spots, 1) end
    self.version = (self.version or 0) + 1
    return true
end

local function Near(a, b)
    return a.zone == b.zone and math.abs(a.x - b.x) <= Doors.NEAR and math.abs(a.y - b.y) <= Doors.NEAR
end

--- The door's spot for a dungeon by key: { zone, x, y }, or nil.
function Doors:Spot(key)
    local store = Store()
    local entry = store and key and store[key]
    if type(entry) ~= "table" or type(entry.spots) ~= "table" then return nil end
    local DQ = ns.DungeonQuests
    local dungeon = DQ and DQ.Dungeon(key)
    local zone = dungeon and dungeon.door
    -- Newest first: a door spot that agrees with another, else one in the
    -- zone the data names.
    for i = #entry.spots, 1, -1 do
        local spot = entry.spots[i]
        if type(spot) == "table" and spot.zone and Number(spot.x) and Number(spot.y) then
            local trusted = zone and spot.zone == zone
            if not trusted and not zone then
                for j = i - 1, 1, -1 do
                    local other = entry.spots[j]
                    if type(other) == "table" and Number(other.x) and Number(other.y) and Near(spot, other) then
                        trusted = true
                        break
                    end
                end
            end
            if trusted then return { zone = spot.zone, x = spot.x, y = spot.y } end
        end
    end
    return nil
end

--- The same, by the dungeon's name (the upgrade quest names dungeons).
function Doors:SpotByName(name)
    local DQ = ns.DungeonQuests
    local key = DQ and DQ.KeyForName(name)
    return key and self:Spot(key) or nil
end

--- A door place for the arrow: the learned spot laid on `place` (which
--- names the zone), when it is in that zone. `place` is changed and given back.
function Doors:Fill(place, dungeonName)
    if type(place) ~= "table" or (place.x or 0) > 0 then return place end
    local spot = self:SpotByName(dungeonName)
    if spot and (not place.zone or place.zone == spot.zone) then
        place.zone, place.x, place.y = spot.zone, spot.x, spot.y
    end
    return place
end

--- For /beq probe.
function Doors:Describe()
    local store = Store() or {}
    local known, kept = 0, 0
    for key in pairs(store) do
        kept = kept + 1
        if self:Spot(key) then known = known + 1 end
    end
    return ("%d dungeons with a spot, %d trusted, inside %s"):format(kept, known,
        tostring(ns.DungeonQuests and ns.DungeonQuests.Inside()))
end

function Doors:OnEnable()
    ns.RegisterEvent(self, "PLAYER_LEAVING_WORLD", function() Doors:Leaving() end)
    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function() Doors:Arrived() end)
end
