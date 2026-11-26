-- /beq probe reads the client and reports; it must never break on a client
-- that is missing something or raises.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("probe")

local ns = env.Load()
ns.HandleSlash("probe")
suite.check("runs on a client with none of the calls",
    env.ChatText():find("has|r  none of them", 1, true), env.ChatText())
suite.check("says no weapon skills could be read",
    env.ChatText():find("weapon skills|r  none read, so no trainer lines", 1, true), env.ChatText())
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
    -- Two columns: x 100 holds nodes 1 and 2, x 700 holds 3 and 4. Node 3 has
    -- two points in it; node 4 raises.
    GetNodeInfo = function(_, nodeID)
        if nodeID == 4 then error("secret value") end
        local layout = {
            [1] = { posX = 100, posY = 50, entryIDs = { 11 }, ranksPurchased = 0 },
            [2] = { posX = 100.4, posY = 10, entryIDs = { 12 }, ranksPurchased = 0 },
            [3] = { posX = 700, posY = 10, entryIDs = { 13 }, ranksPurchased = 2 },
        }
        return layout[nodeID]
    end,
    GetEntryInfo = function(_, entryID) return { definitionID = entryID + 100 } end,
    GetDefinitionInfo = function(definitionID) return { spellID = definitionID + 1000 } end,
}
_G.C_Spell = { GetSpellName = function(spellID)
    return ({ [1112] = "Kill Command", [1113] = "Aimed Shot" })[spellID]
end }
_G.C_SpecializationInfo = { GetSpecialization = function() return 5 end }
ns.HandleSlash("probe")
local text = env.ChatText()
suite.check("reads the class", text:find("HUNTER", 1, true), text)
suite.check("counts points per spec from the trait tree",
    text:find("points per spec|r  2 / 0 / 0", 1, true), text)
suite.check("and judges from them", text:find("beast (talents)", 1, true), text)
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
suite.check("reads the spec index", text:find("spec index|r  5", 1, true), text)
suite.check("groups nodes into columns, named by their top talent",
    text:find("x100: 2 (Kill Command); x700: 1 (Aimed Shot)", 1, true), text)
suite.check("lists where points are spent",
    text:find("spent in|r  Aimed Shot 2 at x700", 1, true), text)
suite.check("a tree that raises is still listed",
    text:find("id 102, 0 nodes", 1, true), text)
suite.check("says which bag windows there are", text:find("bag windows|r  none found", 1, true), text)
suite.check("and what the arrows are hooked to", text:find("bag hooks|r  none", 1, true), text)

-- /beq probe looks: on a client with none of it, it still reports.
ns = env.Load()
ns.HandleSlash("probe looks")
text = env.ChatText()
suite.check("looks runs on a bare client", text:find("looks missing|r  DressUpItemLink", 1, true), text)
suite.check("says when no player is targeted", text:find("no player targeted", 1, true), text)
suite.check("and saves the report", ns.db.lastProbe and ns.db.lastProbe.check == "probe looks",
    ns.db.lastProbe and ns.db.lastProbe.check)

-- A client with model frames and a warrior targeted. The report waits for
-- the timer, and the inspect answers before it fires.
ns = env.Load()
local waiting
_G.C_Timer = { After = function(_, fn) waiting = fn end }
local tried, cleared
_G.CreateFrame = function(kind, name, parent)
    local frame = env.Stub({ _parent = parent })
    if kind == "DressUpModel" then
        frame.SetUnit = function() end
        frame.TryOn = function(_, link) tried = link; return 0 end
        frame.GetModelFileID = function() return 1100258 end
    elseif kind == "PlayerModel" then
        error("unknown frame type")
    elseif kind == "ModelScene" then
        frame.CreateActor = function() return { SetModelByUnit = function() return true end } end
    end
    if name then _G[name] = frame end
    return frame
end
_G.UnitIsPlayer = function(unit) return unit == "target" end
_G.UnitClass = function() return "Warrior", "WARRIOR" end
_G.CanInspect = function() return true end
local ready = false
_G.NotifyInspect = function() end
_G.ClearInspectPlayer = function() cleared = true end
_G.GetInventoryItemLink = function(unit, slot)
    if unit == "player" and slot == 5 then return "|Hitem:6731|h[Ironforge Breastplate]|h" end
    if unit == "target" and ready and (slot == 1 or slot == 3) then return "|Hitem:9|h[Helm of the Mountain]|h" end
    if unit == "target" and slot == 2 then error("secret value") end
end
ns.HandleSlash("probe looks")
suite.check("waits before it reports", waiting ~= nil and not env.ChatText():find("DressUpModel|r", 1, true))
suite.check("tries on a worn item", tried and tried:find("Ironforge Breastplate", 1, true), tried)
ready = true
ns.eventFrame:GetScript("OnEvent")(ns.eventFrame, "INSPECT_READY", "Player-1-ABC")
waiting()
text = env.ChatText()
suite.check("says the dress up model was made", text:find("DressUpModel|r  made; has SetUnit, TryOn", 1, true), text)
suite.check("reads its model file", text:find("model file|r  1100258", 1, true), text)
suite.check("says a frame type it could not make", text:find("PlayerModel|r  could not be made", 1, true), text)
suite.check("checks the scene actor", text:find("ModelScene|r  made, actor has SetModelByUnit", 1, true), text)
suite.check("names the target's class", text:find("class WARRIOR, same class as you", 1, true), text)
suite.check("hears the inspect answer", text:find("inspect ready|r  Player-1-ABC", 1, true), text)
suite.check("counts their links after", text:find("gear after|r  links 2, item IDs 0, icons 0 of 19; first link Helm of the Mountain, first ID none, 1 raised", 1, true), text)
suite.check("and none before", text:find("gear before|r  links 0,", 1, true), text)
suite.check("reads them when the inspect answers", text:find("gear at ready|r  links 2,", 1, true), text)
suite.check("lets go of the inspect", cleared)
suite.check("saves it for Claude", ns.db.lastProbe.check == "probe looks")

suite.done()
