-- Auction house gear in Find Upgrades (the owner said build it from a
-- mockup, 2026-11-26). Nothing here scans: it reads what Tradeskills saw
-- listed at its last scan.
--
-- What must hold:
--   1. Gear Tradeskills saw on sale that beats what you wear shows, with
--      an Auction House box, its price and where it is from.
--   2. The sheet says the lowest price, how many and when, and the gold
--      you have, with Search the Auction House leading (no quest to make).
--   3. Auction Price hides what costs more; so does gear you can't pay for.
--   4. The upgrade quest never picks the auction house.
--   5. A Tradeskills scan reads again; random suffix gear is left out.
--   6. Without Tradeskills there is no box and nothing from it.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("auctiongear")

local ARMOR, LEATHER = 4, 2
local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end
local function Piece(loc, n)
    return { loc = loc, class = ARMOR, subclass = LEATHER, stats = Agi(n), bind = 2 }
end

local ITEMS = {
    ["item:800"] = Piece("INVTYPE_HEAD", 5),     -- worn
    ["item:900"] = Piece("INVTYPE_WAIST", 5),    -- worn
    ["item:3001"] = Piece("INVTYPE_HEAD", 12),   -- on sale, 4g 20s
    ["item:3002"] = Piece("INVTYPE_WAIST", 9),   -- on sale, 75s
    ["item:3003"] = Piece("INVTYPE_WAIST", 20),  -- on sale, random suffix
    ["item:3004"] = { loc = "", class = 7, subclass = 0, stats = {} },  -- cloth, not gear
}

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitFactionGroup = function() return "Horde", "Horde" end
_G.UnitRace = function() return "Orc", "Orc", 2 end
env.InstallItems(ITEMS, { [1] = "item:800", [6] = "item:900" }, { [0] = {} }, 30)
local money = 110400   -- 11g 4s
_G.GetMoney = function() return money end

