-- The quest filters. "Solo quests only": quests that need a group, a
-- dungeon, a raid or a battleground, or come after one that does, are left
-- out of the finder and the upgrade quest while it is ticked. "Quest
-- level": quests more than so many levels above the character are too.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("soloquests")

local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end
local function Chest(n) return { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = Agi(n) } end

local ITEMS = {
    ["item:900"] = Chest(10),    -- worn
    ["item:1001"] = Chest(20),   -- a vendor's
    ["item:1002"] = Chest(30),   -- a quest done alone
    ["item:1003"] = Chest(50),   -- a dungeon quest's
    ["item:1004"] = Chest(40),   -- a quest after a group quest
    ["item:1005"] = Chest(60),   -- a quest seven levels up
}

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitRace = function() return "Human", "Human", 1 end
_G.GetRealZoneText = function() return "Elwynn Forest" end
env.InstallItems(ITEMS, { [5] = "item:900" }, { [0] = {} }, 20)
_G.C_QuestLog = { IsQuestFlaggedCompleted = function() return false end }

local S = ns.Sources
ns.Crafts.ITEMS = {}
ns.RollData.ITEMS = {}
S.ZONES = { [12] = "Elwynn Forest" }
S.NPCS = { [1] = { "Corina Steele", 12, 41.5, 65.9, "A" } }
S.QUESTS = {
    [10] = { "Wolves of the Forest", 15, 18, 0, 0, "Marshal Dughan", 12, 42.1, 65.9, "" },
    [11] = { "The Defias Brotherhood", 15, 22, 0, 0, "Gryan Stoutmantle", 12, 40, 40, "", "dungeon" },
    [12] = { "After the Bandits", 15, 18, 0, 0, "Someone", 12, 40, 40, "Bandit Camp", p = 13 },
    [13] = { "Bandit Camp", 15, 18, 0, 0, "Someone", 12, 40, 40, "", "group" },
    [14] = { "Far Too Hard", 15, 27, 0, 0, "Someone", 12, 40, 40, "" },
}
S.DUNGEONS = {}
S.BOSSES = {}
S.FOREVER = {}
S.ITEMS = {
    [1001] = { 15, 18, 0, 0, 500, v = { 1, 0 } },
    [1002] = { 15, 18, 0, 0, 0, q = { 10 } },
    [1003] = { 15, 18, 0, 0, 0, q = { 11 } },
    [1004] = { 15, 18, 0, 0, 0, q = { 12 } },
    [1005] = { 15, 18, 0, 0, 0, q = { 14 } },
}

local Finder, Quest = ns.Finder, ns.UpgradeQuest

