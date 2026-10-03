-- Upgrade hunts: tracking a pick, the banner when it lands in the bags, the
-- tracker panel, map pins, the character-sheet slots, and the arrow on a
-- vendor's wares and in the loot window.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("hunts")

local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end
local function Gear(loc, n) return { loc = loc, class = 4, subclass = 2, stats = Agi(n) } end

local ITEMS = {
    ["item:900"] = Gear("INVTYPE_CHEST", 10),   -- worn
    ["item:1001"] = Gear("INVTYPE_CHEST", 20),  -- sold by a vendor
    ["item:1002"] = Gear("INVTYPE_CHEST", 30),  -- quest reward
    ["item:1003"] = Gear("INVTYPE_CHEST", 5),   -- worse
}

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitRace = function() return "Human", "Human", 1 end
env.InstallItems(ITEMS, { [5] = "item:900" }, { [0] = {} }, 20)
_G.C_QuestLog = { IsQuestFlaggedCompleted = function() return false end }

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

local Finder, Tracking = ns.Finder, ns.Tracking
local found = Finder:Scan()
local vendorPick, questPick
for _, pick in ipairs(found.slots[5] or {}) do
    if pick.itemID == 1001 then vendorPick = pick end
    if pick.itemID == 1002 then questPick = pick end
end
suite.check("the finder has both picks", vendorPick and questPick)

--------------------------------------------------------------------------------
-- Tracking
--------------------------------------------------------------------------------

