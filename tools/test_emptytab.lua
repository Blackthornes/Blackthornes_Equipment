-- The upgrade quest never shows an empty source while another has an
-- upgrade (the owner's report, 2026-11-24: Quest was the tab picked and had
-- nothing, while Crafted held Shadoweave Pants, so the small panel and the
-- Upgrade Quest tab said "No quest reward is an upgrade right now.").

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("emptytab")

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end

local Quest = ns.UpgradeQuest
Quest:SetEnabled(true)

-- Vendor and Dungeons unticked, as in the report: Quest and Crafted show.
ns.db.finderSourcesOff = { vendor = true, dungeon = true, raid = true }
ns.charDB.questLogTab = nil
ns.charDB.upgradeQuestTab = "quest"
local pants = { itemID = 10070, link = "[Shadoweave Pants]", source = { kind = "craft" }, followed = true }
ns.charDB.upgradeQuestTabs = { craft = pants }
Quest.states.quest = "none"
Quest.states.craft = "active"

suite.check("an empty picked tab gives way to one with an upgrade", Quest:Tab() == "craft", Quest:Tab())
suite.check("so the upgrade shows", Quest:Current() == pants)
suite.check("the pick saved is left alone", ns.charDB.upgradeQuestTab == "quest")

-- Still looking on the picked tab: it stays, and says it is looking.
Quest.states.quest = "waiting"
suite.check("a picked tab still looking stays", Quest:Tab() == "quest", Quest:Tab())
Quest.states.quest = "none"

-- A source left out of the window is never shown in its place.
ns.db.finderSourcesOff = { vendor = true, dungeon = true, raid = true, craft = true }
suite.check("a hidden tab's upgrade is not shown", Quest:Tab() == "quest", Quest:Tab())
ns.db.finderSourcesOff = { vendor = true, dungeon = true, raid = true }

-- Every tab empty: the picked one shows its own line.
ns.charDB.upgradeQuestTabs = {}
suite.check("every tab empty: the picked one stays", Quest:Tab() == "quest", Quest:Tab())

-- Picked by hand, an empty tab shows as it is.
Quest:SelectTab("quest")
suite.check("an empty tab picked by hand shows", Quest:Tab() == "quest" and Quest:Current() == nil, Quest:Tab())

-- Clicking Crafted while it stands in saves it as the pick.
ns.charDB.upgradeQuestTabs = { craft = pants }
Quest:SelectTab("craft")
suite.check("picking the tab shown saves it", ns.charDB.upgradeQuestTab == "craft", tostring(ns.charDB.upgradeQuestTab))

ns.db.finderSourcesOff = nil
suite.done()
