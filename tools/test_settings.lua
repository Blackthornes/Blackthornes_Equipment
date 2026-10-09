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

-- Every verdict can change with the spec: quest rewards and Tradeskills'
-- arrows are drawn again too, not only the bag arrows.
local asked, rewards = 0, 0
_G.BlackthornesTS = { Upgrades = { RedrawSoon = function() asked = asked + 1 end } }
local QuestRefresh = ns.QuestRewards.Refresh
ns.QuestRewards.Refresh = function(...) rewards = rewards + 1; return QuestRefresh(...) end
local function Told() return ("%d/%d"):format(asked, rewards) end

controls.spec:SetValue(2)
suite.check("picking a spec redraws quest rewards and Tradeskills' arrows",
    asked == 1 and rewards == 1, Told())
ns.HandleSlash("spec mm")
suite.check("and so does /beq spec", asked == 2 and rewards == 2, Told())
ns.HandleSlash("spec auto")
suite.check("and /beq spec auto", asked == 3 and rewards == 3 and ns.charDB.spec == nil, Told())

ns.QuestRewards.Refresh = QuestRefresh
_G.BlackthornesTS = nil

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
suite.check("the upgrade in chat box starts ticked", controls.upgradeChat:GetChecked())
controls.upgradeChat:GetScript("OnClick")(controls.upgradeChat)
suite.check("unticking it switches the chat line off", ns.db.upgradeChat == false, ns.db.upgradeChat)

-- The pages along the top, as Tradeskills' Settings tab has them.
local pages = SettingsUI.pages
suite.check("it opens on the first page", pages.shown == "gear", pages.shown)
suite.check("with the gear rows showing", pages.pages.gear.content:IsShown()
    and not pages.pages.general.content:IsShown())
local generalPart
for _, part in ipairs(pages.switch) do
    if part.key == "general" then generalPart = part end
end
generalPart.button:GetScript("OnClick")(generalPart.button)
suite.check("a click on the switch shows that page", pages.pages.general.content:IsShown()
    and not pages.pages.gear.content:IsShown())
suite.check("and the page is remembered", ns.db.settingsPage == "general")
suite.check("the page picked is gold", generalPart.label._color[1] == ns.Theme.colors.accent[1])
SettingsUI:Hide()
SettingsUI:Show()
suite.check("it opens again on the page left", pages.shown == "general")

-- Every page has rows, and the window is at least two columns wide.
for _, page in pairs(pages.pages) do
    suite.check(page.key .. " has rows", #page.rows > 0)
end
suite.check("the window is two columns wide or more",
    SettingsUI.frame:GetWidth() >= 330 * 2 + 18 + 18 * 2, SettingsUI.frame:GetWidth())

-- What a setting does is a tooltip until Show descriptions is ticked.
local tooltipRow
for _, row in ipairs(pages.pages.gear.rows) do
    if row.labelText == "Tooltip line" then tooltipRow = row end
end
suite.check("descriptions start hidden", ns.db.settingsDescriptions == false
    and not tooltipRow.hint:IsShown())
GameTooltip._lines = {}
tooltipRow:GetScript("OnEnter")(tooltipRow)
suite.check("a row lights under the mouse", tooltipRow.hover:IsShown())
suite.check("and says what it does in a tooltip", GameTooltip._lines[1] and
    GameTooltip._lines[1]:find("beats what you wear") ~= nil)
local before = SettingsUI.frame:GetHeight()
pages.describe:GetScript("OnClick")(pages.describe)
suite.check("Show descriptions is saved", ns.db.settingsDescriptions == true)
suite.check("and puts the words under the rows", tooltipRow.hint:IsShown())
suite.check("and the window grows to fit them", SettingsUI.frame:GetHeight() > before)
pages.describe:GetScript("OnClick")(pages.describe)
suite.check("unticked, the window goes back", SettingsUI.frame:GetHeight() == before)

-- The spec row's words change with the spec, in its tooltip too.
controls.spec:SetValue(3)
suite.check("the spec row's description follows the pick",
    SettingsUI.specRow.description:find("because you picked it", 1, true) ~= nil)
controls.spec:SetValue(1)

-- Find a setting.
pages.find:SetText("tomtom")
pages:Search("tomtom")
suite.check("the search shows the page that has it", pages.shown == "quest", pages.shown)
local lit = 0
for _, entry in ipairs(pages.searchables) do
    if entry.glow:IsShown() then lit = lit + 1 end
end
suite.check("and lights only what matches", lit == 1, lit)
pages:Search("")
lit = 0
for _, entry in ipairs(pages.searchables) do
    if entry.glow:IsShown() then lit = lit + 1 end
end
suite.check("an empty search lights nothing", lit == 0)

-- Text size, saved as a word, waits for a reload.
controls.textSize.plus:GetScript("OnClick")(controls.textSize.plus)
suite.check("Text size saves Large", ns.db.textSize == "large")
suite.check("and offers Reload now", controls.textSize.reload:IsShown())
controls.textSize.minus:GetScript("OnClick")(controls.textSize.minus)
suite.check("back to Normal needs no reload", ns.db.textSize == "normal"
    and not controls.textSize.reload:IsShown())
suite.check("sizes read through the step", ns.Theme.sizes.small == ns.Theme.BASE_SIZES.small)

-- Every /beq command has a button here.
local ran = {}
local realSlash = ns.HandleSlash
ns.HandleSlash = function(text) ran[#ran + 1] = text end
for _, key in ipairs({ "openWindow", "bags", "find", "tracked", "questArrowNext", "probe", "help" }) do
    controls[key]:GetScript("OnClick")(controls[key])
end
ns.HandleSlash = realSlash
suite.check("the command buttons run their commands",
    table.concat(ran, ",") == "window,bags,find,tracked,arrow next,probe,help", table.concat(ran, ","))

-- And every command registered has a control (house rule).
local covered = {
    window = true, bags = true, find = true, tracked = true, quest = true, arrow = true,
    probe = true, help = true, perf = true, spec = true, weights = true, minimap = true,
    settings = true,
}
for _, name in ipairs(ns.commandOrder) do
    suite.check("/beq " .. name .. " has a button in Settings", covered[name] == true)
end

-- Position.
ns.db.settingsX = 400
SettingsUI:ResetPositions()
suite.check("putting it back forgets where it was dragged", ns.db.settingsX == nil)

-- A client with neither options API still loads.
local ns2 = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER" end
suite.check("no options API is not an error", ns2.SettingsUI:RegisterGameOptions() == false)

suite.done()
