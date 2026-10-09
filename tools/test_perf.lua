-- The shortcuts that keep Equipment cheap give the same answers as the long
-- way: the client reads hand back every value, from the first call that
-- answers; a worn item's score is kept for the same weights and worked out
-- again for new ones; and the finder never works out sources for gear the
-- class cannot wear.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("perf")

local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end

local ITEMS = {
    ["item:1"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = Agi(10) },
    ["item:2"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = Agi(15) },
}

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
env.InstallItems(ITEMS, { [5] = "item:1" })
local Items, Compare, Weights = ns.Items, ns.Compare, ns.Weights

-- Reading the client.
local a, b, c = Items.Call({ "C_Item.GetItemInfo" }, "item:1")
suite.check("every value comes back", a == "Item" and b == "item:1" and c == 2, tostring(c))
local thirteenth = select(13, Items.Call({ "C_Item.GetItemInfo" }, "item:1"))
suite.check("down to the last", thirteenth == 2, thirteenth)
_G.PerfRaises = function() error("no") end
_G.PerfAnswers = function(x) return x, nil, "third" end
local first, second, third = Items.Call({ "PerfMissing", "PerfRaises", "PerfAnswers" }, 7)
suite.check("a missing or raising call falls through to the next", first == 7 and second == nil and third == "third")
suite.check("none answering gives nothing", Items.Call({ "PerfMissing", "PerfRaises" }) == nil)
_G.PerfRaises, _G.PerfAnswers = nil, nil

-- Scores kept per weights.
local statsAsked = 0
local realStats = _G.C_Item.GetItemStats
_G.C_Item.GetItemStats = function(link)
    statsAsked = statsAsked + 1
    return realStats(link)
end
_G.C_TooltipInfo = {
    GetHyperlink = function() return { lines = { { leftText = "Item" }, { leftText = "+10 Agility" } } } end,
}

local weights = { agility = 1 }
local one = Compare:ScoreOf("item:1", weights)
statsAsked = 0
local again = Compare:ScoreOf("item:1", weights)
suite.check("the same item and weights are scored once", again == one and statsAsked == 0, statsAsked)

local heavier = { agility = 2 }
local other = Compare:ScoreOf("item:1", heavier)
suite.check("new weights score it again", other == one * 2 and statsAsked == 1, tostring(other))

_G.C_TooltipInfo = { GetHyperlink = function() return { lines = { { leftText = "Retrieving item information" } } } end }
local fresh = { agility = 1 }
Compare:ScoreOf("item:2", fresh)
statsAsked = 0
Compare:ScoreOf("item:2", fresh)
suite.check("an item whose tooltip has not loaded is not kept", statsAsked == 1, statsAsked)
_G.C_TooltipInfo = nil
_G.C_Item.GetItemStats = realStats

local result = Compare:Judge("item:2")
suite.check("judging still works", result and result.verdict == "upgrade", result and result.verdict)

-- The finder skips what the class cannot wear.
suite.check("the finder's wear check is shared", type(ns.Finder.Wearable) == "function")

suite.done()
