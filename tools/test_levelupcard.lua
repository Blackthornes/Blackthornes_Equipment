-- The Level Up card (UI/LevelUpCard.lua, the owner said build it from the
-- mockup, 2026-11-26).
--
-- What must hold:
--   1. A level up shows one card: the level, bag upgrades with Put It On,
--      the new upgrades that level opened with the best named, and the
--      spells to train. Only lines with something to say show.
--   2. Once per level: the same level never shows it again, after a
--      reload too.
--   3. In a fight it waits, and shows when the fight ends.
--   4. Its switch, Level Up Card:, keeps it away.
--   5. A click anywhere else puts it away; Show Me opens Find Upgrades.
--   6. A heavier armor opening is said at the top; nothing new, no card.
--   7. It plays no sound and joins the top shelf until dragged.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("levelupcard")

local ARMOR, LEATHER = 4, 2
local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end
local function Piece(loc, n, level)
    return { loc = loc, class = ARMOR, subclass = LEATHER, stats = Agi(n), bind = 0, minLevel = level }
end

local ITEMS = {
    ["item:800"] = Piece("INVTYPE_HEAD", 5),           -- worn
    ["item:900"] = Piece("INVTYPE_CHEST", 10),         -- worn
    ["item:901"] = Piece("INVTYPE_CHEST", 14),         -- in the bags
    ["item:1101"] = Piece("INVTYPE_HEAD", 7, 15),      -- an upgrade from before
    ["item:1401"] = Piece("INVTYPE_HEAD", 12, 21),     -- opens at 21
    ["item:1402"] = Piece("INVTYPE_LEGS", 6, 21),      -- opens at 21
}

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitRace = function() return "Human", "Human", 1 end
env.InstallItems(ITEMS, { [1] = "item:800", [5] = "item:900" }, { [0] = { "item:901" } }, 20)

local S = ns.Sources
ns.Crafts.ITEMS = {}
ns.RollData.ITEMS = {}
S.ZONES = { [12] = "Elwynn Forest" }
S.NPCS = { [1] = { "Corina Steele", 12, 41.5, 65.9, "A" } }
S.QUESTS, S.DUNGEONS, S.BOSSES, S.FOREVER = {}, {}, {}, {}
S.ITEMS = {
    [1101] = { 15, 15, 0, 0, 100, v = { 1, 0 } },
    [1401] = { 21, 21, 0, 0, 100, v = { 1, 0 } },
    [1402] = { 21, 21, 0, 0, 100, v = { 1, 0 } },
}

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end

local Card, Finder, Gear = ns.LevelUpCard, ns.Finder, ns.GearWindow
local function Fire(event, ...) ns.eventFrame._scripts.OnEvent(ns.eventFrame, event, ...) end
local function Click(frame, ...) frame:GetScript("OnClick")(frame, ...) end
local sounds = 0
_G.PlaySound = function() sounds = sounds + 1 end
_G.PlaySoundFile = function() sounds = sounds + 1 end
ns.db.effectsLevel = "off"

local level = 20
local function LevelTo(n)
    level = n
    _G.UnitLevel = function() return level end
    Finder:MarkStale()
    Fire("PLAYER_LEVEL_UP", n)
