-- The Equipment window by its old names (UI:Show, UI:Hide, /beq window),
-- its tabs and the keys the old tabs had, and UI:ReadBags, the read of the
-- upgrades you own.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("mainwindow")

local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end

local ITEMS = {
    ["item:1"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = Agi(10) },
    ["item:2"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = Agi(15) },
    ["item:3"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = Agi(12) },
    ["item:4"] = { loc = "INVTYPE_FEET", class = 4, subclass = 2, stats = Agi(3) },
    ["item:5"] = { loc = "INVTYPE_FINGER", class = 4, subclass = 0, stats = Agi(8) },
    ["item:6"] = { loc = "INVTYPE_FINGER", class = 4, subclass = 0, stats = Agi(2) },
    ["item:7"] = { loc = "INVTYPE_FINGER", class = 4, subclass = 0, stats = Agi(5) },
    ["item:8"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = Agi(40), minLevel = 30 },
}

local ns = env.Load()
_G.UnitClass = function() return "HUNTER", "HUNTER" end
env.InstallItems(ITEMS, { [5] = "item:1", [11] = "item:5", [12] = "item:6" },
    { [0] = { "item:2", "item:3", "item:4", "item:7", "item:8" } })

local UI = ns.UI
local Finder = ns.FinderUI

--- The links UI:ReadBags gives a slot.
local function Owned(slot)
    local owned = UI:ReadBags()[slot] or {}
    local links = {}
    for _, entry in ipairs(owned) do links[#links + 1] = entry.link end
    return table.concat(links, ",")
end

-- The window opens on My Gear (UI/GearWindow.lua). Every tab is a page of
-- it; a key an old tab had opens the page that took its place.
local Gear = ns.GearWindow
UI:Show()
suite.check("it opens", UI:IsShown() and Gear.frame:IsShown())
suite.check("on My Gear", Gear.tab == "gear" and ns.MyGear:IsShown())
local tabKeys = {}
for _, tab in ipairs(Gear.strip.tabs) do tabKeys[#tabKeys + 1] = tab.key end
suite.check("the tabs are My Gear, Find Upgrades, Upgrade Quest, Dungeons, Training and Settings",
    table.concat(tabKeys, ",") == "gear,find,quest,instances,training,settings", table.concat(tabKeys, ","))
Gear:ShowTab("upgrades")
suite.check("the old gear list's key opens Find Upgrades", Gear.tab == "find" and ns.FindUpgrades:IsShown()
    and not ns.MyGear:IsShown() and Gear.strip.selected == "find", Gear.tab)
Gear:ShowTab("enchant")
suite.check("the old Enchants tab's key opens My Gear", Gear.tab == "gear" and ns.MyGear:IsShown())
Gear:ShowTab("dungeons")
suite.check("the old Dungeon Quests key opens Dungeons", Gear.tab == "instances" and ns.DungeonsTab:IsShown())
Gear:ShowTab("loot")
suite.check("and so does Dungeon Loot's", Gear.tab == "instances" and ns.DungeonsTab:IsShown())
Gear:ShowTab("nothing-by-this-name")
suite.check("a key nobody knows opens My Gear", Gear.tab == "gear")
suite.check("the old windows are gone", ns.DungeonQuestsUI == nil and ns.DungeonLootUI == nil
    and ns.IgnoredUI == nil and ns.TrainingDrawer == nil and ns.QuestPanel == nil and ns.TrackerPanel == nil
    and ns.WeightsUI == nil)

suite.check("the bigger of two chest upgrades", Owned(5) == "item:2", Owned(5))
suite.check("an item above your level is not offered", not Owned(5):find("item:8", 1, true))
suite.check("an empty slot is filled from the bags", Owned(8) == "item:4", Owned(8))
suite.check("a new ring goes against the weaker ring", Owned(12) == "item:7", Owned(12))
suite.check("not the stronger one", Owned(11) == "", Owned(11))
suite.check("three upgrades in the bags", UI.upgrades == 3, UI.upgrades)

-- Putting the upgrade on moves it across.
env.worn[5] = "item:2"
env.bags[0][1] = "item:1"
suite.check("wearing the upgrade empties the chest", Owned(5) == "", Owned(5))
suite.check("and drops the count", UI.upgrades == 2, UI.upgrades)

-- Settings is a page of the window, last on the bar.
Gear:ShowTab("settings")
suite.check("Settings shows from its tab", ns.SettingsUI:IsShown() and not ns.MyGear:IsShown())
suite.check("as a page laid into the window, with no frame of its own",
    ns.SettingsUI.frame:GetParent() == Gear.area and Gear.pages.settings == ns.SettingsUI)
suite.check("with the Settings tab lit", Gear.strip.selected == "settings")
suite.check("and counts as the window being open", UI:IsShown())
Gear:ShowTab("gear")
suite.check("My Gear takes its place", ns.MyGear:IsShown() and not ns.SettingsUI:IsShown())
ns.HandleSlash("settings")
suite.check("/beq settings opens the window on Settings", Gear.tab == "settings" and ns.SettingsUI:IsShown())
ns.HandleSlash("settings")
suite.check("and again closes the window", not UI:IsShown() and not ns.SettingsUI:IsShown())
ns.HandleSlash("dungeons")
suite.check("/beq dungeons opens the Dungeons tab", ns.DungeonsTab:IsShown() and Gear.strip.selected == "instances")
ns.HandleSlash("loot")
suite.check("and so does /beq loot", ns.DungeonsTab:IsShown() and Gear.strip.selected == "instances")
Gear:ShowTab("training")
suite.check("Training has a tab of its own", ns.TrainingTab:IsShown() and not ns.DungeonsTab:IsShown())
UI:Hide()
suite.check("closing the window closes the page", not ns.TrainingTab:IsShown() and not UI:IsShown())

-- /beq window.
UI:Hide()
suite.check("closing hides it", not UI:IsShown())
ns.HandleSlash("window")
suite.check("/beq window opens it, on My Gear", UI:IsShown() and Gear.tab == "gear")
UI:Hide()

-- A second copy of the ring already worn goes against the other ring.
env.worn[11], env.worn[12] = "item:5", "item:6"
env.bags[0] = { "item:5" }
suite.check("a second copy of a worn ring is an upgrade for the other slot", Owned(12) == "item:5", Owned(12))
suite.check("and gets the bag arrow", ns.Compare:IsUpgradeNow("item:5", true))
suite.check("but the worn one itself is not called an upgrade", not ns.Compare:IsUpgradeNow("item:5"))

-- A trinket is taken to be unique, so a second copy is not offered.
ITEMS["item:10"] = { loc = "INVTYPE_TRINKET", class = 4, subclass = 0, stats = Agi(9) }
ITEMS["item:11"] = { loc = "INVTYPE_TRINKET", class = 4, subclass = 0, stats = Agi(1) }
env.worn[13], env.worn[14] = "item:10", "item:11"
env.bags[0] = { "item:10" }
suite.check("a second copy of a unique trinket is not an upgrade", Owned(14) == "", Owned(14))
env.worn[13], env.worn[14] = nil, nil

_G.C_Item.GetItemUniquenessByID = function() return false end
suite.check("a trinket the client calls not unique", not ns.Compare:IsUnique("item:10"))
_G.C_Item.GetItemUniquenessByID = nil
_G.GetItemUniqueness = function() return -1, 1 end
suite.check("the old call's -1 means unique", ns.Compare:IsUnique("item:5"))
_G.GetItemUniqueness = function() return 0, 0 end
suite.check("and nothing there means not", not ns.Compare:IsUnique("item:10"))
_G.GetItemUniqueness = nil
suite.check("no answer: a ring is not taken to be unique", not ns.Compare:IsUnique("item:5"))

-- Every tab shares the one Equipment window, so it never jumps as the
-- tabs are clicked: it holds the size the tabs share, under its tab bar.
UI:Show()
local pageWidth, pageHeight = Gear:PageSize()
local wantWidth = pageWidth + Gear.CHROME_WIDTH
local wantHeight = pageHeight + Gear.CHROME_HEIGHT
suite.check("the pages share the old window's room, or more", pageWidth >= Gear.WIDTH and pageHeight == Gear.HEIGHT,
    pageWidth .. "x" .. pageHeight)
local sizes, same = {}, true
for _, key in ipairs({ "find", "quest", "instances", "training", "settings", "gear" }) do
    Gear:ShowTab(key)
    local size = Gear.frame:GetWidth() .. "x" .. Gear.frame:GetHeight()
    sizes[#sizes + 1] = size
    same = same and size == wantWidth .. "x" .. wantHeight
end
suite.check("every tab shows in a window of one size", same, table.concat(sizes, ", "))
suite.check("the window has the one size grip", Gear.sizeGrip ~= nil)
suite.check("Settings has no grip, rim or spot of its own", ns.SettingsUI.sizeGrip == nil
    and ns.SettingsUI.RestorePosition == nil)
Gear:Need("test", nil, pageHeight + 40)
suite.check("a page that needs more room makes the window taller",
    Gear.frame:GetHeight() == wantHeight + 40, Gear.frame:GetHeight())
Gear:Need("test", nil, nil)
suite.check("and it goes back when the need does", Gear.frame:GetHeight() == wantHeight, Gear.frame:GetHeight())
UI:Hide()

-- A class with no weights is offered nothing.
_G.UnitClass = function() return "DEATHKNIGHT", "DEATHKNIGHT" end
suite.check("a class without weights owns no upgrades", next(UI:ReadBags()) == nil)
_G.UnitClass = function() return "HUNTER", "HUNTER" end

suite.done()
