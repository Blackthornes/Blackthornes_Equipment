-- Biggest Upgrade First: each Upgrade Quest tab picks the biggest % gain,
-- off unless ticked; ease only breaks a tie.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("biggestfirst")

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitRace = function() return "Human", "Human", 1 end
_G.GetRealZoneText = function() return "Elwynn Forest" end
env.InstallItems({ ["item:900"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = {} } }, { [5] = "item:900" }, { [0] = {} }, 20)

local Quest = ns.UpgradeQuest

local function Pick(itemID, percent, zone, empty)
    return { itemID = itemID, gain = percent, result = { percent = not empty and percent or nil, empty = empty },
        sources = { { kind = "vendor", zone = zone } } }
end
-- A small gain close by, a big one far away.
local near = Pick(1, 15, "Elwynn Forest")
local far = Pick(2, 18, "Wetlands")
local found = { player = { zone = "Elwynn Forest" }, slots = { [5] = { near }, [16] = { far } } }

suite.check("off unless ticked", not Quest:BiggestFirst() and ns.db.upgradeQuestBiggest == nil)
local farEase = Quest.Ease(far.sources[1], "Elwynn Forest")
local nearEase = Quest.Ease(near.sources[1], "Elwynn Forest")
suite.check("the fake tab is set up so ease matters", nearEase * 15 > farEase * 18, nearEase .. " " .. farEase)
local today = Quest:Choose(found, nil, "vendor")
suite.check("unticked, the close small gain wins as before", today and today.pick.itemID == 1, today and today.pick.itemID)

ns.db.upgradeQuestBiggest = true
local best = Quest:Choose(found, nil, "vendor")
suite.check("ticked, the biggest % gain is picked", best and best.pick.itemID == 2, best and best.pick.itemID)
suite.check("and it says it is the biggest gain", best and best.why == "biggest")

-- Same whole percent: the easier one wins.
local tieNear, tieFar = Pick(3, 10.2, "Elwynn Forest"), Pick(4, 9.8, "Wetlands")
best = Quest:Choose({ player = found.player, slots = { [5] = { tieFar, tieNear } } }, nil, "vendor")
suite.check("a tie in the percent shown goes to the easier one", best and best.pick.itemID == 3, best and best.pick.itemID)

-- An empty slot beats every percent.
best = Quest:Choose({ player = found.player, slots = { [5] = { far }, [6] = { Pick(5, 0, "Wetlands", true) } } }, nil, "vendor")
suite.check("an empty slot still comes first", best and best.pick.itemID == 5, best and best.pick.itemID)

-- Gear rules are untouched: a pick that waits on a level is still left out.
local later = Pick(6, 80, "Elwynn Forest")
later.at = 30
best = Quest:Choose({ player = found.player, slots = { [5] = { near, later } } }, nil, "vendor")
suite.check("gear that waits on a level is still left out", best and best.pick.itemID == 1, best and best.pick.itemID)

suite.check("PercentWorth rounds to the percent shown", Quest.PercentWorth({ percent = 9.6 }, 1) == 10)
suite.check("gain over a worn piece worth nothing beats a percent",
    Quest.PercentWorth({}, 3) > Quest.PercentWorth({ percent = 500 }, 1))

-- Ticking it lets go of quests not followed by hand, and keeps the rest.
ns.db.upgradeQuestBiggest = nil
local quests = Quest:Quests()
quests.vendor = { itemID = 11, link = "item:11", source = { kind = "vendor", zone = "Elwynn Forest" } }
quests.quest = { itemID = 12, link = "item:12", followed = true, source = { kind = "quest", zone = "Elwynn Forest" } }
Quest:SetBiggestFirst(true)
quests = Quest:Quests()
suite.check("ticked is saved", ns.db.upgradeQuestBiggest == true)
suite.check("a quest the addon picked is let go to pick again", not (quests.vendor and quests.vendor.itemID == 11))
suite.check("a quest followed by hand is kept", quests.quest and quests.quest.itemID == 12)
Quest:SetBiggestFirst(false)
suite.check("unticked saves nothing", ns.db.upgradeQuestBiggest == nil and not Quest:BiggestFirst())

-- Settings shows the box and ticking it there saves it.
ns.SettingsUI:Show()
local box = ns.SettingsUI.controls.questBiggest
suite.check("Settings has the box, unticked", box and not box:GetChecked())
box:GetScript("OnClick")(box)
suite.check("ticked in Settings", ns.db.upgradeQuestBiggest == true)
ns.SettingsUI:Hide()

suite.done()
