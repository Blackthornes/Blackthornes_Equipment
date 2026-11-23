-- Forget a character (a player asked, the owner said build it, 2026-11-22):
-- a deleted alt kept being offered gear. Forget drops that one character's
-- note and skip tick, never the one playing, and never while the GUID
-- can't be read.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("forgetalt")

local ARMOR, LEATHER = 4, 2
local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end

local ITEMS = {
    ["item:1"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = LEATHER, stats = Agi(10) },
    ["item:11"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = LEATHER, stats = Agi(2) },
    -- No upgrade for the hunter, twice the rogue's chest.
    ["item:4"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = LEATHER, stats = Agi(4) },
}

local ns = env.Load()
_G.UnitClass = function() return "HUNTER", "HUNTER" end
local guid = "Player-1"
_G.UnitGUID = function() return guid end
_G.GetRealmName = function() return "Here" end
_G.UnitFactionGroup = function() return "Horde", "Horde" end
_G.UnitName = function() return "Ana Smith" end
env.InstallItems(ITEMS, { [5] = "item:1" }, { [0] = { [4] = "item:4" } })
_G.C_Container.GetContainerItemInfo = function(bag, slot)
    if bag ~= 0 then return nil end
    return { quality = 1, isBound = false, stackCount = 1 }
end
_G.C_TooltipInfo = { GetHyperlink = function() return { lines = { { type = 11, price = 50 } } } end }

local Alts = ns.Alts
Alts:Record()
ns.db.characterGear["Player-2"] = { class = "ROGUE", level = 20, realm = "Here", faction = "Horde",
    worn = { [5] = "item:11" }, name = "Bob Wither" }
ns.db.characterGear["Player-3"] = { class = "ROGUE", level = 20, realm = "Here", faction = "Horde",
    worn = { [5] = "item:11" }, name = "Cara Wells" }
ns.db.skipUpgrades = { ["Player-2"] = true }
Alts:SetSkipped("Player-2", false)

-- The deleted alt (Player-3) is offered the chest before.
local best = Alts:BestFor("item:4")
suite.check("the alt is offered gear at first", best ~= nil)

-- Never the character playing.
suite.check("the one playing can't be forgotten", Alts:CanForget("Player-1") == false)
suite.check("and Forget refuses it", Alts:Forget("Player-1") == nil)
suite.check("its note stays", ns.db.characterGear["Player-1"] ~= nil)

-- Never while the client won't say who's playing.
guid = nil
suite.check("no GUID: nothing can be forgotten", Alts:CanForget("Player-3") == false)
suite.check("and Forget changes nothing", Alts:Forget("Player-3") == nil
    and ns.db.characterGear["Player-3"] ~= nil)
guid = "Player-1"

-- A character with no note can't be forgotten.
suite.check("an unknown key is refused", Alts:Forget("Player-9") == nil)

-- Forget both rogues; one was skipped.
Alts:SetSkipped("Player-2", true)
local redraws = 0
_G.BlackthornesTS = { Upgrades = { RedrawSoon = function() redraws = redraws + 1 end } }
suite.check("forgetting answers the whole name", Alts:Forget("Player-3") == "Cara Wells")
suite.check("its note is gone", ns.db.characterGear["Player-3"] == nil)
suite.check("Tradeskills is told to ask again", redraws >= 1, redraws)
suite.check("a skipped one loses its tick too", Alts:Forget("Player-2") == "Bob Wither"
    and ns.db.skipUpgrades["Player-2"] == nil)
suite.check("nobody else is offered the chest", Alts:BestFor("item:4") == nil)
suite.check("the picker lists only the one playing", #Alts:Characters() == 1
    and Alts:Characters()[1].key == "Player-1")

-- It comes back if it logs in again.
guid = "Player-3"
_G.UnitName = function() return "Cara Wells" end
Alts:Record()
suite.check("a forgotten character that logs in writes a new note", ns.db.characterGear["Player-3"] ~= nil)

-- The Characters page of Settings: Forget is on each row. The first click
-- asks for Confirm, the second forgets.
guid = "Player-1"
_G.UnitName = function() return "Ana Smith" end
ns.db.characterGear["Player-4"] = { class = "ROGUE", level = 20, realm = "Here", faction = "Horde",
    worn = { [5] = "item:11" }, name = "Dan Ford" }
