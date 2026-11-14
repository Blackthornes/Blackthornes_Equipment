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

--------------------------------------------------------------------------------
-- Shift redraws the tooltip only when its lines can be read
--------------------------------------------------------------------------------

-- A secret value, as an instance hands one out: any touch raises.
local function Secret(what)
    local raise = function() error("secret value: " .. what, 2) end
    return setmetatable({}, { __index = raise, __newindex = raise, __call = raise,
        __concat = raise, __eq = raise, __lt = raise, __le = raise, __tostring = raise })
end

local shared = _G.BlackthornesTooltipShift
local REDRAW_KEY = Shift.KEYS[1]
local savedTooltip, savedTooltipInfo = _G.GameTooltip, _G.C_TooltipInfo
Shift:Apply(Shift.SHIFT, REDRAW_KEY, true, nil)
suite.check("a line is on Shift for the redraw", shared.AnyShift())

local lines
_G.C_TooltipInfo = { GetUnit = function() return { lines = lines } end }

local function RedrawTooltip()
    local tooltip = { _refreshed = 0 }
    tooltip.IsShown = function() return true end
    tooltip.GetPrimaryTooltipInfo = function() return { getterName = "GetUnit", getterArgs = { "mouseover" } } end
    tooltip.RefreshData = function(self) self._refreshed = self._refreshed + 1 end
    _G.GameTooltip = tooltip
    return tooltip
end

local plain = { GetRGB = function() return 1, 1, 1 end }
lines = { { leftColor = plain }, { leftColor = plain, rightColor = plain } }
local redraw = RedrawTooltip()
shared.OnModifier("LSHIFT")
suite.check("plain lines are redrawn on Shift", redraw._refreshed == 1, redraw._refreshed)
shared.OnModifier("LCTRL")
suite.check("another key redraws nothing", redraw._refreshed == 1)

lines = { { leftColor = plain }, { leftColor = Secret("a color") } }
redraw = RedrawTooltip()
local ok = pcall(shared.OnModifier, "RSHIFT")
suite.check("a secret color raises nothing", ok)
suite.check("and the tooltip is left as it is", redraw._refreshed == 0, redraw._refreshed)

lines = { { leftColor = plain, rightColor = Secret("a color") } }
redraw = RedrawTooltip()
ok = pcall(shared.OnModifier, "LSHIFT")
suite.check("a secret right color too", ok and redraw._refreshed == 0)

redraw = RedrawTooltip()
redraw.GetPrimaryTooltipInfo = function() return nil end
shared.OnModifier("LSHIFT")
suite.check("a tooltip with no info is left alone", redraw._refreshed == 0)

lines = { { leftColor = plain } }
redraw = RedrawTooltip()
redraw.GetPrimaryTooltipInfo = nil
redraw.infoList = { { getterName = "GetUnit", getterArgs = { "mouseover" } } }
shared.OnModifier("LSHIFT")
suite.check("an older client's info list reads the same", redraw._refreshed == 1)

-- Every line back to Always: nothing is left on Shift, so Shift redraws nothing.
for _, key in ipairs(Shift.KEYS) do Shift:Apply(Shift.ALWAYS, key, true, nil) end
redraw = RedrawTooltip()
shared.OnModifier("LSHIFT")
suite.check("with no line on Shift nothing is redrawn", redraw._refreshed == 0)

-- An older copy of this file, loaded after, writes its handler plainly.
local newest = shared.OnModifier
shared.OnModifier = function() error("the old handler ran") end
suite.check("an older copy cannot put its handler back", shared.OnModifier == newest)
suite.check("the newest copy's version is kept", shared.handlers.version == Shift.FILE_VERSION)
suite.check("nor an older AnyShift", shared.AnyShift ~= nil and shared.AnyShift() == false)
suite.check("the frame still finds the handler", _G.BlackthornesTooltipShift.OnModifier == newest)
_G.GameTooltip, _G.C_TooltipInfo = savedTooltip, savedTooltipInfo

suite.done()
