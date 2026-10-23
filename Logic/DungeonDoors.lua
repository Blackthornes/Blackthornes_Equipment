-- Where a dungeon's door stands, learned as the player walks in (the owner
-- picked it, 2026-10-22). The data names the zone a door opens in, never
-- the spot, so the arrow and the upgrade quest could only aim at the
-- zone's middle. Outside, the spot the character stands on is noted on
-- zone changes, as a loading screen starts (PLAYER_LEAVING_WORLD) and every
-- `NOTE_EVERY` seconds (two cheap map calls), since on Forever the loading
-- screen alone noted nothing (Ragefire Chasm, 2026-10-23). If the next
-- PLAYER_ENTERING_WORLD, or a look again `RETRIES` seconds later while the
-- game is still setting the dungeon up, finds them inside a dungeon the
-- addon knows, the last spot noted is kept for it,
-- account wide in dungeonDoors[key] = { spots = { { zone, x, y, at } } }
-- (never rename it). A hearth or a summon lands somewhere else, so a spot
-- is used only when it sits in the zone the data names for the door, or,
-- for a dungeon whose zone the data lacks, once two spots agree.
--
-- Before any walk in, the door comes from Data/DungeonDoorSpots.lua
-- (ns.DUNGEON_DOOR_SPOTS, from the Forever client's game tables), so a new
-- player's arrow points at the door, not the middle of the zone. A spot
-- the player walked through always wins.

local _, ns = ...

local Doors = ns.NewModule("DungeonDoors")

-- How long the loading screen may take between leaving and arriving.
Doors.WAIT = 120
-- Spots kept a dungeon, newest replacing oldest.
Doors.KEEP = 5
-- Two spots this close (0 to 100 on the zone map) agree.
Doors.NEAR = 3
-- How often the spot outside is noted, in seconds.
Doors.NOTE_EVERY = 2
-- After arriving in an instance, look again this many seconds later while
-- the game has not said which dungeon it is.
Doors.RETRIES = { 1, 3, 6 }

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

--- Where the character stands outside, on the door zone's own map:
--- { zone, x, y } (0 to 100), or nil and why.
function Doors.HereOutside()
    local arrow = ns.QuestArrow
    if not (arrow and arrow.Here) then return nil, "no arrow" end
    if arrow.Inside and arrow.Inside() then return nil, "inside" end
    local ok, here = pcall(arrow.Here, arrow)
    if not (ok and type(here) == "table") then return nil, "no position" end
    local zone = here.zone
    if type(zone) ~= "string" or zone == "" then return nil, "no zone" end
    local x, y = Number(here.x), Number(here.y)
    -- The spot by the zone's own map: the game's best map can be a smaller
    -- one inside it (a city's cave), whose numbers point somewhere else.
    local zoneMap = ns.Waypoints and ns.Waypoints.MapFor and ns.Waypoints:MapFor(zone)
    if zoneMap and zoneMap ~= here.map then
        local okPos, zx, zy = pcall(function()
            local pos = _G.C_Map.GetPlayerMapPosition(zoneMap, "player")
            if not pos then return nil end
            local px, py = pos:GetXY()
            return px + 0, py + 0
        end)
        if okPos and zx and zy and (zx ~= 0 or zy ~= 0) then x, y = zx, zy end
    end
    if not (x and y) then return nil, "no position" end
    return { zone = zone, x = x * 100, y = y * 100 }
end

--- Note where the character stands outside. Kept until a newer one.
function Doors:Note()
    local spot, why = Doors.HereOutside()
    if not spot then
        if why ~= "inside" then self.lastNoteWhy = why end
        return false
    end
    spot.at = Now()
    self.outside = spot
    self.lastNoteWhy = nil
    return true
end

--- As a loading screen starts: note the spot once more if it can be read.
function Doors:Leaving()
    self:Note()
end

--- After the loading screen: inside a dungeon just now, keep the spot.
--- @return true when one was kept
function Doors:Arrived()
    local spot = self.outside
    if not spot then
        self.lastTry = "no spot noted outside" .. (self.lastNoteWhy and (" (" .. self.lastNoteWhy .. ")") or "")
        return false
    end
    if Now() - spot.at > Doors.WAIT then
        self.lastTry = "the spot outside was too old"
        return false
    end
    local DQ = ns.DungeonQuests
    local key = DQ and DQ.Inside()
    if not key then
        local arrow = ns.QuestArrow
        if not (arrow and arrow.Inside and arrow.Inside()) then return false end
        self.lastTry = "not in a known dungeon (" .. tostring(DQ and DQ.InstanceText and DQ.InstanceText() or "?") .. ")"
        return false
    end
    self.outside = nil
    local kept = self:Keep(key, spot.zone, spot.x, spot.y)
    self.lastTry = kept and ("kept " .. key .. " at " .. spot.zone) or "could not save"
    return kept
end

--- PLAYER_ENTERING_WORLD: try now, and again a little later while the game
--- is still saying which dungeon this is.
function Doors:Entered()
    if self:Arrived() then return end
    local arrow = ns.QuestArrow
    if not (self.outside and arrow and arrow.Inside and arrow.Inside()) then return end
    local after = _G.C_Timer and _G.C_Timer.After
    if type(after) ~= "function" then return end
    self.tries = (self.tries or 0) + 1
    local try = self.tries
    for _, wait in ipairs(Doors.RETRIES) do
        after(wait, function()
            if Doors.tries == try and Doors.outside then Doors:Arrived() end
        end)
    end
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

--- The shipped door spot by key: { zone, x, y, shipped = true }, or nil.
function Doors.Shipped(key)
    local row = key and ns.DUNGEON_DOOR_SPOTS and ns.DUNGEON_DOOR_SPOTS[key]
    if type(row) ~= "table" or type(row[1]) ~= "string" then return nil end
    local x, y = Number(row[2]), Number(row[3])
    if not (x and y) then return nil end
    return { zone = row[1], x = x, y = y, shipped = true }
end

--- The door's spot for a dungeon by key: { zone, x, y }, or nil. The one
--- the player walked through, else the shipped one.
function Doors:Spot(key)
    return self:Learned(key) or Doors.Shipped(key)
end

function Doors:Learned(key)
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
    if not key and type(name) == "string" then
        -- Scarlet Monastery's wings have doors of their own.
        local lower = name:lower()
        for wing, row in pairs(ns.Sources and ns.Sources.DUNGEONS or {}) do
            if type(row) == "table" and type(row[1]) == "string" and row[1]:lower() == lower then
                key = wing
                break
            end
        end
    end
    return key and self:Spot(key) or nil
end

--- A door place for the arrow: the learned spot laid on `place` (which
--- names the zone), when it is in that zone. `place` is changed and given back.
function Doors:Fill(place, dungeonName)
    if type(place) ~= "table" or (place.x or 0) > 0 then return place end
    local spot = self:SpotByName(dungeonName)
    -- A shipped spot can name the zone the door is reached from
    -- (Blackrock Mountain's are in Searing Gorge), so it brings its zone.
    if spot and (not place.zone or place.zone == spot.zone or spot.shipped) then
        place.zone, place.x, place.y = spot.zone, spot.x, spot.y
    end
    return place
end

--- For /beq probe.
function Doors:Describe()
    local store = Store() or {}
    local known, kept, shipped = 0, 0, 0
    for key in pairs(store) do
        kept = kept + 1
        if self:Learned(key) then known = known + 1 end
    end
    for _ in pairs(ns.DUNGEON_DOOR_SPOTS or {}) do shipped = shipped + 1 end
    local DQ = ns.DungeonQuests
    local outside = self.outside
    return ("%d dungeons with a spot, %d trusted, %d shipped, inside %s (%s), spot outside %s, last try: %s"):format(
        kept, known, shipped, tostring(DQ and DQ.Inside()),
        tostring(DQ and DQ.InstanceText and DQ.InstanceText() or "?"),
        outside and ("%s %.1f %.1f, %ds ago"):format(outside.zone, outside.x, outside.y,
            math.floor(Now() - outside.at)) or ("none" .. (self.lastNoteWhy and (" (" .. self.lastNoteWhy .. ")") or "")),
        self.lastTry or "none yet")
end

function Doors:OnEnable()
    ns.RegisterEvent(self, "PLAYER_LEAVING_WORLD", function() Doors:Leaving() end)
    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function() Doors:Entered() end)
    for _, event in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" }) do
        ns.RegisterEvent(self, event, function() Doors:Note() end)
    end
    local timer = _G.C_Timer
    if timer and type(timer.NewTicker) == "function" and not self.ticker then
        local ok, ticker = pcall(timer.NewTicker, Doors.NOTE_EVERY, function() Doors:Note() end)
        if ok then self.ticker = ticker end
    end
end
