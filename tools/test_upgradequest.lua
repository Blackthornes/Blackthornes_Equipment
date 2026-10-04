-- The upgrade quest: off until turned on, then the best next upgrade with
-- the steps to get it, ticking off as the game shows them done, and the
-- next one picked once it is worn.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("upgradequest")

local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end
local function Gear(loc, n) return { loc = loc, class = 4, subclass = 2, stats = Agi(n) } end

local ITEMS = {
    ["item:900"] = Gear("INVTYPE_CHEST", 10),   -- worn
    ["item:1001"] = Gear("INVTYPE_CHEST", 20),  -- sold by a vendor
    ["item:1002"] = Gear("INVTYPE_CHEST", 30),  -- quest reward
    ["item:1003"] = Gear("INVTYPE_CHEST", 5),   -- worse
    ["item:2001"] = Gear("INVTYPE_CHEST", 40),  -- a dungeon drop, seen later
    ["item:9000"] = Gear("INVTYPE_CHEST", 50),  -- better than anything on offer
}

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitRace = function() return "Human", "Human", 1 end
_G.GetRealZoneText = function() return "Elwynn Forest" end
env.InstallItems(ITEMS, { [5] = "item:900" }, { [0] = {} }, 20)

local onQuest, ready, turnedIn = false, false, false
_G.C_QuestLog = {
    IsQuestFlaggedCompleted = function() return turnedIn end,
    IsOnQuest = function(id) return id == 10 and onQuest end,
    ReadyForTurnIn = function(id) return id == 10 and ready end,
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
    [1003] = { 15, 18, 0, 0, 40, v = { 1, 0 } },
}

local Quest, Panel = ns.UpgradeQuest, ns.QuestPanel

