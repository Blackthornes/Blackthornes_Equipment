-- The upgrade quest's source tab: a source whose boxes are unticked in
-- Where to get upgrades (`finderSourcesOff`) is left out, and the tab
-- picked, once left out, gives way to the first one still shown.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("questtabs")

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end

local Quest, Panel, UI = ns.UpgradeQuest, ns.SmallPanel, ns.FinderUI

ns.UI:Show()
Quest:SetEnabled(true)
Quest:SelectTab("craft")
Panel:Refresh()

-- Untick Crafted while it is the tab shown.
UI:SetSource("craft", false)
Panel:Refresh()
suite.check("the tab shown moves to the first one left", Quest:Tab() == "vendor", Quest:Tab())
suite.check("and is saved there", ns.charDB.upgradeQuestTab == "vendor", tostring(ns.charDB.upgradeQuestTab))

-- Dungeons and Raids needs both boxes off.
UI:SetSource("dungeon", false)
Panel:Refresh()
UI:SetSource("raid", false)
Panel:Refresh()

-- Ticking another box leaves the pick alone.
UI:SetSource("raid", true)
Panel:Refresh()
suite.check("the tab shown stays where it moved", Quest:Tab() == "vendor", Quest:Tab())

-- Vendor unticked too.
UI:SetSource("vendor", false)
Panel:Refresh()
suite.check("Vendor unticked: the picked tab moves to Quest", Quest:Tab() == "quest", Quest:Tab())

-- Every box off and on again raises nothing.
for _, kind in ipairs({ "vendor", "quest", "dungeon", "raid", "craft" }) do UI:SetSource(kind, false) end
Panel:Refresh()
for _, kind in ipairs({ "vendor", "quest", "dungeon", "raid", "craft" }) do UI:SetSource(kind, true) end
Panel:Refresh()

-- An old save with a hidden tab picked reads as the first tab shown.
ns.db.finderSourcesOff = { vendor = true }
ns.charDB.upgradeQuestTab = "vendor"
suite.check("a save picking a hidden tab reads the first shown", Quest:Tab() == "quest", Quest:Tab())
ns.db.finderSourcesOff = nil

suite.done()
