-- My Gear, the page the Equipment window opens on (UI/MyGear.lua, rework
-- step 2, the owner approved the mockup 2026-11-22).
--
-- What must hold:
--   1. The window opens on My Gear, with a card for each thing to do next
--      and none for what there is nothing to do.
--   2. The figure marks each slot that has something better: green to wear
--      now, amber for later.
--   3. The slot's side lists what you own, then the top pieces to go and
--      get, those you can wear now first; See All opens Find Upgrades on
--      that slot.
--   4. Clicking slots, sorting the list and opening the window again with
--      nothing changed judge no gear: the page reads the finder's scan.
--   5. A hidden page does nothing when events come.
--   6. Put Them On puts on every bag upgrade, and waits for a fight's end.
--   7. List shows the same slots as rows that sort, and the view is kept.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("mygear")

local ARMOR, LEATHER = 4, 2
local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end
local function Piece(loc, n) return { loc = loc, class = ARMOR, subclass = LEATHER, stats = Agi(n), bind = 0 } end

local ITEMS = {
    ["item:800"] = Piece("INVTYPE_HEAD", 5),       -- worn
    ["item:900"] = Piece("INVTYPE_CHEST", 10),     -- worn
    ["item:901"] = Piece("INVTYPE_CHEST", 14),     -- in the bags
    ["item:902"] = Piece("INVTYPE_FEET", 3),       -- in the bags, for an empty slot
    ["item:1001"] = Piece("INVTYPE_CHEST", 15),
    ["item:1002"] = Piece("INVTYPE_CHEST", 20),
    ["item:1101"] = Piece("INVTYPE_HEAD", 8),
    ["item:1102"] = Piece("INVTYPE_HEAD", 12),
    ["item:1103"] = Piece("INVTYPE_HEAD", 9),
    ["item:1104"] = Piece("INVTYPE_HEAD", 7),
    ["item:1201"] = Piece("INVTYPE_LEGS", 5),
}

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitRace = function() return "Human", "Human", 1 end
env.InstallItems(ITEMS, { [1] = "item:800", [5] = "item:900" }, { [0] = { "item:901", "item:902" } }, 20)

local S = ns.Sources
ns.Crafts.ITEMS = {}
ns.RollData.ITEMS = {}
S.ZONES = { [12] = "Elwynn Forest" }
S.NPCS = { [1] = { "Corina Steele", 12, 41.5, 65.9, "A" } }
S.QUESTS, S.DUNGEONS, S.BOSSES, S.FOREVER = {}, {}, {}, {}
S.ITEMS = {}
for _, id in ipairs({ 1001, 1002, 1101, 1102, 1103, 1104, 1201 }) do
    S.ITEMS[id] = { 15, 15, 0, 0, 100, v = { 1, 0 } }
end

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end

local Gear, MyGear, Finder, Compare = ns.GearWindow, ns.MyGear, ns.Finder, ns.Compare

local judges, sources = 0, 0
local realJudge, realSources = Compare.Judge, Finder.SourcesFor
Compare.Judge = function(...) judges = judges + 1 return realJudge(...) end
Finder.SourcesFor = function(...) sources = sources + 1 return realSources(...) end

local function Heading(row) return row:IsShown() and rawget(row, "heading") == true and row.headingLabel:GetText() or nil end

