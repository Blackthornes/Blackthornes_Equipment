-- /beq probe reads the client and reports; it must never break on a client
-- that is missing something or raises.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("probe")

local ns = env.Load()
ns.HandleSlash("probe")
suite.check("runs on a client with none of the calls",
    env.ChatText():find("GetItemStats|r  no", 1, true), env.ChatText())

ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER" end
_G.GetInventoryItemLink = function(_, slot)
    if slot == 18 then return "|Hitem:2504|h[Worn Shortbow]|h" end
    if slot == 17 then error("secret value") end
end
_G.C_Item = { GetItemStats = function()
    return { ITEM_MOD_AGILITY_SHORT = 1, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 3.1,
             ITEM_MOD_NEW_THING = 2 }
end }
ns.HandleSlash("probe")
local text = env.ChatText()
suite.check("reads the class", text:find("HUNTER", 1, true), text)
suite.check("says it judges as the default", text:find("beast (default)", 1, true), text)
suite.check("shows the ranged weapon's raw stats",
    text:find("ITEM_MOD_AGILITY_SHORT=1", 1, true), text)
suite.check("lists the stats it does not weigh",
    text:find("not weighted|r  ITEM_MOD_NEW_THING", 1, true), text)
suite.check("an empty slot says so", text:find("main hand|r  empty", 1, true), text)
suite.check("a slot that raises says so too", text:find("off hand|r  empty or not readable", 1, true), text)

suite.done()
