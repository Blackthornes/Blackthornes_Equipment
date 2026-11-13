-- A quest whose giver shows the character its quests without it (Forever
-- changed some givers): the upgrade quest lets it go and picks the next
-- upgrade, only at that level, and asks again after a level or a hand-in.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("questnotoffered")

local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end
local function Gear(loc, n) return { loc = loc, class = 4, subclass = 2, stats = Agi(n) } end

local ITEMS = {
    ["item:900"] = Gear("INVTYPE_CHEST", 10),   -- worn
    ["item:1001"] = Gear("INVTYPE_CHEST", 20),  -- sold by a vendor
    ["item:1002"] = Gear("INVTYPE_CHEST", 30),  -- quest reward
}

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitRace = function() return "Human", "Human", 1 end
_G.GetRealZoneText = function() return "Elwynn Forest" end
local level = 20
env.InstallItems(ITEMS, { [5] = "item:900" }, { [0] = {} }, 20)
_G.UnitLevel = function() return level end

local onQuest = false
_G.C_QuestLog = {
    IsQuestFlaggedCompleted = function() return false end,
    IsOnQuest = function(id) return id == 10 and onQuest end,
}

local S = ns.Sources
ns.Crafts.ITEMS = {}
ns.RollData.ITEMS = {}
S.ZONES = { [12] = "Elwynn Forest" }
S.NPCS = { [1] = { "Corina Steele", 12, 41.5, 65.9, "A" } }
S.QUESTS = { [10] = { "Wolves of the Forest", 15, 18, 0, 0, "Marshal Dughan", 12, 42.1, 65.9, "" } }
S.DUNGEONS = {}
S.BOSSES = {}
S.FOREVER = {}
S.ITEMS = {
    [1001] = { 15, 18, 0, 0, 12050, v = { 1, 0 } },
    [1002] = { 15, 18, 0, 0, 0, q = { 10 } },
}

local Quest, Finder = ns.UpgradeQuest, ns.Finder
local function Fire(event, ...) ns.eventFrame:GetScript("OnEvent")(ns.eventFrame, event, ...) end

local npc, isPlayer, offered, detailID = "Marshal Dughan", false, {}, 0
_G.UnitName = function(unit) if unit == "npc" then return npc end return "Me" end
_G.UnitIsPlayer = function(unit) return unit == "npc" and isPlayer end
_G.C_GossipInfo = {
    GetAvailableQuests = function()
        local list = {}
        for _, id in ipairs(offered) do list[#list + 1] = { title = "Q" .. id, questID = id, isTrivial = false } end
        return list
    end,
}
_G.GetQuestID = function() return detailID end
-- Tests skip the login, so the giver window events are signed up here.
Quest:OnEnable()
local clock = 1000
_G.GetTime = function() return clock end

local function QuestTab() return Quest:Quests().quest end
local function Pick()
    Finder:MarkStale()
    Quest.rescan = true
    Quest:Update()
end

ns.HandleSlash("quest")
suite.check("turned on, the quest reward is on the quest tab", QuestTab() and QuestTab().itemID == 1002,
    QuestTab() and QuestTab().itemID)

-- Another giver's list says nothing about this quest.
npc = "Deathguard Burgess"
Fire("GOSSIP_SHOW")
suite.check("another giver's window changes nothing", QuestTab() and QuestTab().itemID == 1002)
suite.check("and notes nothing", ns.charDB.questsNotOffered == nil)

-- A player is never the giver.
npc, isPlayer = "Marshal Dughan", true
Fire("GOSSIP_SHOW")
suite.check("a player's window notes nothing", ns.charDB.questsNotOffered == nil)
isPlayer = false

-- The giver offers it: nothing changes.
offered = { 10, 11 }
Fire("GOSSIP_SHOW")
suite.check("offered, the quest stays", ns.charDB.questsNotOffered == nil and QuestTab().itemID == 1002)

-- Clicking another quest in that list is not the giver's only offer.
detailID = 11
clock = clock + 2
Fire("QUEST_DETAIL")
suite.check("a quest picked from the list notes nothing", ns.charDB.questsNotOffered == nil)

-- The giver shows its quests without it.
offered = { 11 }
clock = clock + 60
Fire("GOSSIP_SHOW")
suite.check("left out, it is noted at this level", ns.charDB.questsNotOffered
    and ns.charDB.questsNotOffered[10] == 20)
Quest:Update()
suite.check("the quest tab lets it go", QuestTab() == nil or QuestTab().itemID ~= 1002,
    QuestTab() and QuestTab().itemID)
suite.check("not skipped", not (ns.charDB.upgradeQuestSkipped and ns.charDB.upgradeQuestSkipped[1002]))
suite.check("the finder leaves it out", #Finder:SourcesFor(1002, Finder:Player()) == 0)
suite.check("the vendor tab still has its pick", Quest:Quests().vendor and Quest:Quests().vendor.itemID == 1001)

-- A level later, it may be offered.
level = 21
Pick()
suite.check("at a new level it comes back", QuestTab() and QuestTab().itemID == 1002,
    QuestTab() and QuestTab().itemID)

-- A single quest's page with another quest, no list shown: the giver's only offer.
detailID = 11
clock = clock + 60
Fire("QUEST_DETAIL")
suite.check("a lone quest page without it notes it", ns.charDB.questsNotOffered[10] == 21)

-- A hand-in forgets them all.
Finder:OnQuestTurnedIn("QUEST_TURNED_IN", 11)
suite.check("a hand-in forgets what was noted", ns.charDB.questsNotOffered == nil)

-- In the log, or above the character's level: not judged.
onQuest = true
Fire("GOSSIP_SHOW")
suite.check("in the log, nothing is noted", ns.charDB.questsNotOffered == nil)
onQuest = false
S.QUESTS[10][2] = 30
Fire("GOSSIP_SHOW")
suite.check("too high to pick up, nothing is noted", ns.charDB.questsNotOffered == nil)
S.QUESTS[10][2] = 15

-- Grey to the character: the game may hide it.
level = 40
Fire("GOSSIP_SHOW")
suite.check("a grey quest is not judged", ns.charDB.questsNotOffered == nil)

-- A name the game won't let us compare.
level = 21
_G.UnitName = function() return setmetatable({}, {}) end
Fire("GOSSIP_SHOW")
suite.check("a name it can't read notes nothing", ns.charDB.questsNotOffered == nil)

suite.done()