--- The slot side's rows, as words: "IN YOUR BAGS", "owned item:901", "pick 1102".
local function Side()
    local out = {}
    for _, row in ipairs(MyGear.rows) do
        if row:IsShown() then
            local owned, pick = rawget(row, "owned"), rawget(row, "pick")
            if Heading(row) then
                out[#out + 1] = Heading(row)
            elseif owned then
                out[#out + 1] = "owned " .. owned.link
            elseif pick then
                out[#out + 1] = "pick " .. pick.itemID
            elseif rawget(row, "enchant") then
                out[#out + 1] = "enchant"
            end
        end
    end
    return table.concat(out, ", ")
end

-- 1.
ns.UI:Show()
local state = MyGear.state
suite.check("the window opens on My Gear", Gear.frame:IsShown() and Gear.tab == "gear" and MyGear:IsShown())
suite.check("with the finder's scan read", type(state) == "table" and state.found ~= nil)
suite.check("two upgrades are ready in the bags", #state.ready == 2, #state.ready)
suite.check("the first card says so", MyGear.cards.ready:IsShown()
    and MyGear.cards.ready.line:GetText() == "2 upgrades in your bags."
    and MyGear.cards.ready.button.label:GetText() == "Put Them On", MyGear.cards.ready.line:GetText())
suite.check("the second card names the best piece to go and get", MyGear.cards.next:IsShown()
    and state.next ~= nil and state.next.itemID == 1201, state.next and state.next.itemID)
suite.check("with Show Me How", MyGear.cards.next.button.label:GetText() == "Show Me How")
suite.check("the trainer card shows only with spells to train",
    (state.training ~= nil) == (MyGear.cards.trainer:IsShown() == true),
    state.training and state.training.count)
suite.check("the cards are numbered in order", MyGear.cards.ready.number:GetText() == "1"
    and MyGear.cards.next.number:GetText() == "2")

-- 2.
local head, chest, feet, neck = MyGear.slotButtons[1], MyGear.slotButtons[5], MyGear.slotButtons[8], MyGear.slotButtons[2]
suite.check("a button for each of the 17 slots", (function()
    local count = 0
    for _ in pairs(MyGear.slotButtons) do count = count + 1 end
    return count
end)() == 17)
suite.check("the head has an arrow and its gain", head.arrow:IsShown() and head.gain:GetText() == "+140%",
    head.gain:GetText())
suite.check("the chest shows the bag piece's gain", chest.arrow:IsShown() and chest.gain:GetText() == "+40%",
    chest.gain:GetText())
suite.check("an empty slot says Empty and takes the bag piece", feet.name:GetText():find("Empty", 1, true) ~= nil
    and feet.arrow:IsShown())
suite.check("a slot with nothing better has no arrow", not neck.arrow:IsShown() and not neck.strip:IsShown())
suite.check("four slots have an upgrade", state.upgrades == 4, state.upgrades)
suite.check("the footer counts them", MyGear.footer:GetText():find("4 slots have an upgrade.", 1, true) == 1, MyGear.footer:GetText())
suite.check("the ring counts them too", MyGear.countLabel:GetText() == "4 upgrades", MyGear.countLabel:GetText())

-- 3.
suite.check("it opens on the first slot with a piece to wear now", MyGear.slot == 5, MyGear.slot)
MyGear:PickSlot(1)
suite.check("the head's side lists the top three to go and get",
    Side() == "TO GO AND GET, pick 1102, pick 1103, pick 1101", Side())
suite.check("with See All for Head", MyGear.seeAll:IsShown() and MyGear.seeAll.label:GetText() == "See All for Head",
    MyGear.seeAll.label:GetText())

-- 4.
judges, sources = 0, 0
MyGear:PickSlot(5)
suite.check("a click shows the chest", MyGear.slot == 5
    and Side() == "IN YOUR BAGS, owned item:901, BEST ENCHANT, enchant, TO GO AND GET, pick 1002, pick 1001", Side())
local ownedRow
for _, row in ipairs(MyGear.rows) do
    if row:IsShown() and rawget(row, "owned") then ownedRow = row end
end
suite.check("the bag piece has Put It On", ownedRow and ownedRow.putOn:IsShown())
MyGear:PickSlot(2)
suite.check("a slot with nothing says so", Side() == "" and MyGear.empty:IsShown()
    and MyGear.empty:GetText() == "Nothing on offer beats what you wear here." and not MyGear.seeAll:IsShown())
MyGear:PickSlot(1)
suite.check("clicking slots judges no gear", judges == 0 and sources == 0, judges .. " " .. sources)

-- The first scan asked the server about gear; one more look follows
-- once those answers are in, and then the scan is up to date.
MyGear:Refresh()
suite.check("after the follow-up look the scan is up to date", Finder:Fresh() ~= nil)
ns.UI:Hide()
suite.check("closing the window hides the page", not MyGear:IsShown())
judges, sources = 0, 0
ns.UI:Show()
suite.check("opening it again with nothing changed judges nothing", judges == 0 and sources == 0,
    judges .. " " .. sources)

-- 5.
ns.UI:Hide()
local scans = 0
local realScan = Finder.ScanInBackground
Finder.ScanInBackground = function(...)
    if not Finder.background then scans = scans + 1 end
    return realScan(...)
end
Finder:MarkStale()
MyGear:RefreshSoon()
suite.check("a hidden page starts no scan", scans == 0 and MyGear:Refresh() == nil)
ns.UI:Show()
-- One look, and the engine's one more once the item answers are in.
suite.check("shown again after a change, it looks again and then stops", scans >= 1 and scans <= 3
    and Finder:Fresh() ~= nil, scans .. " " .. tostring(Finder.stale) .. " " .. tostring(Finder.background))
Finder.ScanInBackground = realScan

-- See All: Find Upgrades, narrowed to the slot picked here.
MyGear:PickSlot(5)
MyGear:SeeAll()
suite.check("See All opens Find Upgrades", Gear.tab == "find" and ns.FindUpgrades:IsShown()
    and not MyGear:IsShown())
suite.check("on that slot", ns.FindUpgrades:Slot() == 5 and ns.db.findSlot == 5, ns.db.findSlot)
ns.FindUpgrades:SetSlot(nil)
Gear:ShowTab("gear")

-- Show Me How follows the piece as the upgrade quest.
suite.check("the upgrade quest starts off", not ns.UpgradeQuest:IsEnabled())
MyGear:ShowMeHow()
suite.check("Show Me How follows the piece", ns.UpgradeQuest:IsEnabled() and ns.UpgradeQuest:IsFollowing(1201))

-- What Read makes of a scan: wear-it-now before later, the ignored left out.
do
    local function Pick(id, percent, extra)
        local pick = { itemID = id, link = "item:" .. id, result = { percent = percent, verdict = "upgrade" },
            sources = { { kind = "vendor", name = "Corina Steele", zone = "Elwynn Forest" } } }
        for key, value in pairs(extra or {}) do pick[key] = value end
        return pick
    end
    local found = { all = {
        [2] = { Pick(1, 50, { at = 40 }), Pick(2, 30), Pick(3, 20), Pick(4, 10), Pick(5, 5) },
        [3] = { Pick(6, 80, { at = 40 }) },
        [9] = { Pick(7, 60) },
    } }
    ns.UpgradeQuest:Skipped()[7] = true
    local read = MyGear:Read(found)
    local ids = {}
    for _, pick in ipairs(read.slots[2].picks) do ids[#ids + 1] = pick.itemID end
    suite.check("three to go and get, wear-it-now first", table.concat(ids, ",") == "2,3,4", table.concat(ids, ","))
    suite.check("a slot with something to wear now is green", read.slots[2].tone == "good"
        and MyGear.Badge(read.slots[2].mark) == "+30%")
    suite.check("a slot with only a later piece is amber", read.slots[3].tone == "warn"
        and read.slots[3].picks[1].itemID == 6)
    suite.check("an ignored piece is left out", read.slots[9].mark == nil and #read.slots[9].picks == 0)
    suite.check("a later piece is not the one to go and get next", read.next == nil or read.next.itemID ~= 6)
    ns.UpgradeQuest:Skipped()[7] = nil
    suite.check("Later: a level, a reputation or a far crafter", MyGear.Later({ at = 40 })
        and MyGear.Later({ needs = {} }) and MyGear.Later({ remote = true }) and not MyGear.Later({}))
    suite.check("an empty slot's badge is a plus", MyGear.Badge({ empty = true }) == "+")
end

-- 6.
local worn = {}
_G.C_Item.EquipItemByName = function(link) worn[#worn + 1] = link end
env.chat = {}
local fighting = true
_G.InCombatLockdown = function() return fighting end
_G.UnitAffectingCombat = function() return fighting end
MyGear:Refresh()
suite.check("in a fight Put Them On takes both in hand", MyGear:PutThemOn() == 2 and #worn == 0, #worn)
suite.check("and says they go on after", env.ChatText():find("They go on after the fight.", 1, true) ~= nil,
    env.ChatText())
fighting = false
ns.Wear:Next()
suite.check("after the fight they go on, one at a time", #worn >= 1 and (worn[1] == "item:901" or worn[1] == "item:902"),
    table.concat(worn, ","))
suite.check("with Put on upgrades still off", not ns.Wear:AutoOn())

-- 7.
MyGear:SetView("list")
suite.check("List is kept", ns.db.myGearView == "list" and MyGear.list:IsShown() and not MyGear.figure:IsShown())
suite.check("a row for each slot, in sheet order", MyGear.listRows[1].slot == 1 and MyGear.listRows[17].slot == 18
    and MyGear.listRows[1].slotLabel:GetText() == "Head")
MyGear:SortBy("best")
suite.check("Best Upgrade sorts the biggest first, an empty slot ahead", MyGear.listRows[1].slot == 7 or MyGear.listRows[1].slot == 8,
    MyGear.listRows[1].slot)
local last = MyGear.listRows[17].slot
suite.check("slots with nothing sort last", MyGear.state.slots[last].mark == nil, last)
MyGear:SortBy("best")
suite.check("a second click turns it round", MyGear.state.slots[MyGear.listRows[1].slot].mark ~= nil
    and MyGear.listRows[1].slot ~= 1, MyGear.listRows[1].slot)
judges = 0
MyGear:SortBy("worn")
MyGear.listRows[1]:GetScript("OnClick")(MyGear.listRows[1], "LeftButton")
suite.check("sorting and clicking rows judge nothing", judges == 0, judges)
suite.check("a click on a row shows its slot", MyGear.slot == MyGear.listRows[1].slot)
MyGear:SetView("figure")
suite.check("Figure brings the slots back", ns.db.myGearView == "figure" and MyGear.figure:IsShown())

-- 8. Worn names show in their rarity colour. Forever writes item links with
-- the named colour ("|cnIQ2:"), not "|cff1eff00"; the names showed white.
do
    _G.ITEM_QUALITY_COLORS = { [2] = { r = 0.12, g = 1, b = 0 } }
    local green = "|cnIQ2:|Hitem:800::::::::20:::::|h[Crown of Leaves]|h|r"
    env.items[green] = ITEMS["item:800"]
    local text = ns.FinderUI.ItemText(green)
    suite.check("a named-colour link keeps its colour", text == "|c" .. ns.Items.QualityHex(2) .. "Crown of Leaves|r", text)
    suite.check("an old-style link keeps its colour",
        ns.FinderUI.ItemText("|cff0070dd|Hitem:9::|h[Blue Hat]|h|r") == "|cff0070ddBlue Hat|r")
    env.worn[1] = green
    MyGear:Refresh()
    local shown = MyGear.slotButtons[1].name:GetText()
    suite.check("the figure shows the worn name in colour", shown == text, shown)
    MyGear:SetView("list")
    local row
    for _, r in ipairs(MyGear.listRows) do if r.slot == 1 then row = r end end
    suite.check("the list shows the worn name in colour", row and row.worn:GetText() == text,
        row and row.worn:GetText())
    MyGear:SetView("figure")
end

-- 9. My Gear follows Find Upgrades' From boxes (a player's report on
-- 1.18.0): with every box unticked, the figure still showed arrows, gains
-- and a dungeon drop under Next To Go Get.
do
    MyGear:SetView("figure")
    ns.db.finderSourcesOff = nil
    MyGear:Refresh()
    local before = MyGear.state
    suite.check("with every box ticked the head has picks", #before.slots[1].picks > 0, #before.slots[1].picks)
    suite.check("and a next card", before.next ~= nil)
    for _, entry in ipairs(ns.FinderUI.SOURCE_BOXES) do ns.FinderUI:SetSource(entry[1], false) end
    MyGear:Refresh()
    local state = MyGear.state
    suite.check("with every box unticked the head has no picks", #state.slots[1].picks == 0, #state.slots[1].picks)
    suite.check("and no mark", state.slots[1].tone == nil, tostring(state.slots[1].tone))
    suite.check("and no next card", state.next == nil)
    suite.check("what is in the bags still shows", state.slots[5].owned[1] ~= nil and state.slots[5].tone == "good")
    suite.check("the sheet's arrows agree", not MyGear:GreenSlots(state.found)[1])
    ns.FinderUI:SetSource("vendor", true)
    MyGear:Refresh()
    suite.check("ticking Vendor again brings the vendor picks back", #MyGear.state.slots[1].picks > 0)
    ns.db.finderSourcesOff = nil
    MyGear:Refresh()
end

suite.done()