end
local function Lines()
    local out = {}
    for _, row in ipairs(Card.rows or {}) do
        if row:IsShown() then out[#out + 1] = row.line:GetText() end
    end
    return out
end

suite.check("on unless switched off", Card:IsOn() and ns.db.levelUpCard == true)
suite.check("nothing shows at login", not (Card.frame and Card.frame:IsShown()))

-- 1.
LevelTo(21)
local frame = Card.frame
suite.check("a level up shows the card", frame and frame:IsShown())
suite.check("with its heading and level", Card.kicker:GetText() == "LEVEL UP" and Card.title:GetText() == "Level 21",
    Card.title and Card.title:GetText())
suite.check("no armor line for a hunter at 21", not Card.armor:IsShown())
local lines = Lines()
suite.check("the bag upgrade comes first", lines[1] == "1 upgrade in your bags.", lines[1])
suite.check("with Put It On", Card.rows[1].button.label:GetText() == "Put It On")
suite.check("then the upgrades the level opened", lines[2] == "2 new upgrades to go and get.", lines[2])
suite.check("the best is named, an empty slot first", Card.rows[2].under:IsShown()
    and Card.rows[2].under:GetText():find("Best: ", 1, true) == 1
    and Card.rows[2].under:GetText():find("item:1402", 1, true) ~= nil, Card.rows[2].under:GetText())
suite.check("an upgrade from an earlier level is not new", Card.read.new == 2, Card.read.new)
suite.check("numbered in order", Card.rows[1].number:GetText() == "1" and Card.rows[2].number:GetText() == "2")
suite.check("the trainer line shows only with spells to train", (Card.read.training ~= nil) == (#lines == 3), #lines)
suite.check("no sound", sounds == 0, sounds)

-- 2.
Card:Hide()
suite.check("the level counts as seen", ns.charDB.levelUpCardShown == 21)
Card.level = 20
LevelTo(21)
suite.check("the same level never shows it twice", not frame:IsShown())

-- 3.
_G.InCombatLockdown = function() return true end
LevelTo(22)
suite.check("in a fight it waits", not frame:IsShown() and Card.pending ~= nil)
_G.InCombatLockdown = function() return false end
Fire("PLAYER_REGEN_ENABLED")
suite.check("and shows when the fight ends", frame:IsShown() and Card.title:GetText() == "Level 22",
    Card.title:GetText())
suite.check("levels 21 to 22 count, so nothing new opened", Card.read.new == 0 and #Lines() >= 1, Card.read.new)

-- 5.
local over = false
frame.IsMouseOver = function() return over end
over = true
frame:GetScript("OnEvent")(frame, "GLOBAL_MOUSE_DOWN")
suite.check("a click on the card keeps it", frame:IsShown())
over = false
frame:GetScript("OnEvent")(frame, "GLOBAL_MOUSE_DOWN")
suite.check("a click anywhere else puts it away", not frame:IsShown())

-- 4.
ns.db.levelUpCard = false
LevelTo(23)
suite.check("switched off, no card", not frame:IsShown() and Card.pending == nil)
ns.db.levelUpCard = true

-- 6.
suite.check("plate opens at 40 for a warrior", Card.ArmorOpened("WARRIOR", 39, 40) == "Plate")
suite.check("mail at 40 for a hunter", Card.ArmorOpened("HUNTER", 38, 40) == "Mail")
suite.check("nothing at other levels", Card.ArmorOpened("WARRIOR", 40, 41) == nil
    and Card.ArmorOpened("MAGE", 39, 40) == nil)
suite.check("said mid-sentence in small letters", Card.ArmorWord("Plate") == "plate")
do
    local realRead = ns.MyGear.Read
    ns.MyGear.Read = function() return { ready = {} } end
    suite.check("nothing new, no card", Card.Read({ all = {}, player = { level = 30, class = "MAGE" } }, 29, 30) == nil)
    ns.MyGear.Read = realRead
end
Card:Show({ level = 40, armor = "Plate", ready = {}, new = 0 })
suite.check("the armor line reads plainly", Card.armor:IsShown() and Card.armor:GetText() == "You can wear plate now.",
    Card.armor:GetText())
suite.check("a card with no lines below has none", #Lines() == 0)
Card:Hide()

-- Show Me.
Card:Show({ level = 41, ready = {}, new = 1, best = { link = "item:1401", result = { percent = 20 } } })
suite.check("one new upgrade reads in the singular", Lines()[1] == "1 new upgrade to go and get.", Lines()[1])
Click(Card.rows[1].button)
suite.check("Show Me opens Find Upgrades", Gear.frame:IsShown() and Gear.tab == "find" and not frame:IsShown(), Gear.tab)

-- 7.
suite.check("not dragged, it joins the top shelf", not Card:Dragged()
    and _G.BlackthornesShelves.pieces["upgrade.levelup"] ~= nil)

suite.done()
