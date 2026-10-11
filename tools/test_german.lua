-- A client in another language (German here): the game names zones,
-- professions and skills in German, while the data names them in English.
-- Every check that matched an English name also matches the client's own,
-- found by ID; on an English client nothing changes.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("german")

--------------------------------------------------------------------------------
-- Zones
--------------------------------------------------------------------------------

local ns = env.Load()
local Waypoints = ns.Waypoints

local MAPS = {
    [947] = { name = "Azeroth", parentMapID = 0 },
    [1415] = { name = "Östliche Königreiche", parentMapID = 947 },
    [1429] = { name = "Wald von Elwynn", parentMapID = 1415 },
    [1458] = { name = "Unterstadt", parentMapID = 1415 },
    [5001] = { name = "Jaspismine", parentMapID = 1429 },
    [1412] = { name = "Mulgore", parentMapID = 1414 },
    [1456] = { name = "Donnerfels", parentMapID = 1412 },
}
local here = 1429
local zone = "Wald von Elwynn"
_G.C_Map = {
    GetBestMapForUnit = function() return here end,
    GetMapInfo = function(id) return MAPS[id] end,
    GetMapChildrenInfo = function()
        local list = {}
        for id, info in pairs(MAPS) do
            if id ~= 947 then list[#list + 1] = { name = info.name, mapID = id } end
        end
        return list
    end,
}
_G.GetRealZoneText = function() return zone end

-- English first: just as before, whatever the maps say.
_G.GetLocale = function() return "enUS" end
suite.check("English: the client's name as given", ns.UpgradeQuest.Zone() == "Wald von Elwynn",
    ns.UpgradeQuest.Zone())
suite.check("English: a map is found by its name only", Waypoints:MapFor("Elwynn Forest") == nil)
Waypoints.found = nil

_G.GetLocale = function() return "deDE" end
-- In a mine with a map of its own, the zone it is in.
here = 5001
suite.check("German, in a cave: its zone by the data's name", ns.UpgradeQuest.Zone() == "Elwynn Forest",
    ns.UpgradeQuest.Zone())
here = 1429
suite.check("German: the zone by the data's name", ns.UpgradeQuest.Zone() == "Elwynn Forest",
    ns.UpgradeQuest.Zone())
suite.check("the finder sees it too", ns.Waypoints:DataZone(zone) == "Elwynn Forest")
suite.check("the map for a zone the data names", Waypoints:MapFor("Elwynn Forest") == 1429)
suite.check("one it does not know has none", Waypoints:MapFor("Nowhere") == nil)
suite.check("but a spot on the cave's own map is not called the zone's",
    Waypoints:DataZone("Jaspismine", 5001) == "Jaspismine")
suite.check("a map the data knows, by its ID", Waypoints:DataZone("Unterstadt", 1458) == "Undercity")

-- A name the data already knows (the same in German) is kept.
zone = "Durotar"
suite.check("a name the same in both", ns.UpgradeQuest.Zone() == "Durotar")

-- Inside a dungeon: by the instance's ID.
here, zone = nil, "Der Flammenschlund"
_G.GetInstanceInfo = function() return "Der Flammenschlund", "party", 1, "Normal", 5, 0, false, 389 end
suite.check("in a dungeon, its name in the data", ns.UpgradeQuest.Zone() == "Ragefire Chasm",
    ns.UpgradeQuest.Zone())
_G.GetInstanceInfo = nil

-- The weapon master in the city you are in.
here, zone = 1456, "Donnerfels"
_G.UnitClass = function() return "Krieger", "WARRIOR" end
_G.UnitFactionGroup = function() return "Horde" end
_G.IsPlayerSpell = function(id) return id == 196 or id == 197 end
env.InstallItems({
    ["item:1"] = { loc = "INVTYPE_2HWEAPON", class = 2, subclass = 1, stats = { ITEM_MOD_STRENGTH_SHORT = 10 } },
    ["item:2"] = { loc = "INVTYPE_2HWEAPON", class = 2, subclass = 10, stats = { ITEM_MOD_STRENGTH_SHORT = 20 } },
}, { [16] = "item:1" }, { [0] = {} })
local place = ns.WeaponSkills:Master("item:2")
suite.check("in Donnerfels, Thunder Bluff's master", place and place.name == "Ansekhwa", place and place.name)

--------------------------------------------------------------------------------
-- Gathering tools and Enchanting
--------------------------------------------------------------------------------

ns = env.Load()
_G.GetLocale = function() return "deDE" end
local TIPS = {
    ["item:9"] = "Anlegen: Kürschnerei +10.",
    ["item:10"] = "Equip: Skinning +5.",
    ["item:11"] = "Anlegen: Ausdauer +5.",
}
_G.C_TooltipInfo = { GetHyperlink = function(link)
    return { lines = { { leftText = TIPS[link] } } }
end }
local NAMES = { [393] = "Kürschnerei", [186] = "Bergbau", [182] = "Kräuterkunde", [356] = "Angeln",
    [333] = "Verzauberkunst", [2940] = "Verzauberkunst", [165] = "Lederverarbeitung",
    [2945] = "Lederverarbeitung" }
_G.C_TradeSkillUI = {
    GetProfessionInfoBySkillLineID = function(id)
        return NAMES[id] and { professionName = NAMES[id], skillLevel = 100, maxSkillLevel = 150 } or nil
    end,
    GetAllProfessionTradeSkillLines = function() return { 2945, 165 } end,
}
suite.check("a German skinning knife's line is a tool", ns.BagIcons.IsTool("item:9") == true)
suite.check("the English line still is", ns.BagIcons.IsTool("item:10") == true)
suite.check("anything else is not", ns.BagIcons.IsTool("item:11") == false)

_G.GetNumSkillLines = function() return 1 end
_G.GetSkillLineInfo = function() return "Verzauberkunst", false, false, 120 end
suite.check("Enchanting in the skill list, by the client's name", ns.BagIcons:ReadEnchanter() == true)
_G.GetSkillLineInfo = function() return "Schneiderei", false, false, 120 end
suite.check("another profession is not", ns.BagIcons:ReadEnchanter() == false)
_G.GetNumSkillLines, _G.GetSkillLineInfo = nil, nil

-- Professions for crafted gear: by skill line, whatever the name.
local professions = ns.Crafting:Professions()
suite.check("Lederverarbeitung counts as Leatherworking", professions[165] == 100, tostring(professions[165]))

suite.done()
