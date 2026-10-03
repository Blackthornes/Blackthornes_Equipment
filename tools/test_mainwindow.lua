-- The gear window: what is worn in each slot, and the best upgrade for it
-- in the bags.

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

--- The link a cell holds, or nil. (Test frames answer any missing field with
--- a function, so the type is what tells.)
local function Link(cell)
    return type(cell.link) == "string" and cell.link or nil
end

--- The row for an inventory slot.
local function Row(slot)
    for _, row in ipairs(UI.rows) do
        if row.slot == slot then return row end
    end
end

UI:Show()
suite.check("it opens", UI.frame:IsShown())
suite.check("a row for every slot on the character sheet", #UI.rows == 17, #UI.rows)
suite.check("the header names the spec", UI.specLabel:GetText() == "judging gear as Beast Mastery",
    UI.specLabel:GetText())

local chest = Row(5)
suite.check("the chest shows what is worn", chest.worn.text:GetText() == "item:1", chest.worn.text:GetText())
suite.check("and the bigger of two upgrades", chest.best.text:GetText() == "item:2", chest.best.text:GetText())
suite.check("with how much better", chest.gain:GetText() == "+50%", chest.gain:GetText())
suite.check("an item above your level is not offered", Link(chest.best) ~= "item:8")

local feet = Row(8)
suite.check("an empty slot says so", feet.worn.text:GetText() == "empty", feet.worn.text:GetText())
suite.check("and is filled from the bags", feet.best.text:GetText() == "item:4")
suite.check("saying it fills the slot", feet.gain:GetText() == "fills an empty slot", feet.gain:GetText())

suite.check("a new ring goes against the weaker ring", Row(12).best.text:GetText() == "item:7",
    Row(12).best.text:GetText())
suite.check("not the stronger one", Link(Row(11).best) == nil)
suite.check("slots with nothing better show a dash", Row(1).best.text:GetText() == "-")

suite.check("the footer counts the upgrades", UI.footer:GetText() == "3 upgrades in your bags.",
    UI.footer:GetText())

-- Hovering a cell shows the item's own tooltip.
local shown
GameTooltip.SetHyperlink = function(_, link) shown = link end
chest.best:GetScript("OnEnter")(chest.best)
suite.check("hovering shows that item's tooltip", shown == "item:2", shown)
shown = nil
Row(1).best:GetScript("OnEnter")(Row(1).best)
suite.check("an empty cell shows none", shown == nil)

-- Putting the upgrade on moves it across.
env.worn[5] = "item:2"
env.bags[0][1] = "item:1"
suite.check("wearing the upgrade drops the count", UI:Refresh() == 2)
suite.check("and the chest now shows it worn", chest.worn.text:GetText() == "item:2")
suite.check("with nothing better left", Link(chest.best) == nil)

-- /beq spec re-judges while it is open.
ns.HandleSlash("spec sv")
suite.check("the header follows /beq spec", UI.specLabel:GetText() == "judging gear as Survival",
    UI.specLabel:GetText())

-- A class with no weights.
_G.UnitClass = function() return "DEATHKNIGHT", "DEATHKNIGHT" end
UI:Refresh()
suite.check("a class without weights says so", UI.footer:GetText() == "There are no stat weights for DEATHKNIGHT yet.",
    UI.footer:GetText())
suite.check("and offers nothing", Link(Row(8).best) == nil)
_G.UnitClass = function() return "HUNTER", "HUNTER" end

-- /beq window, and the settings button in the header.
UI:Hide()
ns.HandleSlash("window")
suite.check("/beq window opens it", UI.frame:IsShown())

-- Closed, it does no work.
UI:Hide()
suite.check("a closed window does not refresh", UI:Refresh() == 0)

-- Two rings in the bags that both beat the weaker worn ring: the runner-up
-- is measured against the other ring, so both ring slots can show one.
UI:Show()
env.worn[11], env.worn[12] = "item:6", "item:7"     -- Agi 2 and 5
env.bags[0] = { "item:5", "item:9" }                 -- Agi 8 and 6
ITEMS["item:9"] = { loc = "INVTYPE_FINGER", class = 4, subclass = 0, stats = Agi(6) }
UI:Refresh()
suite.check("the better ring goes against the weaker one", Link(Row(11).best) == "item:5",
    Link(Row(11).best))
suite.check("the second ring against the other", Link(Row(12).best) == "item:9", Link(Row(12).best))
suite.check("with its own gain", Row(12).gain:GetText() == "+20%", Row(12).gain:GetText())
env.bags[0] = { "item:5" }
UI:Refresh()
suite.check("one ring only fills one slot", Link(Row(12).best) == nil, Link(Row(12).best))
suite.check("upgrade rows are lit", Row(11).frame.edge:IsShown() and not Row(12).frame.edge:IsShown())
UI:Hide()

-- Its place is remembered.
UI.frame._point = { "TOPLEFT", nil, "TOPLEFT", 120, -80 }
UI:SavePosition()
suite.check("where it was dragged is saved", ns.db.point == "TOPLEFT" and ns.db.x == 120)

suite.done()
