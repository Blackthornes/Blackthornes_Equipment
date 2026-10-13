-- The upgrade quest's step to do now, on a quest in the log, shows that
-- quest as the game's tracker does (the owner asked 2026-10-13): its
-- objectives with their counts, a tick box that tracks it, and a title
-- that opens it in the quest log. Only that quest is read, and the panel
-- draws again when a count moves.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("questprogress")

local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end
local function Gear(loc, n) return { loc = loc, class = 4, subclass = 2, stats = Agi(n) } end

local ITEMS = {
    ["item:900"] = Gear("INVTYPE_CHEST", 10),
    ["item:1002"] = Gear("INVTYPE_CHEST", 30),
}

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitFactionGroup = function() return "Horde", "Horde" end
_G.UnitRace = function() return "Tauren", "Tauren", 6 end
_G.UnitLevel = function() return 10 end
_G.GetRealZoneText = function() return "Mulgore" end
env.InstallItems(ITEMS, { [5] = "item:900" }, { [0] = {} }, 10)

local LOG = {
    { title = "Mulgore", isHeader = true },
    { title = "Supervisor Fizsprocket", questID = 765, level = 12 },
}
local objectives = {
    { text = "Fizsprocket's Clipboard: 0/1", finished = false },
    { text = "Venture Co. Worker slain: 3/12", finished = false },
}
local inLog, ready, watched, opened = {}, {}, {}, nil
local finds = 0
_G.C_QuestLog = {
    IsQuestFlaggedCompleted = function() return false end,
    IsOnQuest = function(id) return inLog[id] == true end,
    ReadyForTurnIn = function(id) return ready[id] == true end,
    IsComplete = function(id) return ready[id] == true end,
    GetNumQuestLogEntries = function() return inLog[765] and #LOG or 1 end,
    GetInfo = function(index) return LOG[index] end,
    GetLogIndexForQuestID = function(id) finds = finds + 1 return inLog[id] and id == 765 and 2 or nil end,
    GetQuestObjectives = function(id) return id == 765 and objectives or nil end,
    GetQuestWatchType = function(id) return watched[id] and 0 or nil end,
    AddQuestWatch = function(id) watched[id] = true end,
    RemoveQuestWatch = function(id) watched[id] = nil end,
}
_G.QuestMapFrame_OpenToQuestDetails = function(id) opened = id end

local S = ns.Sources
ns.Crafts.ITEMS = {}
ns.RollData.ITEMS = {}
S.ZONES = { [215] = "Mulgore" }
S.NPCS = {}
S.QUESTS = { [765] = { "Supervisor Fizsprocket", 5, 12, 178, 0, "Morin Cloudstalker", 215, 51.9, 59.6, "" } }
S.DUNGEONS = {}
S.BOSSES = {}
S.FOREVER = {}
S.STARTS = {}
S.ITEMS = { [1002] = { 5, 12, 0, 0, 0, q = { 765 } } }
S.ENDS = {
    [765] = { "npc", "Morin Cloudstalker", "Mulgore", 51.9, 59.6,
        o = { "mob", "Supervisor Fizsprocket", "Mulgore", 64.9, 43.3, "Fizsprocket's Clipboard" } },
}

local Quest, Panel = ns.UpgradeQuest, ns.QuestPanel

local function Now()
    local steps, current = Quest:Steps()
    return steps[current], current
end

local function NowRow()
    Panel:Refresh()
    for _, row in ipairs(Panel.steps or {}) do
        if rawget(row, "now") == true then return row end
    end
end

