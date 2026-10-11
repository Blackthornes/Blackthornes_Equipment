-- The player's other characters: each keeps a note of its class, level,
-- spec and worn gear, and bag gear that is no upgrade here is judged for
-- them (Alts:BestFor), so Butler can offer it as a mail (Butler:Advise's
-- `alt`).

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("alts")

local ARMOR = 4
local LEATHER, MAIL = 2, 3

local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end

local ITEMS = {
    -- The hunter's worn chest.
    ["item:1"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = LEATHER, stats = Agi(10) },
    -- The rogue's worn chest.
    ["item:11"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = LEATHER, stats = Agi(2) },
    -- Worse than the hunter's, twice the rogue's.
    ["item:4"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = LEATHER, stats = Agi(4) },
    -- Mail: no rogue wears it.
    ["item:5"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = MAIL, stats = Agi(6) },
    -- Better for the hunter too.
    ["item:6"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = LEATHER, stats = Agi(20) },
    -- For the rogue from level 30.
    ["item:7"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = LEATHER, stats = Agi(8), minLevel = 30 },
}

local ns = env.Load()
_G.UnitClass = function() return "HUNTER", "HUNTER" end
_G.UnitGUID = function() return "Player-1" end
_G.GetRealmName = function() return "Here" end
_G.UnitFactionGroup = function() return "Horde", "Horde" end
env.InstallItems(ITEMS, { [5] = "item:1" }, { [0] = {
    [4] = "item:4", [5] = "item:5", [6] = "item:6", [7] = "item:7",
} })
_G.C_Container.GetContainerItemInfo = function(bag, slot)
    if bag ~= 0 then return nil end
    return { quality = 1, isBound = false, stackCount = 1 }
end
_G.C_TooltipInfo = { GetHyperlink = function() return { lines = { { type = 11, price = 50 } } } end }
ns.Alts:OnEnable()
local function Fire(event, ...) ns.eventFrame:GetScript("OnEvent")(ns.eventFrame, event, ...) end

local Alts = ns.Alts

-- The character playing keeps its note.
suite.check("the character playing writes its note", Alts:Record() == true)
local mine = ns.db.characterGear["Player-1"]
suite.check("with class, level, realm and side", mine and mine.class == "HUNTER" and mine.level == 20
    and mine.realm == "Here" and mine.faction == "Horde")
suite.check("and what it wears", mine.worn[5] == "item:1" and mine.worn[1] == nil)
suite.check("and the spec it is judged as", mine.spec ~= nil)

-- A burst of events writes it once.
local writes = 0
local record = Alts.Record
Alts.Record = function(self) writes = writes + 1; return record(self) end
local timer = C_Timer.After
local waiting = {}
C_Timer.After = function(_, fn) waiting[#waiting + 1] = fn end
Fire("PLAYER_EQUIPMENT_CHANGED")
Fire("PLAYER_EQUIPMENT_CHANGED")
Fire("PLAYER_LEVEL_UP")
for _, fn in ipairs(waiting) do fn() end
suite.check("a burst of gear events writes the note once", writes == 1, writes)
C_Timer.After = timer
Alts.Record = record

-- A rogue alt on the same realm and side, and two that are not.
ns.db.characterGear["Player-2"] = { class = "ROGUE", level = 20, realm = "Here", faction = "Horde",
    worn = { [5] = "item:11" } }
ns.db.characterGear["Player-3"] = { class = "ROGUE", level = 20, realm = "Here", faction = "Alliance",
    worn = {} }
ns.db.characterGear["Player-4"] = { class = "ROGUE", level = 20, realm = "Elsewhere", faction = "Horde",
    worn = {} }

local Butler = _G.BlackthornesEquipment.Butler
local advice = Butler:Advise("item:4", 0, 4)
suite.check("no upgrade here", advice and advice.upgrade == nil)
suite.check("but an upgrade for the rogue", advice.alt and advice.alt.key == "Player-2",
    advice.alt and advice.alt.key)
suite.check("by 100 percent", advice.alt.gain == 100, advice.alt.gain)
suite.check("to wear now", advice.alt.level == nil)

advice = Butler:Advise("item:5", 0, 5)
suite.check("mail is offered to nobody who cannot wear it", advice and advice.alt == nil)

advice = Butler:Advise("item:6", 0, 6)
suite.check("an upgrade for the character playing names no alt", advice.upgrade == "now" and advice.alt == nil)

advice = Butler:Advise("item:7", 0, 7)
suite.check("one that waits on the alt's level says the level", advice.alt and advice.alt.level == 30)

-- The other side and another realm are never picked, even for an empty slot.
ns.db.characterGear["Player-2"] = nil
suite.check("other realms and sides are left out", Alts:BestFor("item:4") == nil)

-- Its own note never counts.
ns.db.characterGear["Player-5"] = { class = "HUNTER", level = 20, realm = "Here", faction = "Horde",
    worn = { [5] = "item:1" } }
suite.check("a hunter wearing the same is no upgrade", Alts:BestFor("item:4") == nil)
ns.db.characterGear["Player-5"].worn = {}
local best = Alts:BestFor("item:4")
suite.check("an empty slot is, with no percent", best and best.key == "Player-5" and best.gain == nil)
ns.db.characterGear["Player-1"].worn = {}
suite.check("the character playing's own note is never judged", Alts:BestFor("item:4").key == "Player-5")

-- A note the code cannot read is skipped, not an error.
ns.db.characterGear["Player-6"] = { class = "NOBODY" }
ns.db.characterGear["Player-7"] = "garbage"
local ok = pcall(Alts.BestFor, Alts, "item:4")
suite.check("a broken note is skipped", ok)

suite.done()
