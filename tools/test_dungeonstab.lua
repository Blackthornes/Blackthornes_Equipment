-- The Dungeons tab, the Equipment window's fourth (UI/DungeonsTab.lua,
-- rework step 5, the owner approved the mockup 2026-11-22).
--
-- What must hold:
--   1. It is a tab of the Equipment window, after Upgrade Quest, and
--      /beq loot and /beq dungeons open it.
--   2. The left lists every dungeon for this side with its levels, how
--      many drops are upgrades and how many quests are done. One above
--      the character's level reads Later.
--   3. A dungeon is picked once: the right shows its bosses with their
--      drops, chance and gain, then QUESTS INSIDE.
--   4. Upgrades Only hides the rest. Hide Finished Quests is the old
--      tab's saved choice.
--   5. A heading sorts the left list; a second click flips it.
--   6. A click on an upgrade's drop offers the upgrade lists' menu.
--   7. A click on a dungeon, a heading or a box starts no scan, a second
--      look judges nothing, and a hidden page does nothing.
--   8. A wing shows its dungeon's quests, and the other side's dungeons
--      and quests never show.
--   9. A drop you own already (in your bags or bank) is no upgrade to go
--      get: it says where it is, Upgrades Only hides it, and the count and
--      Find Upgrades leave it out (a player's report, 2026-11-25).

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("dungeonstab")

local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end
local function Gear(loc, n) return { loc = loc, class = 4, subclass = 2, stats = Agi(n) } end

local ITEMS = {
    ["item:900"] = Gear("INVTYPE_CHEST", 10),   -- worn
    ["item:901"] = Gear("INVTYPE_HEAD", 10),    -- worn
    ["item:1001"] = Gear("INVTYPE_CHEST", 20),  -- Lord Test drops it: +100%
    ["item:1002"] = Gear("INVTYPE_HEAD", 15),   -- Lady Test drops it: +50%
    ["item:1003"] = Gear("INVTYPE_CHEST", 5),   -- Lady Test drops it: worse
    ["item:1004"] = Gear("INVTYPE_HEAD", 30),   -- a quest's reward
    ["item:1005"] = Gear("INVTYPE_CHEST", 40),  -- drops in the far dungeon
    ["item:1006"] = Gear("INVTYPE_CHEST", 12),  -- drops in the wing
}

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitFactionGroup = function() return "Horde", "Horde" end
_G.UnitRace = function() return "Orc", "Orc", 2 end
_G.GetRealZoneText = function() return "The Barrens" end
env.InstallItems(ITEMS, { [5] = "item:900", [1] = "item:901" }, { [0] = {} }, 20)

_G.C_QuestLog = {
    IsQuestFlaggedCompleted = function() return false end,
    IsOnQuest = function() return false end,
    ReadyForTurnIn = function() return false end,
}

local S = ns.Sources
ns.Crafts.ITEMS = {}
ns.RollData.ITEMS = {}
S.ZONES, S.NPCS, S.QUESTS, S.FOREVER = {}, {}, {}, {}
S.DUNGEONS = {
    ["43"] = { "Test Caverns", 17, 24, "The Barrens", "" },
    ["209"] = { "Far Farrak", 44, 54, "Tanaris", "" },
    ["34"] = { "Alliance Stockade", 18, 24, "Stormwind City", "A" },
    ["189"] = { "Test Monastery", 18, 30, "Tirisfal Glades", "" },
    ["189Library"] = { "Test Monastery Library", 18, 28, "Tirisfal Glades", "" },
}
S.BOSSES = {
    [9101] = { "Lord Test", "43", 20 }, [9102] = { "Lady Test", "43", 21 },
    [9103] = { "Far Boss", "209", 46 }, [9104] = { "Stockade Boss", "34", 24 },
    [9105] = { "Librarian", "189Library", 22 },
}
S.ITEMS = {
    [1001] = { 15, 18, 0, 0, 0, d = { 9101, 24 } },
    [1002] = { 15, 18, 0, 0, 0, d = { 9102, 0.4 } },
    [1003] = { 15, 18, 0, 0, 0, d = { 9102, 30 } },
    [1005] = { 15, 18, 0, 0, 0, d = { 9103, 10, 9104, 10 } },
    [1006] = { 15, 18, 0, 0, 0, d = { 9105, 12 } },
}
ns.FOREVER_BOSSES, ns.FOREVER_DUNGEON_PLACES = {}, {}
ns.FOREVER_DUNGEON_QUESTS = {}
ns.DUNGEON_QUESTS = {
    [1] = { "43", "Leaders of the Fang", 10, 22, "H", 0, "Nara Wildmane", "Thunder Bluff", 75, 31, 1004, 0 },
    [2] = { "43", "Serpentbloom", 14, 18, "H", 0, "Apothecary Zamah", "Thunder Bluff", 23, 21, 0, 0 },
    [3] = { "43", "Deviate Eradication", 15, 21, "A", 0, "Ebru", "The Barrens", 46, 36, 0, 0 },
    [4] = { "189", "Hearts of Zeal", 18, 22, "H", 0, "Master Apothecary", "Undercity", 48, 69, 0, 0 },
    [5] = { "34", "Crime and Punishment", 18, 22, "A", 0, "Councilman", "Duskwood", 72, 47, 0, 0 },
}
ns.DungeonLoot.index = nil
ns.DungeonLoot.NameOf = function(itemID) return "item:" .. itemID end
ns.DungeonQuests.version = (ns.DungeonQuests.version or 0) + 1
local doneIDs = { [2] = true }
local realDone = ns.Finder.QuestDone
ns.Finder.QuestDone = function(self, id) return doneIDs[id] == true or realDone(self, id) end

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end

local Window, Tab, Finder, Compare = ns.GearWindow, ns.DungeonsTab, ns.Finder, ns.Compare

local judges, scans = 0, 0
local realJudge, realBuild = Compare.Judge, Finder.Build
Compare.Judge = function(...) judges = judges + 1 return realJudge(...) end
Finder.Build = function(...) scans = scans + 1 return realBuild(...) end
local function Quiet() judges, scans = 0, 0 end

local function Click(frame, ...) frame:GetScript("OnClick")(frame, ...) end
local function DungeonRow(name)
    for _, row in ipairs(Tab.dungeonRows) do
        if row:IsShown() and row.name:GetText() == name then return row end
    end
end
local function Names()
    local out = {}
    for _, row in ipairs(Tab.dungeonRows) do
        if row:IsShown() then out[#out + 1] = row.name:GetText() end
    end
    return table.concat(out, ",")
end
local function Lines()
    local out = {}
    for _, row in ipairs(Tab.rows) do
        if row:IsShown() then
            local line = rawget(row, "line")
            out[#out + 1] = line.kind .. ":" .. (row.name:GetText() or "") .. "|" .. (row.drops:GetText() or "")
                .. "|" .. (row.gain:GetText() or "")
        end
    end
    return table.concat(out, "\n")
end
local function LineRow(text)
    for _, row in ipairs(Tab.rows) do
        if row:IsShown() and row.name:GetText() == text then return row end
    end
end

--------------------------------------------------------------------------------
-- 1. A tab of the Equipment window
--------------------------------------------------------------------------------

do
    local keys = {}
    for _, tab in ipairs(Window.TABS) do keys[#keys + 1] = tab.key end
    suite.check("Dungeons comes after Upgrade Quest",
        table.concat(keys, ","):find("gear,find,quest,instances,", 1, true) == 1, table.concat(keys, ","))
    suite.check("the old Dungeon Quests and Dungeon Loot tabs are off the bar",
        not table.concat(keys, ","):find("loot", 1, true) and not table.concat(keys, ","):find("dungeons", 1, true))
    suite.check("the window knows its page", Window.pages.instances == Tab)
end

ns.HandleSlash("loot")
suite.check("/beq loot opens it", Window.tab == "instances" and Tab:IsShown())
Window:Close()
suite.check("closing the window hides the page", not Tab:IsShown())
ns.HandleSlash("dungeons")
suite.check("/beq dungeons opens it", Window.tab == "instances" and Tab:IsShown())
-- The fake game gives every frame the same small height; the page is as
-- tall as the window makes it in play.
Tab.page.GetHeight = function() return 668 end
Tab:Refresh()

--------------------------------------------------------------------------------
-- 2. The left list
--------------------------------------------------------------------------------

suite.check("this side's dungeons, by level, the wing for its dungeon",
    Names() == "Test Caverns,Test Monastery Library,Far Farrak", Names())
local caverns, far, wing = DungeonRow("Test Caverns"), DungeonRow("Far Farrak"), DungeonRow("Test Monastery Library")
suite.check("its levels", caverns.levels:GetText() == "17-24", caverns.levels:GetText())
suite.check("two of its drops are upgrades", caverns.upgrades:GetText() == "2", caverns.upgrades:GetText())
suite.check("one of its two quests is done, the other side's left out",
    caverns.quests:GetText() == "1 of 2", caverns.quests:GetText())
suite.check("a dungeon above the character's level reads Later", far.upgrades:GetText() == "Later",
    far.upgrades:GetText())
suite.check("the wing counts its own upgrade", wing.upgrades:GetText() == "1", wing.upgrades:GetText())
suite.check("and shows its dungeon's quests", wing.quests:GetText() == "0 of 1", wing.quests:GetText())

--------------------------------------------------------------------------------
-- 3. The dungeon picked
--------------------------------------------------------------------------------

suite.check("it opens on the first dungeon at the character's level",
    ns.db.dungeonLootPick == "43" and rawget(caverns, "picked") == true, tostring(ns.db.dungeonLootPick))
suite.check("the right names it", Tab.dungeonName:GetText() == "Test Caverns", Tab.dungeonName:GetText())
suite.check("and says where its door is", Tab.dungeonWhere:GetText() == "Door in The Barrens.",
    Tab.dungeonWhere:GetText())
local text = Lines()
suite.check("a boss heads its drops", text:find("boss:LORD TEST||\ndrop:item:1001|24%|+100%", 1, true) ~= nil, text)
suite.check("a rare drop says so", text:find("drop:item:1002|Under 1%|+50%", 1, true) ~= nil, text)
suite.check("a drop that is no upgrade has no gain", text:find("drop:item:1003|30%|\n", 1, true) ~= nil, text)
suite.check("the biggest upgrade's boss comes first",
    text:find("LORD TEST", 1, true) < text:find("LADY TEST", 1, true), text)
suite.check("then the quests inside", text:find("boss:QUESTS INSIDE", 1, true) ~= nil, text)
local toDo, done = LineRow("Leaders of the Fang"), LineRow("Serpentbloom")
suite.check("a quest to do says its level, where it starts and its reward",
    toDo ~= nil and toDo.sub:GetText():find("Level 22. Starts in Thunder Bluff. Reward: ", 1, true) == 1,
    toDo and toDo.sub:GetText())
suite.check("the reward shows its gain", toDo.sub:GetText():find("+200%", 1, true) ~= nil, toDo.sub:GetText())
suite.check("with Show the Way", toDo.way:IsShown())
suite.check("a finished quest reads Done, with no button",
    done ~= nil and done.gain:GetText() == "Done" and not done.way:IsShown(), done and done.gain:GetText())
suite.check("the other side's quest is not there", LineRow("Deviate Eradication") == nil)
suite.check("the foot sums it up",
    Tab.foot:GetText() == "Test Caverns: 2 upgrades for you, 1 quest left.", Tab.foot:GetText())

local aimed
ns.QuestArrow.AimAtQuest = function(_, id, title, place) aimed = { id = id, title = title, place = place } return true end
Click(toDo.way)
suite.check("Show the Way points at where the quest starts",
    aimed ~= nil and aimed.place.zone == "Thunder Bluff" and aimed.place.x == 75, aimed and aimed.place.zone)

--------------------------------------------------------------------------------
-- 4. The boxes
--------------------------------------------------------------------------------

Quiet()
Click(Tab.onlyBox)
text = Lines()
suite.check("Upgrades Only hides the rest", text:find("item:1003", 1, true) == nil
    and text:find("item:1001", 1, true) ~= nil and text:find("item:1002", 1, true) ~= nil, text)
suite.check("the quests stay", text:find("Leaders of the Fang", 1, true) ~= nil, text)
Click(Tab.onlyBox)
suite.check("unticked, they come back", Lines():find("item:1003", 1, true) ~= nil)

Click(Tab.hideBox)
suite.check("Hide Finished Quests is the old tab's saved choice", ns.db.dungeonQuestsHideDone == true)
suite.check("the finished quest goes", LineRow("Serpentbloom") == nil and LineRow("Leaders of the Fang") ~= nil)
suite.check("and the count stays", DungeonRow("Test Caverns").quests:GetText() == "1 of 2")
Click(Tab.hideBox)
suite.check("unticked, it clears the saved choice", ns.db.dungeonQuestsHideDone == nil
    and LineRow("Serpentbloom") ~= nil)
suite.check("the boxes started no scan and judged nothing", scans == 0 and judges == 0, scans .. " " .. judges)

-- The bar never lays one piece on another (a player's report, 2026-11-27:
-- Upgrades Only sat on the Find box, so it could not be ticked). Each
-- piece's span on its row, from where it is anchored and how wide it is.
local function Spans()
    local spans = {}
    for _, group in ipairs(Tab.barGroups) do
        local first = group.lead or group.item
        local _, _, _, x = first:GetPoint()
        spans[#spans + 1] = { x = x, y = group.row, right = x + group.width }
    end
    return spans
end
local function Overlaps(spans)
    for i = 1, #spans do
        for j = i + 1, #spans do
            local a, b = spans[i], spans[j]
            if a.y == b.y and a.x < b.right and b.x < a.right then return i .. " and " .. j end
        end
    end
    return nil
end
local function Resize(width)
    Tab.page._width = width
    Tab.page:GetScript("OnSizeChanged")(Tab.page)
end
Resize(1040)
local spans = Spans()
suite.check("on a wide window nothing in the bar overlaps", Overlaps(spans) == nil, tostring(Overlaps(spans)))
suite.check("Upgrades Only sits right of the Find box", spans[4].x >= spans[3].right, spans[4].x .. " " .. spans[3].right)
suite.check("and it is all one row", Tab.barRows == 1 and Tab.bodyTop == 52, Tab.barRows .. " " .. Tab.bodyTop)
Resize(560)
spans = Spans()
suite.check("on a narrow window the bar wraps, nothing overlaps", Overlaps(spans) == nil and Tab.barRows > 1,
    tostring(Overlaps(spans)) .. " " .. Tab.barRows)
suite.check("every piece stays inside the window", spans[5].right <= 560 - 18 and spans[4].right <= 560 - 18)
suite.check("and the lists move down under it", Tab.bodyTop > 52, Tab.bodyTop)
Resize(1040)
suite.check("wide again, one row and the lists move back", Tab.barRows == 1 and Tab.bodyTop == 52)

--------------------------------------------------------------------------------
-- 5. Sorting, and picking another
--------------------------------------------------------------------------------

Quiet()
Tab:SortBy("name")
suite.check("a heading sorts by name", Names() == "Far Farrak,Test Caverns,Test Monastery Library", Names())
Tab:SortBy("name")
suite.check("a second click flips it", Names() == "Test Monastery Library,Test Caverns,Far Farrak", Names())
Tab:SortBy("name")
suite.check("a third goes back to levels", Names() == "Test Caverns,Test Monastery Library,Far Farrak", Names())
Tab:SortBy("upgrades")
suite.check("Upgrades puts the most first and Later last",
    Names() == "Test Caverns,Test Monastery Library,Far Farrak", Names())
Tab:SortBy("quests")
suite.check("Quests puts the most left to do first", Names():find("Far Farrak", 1, true) ~= 1, Names())
Tab:SortBy("quests")
Tab:SortBy("quests")

Click(DungeonRow("Test Monastery Library"))
suite.check("a click picks a dungeon", ns.db.dungeonLootPick == "189Library"
    and Tab.dungeonName:GetText() == "Test Monastery Library")
text = Lines()
suite.check("its own drops show", text:find("boss:LIBRARIAN", 1, true) ~= nil
    and text:find("item:1006|12%|+20%", 1, true) ~= nil, text)
suite.check("with the quests of the dungeon it is a wing of", LineRow("Hearts of Zeal") ~= nil, text)
suite.check("sorting and picking started no scan", scans == 0, scans)
local firstLook = judges
Click(DungeonRow("Test Caverns"))
Click(DungeonRow("Test Monastery Library"))
suite.check("a second look at a dungeon judges nothing", judges == firstLook, judges - firstLook)

do
    local reads, realRows = 0, ns.DungeonLoot.Rows
    ns.DungeonLoot.Rows = function(...) reads = reads + 1 return realRows(...) end
    Tab:Scroll(3)
    Tab:Scroll(-3)
    Tab:ScrollDungeons(1)
    Tab:ScrollDungeons(-1)
    suite.check("the wheel reads no drops again", reads == 0, reads)
    ns.DungeonLoot.Rows = realRows
end

Click(DungeonRow("Far Farrak"))
suite.check("a dungeon for later says so in the foot",
    Tab.foot:GetText() == "Far Farrak: its gear is for later.", Tab.foot:GetText())
Click(DungeonRow("Test Caverns"))

--------------------------------------------------------------------------------
-- 6. A click on a drop
--------------------------------------------------------------------------------

local opened
local realOpen = ns.RowMenu.Open
ns.RowMenu.Open = function(self, lines, opts) opened = { lines = lines, opts = opts } return realOpen(self, lines, opts) end
Click(LineRow("item:1001"), "LeftButton")
local offers = {}
for _, line in ipairs(opened and opened.lines or {}) do offers[#offers + 1] = line.text end
suite.check("a click on an upgrade offers to follow it or track it",
    table.concat(offers, ","):find("Follow", 1, true) ~= nil and table.concat(offers, ","):find("Track", 1, true) ~= nil,
    table.concat(offers, ","))
opened = nil
Click(LineRow("item:1003"), "LeftButton")
suite.check("a drop that is no upgrade offers nothing", opened == nil)
ns.RowMenu.Open = realOpen
if ns.RowMenu.Close then ns.RowMenu:Close() end

--------------------------------------------------------------------------------
-- 7. Hidden, it does nothing
--------------------------------------------------------------------------------

Window:ShowTab("gear")
suite.check("another tab hides the page", not Tab:IsShown())
Quiet()
local drawn = Tab.foot:GetText()
Tab.foot:SetText("untouched")
Tab:RefreshSoon()
Tab:RedrawSoon()
Tab:OnDungeonQuestsChanged()
ns.DungeonQuests:Changed()
suite.check("hidden, it draws nothing and judges nothing",
    Tab.foot:GetText() == "untouched" and judges == 0, Tab.foot:GetText())
Tab.foot:SetText(drawn)

-- A quest handed in while it shows: the count moves.
Window:ShowTab("instances")
doneIDs[1] = true
ns.DungeonQuests:Changed()
suite.check("a quest handed in moves the count", DungeonRow("Test Caverns").quests:GetText() == "2 of 2",
    DungeonRow("Test Caverns").quests:GetText())
suite.check("and the foot", Tab.foot:GetText() == "Test Caverns: 2 upgrades for you, every quest done.",
    Tab.foot:GetText())

--------------------------------------------------------------------------------
-- 8. Rows are dark glass
--------------------------------------------------------------------------------

local row = DungeonRow("Test Monastery Library")
suite.check("rows take glass and glassAlt in turn",
    Tab.dungeonRows[1].restKey == "glass" and Tab.dungeonRows[2].restKey == "glassAlt")
row:GetScript("OnEnter")(row)
suite.check("the row under the mouse shows its gold edge", row.edge:IsShown())
row:GetScript("OnLeave")(row)
suite.check("and lets it go", not row.edge:IsShown())
suite.check("the picked row keeps its edge", DungeonRow("Test Caverns").edge:IsShown())

--------------------------------------------------------------------------------
-- 9. A drop you own already
--------------------------------------------------------------------------------

Window:ShowTab("instances")
Tab:Pick("43")
env.bags[0] = { [1] = "item:1001", [2] = "item:1004" }
doneIDs[1] = nil
ns.DungeonQuests:Changed()
Finder:OnBags()
Tab:Refresh()
text = Lines()
local reward = LineRow("Leaders of the Fang")
suite.check("a quest reward in your bags says so, with no gain",
    reward ~= nil and reward.sub:GetText():find("in your bags", 1, true) ~= nil
    and reward.sub:GetText():find("+200%", 1, true) == nil, reward and reward.sub:GetText())
suite.check("a drop in your bags says so, with no gain",
    text:find("drop:item:1001|24%|in your bags", 1, true) ~= nil, text)
suite.check("it no longer counts as an upgrade",
    DungeonRow("Test Caverns").upgrades:GetText() == "1", DungeonRow("Test Caverns").upgrades:GetText())
Click(Tab.onlyBox)
text = Lines()
suite.check("Upgrades Only hides it", text:find("item:1001", 1, true) == nil
    and text:find("item:1002", 1, true) ~= nil, text)
Click(Tab.onlyBox)
local listed = false
for _, list in pairs((Finder.latest or {}).all or {}) do
    for _, pick in ipairs(list) do if pick.itemID == 1001 then listed = true end end
end
suite.check("Find Upgrades leaves it out", not listed)

env.bags[0] = {}
Finder:OnBags()
_G.UnitGUID = function() return "Player-1-00000001" end
local guid = ns.Alts.PlayerGUID()
local notes = ns.Alts:Notes()
notes[guid] = notes[guid] or { name = "Test" }
notes[guid].bank = { { link = "item:1002", bound = true } }
Finder:MarkStale()
Tab:Refresh()
text = Lines()
suite.check("a drop in your bank says so",
    text:find("drop:item:1002|Under 1%|in your bank", 1, true) ~= nil, text)
suite.check("and the one back out of your bags is an upgrade again",
    text:find("drop:item:1001|24%|+100%", 1, true) ~= nil, text)
listed = false
for _, list in pairs((Finder.latest or {}).all or {}) do
    for _, pick in ipairs(list) do if pick.itemID == 1002 then listed = true end end
end
suite.check("Find Upgrades leaves out the one in the bank", not listed)
notes[guid].bank = nil
Finder:MarkStale()

Compare.Judge, Finder.Build = realJudge, realBuild
suite.done()
