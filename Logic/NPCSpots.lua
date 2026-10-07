-- Blackthornes Equipment -- Logic/NPCSpots.lua
-- Where vendors and trainers really stand on WoW: Forever.
--
-- The finder's vendor and trainer spots come from Classic data, and Forever
-- has moved some of them. So whenever a merchant or trainer window opens,
-- the NPC's ID (from its GUID), the map the character is on and where the
-- character stands are kept, account wide, in `BlackthornesEquipmentDB.npcSpots`
-- [npcID] = { name, zone, x, y }. Talking to an NPC means standing next to
-- it, so the character's spot is the NPC's spot to within a step.
--
-- A spot seen in game wins over the shipped one: this file's Get is asked
-- first wherever a place is made from an NPC ID. Before a release, the spots
-- in the owner's save are folded into Data/ForeverNPCs.lua by
-- tools/forever_npcs.py (NPC IDs, map names and numbers only), so every
-- player gets them.
--
-- Every client value is read inside a pcall and copied: in an instance the
-- game hands out secret values that raise when touched. One merchant window
-- is one read, so nothing here runs on bag events.

local _, ns = ...

local NPCSpots = ns.NewModule("NPCSpots")

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
    local ok, copy = pcall(function()
        local n = tonumber(value)
        if n and n == n then return n + 0 end
    end)
    return ok and copy or nil
end

--- The NPC ID in a creature's GUID ("Creature-0-1-2-3-3079-0000A1B2C3"),
--- or nil for players, pets and anything unreadable.
function NPCSpots.IDFromGUID(guid)
    local ok, id = pcall(function()
        if type(guid) ~= "string" then return nil end
        local parts = {}
        for part in guid:gmatch("[^-]+") do parts[#parts + 1] = part end
        if parts[1] ~= "Creature" and parts[1] ~= "Vehicle" then return nil end
        return tonumber(parts[6])
    end)
    return ok and id or nil
end

local function Round(n) return math.floor(n * 1000 + 0.5) / 10 end

--- Where the character stands: the map's name, and x, y on it from 0 to
--- 100 as the finder shows them. Nil inside an instance or when unreadable.
function NPCSpots:Here()
    local map = type(_G.C_Map) == "table" and _G.C_Map or nil
    if not map then return nil end
    local mapID = Number(Read(map.GetBestMapForUnit, "player"))
    if not mapID then return nil end
    local position = Read(map.GetPlayerMapPosition, mapID, "player")
    if position == nil then return nil end
    local ok, x, y = pcall(function()
        local px, py = position:GetXY()
        return px + 0, py + 0
    end)
    if not ok or not x or not y or x <= 0 or y <= 0 or x >= 1 or y >= 1 then return nil end
    local info = Read(map.GetMapInfo, mapID)
    local name
    if type(info) == "table" then
        local read, value = pcall(function() return info.name end)
        name = read and Plain(value) or nil
    end
    if not name then return nil end
    return name, Round(x), Round(y), mapID
end

--- What the game says about the NPC behind an open window, without keeping
--- it: ID, name, and where it stands. Nil when any part is unreadable.
function NPCSpots:Read(unit)
    unit = unit or "npc"
    local npcID = self.IDFromGUID(Plain(Read(_G.UnitGUID, unit)))
    if not npcID then return nil end
    local zone, x, y = self:Here()
    if not zone then return nil end
    return { npcID = npcID, name = Plain(Read(_G.UnitName, unit)), zone = zone, x = x, y = y }
end

--- Keep where the NPC behind an open merchant or trainer window stands.
--- The latest sighting wins, so an NPC Forever moves is followed.
function NPCSpots:Learn(unit)
    local db = ns.db
    if type(db) ~= "table" then return nil end
    local seen = self:Read(unit)
    if not seen then return nil end
    if type(db.npcSpots) ~= "table" then db.npcSpots = {} end
    db.npcSpots[seen.npcID] = { seen.name or "", seen.zone, seen.x, seen.y }
    return seen
end

--- How many spots this account has learned.
function NPCSpots:Count()
    local n = 0
    for _ in pairs(type(ns.db) == "table" and type(ns.db.npcSpots) == "table" and ns.db.npcSpots or {}) do
        n = n + 1
    end
    return n
end

local function Valid(spot)
    return type(spot) == "table" and type(spot[2]) == "string" and spot[2] ~= ""
        and type(spot[3]) == "number" and type(spot[4]) == "number"
end

--- Where an NPC stands on Forever, as { name, zone, x, y }: learned on this
--- account first, then shipped in Data/ForeverNPCs.lua. Nil when neither
--- knows it, and the Classic spot stands. The name is "" when not known.
function NPCSpots:Get(npcID)
    local learned = type(ns.db) == "table" and type(ns.db.npcSpots) == "table" and ns.db.npcSpots[npcID]
    if Valid(learned) then return learned end
    local shipped = ns.ForeverNPCs and ns.ForeverNPCs[npcID]
    if Valid(shipped) then return shipped end
    return nil
end

--- A place made from Classic data, moved to where the NPC stands on
--- Forever when that is known: name, zone, x, y.
function NPCSpots:Place(npcID, name, zone, x, y)
    local spot = self:Get(npcID)
    if not spot then return name, zone, x, y end
    local seenName = type(spot[1]) == "string" and spot[1] ~= "" and spot[1] or name
    return seenName, spot[2], spot[3], spot[4]
end

function NPCSpots:OnEnable()
    ns.RegisterEvent(self, "MERCHANT_SHOW", function() NPCSpots:Learn("npc") end)
    ns.RegisterEvent(self, "TRAINER_SHOW", function() NPCSpots:Learn("npc") end)
end
