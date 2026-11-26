-- Gear Road, My Gear's third view (UI/GearRoad.lua, the owner said build
-- it from the mockup, 2026-11-26).
--
-- What must hold:
--   1. A slot's road keeps only pieces that beat every piece before them.
--   2. Stops: Now first, the goal at 60 last, at most four between; a
--      heavier armor names its stop, else a dungeon, else its level.
--   3. Every step lands in the first stop at or after its level, one per
--      slot; the goal holds the best piece per slot and counts done slots.
--   4. In the fake game: Road shows the line, Now lists today's pieces,
--      a later piece shows in amber with its level, a click on a stop
--      fills the list, and the view is kept.
--   5. Opening the road again with nothing changed judges nothing, and
--      a hidden page starts no scan.
--   6. The From boxes leave out their gear; Alt-click on a slot goes back
--      to the figure.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("gearroad")

local ARMOR, LEATHER = 4, 2
local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end
local function Piece(loc, n, level)
    return { loc = loc, class = ARMOR, subclass = LEATHER, stats = Agi(n), bind = 0, minLevel = level }
end

local ITEMS = {
    ["item:800"] = Piece("INVTYPE_HEAD", 5),         -- worn
    ["item:900"] = Piece("INVTYPE_CHEST", 10),       -- worn
    ["item:1101"] = Piece("INVTYPE_HEAD", 8),        -- now
    ["item:1301"] = Piece("INVTYPE_HEAD", 14, 24),   -- level 24
    ["item:1302"] = Piece("INVTYPE_HEAD", 11, 30),   -- level 30, worse than 1301: no step
    ["item:1303"] = Piece("INVTYPE_CHEST", 22, 30),  -- level 30
    ["item:1304"] = Piece("INVTYPE_LEGS", 9, 52),    -- level 52
}

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitRace = function() return "Human", "Human", 1 end
env.InstallItems(ITEMS, { [1] = "item:800", [5] = "item:900" }, { [0] = {} }, 20)

local S = ns.Sources
ns.Crafts.ITEMS = {}
ns.RollData.ITEMS = {}
S.ZONES = { [12] = "Elwynn Forest" }
S.NPCS = { [1] = { "Corina Steele", 12, 41.5, 65.9, "A" } }
S.QUESTS, S.DUNGEONS, S.BOSSES, S.FOREVER = {}, {}, {}, {}
S.ITEMS = {
    [1101] = { 15, 15, 0, 0, 100, v = { 1, 0 } },
    [1301] = { 24, 24, 0, 0, 100, v = { 1, 0 } },
    [1302] = { 30, 30, 0, 0, 100, v = { 1, 0 } },
    [1303] = { 30, 30, 0, 0, 100, v = { 1, 0 } },
    [1304] = { 52, 52, 0, 0, 100, v = { 1, 0 } },
}

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end

local Gear, MyGear, Road, Finder, Compare = ns.GearWindow, ns.MyGear, ns.GearRoad, ns.Finder, ns.Compare
local function Click(frame, ...) frame:GetScript("OnClick")(frame, ...) end

local judges, scans = 0, 0
local realJudge, realBuild = Compare.Judge, Finder.Build
Compare.Judge = function(...) judges = judges + 1 return realJudge(...) end
Finder.Build = function(...) scans = scans + 1 return realBuild(...) end

-- 1. to 3. with a scan made by hand.
local function Pick(id, gain, at, percent, source)
    return { itemID = id, link = "item:" .. id, gain = gain, at = at,
        result = { verdict = "upgrade", percent = percent, slot = 1 },
        sources = { source or { kind = "vendor", name = "Corina Steele" } } }