_G.Settings = {
    RegisterCanvasLayoutCategory = function(panel, name) return { panel = panel, name = name } end,
    RegisterAddOnCategory = function() end,
}
local SettingsUI = ns.SettingsUI
if SettingsUI.OnEnable then SettingsUI:OnEnable() end
ns.HandleSlash("settings")
local Page = ns.CharactersPage
SettingsUI.pages:Show("characters")
local printed = {}
local realPrint = ns.Print
ns.Print = function(text) printed[#printed + 1] = text end
local function Row(key)
    for _, row in ipairs(Page.rows) do
        if row:IsShown() and row.key == key then return row end
    end
end
-- Timers wait until run by hand, so Confirm stays up between clicks.
local timers = {}
local realAfter = C_Timer.After
C_Timer.After = function(_, fn) timers[#timers + 1] = fn end
local function Click(key)
    local row = Row(key)
    row.forget:GetScript("OnClick")(row.forget)
    return Row(key)
end

suite.check("Settings opens on the Characters page", SettingsUI:IsShown() and Page:IsShown()
    and ns.db.settingsPage == "characters")
suite.check("every character has a row", Row("Player-1") ~= nil and Row("Player-3") ~= nil
    and Row("Player-4") ~= nil)
local mine = Row("Player-1")
suite.check("the one playing is first and tagged Playing", Page.rows[1] == mine and mine.tag:IsShown()
    and mine.tag:GetText() == "Playing")
suite.check("and has no Forget", not mine.forget:IsShown())
suite.check("a row shows the whole name, level and class", Row("Player-4").name:GetText() == "Dan Ford"
    and Row("Player-4").class:GetText() == "20 Rogue", Row("Player-4").class:GetText())
suite.check("an alt is not tagged", not Row("Player-4").tag:IsShown())
Page:ForgetClicked(mine); Page:ForgetClicked(mine)
suite.check("clicks on the one playing do nothing", ns.db.characterGear["Player-1"] ~= nil and #printed == 0
    and not mine.armed)

suite.check("an alt has Forget", Row("Player-4").forget:IsShown()
    and Row("Player-4").forget.label:GetText() == "Forget" and not Row("Player-4").ask:IsShown())
local row = Click("Player-4")
suite.check("one click asks for Confirm", row.forget.label:GetText() == "Confirm"
    and row.ask:IsShown() and row.ask:GetText() == "Forget this one"
    and ns.db.characterGear["Player-4"] ~= nil)
local other = Click("Player-3")
suite.check("each row asks for its own Confirm", ns.db.characterGear["Player-3"] ~= nil
    and other.forget.label:GetText() == "Confirm")
row = Click("Player-4")
suite.check("the second click forgets", ns.db.characterGear["Player-4"] == nil)
suite.check("chat says who", printed[1] == "Equipment forgot Dan Ford.", printed[1])
suite.check("its row is gone", Row("Player-4") == nil)
suite.check("no row is left on Confirm for someone else", (function()
    for _, r in ipairs(Page.rows) do
        if r:IsShown() and r.armed and r.armedKey ~= r.key then return false end
    end
    return true
end)())
-- Left alone, Confirm turns back to Forget.
other = Row("Player-3")
if not other.armed then other = Click("Player-3") end
suite.check("armed", other.forget.label:GetText() == "Confirm")
for _, fn in ipairs(timers) do fn() end
suite.check("Confirm times out", other.forget.label:GetText() == "Forget" and not other.armed
    and not other.ask:IsShown())
suite.check("and forgets nothing", ns.db.characterGear["Player-3"] ~= nil)

-- Skip Upgrades is a tick on the row.
other.skip:GetScript("OnClick")(other.skip)
suite.check("ticking a row skips that character", Alts:IsSkipped("Player-3") and Row("Player-3").skip:GetChecked())
Row("Player-3").skip:GetScript("OnClick")(Row("Player-3").skip)
suite.check("unticking brings it back", not Alts:IsSkipped("Player-3"))

-- The headings sort.
ns.db.characterGear["Player-5"] = { class = "MAGE", level = 9, realm = "Here", faction = "Horde",
    worn = {}, name = "Abe Young" }
Page:Refresh()
local function Order()
    local keys = {}
    for _, r in ipairs(Page.rows) do
        if r:IsShown() then keys[#keys + 1] = r.key end
    end
    return table.concat(keys, ",")
end
suite.check("unsorted, the one playing leads, then by name", Order() == "Player-1,Player-5,Player-3", Order())
Page.heads.name:GetScript("OnClick")(Page.heads.name)
suite.check("CHARACTER sorts by name", Order() == "Player-5,Player-1,Player-3", Order())
Page.heads.name:GetScript("OnClick")(Page.heads.name)
suite.check("a second click turns it round", Order() == "Player-3,Player-1,Player-5", Order())
Page.heads.class:GetScript("OnClick")(Page.heads.class)
suite.check("CLASS sorts by class, the mage after the hunters", Order() == "Player-1,Player-3,Player-5", Order())
Page.heads.class:GetScript("OnClick")(Page.heads.class)
suite.check("and the other way", Order():find("Player-5", 1, true) == 1, Order())
Alts:SetSkipped("Player-3", true)
Page.heads.skip:GetScript("OnClick")(Page.heads.skip)
suite.check("SKIP UPGRADES puts the skipped first", Order():find("Player-3", 1, true) == 1, Order())
Alts:SetSkipped("Player-3", false)

-- Not sure who is playing (a dungeon): nobody can be forgotten.
guid = nil
Page:Refresh()
suite.check("with no GUID no row offers Forget", (function()
    for _, r in ipairs(Page.rows) do
        if r:IsShown() and r.forget:IsShown() then return false end
    end
    return true
end)())
guid = "Player-1"
C_Timer.After = realAfter
ns.Print = realPrint

_G.BlackthornesTS = nil
suite.done()
