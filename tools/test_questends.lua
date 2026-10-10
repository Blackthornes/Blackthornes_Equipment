-- A quest in the log sends the player to its objective, or to whoever takes
-- it back, never back to its giver (asked 2026-10-08: on The Ravaged
-- Caravan the arrow said "Morin Cloudstalker, Step 1" while the step was
-- to go to the caravan).

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("questends")

local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end
local function Gear(loc, n) return { loc = loc, class = 4, subclass = 2, stats = Agi(n) } end

local ITEMS = {
    ["item:900"] = Gear("INVTYPE_CHEST", 10),   -- worn
    ["item:1002"] = Gear("INVTYPE_CHEST", 30),  -- Goblin Smasher stands in
}

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitFactionGroup = function() return "Horde", "Horde" end
_G.UnitRace = function() return "Tauren", "Tauren", 6 end
_G.GetRealZoneText = function() return "Mulgore" end
env.InstallItems(ITEMS, { [5] = "item:900" }, { [0] = {} }, 10)

local inLog, ready, done = {}, {}, {}
_G.C_QuestLog = {
    IsQuestFlaggedCompleted = function(id) return done[id] == true end,
    IsOnQuest = function(id) return inLog[id] == true end,
    ReadyForTurnIn = function(id) return ready[id] == true end,
}

local S = ns.Sources
ns.Crafts.ITEMS = {}
ns.RollData.ITEMS = {}
S.ZONES = { [215] = "Mulgore" }
S.NPCS = {}
S.QUESTS = {
    [749] = { "The Ravaged Caravan", 5, 8, 178, 0, "Morin Cloudstalker", 215, 51.9, 59.6, "" },
    [751] = { "The Ravaged Caravan", 5, 8, 178, 0, "Sealed Supply Crate", 215, 53.7, 48.2, "The Ravaged Caravan", p = 749 },
    [765] = { "Supervisor Fizsprocket", 5, 12, 178, 0, "Morin Cloudstalker", 215, 51.9, 59.6, "The Ravaged Caravan", p = 751 },
}
S.DUNGEONS = {}
S.BOSSES = {}
S.FOREVER = {}
S.STARTS = {}
S.ITEMS = { [1002] = { 5, 12, 0, 0, 0, q = { 765 } } }
S.ENDS = {
    [749] = { "object", "Sealed Supply Crate", "Mulgore", 53.7, 48.2 },
    [751] = { "npc", "Morin Cloudstalker", "Mulgore", 51.9, 59.6 },
    [765] = { "npc", "Morin Cloudstalker", "Mulgore", 51.9, 59.6,
        o = { "mob", "Supervisor Fizsprocket", "Mulgore", 64.9, 43.3, "Fizsprocket's Clipboard" } },
}

local Quest = ns.UpgradeQuest
local Arrow = ns.QuestArrow

