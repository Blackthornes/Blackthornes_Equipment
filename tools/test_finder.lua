-- The upgrade finder: gear from vendors, quests and dungeons that beats what
-- is worn, and only what this character can go and get now.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("finder")

local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end
local function Chest(n, extra)
    local item = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = Agi(n) }
    for k, v in pairs(extra or {}) do item[k] = v end
    return item
end

local ITEMS = {
    ["item:900"] = Chest(10),                                   -- worn
    ["item:1001"] = Chest(15),
    ["item:1002"] = Chest(20),
    ["item:1003"] = Chest(30),
    ["item:1004"] = Chest(40),
    ["item:1005"] = { loc = "INVTYPE_FEET", class = 4, subclass = 2, stats = Agi(5) },
    ["item:1006"] = { loc = "INVTYPE_FEET", class = 4, subclass = 2, stats = Agi(50) },
    ["item:1007"] = Chest(35),
    ["item:1008"] = Chest(60, { subclass = 4 }),                -- plate
    ["item:1009"] = Chest(8),
    ["item:1010"] = Chest(45),
    ["item:1011"] = { loc = "INVTYPE_HEAD", class = 4, subclass = 2, stats = Agi(5) },
    ["item:1012"] = Chest(25),
}

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitRace = function() return "Human", "Human", 1 end
env.InstallItems(ITEMS, { [5] = "item:900" }, {}, 20)

local done = { [13] = true }
_G.C_QuestLog = { IsQuestFlaggedCompleted = function(id) return done[id] or false end }

local S = ns.Sources
-- Crafted gear and random rolls have suites of their own.
ns.Crafts.ITEMS = {}
ns.RollData.ITEMS = {}
S.ZONES = { [12] = "Elwynn Forest", [14] = "Durotar" }
S.NPCS = {
    [1] = { "Corina Steele", 12, 41.5, 65.9, "A" },
    [2] = { "Horde Smith", 14, 50, 50, "H" },
}
S.QUESTS = {
    [10] = { "Wolves of the Forest", 15, 18, 77, 0, "Marshal Dughan", 12, 42.1, 65.9, "Prowlers", "group" },
    [11] = { "Too Soon", 25, 28, 0, 0, "Someone", 12, 40, 40, "" },
    [12] = { "For the Horde", 15, 18, 178, 0, "Thrall", 14, 30, 30, "" },
    [13] = { "Already Done", 15, 18, 0, 0, "Someone", 12, 40, 40, "" },
    [14] = { "Mages Only", 15, 18, 0, 128, "Someone", 12, 40, 40, "" },
    [15] = { "A Strange Note", 15, 18, 0, 0, "Strange Note", 0, 0, 0, "" },
}
S.DUNGEONS = {
    ["36"] = { "The Deadmines", 17, 26, "Westfall", "" },
    ["34"] = { "The Stockade", 24, 32, "Stormwind City", "A" },
}
S.BOSSES = {
    [100] = { "Edwin VanCleef", "36", 21 },
    [101] = { "Bazil Thredd", "34", 29 },
}
S.ITEMS = {
    [1001] = { 15, 18, 0, 0, 12050, v = { 1, 0 } },
    [1002] = { 15, 18, 0, 0, 300, v = { 2, 0 } },
    [1003] = { 15, 18, 0, 0, 0, q = { 10 } },
    [1004] = { 15, 18, 0, 0, 0, q = { 11 } },
    [1005] = { 15, 20, 0, 0, 0, d = { 100, 20 } },
    [1006] = { 15, 25, 0, 0, 0, d = { 101, 12.5 } },
    [1007] = { 15, 18, 0, 0, 0, q = { 13 } },
    [1008] = { 15, 18, 0, 0, 0, q = { 10 } },
    [1009] = { 15, 18, 0, 0, 40, v = { 1, 3 } },
    [1010] = { 25, 30, 0, 0, 0, q = { 10 } },
    [1011] = { 0, 3, 0, 0, 0, q = { 10 } },
    [1012] = { 15, 18, 0, 0, 0, q = { 14 } },
}

local Finder = ns.Finder

