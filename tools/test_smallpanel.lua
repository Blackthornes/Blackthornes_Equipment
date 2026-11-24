-- The small panel (UI/SmallPanel.lua, rework step 4, the owner approved the
-- mockup 2026-11-23): the upgrade quest, the tracked upgrades and the quest
-- log in one small window with three tabs.
--
-- What must hold:
--   1. It shows while the upgrade quest is on, or while something is
--      tracked.
--   2. The Quest tab shows the upgrade, its gain, the step to do now and
--      five marks. A click on the step opens every step; another closes it.
--   3. The fold gem makes it one line and back.
--   4. Tracking lists what is tracked, with a count on its tab. Log lists
--      the character's quests.
--   5. The red gem turns the upgrade quest off and keeps its quests.
--   6. "Panel: Show" unticked keeps it off screen.
--   7. Clicks judge no gear and start no scan.
--   8. In a fight with no pick yet it says the upgrade comes after.
--   9. It reads and writes the places the old panel saved, and adds keys
--      without touching old ones.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("smallpanel")

local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end
local function Gear(loc, n) return { loc = loc, class = 4, subclass = 2, stats = Agi(n) } end

local ITEMS = {
    ["item:900"] = Gear("INVTYPE_CHEST", 10),   -- worn
    ["item:1001"] = Gear("INVTYPE_CHEST", 20),  -- sold by a vendor
    ["item:1002"] = Gear("INVTYPE_CHEST", 30),  -- quest reward
    ["item:1101"] = Gear("INVTYPE_HEAD", 8),    -- sold by a vendor
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

local fighting = false
_G.InCombatLockdown = function() return fighting end

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
    [1101] = { 15, 18, 0, 0, 100, v = { 1, 0 } },
}

local Quest, Panel = ns.UpgradeQuest, ns.SmallPanel
local Finder, Compare, Tracking = ns.Finder, ns.Compare, ns.Tracking

local judges, scans = 0, 0
local realJudge, realBuild = Compare.Judge, Finder.Build
Compare.Judge = function(...) judges = judges + 1 return realJudge(...) end
Finder.Build = function(...) scans = scans + 1 return realBuild(...) end
local function Quiet() judges, scans = 0, 0 end
local function Worked() return judges + scans end

local function Up(frame) return frame ~= nil and frame:IsShown() == true end
local function Click(frame, ...) frame:GetScript("OnClick")(frame, ...) end

--------------------------------------------------------------------------------
-- 1. When it shows
--------------------------------------------------------------------------------

Panel:Refresh()
suite.check("off and nothing tracked: no panel", not Up(Panel.frame))

ns.HandleSlash("quest")
local quest = Quest:Current()
suite.check("the quest is on with a pick", Quest:IsEnabled() and quest and quest.itemID == 1002, quest and quest.itemID)
suite.check("the panel shows", Up(Panel.frame))
suite.check("it has the frame's own name", _G.BlackthornesEquipmentPanel == Panel.frame)

--------------------------------------------------------------------------------
-- 2. The Quest tab
--------------------------------------------------------------------------------

suite.check("it opens on Quest", Panel:View() == "quest")
suite.check("the upgrade's name", Panel.item.name:GetText() == "item:1002", Panel.item.name:GetText())
suite.check("and its gain", Panel.item.gain:GetText() == "+200%", Panel.item.gain:GetText())
suite.check("the step to do now", Up(Panel.step)
    and Panel.step.text:GetText() == "Pick up Wolves of the Forest from Marshal Dughan (42.1, 65.9)",
    Panel.step.text:GetText())
