-- The gear window: since 2026-10-22 one window with Where to get upgrades.
-- What is worn shows down the left, and the upgrades you own come first in
-- a slot's list, under IN YOUR BAGS.

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

UI:Show()
suite.check("it opens", UI.frame:IsShown())
suite.check("one window: the gear window is the finder's", UI.frame == Finder.frame)
suite.check("named on its plate", Finder.frame ~= nil)
suite.check("a line for every slot down the left", #Finder.slotButtons == #Finder.SLOT_GROUPS,
    #Finder.slotButtons)
suite.check("Upgrades, Enchants and Settings hang under it", Finder.tabStrip ~= nil
    and Finder.tabStrip.selected == "upgrades", Finder.tabStrip and Finder.tabStrip.selected)
suite.check("the header has Training, Upgrade quest and Dungeon Loot",
    UI.trainingButton ~= nil and UI.questButton ~= nil and UI.lootButton ~= nil)

suite.check("the bigger of two chest upgrades", Owned(5) == "item:2", Owned(5))
suite.check("an item above your level is not offered", not Owned(5):find("item:8", 1, true))
suite.check("an empty slot is filled from the bags", Owned(8) == "item:4", Owned(8))
suite.check("a new ring goes against the weaker ring", Owned(12) == "item:7", Owned(12))
suite.check("not the stronger one", Owned(11) == "", Owned(11))
suite.check("three upgrades in the bags", UI.upgrades == 3, UI.upgrades)

-- The chest's line on the left says what is worn there.
local chestButton
for _, button in ipairs(Finder.slotButtons) do
    if button.group == 5 then chestButton = button end
end
Finder:PaintWorn(chestButton)
suite.check("the slot's line names what you wear", chestButton.worn:GetText():find("item:1", 1, true) ~= nil,
    chestButton.worn:GetText())

-- The list for a slot: IN YOUR BAGS, the piece, then what to go and get.
local groups = Finder:Groups({ all = {} })
suite.check("the chest's group holds the bag upgrade", #groups[5].owned == 1
    and groups[5].owned[1].where == "bags")
suite.check("both rings are one group", #groups[11].owned == 1 and groups[11].owned[1].link == "item:7")
local row = Finder.rows[1]
Finder:FillRow(row, { heading = "IN YOUR BAGS" })
suite.check("a heading row says so", row.headingLabel:GetText() == "IN YOUR BAGS" and row.heading == true)
Finder:FillRow(row, { owned = groups[5].owned[1] })
suite.check("an owned row shows the item", row.item:GetText() ~= "" and row.owned ~= false)
suite.check("in your bags", row.where:GetText() == "Your bags", row.where:GetText())
suite.check("with how much better", row.gain:GetText() == "+50%", row.gain:GetText())
suite.check("and Put it on", row.putOn:IsShown())
Finder:FillRow(row, { owned = { link = "item:2", where = "bank", result = { percent = 50 } } })
suite.check("one in the bank says so", row.where:GetText() == "Your bank", row.where:GetText())
suite.check("and can't be put on from there", not row.putOn:IsShown())
Finder:FillRow(row, nil)
suite.check("an empty row hides", not row:IsShown())

-- Putting the upgrade on moves it across.
env.worn[5] = "item:2"
env.bags[0][1] = "item:1"
suite.check("wearing the upgrade empties the chest", Owned(5) == "", Owned(5))
suite.check("and drops the count", UI.upgrades == 2, UI.upgrades)

-- The Settings tab shows Settings in its place, and Upgrades brings it back.
Finder:ShowTab("settings")
suite.check("Settings shows from its tab", ns.SettingsUI.frame:IsShown() and not Finder.frame:IsShown())
suite.check("with the Settings tab lit", ns.SettingsUI.tabStrip.selected == "settings")
suite.check("and counts as the window being open", UI:IsShown())
Finder:ShowTab("upgrades", ns.SettingsUI.frame)
suite.check("Upgrades brings the window back", Finder.frame:IsShown() and not ns.SettingsUI.frame:IsShown())
Finder:ShowTab("enchant")
suite.check("Enchants shows the enchants", Finder:ShowingEnchants() and Finder.tabStrip.selected == "enchant")
Finder:ShowTab("upgrades")
suite.check("and Upgrades the gear", not Finder:ShowingEnchants())

-- /beq window.
UI:Hide()
suite.check("closing hides it", not UI.frame:IsShown())
ns.HandleSlash("window")
suite.check("/beq window opens it", UI.frame:IsShown())
UI:Hide()
suite.check("a closed window does not refresh", UI:Refresh() == 0)

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

-- A class with no weights is offered nothing.
_G.UnitClass = function() return "DEATHKNIGHT", "DEATHKNIGHT" end
suite.check("a class without weights owns no upgrades", next(UI:ReadBags()) == nil)
_G.UnitClass = function() return "HUNTER", "HUNTER" end

suite.done()
