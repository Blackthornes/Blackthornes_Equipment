-- Out in the world (rework step 7, the owner approved the mockup
-- 2026-11-22): the character sheet's arrows, My Gear beside the sheet, the
-- percent under an arrow, and one stack for the banner, Upgrade Done! and
-- note cards.
--
-- What must hold:
--   1. With the sheet open, every slot My Gear's figure marks green wears
--      the green arrow, and no other slot does.
--   2. Nothing is looked at while the sheet is shut, and marking a sheet
--      again with nothing changed judges no gear.
--   3. "Character Sheet:" unticked takes the arrows off.
--   4. Alt-click a slot opens My Gear on that slot, beside the sheet: on
--      its right, or its left when the right has no room.
--   5. Dragged there, it keeps that spot for next time beside the sheet,
--      and the spot it opens at by itself is left alone.
--   6. A window already open stays put and only turns to the slot.
--   7. A bag or vendor arrow says how much better under it.
--   8. The banner, Upgrade Done! and a note card never share a spot.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("sheet")

local ARMOR, LEATHER = 4, 2
local function Piece(loc, n)
    return { loc = loc, class = ARMOR, subclass = LEATHER, stats = { ITEM_MOD_AGILITY_SHORT = n }, bind = 0 }
end
local ITEMS = {
    ["item:800"] = Piece("INVTYPE_HEAD", 5),       -- worn
    ["item:900"] = Piece("INVTYPE_CHEST", 10),     -- worn
    ["item:901"] = Piece("INVTYPE_CHEST", 14),     -- in the bags
    ["item:1101"] = Piece("INVTYPE_HEAD", 8),      -- at a vendor
    ["item:1201"] = Piece("INVTYPE_LEGS", 5),      -- at a vendor, empty slot
}

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitRace = function() return "Human", "Human", 1 end
env.InstallItems(ITEMS, { [1] = "item:800", [5] = "item:900" }, { [0] = { "item:901" } }, 20)

local S = ns.Sources
ns.Crafts.ITEMS = {}
ns.RollData.ITEMS = {}
S.ZONES = { [12] = "Elwynn Forest" }
S.NPCS = { [1] = { "Corina Steele", 12, 41.5, 65.9, "A" } }
S.QUESTS, S.DUNGEONS, S.BOSSES, S.FOREVER = {}, {}, {}, {}
S.ITEMS = {}
for _, id in ipairs({ 1101, 1201 }) do S.ITEMS[id] = { 15, 15, 0, 0, 100, v = { 1, 0 } } end

-- The sheet and four of its slots: head, chest, legs and feet.
local sheetShown = false
local sheet = env.Stub({ _left = 20, _top = 900 })
sheet.GetRight = function() return 360 end
sheet.IsVisible = function() return sheetShown end
_G.CharacterFrame = sheet
local slots = {}
for name, id in pairs({ CharacterHeadSlot = 1, CharacterChestSlot = 5, CharacterLegsSlot = 7, CharacterFeetSlot = 8 }) do
    local button = env.Stub({ GetID = function() return id end })
    _G[name] = button
    slots[id] = button
end
_G.UIParent.GetWidth = function() return 1920 end

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end

local Gear, MyGear, Finder, Compare, Sheet = ns.GearWindow, ns.MyGear, ns.Finder, ns.Compare, ns.SlotUpgrades
local Icons = ns.BagIcons

local judges, scans = 0, 0
local realJudge, realBuild = Compare.Judge, Finder.Build
Compare.Judge = function(...) judges = judges + 1 return realJudge(...) end
Finder.Build = function(...) scans = scans + 1 return realBuild(...) end

local function Arrow(id)
    local arrow = Icons:ExistingArrow(slots[id])
    return arrow ~= nil and arrow:IsShown() == true
end

--------------------------------------------------------------------------------
-- 2. A shut sheet costs nothing
--------------------------------------------------------------------------------

Sheet:MarkSoon()
Sheet:Mark()
suite.check("a shut sheet starts no scan", scans == 0 and judges == 0, scans .. "/" .. judges)
suite.check("and wears no arrow", not Arrow(1) and not Arrow(5))

--------------------------------------------------------------------------------
-- 1. The arrows
--------------------------------------------------------------------------------

sheetShown = true
sheet:GetScript("OnShow")(sheet)
suite.check("opening the sheet looks once", scans == 1, scans)
suite.check("the chest has a better piece in the bags: an arrow", Arrow(5))
suite.check("the head has a better piece at a vendor: an arrow", Arrow(1))
suite.check("empty legs with a piece to get: an arrow", Arrow(7))
suite.check("feet with nothing better: no arrow", not Arrow(8))

