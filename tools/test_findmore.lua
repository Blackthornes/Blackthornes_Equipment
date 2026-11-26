-- More in Find Upgrades (the owner said build it from a mockup,
-- 2026-11-26): the Reputation box, gear only a crafter can wear, and the
-- Find box on the Dungeons tab.
--
-- What must hold:
--   1. Reputation starts ticked. Unticked, gear a faction sells leaves
--      the list, a line under it says how many, and "Show them" ticks it
--      again. The old list's filter and the upgrade quest agree.
--   2. Gear only a crafter can wear stays listed and says the skill it
--      needs, in amber while the character lacks it. It is not a quest
--      yet and "Only What I Can Get Now" hides it.
--   3. The Dungeons tab's Find box keeps the drops and quests that match,
--      each under its heading, and says how many show.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("findmore")

local ARMOR, LEATHER = 4, 2
local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end
local function Piece(loc, n)
    return { loc = loc, class = ARMOR, subclass = LEATHER, stats = Agi(n), bind = 0 }
end

local ITEMS = {
    ["item:800"] = Piece("INVTYPE_HEAD", 5),     -- worn
    ["item:900"] = Piece("INVTYPE_CHEST", 10),   -- worn
    ["item:1001"] = Piece("INVTYPE_CHEST", 15),  -- a vendor's
    ["item:1002"] = Piece("INVTYPE_CHEST", 20),  -- a faction's quartermaster's
    ["item:1101"] = Piece("INVTYPE_HEAD", 12),   -- goggles: Engineering 100 to wear
}

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitRace = function() return "Human", "Human", 1 end
env.InstallItems(ITEMS, { [1] = "item:800", [5] = "item:900" }, { [0] = {} }, 20)

local S = ns.Sources
ns.RollData.ITEMS = {}
S.ZONES = { [12] = "Elwynn Forest" }
S.NPCS = { [1] = { "Corina Steele", 12, 41.5, 65.9, "A" }, [2] = { "Quartermaster Test", 12, 40, 60, "A" } }
S.QUESTS, S.DUNGEONS, S.BOSSES, S.FOREVER = {}, {}, {}, {}
S.FACTIONS = { [72] = "Stormwind" }
S.ITEMS = {
    [1001] = { 15, 15, 0, 0, 100, v = { 1, 0 } },
    [1002] = { 15, 15, 0, 0, 100, v = { 2, 0 }, r = { 72, 4 } },
}
-- Goggles an engineer makes and only an engineer of 100 can wear.
ns.Crafts.ITEMS = {
    [1101] = { 202, 90, 3934, 0, 15, 0, 0, 0, m = { 2318, 6 }, w = { 202, 100 } },
}
ns.Crafts.PROFESSIONS = { [202] = "Engineering" }
local skill = 80
ns.Crafting.Professions = function() return { [202] = skill } end
ns.Crafting.Knows = function() return true end

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end

local Gear, Find, Finder, FinderUI = ns.GearWindow, ns.FindUpgrades, ns.Finder, ns.FinderUI
local Quest = ns.UpgradeQuest
Quest.Zone = function() return "Elwynn Forest" end
-- The standing is reached: the quartermaster's gear needs nothing more.
Finder.Standing = function() return 8, "Stormwind" end

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
local function Colored(key, text)
    local r, g, b = ns.Theme.Unpack(key)
    return ("|cff%02x%02x%02x%s|r"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
        math.floor(b * 255 + 0.5), text)
end
local function Click(frame, ...) frame:GetScript("OnClick")(frame, ...) end
local function LineFor(itemID)
    for _, line in ipairs(Find.state.lines) do
        if line.pick.itemID == itemID then return line end
    end
end

ns.UI:Show()
Gear:ShowTab("find")
Find.sheetHold:SetHeight(590)

-- 1.
suite.check("all three upgrades show", Listed() == "1101,1002,1001", Listed())
suite.check("Reputation is a box under FROM, ticked", Box("rep") ~= nil and Box("rep"):GetChecked() == true
    and Box("rep").label and Box("rep").label:GetText() == "Reputation" or Box("rep"):GetChecked() == true)
suite.check("it counts the gear factions sell", Find.sourceCounts.rep:GetText() == "1",
    Find.sourceCounts.rep:GetText())
suite.check("no line under the list while it is ticked", not Find.repStrip:IsShown())
Click(Box("rep"))
suite.check("unticked, the quartermaster's gear leaves", Listed():find("1002", 1, true) == nil
    and ns.db.finderSourcesOff.rep == true, Listed())
suite.check("a line under the list says so", Find.repStrip:IsShown()
    and Find.repStrip.text:GetText() == "1 upgrade from a reputation vendor is hidden.", Find.repStrip.text:GetText())
