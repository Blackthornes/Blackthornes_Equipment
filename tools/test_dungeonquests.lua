-- Dungeon Quests (the owner said build it, 2026-10-20): every dungeon and
-- raid quest, Classic's from Data/DungeonQuests.lua and Forever's own
-- learned from the quest log, with Done, In Log or To Do for each.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("dungeonquests")

local ns = env.Load()
for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end

local DQ, UI = ns.DungeonQuests, ns.DungeonQuestsUI

local count = 0
for _ in pairs(ns.DUNGEON_QUESTS) do count = count + 1 end
suite.check("the data has Classic's dungeon quests", count > 100, count)
local unknown = 0
for _, q in pairs(ns.DUNGEON_QUESTS) do
    if not DQ.Dungeon(q[1]) then unknown = unknown + 1 end
end
suite.check("every quest names a dungeon the addon knows", unknown == 0, unknown)

-- A pretend data set and character, so the counts can be checked.
local realData = ns.DUNGEON_QUESTS
ns.DUNGEON_QUESTS = {
    [1] = { "389", "Searching for the Lost Satchel", 9, 16, "H", 0, "Rahauro", "Thunder Bluff", 70, 30, 0, 0 },
    [2] = { "389", "Hidden Enemies", 10, 16, "H", 0, "Thrall", "Orgrimmar", 31, 37, 5000, 0 },
    [3] = { "389", "Slaying the Beast", 9, 16, "H", 0, "Neeru Fireblade", "Orgrimmar", 49, 50, 0, 0 },
    [4] = { "36", "Red Silk Bandanas", 14, 17, "A", 0, "Scout Riell", "Westfall", 56, 47, 0, 0 },
    [5] = { "389", "Only Mages", 9, 16, "", 128, "A Trainer", "Orgrimmar", 40, 40, 0, 0 },
    [6] = { "209", "Far Ahead", 44, 47, "H", 0, "Someone", "Tanaris", 50, 50, 0, 0 },
}
DQ.version = (DQ.version or 0) + 1
local player = { level = 14, faction = "H", classBit = 1 }
ns.Finder.Player = function() return player end
local doneIDs = { [1] = true }
ns.Finder.QuestDone = function(_, id) return doneIDs[id] == true end
local logLines = {}
ns.QuestLog.Size = function() return #logLines, "retail" end
ns.QuestLog.Line = function(index) return logLines[index] end
logLines = { { header = true, title = "Ragefire Chasm" }, { questID = 2, title = "Hidden Enemies", level = 16 } }
DQ.logStale = true

local data = DQ:Build()
suite.check("only this side's and class's quests at this level",
    data.all == 3 and #data.dungeons == 1, data.all .. " in " .. #data.dungeons)
local rfc = data.dungeons[1]
suite.check("the dungeon is Ragefire Chasm", rfc and rfc.name == "Ragefire Chasm", rfc and rfc.name)
local statuses = {}
for _, q in ipairs(rfc.quests) do statuses[q.questID] = q.status end
suite.check("done, in the log and to do", statuses[1] == "done" and statuses[2] == "log" and statuses[3] == "todo")
suite.check("one of three done", data.done == 1 and rfc.done == 1)

DQ:SetMyLevelOnly(false)
data = DQ:Build()
local seen = {} for _, d in ipairs(data.dungeons) do for _, q in ipairs(d.quests) do seen[#seen+1] = q.questID end end
suite.check("My Level Only off shows quests far past or ahead", data.all == 4, data.all .. ":" .. table.concat(seen, ",") .. ":" .. tostring(DQ.MyLevelOnly()))
suite.check("My Level Only is saved as false only", ns.db.dungeonQuestsMyLevel == false)
DQ:SetMyLevelOnly(true)
suite.check("on again leaves nothing saved", ns.db.dungeonQuestsMyLevel == nil)

DQ:SetHideDone(true)
data = DQ:Build()
suite.check("Hide Done takes the row out but keeps the count",
    #data.dungeons[1].quests == 2 and data.done == 1 and data.all == 3)
DQ:SetHideDone(false)

suite.check("the start line names who and where",
    DQ.From(DQ:All()[2]) == "Thrall, Orgrimmar", DQ.From(DQ:All()[2]))
suite.check("the place it starts", DQ.Place(DQ:All()[2]).zone == "Orgrimmar")

-- Learning Forever's own: a quest under a Forever dungeon's heading.
local forever, foreverName
for key, place in pairs(ns.FOREVER_DUNGEON_PLACES) do forever, foreverName = key, place[1] break end
logLines = {
    { header = true, title = foreverName },
    { questID = 900001, title = "A New Forever Quest", level = 20 },
    { header = true, title = "Elwynn Forest" },
    { questID = 900002, title = "Not a Dungeon Quest", level = 5 },
}
DQ:LearnLog()
local store = ns.db.learnedDungeonQuests or {}
suite.check("a quest under a dungeon heading is learned",
    store[900001] and store[900001].dungeon == forever and store[900001].title == "A New Forever Quest")
suite.check("a quest under a zone heading is not", store[900002] == nil)
suite.check("a quest the data has is never learned again", not DQ:Learn(2, "389", { title = "Hidden Enemies" }))
player.level = 20
data = DQ:Build()
local found
for _, d in ipairs(data.dungeons) do if d.key == forever then found = d end end
suite.check("the learned quest shows under its dungeon", found and #found.quests == 1 and found.forever)
suite.check("Forever's own dungeons come last", data.dungeons[#data.dungeons].key == forever)

-- Accepted inside a dungeon, with no heading over it.
_G.GetInstanceInfo = function() return "Ragefire Chasm", "party", 1, "", 5, 0, false, 389 end
logLines = { { questID = 900003, title = "Picked Up Inside", level = 15 } }
DQ:LearnLog(900003)
suite.check("a quest accepted inside a dungeon is learned for it",
    ns.db.learnedDungeonQuests[900003] and ns.db.learnedDungeonQuests[900003].dungeon == "389")
_G.GetInstanceInfo = nil

-- The window.
player.level = 14
UI:Show()
suite.check("the window opens", UI.frame and UI.frame:IsShown())
suite.check("it picks a dungeon with something to do", ns.db.dungeonQuestsPick ~= nil)
UI:Pick("389")
suite.check("the total reads as a count", UI.total:GetText() ~= nil and UI.total:GetText():find("of") ~= nil,
    UI.total:GetText())
local shown = 0
for _, row in ipairs(UI.questRows) do if row:IsShown() then shown = shown + 1 end end
suite.check("its quests show", shown == 3, shown)
UI.questRows[2]:GetScript("OnClick")(UI.questRows[2])
suite.check("a picked quest says where it starts", UI.foot:GetText():find("Orgrimmar", 1, true) ~= nil
    or UI.foot:GetText():find("Thunder Bluff", 1, true) ~= nil, UI.foot:GetText())
UI:Hide()
suite.check("the window closes", not UI.frame:IsShown())

ns.HandleSlash("dungeons")
suite.check("/beq dungeons opens it", UI.frame:IsShown())
UI:Hide()
suite.check("the gear window has a Dungeon Quests button", ns.UI.dungeonButton ~= nil or ns.UI.frame == nil)

ns.DUNGEON_QUESTS = realData
suite.check("the probe line reads", type(DQ:Describe()) == "string")

suite.done()
