-- The Upgrade Quest tab, the Equipment window's third (UI/UpgradeQuestTab.lua,
-- rework step 4, the owner approved the mockup 2026-11-23).
--
-- What must hold:
--   1. It is a tab of the Equipment window, after Find Upgrades.
--   2. Off, it says what the upgrade quest is and offers to turn it on.
--   3. On, the left lists the best pick from each source and the right
--      shows the one picked: its gain, what it asks, its steps and others
--      as good. A click on a source works on that one.
--   4. Its boxes are the saved choices Settings and the old panel wrote.
--   5. Tracking, Done and Ignored each list theirs, with a count on the
--      chip. Stop Tracking, Restore and Restore All work from here.
--   6. Ignore takes the pick off and onto the Ignored list.
--   7. Clicks start no scan, and a hidden page does nothing.
--   8. A finished quest is kept for the Done list, the newest thirty.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("questtab")

local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end
local function Gear(loc, n) return { loc = loc, class = 4, subclass = 2, stats = Agi(n) } end

local ITEMS = {
    ["item:900"] = Gear("INVTYPE_CHEST", 10),   -- worn
    ["item:1001"] = Gear("INVTYPE_CHEST", 20),  -- sold by a vendor
    ["item:1002"] = Gear("INVTYPE_CHEST", 30),  -- quest reward
    ["item:1004"] = Gear("INVTYPE_CHEST", 16),  -- sold by a vendor, less good
    ["item:1101"] = Gear("INVTYPE_HEAD", 8),    -- tracked by hand
}

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitRace = function() return "Human", "Human", 1 end
_G.GetRealZoneText = function() return "Elwynn Forest" end
env.InstallItems(ITEMS, { [5] = "item:900" }, { [0] = {} }, 20)

_G.C_QuestLog = {
    IsQuestFlaggedCompleted = function() return false end,
    IsOnQuest = function() return false end,
    ReadyForTurnIn = function() return false end,
}

local S = ns.Sources
ns.Crafts.ITEMS = {}
ns.RollData.ITEMS = {}
S.ZONES = { [12] = "Elwynn Forest" }
S.NPCS = { [1] = { "Corina Steele", 12, 41.5, 65.9, "A" } }
S.QUESTS = { [10] = { "Wolves of the Forest", 15, 18, 0, 0, "Marshal Dughan", 12, 42.1, 65.9, "" } }
S.DUNGEONS, S.BOSSES, S.FOREVER = {}, {}, {}
S.ITEMS = {
    [1001] = { 15, 18, 0, 0, 12050, v = { 1, 0 } },
    [1002] = { 15, 18, 0, 0, 0, q = { 10 } },
    [1004] = { 15, 18, 0, 0, 90, v = { 1, 0 } },
}

local Window, Tab, Quest, Panel = ns.GearWindow, ns.QuestTab, ns.UpgradeQuest, ns.SmallPanel
local Finder, Compare, Tracking = ns.Finder, ns.Compare, ns.Tracking

local judges, scans = 0, 0
local realJudge, realBuild = Compare.Judge, Finder.Build
Compare.Judge = function(...) judges = judges + 1 return realJudge(...) end
Finder.Build = function(...) scans = scans + 1 return realBuild(...) end
local function Quiet() judges, scans = 0, 0 end
local function Worked() return judges + scans end

local function Up(frame) return frame ~= nil and frame:IsShown() == true end
local function Click(frame, ...) frame:GetScript("OnClick")(frame, ...) end
local function SourceRow(key)
    for _, row in ipairs(Tab.sourceRows) do
        if row.tabKey == key then return row end
    end
