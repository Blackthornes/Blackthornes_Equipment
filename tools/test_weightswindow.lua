-- The stat weights window: opens on the spec gear is judged by, steps and
-- typed values land in the saved weights, reset puts them back, and nothing
-- is cut off.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("weightswindow")

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER" end

local WeightsUI, Weights = ns.WeightsUI, ns.Weights

ns.HandleSlash("weights")
suite.check("/beq weights opens it", WeightsUI.frame:IsShown())
suite.check("on the player's class", WeightsUI.class == "HUNTER", WeightsUI.class)
suite.check("and the spec gear is judged by", WeightsUI.spec == "beast", WeightsUI.spec)
suite.check("the class picker reads Hunter",
    WeightsUI.classPicker.text:GetText() == "Hunter", WeightsUI.classPicker.text:GetText())
suite.check("the spec picker reads Beast Mastery",
    WeightsUI.specPicker.text:GetText() == "Beast Mastery", WeightsUI.specPicker.text:GetText())
suite.check("the status says the built-in weights are in use",
    WeightsUI.status:GetText():find("uses the built-in weights", 1, true), WeightsUI.status:GetText())
suite.check("and that this is the spec gear is judged by",
    WeightsUI.status:GetText():find("judged by this spec", 1, true))
suite.check("there is nothing to reset yet", not WeightsUI.reset:IsShown())

local function Row(key)
    for _, row in ipairs(WeightsUI.rows) do
        if row.entry.key == key then return row end
    end
end

-- Which stats are listed.
suite.check("a hunter sees agility", Row("agility"):IsShown())
suite.check("but not spell power", not Row("spellPower"):IsShown())
WeightsUI.allStats:GetScript("OnClick")(WeightsUI.allStats)
suite.check("every stat shows them all", Row("spellPower"):IsShown())
WeightsUI.allStats:GetScript("OnClick")(WeightsUI.allStats)
suite.check("and unticking hides them again", not Row("spellPower"):IsShown())

suite.check("a row shows the built-in weight", Row("crit").box:GetText() == "12", Row("crit").box:GetText())
suite.check("without trailing zeros", Row("armor").box:GetText() == "0.02", Row("armor").box:GetText())

-- Steps.
Row("crit").plus:GetScript("OnClick")(Row("crit").plus)
suite.check("+ adds a whole point to crit", Weights:Get("HUNTER", "beast").crit == 13)
suite.check("the box shows it", Row("crit").box:GetText() == "13")
suite.check("the row is marked as changed", Row("crit").mark:IsShown())
suite.check("and reset appears", WeightsUI.reset:IsShown())
suite.check("the status counts it",
    WeightsUI.status:GetText():find("1 stat changed", 1, true), WeightsUI.status:GetText())

Row("stamina").minus:GetScript("OnClick")(Row("stamina").minus)
suite.check("- takes a small step off a small weight",
    Weights:Get("HUNTER", "beast").stamina == 0.45, Weights:Get("HUNTER", "beast").stamina)

suite.check("1 steps down to 0.95", WeightsUI.Nudge(1, -1) == 0.95, WeightsUI.Nudge(1, -1))
suite.check("0 does not go below 0", WeightsUI.Nudge(0, -1) == 0)
suite.check("0.02 steps up to 0.03", WeightsUI.Nudge(0.02, 1) == 0.03, WeightsUI.Nudge(0.02, 1))

-- Typing.
local box = Row("hit").box
box:GetScript("OnEditFocusGained")(box)
box:SetText("7,5")
box:GetScript("OnEnterPressed")(box)
suite.check("a typed weight is kept, with a comma for a point",
    Weights:Get("HUNTER", "beast").hit == 7.5, Weights:Get("HUNTER", "beast").hit)

box:GetScript("OnEditFocusGained")(box)
box:SetText("abc")
box:GetScript("OnEnterPressed")(box)
suite.check("text that is not a number changes nothing", Weights:Get("HUNTER", "beast").hit == 7.5)
suite.check("and the box goes back to the weight", box:GetText() == "7.5", box:GetText())

box:GetScript("OnEditFocusGained")(box)
box:SetText("3")
box:GetScript("OnEscapePressed")(box)
suite.check("escape throws away what was typed", Weights:Get("HUNTER", "beast").hit == 7.5
    and box:GetText() == "7.5", box:GetText())

-- Other specs and classes.
WeightsUI.specPicker:SetValue(2)
suite.check("stepping the spec shows Marksmanship", WeightsUI.spec == "marks"
    and Row("crit").box:GetText() == "15", Row("crit").box:GetText())
suite.check("which is untouched", not WeightsUI.reset:IsShown())
suite.check("and not the spec gear is judged by",
    not WeightsUI.status:GetText():find("judged by this spec", 1, true))

WeightsUI.classPicker:SetValue(7)
suite.check("stepping the class to Mage", WeightsUI.class == "MAGE" and WeightsUI.spec == "arcane",
    WeightsUI.class .. " " .. tostring(WeightsUI.spec))
suite.check("lists spell power", Row("spellPower"):IsShown())
suite.check("and not ranged attack power", not Row("rangedAttackPower"):IsShown())

WeightsUI.classPicker:SetValue(3)
suite.check("back on Hunter it opens on the spec gear is judged by", WeightsUI.spec == "beast")

-- Reset.
WeightsUI.reset:GetScript("OnClick")(WeightsUI.reset)
suite.check("reset puts every weight back",
    not Weights:IsCustom("HUNTER", "beast") and Row("crit").box:GetText() == "12")

-- The settings window has a way in.
ns.HandleSlash("weights")
suite.check("/beq weights closes it", not WeightsUI.frame:IsShown())
ns.SettingsUI:Show()
ns.SettingsUI.controls.weights:GetScript("OnClick")(ns.SettingsUI.controls.weights)
suite.check("the settings button opens it", WeightsUI.frame:IsShown())

-- Fit: no label narrower than its text, and the columns inside the window.
for _, row in ipairs(WeightsUI.rows) do
    local text = row.label:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    suite.check(row.entry.name .. " fits its label", row.label:GetWidth() >= #text * 6,
        row.label:GetWidth() .. " < " .. #text * 6)
end
suite.check("both columns fit the window",
    WeightsUI.columnWidth * 2 + 22 + 36 <= WeightsUI.width, WeightsUI.width)

suite.done()
