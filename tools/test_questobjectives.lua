-- A quest with several objectives (Warsong Supplies: four items from four
-- places) moves on once the log shows one done: the step, the arrow and
-- the map pin go to the next objective not done yet, and the step is done
-- only when the quest is ready to hand in.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("questobjectives")

local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end
local function Gear(loc, n) return { loc = loc, class = 4, subclass = 2, stats = Agi(n) } end

local ITEMS = {
    ["item:900"] = Gear("INVTYPE_FEET", 10),
    ["item:1002"] = Gear("INVTYPE_FEET", 30),
}

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitFactionGroup = function() return "Horde", "Horde" end
_G.UnitRace = function() return "Tauren", "Tauren", 6 end
_G.UnitLevel = function() return 26 end
_G.GetRealZoneText = function() return "Ashenvale" end
env.InstallItems(ITEMS, { [8] = "item:900" }, { [0] = {} }, 26)

local LOG = {
    { title = "Ashenvale", isHeader = true },
    { title = "Warsong Supplies", questID = 6571, level = 27 },
}
local objectives = {
    { text = "Warsong Saw Blades: 0/1", finished = false },
    { text = "Warsong Axe Shipment: 0/1", finished = false },
    { text = "Warsong Oil: 0/1", finished = false },
    { text = "Logging Rope: 0/1", finished = false },
}
local inLog, ready = {}, {}
_G.C_QuestLog = {
    IsQuestFlaggedCompleted = function() return false end,
    IsOnQuest = function(id) return inLog[id] == true end,
    ReadyForTurnIn = function(id) return ready[id] == true end,
    IsComplete = function(id) return ready[id] == true end,
    GetNumQuestLogEntries = function() return inLog[6571] and #LOG or 1 end,
    GetInfo = function(index) return LOG[index] end,
    GetLogIndexForQuestID = function(id) return inLog[id] and id == 6571 and 2 or nil end,
    GetQuestObjectives = function(id) return id == 6571 and objectives or nil end,
    GetQuestWatchType = function() return nil end,
}

local S = ns.Sources
ns.Crafts.ITEMS = {}
ns.RollData.ITEMS = {}
S.ZONES = { [331] = "Ashenvale" }
S.NPCS = {}
S.QUESTS = { [6571] = { "Warsong Supplies", 22, 27, 178, 0, "Locke Okarr", 331, 71.4, 67.6, "" } }
S.DUNGEONS = {}
S.BOSSES = {}
S.FOREVER = {}
S.STARTS = {}
S.ITEMS = { [1002] = { 22, 27, 0, 0, 0, q = { 6571 } } }
S.ENDS = {
    [6571] = { "npc", "Locke Okarr", "Ashenvale", 71.4, 67.6,
        o = { "mob", "Foulweald Den Watcher", "Ashenvale", 53.8, 62, "Logging Rope" },
        m = { { "object", "Warsong Oil", "Ashenvale", 79.5, 50.7, "Warsong Oil" },
            { "object", "Warsong Axe Shipment", "Stranglethorn Vale", 26.4, 73.3, "Warsong Axe Shipment" } } },
}

local Quest = ns.UpgradeQuest

local function Now()
    local steps, current = Quest:Steps()
    return steps[current], current
end

ns.HandleSlash("quest quest")
suite.check("the quest reward is picked", Quest:Current() and Quest:Current().itemID == 1002)

local ender = Quest.Ender(6571)
suite.check("every objective's place is read", ender and #ender.goals == 4
    and ender.goal == ender.goals[1] and ender.goals[2].name == "Warsong Oil")
suite.check("the saw blades come last, from Pixel, for a Deadly Blunderbuss", ender.goals[4].name == "Pixel"
    and ender.goals[4].item == "Warsong Saw Blades" and ender.goals[4].wants == 4369
    and ender.goals[4].x == 73.1 and ender.goals[4].y == 61.5)

-- The Deadly Blunderbuss: a step to have one on hand, before the quest's work.
local function Find(text)
    for index, row in ipairs((Quest:Steps())) do
        if row.text:find(text, 1, true) then return row, index end
    end
end
local realCount = Quest.Count
local gun, gunAt = Find("Deadly Blunderbuss for Pixel")
local _, completeAt = Find("Complete Warsong Supplies")
suite.check("a step says to get a Deadly Blunderbuss for Pixel", gun ~= nil and gun.done == false
    and gun.text:find("auction house", 1, true) ~= nil and gun.text:find("an engineer", 1, true) == nil,
    gun and gun.text)
suite.check("it comes before the quest's work", gunAt and completeAt and gunAt < completeAt)
ns.Crafts.ITEMS[4369] = { 202, 105, 3936, 16, 21, 0, 0, 0, m = {} }
gun = Find("Deadly Blunderbuss for Pixel")
suite.check("an engineer can make it", gun and gun.text:find("ask an engineer to make it", 1, true) ~= nil,
    gun and gun.text)
local realKnows, realPrice = ns.Crafting.Knows, ns.Crafting.AuctionPrice
ns.Crafting.AuctionPrice = function() return 21000 end
gun = Find("Deadly Blunderbuss for Pixel")
suite.check("the auction price shows under it when known", gun and gun.note
    and gun.note:find("auction house", 1, true) ~= nil, gun and gun.note)
