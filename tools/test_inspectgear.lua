-- Another Player's Gear (UI/InspectGear.lua, the owner said build it
-- 2026-11-26).
--
-- What must hold:
--   1. Off unless ticked: nothing shows when the inspect window opens.
--   2. Ticked, inspecting a player of your class lists what they wear that
--      beats yours and that you can get, biggest gain first, with green
--      arrows on those slots of the inspect window.
--   3. Forever sends item IDs first and links a moment later: the gear is
--      read again until the links are in.
--   4. Another class, or a piece you can't get, is left out.
--   5. The window and arrows go when the inspect window shuts; nothing
--      about the other player is kept.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("inspectgear")

local ARMOR, LEATHER = 4, 2
local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end
local function Piece(loc, n) return { loc = loc, class = ARMOR, subclass = LEATHER, stats = Agi(n), bind = 0 } end

local ITEMS = {
    ["item:800"] = Piece("INVTYPE_HEAD", 5),     -- your head
    ["item:900"] = Piece("INVTYPE_CHEST", 10),   -- your chest
    ["item:1101"] = Piece("INVTYPE_HEAD", 12),   -- their head: an upgrade you can get
    ["item:1002"] = Piece("INVTYPE_CHEST", 11),  -- their chest: a small upgrade you can get
    ["item:1201"] = Piece("INVTYPE_LEGS", 6),    -- their legs: no source for you
    ["item:1301"] = Piece("INVTYPE_FEET", 2),    -- their feet: an upgrade (your feet are empty)
}

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitRace = function() return "Human", "Human", 1 end
env.InstallItems(ITEMS, { [1] = "item:800", [5] = "item:900" }, {}, 20)

local S = ns.Sources
ns.Crafts.ITEMS = {}
ns.RollData.ITEMS = {}
S.ZONES = { [12] = "Elwynn Forest" }
S.NPCS = { [1] = { "Corina Steele", 12, 41.5, 65.9, "A" } }
S.QUESTS, S.DUNGEONS, S.BOSSES, S.FOREVER = {}, {}, {}, {}
S.ITEMS = {}
for _, id in ipairs({ 1101, 1002, 1301 }) do
    S.ITEMS[id] = { 15, 15, 0, 0, 100, v = { 1, 0 } }
end

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end

local Inspect = ns.InspectGear
suite.check("the module loads from the TOC", Inspect ~= nil)

-- The game's inspect window, made by its load-on-demand addon.
local inspect = env.Stub({ unit = "target" })
_G.InspectFrame = inspect
for slot, name in pairs(Inspect.BUTTONS) do
    _G[name] = env.Stub({ _id = slot })
end
local function Fire(event, ...) ns.eventFrame:GetScript("OnEvent")(ns.eventFrame, event, ...) end
Fire("ADDON_LOADED", "Blizzard_InspectUI")
suite.check("it hooks the inspect window once it is made", Inspect.hooked == true)

-- The other player: links arrive only once `ready` is set.
local theirs = { [1] = "item:1101", [5] = "item:1002", [7] = "item:1201", [8] = "item:1301" }
local ready = false
local wornLink = _G.GetInventoryItemLink
_G.GetInventoryItemLink = function(unit, slot)
    if unit == "target" then return ready and theirs[slot] or nil end
    return wornLink(unit, slot)
end
_G.GetInventoryItemID = function(unit, slot)
    if unit ~= "target" or not theirs[slot] then return nil end
    return tonumber(theirs[slot]:match("item:(%d+)"))
end
local targetClass = "HUNTER"
_G.UnitClass = function(unit)
    if unit == "target" then return "Hunter", targetClass, 3 end
    return "Hunter", "HUNTER", 3
end
_G.UnitIsPlayer = function(unit) return unit == "target" end
local oldGUID = _G.UnitGUID
_G.UnitGUID = function(unit) return unit == "target" and "Player-1-ABC" or "Player-1-ME" end
_G.GetUnitName = function() return "Thokka Stonehide" end
local timers = {}
_G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function RunTimers()
    local list = timers
    timers = {}
    for _, fn in ipairs(list) do fn() end
