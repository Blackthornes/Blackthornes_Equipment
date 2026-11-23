-- "Current step only" (the owner asked 2026-10-13): a saved choice of the
-- old quest panel. The small panel opens and closes its steps with a click
-- (rework step 4), so nothing draws by it now; the choice stays saved and
-- setting it looks for nothing again.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("queststeponly")

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

local Quest = ns.UpgradeQuest

suite.check("off by default", ns.db.upgradeQuestStepOnly == false and not Quest:StepOnly())

ns.HandleSlash("quest quest")
suite.check("the quest reward is picked", Quest:Current() and Quest:Current().itemID == 1002)
local steps = Quest:Steps()
suite.check("the quest has several steps", #steps > 1, #steps)

local scans = 0
local scan = ns.Finder.Scan
ns.Finder.Scan = function(...) scans = scans + 1 return scan(...) end
local refresh = Quest.Refresh
local refreshes = 0
if refresh then Quest.Refresh = function(...) refreshes = refreshes + 1 return refresh(...) end end

Quest:SetStepOnly(true)
suite.check("ticking saves it", ns.db.upgradeQuestStepOnly == true and Quest:StepOnly())
suite.check("and looks for nothing again", scans == 0 and refreshes == 0, scans .. " " .. refreshes)
suite.check("the steps are all still there to open", #(Quest:Steps()) == #steps)

-- The small panel opens and closes its steps with a click, so its menu
-- leaves the line out; the saved choice stays.
local hasLine = false
for _, line in ipairs(ns.SmallPanel:OptionLines()) do
    if line.text == "Current Step Only" then hasLine = line.checked == true end
end
suite.check("the saved choice still reads ticked", hasLine)

Quest:SetStepOnly(false)
suite.check("unticked again", ns.db.upgradeQuestStepOnly == false and not Quest:StepOnly())

ns.Finder.Scan = scan
if refresh then Quest.Refresh = refresh end
suite.done()