local function Offered()
    local ids = {}
    for _, pick in ipairs(Finder:Scan().slots[5] or {}) do ids[#ids + 1] = pick.itemID end
    return table.concat(ids, ",")
end

--------------------------------------------------------------------------------
-- Telling them apart
--------------------------------------------------------------------------------

suite.check("off by default", ns.db.soloQuestsOnly == false and not Finder:SoloOnly())
suite.check("every quest is offered", Offered() == "1003,1004,1002", Offered())

local player = Finder:Player()
local dungeon = Finder:SourcesFor(1003, player)[1]
suite.check("a dungeon quest is marked", dungeon.group == "dungeon" and not Finder.Solo(dungeon))
suite.check("and says so", Finder:Describe(dungeon):find("(level 22), dungeon,", 1, true) ~= nil,
    Finder:Describe(dungeon))
local after = Finder:SourcesFor(1004, player)[1]
suite.check("a quest after a group quest is not solo", after.chainGroup == "group" and not Finder.Solo(after))
suite.check("a quest done alone is", Finder.Solo(Finder:SourcesFor(1002, player)[1]))
suite.check("a vendor always is", Finder.Solo(Finder:SourcesFor(1001, player)[1]))
suite.check("an unknown mark counts as alone", Finder.Need("") == nil and Finder.Need("nonsense") == nil)

--------------------------------------------------------------------------------
-- The setting, ticked from anywhere
--------------------------------------------------------------------------------

local UI = ns.FinderUI
Finder:SetSoloOnly(true)
suite.check("ticking it saves it", ns.db.soloQuestsOnly == true and Finder:SoloOnly())
suite.check("group and dungeon quests are gone", Offered() == "1002,1001", Offered())

ns.SettingsUI:Show()
suite.check("Settings shows it ticked", ns.SettingsUI.controls.soloQuests:GetChecked())
ns.SettingsUI.controls.soloQuests:GetScript("OnClick")(ns.SettingsUI.controls.soloQuests)
suite.check("unticked in Settings", ns.db.soloQuestsOnly == false)
suite.check("the list follows", Offered() == "1003,1004,1002", Offered())
ns.SettingsUI:Hide()

--------------------------------------------------------------------------------
-- The upgrade quest
--------------------------------------------------------------------------------

Quest:SetEnabled(true)
Quest:SelectTab("quest")
local quest = Quest:QuestOn("quest")
suite.check("the quest tab picks the dungeon quest", quest and quest.itemID == 1003, quest and quest.itemID)
local texts = {}
for _, step in ipairs((Quest:Steps())) do texts[#texts + 1] = step.note or "" end
suite.check("its step says it is done in a dungeon",
    table.concat(texts, "|"):find("Done in a dungeon, so bring a group.", 1, true) ~= nil, table.concat(texts, "|"))

Finder:SetSoloOnly(true)
quest = Quest:QuestOn("quest")
suite.check("ticked, the quest tab lets it go and picks a solo one", quest and quest.itemID == 1002,
    quest and quest.itemID)
suite.check("the dungeon quest is not counted as skipped", not Quest:Skipped()[1003])

Finder:SetSoloOnly(false)
quest = Quest:QuestOn("quest")
suite.check("unticked, the solo quest is kept", quest and quest.itemID == 1002, quest and quest.itemID)

--------------------------------------------------------------------------------
-- Quest level
--------------------------------------------------------------------------------

suite.check("quests up to 4 levels up by default", Finder:QuestLevelsAbove() == 4 and ns.db.questLevelsAbove == 4)
suite.check("so the level 27 quest is left out at 20", not Offered():find("1005"), Offered())
suite.check("its words", UI.QuestLevelsText(0) == "Up to my level" and UI.QuestLevelsText(11) == "Any"
    and UI.QuestLevelsText(7) == "Up to +7")

Finder:SetQuestLevelsAbove(0)
suite.check("up to my level leaves out the level 22 quest too", Offered() == "1004,1002,1001", Offered())
Finder:SetQuestLevelsAbove(7)
suite.check("seven up lets the level 27 quest in", Offered():find("1005") ~= nil, Offered())
Finder:SetQuestLevelsAbove(Finder.QUEST_LEVELS_ANY)
suite.check("Any is no limit", Finder:QuestLevelsAbove() == nil and Offered():find("1005") ~= nil)
suite.check("and is saved", ns.db.questLevelsAbove == 11)

-- The upgrade quest follows it.
Quest:Skip()
quest = Quest:QuestOn("quest")
suite.check("with any level, the quest tab takes the level 27 quest", quest and quest.itemID == 1005,
    quest and quest.itemID)
Finder:SetQuestLevelsAbove(4)
quest = Quest:QuestOn("quest")
suite.check("brought back to +4, it lets it go and picks again", quest and quest.itemID == 1003,
    quest and quest.itemID)

--------------------------------------------------------------------------------
-- Dungeon quests the quest data does not mark (the owner, 2026-11-23: a
-- dungeon quest line's reward was offered with Solo Quests Only ticked).
-- Quests learned in game, and some Classic ones, carry no mark of their
-- own; the dungeon quest lists still say where they are done.
--------------------------------------------------------------------------------

ITEMS["item:1006"] = Chest(70)
ITEMS["item:1007"] = Chest(80)
ITEMS["item:1008"] = Chest(90)
env.InstallItems(ITEMS, { [5] = "item:900" }, { [0] = {} }, 20)
S.DUNGEONS = { ["36"] = { "The Deadmines", 17, 26, "Elwynn Forest", "" },
    ["99"] = { "Molten Core", 60, 60, "Elwynn Forest", "", true } }
-- Learned on Forever: no mark, but on Forever's dungeon quest list.
S.QUESTS[20] = { "Into the Mine", 15, 18, 0, 0, "Someone", 12, 40, 40, "", learned = true }
-- Classic, no mark, but on the Classic dungeon quest list; its reward
-- comes from the next quest in the line.
S.QUESTS[21] = { "Down Below", 15, 18, 0, 0, "Someone", 12, 40, 40, "" }
S.QUESTS[22] = { "Back to Town", 15, 18, 0, 0, "Someone", 12, 40, 40, "Down Below", p = 21 }
S.QUESTS[23] = { "The Core", 15, 18, 0, 0, "Someone", 12, 40, 40, "" }
S.ITEMS[1006] = { 15, 18, 0, 0, 0, q = { 20 } }
S.ITEMS[1007] = { 15, 18, 0, 0, 0, q = { 22 } }
S.ITEMS[1008] = { 15, 18, 0, 0, 0, q = { 23 } }
ns.FOREVER_DUNGEON_QUESTS = { [20] = { "36", "Into the Mine", 15, 18, "", 0, "Someone", "Elwynn Forest", 40, 40, 0, 0 } }
ns.DUNGEON_QUESTS = { [21] = { "36", "Down Below", 15, 18, "", 0, "Someone", "Elwynn Forest", 40, 40, 0, 0 },
    [23] = { "99", "The Core", 15, 18, "", 0, "Someone", "Elwynn Forest", 40, 40, 0, 0 } }
Finder:MarkStale()

local learned = Finder:SourcesFor(1006, player)[1]
suite.check("a learned dungeon quest is marked", learned and learned.group == "dungeon" and not Finder.Solo(learned),
    learned and tostring(learned.group))
local line = Finder:SourcesFor(1007, player)[1]
suite.check("a quest after an unmarked dungeon quest is not solo",
    line and line.chainGroup == "dungeon" and not Finder.Solo(line), line and tostring(line.chainGroup))
local raid = Finder:SourcesFor(1008, player)[1]
suite.check("an unmarked raid quest says raid", raid and raid.group == "raid", raid and tostring(raid.group))

Finder:SetSoloOnly(true)
suite.check("ticked, none of them are offered", not Offered():find("1006") and not Offered():find("1007")
    and not Offered():find("1008"), Offered())
quest = Quest:QuestOn("quest")
-- 1002 was skipped above, so nothing solo may be left to pick.
suite.check("and the quest tab does not pick them", not quest or quest.itemID ~= 1006 and quest.itemID ~= 1007
    and quest.itemID ~= 1008, quest and quest.itemID)
Finder:SetSoloOnly(false)

suite.done()