suite.check("five marks", #Panel.marks == 5 and Up(Panel.marks[1]) and Up(Panel.marks[5]))
suite.check("the steps are closed", not Up(Panel.stepRows[1]))
suite.check("all three tabs show", Up(Panel.tabs.quest) and Up(Panel.tabs.tracking) and Up(Panel.tabs.log))
suite.check("the Tracking tab has no count yet", Panel.tabs.tracking.label:GetText() == "Tracking",
    Panel.tabs.tracking.label:GetText())

do
    local lit, under = Panel.MarksFor(1, 5)
    suite.check("one step of five: one mark done, one under way", lit == 1 and under == true)
    lit, under = Panel.MarksFor(5, 5)
    suite.check("every step done: five marks", lit == 5 and under == false)
    lit, under = Panel.MarksFor(0, 3)
    suite.check("none done: the first is under way", lit == 0 and under == true)
    lit, under = Panel.MarksFor(2, 3)
    suite.check("the last step never looks done early", lit < 5 and under == true, lit)
end

Quiet()
local closed = Panel.frame:GetHeight()
Click(Panel.step, "LeftButton")
suite.check("a click on the step opens every step", Panel:StepsOpen() and Up(Panel.stepRows[1])
    and Up(Panel.stepRows[5]) and not Up(Panel.step))
suite.check("saved for every character", ns.db.questPanelSteps == true)
suite.check("the panel grows", Panel.frame:GetHeight() > closed, Panel.frame:GetHeight())
suite.check("a done step is ticked", Up(Panel.stepRows[1].check) and not Up(Panel.stepRows[1].now))
suite.check("the one to do now is marked", Up(Panel.stepRows[2].now) and rawget(Panel.stepRows[2], "isNow") == true)
suite.check("the marks give way to the list", not Up(Panel.marks[1]))
Click(Panel.stepRows[2], "LeftButton")
suite.check("a click on it closes them", not Panel:StepsOpen() and Up(Panel.step) and not Up(Panel.stepRows[1]))
suite.check("and the key is gone again", ns.db.questPanelSteps == nil)
suite.check("opening and closing judges nothing", Worked() == 0, Worked())

--------------------------------------------------------------------------------
-- 3. One line
--------------------------------------------------------------------------------

Quiet()
local full = Panel.frame:GetHeight()
Click(Panel.gems.fold, "LeftButton")
suite.check("the fold gem makes it one line", Panel:OneLine() and ns.db.questPanelLine == true)
suite.check("the bar and the item go", not Up(Panel.bar) and not Up(Panel.item) and not Up(Panel.body))
suite.check("the step stays", Up(Panel.step)
    and Panel.step.text:GetText():find("Pick up Wolves of the Forest", 1, true) ~= nil, Panel.step.text:GetText())
suite.check("the panel is shorter", Panel.frame:GetHeight() < full, Panel.frame:GetHeight())
suite.check("the red gem is put away with the bar", not Up(Panel.gems.close))
Click(Panel.step, "LeftButton")
suite.check("a click on the line opens it again", not Panel:OneLine() and Up(Panel.bar) and Up(Panel.item))
Click(Panel.gems.fold, "LeftButton")
Click(Panel.gems.fold, "LeftButton")
suite.check("so does the gem", not Panel:OneLine() and ns.db.questPanelLine == nil)
suite.check("folding judges nothing", Worked() == 0, Worked())

--------------------------------------------------------------------------------
-- 4. Tracking and Log
--------------------------------------------------------------------------------

Tracking:Track({ itemID = 1101, link = "item:1101", slot = 1,
    source = { kind = "vendor", name = "Corina Steele", zone = "Elwynn Forest", x = 41.5, y = 65.9 } })
suite.check("a tracked upgrade counts on the tab", Panel.tabs.tracking.label:GetText() == "Tracking 1",
    Panel.tabs.tracking.label:GetText())
suite.check("the view stays on Quest", Panel:View() == "quest")

Quiet()
Click(Panel.tabs.tracking, "LeftButton")
suite.check("a click shows Tracking", Panel:View() == "tracking" and ns.charDB.panelTab == "tracking")
suite.check("with the tracked upgrade", Up(Panel.rows[1]) and Panel.rows[1].text:GetText() == "item:1101",
    Panel.rows[1].text:GetText())
suite.check("and only that", not Up(Panel.rows[2]))
suite.check("the quest's parts are put away", not Up(Panel.item) and not Up(Panel.step) and not Up(Panel.marks[1]))

_G.C_QuestLog.GetNumQuestLogEntries = function() return 2, 1 end
local LOG = {
    { title = "Elwynn Forest", isHeader = true },
    { title = "Wolves at the Door", questID = 77, level = 9, isHeader = false },
}
_G.C_QuestLog.GetInfo = function(index) return LOG[index] end
_G.C_QuestLog.GetQuestObjectives = function() return { { text = "Wolves slain: 3/8", finished = false } } end
if ns.QuestLog.Forget then ns.QuestLog:Forget() end
Click(Panel.tabs.log, "LeftButton")
suite.check("a click shows the Log", Panel:View() == "log" and ns.charDB.questLogTab == true)
suite.check("the tab kept for Tracking lets go", ns.charDB.panelTab == nil)
do
    local lines = Panel:LogLines()
    local first = lines[1]
    suite.check("the Log lists the character's quests", #lines == 1 and first and first.title == "Wolves at the Door",
        #lines)
    if first then
        local mark = Panel.LogMark(first)
        suite.check("with its count on the right", mark == "3/8", tostring(mark))
    end
end
suite.check("a quest ready to hand in shows a check",
    Panel.LogMark({ title = "x", complete = true, objectives = {} }) == "check")
suite.check("a failed one shows nothing", Panel.LogMark({ title = "x", failed = true, objectives = {} }) == nil)
do
    local realMark = Quest.RewardMark
    Quest.RewardMark = function() return { percent = 18.6, slot = 1 } end
    local ok, text = pcall(Panel.LogMark, { title = "x", questID = 5, objectives = {} })
    Quest.RewardMark = realMark
    suite.check("a reward's gain is rounded like everywhere else", ok and text == "+19%", tostring(text))
end
suite.check("several goals show how many are done", Panel.LogMark({ title = "x",
    objectives = { { text = "a", done = true }, { text = "b" }, { text = "c" } } }) == "1/3")

do
    local open, log = Panel.openTab, Panel.tabs.log
    suite.check("a small button sits after the tabs", Up(open))
    local _, anchor, _, x = open:GetPoint()
    local _, _, _, logX = log:GetPoint()
    suite.check("right after Log, clear of the gems", anchor == Panel.bar and x >= logX + log:GetWidth()
        and x + 18 <= Panel.WIDTH - (15 * 2 + 14), tostring(x))
    open:GetScript("OnEnter")(open)
    suite.check("its tooltip says what it does", _G.GameTooltip:IsShown())
    open:GetScript("OnLeave")(open)
    Click(open, "LeftButton")
    local gear = ns.GearWindow
    suite.check("a click opens the Upgrade Quest tab", gear:IsShown() and rawget(gear, "tab") == "quest",
        tostring(rawget(gear, "tab")))
    gear.frame:Hide()
    suite.check("the panel keeps its tab", Panel:View() == "log")
end

do
    local open, search = Panel.openTab, Panel.searchButton
    suite.check("a magnifying glass sits right of the scroll", Up(search))
    local _, anchor, _, x = search:GetPoint()
    suite.check("4 pixels after it", anchor == open and x == 4, tostring(x))
    local _, _, _, openX = open:GetPoint()
    suite.check("both clear of the gems", openX + 18 + 4 + 18 <= Panel.WIDTH - (15 * 2 + 14), tostring(openX))
    search:GetScript("OnEnter")(search)
    suite.check("its tooltip says what it does", _G.GameTooltip:IsShown())
    search:GetScript("OnLeave")(search)
    local finder, logic = ns.Finder, ns.UpgradeQuest
    local forgot, asked = 0, 0
    local realForget, realUpdate = finder.ForgetVerdicts, logic.Update
    finder.ForgetVerdicts = function(self, ...) forgot = forgot + 1; return realForget(self, ...) end
    logic.Update = function(self, ...) asked = asked + 1; return realUpdate(self, ...) end
    local realScanning = finder.Scanning
    finder.Scanning = function() return false end
    Quiet()
    Click(search, "LeftButton")
    suite.check("a click forgets the old verdicts and looks again", forgot == 1 and asked == 1,
        forgot .. " " .. asked)
    finder.Scanning = function() return true end
    Click(search, "LeftButton")
    suite.check("a click while it searches does nothing more", forgot == 1, forgot)
    Panel:FillBar(Panel:View(), false)
    suite.check("the glass dims while it searches", search.dimmed == true)
    suite.check("and it really searches", Worked() > 0, Worked())
    Quiet()
    finder.Scanning = realScanning
    finder.ForgetVerdicts, logic.Update = realForget, realUpdate
    Panel:FillBar(Panel:View(), false)
    suite.check("and lights again after", search.dimmed == false)
end

-- Found 2026-11-24: with a quest on every tab, or with the upgrade quest
-- off, a click on the glass forgot the verdicts and searched nothing.
do
    local search, finder = Panel.searchButton, ns.Finder
    local asked = 0
    local realScan = finder.ScanInBackground
    finder.ScanInBackground = function(self, ...) asked = asked + 1; return realScan(self, ...) end
    local tabs = Quest:Quests()
    local kept, held = {}, nil
    for _, tab in ipairs(Quest.TABS) do
        kept[tab.key] = tabs[tab.key]
        held = held or tabs[tab.key]
    end
    suite.check("a tab holds a quest to copy", held ~= nil)
    for _, tab in ipairs(Quest.TABS) do tabs[tab.key] = tabs[tab.key] or held end
    Click(search, "LeftButton")
    suite.check("a click searches with a quest on every tab", asked >= 1, asked)
    for _, tab in ipairs(Quest.TABS) do tabs[tab.key] = kept[tab.key] end

    local was = ns.db.upgradeQuest
    ns.db.upgradeQuest = false
    asked = 0
    Click(search, "LeftButton")
    suite.check("and with the upgrade quest off", asked >= 1, asked)
    ns.db.upgradeQuest = was
    finder.ScanInBackground = realScan
    Quest:Update()
    Quiet()
end

Click(Panel.tabs.quest, "LeftButton")
suite.check("and back to Quest", Panel:View() == "quest" and ns.charDB.questLogTab == nil and Up(Panel.item))
suite.check("changing tabs judges nothing", Worked() == 0, Worked())

--------------------------------------------------------------------------------
-- 5. The menu
--------------------------------------------------------------------------------

do
    local texts = {}
    for _, line in ipairs(Panel:MenuLines()) do texts[line.text] = line end
    suite.check("the menu has Arrow and Ignore", texts["Arrow"] ~= nil and texts["Ignore"] ~= nil)
    suite.check("and the four options", texts["Current Zone Only"] ~= nil and texts["Update on Zone Change"] ~= nil
        and texts["Solo Quests Only"] ~= nil and texts["Open Equipment"] ~= nil)
    for _, gone in ipairs({ "This Zone Only", "Change on a New Zone", "Current Step Only", "Tracked Only",
        "Hide Game's Tracker", "Upgrade Quest", "Settings" }) do
        suite.check("but not " .. gone, texts[gone] == nil)
    end
    local gone = 0
    for text in pairs(texts) do
        if text:find("How You Gear Up", 1, true) or text:find("Quest Level", 1, true) then gone = gone + 1 end
    end
    suite.check("nor How You Gear Up or Quest Level", gone == 0)
    local soloBefore, zoneBefore = ns.Finder:SoloOnly(), ns.UpgradeQuest:ZoneOnly()
    suite.check("the log's saved choices are left alone",
        ns.db.questLogTrackedOnly == nil or type(ns.db.questLogTrackedOnly) == "boolean")
    texts["Open Equipment"].run()
    suite.check("Open Equipment opens the Equipment window", ns.GearWindow.frame and ns.GearWindow.frame:IsShown())
    suite.check("and changes no setting", ns.Finder:SoloOnly() == soloBefore and ns.UpgradeQuest:ZoneOnly() == zoneBefore)
    ns.GearWindow.frame:Hide()
end

--------------------------------------------------------------------------------
-- 6. Size and place
--------------------------------------------------------------------------------

ns.HandleSlash("quest size large")
suite.check("/beq quest size sizes this panel", math.abs(Panel:SizePercent() - 120) < 0.5, Panel:SizePercent())
ns.HandleSlash("quest size normal")
suite.check("and back", math.abs(Panel:SizePercent() - 100) < 0.5, Panel:SizePercent())

--------------------------------------------------------------------------------
-- 7. Panel: Show, and the red gem
--------------------------------------------------------------------------------

Panel:SetOff(true)
suite.check("Panel: Show unticked hides it", not Up(Panel.frame) and ns.db.questPanelOff == true)
suite.check("the quest stays on", Quest:IsEnabled() and Quest:Current() ~= nil)
Panel:SetOff(false)
suite.check("ticked again it is back", Up(Panel.frame) and ns.db.questPanelOff == nil)

local kept = Quest:Current()
Panel.gems.close:GetScript("OnClick")(Panel.gems.close, "LeftButton")
suite.check("the red gem turns the upgrade quest off", not Quest:IsEnabled())
suite.check("its quest is kept", ns.charDB.upgradeQuestTabs ~= nil and kept ~= nil
    and Quest:QuestOn(Quest:Tab()) == kept)
suite.check("the panel goes, tracked upgrade or not", not Up(Panel.frame))
Tracking:Track({ itemID = 1001, link = "item:1001", slot = 5,
    source = { kind = "vendor", name = "Corina Steele", zone = "Elwynn Forest", x = 41.5, y = 65.9 } })
suite.check("a new tracked upgrade brings it back", Up(Panel.frame))
suite.check("with no Quest tab while the quest is off", not Up(Panel.tabs.quest) and Panel:View() == "tracking")
suite.check("and two on the Tracking tab", Panel.tabs.tracking.label:GetText() == "Tracking 2",
    Panel.tabs.tracking.label:GetText())

ns.db.showTracker = false
Panel:OnTrackingChanged()
suite.check("Upgrade Tracker unticked hides it with the quest off", not Up(Panel.frame))
ns.db.showTracker = nil
Tracking:Untrack(1001)
Tracking:Untrack(1101)
suite.check("nothing tracked and the quest off: no panel", not Up(Panel.frame))

ns.HandleSlash("quest")
suite.check("/beq quest brings it back on Quest", Up(Panel.frame) and Panel:View() == "quest"
    and Quest:Current() == kept)

--------------------------------------------------------------------------------
-- 8. In a fight
--------------------------------------------------------------------------------

do
    local state = Quest.state
    Quest.state = "waiting"
    suite.check("looking, out of a fight", Panel.EmptyText() == "Looking for your next upgrade...", Panel.EmptyText())
    fighting = true
    suite.check("in a fight it says the upgrade comes after",
        Panel.EmptyText() == "Your next upgrade comes after the fight.", Panel.EmptyText())
    fighting = false
    Quest.state = state
end

--------------------------------------------------------------------------------
-- 9. Saved keys
--------------------------------------------------------------------------------

do
    ns.db.questX, ns.db.questY = -100, -200
    ns.db.questPoint, ns.db.questRelativePoint = "RIGHT", "RIGHT"
    Panel:RestorePosition()
    local point, _, relative, x, y = Panel.frame:GetPoint()
    suite.check("it opens where the old panel was dragged", point == "RIGHT" and relative == "RIGHT"
        and math.abs(x + 100) < 0.5 and math.abs(y + 200) < 0.5, tostring(x) .. " " .. tostring(y))
    suite.check("the see-through level is the quest panel's own",
        ns.SeeThrough.PANELS.panel.key == "questPanelSeeThrough")
end

--------------------------------------------------------------------------------
-- 10. New Upgrade Unlocked never covers the panel (the owner's screenshot,
--     2026-11-23: with the panel at the top of the screen the offer was
--     pushed down onto its tabs and buttons)
--------------------------------------------------------------------------------

do
    UIParent._width = 3840
    local frame = env.Stub({ _width = 384, _height = 300, _left = 3400, _top = 2150 })
    local box = Panel:BuildOffer()
    box._width, box._height = 290, 120
    local saved = Panel.frame
    Panel.frame = frame

    Panel:PlaceOffer(box)
    local point, anchor, relative, _, y = box:GetPoint()
    suite.check("panel at the top: the offer goes under it", box.side == "below"
        and point == "TOPRIGHT" and anchor == frame and relative == "BOTTOMRIGHT" and y < 0,
        tostring(box.side))

    frame._top = 1000
    Panel:PlaceOffer(box)
    suite.check("room above: the offer sits above the panel", box.side == "above")

    frame._top, frame._height = 2150, 2100
    Panel:PlaceOffer(box)
    suite.check("a tall panel: the offer goes to its left", box.side == "left")

    frame._left = 100
    suite.check("a tall panel on the left edge: the offer goes to its right",
        Panel.OfferSide(frame, box) == "right")

    frame._top = nil
    suite.check("not laid out yet: above, as before", Panel.OfferSide(frame, box) == "above")
    Panel.frame = saved
    box:Hide()
end

Compare.Judge, Finder.Build = realJudge, realBuild
suite.done()