suite.check("with Show them", Find.repStrip.button.label:GetText() == "Show them")
suite.check("the old list's filter agrees", #FinderUI:SourceFilter(Find.state.found)(LineFor(1002).pick) == 0
    and #FinderUI:SourceFilter(Find.state.found)(LineFor(1001).pick) == 1)
suite.check("the upgrade quest leaves it out",
    not Quest.WindowAllows(LineFor(1002).pick.sources[1], LineFor(1002).pick)
    and Quest.WindowAllows(LineFor(1001).pick.sources[1], LineFor(1001).pick))
local chosen = Quest:Choose(Find.state.found)
suite.check("and never picks it", chosen == nil or chosen.pick.itemID ~= 1002,
    chosen and chosen.pick.itemID)
suite.check("the words read right for more", Find.RepHiddenText(3) == "3 upgrades from reputation vendors are hidden."
    and Find.RepHiddenText(0) == nil)
Click(Find.repStrip.button)
suite.check("Show them ticks it again", ns.db.finderSourcesOff.rep == nil and Box("rep"):GetChecked() == true
    and Listed():find("1002", 1, true) ~= nil and not Find.repStrip:IsShown(), Listed())
Click(Box("rep"))
Click(Find.showAll)
suite.check("Show All ticks it too", ns.db.finderSourcesOff == nil and Box("rep"):GetChecked() == true)

-- 2.
local goggles = Row(1101)
suite.check("the goggles stay listed", goggles ~= nil, Listed())
suite.check("and say the skill they need", goggles and goggles.item:GetText():find("Needs Engineering 100 to wear", 1, true) ~= nil,
    goggles and goggles.item:GetText())
suite.check("in amber while you lack it", goggles and goggles.item:GetText():find(Colored("warn",
    "Needs Engineering 100 to wear"), 1, true) ~= nil)
local pick = LineFor(1101).pick
suite.check("they wait on the skill", ns.Crafting.WearWaits(pick) and pick.wear.rank == 100 and pick.wear.have == 80)
local follow, why = Quest.CanFollow(pick)
suite.check("so they are not a quest yet", follow == nil and why == "Needs Engineering 100 to wear", why)
suite.check("Only What I Can Get Now leaves them out", not FinderUI.GetsNow(pick.sources[1], pick))
suite.check("the footer explains amber", Find.footer:GetText():find("Amber gear is for later", 1, true) ~= nil,
    Find.footer:GetText())
skill = 120
ns.Finder:MarkStale()
pick.wear = ns.Crafting:Wear(1101)
suite.check("with the skill they wait on nothing", not ns.Crafting.WearWaits(pick) and pick.wear.met)
suite.check("but still say it", ns.Crafting.WearText(pick) == "Needs Engineering 100 to wear")

-- 3.
local Dungeons = ns.DungeonsTab
local lines = {
    { kind = "boss", text = "Scarlet Commander Mograine" },
    { kind = "drop", name = "Aegis of the Scarlet Commander", slot = "Off Hand" },
    { kind = "drop", name = "Mograine's Might", slot = "Two-Hand" },
    { kind = "boss", text = "Herod" },
    { kind = "drop", name = "Ravager", slot = "Two-Hand" },
    { kind = "note", text = "No drops seen here yet." },
    { kind = "boss", text = "QUESTS INSIDE" },
    { kind = "quest", name = "In the Name of the Light", sub = "Reward: |cff1eff00Bonebiter|r +12%" },
}
local all, none, total = Dungeons.Match(lines, nil)
suite.check("with nothing typed every line shows", all == lines and none == nil and total == nil)
local found, matched, count = Dungeons.Match(lines, "aegis")
suite.check("typing keeps the drops that match, under their boss", #found == 2 and found[1].text
    == "Scarlet Commander Mograine" and found[2].name == "Aegis of the Scarlet Commander", #found)
suite.check("and counts them", matched == 1 and count == 4, tostring(matched) .. " " .. tostring(count))
found = Dungeons.Match(lines, "herod")
suite.check("a boss's name keeps all its drops", #found == 2 and found[2].name == "Ravager", #found)
found = Dungeons.Match(lines, "bonebiter")
suite.check("a quest's reward matches, without its colour", #found == 2 and found[2].kind == "quest", #found)
found = Dungeons.Match(lines, "two-hand")
suite.check("the slot matches", #found == 4, #found)
suite.check("the words read right", ns.L.Format("%d of %d shown", 2, 31) == "2 of 31 shown")
Gear:ShowTab("dungeons")
suite.check("the Dungeons tab has a Find box", Dungeons.findBox ~= nil and Dungeons:IsShown())
Dungeons.allLines = lines
Dungeons.findBox.editBox:SetText("aegis")
Dungeons.findBox.editBox:GetScript("OnTextChanged")(Dungeons.findBox.editBox, true)
suite.check("typing narrows the lines shown", Dungeons.find == "aegis" and #Dungeons.lines == 2, #Dungeons.lines)
suite.check("and the foot says how many", Dungeons.foot:GetText():find("1 of 4 shown.", 1, true) ~= nil,
    Dungeons.foot:GetText())
Dungeons.findBox.editBox:SetText("")
Dungeons.findBox.editBox:GetScript("OnTextChanged")(Dungeons.findBox.editBox, true)
suite.check("cleared, every line is back", Dungeons.find == nil and #Dungeons.lines == #lines)

suite.done()
