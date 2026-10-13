-- Closing the upgrade quest and bringing it back (the owner asked
-- 2026-10-13 for an easy way to do both): the close gem says how to bring
-- it back, the gear window's Upgrade quest button and the minimap button's
-- Shift-click close it or bring it back, and its quests are kept closed.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("questtoggle")

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end

local Quest, Panel = ns.UpgradeQuest, ns.QuestPanel
local kept = { itemID = 1002, link = "item:1002", source = { kind = "vendor" } }

local function Tip()
    local lines = {}
    for _, line in ipairs(GameTooltip._lines or {}) do lines[#lines + 1] = tostring(line[1] or line.text or line) end
    return table.concat(lines, " | ")
end

suite.check("off to begin with", not Quest:IsEnabled())

-- The gear window's button brings it back.
ns.UI:Show()
local button = ns.UI.questButton
suite.check("the gear window has an Upgrade quest button", button ~= nil and ns.UI.frame:IsShown())
GameTooltip._lines = nil
button:GetScript("OnEnter")(button)
suite.check("off, its tooltip says a click brings it back", Tip():find("bring back", 1, true) ~= nil, Tip())
button:GetScript("OnClick")(button, "LeftButton")
suite.check("a click turns it on", Quest:IsEnabled() and Panel.frame and Panel.frame:IsShown())
suite.check("and says so", env.ChatText():find("upgrade quest on", 1, true) ~= nil)

-- Its quests are kept through a close.
ns.charDB.upgradeQuestTabs = ns.charDB.upgradeQuestTabs or {}
ns.charDB.upgradeQuestTabs.vendor = kept

-- The close gem explains itself, then closes it.
local gem = Panel.trim and rawget(Panel.trim, "closeButton")
suite.check("the panel has a close gem", gem ~= nil)
GameTooltip._lines = nil
gem:GetScript("OnEnter")(gem)
suite.check("its tooltip says how to bring it back", Tip():find("/beq quest", 1, true) ~= nil
    and Tip():find("Upgrade quest in the gear window", 1, true) ~= nil, Tip())
gem:GetScript("OnClick")(gem)
suite.check("the close gem closes it", not Quest:IsEnabled() and not Panel.frame:IsShown())
suite.check("chat says how to bring it back", env.ChatText():find("Bring it back with the Upgrade quest button", 1, true) ~= nil)
suite.check("its quests are kept", ns.charDB.upgradeQuestTabs.vendor == kept)

-- The minimap button's Shift-click.
local mini = ns.MinimapButton.button
local shift = false
_G.IsShiftKeyDown = function() return shift end
GameTooltip._lines = nil
mini:GetScript("OnEnter")(mini)
suite.check("the minimap tooltip names the Shift-click", Tip():find("Shift-click to bring back the upgrade quest", 1, true) ~= nil, Tip())
shift = true
mini:GetScript("OnClick")(mini, "LeftButton")
suite.check("Shift-click brings it back", Quest:IsEnabled() and Panel.frame:IsShown())
suite.check("with its quests as they were", ns.charDB.upgradeQuestTabs.vendor == kept)
mini:GetScript("OnClick")(mini, "LeftButton")
suite.check("a second Shift-click closes it", not Quest:IsEnabled())
shift = false
local uiShown = ns.UI.frame:IsShown()
mini:GetScript("OnClick")(mini, "LeftButton")
suite.check("a plain click still opens or closes the gear window", ns.UI.frame:IsShown() ~= uiShown)

-- /beq quest off and /beq quest, as before.
ns.HandleSlash("quest")
suite.check("/beq quest brings it back", Quest:IsEnabled())
ns.HandleSlash("quest off")
suite.check("/beq quest off closes it", not Quest:IsEnabled())

suite.done()
