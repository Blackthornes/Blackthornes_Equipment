-- A hunter's every shot spends ammo, and the client says the bags and the
-- ammo slot changed each time. Those are passed on only when what is
-- carried or worn has really changed, or the game hangs after each arrow.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("quietevents")

local ITEMS = {
    ["item:900"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = { ITEM_MOD_AGILITY_SHORT = 10 } },
    ["item:1001"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = { ITEM_MOD_AGILITY_SHORT = 20 } },
    ["item:2512"] = { loc = "INVTYPE_AMMO", class = 6, subclass = 2 },   -- Rough Arrow
    ["item:2318"] = { loc = "", class = 7, subclass = 6 },               -- Light Leather
}

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
env.InstallItems(ITEMS, { [0] = "item:2512", [5] = "item:900" },
    { [0] = { [1] = "item:2512", [2] = "item:2318" } }, 17)

local counts = { [0] = { [1] = 200, [2] = 4 } }
_G.C_Container.GetContainerItemInfo = function(bag, slot)
    return { stackCount = counts[bag] and counts[bag][slot] or 1 }
end

local heard = { BAG_UPDATE_DELAYED = 0, PLAYER_EQUIPMENT_CHANGED = 0 }
local listener = {}
for event in pairs(heard) do
    ns.RegisterEvent(listener, event, function(_, name) heard[name] = heard[name] + 1 end)
end
local function Fire(event, ...)
    ns.eventFrame:GetScript("OnEvent")(ns.eventFrame, event, ...)
end

Fire("BAG_UPDATE_DELAYED")
suite.check("the first bag change is passed on", heard.BAG_UPDATE_DELAYED == 1)

for _ = 1, 30 do
    counts[0][1] = counts[0][1] - 1
    Fire("BAG_UPDATE_DELAYED")
    Fire("PLAYER_EQUIPMENT_CHANGED", 0)
end
suite.check("thirty arrows shot: no bag change passed on", heard.BAG_UPDATE_DELAYED == 1, heard.BAG_UPDATE_DELAYED)
suite.check("the ammo slot is passed on once at most", heard.PLAYER_EQUIPMENT_CHANGED <= 1,
    heard.PLAYER_EQUIPMENT_CHANGED)
local equipBefore = heard.PLAYER_EQUIPMENT_CHANGED

counts[0][2] = 5
Fire("BAG_UPDATE_DELAYED")
suite.check("a material's count is a change (crafting steps count them)", heard.BAG_UPDATE_DELAYED == 2)

env.bags[0][3] = "item:1001"
Fire("BAG_UPDATE_DELAYED")
suite.check("new gear in the bags is a change", heard.BAG_UPDATE_DELAYED == 3)

env.bags[0][1] = nil
Fire("BAG_UPDATE_DELAYED")
suite.check("the last arrow gone from the bags is a change", heard.BAG_UPDATE_DELAYED == 4)

env.worn[5] = "item:1001"
Fire("PLAYER_EQUIPMENT_CHANGED", 5)
suite.check("putting on gear is a change", heard.PLAYER_EQUIPMENT_CHANGED == equipBefore + 1)

-- The modules that look again at upgrades hear only real changes too.
local scans = 0
local realScan = ns.Finder.MarkStale
ns.Finder.MarkStale = function(...) scans = scans + 1 return realScan(...) end
env.bags[0][1] = "item:2512"
Fire("BAG_UPDATE_DELAYED")
local after = scans
for _ = 1, 10 do
    counts[0][1] = counts[0][1] - 1
    Fire("BAG_UPDATE_DELAYED")
end
suite.check("the upgrade finder does not look again per arrow", scans == after, scans - after)
ns.Finder.MarkStale = realScan

suite.done()
