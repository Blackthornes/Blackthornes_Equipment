-- Following an upgrade (Make It My Quest in Find Upgrades, FinderUI:Follow)
-- makes it the upgrade quest, on its source's tab (asked 2026-10-06). The
-- row's clicks are tested with Find Upgrades (test_findupgrades.lua).

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("followquest")

local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end
local function Gear(loc, n) return { loc = loc, class = 4, subclass = 2, stats = Agi(n) } end

local ITEMS = {
    ["item:900"] = Gear("INVTYPE_CHEST", 10),   -- worn
    ["item:1001"] = Gear("INVTYPE_CHEST", 20),  -- sold by a vendor
    ["item:1002"] = Gear("INVTYPE_CHEST", 30),  -- quest reward
}

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitRace = function() return "Human", "Human", 1 end
_G.GetRealZoneText = function() return "Elwynn Forest" end
env.InstallItems(ITEMS, { [5] = "item:900" }, { [0] = {} }, 20)
_G.C_QuestLog = {
    IsQuestFlaggedCompleted = function() return false end,
    IsOnQuest = function() return false end,
    ReadyForTurnIn = function() return false end,
}

local S = ns.Sources
ns.Crafts.ITEMS = {}
ns.RollData.ITEMS = {}
S.ZONES = { [12] = "Elwynn Forest" }
S.NPCS = { [1] = { "Corina Steele", 12, 41.5, 65.9, "A" } }
S.QUESTS = { [10] = { "Wolves of the Forest", 15, 18, 0, 0, "Marshal Dughan", 12, 42.1, 65.9, "" } }
S.DUNGEONS = {}
S.BOSSES = {}
S.FOREVER = {}
S.ITEMS = {
    [1001] = { 15, 18, 0, 0, 12050, v = { 1, 0 } },
    [1002] = { 15, 18, 0, 0, 0, q = { 10 } },
}

local Quest, Panel, UI = ns.UpgradeQuest, ns.SmallPanel, ns.FinderUI

-- The picks as a scan finds them, the way a row of Find Upgrades holds one.
local found = ns.Finder:Scan()
local function Pick(itemID)
    for _, list in pairs(found.slots) do
        for _, pick in ipairs(list) do
            if pick.itemID == itemID then return pick end
        end
    end
end

suite.check("the quest starts off", not Quest:IsEnabled())
suite.check("both upgrades are found", Pick(1001) ~= nil and Pick(1002) ~= nil)

-- A skipped upgrade can still be chosen by hand.
Quest:Skipped()[1001] = true
UI:Follow(Pick(1001))
suite.check("following turns the quest on", Quest:IsEnabled() and ns.db.upgradeQuest == true)
suite.check("and follows the vendor's chest on the Vendor tab", Quest:Tab() == "vendor"
    and Quest:Current() and Quest:Current().itemID == 1001, Quest:Tab())
suite.check("the copy older versions read follows", ns.charDB.upgradeQuest == Quest:Current())
suite.check("it is no longer skipped", not Quest:Skipped()[1001])
suite.check("the small panel opens", Panel.frame ~= nil and Panel.frame:IsShown())
suite.check("the chat says so", env.ChatText():find("following item:1001", 1, true) ~= nil)
suite.check("it is marked as followed", Quest:IsFollowing(1001))

-- The quest reward goes on the Quest tab, and the vendor's is kept.
UI:Follow(Pick(1002))
suite.check("the quest reward goes on the Quest tab", Quest:Tab() == "quest" and Quest:Current().itemID == 1002)
suite.check("the Vendor tab keeps its pick", Quest:QuestOn("vendor") and Quest:QuestOn("vendor").itemID == 1001)

-- Following while the panel shows the Quest log tab shows the followed
-- quest's tab instead.
ns.charDB.questLogTab = true
UI:Follow(Pick(1002))
suite.check("following leaves the Quest log tab", ns.charDB.questLogTab == nil and Quest:Tab() == "quest")
UI:Follow(Pick(1001))

-- What cannot be followed yet says why, and changes nothing.
local function Says(pick, words)
    local source, why = Quest.CanFollow(pick)
    return source == nil and type(why) == "string" and why:find(words, 1, true) ~= nil, why
end
local vendor = { kind = "vendor", name = "Corina Steele" }
suite.check("a reputation not reached", Says({ itemID = 1001, sources = { vendor },
    needs = { standing = "Honored", faction = "Stormwind" } }, "Honored with Stormwind"))
suite.check("a level not reached", Says({ itemID = 1001, sources = { vendor }, at = 22 }, "level 22"))
suite.check("only another player's craft", Says({ itemID = 1001,
    sources = { { kind = "craft", state = "other" } } }, "another player"))
suite.check("an alt's craft can be followed", Quest.CanFollow({ itemID = 1001,
    sources = { { kind = "craft", state = "alt" } } }) ~= nil)
local before = Quest:Current().itemID
UI:Follow({ itemID = 1002, link = "item:1002", sources = { vendor }, at = 22 })
suite.check("a click on one changes nothing", Quest:Current().itemID == before)
suite.check("and the chat says why", env.ChatText():find("can't be an upgrade quest yet: you can wear it from level 22", 1, true) ~= nil)

-- Turned off and on again by hand, the picks are still there.
Quest:SetEnabled(false)
suite.check("off, nothing is marked", not Quest:IsFollowing(1001))

suite.done()
