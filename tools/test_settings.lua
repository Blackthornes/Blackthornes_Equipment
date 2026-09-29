-- The settings window.
--
-- What matters is that every way in opens it, that each control changes the
-- same saved value its chat command does, and that the page shows what is
-- saved rather than what it last drew.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("settings")

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER" end

local SettingsUI = ns.SettingsUI

-- A client with retail's Settings API, recording what is registered.
local registered = {}
_G.Settings = {
    RegisterCanvasLayoutCategory = function(panel, name) return { panel = panel, name = name } end,
    RegisterAddOnCategory = function(category) registered[#registered + 1] = category end,
}

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end

suite.check("it is listed under the game's AddOns options",
    registered[1] and registered[1].name == "Blackthornes Equipment")

-- Ways in.
ns.HandleSlash("settings")
suite.check("/beq settings opens it", SettingsUI.frame:IsShown())
ns.HandleSlash("settings")
suite.check("and closes it", not SettingsUI.frame:IsShown())
ns.HandleSlash("options")
suite.check("/beq options works too", SettingsUI.frame:IsShown())
suite.check("options is not listed twice in help",
    not (function()
        for _, name in ipairs(ns.commandOrder) do
            if name == "options" or name == "config" then return true end
        end
    end)())

local controls = SettingsUI.controls

-- The spec stepper.
suite.check("the spec starts on Auto", controls.spec:GetValue() == 1)
suite.check("which reads Auto", controls.spec.text:GetText() == "Auto", controls.spec.text:GetText())
suite.check("and says what Auto means now",
    SettingsUI.specRow.hint:GetText():find("Beast Mastery until your talents", 1, true),
    SettingsUI.specRow.hint:GetText())

controls.spec:SetValue(3)
suite.check("stepping to Marksmanship picks it", ns.charDB.spec == "marks", ns.charDB.spec)
suite.check("the stepper shows its name",
    controls.spec.text:GetText() == "Marksmanship", controls.spec.text:GetText())
suite.check("and the hint says it was picked",
    SettingsUI.specRow.hint:GetText():find("because you picked it", 1, true))

ns.HandleSlash("spec sv")
suite.check("/beq spec while it is open moves the stepper",
    controls.spec:GetValue() == 4 and controls.spec.text:GetText() == "Survival",
    controls.spec.text:GetText())

controls.spec:SetValue(1)
suite.check("stepping back to Auto clears the pick", ns.charDB.spec == nil)

-- The minimap checkbox.
local minimapBox = controls.minimap
suite.check("the minimap box starts ticked", minimapBox:GetChecked())
minimapBox:GetScript("OnClick")(minimapBox)
suite.check("unticking hides the button",
    ns.db.minimapHidden == true and not ns.MinimapButton.button:IsShown())
ns.HandleSlash("minimap")
suite.check("/beq minimap ticks it again", minimapBox:GetChecked())

-- Debug.
controls.debug:GetScript("OnClick")(controls.debug)
suite.check("the debug box sets debug", ns.db.debug == true)

-- The verdict switches.
suite.check("the tooltip box starts ticked", controls.tooltip:GetChecked())
suite.check("so does the bag arrows box", controls.arrows:GetChecked())
controls.arrows:GetScript("OnClick")(controls.arrows)
suite.check("unticking it switches the arrows off", ns.db.bagArrows == false, ns.db.bagArrows)
controls.tooltip:GetScript("OnClick")(controls.tooltip)
suite.check("and the tooltip line", ns.db.tooltipLine == false, ns.db.tooltipLine)

-- Position.
ns.db.settingsX = 400
SettingsUI:ResetPositions()
suite.check("putting it back forgets where it was dragged", ns.db.settingsX == nil)

-- A client with neither options API still loads.
local ns2 = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER" end
suite.check("no options API is not an error", ns2.SettingsUI:RegisterGameOptions() == false)

suite.done()