end

ns.Finder:Scan()

-- 1.
inspect:Show()
inspect:GetScript("OnShow")(inspect)
suite.check("off unless ticked", ns.DEFAULTS.otherPlayersGear == false
    and not (Inspect.frame and Inspect.frame:IsShown()))

-- 2 and 3.
ns.db.otherPlayersGear = true
inspect:GetScript("OnShow")(inspect)
suite.check("before the server answers nothing shows", not (Inspect.frame and Inspect.frame:IsShown()))
Fire("INSPECT_READY", "Player-1-ABC")
suite.check("at the answer the IDs are in but not the links, so it reads again", Inspect.pending == true)
ready = true
RunTimers()
local frame = Inspect.frame
suite.check("the window shows once the links are in", frame and frame:IsShown())
suite.check("titled with their name", Inspect.title:GetText() == "Thokka Stonehide wears", Inspect.title:GetText())
local rows = {}
for _, row in ipairs(Inspect.rows) do
    local piece = rawget(row, "piece")
    if row:IsShown() and piece then rows[#rows + 1] = piece.itemID end
end
suite.check("three pieces beat yours and can be had", #rows == 3, table.concat(rows, ","))
suite.check("the empty slot first, then the biggest gain", rows[1] == 1301 and rows[2] == 1101 and rows[3] == 1002,
    table.concat(rows, ","))
suite.check("the heading counts them", Inspect.heading:GetText() == "3 PIECES WOULD BE UPGRADES FOR YOU",
    Inspect.heading:GetText())
suite.check("each row says where to get it", Inspect.rows[2].under:GetText():find("Corina Steele", 1, true) ~= nil,
    Inspect.rows[2].under:GetText())
suite.check("and how much better", Inspect.rows[2].gain:GetText() == "+140%", Inspect.rows[2].gain:GetText())
suite.check("with a Track button", Inspect.rows[1].track.label:GetText() == "Track")
suite.check("their gear rating beside yours", (Inspect.foot:GetText() or ""):find("^Their gear rating: %a+%. Yours: %a+%.$") ~= nil,
    Inspect.foot:GetText())
local arrows = ns.BagIcons
suite.check("a green arrow on their head slot", arrows:ExistingArrow(_G.InspectHeadSlot)
    and arrows:ExistingArrow(_G.InspectHeadSlot):IsShown())
suite.check("none on their legs, which you can't get", not (arrows:ExistingArrow(_G.InspectLegsSlot)
    and arrows:ExistingArrow(_G.InspectLegsSlot):IsShown()))
suite.check("no more reading once every link is in", not Inspect.pending)

local followed
local follow = ns.FinderUI.Follow
ns.FinderUI.Follow = function(_, pick) followed = pick end
Inspect.rows[2].track:GetScript("OnClick")(Inspect.rows[2].track)
ns.FinderUI.Follow = follow
suite.check("Track follows the piece", followed and followed.itemID == 1101, followed and followed.itemID)

-- 4.
targetClass = "MAGE"
inspect:GetScript("OnShow")(inspect)
suite.check("another class shows nothing", not frame:IsShown())

-- 5.
targetClass = "HUNTER"
inspect:GetScript("OnShow")(inspect)
suite.check("your class again shows it", frame:IsShown())
inspect:Hide()
inspect:GetScript("OnHide")(inspect)
suite.check("shutting the inspect window takes it down", not frame:IsShown()
    and not arrows:ExistingArrow(_G.InspectHeadSlot):IsShown())
suite.check("and keeps nothing about them", Inspect.guid == nil and Inspect.unit == nil
    and ns.db.inspected == nil)
local saved = 0
for key in pairs(ns.db) do if tostring(key):find("nspect") then saved = saved + 1 end end
suite.check("no saved key about inspecting", saved == 0, saved)

-- Unticking takes it down too.
inspect:Show()
inspect:GetScript("OnShow")(inspect)
ns.db.otherPlayersGear = false
Inspect:Changed()
suite.check("unticking takes it down", not frame:IsShown())

_G.UnitGUID = oldGUID
suite.done()