-- The same slots My Gear's figure marks green.
Gear:Open("gear")
local same = true
for id in pairs(slots) do
    local info = MyGear.state.slots[id]
    if (info.tone == "good") ~= Arrow(id) then same = false end
end
suite.check("the sheet and My Gear's figure agree", same)
Gear:Close()

judges, scans = 0, 0
sheet:GetScript("OnShow")(sheet)
Sheet:MarkSoon()
suite.check("marking again with nothing changed judges nothing", judges == 0 and scans == 0,
    judges .. "/" .. scans)

--------------------------------------------------------------------------------
-- 3. The switch
--------------------------------------------------------------------------------

ns.db.slotUpgrades = false
Sheet:OnTrackingChanged()
suite.check("unticked, the arrows come off", not Arrow(1) and not Arrow(5) and not Arrow(7))
ns.db.slotUpgrades = true
Sheet:OnTrackingChanged()
suite.check("ticked, they come back", Arrow(1) and Arrow(5) and Arrow(7))

--------------------------------------------------------------------------------
-- 4. Alt-click: My Gear on the slot, beside the sheet
--------------------------------------------------------------------------------

local kept = { ns.db.finderPoint, ns.db.finderX, ns.db.finderY }
suite.check("the old floating panel is gone", Sheet.Build == nil and Sheet.frame == nil)
_G.IsAltKeyDown = function() return true end
slots[1]:GetScript("OnClick")(slots[1])
local frame = Gear.frame
suite.check("Alt-click opens the Equipment window", Gear:IsShown() and Gear.tab == "gear", Gear.tab)
suite.check("on My Gear, on the slot clicked", MyGear.slot == 1, MyGear.slot)
local point = frame._point
suite.check("it stands right of the sheet", point[1] == "TOPLEFT" and point[4] >= 360 and point[4] <= 420,
    point[4])
suite.check("level with its top", point[5] <= 900 and point[5] >= 840, point[5])

-- 6. Open already: it stays and turns to the slot.
frame._point = { "TOPLEFT", _G.UIParent, "BOTTOMLEFT", 777, 555 }
slots[5]:GetScript("OnClick")(slots[5])
suite.check("open already, it turns to the new slot", MyGear.slot == 5, MyGear.slot)
suite.check("and stays where it is", frame._point[4] == 777 and frame._point[5] == 555)
Gear:Close()

-- No room on the right: the left.
sheet._left = 1500
sheet.GetRight = function() return 1840 end
slots[7]:GetScript("OnClick")(slots[7])
point = frame._point
suite.check("with no room on the right it stands left of the sheet",
    point[4] + frame:GetWidth() <= 1500 and point[4] >= 0, point[4])
suite.check("on the slot clicked", MyGear.slot == 7, MyGear.slot)
Gear:Close()
sheet._left = 20
sheet.GetRight = function() return 360 end

--------------------------------------------------------------------------------
-- 5. Its own spot beside the sheet
--------------------------------------------------------------------------------

slots[1]:GetScript("OnClick")(slots[1])
frame._left, frame._top = 600, 700
frame:GetScript("OnDragStart")(frame)
frame:GetScript("OnDragStop")(frame)
local spot = ns.db.gearSheetSpot
suite.check("dragged beside the sheet, that spot is kept", spot and spot[1] == 600 and spot[2] == 700)
suite.check("the spot it opens at by itself is left alone", ns.db.finderPoint == kept[1]
    and ns.db.finderX == kept[2] and ns.db.finderY == kept[3] and not ns.db.finderMoved)
Gear:Close()
slots[5]:GetScript("OnClick")(slots[5])
suite.check("next time it stands at the kept spot", frame._point[4] == 600 and frame._point[5] == 700,
    frame._point[4])
Gear:Close()
Gear:Open()
suite.check("opened by itself, it stands where it always did", frame._point[1] == (kept[1] or "CENTER")
    and frame._point[4] == (kept[2] or 0), frame._point[4])
frame._left, frame._top = 100, 800
frame:GetScript("OnDragStart")(frame)
frame:GetScript("OnDragStop")(frame)
suite.check("a drag then saves its own spot as before", ns.db.finderMoved == true
    and ns.db.gearSheetSpot[1] == 600)
Gear:Close()
ns.SettingsUI:ResetPositions()
suite.check("Window Spots' Set Default clears the spot beside the sheet", ns.db.gearSheetSpot == nil)
_G.IsAltKeyDown = nil