local function Shown(row)
    local texts = {}
    for _, label in ipairs(row.objectives) do
        if label:IsShown() then texts[#texts + 1] = label:GetText() end
    end
    return texts
end

ns.HandleSlash("quest quest")
suite.check("the quest reward is picked", Quest:Current() and Quest:Current().itemID == 1002)

-- Not in the log yet: picking it up is the step, and nothing of the log shows.
local step = Now()
suite.check("not in the log, the step has no quest progress", step and step.progress == nil and step.questID == nil)
local row = NowRow()
suite.check("and the row shows no quest", row and not row.questTitle:IsShown() and not row.track:IsShown())
suite.check("no objective lines", row and #Shown(row) == 0)

-- In the log: the step to complete it carries the quest as the log shows it.
inLog[765] = true
finds = 0
step = Now()
suite.check("in the log, the step names its quest", step.questID == 765, step.text)
suite.check("read for that one quest by its log index", finds >= 1 and step.progress and step.progress.index == 2)
suite.check("with its objectives and counts", step.progress and #step.progress.objectives == 2
    and step.progress.objectives[2].text == "Venture Co. Worker slain: 3/12")
suite.check("not tracked yet", step.progress and step.progress.tracked == false)

row = NowRow()
suite.check("the row shows the quest's title", row.questTitle:IsShown()
    and row.questTitle.label:GetText():find("[12] Supervisor Fizsprocket", 1, true) ~= nil,
    row.questTitle.label:GetText())
local texts = Shown(row)
suite.check("and its objectives as x/y lines", #texts == 2 and texts[1] == "- Fizsprocket's Clipboard: 0/1"
    and texts[2] == "- Venture Co. Worker slain: 3/12", table.concat(texts, " / "))
suite.check("the track box is shown, unticked", row.track:IsShown() and not row.track:GetChecked())

-- Only the step to do now gets it.
local others = 0
for _, other in ipairs(Panel.steps) do
    if other ~= row and other.questTitle:IsShown() then others = others + 1 end
end
suite.check("no other step shows a quest", others == 0, others)

-- The tick box tracks it, the way the game's tracker does.
row.track:GetScript("OnClick")(row.track)
suite.check("ticking tracks the quest", watched[765] == true)
row = NowRow()
suite.check("and the box stays ticked", row.track:GetChecked() == true)
row.track:GetScript("OnClick")(row.track)
suite.check("unticking stops tracking it", watched[765] == nil)

-- A click on the title opens it in the quest log.
row.questTitle:GetScript("OnClick")(row.questTitle, "LeftButton")
suite.check("a click on the title opens the quest in the log", opened == 765, tostring(opened))
suite.check("the title explains the click", pcall(row.questTitle:GetScript("OnEnter"), row.questTitle))

-- A count moving changes what the panel shows, so a quest log event draws it again.
local before = Quest:Shows((Quest:Steps()))
objectives[2] = { text = "Venture Co. Worker slain: 4/12", finished = false }
suite.check("a count moving changes what is shown", Quest:Shows((Quest:Steps())) ~= before)
objectives[1] = { text = "Fizsprocket's Clipboard: 1/1", finished = true }
row = NowRow()
texts = Shown(row)
suite.check("a done objective is ticked", texts[1] and texts[1]:find("ReadyCheck-Ready", 1, true) ~= nil
    and texts[2] == "- Venture Co. Worker slain: 4/12", table.concat(texts, " / "))

-- Done: the hand-in is the step, and the quest says it is ready.
ready[765] = true
step = Now()
suite.check("ready, the hand-in step still shows the quest", step.questID == 765 and step.turnIn == true, step.text)
row = NowRow()
texts = Shown(row)
suite.check("saying who to hand it to", #texts == 1 and texts[1] == "- Ready to hand in to Morin Cloudstalker",
    table.concat(texts, " / "))

-- A client that cannot find it by ID still finds it by reading the log.
local byID = _G.C_QuestLog.GetLogIndexForQuestID
_G.C_QuestLog.GetLogIndexForQuestID = nil
local found = ns.QuestLog:Find(765)
suite.check("found by reading the log", found and found.questID == 765 and found.index == 2)
suite.check("a quest not in the log is nil", ns.QuestLog:Find(999) == nil)
_G.C_QuestLog.GetLogIndexForQuestID = byID

-- A client that raises gives no progress, and the step still shows.
_G.C_QuestLog.GetInfo = function() error("secret") end
step = Now()
suite.check("an error reading the log leaves the step without progress", step and step.progress == nil)
row = NowRow()
suite.check("and the row hides the quest", row and not row.questTitle:IsShown())

suite.done()
