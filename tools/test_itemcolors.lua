-- Item names show their rarity colour wherever they are drawn (the owner,
-- 2026-10-18): grey, white, green, blue, purple and orange, from the item's
-- own quality. An item the client has not sent yet keeps the line's colour,
-- is asked for once, and the windows draw again when it arrives.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("itemcolors")

local ns = env.Load()

local HEX = { [0] = "ff9d9d9d", "ffffffff", "ff1eff00", "ff0070dd", "ffa335ee", "ffff8000" }
_G.ITEM_QUALITY_COLORS = {}
for quality, hex in pairs(HEX) do
    _G.ITEM_QUALITY_COLORS[quality] = {
        r = tonumber(hex:sub(3, 4), 16) / 255, g = tonumber(hex:sub(5, 6), 16) / 255,
        b = tonumber(hex:sub(7, 8), 16) / 255,
    }
end

-- [itemID] = { name, quality }
local KNOWN = {
    [100] = { "Broken Fang", 0 }, [2318] = { "Light Leather", 1 }, [2320] = { "Coarse Thread", 1 },
    [300] = { "Green Thing", 2 }, [400] = { "Blue Thing", 3 }, [500] = { "Purple Thing", 4 },
    [600] = { "Orange Thing", 5 }, [2406] = { "Pattern: Fine Leather Boots", 2 },
}
local byName = {}
for id, item in pairs(KNOWN) do byName[item[1]] = id end
local asked = {}
_G.C_Item = {
    GetItemInfo = function(item)
        local id = tonumber(item) or (type(item) == "string" and tonumber(item:match("item:(%d+)")))
            or byName[item]
        local known = id and KNOWN[id]
        if not known then return nil end
        local link = ("|c%s|Hitem:%d::::::::::::|h[%s]|h|r"):format(HEX[known[2]], id, known[1])
        return known[1], link, known[2]
    end,
    RequestLoadItemDataByID = function(id) asked[#asked + 1] = id end,
}

local Items = ns.Items
local function Wrapped(id, name) return ("|c%s%s|r"):format(HEX[KNOWN[id][2]], name) end

for id, item in pairs(KNOWN) do
    suite.check("quality " .. item[2] .. " in its own colour",
        Items.ColorName(id, item[1]) == Wrapped(id, item[1]), Items.ColorName(id, item[1]))
end
suite.check("white items are white, not left plain",
    Items.ColorName(2318, "Light Leather") == "|cffffffffLight Leather|r")
suite.check("a name with no ID, once the client knows it",
    Items.ColorName(nil, "Blue Thing") == Wrapped(400, "Blue Thing"))
suite.check("text that already has a colour is left alone",
    Items.ColorName(300, "|cffff0000Green Thing|r") == "|cffff0000Green Thing|r")

-- Not sent yet: plain, asked once, and the windows hear when it comes.
suite.check("an item not sent yet stays as it is", Items.ColorName(777, "Mystery") == "Mystery")
Items.ColorName(777, "Mystery")
suite.check("and is asked for once", #asked == 1 and asked[1] == 777, #asked)
suite.check("it waits for that item", Items:Waiting(777) == true)
local redrawn = 0
Items:WatchNames(function() redrawn = redrawn + 1 end)
Items:OnItemInfo("GET_ITEM_INFO_RECEIVED", 12345)
suite.check("an item nobody here asked for redraws nothing", redrawn == 0)
KNOWN[777] = { "Mystery", 3 }
Items:OnItemInfo("GET_ITEM_INFO_RECEIVED", 777)
suite.check("its arrival redraws the windows", redrawn == 1, redrawn)
suite.check("now in its colour", Items.ColorName(777, "Mystery") == Wrapped(777, "Mystery"))
suite.check("and no longer waited on", Items:Waiting(777) == false)

-- A quest saved before the client sent the item shows its real link.
suite.check("an item string shows as the item's link",
    Items.ShowLink("item:400") == select(2, C_Item.GetItemInfo(400)), Items.ShowLink("item:400"))
local real = select(2, C_Item.GetItemInfo(500))
suite.check("a real link is kept as it is", Items.ShowLink(real) == real)

-- Materials and a recipe to learn, in the finder and the quest steps.
local C = ns.Crafts
C.MATERIALS = { [2318] = { "Light Leather", 0 }, [2320] = { "Coarse Thread", 10 } }
C.ITEMS = { [3001] = { 165, 50, 9001, 15, 18, 0, 0, 0, m = { 2318, 8, 2320, 4 } } }
suite.check("materials each in their colour",
    ns.Crafting:MaterialsText(3001) == "8 |cffffffffLight Leather|r, 4 |cffffffffCoarse Thread|r",
    ns.Crafting:MaterialsText(3001))
local learn = { how = "drop", recipe = "Pattern: Fine Leather Boots", recipeID = 2406, drops = 500 }
suite.check("a recipe to learn names the recipe in its colour",
    ns.Crafting:LearnText(learn, function() return nil end)
        == Wrapped(2406, "Pattern: Fine Leather Boots") .. ", a world drop",
    ns.Crafting:LearnText(learn, function() return nil end))

-- The upgrade quest's steps for a quest that starts from an item.
ns.Sources.STARTS = { [770] = { 300, "Green Thing", 1, { "mob", "Ghost Howl", "Mulgore", 37.3, 14.2, 12, 12, 100, "rare" } } }
local quest = { itemID = 400, link = "item:400", source = { kind = "quest", questID = 770, title = "A Quest",
    questLevel = 12, name = "Green Thing", zone = "Mulgore" } }
local ok, steps = pcall(ns.UpgradeQuest.Steps, ns.UpgradeQuest, quest)
local texts = {}
for _, step in ipairs(ok and steps or {}) do texts[#texts + 1] = step.text end
local all = table.concat(texts, " | ")
suite.check("the item that starts it in its colour",
    all:find("Get " .. Wrapped(300, "Green Thing") .. " from Ghost Howl", 1, true) ~= nil, all)
suite.check("and the upgrade by its real link, though saved as an item string",
    all:find(select(2, C_Item.GetItemInfo(400)), 1, true) ~= nil, all)

-- A tracked hunt keeps its place in plain words; the names are coloured
-- only when drawn.
local questSource = { kind = "quest", questID = 770, title = "A Quest", questLevel = 12,
    name = "Green Thing", zone = "Mulgore" }
local place = ns.Tracking.PlaceOf(questSource)
suite.check("a saved place has no colour", place and not place.text:find("|c", 1, true), place and place.text)
suite.check("and keeps the item it names by ID", place and place.items and place.items[1][1] == 300)
suite.check("drawn, the item is in its colour",
    ns.Tracking.PlaceText(place):find(Wrapped(300, "Green Thing"), 1, true) ~= nil, ns.Tracking.PlaceText(place))
local craftSource = { kind = "craft", itemID = 3001, state = "learn", profession = "Leatherworking", skill = 90,
    learn = learn }
local craftPlace = ns.Tracking.PlaceOf(craftSource)
suite.check("a saved recipe place has no colour", craftPlace and not craftPlace.text:find("|c", 1, true),
    craftPlace and craftPlace.text)
suite.check("drawn, the recipe is in its colour",
    ns.Tracking.PlaceText(craftPlace):find(Wrapped(2406, "Pattern: Fine Leather Boots"), 1, true) ~= nil,
    ns.Tracking.PlaceText(craftPlace))
suite.check("an older place with no items draws as saved",
    ns.Tracking.PlaceText({ text = "Vendor  Bob" }) == "Vendor  Bob")

suite.done()
