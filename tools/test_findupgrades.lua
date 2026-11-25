-- Find Upgrades, the Equipment window's second tab (UI/FindUpgrades.lua,
-- rework step 3, the owner approved the mockup 2026-11-22).
--
-- What must hold:
--   1. The tab lists every slot's upgrades in one list, the biggest gain
--      first, with a count beside each kind of source.
--   2. The filters down the left narrow it, and are the saved choices the
--      old list and the upgrade quest read. Show All puts them back.
--   3. Find narrows by item or place as you type.
--   4. Every heading sorts; a third click goes back to best first.
--   5. A click on a row fills the sheet: the item, its gain, every place to
--      get it, the one in your zone first, and its buttons.
--   6. Make It My Quest follows it, Track tracks it, and Ignore takes it
--      off the list and onto the ignored list.
--   7. Clicks, sorting, filters and typing judge no gear and start no scan.
--      Opening it again with nothing changed doesn't either, and a hidden
--      page does nothing when events come.
--   8. Plan Ahead makes one scan a slice per frame and keeps it.
--   9. Gear waiting on a level shows in amber and can't be a quest yet.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("findupgrades")

local ARMOR, LEATHER = 4, 2
local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end
local function Piece(loc, n, level)
    return { loc = loc, class = ARMOR, subclass = LEATHER, stats = Agi(n), bind = 0, minLevel = level }
end

local ITEMS = {
    ["item:800"] = Piece("INVTYPE_HEAD", 5),       -- worn
    ["item:900"] = Piece("INVTYPE_CHEST", 10),     -- worn
    ["item:1001"] = Piece("INVTYPE_CHEST", 15),
    ["item:1002"] = Piece("INVTYPE_CHEST", 20),
    ["item:1101"] = Piece("INVTYPE_HEAD", 8),
    ["item:1102"] = Piece("INVTYPE_HEAD", 12),
    ["item:1201"] = Piece("INVTYPE_LEGS", 5),
    ["item:1301"] = Piece("INVTYPE_HEAD", 30, 22), -- for level 22
}

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitRace = function() return "Human", "Human", 1 end
env.InstallItems(ITEMS, { [1] = "item:800", [5] = "item:900" }, { [0] = {} }, 20)

local S = ns.Sources
ns.Crafts.ITEMS = {}
ns.RollData.ITEMS = {}
S.ZONES = { [12] = "Elwynn Forest", [40] = "Westfall" }
S.NPCS = {
    [1] = { "Corina Steele", 12, 41.5, 65.9, "A" },
    [2] = { "Gina MacGregor", 40, 57.6, 53.9, "A" },
}
S.QUESTS, S.DUNGEONS, S.BOSSES, S.FOREVER = {}, {}, {}, {}
S.ITEMS = {}
-- Sold in Elwynn Forest, the helm 1102 only in Westfall, the chest 1002 in both.
for _, id in ipairs({ 1001, 1101, 1201 }) do S.ITEMS[id] = { 15, 15, 0, 0, 100, v = { 1, 0 } } end
S.ITEMS[1102] = { 15, 15, 0, 0, 100, v = { 2, 0 } }
S.ITEMS[1002] = { 15, 15, 0, 0, 100, v = { 2, 0, 1, 0 } }
S.ITEMS[1301] = { 22, 22, 0, 0, 100, v = { 1, 0 } }

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end

local Gear, Find, Finder, Compare, FinderUI = ns.GearWindow, ns.FindUpgrades, ns.Finder, ns.Compare, ns.FinderUI
local Quest = ns.UpgradeQuest
Quest.Zone = function() return "Elwynn Forest" end

local judges, sources, scans, whole = 0, 0, 0, 0
local realJudge, realSources, realBuild, realScan = Compare.Judge, Finder.SourcesFor, Finder.Build, Finder.Scan
Compare.Judge = function(...) judges = judges + 1 return realJudge(...) end
Finder.SourcesFor = function(...) sources = sources + 1 return realSources(...) end
Finder.Build = function(...) scans = scans + 1 return realBuild(...) end
-- The old list scanned in one go on every click. This page never does.
Finder.Scan = function(...) whole = whole + 1 return realScan(...) end
local function Quiet() judges, sources, scans = 0, 0, 0 end
local function Worked() return judges + sources + scans end