local toasts = {}
local realShow = ns.Toast.Show
ns.Toast.Show = function(self, banner)
    toasts[#toasts + 1] = banner
    return realShow(self, banner)
end

suite.check("nothing is tracked to begin with", Tracking:Count() == 0 and ns.charDB.tracked == nil)
suite.check("tracking a pick", Tracking:Toggle(vendorPick) == true and Tracking:IsTracked(1001))
suite.check("is kept per character", type(ns.charDB.tracked[1001]) == "table")
local hunt = Tracking:List()[1]
suite.check("with where to go", hunt.place.zone == "Elwynn Forest" and hunt.place.x == 41.5
    and hunt.place.name == "Corina Steele", hunt.place.zone)
suite.check("in words", hunt.place.text:find("Corina Steele", 1, true) ~= nil, hunt.place.text)
suite.check("and the slot", hunt.slot == 5)
Tracking:Track(questPick)
suite.check("two hunts", Tracking:Count() == 2 and #Tracking:List() == 2)

suite.check("the tracker shows them", ns.TrackerPanel.frame and ns.TrackerPanel.frame:IsShown())
suite.check("with a count", ns.TrackerPanel.title:GetText() == "Upgrade hunts (2)", ns.TrackerPanel.title:GetText())
suite.check("and where to go", ns.TrackerPanel.rows[1].where:GetText():find("Corina Steele", 1, true) ~= nil,
    ns.TrackerPanel.rows[1].where:GetText())

-- It lands in the bags.
env.bags[0][1] = "item:1001"
Tracking:Check()
suite.check("a banner says it arrived", #toasts == 1 and toasts[1].title == "Tracked upgrade in your bags",
    toasts[1] and toasts[1].title)
suite.check("the banner shows", ns.Toast.frame:IsShown() and ns.Toast.title:GetText() == "Tracked upgrade in your bags")
suite.check("the hunt is marked got", ns.charDB.tracked[1001].got ~= nil)
suite.check("the tracker says put it on",
    ns.TrackerPanel.rows[1].where:GetText():find("In your bags: put it on", 1, true) ~= nil)
Tracking:Check()
suite.check("only once", #toasts == 1)

-- Sold before it was worn: hunted again.
env.bags[0][1] = nil
Tracking:Check()
suite.check("it leaving the bags puts it back on the hunt", ns.charDB.tracked[1001].got == nil)

-- Worn: done.
env.worn[5] = "item:1001"
Tracking:Check()
suite.check("wearing it finishes the hunt", not Tracking:IsTracked(1001) and Tracking:Count() == 1)
suite.check("and it goes on the finished list", Tracking:Done()[1].itemID == 1001)
suite.check("with a banner", toasts[#toasts].title == "Hunt done")
env.worn[5] = "item:900"

-- Banners queue rather than pile up.
suite.check("a second banner waits its turn", #(ns.Toast.queue or {}) >= 1)
ns.Toast:Dismiss()
suite.check("and shows when the first goes", ns.Toast.frame:IsShown() and ns.Toast.title:GetText() == "Hunt done")
ns.Toast:Dismiss()
suite.check("then the banner closes", not ns.Toast.frame:IsShown())
ns.db.upgradeToast = false
suite.check("no banner with the setting off", ns.Toast:Show({ title = "x" }) == false)
ns.db.upgradeToast = true

ns.TrackerPanel:ToggleDone()
suite.check("the tracker lists finished hunts", ns.TrackerPanel.title:GetText() == "Finished hunts (1)")
ns.TrackerPanel:ToggleDone()
ns.TrackerPanel:ToggleFold()
suite.check("folding hides the rows", not ns.TrackerPanel.rows[1]:IsShown())
ns.TrackerPanel:ToggleFold()
ns.db.showTracker = false
ns.TrackerPanel:Refresh()
suite.check("the tracker hides with its setting off", not ns.TrackerPanel.frame:IsShown())
ns.db.showTracker = true

ns.HandleSlash("tracked")
suite.check("/beq tracked lists them", env.ChatText():find("tracking 1 upgrade", 1, true) ~= nil, env.ChatText())

--------------------------------------------------------------------------------
-- The map
--------------------------------------------------------------------------------

local place = Tracking:List()[1].place
local ok, why = ns.Waypoints:Pin(place)
suite.check("a client without map pins says so", ok == false and why == "noclient", why)
suite.check("a hunt without a spot says so", select(2, ns.Waypoints:Pin({ zone = "Elwynn Forest" })) == "nospot")

local waypoint, tracked, opened
_G.UiMapPoint = { CreateFromCoordinates = function(id, x, y) return { id = id, x = x, y = y } end }
_G.C_SuperTrack = { SetSuperTrackedUserWaypoint = function(v) tracked = v end }
_G.OpenWorldMap = function(id) opened = id end
local MAPS = {
    [1415] = { name = "Eastern Kingdoms", parentMapID = 947 },
    [947] = { name = "Azeroth", parentMapID = 0 },
    [1429] = { name = "Elwynn Forest", parentMapID = 1415 },
}
_G.C_Map = {
    GetBestMapForUnit = function() return 1429 end,
    GetMapInfo = function(id) return MAPS[id] end,
    GetMapChildrenInfo = function()
        return { { name = "Eastern Kingdoms", mapID = 1415 }, { name = "Elwynn Forest", mapID = 1429 } }
    end,
    SetUserWaypoint = function(point) waypoint = point end,
}
suite.check("the zone's map is found by name", ns.Waypoints:MapFor("Elwynn Forest") == 1429)
suite.check("an unknown zone has none", ns.Waypoints:MapFor("Nowhere") == nil)
suite.check("pinning works", ns.Waypoints:Show(place, "it") == true)
suite.check("at the spot", waypoint.id == 1429 and math.abs(waypoint.x - 0.421) < 1e-9, waypoint and waypoint.x)
suite.check("with the game's arrow on it", tracked == true and opened == 1429)
suite.check("and says so", env.ChatText():find("pinned it on your map: Elwynn Forest (42.1, 65.9)", 1, true) ~= nil,
    env.ChatText())

local canvas = env.Stub({ _width = 1000, _height = 600 })
function canvas:GetHeight() return 600 end
_G.WorldMapFrame = env.Stub({ _shown = true, GetCanvas = function() return canvas end,
    GetMapID = function() return 1429 end })
ns.MapPins:Draw()
suite.check("a map pin for the hunt", ns.MapPins.pins and ns.MapPins.pins[1] and ns.MapPins.pins[1]:IsShown())
local point = ns.MapPins.pins[1]._point
suite.check("where it is", point and math.abs(point[4] - 421) < 1e-6 and math.abs(point[5] + 395.4) < 1e-6,
    point and (point[4] .. "," .. point[5]))
_G.WorldMapFrame.GetMapID = function() return 1415 end
ns.MapPins:Draw()
suite.check("and none on another zone's map", not ns.MapPins.pins[1]:IsShown())

--------------------------------------------------------------------------------
-- The character sheet
--------------------------------------------------------------------------------

Finder:MarkStale()
local picks = ns.SlotUpgrades:PicksFor(5)
suite.check("the chest slot's picks, best first", #picks == 2 and picks[1].itemID == 1002, #picks)

local chest = env.Stub({ GetID = function() return 5 end })
_G.CharacterChestSlot = chest
ns.SlotUpgrades:OnEnable()
_G.GameTooltip._shown = true
_G.GameTooltip._lines = { "Chest", "item:900" }
_G.GameTooltip.GetOwner = function() return chest end
_G.GameTooltip.AddDoubleLine = function(self, left, right) self._lines[#self._lines + 1] = left .. "  " .. right end
chest:GetScript("OnEnter")(chest)
local text = table.concat(_G.GameTooltip._lines, "\n")
suite.check("hovering the slot lists the upgrade", text:find("Upgrades on offer", 1, true)
    and text:find("item:1002", 1, true), text)
suite.check("and says how to track it", text:find("Alt-click", 1, true) ~= nil)

-- The game redraws a slot's tooltip several times a second, which wipes
-- added lines; they go straight back on, without a new scan.
local lines = #_G.GameTooltip._lines
local scans = 0
local realScan = Finder.Scan
Finder.Scan = function(...) scans = scans + 1 return realScan(...) end
_G.GameTooltip._lines = { "Chest", "item:900" }
_G.GameTooltip:GetScript("OnUpdate")(_G.GameTooltip, 0.2)
suite.check("a redraw puts the upgrades back", #_G.GameTooltip._lines == lines
    and table.concat(_G.GameTooltip._lines, "\n"):find("Upgrades on offer", 1, true), #_G.GameTooltip._lines)
_G.GameTooltip:GetScript("OnUpdate")(_G.GameTooltip, 0.2)
suite.check("and only once", #_G.GameTooltip._lines == lines, #_G.GameTooltip._lines)
suite.check("without scanning again", scans == 0, scans)
Finder.Scan = realScan
_G.GameTooltip.GetOwner = function() return nil end
_G.GameTooltip._lines = {}
_G.GameTooltip:GetScript("OnUpdate")(_G.GameTooltip, 0.2)
suite.check("another owner's tooltip is left alone", #_G.GameTooltip._lines == 0)

_G.IsAltKeyDown = function() return true end
chest:GetScript("OnClick")(chest)
suite.check("Alt-click opens the panel", ns.SlotUpgrades.frame and ns.SlotUpgrades.frame:IsShown())
local row = ns.SlotUpgrades.rows[1]
suite.check("with the pick", row:IsShown() and row.item:GetText() == "item:1002")
suite.check("already tracked", row.track.label:GetText() == "Untrack", row.track.label:GetText())
Tracking:Untrack(1002)
suite.check("the panel follows the tracking", row.track.label:GetText() == "Track")
_G.IsAltKeyDown = nil

--------------------------------------------------------------------------------
-- Vendors and loot
--------------------------------------------------------------------------------

_G.MerchantFrame = env.Stub({ page = 1, selectedTab = 1 })
_G.MERCHANT_ITEMS_PER_PAGE = 10
local wares = { [1] = "item:1002", [2] = "item:1003" }
_G.GetMerchantItemLink = function(i) return wares[i] end
local first, second = env.Stub(), env.Stub()
_G.MerchantItem1ItemButton, _G.MerchantItem2ItemButton = first, second
ns.MoreMarks:RefreshMerchant()
suite.check("an upgrade on sale gets the arrow", ns.BagIcons:ExistingArrow(first)
    and ns.BagIcons:ExistingArrow(first):IsShown())
suite.check("worse gear does not", not ns.BagIcons:ExistingArrow(second))
_G.MerchantFrame.selectedTab = 2
ns.MoreMarks:RefreshMerchant()
suite.check("the buyback tab has none", not ns.BagIcons:ExistingArrow(first):IsShown())

local loot = env.Stub({ slot = 1 })
_G.LootButton1 = loot
_G.GetLootSlotLink = function(slot) return slot == 1 and "item:1002" or nil end
ns.MoreMarks:RefreshLoot()
suite.check("an upgrade in the loot window gets the arrow", ns.BagIcons:ExistingArrow(loot):IsShown())
ns.db.bagArrows = false
ns.MoreMarks:RefreshLoot()
suite.check("not with bag arrows off", not ns.BagIcons:ExistingArrow(loot):IsShown())
ns.db.bagArrows = true
_G.GetLootSlotLink = function() error("secret value") end
ns.MoreMarks:RefreshLoot()
suite.check("a link the game will not give is no arrow", not ns.BagIcons:ExistingArrow(loot):IsShown())

ns.Toast.Show = realShow
suite.done()
