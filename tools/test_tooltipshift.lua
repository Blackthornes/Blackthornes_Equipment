-- Off, Shift or Always for each tooltip line (UI/TooltipShift.lua): nobody's
-- settings change until they pick, Shift holds a line back while Shift is
-- up, the hint goes on once, and the real tooltip hook follows it.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("tooltipshift")

local ITEMS = {
    ["item:1"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = { ITEM_MOD_AGILITY_SHORT = 10 } },
    ["item:2"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = { ITEM_MOD_AGILITY_SHORT = 15 } },
}

local shiftDown = false
_G.IsShiftKeyDown = function() return shiftDown end

local postCall
local ns = env.Load()
_G.UnitClass = function() return "HUNTER", "HUNTER" end
env.InstallItems(ITEMS, { [5] = "item:1" })
_G.Enum = { TooltipDataType = { Item = 0 } }
_G.TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) postCall = fn end }
ns.Tooltip:OnEnable()

local Shift = ns.TooltipShift
suite.check("the shared file is loaded", type(Shift) == "table")
suite.check("with this addon's lines", #Shift.KEYS == 5, #Shift.KEYS)

-- A player who never touches it: every line reads as it does today.
suite.check("an on line reads Always", Shift:Mode(ns.db.tooltipLine ~= false, "upgrade") == Shift.ALWAYS)
ns.db.suffixLine = false
suite.check("an off line reads Off", Shift:Mode(ns.db.suffixLine ~= false, "suffix") == Shift.OFF)
ns.db.suffixLine = true
suite.check("and nothing is written to the save", ns.db.tooltipShift == nil)
suite.check("an Always line shows", Shift:Shows("upgrade"))

-- The Settings stepper.
ns.SettingsUI:Show()
local controls = ns.SettingsUI.controls
suite.check("the tooltip stepper starts on Always", controls.tooltip:GetValue() == 2, controls.tooltip:GetValue())
suite.check("and says so", controls.tooltip.text:GetText() == "Always", controls.tooltip.text:GetText())
suite.check("the enchant stepper too", controls.enchantTooltip:GetValue() == 2)
suite.check("opening Settings wrote nothing", ns.db.tooltipShift == nil)

controls.tooltip:SetValue(1)
suite.check("Shift keeps the choice", ns.db.tooltipShift and ns.db.tooltipShift.upgrade == true)
suite.check("and leaves the line on", ns.db.tooltipLine ~= false)
suite.check("it is held back with Shift up", not Shift:Shows("upgrade"))
shiftDown = true
suite.check("and shown with Shift down", Shift:Shows("upgrade"))
shiftDown = false

-- The real hook: the verdict waits for Shift, and the hint says so once.
local tip = _G.GameTooltip
tip._lines = {}
postCall(tip, { id = 2, hyperlink = "item:2" })
suite.check("the verdict waits", #tip._lines == 1, tip._lines[1])
suite.check("for the hint alone", tip._lines[1] == "Hold Shift for more.", tip._lines[1])
Shift:Held(tip)
suite.check("the hint goes on once", #tip._lines == 1, #tip._lines)

-- Shift goes down: the tooltip is cleared and built again with the line.
shiftDown = true
tip._scripts.OnTooltipCleared(tip)
tip._lines = {}
postCall(tip, { id = 2, hyperlink = "item:2" })
suite.check("with Shift down the verdict comes back",
    tip._lines[1] == "|cff4fd18bUpgrade for Beast Mastery: +50%|r", tip._lines[1])
suite.check("and no hint", #tip._lines == 1, #tip._lines)
shiftDown = false

-- Off and back to Always.
controls.tooltip:SetValue(0)
suite.check("Off turns the line off", ns.db.tooltipLine == false)
controls.tooltip:Sync()
suite.check("and reads Off", controls.tooltip:GetValue() == 0)
controls.tooltip:SetValue(2)
suite.check("Always turns it on", ns.db.tooltipLine == true)
suite.check("and clears the Shift choice", ns.db.tooltipShift.upgrade == nil)
suite.check("so it shows with Shift up", Shift:Shows("upgrade"))

tip._scripts.OnTooltipCleared(tip)
tip._lines = {}
postCall(tip, { id = 2, hyperlink = "item:2" })
suite.check("and the verdict is back on the tooltip", #tip._lines == 1
    and tip._lines[1]:find("Upgrade for", 1, true) ~= nil, tip._lines[1])

-- The enchant line on Shift, on a worn piece.
controls.enchantTooltip:SetValue(1)
tip._scripts.OnTooltipCleared(tip)
tip._lines = {}
postCall(tip, { id = 1, hyperlink = "item:1" })
suite.check("the best enchant waits for Shift", #tip._lines == 1 and tip._lines[1] == "Hold Shift for more.",
    tip._lines[1])
shiftDown = true
tip._scripts.OnTooltipCleared(tip)
tip._lines = {}
postCall(tip, { id = 1, hyperlink = "item:1" })
suite.check("and shows with Shift down", tip._lines[1] and tip._lines[1]:find("Best enchant: ", 1, true) ~= nil,
    tip._lines[1])
shiftDown = false

suite.done()