local toasts = {}
local realShow = ns.Toast.Show
ns.Toast.Show = function(self, banner)
    toasts[#toasts + 1] = banner
    return realShow(self, banner)
end

local function StepTexts()
    local texts = {}
    for _, step in ipairs((Quest:Steps())) do texts[#texts + 1] = step.text end
    return table.concat(texts, " | ")
end

--------------------------------------------------------------------------------
-- Off by default
--------------------------------------------------------------------------------

suite.check("off by default", ns.db.upgradeQuest == false and not Quest:IsEnabled())
Quest:Update()
suite.check("off, it picks nothing", ns.charDB.upgradeQuest == nil)
Panel:Refresh()
suite.check("and shows nothing", not (Panel.frame and Panel.frame:IsShown()))

--------------------------------------------------------------------------------
-- Turned on: the best next upgrade
--------------------------------------------------------------------------------

ns.HandleSlash("quest")
suite.check("/beq quest turns it on", ns.db.upgradeQuest == true)
suite.check("and says so", env.ChatText():find("upgrade quest on", 1, true) ~= nil, env.ChatText())
local quest = Quest:Current()
-- The quest reward is +200%, the vendor's +100%; a quest is a little more
-- work than buying, but not twice as much.
suite.check("picks the best upgrade worth the trip", quest and quest.itemID == 1002, quest and quest.itemID)
suite.check("kept per character", ns.charDB.upgradeQuest == quest)
suite.check("with how much better", quest.howMuch == "+200%", quest.howMuch)
suite.check("a banner says so", toasts[#toasts] and toasts[#toasts].title == "New upgrade quest")
suite.check("the panel shows", Panel.frame and Panel.frame:IsShown())
suite.check("with the item", Panel.name:GetText() == "item:1002", Panel.name:GetText())
suite.check("how much better and from where", Panel.gain:GetText():find("+200% over what you wear", 1, true)
    and Panel.gain:GetText():find("Quest", 1, true), Panel.gain:GetText())

local steps, current = Quest:Steps()
suite.check("the quest's steps", StepTexts() == "Travel to Elwynn Forest"
    .. " | Pick up Wolves of the Forest from Marshal Dughan (42.1, 65.9)"
    .. " | Complete Wolves of the Forest (level 18)"
    .. " | Hand it in and choose item:1002"
    .. " | Put on item:1002", StepTexts())
suite.check("already in the zone, so travel is done", steps[1].done and current == 2, current)
suite.check("the panel counts the steps", Panel.progress:GetText() == "Step 2 of 5", Panel.progress:GetText())
suite.check("the step to do now is lit", Panel.steps[2].now and not Panel.steps[1].now)
suite.check("steps to come are numbered", Panel.steps[3].number:GetText() == "3.")
suite.check("Show on map is offered", Panel.mapButton:IsShown())

-- Picked up, done, handed in, worn.
onQuest = true
Quest:Update()
suite.check("taking the quest ticks off picking it up", select(2, Quest:Steps()) == 3)
suite.check("the panel follows", Panel.progress:GetText() == "Step 3 of 5", Panel.progress:GetText())
ready = true
suite.check("its objectives done", select(2, Quest:Steps()) == 4)
onQuest, ready, turnedIn = false, false, true
env.bags[0][1] = "item:1002"
steps, current = Quest:Steps()
suite.check("handed in, the reward in the bags: put it on", current == 5 and steps[4].done and steps[2].done,
    current)
suite.check("the progress bar fills", (function()
    Panel:Refresh()
    return Panel.fill:GetWidth() > 200
end)(), Panel.fill:GetWidth())

env.bags[0][1] = nil
env.worn[5] = "item:1002"
Quest:Update()
suite.check("worn, the quest is complete", Quest:DoneCount() == 1)
suite.check("with a banner", (function()
    for _, banner in ipairs(toasts) do
        if banner.title == "Upgrade quest complete" then return true end
    end
end)())
-- Nothing on offer beats what is worn now.
suite.check("and nothing left to chase", Quest:Current() == nil and Quest.state == "none", Quest.state)
suite.check("the panel says so", Panel.empty:IsShown()
    and Panel.empty:GetText():find("No upgrade to chase", 1, true) ~= nil, Panel.empty:GetText())
suite.check("with Other ways still there", Panel.otherButton:IsShown() and not Panel.skipButton:IsShown())

--------------------------------------------------------------------------------
-- Skipping, and the vendor's steps
--------------------------------------------------------------------------------

env.worn[5] = "item:900"
turnedIn = false
ns.Finder:MarkStale()
Quest:Update()
suite.check("a new quest once there is an upgrade again", Quest:Current() and Quest:Current().itemID == 1002)
ns.HandleSlash("quest skip")
quest = Quest:Current()
suite.check("skip moves to the next best", quest and quest.itemID == 1001, quest and quest.itemID)
suite.check("and remembers it", ns.charDB.upgradeQuestSkipped[1002] == true)
suite.check("the vendor's steps", StepTexts() == "Travel to Elwynn Forest"
    .. " | Find Corina Steele (41.5, 65.9)"
    .. " | Buy item:1001 for |cffffd700" .. "1g|r |cffc7c7cf20s|r |cffeda55f50c|r"
    .. " | Put on item:1001", StepTexts())
local place = Quest:NextPlace()
suite.check("the next place is the vendor", place and place.name == "Corina Steele" and place.x == 41.5)

-- Show on map uses the game's pin.
local waypoint
_G.UiMapPoint = { CreateFromCoordinates = function(id, x, y) return { id = id, x = x, y = y } end }
_G.C_Map = {
    GetBestMapForUnit = function() return 1429 end,
    GetMapInfo = function(id)
        return ({ [1429] = { name = "Elwynn Forest", parentMapID = 0 } })[id]
    end,
    GetMapChildrenInfo = function() return {} end,
    SetUserWaypoint = function(point) waypoint = point end,
}
suite.check("Show on map pins the vendor", Panel:ShowOnMap() == true and waypoint
    and math.abs(waypoint.x - 0.415) < 1e-9, waypoint and waypoint.x)

-- And the world map gets a pin for it.
local canvas = env.Stub({ _width = 1000, _height = 600 })
function canvas:GetHeight() return 600 end
_G.WorldMapFrame = env.Stub({ _shown = true, GetCanvas = function() return canvas end,
    GetMapID = function() return 1429 end })
ns.MapPins.key = nil
ns.MapPins:Draw()
local pin = ns.MapPins.pins and ns.MapPins.pins[1]
suite.check("a map pin for the quest's next place", pin and pin:IsShown() and pin.hunt.quest == true)

ns.HandleSlash("quest reset")
suite.check("/beq quest reset brings skipped ones back", next(ns.charDB.upgradeQuestSkipped) == nil)

-- Something as good turns up another way: the quest is dropped.
env.worn[5] = "item:9000"
Quest:Update()
suite.check("an upgrade no longer wanted is dropped", Quest:Current() == nil)
suite.check("and chat says why", env.ChatText():find("wear something as good now", 1, true) ~= nil)
suite.check("without counting as done", Quest:DoneCount() == 1)
env.worn[5] = "item:900"

--------------------------------------------------------------------------------
-- Waiting on the server
--------------------------------------------------------------------------------

local clock = 100
_G.GetTime = function() return clock end
local cached = false
_G.C_Item.IsItemDataCachedByID = function() return cached end
_G.C_Item.RequestLoadItemDataByID = function() return true end
ns.charDB.upgradeQuest = nil
ns.Finder:MarkStale()
Quest:Update()
suite.check("waits for the server's answers before picking", Quest:Current() == nil and Quest.state == "waiting",
    Quest.state)
suite.check("and says it is looking", Panel.empty:GetText():find("Looking for your next upgrade", 1, true) ~= nil)
cached = true
Quest:Update()
suite.check("picks once they are in", Quest:Current() ~= nil)
_G.GetTime = nil
_G.C_Item.IsItemDataCachedByID = nil

--------------------------------------------------------------------------------
-- Dungeons and crafting
--------------------------------------------------------------------------------

_G.GetRealZoneText = function() return "Westfall" end
local dungeon = {
    itemID = 2001, link = "item:2001", howMuch = "+300%",
    source = { kind = "dungeon", name = "Edwin VanCleef", dungeon = "The Deadmines", minLevel = 17,
        maxLevel = 26, zone = "Westfall", chance = 5, forever = true },
}
steps, current = Quest:Steps(dungeon)
suite.check("a dungeon's steps", #steps == 4 and steps[1].text == "Travel to Westfall"
    and steps[2].text == "Gather a group and enter The Deadmines (levels 17 to 26)"
    and steps[3].text == "Defeat Edwin VanCleef and loot item:2001", steps[2].text)
suite.check("in Westfall, the door is next", steps[1].done and current == 2, current)
suite.check("with the drop chance", steps[3].note:find("5% drop", 1, true) and steps[3].note:find("Forever", 1, true),
    steps[3].note)
suite.check("the map takes you to the door", steps[2].place.zone == "Westfall")
_G.GetRealZoneText = function() return "The Deadmines" end
steps, current = Quest:Steps(dungeon)
suite.check("inside, the boss is next", current == 3 and steps[1].done, current)
suite.check("a rare drop counts as harder to get", Quest.Ease(dungeon.source) < Quest.Ease({ kind = "dungeon" }))

ns.Crafts.ITEMS = { [2001] = { 165, 100, 555, 15, 18, 0, 0, 0, m = { 2318, 4 } } }
ns.Crafts.MATERIALS = { [2318] = { "Light Leather", 15 } }
local craft = {
    itemID = 2001, link = "item:2001",
    source = { kind = "craft", state = "known", profession = "Leatherworking", skill = 100 },
}
steps = Quest:Steps(craft)
suite.check("a craft's steps", #steps == 3 and steps[1].text == "Gather the materials: 4 Light Leather"
    and steps[2].text == "Make item:2001 (Leatherworking)", steps[1] and steps[1].text)
env.bags[0] = { "item:2318", "item:2318", "item:2318", "item:2318" }
steps, current = Quest:Steps(craft)
suite.check("materials in the bags tick it off", steps[1].done and current == 2, current)
env.bags[0] = {}
craft.source.state = "alt"
craft.source.who = { "Bob" }
steps = Quest:Steps(craft)
suite.check("an alt can make it", steps[1].text == "Ask Bob to make item:2001 (Leatherworking) and mail it to you")

--------------------------------------------------------------------------------
-- A quest handed in with another reward taken
--------------------------------------------------------------------------------

_G.GetRealZoneText = function() return "Elwynn Forest" end
ns.Crafts.ITEMS = {}
env.bags[0] = {}
env.worn[5] = "item:900"
turnedIn = false
ns.charDB.upgradeQuest = nil
ns.charDB.upgradeQuestSkipped = {}
ns.Finder:MarkStale()
Quest:Update()
suite.check("the quest reward is picked again", Quest:Current() and Quest:Current().itemID == 1002)
clock = 500
_G.GetTime = function() return clock end
turnedIn = true
Quest:Update()
suite.check("handed in, it waits a moment for the reward to reach the bags",
    Quest:Current() and Quest:Current().itemID == 1002)
clock = 506
Quest:Update()
suite.check("still not in the bags: the quest is dropped",
    env.ChatText():find("that quest is already done", 1, true) ~= nil)
suite.check("and never picked again", ns.charDB.upgradeQuestSkipped[1002] == true
    and Quest:Current() and Quest:Current().itemID == 1001, Quest:Current() and Quest:Current().itemID)
_G.GetTime = nil
turnedIn = false

-- A client that cannot say which quests are done: hand-ins seen are kept.
local realLog = _G.C_QuestLog
_G.C_QuestLog = {}
suite.check("an unknown quest is not done", ns.Finder:QuestDone(10) == false)
ns.Finder:OnQuestTurnedIn("QUEST_TURNED_IN", 10)
suite.check("a quest seen handed in is done", ns.Finder:QuestDone(10) == true
    and ns.charDB.questsTurnedIn[10] == true)
suite.check("so the finder leaves its reward out", (function()
    for _, source in ipairs(ns.Finder:SourcesFor(1002, ns.Finder:Player())) do
        if source.kind == "quest" then return false end
    end
    return true
end)())
_G.C_QuestLog = realLog

--------------------------------------------------------------------------------
-- Quest chains
--------------------------------------------------------------------------------

local done = {}
_G.C_QuestLog = {
    IsQuestFlaggedCompleted = function(id) return done[id] == true end,
    IsOnQuest = function() return false end,
}
S.QUESTS = {
    [10] = { "Wolves of the Forest", 15, 18, 0, 0, "Marshal Dughan", 12, 42.1, 65.9, "The Fargodeep Mine", p = 11 },
    [11] = { "The Fargodeep Mine", 10, 12, 0, 0, "Marshal Dughan", 12, 42.1, 65.9, "Bounty on Murlocs", p = 12 },
    [12] = { "Bounty on Murlocs", 8, 10, 0, 0, "Guard Thomas", 12, 74, 72, "Report to Goldshire", p = 13 },
    [13] = { "Report to Goldshire", 1, 5, 0, 0, "Guard Thomas", 12, 74, 72, "" },
}
ns.charDB.upgradeQuest = nil
ns.charDB.upgradeQuestSkipped = {}
ns.charDB.questsTurnedIn = nil
ns.Finder:MarkStale()
local player = ns.Finder:Player()
local chained = ns.Finder:SourcesFor(1002, player)[1]
suite.check("the finder counts the quests before it", chained.chain == 3, chained.chain)
suite.check("and says so", ns.Finder:Describe(chained):find("after 3 earlier quests", 1, true) ~= nil,
    ns.Finder:Describe(chained))
Quest:Update()
-- Three quests first make the bigger upgrade less worth the trip than the
-- vendor's, a short walk away.
suite.check("a long chain counts as more work", Quest:Current() and Quest:Current().itemID == 1001,
    Quest:Current() and Quest:Current().itemID)

local chainQuest = { itemID = 1002, link = "item:1002", source = chained }
steps, current = Quest:Steps(chainQuest)
suite.check("the chain comes first, from its first quest",
    steps[1].text == "Do Report to Goldshire: pick it up from Guard Thomas in Elwynn Forest (74, 72)"
    and steps[2].text == "Do Bounty on Murlocs: pick it up from Guard Thomas in Elwynn Forest (74, 72)"
    and steps[3].text == "Then 1 more quest in the chain, up to The Fargodeep Mine", StepTexts and steps[1].text)
suite.check("saying how many", steps[1].note == "3 quests to do before Wolves of the Forest.", steps[1].note)
suite.check("then the quest itself", steps[5].text:find("Pick up Wolves of the Forest", 1, true) ~= nil
    and #steps == 8, #steps)
suite.check("the first quest is the step to do now", current == 1 and steps[1].place.x == 74, current)

done[13] = true
steps = Quest:Steps(chainQuest)
suite.check("a quest done drops off the chain", steps[1].text:find("Do Bounty on Murlocs", 1, true) == 1
    and steps[2].text:find("Do The Fargodeep Mine", 1, true) == 1 and #steps == 7, steps[1].text)
done[12], done[11] = true, true
steps = Quest:Steps(chainQuest)
suite.check("the whole chain done leaves the quest itself", steps[2].text:find("Pick up Wolves", 1, true) == 1
    and #steps == 5, steps[1].text)

-- An earlier quest the data only names.
S.QUESTS[11] = { "The Fargodeep Mine", 10, 12, 0, 0, "Marshal Dughan", 12, 42.1, 65.9, "Lost Necklace" }
done[11] = nil
steps = Quest:Steps({ itemID = 1002, link = "item:1002", source = ns.Finder:SourcesFor(1002, player)[1] })
suite.check("one only named is still a step", steps[1].text == "Do Lost Necklace"
    and steps[1].note:find("Skip this one if you have done it", 1, true) ~= nil, steps[1].text)
_G.C_QuestLog = realLog
S.QUESTS = { [10] = { "Wolves of the Forest", 15, 18, 0, 0, "Marshal Dughan", 12, 42.1, 65.9, "" } }

--------------------------------------------------------------------------------
-- Text that wraps, and turning it off
--------------------------------------------------------------------------------

suite.check("long steps wrap rather than cut", Panel.Lines("small",
    "Pick up Wolves of the Forest from Marshal Dughan in Elwynn Forest (42.1, 65.9)", 200) > 1)
suite.check("short ones take one line", Panel.Lines("small", "Put it on", 200) == 1)
suite.check("a link's hidden part takes no room",
    Panel.Lines("small", "|cff1eff00|Hitem:1001::::::::20:::::|h[Vest]|h|r", 60) == 1)

ns.SettingsUI:Show()
local box = ns.SettingsUI.controls.upgradeQuest
suite.check("the settings box is ticked while it is on", box:GetChecked())
box:GetScript("OnClick")(box)
suite.check("unticking it turns it off", ns.db.upgradeQuest == false and not Panel.frame:IsShown())
suite.check("the quest is kept for next time", Quest:Current() ~= nil)
ns.HandleSlash("quest off")
suite.check("/beq quest off", ns.db.upgradeQuest == false)

ns.SettingsUI:ResetPositions()
suite.check("the panel's spot is reset with the others", ns.db.questPoint == nil)

ns.Toast.Show = realShow
suite.done()
