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

local Quest = ns.UpgradeQuest
local kept = { itemID = 1002, link = "item:1002", source = { kind = "vendor" } }

local function Tip()
    local lines = {}
    for _, line in ipairs(GameTooltip._lines or {}) do lines[#lines + 1] = tostring(line[1] or line.text or line) end
    return table.concat(lines, " | ")
end

suite.check("off to begin with", not Quest:IsEnabled())

-- Its quests are kept through a close.
ns.charDB.upgradeQuestTabs = ns.charDB.upgradeQuestTabs or {}
ns.charDB.upgradeQuestTabs.vendor = kept
Quest:SetEnabled(true)
suite.check("turned on, it says so", Quest:IsEnabled())
Quest:SetEnabled(false)
suite.check("turned off, its quests are kept", ns.charDB.upgradeQuestTabs.vendor == kept)

-- The minimap button's Shift-click.
local mini = ns.MinimapButton.button
local shift = false
_G.IsShiftKeyDown = function() return shift end
GameTooltip._lines = nil
mini:GetScript("OnEnter")(mini)
suite.check("the minimap tooltip names the Shift-click", Tip():find("Shift-click to bring back the upgrade quest", 1, true) ~= nil, Tip())
shift = true
mini:GetScript("OnClick")(mini, "LeftButton")
suite.check("with its quests as they were", ns.charDB.upgradeQuestTabs.vendor == kept)
mini:GetScript("OnClick")(mini, "LeftButton")
suite.check("a second Shift-click closes it", not Quest:IsEnabled())
shift = false
local uiShown = ns.UI:IsShown()
mini:GetScript("OnClick")(mini, "LeftButton")
suite.check("a plain click still opens or closes the gear window", ns.UI:IsShown() ~= uiShown)

-- /beq quest off and /beq quest, as before.
ns.HandleSlash("quest")
suite.check("/beq quest brings it back", Quest:IsEnabled())
ns.HandleSlash("quest off")
suite.check("/beq quest off closes it", not Quest:IsEnabled())

suite.done()