end
local dungeon = { kind = "dungeon", name = "Boss", dungeon = "Uldaman", minLevel = 41, maxLevel = 51 }
local found = {
    all = {
        [1] = { Pick(1, 3, nil, 20), Pick(2, 9, 44, 60, dungeon), Pick(3, 5, 41, 40), Pick(4, 2, 30, 10) },
        [5] = { Pick(5, 4, 40, 30), Pick(6, 6, 58, 50) },
        [7] = { Pick(7, 1, 22, 5), Pick(8, 2, 25, 8), Pick(9, 3, 28, 9), Pick(10, 4, 33, 12) },
    },
}
local steps = Road.Steps(found, 20)
local function IDs(list)
    local out = {}
    for _, step in ipairs(list) do out[#out + 1] = step.pick.itemID end
    return table.concat(out, ",")
end
suite.check("a slot's road keeps only steps up", IDs(steps[1]) == "1,3,2", IDs(steps[1]))
suite.check("a worse later piece is no step", not IDs(steps[1]):find("4", 1, true))

local road = Road.Read(found, { level = 20, class = "WARRIOR" })
local function Levels()
    local out = {}
    for _, stop in ipairs(road.stops) do out[#out + 1] = stop.level .. ":" .. stop.kind end
    return table.concat(out, " ")
end
suite.check("Now first, the goal last, four between at most", #road.stops == 6
    and road.stops[1].kind == "now" and road.stops[6].kind == "goal" and road.stops[6].level == 60, Levels())
local plate
for _, stop in ipairs(road.stops) do if stop.kind == "armor" then plate = stop end end
suite.check("plate opens at 40 for a warrior, and names its stop", plate and plate.level == 40
    and Road.Head(plate) == "PLATE OPENS", Levels())
suite.check("the list head says the level too", plate and Road.ListHead(plate) == "LEVEL 40, PLATE OPENS",
    plate and Road.ListHead(plate))
local uldaman
for _, stop in ipairs(road.stops) do if stop.level == 44 then uldaman = stop end end
suite.check("a dungeon's best piece names its stop", uldaman and uldaman.kind == "dungeon"
    and Road.Head(uldaman) == "ULDAMAN", Levels())
suite.check("Now holds what can be worn today", IDs(road.stops[1].steps) == "1", IDs(road.stops[1].steps))
local goal = road.stops[6]
suite.check("the goal holds the best piece per slot, in slot order", IDs(goal.steps) == "2,6,10", IDs(goal.steps))
suite.check("and counts the slots with nothing ahead", road.total == 17 and road.done == 14,
    road.done .. " of " .. road.total)
local counted = {}
for _, stop in ipairs(road.stops) do
    if stop.kind ~= "goal" then
        for _, step in ipairs(stop.steps) do
            counted[step.slot] = (counted[step.slot] or 0) + 1
        end
    end
end
suite.check("a skipped level's steps join the next stop", (function()
    for _, stop in ipairs(road.stops) do
        local seen = {}
        for _, step in ipairs(stop.steps) do
            if seen[step.slot] then return false end
            seen[step.slot] = true
        end
    end
    return true
end)())
suite.check("a level 60 character has no goal stop", #Road.Read(found, { level = 60, class = "HUNTER" }).stops == 1)
suite.check("mail opens at 40 for a hunter", Road.ArmorAhead("HUNTER", 20) == 40)
suite.check("nothing opens past it", Road.ArmorAhead("HUNTER", 41) == nil and Road.ArmorAhead("MAGE", 10) == nil)
local more = Road.Read({ all = { [1] = { Pick(1, 1, 21, 5) }, [5] = { Pick(2, 1, 21, 5) },
    [7] = { Pick(3, 1, 21, 5) } } }, { level = 20, class = "MAGE" })
suite.check("a plain stop says its level", Road.Head(more.stops[2]) == "LEVEL 21", Road.Head(more.stops[2]))

-- 4.
-- 4.
ns.UI:Show()
suite.check("My Gear opens on the figure", MyGear:View() == "figure" and not Road:IsShown())
Click(MyGear.roadButton)
suite.check("Road shows the line, kept as the view", MyGear:View() == "road" and ns.db.myGearView == "road"
    and Road:IsShown() and not MyGear.figure:IsShown() and not MyGear.side:IsShown(),
    tostring(MyGear:View()) .. " " .. tostring(ns.db.myGearView) .. " " .. tostring(Road:IsShown()) .. " "
    .. tostring(MyGear.figure:IsShown()) .. " " .. tostring(MyGear.side:IsShown()))
suite.check("the cards step aside", not MyGear.cards.ready:IsShown() and not MyGear.cards.next:IsShown())
suite.check("with the hint for stops", MyGear.hint:GetText() == "Click a stop to see every piece it opens.")
suite.check("and the footer explains amber", MyGear.footer:GetText()
    == "Amber gear is for later. The road only lists gear your class can wear.", MyGear.footer:GetText())
road = Road.road
suite.check("the road was read", type(road) == "table" and road.level == 20, road and road.level)
local function Stop(level)
    for index, stop in ipairs(road.stops) do if stop.level == level then return stop, index end end
end
suite.check("Now lists today's helm", Stop(20) and IDs(Stop(20).steps) == "1101", Stop(20) and IDs(Stop(20).steps))
local at24 = Stop(24)
suite.check("a stop at 24 for the better helm", at24 and IDs(at24.steps) == "1301", at24 and IDs(at24.steps))
local at30 = Stop(30)
suite.check("the worse helm at 30 is left out", at30 and IDs(at30.steps) == "1303", at30 and IDs(at30.steps))
suite.check("the goal is last", road.stops[#road.stops].kind == "goal")
local card = Road.cards[1]
suite.check("the first card says NOW", card:IsShown() and card.head:GetText() == "NOW" and card.dot.number:GetText() == "20")
suite.check("and is picked", rawget(card, "picked") == true)
local row = Road.rows[1]
suite.check("the list shows Now's piece", row and row:IsShown() and rawget(row, "pick").itemID == 1101)
suite.check("with its slot and gain", row.slotLabel:GetText() == "Head" and row.gain:GetText():find("%%") ~= nil,
    row.gain:GetText())
local _, index24 = Stop(24)
Click(Road.cards[index24])
row = Road.rows[1]
suite.check("a click on a stop fills the list", Road.picked == index24 and rawget(row, "pick").itemID == 1301)
suite.check("a later piece says its level", row.where:GetText():find("You can wear it from level 24", 1, true) ~= nil,
    row.where:GetText())
suite.check("and can't be a quest yet", rawget(row.button, "dimmed") == true)
Click(Road.cards[#road.stops])
suite.check("the goal card counts done slots", Road.cards[#road.stops].more:GetText():find("of 17 slots done", 1, true) ~= nil,
    Road.cards[#road.stops].more:GetText())
suite.check("the goal list has a piece per slot", #Road.road.stops[#road.stops].steps == 3,
    #Road.road.stops[#road.stops].steps)

-- 5.
judges, scans = 0, 0
Gear:ShowTab("find")
Gear:ShowTab("gear")
suite.check("opened again with nothing changed, nothing is judged", judges == 0 and scans == 0,
    judges .. " " .. scans)
suite.check("it opens on the road again", Road:IsShown())
Gear:Close()
Finder:MarkStale()
scans = 0
MyGear:RefreshSoon()
suite.check("a hidden page starts no scan", scans == 0 and Road:Refresh() == nil, scans)
Gear:Open("gear")

-- 6.
ns.FinderUI:SetSource("vendor", false)
MyGear:Refresh()
suite.check("unticking Vendors leaves out vendor gear", #Road.road.stops == 2
    and #Road.road.stops[1].steps == 0, #Road.road.stops)
suite.check("Now says nothing beats what is worn", Road.cards[1].more:GetText():find("Nothing on offer", 1, true) ~= nil)
ns.FinderUI:SetSource("vendor", true)
MyGear:Refresh()
suite.check("ticked again, it comes back", #Road.road.stops > 2)
MyGear:Ask(1)
suite.check("Alt-click on a slot goes back to the figure", MyGear:View() == "figure"
    and MyGear.figure:IsShown() and not Road:IsShown() and MyGear.side:IsShown())

suite.done()