--- The item IDs offered for a slot, best first.
local function Offered(found, slot)
    local ids = {}
    for _, pick in ipairs(found.slots[slot] or {}) do ids[#ids + 1] = pick.itemID end
    return table.concat(ids, ",")
end

local found = Finder:Scan()
suite.check("it scans", found ~= nil)
suite.check("the best chest first: quest, then own faction's vendor", Offered(found, 5) == "1003,1001",
    Offered(found, 5))
suite.check("a dungeon open at your level fills an empty slot", Offered(found, 8) == "1005",
    Offered(found, 8))
suite.check("nothing for slots with nothing better", found.slots[1] == nil)
suite.check("three in all", found.count == 3, found.count)

-- Each reason something is left out, one by one.
local player = Finder:Player()
suite.check("the player reads as an Alliance human hunter",
    player.faction == "A" and player.raceBit == 1 and player.classBit == 4 and player.level == 20)
local function Kinds(itemID)
    local kinds = {}
    for _, source in ipairs(Finder:SourcesFor(itemID, player)) do kinds[#kinds + 1] = source.kind end
    return table.concat(kinds, ",")
end
suite.check("the other faction's vendor is left out", Kinds(1002) == "", Kinds(1002))
suite.check("a quest above your level is left out", Kinds(1004) == "")
suite.check("a dungeon above your level is left out", Kinds(1006) == "")
suite.check("a quest you turned in is left out", Kinds(1007) == "")
suite.check("an item above your level is left out", Kinds(1010) == "")
suite.check("another class's quest is left out", Kinds(1012) == "")
suite.check("gear your class can't wear is never offered", not Offered(found, 5):find("1008"))
suite.check("a downgrade is never offered", not Offered(found, 5):find("1009"))
suite.check("gear far below your level is not looked at", found.slots[1] == nil)

-- How sources read.
local vendor = Finder:SourcesFor(1001, player)[1]
suite.check("a vendor says who, where and how much",
    Finder:Describe(vendor) == "Corina Steele, Elwynn Forest (41.5, 65.9)  |cffffd7001g|r |cffc7c7cf20s|r |cffeda55f50c|r",
    Finder:Describe(vendor))
local limited = Finder:SourcesFor(1009, player)[1]
suite.check("limited stock says so", Finder:Describe(limited):find("(limited stock)", 1, true) ~= nil)
local quest = Finder:SourcesFor(1003, player)[1]
suite.check("a quest says its level, that it is for a group, and who gives it",
    Finder:Describe(quest) == "Wolves of the Forest (level 18), group, after Prowlers, from Marshal Dughan in Elwynn Forest (42.1, 65.9)",
    Finder:Describe(quest))
suite.check("and the quest before it", quest.after == "Prowlers")
S.ITEMS[1011] = { 0, 18, 0, 0, 0, q = { 15 } }
local note = Finder:SourcesFor(1011, player)[1]
suite.check("a quest from an item says so", Finder:Describe(note) == "A Strange Note (level 18), starts from Strange Note",
    Finder:Describe(note))
S.ITEMS[1011] = { 0, 3, 0, 0, 0, q = { 10 } }
local drop = Finder:SourcesFor(1005, player)[1]
suite.check("a drop says the boss, dungeon, levels and chance",
    Finder:Describe(drop) == "Edwin VanCleef in The Deadmines (17-26), 20% drop", Finder:Describe(drop))
suite.check("money skips empty coins", Finder.Money(10003) == "|cffffd7001g|r |cffeda55f3c|r")
suite.check("no price, no money", Finder.Money(0) == nil)

-- Reputation gear: offered once the standing is reached, and before then
-- shown as waiting on it.
local standing = {}
_G.C_Reputation = { GetFactionDataByID = function(id)
    if standing[id] then return { name = "Warsong Outriders", reaction = standing[id] } end
end }
S.FACTIONS = { [889] = "Warsong Outriders" }
S.ITEMS[1013] = { 15, 18, 0, 0, 500, v = { 1, 0 }, r = { 889, 5 } }
ITEMS["item:1013"] = Chest(50)
suite.check("never met the faction: it says what is needed",
    Finder:Needs(1013).standing == "Honored" and Finder:Needs(1013).faction == "Warsong Outriders"
    and Finder:Needs(1013).have == nil)
standing[889] = 5
suite.check("Friendly is not enough, and says so", Finder.NeedsText(Finder:Needs(1013))
    == "Needs Honored with Warsong Outriders (you are Friendly)", Finder.NeedsText(Finder:Needs(1013)))
local waits = Finder:Scan()
suite.check("gear waiting on a reputation comes after what can be had now",
    Offered(waits, 5) == "1003,1001,1013", Offered(waits, 5))
standing[889] = 6
suite.check("Honored is enough", Finder:Needs(1013) == nil)
suite.check("and then it is the best chest", Offered(Finder:Scan(), 5):sub(1, 4) == "1013")
S.ITEMS[1013], ITEMS["item:1013"], _G.C_Reputation = nil, nil, nil

-- Raids.
S.DUNGEONS["409"] = { "Molten Core", 60, 60, "Blackrock Mountain", "", true }
S.BOSSES[102] = { "Ragnaros", "409", 63 }
S.ITEMS[1014] = { 0, 18, 0, 0, 0, d = { 102, 22.2 } }
suite.check("a raid is shut below 60", Kinds(1014) == "")
local sixty = Finder:Player()
sixty.level = 60
local raid = Finder:SourcesFor(1014, sixty)[1]
suite.check("and open at 60", raid and raid.raid == true)
suite.check("a raid drop reads as one", Finder:Describe(raid) == "Ragnaros in Molten Core, 22.2% drop"
    and Finder.Label(raid) == "Raid", Finder:Describe(raid))
S.ITEMS[1014] = nil

-- Drops seen on Forever (Farmer's loot records).
S.FOREVER = {
    [1005] = { { "Edwin VanCleef", "36", 35 } },
    [1015] = { { "Captain Greenskin", "36", 0 } },
    [1016] = { { "Ragnaros", "409", 0 } },
}
ITEMS["item:1015"] = { loc = "INVTYPE_HEAD", class = 4, subclass = 2, stats = Agi(9) }
local confirmed = Finder:SourcesFor(1005, player)
suite.check("a Classic drop seen on Forever is marked, with Forever's rate",
    #confirmed == 1 and confirmed[1].forever and confirmed[1].chance == 35)
local new = Finder:SourcesFor(1015, player)[1]
suite.check("gear Classic never had at that boss is added", new and new.forever and new.chance == nil)
suite.check("without a rate when too few were counted",
    Finder:Describe(new) == "Captain Greenskin in The Deadmines (17-26)", Finder:Describe(new))
suite.check("a Forever raid drop still waits for 60", #Finder:SourcesFor(1016, player) == 0)
suite.check("and Forever-only gear is offered", Offered(Finder:Scan(), 1) == "1015", Offered(Finder:Scan(), 1))
suite.check("tagged [Forever] in the window", ns.FinderUI.SourceLine(new):find("[Forever]", 1, true) ~= nil)
S.FOREVER, ITEMS["item:1015"] = {}, nil

-- Somewhere in your own zone comes first.
S.ITEMS[1001].q = { 10 }
_G.GetRealZoneText = function() return "Elwynn Forest" end
player = Finder:Player()
suite.check("a vendor comes before a quest elsewhere", Kinds(1001) == "vendor,quest", Kinds(1001))
S.NPCS[1][2] = 14
player = Finder:Player()
suite.check("but not when the quest is here and the vendor is not", Kinds(1001) == "quest,vendor", Kinds(1001))
S.NPCS[1][2] = 12
S.ITEMS[1001].q = nil
_G.GetRealZoneText = nil
player = Finder:Player()

-- Only one kind of source.
suite.check("vendors only", Offered(Finder:Scan("vendor"), 5) == "1001")
suite.check("dungeons only", Finder:Scan("dungeon").count == 1)

-- The other faction sees the other faction's vendor and quests.
_G.UnitFactionGroup = function() return "Horde", "Horde" end
_G.UnitRace = function() return "Orc", "Orc", 2 end
local horde = Finder:Scan()
suite.check("the Horde gets the Horde vendor, not the Alliance quest", Offered(horde, 5) == "1002",
    Offered(horde, 5))
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitRace = function() return "Human", "Human", 1 end

-- Gear the client has not seen yet is asked about, then judged.
local asked = {}
local cached = { [1003] = false }
C_Item.IsItemDataCachedByID = function(id) if cached[id] == false then return false end return true end
C_Item.RequestLoadItemDataByID = function(id) asked[#asked + 1] = id end
local waiting = Finder:Scan()
suite.check("an item the client has not seen is waited on", waiting.waiting == 1, waiting.waiting)
suite.check("and asked about", asked[1] == 1003)
suite.check("and not offered yet", Offered(waiting, 5) == "1001")
cached[1003] = nil
suite.check("once it arrives it is offered", Offered(Finder:Scan(), 5) == "1003,1001")

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

local UI = ns.FinderUI
UI:Show()
suite.check("it opens", UI.frame:IsShown())
suite.check("the header names the spec and level", UI.specLabel:GetText() == "Beast Mastery, level 20",
    UI.specLabel:GetText())
suite.check("a row for each upgrade", UI.rows[1]:IsShown() and UI.rows[3]:IsShown() and not UI.rows[4]:IsShown())
suite.check("chest first, in character sheet order", UI.rows[1].slot:GetText() == "Chest")
suite.check("its second pick leaves the slot blank", UI.rows[2].slot:GetText() == "")
suite.check("the gain shows", UI.rows[1].gain:GetText() == "+200%", UI.rows[1].gain:GetText())
suite.check("an empty slot says so", UI.rows[3].gain:GetText() == "empty slot")
suite.check("the source line names the quest", UI.rows[1].source:GetText():find("Wolves of the Forest", 1, true) ~= nil,
    UI.rows[1].source:GetText())
suite.check("the footer counts them", UI.footer:GetText() == "3 upgrades you can go and get now.",
    UI.footer:GetText())

-- Hovering shows the item and every place to get it.
local shown
GameTooltip.SetHyperlink = function(_, link) shown = link end
UI.rows[1]:GetScript("OnEnter")(UI.rows[1])
suite.check("hovering shows the item", shown == "item:1003", shown)
local lines = table.concat(GameTooltip._lines, "\n")
suite.check("and where to get it", lines:find("Where to get it", 1, true) and lines:find("Marshal Dughan", 1, true),
    lines)
suite.check("and the quest before it", lines:find("after Prowlers", 1, true) ~= nil)

-- Filters.
UI:SetFilter("dungeon")
suite.check("the filter is remembered", ns.db.finderShow == "dungeon")
suite.check("dungeons only shows the drop", UI.rows[1].slot:GetText() == "Feet" and not UI.rows[2]:IsShown())
UI:SetFilter("vendor")
suite.check("vendors only shows the vendor's chest", UI.rows[1].pick.itemID == 1001)
UI:SetFilter(nil)
suite.check("everything again", ns.db.finderShow == "all" and UI.rows[3]:IsShown())

-- Nothing to offer.
env.worn[5] = "item:1003"
env.worn[8] = "item:1006"
UI:SetFilter("quest")
suite.check("an empty list says why", UI.empty:GetText() == "No quest open to you gives anything better than what you wear.",
    UI.empty:GetText())
UI:SetFilter(nil)
env.worn[5], env.worn[8] = "item:900", nil

-- Long source lines are cut to fit, never run past the edge.
local fitted = UI.Fit("tiny", ("x"):rep(200), 120)
suite.check("a long line is cut", fitted:sub(-3) == "..." and #fitted * 6 <= 120, fitted)
suite.check("a short line is left alone", UI.Fit("tiny", "short", 120) == "short")

-- Many upgrades scroll.
local LOCS = { "INVTYPE_HEAD", "INVTYPE_NECK", "INVTYPE_SHOULDER", "INVTYPE_CLOAK",
    "INVTYPE_WRIST", "INVTYPE_HAND", "INVTYPE_WAIST", "INVTYPE_LEGS" }
for i = 1, 14 do
    local id = 2000 + i
    local loc = LOCS[(i - 1) % #LOCS + 1]
    ITEMS["item:" .. id] = { loc = loc, class = 4, subclass = 0, stats = Agi(i) }
    S.ITEMS[id] = { 15, 18, 0, 0, 10, v = { 1, 0 } }
end
UI:Refresh()
suite.check("more than fits shows a scroll thumb", UI.thumb:IsShown())
local before = UI.rows[1].pick.itemID
UI.frame:GetScript("OnMouseWheel")(UI.frame, -1)
suite.check("the wheel scrolls", UI.offset == 1 and UI.rows[1].pick.itemID ~= before)
UI.frame:GetScript("OnMouseWheel")(UI.frame, 50)
suite.check("never past the top", UI.offset == 0)

-- /beq find toggles it.
ns.HandleSlash("find")
suite.check("/beq find closes it", not UI.frame:IsShown())
ns.HandleSlash("find")
suite.check("and opens it", UI.frame:IsShown())

-- The gear window has a button for it.
ns.UI:Show()
suite.check("the gear window has a Find upgrades button", ns.UI.findButton ~= nil)

suite.done()
