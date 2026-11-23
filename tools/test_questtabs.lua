-- The upgrade quest panel leaves out each source tab whose boxes are
-- unticked in Where to get upgrades (`finderSourcesOff`), and brings it
-- back when one is ticked again. Dungeons and Raids stays while either of
-- its two boxes is ticked. The Quest log tab always stays. The tab shown,
-- once left out, gives way to the first tab still shown. With every box
-- unticked, every tab shows as before.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
-- This suite tests the old panels, kept until rework step 6; the small
-- panel (UI/SmallPanel.lua) stands in for them in play.
env.OLD_PANELS = true
local suite = env.NewSuite("questtabs")

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end

local Quest, Panel, UI = ns.UpgradeQuest, ns.QuestPanel, ns.FinderUI

local function Shown()
    local keys = {}
    for _, button in ipairs(Panel.tabs or {}) do
        if button:IsShown() then keys[#keys + 1] = button.key end
    end
    return table.concat(keys, ",")
end

local function Width(key)
    for _, button in ipairs(Panel.tabs or {}) do
        if button.key == key then return button:GetWidth() or 0 end
    end
    return 0
end

ns.UI:Show()
Quest:SetEnabled(true)
Quest:SelectTab("craft")
Panel:Refresh()
local logKey = Panel.LOG_TAB.key
suite.check("every box ticked: all five tabs show", Shown() == "vendor,quest,dungeon,craft," .. logKey, Shown())
local vendorWide = Width("vendor")

-- Untick Crafted while it is the tab shown.
UI:SetSource("craft", false)
Panel:Refresh()
suite.check("Crafted unticked: its tab goes", Shown() == "vendor,quest,dungeon," .. logKey, Shown())
suite.check("the tab shown moves to the first one left", Quest:Tab() == "vendor", Quest:Tab())
suite.check("and is saved there", ns.charDB.upgradeQuestTab == "vendor", tostring(ns.charDB.upgradeQuestTab))
suite.check("the tabs left grow wider", Width("vendor") > vendorWide, Width("vendor") .. " vs " .. vendorWide)

-- Dungeons and Raids needs both boxes off.
UI:SetSource("dungeon", false)
Panel:Refresh()
suite.check("Dungeons off, Raids on: Dungeons and Raids stays", Shown():find("dungeon", 1, true) ~= nil, Shown())
UI:SetSource("raid", false)
Panel:Refresh()
suite.check("both off: Dungeons and Raids goes", Shown() == "vendor,quest," .. logKey, Shown())

-- Ticking a box brings its tab back.
UI:SetSource("raid", true)
Panel:Refresh()
suite.check("Raids ticked again: Dungeons and Raids comes back", Shown() == "vendor,quest,dungeon," .. logKey, Shown())
suite.check("the tab shown stays where it moved", Quest:Tab() == "vendor", Quest:Tab())

-- The Quest log tab stays while its own view is up.
Panel:ShowLog(true)
UI:SetSource("vendor", false)
Panel:Refresh()
suite.check("the Quest log tab stays shown", Shown():find(logKey, 1, true) ~= nil and Panel:ShowsLog(), Shown())
suite.check("Vendor unticked: the picked tab moves to Quest", Quest:Tab() == "quest", Quest:Tab())

-- Every box off: every tab shows as before.
for _, kind in ipairs({ "vendor", "quest", "dungeon", "raid", "craft" }) do UI:SetSource(kind, false) end
Panel:Refresh()
suite.check("every box unticked: every tab shows", Shown() == "vendor,quest,dungeon,craft," .. logKey, Shown())

-- All back on.
for _, kind in ipairs({ "vendor", "quest", "dungeon", "raid", "craft" }) do UI:SetSource(kind, true) end
Panel:Refresh()
suite.check("every box ticked again: all five show", Shown() == "vendor,quest,dungeon,craft," .. logKey, Shown())

-- An old save with a hidden tab picked reads as the first tab shown.
ns.db.finderSourcesOff = { vendor = true }
ns.charDB.upgradeQuestTab = "vendor"
suite.check("a save picking a hidden tab reads the first shown", Quest:Tab() == "quest", Quest:Tab())
ns.db.finderSourcesOff = nil

suite.done()
