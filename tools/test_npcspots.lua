-- Where vendors stand on Forever: opening a merchant window keeps the NPC's
-- ID and the character's spot, and the finder shows that spot (or the
-- shipped Forever one) ahead of the Classic one.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("npcspots")

local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end
local ITEMS = {
    ["item:900"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = Agi(10) },
    ["item:1001"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = Agi(20) },
}

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitFactionGroup = function() return "Horde", "Horde" end
_G.UnitRace = function() return "Tauren", "Tauren", 6 end
env.InstallItems(ITEMS, { [5] = "item:900" }, { [0] = {} }, 20)

local S = ns.Sources
S.ZONES = { [215] = "Mulgore" }
S.NPCS = { [3079] = { "Varg Windwhisper", 215, 45.8, 58.7, "H" } }
S.QUESTS, S.DUNGEONS, S.BOSSES, S.FOREVER = {}, {}, {}, {}
S.ITEMS = { [1001] = { 10, 18, 0, 0, 500, v = { 3079, 0 } } }
ns.Crafts.ITEMS = {}

local Spots = ns.NPCSpots
local player = ns.Finder:Player()

local function Vendor()
    for _, source in ipairs(ns.Finder:SourcesFor(1001, player)) do
        if source.kind == "vendor" then return source end
    end
end

--------------------------------------------------------------------------------
-- The GUID
--------------------------------------------------------------------------------

suite.check("a creature's GUID gives its NPC ID",
    Spots.IDFromGUID("Creature-0-4372-1-11-3079-00001F2A3B") == 3079)
suite.check("a player's gives nothing", Spots.IDFromGUID("Player-4372-0A1B2C3D") == nil)
suite.check("nor does nothing", Spots.IDFromGUID(nil) == nil)
suite.check("nor a value that raises", Spots.IDFromGUID(setmetatable({}, {
    __index = function() error("secret") end })) == nil)

--------------------------------------------------------------------------------
-- Shipped Forever spot
--------------------------------------------------------------------------------

ns.ForeverNPCs = { [3079] = { "", "Mulgore", 45.3, 62.1 } }
local v = Vendor()
suite.check("the shipped Forever spot wins over Classic's", v and v.x == 45.3 and v.y == 62.1,
    v and (v.x .. ", " .. v.y))
suite.check("and keeps the Classic name when Forever's is not known", v.name == "Varg Windwhisper", v.name)

--------------------------------------------------------------------------------
-- Learning in game
--------------------------------------------------------------------------------

local guid, x, y = "Creature-0-4372-1-11-3079-00001F2A3B", 0.4527, 0.6213
_G.UnitGUID = function(unit) return unit == "npc" and guid or nil end
_G.UnitName = function(unit) return unit == "npc" and "Varg Windshaper" or nil end
_G.C_Map = {
    GetBestMapForUnit = function() return 7 end,
    GetPlayerMapPosition = function() return { GetXY = function() return x, y end } end,
    GetMapInfo = function(id) return id == 7 and { name = "Mulgore" } or nil end,
}

suite.check("nothing learned yet", Spots:Count() == 0)
local seen = Spots:Learn("npc")
suite.check("a merchant window keeps the spot", seen ~= nil and Spots:Count() == 1)
local kept = ns.db.npcSpots[3079]
suite.check("by NPC ID, with name, map and spot to a tenth",
    kept and kept[1] == "Varg Windshaper" and kept[2] == "Mulgore" and kept[3] == 45.3 and kept[4] == 62.1,
    kept and table.concat(kept, ", "))

x, y = 0.40, 0.50
ns.ForeverNPCs = { [3079] = { "", "Mulgore", 45.3, 62.1 } }
Spots:Learn("npc")
v = Vendor()
suite.check("the latest sighting wins over the shipped one", v.x == 40 and v.y == 50, v.x .. ", " .. v.y)
suite.check("with Forever's name", v.name == "Varg Windshaper", v.name)

--------------------------------------------------------------------------------
-- What is not kept
--------------------------------------------------------------------------------

guid = "Player-4372-0A1B2C3D"
suite.check("a player is never kept", Spots:Learn("npc") == nil and Spots:Count() == 1)

guid = "Creature-0-4372-1-11-3080-00001F2A3C"
_G.C_Map.GetPlayerMapPosition = function() return nil end
suite.check("nor a spot inside an instance", Spots:Learn("npc") == nil and Spots:Count() == 1)

_G.C_Map.GetPlayerMapPosition = function() error("secret value") end
suite.check("nor one that raises", Spots:Learn("npc") == nil and Spots:Count() == 1)

ns.db.npcSpots[3079] = { "broken" }
ns.ForeverNPCs = {}
v = Vendor()
suite.check("an unreadable saved spot is skipped, not deleted",
    v.x == 45.8 and ns.db.npcSpots[3079][1] == "broken", v.x)

suite.done()