local clock = 1790000000
_G.time = function() return clock end
local onSale = {
    [3001] = { price = 42000, count = 2, seen = clock - 7200 },
    [3002] = { price = 7500, count = 1, seen = clock - 7200 },
    [3003] = { price = 9000, count = 1, seen = clock - 7200 },
    [3004] = { price = 100, count = 20, seen = clock - 7200 },
}
local watchers, searched = {}, nil
_G.BlackthornesTS = {
    Prices = {
        OnSale = function() return onSale, clock - 7200 end,
        WatchScans = function(_, fn) watchers[#watchers + 1] = fn end,
    },
    Butler = {
        SearchAuctions = function(_, items) searched = items return true, "all" end,
    },
}

local S = ns.Sources
ns.Crafts.ITEMS = {}
ns.RollData.ITEMS = { [3003] = 1 }
ns.RollData.GROUPS = { [1] = {} }
S.ZONES, S.NPCS, S.QUESTS, S.DUNGEONS, S.BOSSES, S.FOREVER, S.ITEMS = {}, {}, {}, {}, {}, {}, {}

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end
local Gear, Find, Finder, FinderUI, AG = ns.GearWindow, ns.FindUpgrades, ns.Finder, ns.FinderUI, ns.AuctionGear
local Quest = ns.UpgradeQuest
Quest.Zone = function() return "Orgrimmar" end

local function Listed()
    local out = {}
    for _, row in ipairs(Find.rows) do
        if row:IsShown() and rawget(row, "line") then out[#out + 1] = row.line.pick.itemID end
    end
    return table.concat(out, ",")
end
local function Row(itemID)
    for _, row in ipairs(Find.rows) do
        if row:IsShown() and rawget(row, "line") and row.line.pick.itemID == itemID then return row end
    end
end
local function Box(kind)
    for _, box in ipairs(Find.sourceBoxes) do
        if box.kind == kind then return box end
    end
end
local function Button(text)
    for _, button in ipairs(Find.sheetButtons) do
        if button:IsShown() and button.label:GetText() == text then return button end
    end
end
local function Click(frame, ...) frame:GetScript("OnClick")(frame, ...) end

suite.check("Tradeskills can be read", AG:On())
suite.check("it lists only gear, never random suffixes", table.concat(AG:IDs(), ",") == "3001,3002",
    table.concat(AG:IDs(), ","))

-- 1.
ns.UI:Show()
Gear:ShowTab("find")
Find.sheetHold:SetHeight(590)
suite.check("both pieces on sale show, the biggest gain first", Listed() == "3001,3002", Listed())
suite.check("an Auction House box under FROM", Box("auction") ~= nil and Box("auction"):GetChecked() == true)
suite.check("it counts them", Find.sourceCounts.auction:GetText() == "2", Find.sourceCounts.auction:GetText())
local where = Row(3001) and Row(3001).where:GetText() or ""
suite.check("the row says Auction House and its price", where:find("Auction House", 1, true) ~= nil
    and where:find("4", 1, true) ~= nil, where)
suite.check("prices say how old they are", Find.auctionAge:GetText() == "Prices are from your last scan, 2 hours ago.",
    Find.auctionAge:GetText())
suite.check("the footer counts them", Find.footer:GetText():find("2 are on the auction house.", 1, true) ~= nil,
    Find.footer:GetText())
suite.check("a bar under each gain, the biggest full", Row(3001).barFill:IsShown()
    and Row(3001).barFill:GetWidth() > Row(3002).barFill:GetWidth(), Row(3001).barFill:GetWidth())

-- 2.
Find.picked = Row(3001).line.key
Find:PaintSheet()
local notes = Find.sheetNotes:GetText()
suite.check("the sheet gives the lowest price", notes:find("Lowest price:", 1, true) ~= nil, notes)
suite.check("how many and when", notes:find("2 for sale at your last scan, 2 hours ago.", 1, true) ~= nil, notes)
suite.check("and the gold you have", notes:find("You have ", 1, true) ~= nil, notes)
suite.check("Search the Auction House leads", Button("Search the Auction House") ~= nil
    and Button("Make It My Quest") == nil and Button("Track") ~= nil)
Click(Button("Search the Auction House"))
suite.check("it asks Tradeskills to search for it", searched and searched[1].itemID == 3001)

-- 3.
Find.mostChoice:SetValue(3)
if Find.mostChoice.onChange then Find.mostChoice.onChange(3) end
AG:SetMost(AG.MOST[3])
Find:Narrow()
suite.check("Up to 5g keeps both", Listed() == "3001,3002", Listed())
AG:SetMost(AG.MOST[2])
Find:Narrow()
suite.check("Up to 1g hides the 4g 20s one", Listed() == "3002" and ns.db.findAuctionMost == 10000, Listed())
suite.check("Auction Price reads as approved", Find.MostText(1) == "Any" and Find.MostText(2) == "Up to 1g"
    and Find.MostText(3) == "Up to 5g" and Find.MostText(4) == "Up to 20g")
Click(Find.showAll)
suite.check("Show All puts Any back", ns.db.findAuctionMost == nil and Listed() == "3001,3002", Listed())
money = 9000
Find:Narrow()
suite.check("gear you can't pay for hides", Listed() == "3002", Listed())
money = 110400
Find:Narrow()

-- 4.
local pick = Row(3001).line.pick
suite.check("not a quest to follow", Quest.CanFollow(pick) == nil)
suite.check("never the upgrade quest's pick", Quest.BestSource(pick.sources) == nil)
local chosen = Quest:Choose(Find.state.found)
suite.check("the quest picks nothing from it", chosen == nil, chosen and chosen.pick.itemID)

-- 5.
onSale[3002] = nil
suite.check("Tradeskills' scans are listened to", #watchers == 1)
local changes = Finder.changes or 0
watchers[1]({ items = 1 })
suite.check("a new scan reads again", table.concat(AG:IDs(), ",") == "3001", table.concat(AG:IDs(), ","))
suite.check("and looks for upgrades again", (Finder.changes or 0) > changes)
suite.check("the sold one leaves the list", Listed() == "3001", Listed())
suite.check("words for how long ago", AG.Ago(clock - 60) == "1 minute" and AG.Ago(clock - 3 * 3600) == "3 hours"
    and AG.Ago(clock - 86400) == "1 day")

-- 6.
_G.BlackthornesTS = nil
AG.list, AG.ids = nil, nil
suite.check("without Tradeskills it is off", not AG:On() and AG:Source(3001) == nil and not Find.AuctionOn())

suite.done()
