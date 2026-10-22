-- Gear limited to some classes (a player's report, 2026-10-22: a druid was
-- told a Hunter-only purple was an upgrade). The data's class mask, or the
-- item's own "Classes:" tooltip line for gear the data does not know, keeps
-- it from ever being an upgrade for another class, here or for an alt.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("classonly")

local ARMOR, LEATHER = 4, 2
local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n, ITEM_MOD_STAMINA_SHORT = n } end

local ITEMS = {
    -- Hunter-only shoulders, in Classic's data.
    ["item:16848"] = { loc = "INVTYPE_SHOULDER", class = ARMOR, subclass = LEATHER, stats = Agi(12) },
    -- Shoulders anyone may wear.
    ["item:900001"] = { loc = "INVTYPE_SHOULDER", class = ARMOR, subclass = LEATHER, stats = Agi(10) },
    -- Forever's own: no data row, the tooltip names its classes.
    ["item:900002"] = { loc = "INVTYPE_SHOULDER", class = ARMOR, subclass = LEATHER, stats = Agi(14) },
    ["item:900003"] = { loc = "INVTYPE_SHOULDER", class = ARMOR, subclass = LEATHER, stats = Agi(14) },
    -- Forever changed this one to druids only.
    ["item:900004"] = { loc = "INVTYPE_SHOULDER", class = ARMOR, subclass = LEATHER, stats = Agi(14) },
}

local ns = env.Load()
_G.UnitClass = function() return "Druid", "DRUID" end
env.InstallItems(ITEMS, {}, {})
_G.UnitLevel = function() return 60 end

ns.Sources.ITEMS[16848] = { 60, 66, 4, 0, 0 }
ns.Sources.ITEMS[900004] = { 60, 66, 4, 0, 0 }
ns.ForeverItems = ns.ForeverItems or {}
ns.ForeverItems[900004] = { 60, 66, 1024, 0, 0 }

local TIPS = {
    [900002] = { "Giant Shoulders", "Shoulder", "Classes: Hunter, Rogue" },
    [900003] = { "Grove Shoulders", "Shoulder", "Classes: Druid" },
}
_G.C_TooltipInfo = {
    GetItemByID = function(id)
        local lines = {}
        for _, text in ipairs(TIPS[id] or { "Plain", "Shoulder" }) do lines[#lines + 1] = { leftText = text } end
        return { lines = lines }
    end,
}

local Compare = ns.Compare
local function Verdict(link) local r = Compare:Judge(link); return r and r.verdict end

suite.check("hunter-only gear is not for a druid", Verdict("item:16848") == "cantuse", Verdict("item:16848"))
suite.check("its tooltip line says so", Compare:Describe(Compare:Judge("item:16848")) ~= nil)
suite.check("no bag arrow on it", Compare:IsUpgrade("item:16848") == false)
suite.check("gear for everyone still is an upgrade", Verdict("item:900001") == "upgrade", Verdict("item:900001"))
suite.check("a tooltip naming other classes keeps it out", Verdict("item:900002") == "cantuse", Verdict("item:900002"))
suite.check("a tooltip naming druids lets it in", Verdict("item:900003") == "upgrade", Verdict("item:900003"))
suite.check("Forever's own classes win over Classic's", Verdict("item:900004") == "upgrade", Verdict("item:900004"))
suite.check("the finder leaves it out too", ns.Finder.Wearable("DRUID", 16848) == false)
suite.check("and keeps gear for everyone", ns.Finder.Wearable("DRUID", 900001) == true)

_G.UnitClass = function() return "Hunter", "HUNTER" end
suite.check("the hunter it's for still gets it", Verdict("item:16848") == "upgrade", Verdict("item:16848"))
suite.check("a hunter is named on the tooltip", Verdict("item:900002") == "upgrade", Verdict("item:900002"))
suite.check("druid-only gear is not for a hunter", Verdict("item:900003") == "cantuse", Verdict("item:900003"))

-- An alt is never offered gear its class can't wear.
local note = { class = "DRUID", level = 60, worn = { [1] = "item:900001" } }
suite.check("no alt upgrade for a druid", ns.Alts:Judge(note, "item:16848") == nil)
suite.check("an alt druid still gets gear for everyone", ns.Alts:Judge(note, "item:900001") ~= nil)

suite.done()