end
local function Listed()
    local out = {}
    for _, row in ipairs(Tab.rows) do
        if row:IsShown() then out[#out + 1] = tostring(rawget(row, "itemID")) end
    end
    return table.concat(out, ",")
end
local function ViewChip(key)
    return Tab.ViewText(key, Tab.Counts()[key])
end

--------------------------------------------------------------------------------
-- 1. A tab of the Equipment window
--------------------------------------------------------------------------------

do
    local keys = {}
    for _, tab in ipairs(Window.TABS) do keys[#keys + 1] = tab.key end
    suite.check("Upgrade Quest comes after Find Upgrades",
        table.concat(keys, ","):find("gear,find,quest,", 1, true) == 1, table.concat(keys, ","))
    suite.check("the window knows its page", Window.pages.quest == Tab)
end

--------------------------------------------------------------------------------
-- 2. Off
--------------------------------------------------------------------------------

Window:Open("quest")
suite.check("the tab opens", Window.tab == "quest" and Tab:IsShown())
suite.check("off, it says what the upgrade quest is", Up(Tab.empty)
    and Tab.empty:GetText():find("pick your next gear upgrade", 1, true) ~= nil, Tab.empty:GetText())
suite.check("and offers to turn it on", Up(Tab.turnOn) and not Up(Tab.pickOne))
suite.check("the On box is unticked", Tab.onBox:GetChecked() ~= true)
suite.check("nothing was judged to show that", Worked() == 0, Worked())

--------------------------------------------------------------------------------
-- 3. On: each source's pick, and the one being worked on
--------------------------------------------------------------------------------

Click(Tab.turnOn)
suite.check("Turn it on turns the upgrade quest on", Quest:IsEnabled() and ns.db.upgradeQuest == true)
Tab:Refresh()
local quest = Quest:Current()
suite.check("it picked the quest reward", quest and quest.itemID == 1002, quest and quest.itemID)
suite.check("the On box is ticked", Tab.onBox:GetChecked() == true)
suite.check("the small panel came up with it", Panel.frame ~= nil and Panel.frame:IsShown())

local vendorRow, questRow = SourceRow("vendor"), SourceRow("quest")
suite.check("the left lists the vendor's pick", Up(vendorRow) and vendorRow.item:GetText() == "item:1001"
    and vendorRow.gain:GetText() == "+100%", vendorRow.item:GetText() .. " " .. tostring(vendorRow.gain:GetText()))
suite.check("and the quest's", Up(questRow) and questRow.item:GetText() == "item:1002"
    and questRow.gain:GetText() == "+200%", questRow.item:GetText())
suite.check("the one being worked on is lit", rawget(questRow, "picked") == true and rawget(vendorRow, "picked") == false)
suite.check("a source with nothing says so", Up(SourceRow("dungeon"))
    and SourceRow("dungeon").item:GetText() == Quest.NONE.dungeon, SourceRow("dungeon").item:GetText())

suite.check("the right names the upgrade", Up(Tab.name) and Tab.name:GetText() == "item:1002", Tab.name:GetText())
suite.check("with its gain", Tab.gain:GetText():find("+200%", 1, true) ~= nil, Tab.gain:GetText())
suite.check("and Ignore and Arrow", Up(Tab.ignoreButton) and Up(Tab.arrowButton))
suite.check("Queue It is for gear you make", not Up(Tab.queueButton))
suite.check("the steps are listed", Up(Tab.stepsHead) and Up(Tab.stepRows[1]) and Up(Tab.stepRows[5])
    and not Up(Tab.stepRows[6]))
suite.check("the first is done", Up(Tab.stepRows[1].check))
suite.check("the second is the one to do now", rawget(Tab.stepRows[2], "isNow") == true
    and Tab.stepRows[2].text:GetText():find("Pick up Wolves of the Forest", 1, true) ~= nil,
    Tab.stepRows[2].text:GetText())
suite.check("with Show on Map beside it", Up(Tab.stepRows[2].map) and not Up(Tab.stepRows[3].map))

Quiet()
Click(vendorRow)
Tab:Refresh()
suite.check("a click on a source works on that one", Quest:Tab() == "vendor" and Quest:Current().itemID == 1001)
suite.check("the right follows", Tab.name:GetText() == "item:1001", Tab.name:GetText())
suite.check("and the left lights it", rawget(vendorRow, "picked") == true and rawget(questRow, "picked") == false)
suite.check("each source kept its own pick", questRow.item:GetText() == "item:1002")
-- The quest looks at its kept picks again, as it always has on a change
-- of source: a judge for each, never a scan.
suite.check("the click started no scan", scans == 0 and judges <= #Quest.TABS, judges .. " " .. scans)

do
    local also = Quest:AlsoGood(Quest:Current())
    suite.check("others as good are listed under ALSO GOOD", (#also > 0) == Up(Tab.alsoHead), #also)
    if #also > 0 then
        local row = Tab.alsoRows[1]
        suite.check("with Switch", Up(row) and row.switch ~= nil and rawget(row, "itemID") == also[1].pick.itemID,
            tostring(rawget(row, "itemID")))
    end
end

--------------------------------------------------------------------------------
-- 4. The boxes are the saved choices
--------------------------------------------------------------------------------

suite.check("This Zone Only shows what is saved", (Tab.zoneBox:GetChecked() == true) == (Quest:ZoneOnly() == true))
do
    local before = Quest:ZoneOnly() == true
    Click(Tab.zoneBox)
    suite.check("a click on This Zone Only saves it", (Quest:ZoneOnly() == true) ~= before)
    Quest:SetZoneOnly(before)
    Tab:Sync()
    suite.check("and the box follows a change made elsewhere", (Tab.zoneBox:GetChecked() == true) == before)
end
suite.check("Panel: Show is ticked", Tab.panelBox:GetChecked() == true)
Panel:SetOff(true)
suite.check("it follows the panel", Tab.panelBox:GetChecked() ~= true and not Panel.frame:IsShown())
Panel:SetOff(false)
suite.check("and back", Tab.panelBox:GetChecked() == true and Panel.frame:IsShown())

--------------------------------------------------------------------------------
-- 5. Tracking, Done and Ignored
--------------------------------------------------------------------------------

Tracking:Track({ itemID = 1101, link = "item:1101", slot = 1,
    source = { kind = "vendor", name = "Corina Steele", zone = "Elwynn Forest", x = 41.5, y = 65.9 } })
Tab:Refresh()
suite.check("the Tracking chip counts", ViewChip("tracking") == "Tracking 1", ViewChip("tracking"))
Quiet()
Tab:SetView("tracking")
suite.check("the Tracking view lists it", Tab:View() == "tracking" and Up(Tab.listView) and not Up(Tab.questView)
    and Listed() == "1101", Listed())
suite.check("with Stop Tracking", Up(Tab.rows[1].second) and Tab.rows[1].second.label:GetText() == "Stop Tracking",
    Tab.rows[1].second.label:GetText())
Click(Tab.rows[1].second)
Tab:Refresh()
suite.check("Stop Tracking stops it", Tracking:Count() == 0 and Listed() == "")
suite.check("and the view says what to do", Up(Tab.none)
    and Tab.none:GetText():find("Track an upgrade in Find Upgrades", 1, true) ~= nil, Tab.none:GetText())
suite.check("none of that judged anything", Worked() == 0, Worked())

Tab:SetView("ignored")
suite.check("nothing ignored yet", Listed() == "" and Up(Tab.none) and not Up(Tab.restoreAll))
Tab:SetView("quest")
Quest:SelectTab("vendor")
Tab:Refresh()
local ignored = Quest:Current().itemID
Click(Tab.ignoreButton)
Tab:Refresh()
suite.check("Ignore takes the pick off", Quest:Skipped()[ignored] == true
    and (Quest:Current() == nil or Quest:Current().itemID ~= ignored))
suite.check("the Ignored chip counts", ViewChip("ignored") == "Ignored 1", ViewChip("ignored"))
Tab:SetView("ignored")
suite.check("the Ignored view lists it", Listed() == tostring(ignored), Listed())
suite.check("with Restore and Restore All", Up(Tab.rows[1].second)
    and Tab.rows[1].second.label:GetText() == "Restore" and Up(Tab.restoreAll))
Click(Tab.rows[1].second)
Tab:Refresh()
suite.check("Restore brings it back", Quest:Skipped()[ignored] == nil and Listed() == "")

Quest:Ignore(1001)
Quest:Ignore(1004)
Tab:Refresh()
suite.check("two ignored, two listed", #Quest:IgnoredList() == 2 and Up(Tab.rows[2]))
Click(Tab.restoreAll)
Tab:Refresh()
suite.check("Restore All brings every one back", #Quest:IgnoredList() == 0 and Listed() == "")

ns.HandleSlash("quest ignored")
suite.check("/beq quest ignored opens this list", Window.tab == "quest" and Tab:View() == "ignored")
suite.check("not the old window", not (ns.IgnoredUI.frame and ns.IgnoredUI.frame:IsShown()))

--------------------------------------------------------------------------------
-- 8. Done
--------------------------------------------------------------------------------

Tab:SetView("done")
suite.check("nothing done yet", Listed() == "" and Tab.none:GetText() == "No upgrades done yet.", Tab.none:GetText())
Quest:NoteDone({ itemID = 1002, link = "item:1002", howMuch = "+200%" })
Tab:Refresh()
suite.check("a finished quest is listed", Listed() == "1002" and Tab.rows[1].gain:GetText() == "+200%", Listed())
suite.check("kept for the character", ns.charDB.upgradeQuestDoneList[1].itemID == 1002)
for index = 1, 40 do Quest:NoteDone({ itemID = 5000 + index, link = "item:1002" }) end
suite.check("only the newest thirty are kept", #ns.charDB.upgradeQuestDoneList == 30
    and ns.charDB.upgradeQuestDoneList[1].itemID == 5040, #ns.charDB.upgradeQuestDoneList)
ns.charDB.upgradeQuestDoneList = nil

do
    -- Wearing the pick finishes it, and that lands on the list.
    Tab:SetView("quest")
    Quest:SelectTab("quest")
    Quest:Update()
    local now = Quest:Current()
    suite.check("a quest to finish", now ~= nil and now.itemID == 1002, now and now.itemID)
    env.worn[5] = "item:1002"
    Finder:MarkStale()
    Quest:Update()
    local list = ns.charDB.upgradeQuestDoneList
    suite.check("putting it on adds it to Done", type(list) == "table" and list[1] and list[1].itemID == 1002
        and list[1].gain == "+200%", list and list[1] and list[1].gain)
    suite.check("and counts once", Quest:DoneCount() == 1, Quest:DoneCount())
    env.worn[5] = "item:900"
end

--------------------------------------------------------------------------------
-- 7. A hidden page does nothing
--------------------------------------------------------------------------------

Window:Open("gear")
Quiet()
suite.check("on another tab the page is hidden", not Tab:IsShown())
suite.check("and draws nothing", Tab:Refresh() == nil)
Tab:OnUpgradeQuestChanged()
Tab:OnTrackingChanged()
suite.check("nor when the quest or a hunt changes", Tab.pending ~= true)

Compare.Judge, Finder.Build = realJudge, realBuild
suite.done()