local function Texts()
    local texts = {}
    for _, step in ipairs((Quest:Steps())) do texts[#texts + 1] = step.text end
    return table.concat(texts, " | ")
end

local function Now()
    local steps, current = Quest:Steps()
    return steps[current], current
end

-- The panel's marks: the header's and the step to do now (asked
-- 2026-10-10: a quest done shows the game's ? like over a quest giver).
local Panel = ns.QuestPanel
local marks, spied = {}, {}
local function Marks()
    Panel:Refresh()
    local mark
    for _, row in ipairs(Panel.steps or {}) do
        if rawget(row, "now") == true then mark = marks[row] end
    end
    return Panel.badgeTexture, mark
end
local function SpyMarks()
    for _, row in ipairs(Panel.steps or {}) do
        if not spied[row] then
            spied[row] = true
            row.mark.SetTexture = function(_, texture) marks[row] = texture end
        end
    end
end

ns.HandleSlash("quest quest")
local quest = Quest:Current()
suite.check("the quest reward is picked", quest and quest.itemID == 1002)

-- Not started: the giver is the place.
local step, current = Now()
suite.check("not started, pick up the first quest from its giver",
    step.text == "Do The Ravaged Caravan: pick it up from Morin Cloudstalker in Mulgore (51.9, 59.6)", step.text)
suite.check("the second part says it is the next part",
    Texts():find("Then do the next part of The Ravaged Caravan: pick it up from Sealed Supply Crate", 1, true) ~= nil,
    Texts())

-- The first quest in the log (where the player was): the crate, not Morin.
inLog[749] = true
step, current = Now()
suite.check("in the log, it is done and handed in at the crate",
    step.text == "Complete The Ravaged Caravan (level 8) and hand it in at Sealed Supply Crate in Mulgore (53.7, 48.2)",
    step.text)
suite.check("never 'pick it up' for a quest in the log", not step.text:find("pick it up", 1, true))
suite.check("its place is the crate", step.place and step.place.name == "Sealed Supply Crate"
    and step.place.x == 53.7, step.place and step.place.name)
local place = Quest:NextPlace()
suite.check("the map pin goes to the crate", place and place.name == "Sealed Supply Crate", place and place.name)
local places = Arrow:Places()
suite.check("the arrow's first place is the crate, on the step it belongs to",
    places[1] and places[1].name == "Sealed Supply Crate" and places[1].step == current,
    places[1] and (places[1].name .. " step " .. tostring(places[1].step)))
for _, p in ipairs(places) do
    if p.name == "Morin Cloudstalker" then
        suite.check("Morin comes later, on a later step", p.step > current, p.step)
    end
end

-- Handed in: the second part, picked up at the crate, goes back to Morin.
inLog[749], done[749] = nil, true
step = Now()
suite.check("next, pick up the second part at the crate",
    step.text:find("pick it up from Sealed Supply Crate", 1, true) ~= nil, step.text)
inLog[751] = true
step = Now()
suite.check("in the log, it goes back to Morin",
    step.text == "Complete The Ravaged Caravan (level 8) and hand it in to Morin Cloudstalker in Mulgore (51.9, 59.6)",
    step.text)
suite.check("not ready, no ?", not step.turnIn)

-- The reward quest: the objective, then who takes it back.
inLog[751], done[751] = nil, true
inLog[765] = true
step = Now()
suite.check("the reward quest's objective is where to go",
    step.text == "Complete Supervisor Fizsprocket (level 12): collect Fizsprocket's Clipboard from Supervisor Fizsprocket in Mulgore (64.9, 43.3)",
    step.text)
suite.check("with its spot", step.place and step.place.name == "Supervisor Fizsprocket" and step.place.x == 64.9)
-- The objective's step clicked on the panel: the arrow is pinned there.
local objective = select(2, Now())
Arrow:Aim(objective)
local target = Arrow:Targets(Quest:Current())[1]
suite.check("a clicked step goes first", target and target.name == "Supervisor Fizsprocket", target and target.name)
ready[765] = true
step = Now()
suite.check("ready, hand it in to Morin", step.text == "Hand it in to Morin Cloudstalker (51.9, 59.6) and choose item:1002",
    step.text)
suite.check("the hand-in is marked ready", step.turnIn == true)
Panel:Refresh()
SpyMarks()
local badge, mark = Marks()
suite.check("the header shows the ?", badge == Panel.TURN_IN_ICON, badge)
suite.check("so does the step", mark == Panel.TURN_IN_ICON, mark)
suite.check("and the arrow goes there", (Quest:NextPlace() or {}).name == "Morin Cloudstalker")
-- The objective met: the clicked step moved on, so the arrow follows the
-- steps again without another click (asked 2026-10-10).
target = Arrow:Targets(Quest:Current())[1]
suite.check("the dial lets go of the objective it was pinned to", target and target.name == "Morin Cloudstalker",
    target and target.name)
suite.check("and forgets the pin", Arrow.pinned == nil)
Arrow:SetOn(false)

-- A chain quest ready to hand in says so.
inLog[765], ready[765], done[751] = nil, nil, nil
inLog[751], ready[751] = true, true
step = Now()
suite.check("a chain quest ready to hand in",
    step.text == "Hand in The Ravaged Caravan to Morin Cloudstalker in Mulgore (51.9, 59.6)", step.text)
suite.check("is marked ready", step.turnIn == true)
SpyMarks()
badge, mark = Marks()
suite.check("the header shows the ? for it", badge == Panel.TURN_IN_ICON, badge)
suite.check("and the step", mark == Panel.TURN_IN_ICON, mark)

-- Nothing known about where it ends: no place made up.
S.ENDS[751] = nil
ready[751] = nil
step = Now()
suite.check("nothing known, just complete it", step.text == "Complete The Ravaged Caravan (level 8)", step.text)
suite.check("with no place, not the giver's", step.place == nil)
SpyMarks()
badge, mark = Marks()
suite.check("back to the ! while there is work to do", badge == Panel.QUEST_ICON, badge)
suite.check("on the step too", mark ~= Panel.TURN_IN_ICON, mark)

suite.done()