--- The rows in view, as item IDs in order.
local function Listed()
    local out = {}
    for _, row in ipairs(Find.rows) do
        if row:IsShown() and rawget(row, "line") then out[#out + 1] = row.line.pick.itemID end
    end
    return table.concat(out, ",")
end
local function Row(itemID)
    for _, row in ipairs(Find.rows) do
        if row:IsShown() and rawget(row, "line") and row.line.pick.itemID == itemID then return row end
    end
end
local function Box(kind)
    for _, box in ipairs(Find.sourceBoxes) do
        if box.kind == kind then return box end
    end
end
local function Button(text)
    for _, button in ipairs(Find.sheetButtons) do
        if button:IsShown() and button.label:GetText() == text then return button end
    end
end
local function Click(frame, ...) frame:GetScript("OnClick")(frame, ...) end
local function Places()
    local out = {}
    for _, label in ipairs(Find.sheetPlaces) do
        if label:IsShown() then out[#out + 1] = label:GetText() end
    end
    return out
end

-- 1.
local tabKeys = {}
ns.UI:Show()
for _, tab in ipairs(Gear.strip.tabs) do tabKeys[#tabKeys + 1] = tab.key .. "=" .. tab.label:GetText() end
suite.check("Find Upgrades is the second tab", tabKeys[2] == "find=Find Upgrades", tabKeys[2])
Gear:ShowTab("find")
-- The fake game gives every frame one size; the sheet is this tall in the window.
Find.sheetHold:SetHeight(590)
suite.check("the tab shows its page", Gear.tab == "find" and Find:IsShown() and not ns.MyGear:IsShown())
suite.check("and not the old list", not (FinderUI.frame and FinderUI.frame:IsShown()))
suite.check("every slot in one list, the biggest gain first", Listed() == "1201,1102,1002,1101,1001", Listed())
suite.check("each row names its slot", Row(1201).slot:GetText() == "Legs" and Row(1102).slot:GetText() == "Head"
    and Row(1002).slot:GetText() == "Chest")
suite.check("its gain", Row(1102).gain:GetText() == "+140%" and Row(1201).gain:GetText() == "empty slot",
    Row(1102).gain:GetText())
suite.check("and where it is from", Row(1102).where:GetText():find("Vendor", 1, true) ~= nil
    and Row(1102).where:GetText():find("Westfall", 1, true) ~= nil, Row(1102).where:GetText())
suite.check("the zone you stand in is green", Row(1201).where:GetText():find("|cff%x%x%x%x%x%xElwynn Forest|r") ~= nil,
    Row(1201).where:GetText())
suite.check("each source counts its upgrades", Find.sourceCounts.vendor:GetText() == "5"
    and Find.sourceCounts.quest:GetText() == "0" and Find.sourceCounts.craft:GetText() == "0",
    Find.sourceCounts.vendor:GetText())
suite.check("the footer counts them", Find.footer:GetText():find("5 upgrades you can go and get.", 1, true) == 1,
    Find.footer:GetText())
suite.check("the rows are dark glass in turn", Find.rows[1].restKey == "glass" and Find.rows[2].restKey == "glassAlt")
suite.check("it never scans in one go", whole == 0, whole)

-- 5. (before the filters move the rows)
suite.check("the top row is picked for the sheet", Find.picked == "1201:7"
    and Find.sheetHold:IsShown() and Find.sheetName:GetText():find("1201", 1, true) ~= nil, Find.picked)
Quiet()
Click(Row(1002), "LeftButton")
suite.check("a click picks a row", Find.picked == "1002:5")
suite.check("the sheet names it", Find.sheetName:GetText():find("1002", 1, true) ~= nil, Find.sheetName:GetText())
suite.check("its slot and kind", Find.sheetKind:GetText():find("Chest", 1, true) == 1, Find.sheetKind:GetText())
suite.check("its gain", Find.sheetGain:GetText() == "+100%", Find.sheetGain:GetText())
suite.check("and what you wear there", Find.sheetNotes:GetText():find("You wear:", 1, true) == 1
    and Find.sheetNotes:GetText():find("900", 1, true) ~= nil, Find.sheetNotes:GetText())
local places = Places()
suite.check("every place to get it", #places == 2 and #Find.places == 2, #places .. " " .. #Find.places .. " " .. tostring(Find.sheetHold:GetHeight()))
suite.check("the one in your zone first", places[1] and places[1]:find("Corina Steele", 1, true) ~= nil
    and places[2]:find("Gina MacGregor", 1, true) ~= nil, places[1])
suite.check("with Make It My Quest, Track, Show on Map and Ignore", Button("Make It My Quest") ~= nil
    and Button("Track") ~= nil and Button("Show on Map") ~= nil and Button("Ignore") ~= nil)
suite.check("no Queue It for gear nobody crafts", Button("Queue It") == nil)
suite.check("the buttons share one width", Button("Track"):GetWidth() == Button("Ignore"):GetWidth()
    and Button("Track"):GetWidth() == Button("Show on Map"):GetWidth())
suite.check("the picked row is lit", Row(1002).edge:IsShown() and not Row(1001).edge:IsShown())
suite.check("a click judges nothing", Worked() == 0, Worked())

-- 2.
Quiet()
Click(Box("vendor"))
suite.check("unticking Vendor empties the list", Listed() == "" and ns.db.finderSourcesOff.vendor == true)
suite.check("and says the filters hide them, with Show All", Find.empty:IsShown()
    and Find.empty:GetText() == "Your filters hide 5 more.", Find.empty:GetText())
suite.check("the count beside Vendor stays", Find.sourceCounts.vendor:GetText() == "5")
suite.check("the old list's filter agrees", #FinderUI:SourceFilter(Find.state.found)(Find.state.lines[1].pick) == 0)
suite.check("an empty list leaves the sheet bare", not Find.sheetHold:IsShown())
Click(Box("vendor"))
suite.check("ticked again they come back", Listed() == "1201,1102,1002,1101,1001" and not Find.empty:IsShown(),
    Listed())

Find.slotChoice:Pick(1)
suite.check("the slot drop-down narrows to Head", Listed() == "1102,1101" and ns.db.findSlot == 1, Listed())
suite.check("the footer says what is hidden", Find.footer:GetText():find("Your filters hide 3 more.", 1, true) ~= nil,
    Find.footer:GetText())
Find.slotChoice:Pick(0)
suite.check("All Slots shows every slot again", Listed() == "1201,1102,1002,1101,1001" and ns.db.findSlot == nil
    and Find.slotChoice.label:GetText() == "All Slots", Find.slotChoice.label:GetText())

Click(Find.zoneBox)
suite.check("This Zone Only keeps to the zone", Listed() == "1201,1002,1101,1001" and ns.db.finderZoneOnly == true,
    Listed())
suite.check("and the counts follow", Find.sourceCounts.vendor:GetText() == "4")
Find.slotChoice:Pick(1)
Click(Find.showAll)
suite.check("Show All puts the filters back", Listed() == "1201,1102,1002,1101,1001"
    and ns.db.finderZoneOnly == false and ns.db.findSlot == nil and not Find.zoneBox:GetChecked(), Listed())
suite.check("filters judge nothing", Worked() == 0, Worked())

Click(Find.soloBox)
suite.check("Solo Quests Only is the upgrade quest's switch", ns.db.soloQuestsOnly == true and Finder:SoloOnly())
Click(Find.soloBox)
suite.check("Quest Level reads as approved", Find.QuestLevelsText(4) == "Up to 4 Above Mine"
    and Find.QuestLevelsText(0) == "Up to my level" and Find.QuestLevelsText(Finder.QUEST_LEVELS_ANY) == "Any")
suite.check("and shows the saved level", Find.questLevels:GetValue() == FinderUI:QuestLevelsValue())

-- 3.
Quiet()
local function Type(text)
    Find.findBox.editBox:SetText(text)
    Find.findBox.editBox:GetScript("OnTextChanged")(Find.findBox.editBox, true)
end
Type("1102")
suite.check("Find narrows by item name", Listed() == "1102", Listed())
Type("GINA")
suite.check("by who sells it, in any case", Listed() == "1102,1002", Listed())
Type("westfall")
suite.check("and by zone", Listed() == "1102,1002", Listed())
Type("nothing like this")
suite.check("nothing found says so", Listed() == "" and Find.empty:IsShown())
Type("")
suite.check("cleared, the list is whole", Listed() == "1201,1102,1002,1101,1001", Listed())
suite.check("typing judges nothing", Worked() == 0, Worked())

-- 4.
Quiet()
local function Head(key)
    for _, head in ipairs(Find.heads) do
        if head.key == key then return head end
    end
end
suite.check("a heading each for Item, Slot, Where, Level and Gain", Head("item") and Head("slot") and Head("where")
    and Head("level") and Head("gain") and #Find.heads == 6 and not Head("off"):IsShown())
suite.check("Gain is the sorted one to start", Head("gain").arrow:IsShown() and not Head("item").arrow:IsShown())
Click(Head("item"))
suite.check("Item sorts by name", Listed() == "1001,1002,1101,1102,1201" and Head("item").arrow:IsShown(), Listed())
Click(Head("item"))
suite.check("again turns it round", Listed() == "1201,1102,1101,1002,1001", Listed())
Click(Head("item"))
suite.check("a third time goes back to best first", Listed() == "1201,1102,1002,1101,1001"
    and Head("gain").arrow:IsShown(), Listed())
Click(Head("slot"))
suite.check("Slot sorts in sheet order", Listed() == "1102,1101,1002,1001,1201", Listed())
Click(Head("gain"))
Click(Head("gain"))
suite.check("Gain turned round starts with the smallest", Listed() == "1001,1101,1002,1102,1201", Listed())
Click(Head("gain"))
suite.check("sorting judges nothing", Worked() == 0, Worked())

-- The wheel moves the rows; the list is not read again.
Find.listArea = 90
Find:Draw()
suite.check("a short list shows what fits", Find.inView < 5 and Find.thumb:IsShown(), Find.inView)
local first = Find.rows[1].line.pick.itemID
Find.list:GetScript("OnMouseWheel")(Find.list, -1)
suite.check("the wheel scrolls", Find.offset > 0 and Find.rows[1].line.pick.itemID ~= first, Find.offset)
for _ = 1, 10 do Find.list:GetScript("OnMouseWheel")(Find.list, -1) end
suite.check("never past the last row", Find.atEnd and Find.inView >= 1 and Find.offset <= 4, Find.offset)
Find.list:GetScript("OnMouseWheel")(Find.list, 50)
Find.list:GetScript("OnMouseWheel")(Find.list, 50)
suite.check("nor past the top", Find.offset == 0)
Find.listArea = nil
Find:Narrow()
suite.check("scrolling judges nothing", Worked() == 0, Worked())

-- 6.
suite.check("the upgrade quest starts off", not Quest:IsEnabled())
Click(Row(1101), "LeftButton")
Click(Button("Make It My Quest"))
suite.check("Make It My Quest follows it", Quest:IsEnabled() and Quest:IsFollowing(1101))
Find:Draw()
suite.check("and its row says Following", Row(1101).item:GetText():find("Following", 1, true) ~= nil,
    Row(1101).item:GetText())
Click(Button("Track"))
suite.check("Track tracks it", ns.Tracking:IsTracked(1101))
Find:PaintSheet()
suite.check("and the button turns to Stop Tracking", Button("Stop Tracking") ~= nil and Button("Track") == nil)
Click(Button("Stop Tracking"))
suite.check("which lets it go", not ns.Tracking:IsTracked(1101))

Click(Button("Ignore"))
suite.check("Ignore puts it on the ignored list", Quest:Skipped()[1101] == true)
suite.check("drops it as the quest", not Quest:IsFollowing(1101))
suite.check("and takes it off the list", Listed() == "1201,1102,1002,1001", Listed())
suite.check("the next row takes the sheet", Find.picked ~= "1101:1" and Find.sheetHold:IsShown(), Find.picked)
local ignored = Quest:IgnoredList()
suite.check("Settings' Ignored list holds it", #ignored == 1 and ignored[1].itemID == 1101, #ignored)
Quest:Restore(1101)
suite.check("restored there, it is back here", Listed() == "1201,1102,1002,1101,1001", Listed())

-- A right-click opens the menu the old list had.
local menu
local realOpen = ns.RowMenu.Open
ns.RowMenu.Open = function(_, lines, opts) menu = { lines = lines, title = opts and opts.title } end
Click(Row(1002), "RightButton")
ns.RowMenu.Open = realOpen
suite.check("a right-click opens the row's menu", menu ~= nil and #menu.lines >= 2 and menu.lines[1].text == "Follow",
    menu and #menu.lines)
suite.check("and picks the row", Find.picked == "1002:5")

-- 7.
-- Let the engine's last look for item answers finish first.
for _ = 1, 6 do
    if Finder:Fresh() then break end
end
Quiet()
Gear:ShowTab("gear")
Gear:ShowTab("find")
suite.check("opened again with nothing changed, nothing is judged", judges == 0 and scans == 0,
    judges .. " " .. scans)
Gear:Close()
Finder:MarkStale()
Quiet()
Find:RefreshSoon()
suite.check("a hidden page starts no scan", scans == 0 and Find:Refresh() == nil, scans)
Gear:Open("find")
suite.check("shown again after a change, it looks again", scans >= 1 and Find:IsShown(), scans)
for _ = 1, 6 do
    if Finder:Fresh() then break end
end
suite.check("still never in one go", whole == 0, whole)

-- 8. and 9.
Quiet()
Find.aheadChoice:Pick(2)
suite.check("Plan Ahead is the old list's saved choice", ns.db.finderAhead == 2)
-- One look, and the engine's one more each time item answers came in
-- while it ran. The "kept" check below shows it has stopped.
suite.check("it makes a scan of its own, and stops", scans >= 1 and scans <= 4, scans)
suite.check("which adds the gear two levels on", Row(1301) ~= nil, Listed())
local later = Row(1301)
suite.check("in amber, with its level", later and later.level:GetText() == "22"
    and select(2, Find.GainText(later.line.pick)) == "warn", later and later.level:GetText())
Click(later, "LeftButton")
suite.check("the sheet says what it waits on", Find.sheetNotes:GetText():find("You can wear it from level 22", 1, true) ~= nil,
    Find.sheetNotes:GetText())
suite.check("and why it can't be a quest yet", Find.sheetWhy:IsShown()
    and Find.sheetWhy:GetText():find("Not a quest yet:", 1, true) == 1 and Button("Make It My Quest").dimmed == true,
    Find.sheetWhy:GetText())
suite.check("the footer explains amber", Find.footer:GetText():find("Amber gear is for later", 1, true) ~= nil,
    Find.footer:GetText())
Quiet()
Gear:ShowTab("gear")
Gear:ShowTab("find")
suite.check("kept: opening again scans nothing", scans == 0 and Row(1301) ~= nil, scans)
Find.aheadChoice:Pick(0)
suite.check("back to Now, the later gear goes", Row(1301) == nil and ns.db.finderAhead == 0, Listed())
suite.check("never in one go", whole == 0, whole)

-- The old list's callers open this tab now.
Gear:Close()
FinderUI.OpenFind()
suite.check("the banner, the quest panel's Change and the slot pop-up open Find Upgrades",
    Gear:IsShown() and Gear.tab == "find")
Gear:Close()

suite.done()