ns.Crafting.Knows = function(_, spell) return spell == 3936 end
gun = Find("Make a")
suite.check("knowing the recipe, the step is to make it", gun and gun.text:find("Deadly Blunderbuss", 1, true)
    and gun.text:find("for Pixel", 1, true) and gun.note == nil, gun and gun.text)
ns.Crafting.Knows, ns.Crafting.AuctionPrice = realKnows, realPrice
Quest.Count = function(id) return id == 4369 and 1 or realCount(id) end
gun = Find("Deadly Blunderbuss for Pixel")
suite.check("with one in the bags, the step is done", gun and gun.done == true)
Quest.Count = realCount

-- Not in the log: the step shows the first objective, as before.
local step = Now()
suite.check("before the quest is taken, the step is to pick it up", step.text:find("Pick up", 1, true) ~= nil, step.text)

inLog[6571] = true
step = Now()
suite.check("in the log, the first objective comes first", step.text:find("Logging Rope", 1, true) ~= nil
    and step.place and step.place.name == "Foulweald Den Watcher", step.text)

-- Logging Rope collected: on to the next objective not done.
local before = Quest:Shows((Quest:Steps()))
objectives[4] = { text = "Logging Rope: 1/1", finished = true }
step = Now()
suite.check("one objective done moves the step on", step.text:find("Warsong Oil", 1, true) ~= nil
    and step.text:find("Logging Rope", 1, true) == nil, step.text)
suite.check("and the place with it", step.place and step.place.name == "Warsong Oil"
    and step.place.x == 79.5 and step.place.y == 50.7)
suite.check("the step is not done yet", step.done == false)
local place = Quest:NextPlace()
suite.check("the map pin and arrow go to the next objective", place and place.name == "Warsong Oil",
    place and place.name)
suite.check("what is shown changes, so the panel draws again", Quest:Shows((Quest:Steps())) ~= before)

objectives[3] = { text = "Warsong Oil: 1/1", finished = true }
step = Now()
suite.check("then the next one", step.place and step.place.name == "Warsong Axe Shipment", step.text)

-- The rest done, the saw blades are left: bring Pixel the gun.
objectives[2] = { text = "Warsong Axe Shipment: 1/1", finished = true }
Quest.Count = function(id) return id == 4369 and 1 or realCount(id) end
step = Now()
suite.check("last, the step is to bring Pixel the gun", step.text:find("Complete Warsong Supplies", 1, true) ~= nil
    and step.text:find("Deadly Blunderbuss to Pixel", 1, true) ~= nil
    and step.text:find("Warsong Saw Blades", 1, true) ~= nil and step.done == false, step.text)
suite.check("and the arrow goes to Pixel", step.place and step.place.name == "Pixel" and step.place.x == 73.1)
Quest.Count = realCount
objectives[1] = { text = "Warsong Saw Blades: 1/1", finished = true }
gun = Find("Deadly Blunderbuss for Pixel")
suite.check("with the saw blades, the gun step is done", gun and gun.done == true)

-- Every known place done, one objective left the data has no place for:
-- no made-up spot, the step still waits.
local trades = Quest.TRADES[6571]
Quest.TRADES[6571] = nil
objectives[1] = { text = "Warsong Saw Blades: 0/1", finished = false }
step = Now()
suite.check("with no place left, the step names only the quest", step.text:find("Complete Warsong Supplies", 1, true) ~= nil
    and step.place == nil and step.done == false, step.text)
Quest.TRADES[6571] = trades

-- All done: the hand-in.
objectives[1] = { text = "Warsong Saw Blades: 1/1", finished = true }
ready[6571] = true
step = Now()
suite.check("ready, the hand-in is the step", step.turnIn == true and step.text:find("Locke Okarr", 1, true) ~= nil, step.text)

-- The quest log tab's place follows the same rule.
ready[6571] = nil
objectives[1] = { text = "Warsong Saw Blades: 0/1", finished = false }
objectives[3] = { text = "Warsong Oil: 0/1", finished = false }
local line = ns.QuestLog:Find(6571)
local spot = ns.QuestLog.Place(line)
suite.check("the quest log tab aims at the next objective too", spot and spot.name == "Warsong Oil", spot and spot.name)

-- Lines the data's names don't match (another language) leave the first place.
local german = { { text = "Holzfällerseil: 1/1", done = true } }
suite.check("an objective that names nothing known keeps the first place",
    Quest.OpenGoal(ender, german) == ender.goals[1])
suite.check("no log lines keep the first place", Quest.OpenGoal(ender, nil) == ender.goals[1])
suite.check("a mob objective matches by its name", Quest.OpenGoal(
    { goals = { { name = "Kobold Vermin" }, { name = "Kobold Worker" } } },
    { { text = "Kobold Vermin slain: 10/10", done = true } }).name == "Kobold Worker")

-- A quest with one objective reads as before.
S.ENDS[6571].m = nil
Quest.TRADES[6571] = nil
ender = Quest.Ender(6571)
suite.check("one objective: one place", #ender.goals == 1 and ender.goal.name == "Foulweald Den Watcher")

suite.done()
