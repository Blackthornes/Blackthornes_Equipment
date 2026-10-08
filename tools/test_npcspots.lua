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

--------------------------------------------------------------------------------
-- What vendors charge
--------------------------------------------------------------------------------

ns.db.npcSpots = {}
suite.check("the Classic price stands until a merchant shows one",
    Vendor().price == 500 and not Vendor().priceSeen and Spots:Price(1001) == nil)

local wares = {
    { id = 1001, price = 450, stack = 1 },
    { id = 1002, price = 90, stack = 1 },             -- no vendor in the data
    { id = 1003, price = 0, stack = 1, extended = true },
}
S.ITEMS[1003] = { 10, 18, 0, 0, 0, v = { 3079, 0 } }
_G.GetMerchantNumItems = function() return #wares end
_G.GetMerchantItemID = function(i) return wares[i] and wares[i].id end
_G.C_MerchantFrame = { GetItemInfo = function(i)
    local w = wares[i]
    return w and { price = w.price, stackCount = w.stack, hasExtendedCost = w.extended or false }
end }

suite.check("a merchant window keeps the gear's price", Spots:LearnPrices() == 1)
suite.check("by item ID, in copper", ns.db.vendorPrices[1001] == 450 and Spots:PriceCount() == 1)
suite.check("not gear the finder has no vendor for", ns.db.vendorPrices[1002] == nil)
suite.check("nor what costs tokens", ns.db.vendorPrices[1003] == nil)
v = Vendor()
suite.check("the price seen in game wins over Classic's", v.price == 450 and v.priceSeen, v.price)
suite.check("seeing the same price again changes nothing", Spots:LearnPrices() == 0)

_G.C_MerchantFrame = nil
_G.GetMerchantItemID = nil
_G.GetMerchantItemLink = function(i) return wares[i] and ("|cffffffff|Hitem:%d::|h[x]|h|r"):format(wares[i].id) end
_G.GetMerchantItemInfo = function(i)
    local w = wares[i]
    return "x", 1, w.price, w.stack, -1, true, true, w.extended or false
end
wares[1].price = 405
suite.check("the older merchant calls work too", Spots:LearnPrices() == 1 and Spots:Price(1001) == 405)
_G.GetMerchantItemInfo = function() error("secret value") end
wares[1].price = 1
suite.check("a merchant slot that raises is skipped", Spots:LearnPrices() == 0 and Spots:Price(1001) == 405)

--------------------------------------------------------------------------------
-- Can the character pay
--------------------------------------------------------------------------------

local Finder = ns.Finder
local held = 1000
_G.GetMoney = function() return held end
suite.check("nothing is short when the money is there", Finder.Short(405) == nil)
held = 100
suite.check("the shortfall in copper when it is not", Finder.Short(405) == 305)
suite.check("the finder row says how much more",
    (Finder:Describe(Vendor()):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")):find("need 3s 5c more", 1, true),
    Finder:Describe(Vendor()))
_G.GetMoney = function() error("secret value") end
suite.check("unreadable money says nothing", Finder.Short(405) == nil
    and not Finder:Describe(Vendor()):find("need", 1, true))

held = 100
_G.GetMoney = function() return held end
local quest = { itemID = 1001, link = "[Vest]", source = { kind = "vendor", name = "Varg", zone = "Mulgore",
    x = 40, y = 50, price = 500 } }
local function BuyStep()
    for _, step in ipairs(ns.UpgradeQuest:Steps(quest)) do
        if step.text:find("^Buy") then return step end
    end
end
local buy = BuyStep()
local plain = function(text) return (text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") end
suite.check("the quest's buy step shows the price seen in game", plain(buy.text) == "Buy [Vest] for 4s 5c",
    plain(buy.text))
suite.check("and says the character can't pay yet", buy.short and plain(buy.note)
    == "Not enough money: you have 1s and need 3s 5c more.", plain(buy.note))
held = 5000
buy = BuyStep()
suite.check("with the money, no warning", not buy.short and buy.note == nil, buy.note)

suite.done()