-- The slot's tooltip says so.
local tip = env.Stub({ _lines = {}, AddLine = function(self, t) self._lines[#self._lines + 1] = t end,
    NumLines = function(self) return #self._lines end })
Sheet:AddLines(tip, 5)
suite.check("the slot's tooltip names My Gear",
    table.concat(tip._lines, "\n"):find("Alt-click to see this slot in My Gear", 1, true) ~= nil,
    table.concat(tip._lines, " | "))

--------------------------------------------------------------------------------
-- 7. The percent under an arrow
--------------------------------------------------------------------------------

local function Label(button)
    local label = ns.LootRolls:ExistingLabel(button)
    return label and label:IsShown() and label:GetText() or nil
end
local bag = env.Stub({ _width = 37 })
suite.check("a bag arrow says how much better", Icons:Percent(bag, { percent = 39.6 }) and Label(bag) == "+40%",
    Label(bag))
Icons:Percent(bag, nil)
suite.check("and the words go with the arrow", Label(bag) == nil)
suite.check("an empty slot has no percent to give", Icons:Percent(bag, { empty = true }) == false and Label(bag) == nil)

_G.MerchantFrame = env.Stub({ page = 1, selectedTab = 1 })
_G.MERCHANT_ITEMS_PER_PAGE = 10
local wares = { [1] = "item:1101", [2] = "item:800" }
_G.GetMerchantItemLink = function(i) return wares[i] end
local first, second = env.Stub({ _width = 37 }), env.Stub({ _width = 37 })
_G.MerchantItem1ItemButton, _G.MerchantItem2ItemButton = first, second
ns.MoreMarks:RefreshMerchant()
suite.check("a vendor's upgrade wears the arrow and its percent",
    Icons:ExistingArrow(first) and Icons:ExistingArrow(first):IsShown() and Label(first) == "+60%", Label(first))
suite.check("gear that is no upgrade wears neither", Label(second) == nil
    and not (Icons:ExistingArrow(second) and Icons:ExistingArrow(second):IsShown()))
wares[1] = "item:800"
ns.MoreMarks:RefreshMerchant()
suite.check("a new page takes the percent off", Label(first) == nil)

--------------------------------------------------------------------------------
-- 8. One stack at the top
--------------------------------------------------------------------------------

do
    ns.charDB = ns.charDB or {}
    ns.charDB.toastSpot = nil
    local SW = ns.SharedWindow
    local function Span(key, height)
        local _, _, y = SW.ShelfSpot(key)
        return y, y - height
    end
    ns.Toast:Show({ title = "Upgrade in your bags", link = "item:901" })
    ns.Toast.frame._height = 70
    -- The game runs a frame's OnShow as it shows. The first plaque must
    -- be on the shelf by then, or what stands under it is not moved.
    local plaque = ns.UpgradeDone:Build()
    local show = plaque.Show
    plaque.Show = function(self)
        local was = self:IsShown()
        show(self)
        local script = self:GetScript("OnShow")
        if not was and script then script(self) end
    end
    ns.UpgradeDone:Show({ link = "item:901", name = "Chest" }, 1)
    ns.Notice:Show("A note")
    local doneTop, doneBottom = Span("upgrade.done", ns.UpgradeDone.plaque:GetHeight() + 20)
    local toastTop, toastBottom = Span("upgrade.toast", 70)
    local noteTop = Span("notice", 0)
    suite.check("Upgrade Done! stands over the banner", doneBottom >= toastTop, doneBottom .. " " .. toastTop)
    suite.check("the banner stands over the note cards", toastBottom >= noteTop, toastBottom .. " " .. noteTop)
    suite.check("all three in one column, at the top middle",
        ({ SW.ShelfSpot("upgrade.done") })[1] == "TOP" and ({ SW.ShelfSpot("upgrade.toast") })[1] == "TOP"
        and ({ SW.ShelfSpot("upgrade.toast") })[2] == 0)
    suite.check("the banner was laid at its place", ns.Toast.frame._point[1] == "TOP"
        and math.abs(ns.Toast.frame._point[5] - toastTop) <= 12, ns.Toast.frame._point[5])

    -- A banner the player dragged keeps its spot and takes no room.
    ns.charDB.toastSpot = { 300, 400 }
    ns.Toast:Place()
    local _, _, after = SW.ShelfSpot("notice")
    suite.check("a dragged banner keeps its spot", ns.Toast.frame._point[1] == "TOPLEFT"
        and ns.Toast.frame._point[4] == 300 and ns.Toast.frame._point[5] == 400)
    suite.check("and the notes move up into its place", after > noteTop, after .. " " .. noteTop)
    ns.charDB.toastSpot = nil
end

suite.done()
