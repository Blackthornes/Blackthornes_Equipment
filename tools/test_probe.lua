-- /beq probe reads the client and reports; it must never break on a client
-- that is missing something or raises.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("probe")

local ns = env.Load()
ns.HandleSlash("probe")
suite.check("runs on a client with none of the calls",
    env.ChatText():find("has|r  none of them", 1, true), env.ChatText())
suite.check("and lists them as missing on one line",
    env.ChatText():find("missing|r  UnitClass, UnitLevel,", 1, true), env.ChatText())

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
_G.UnitLevel = function() return 12 end
_G.C_ClassTalents = { GetActiveConfigID = function() return 77 end }
_G.C_Traits = {
    GetConfigInfo = function(id)
        return { ID = id, type = 1, name = "Hunter", treeIDs = { 101, 102 } }
    end,
    GetTreeCurrencyInfo = function(_, treeID)
        if treeID == 101 then return { { spent = 3, maxQuantity = 20 } } end
        error("secret value")
    end,
    GetTreeNodes = function(treeID) return treeID == 101 and { 1, 2, 3, 4 } or {} end,
}
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

suite.check("lists the calls it has",
    text:find("has|r  UnitClass, UnitLevel,", 1, true), text)
suite.check("reads the level", text:find("level|r  12", 1, true), text)
suite.check("reads the talent config", text:find("talent config|r  77", 1, true), text)
suite.check("counts its trees", text:find("2 tree(s)", 1, true), text)
suite.check("reads points spent in a tree",
    text:find("id 101, spent 3 of 20, 4 nodes", 1, true), text)
suite.check("a tree that raises is still listed",
    text:find("id 102, 0 nodes", 1, true), text)

suite.done()
