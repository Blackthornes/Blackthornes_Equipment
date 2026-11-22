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

-- The Settings row: the first click asks for Confirm, the second forgets.
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
local controls = SettingsUI.controls
local printed = {}
local realPrint = ns.Print
ns.Print = function(text) printed[#printed + 1] = text end
SettingsUI:RefreshSkip()
local function Pick(key) controls.skipPicker:SetValue(key); SettingsUI:RefreshSkip() end
-- Timers wait until run by hand, so Confirm stays up between clicks.
local timers = {}
local realAfter = C_Timer.After
C_Timer.After = function(_, fn) timers[#timers + 1] = fn end
local function Click() controls.forget:GetScript("OnClick")(controls.forget) end

Pick("Player-1")
suite.check("the one playing: the button is greyed", not controls.forget.canForget)
suite.check("and the row says why", SettingsUI.forgetRow.hint:GetText():find("you're playing", 1, true))
Click(); Click()
suite.check("clicks on it do nothing", ns.db.characterGear["Player-1"] ~= nil and #printed == 0)

Pick("Player-4")
suite.check("an alt: the button is lit", controls.forget.canForget == true)
Click()
suite.check("one click asks for Confirm", controls.forget.label:GetText() == "Confirm"
    and ns.db.characterGear["Player-4"] ~= nil)
Pick("Player-3")
Click()
suite.check("Confirm for another character starts over", ns.db.characterGear["Player-3"] ~= nil
    and controls.forget.label:GetText() == "Confirm")
Pick("Player-4")
Click()
suite.check("picking back starts over too", ns.db.characterGear["Player-4"] ~= nil)
Click()
suite.check("the second click forgets", ns.db.characterGear["Player-4"] == nil)
suite.check("the button reads Forget again", controls.forget.label:GetText() == "Forget")
suite.check("chat says who", printed[1] == "Equipment forgot Dan Ford.", printed[1])
suite.check("the picker no longer lists it", (function()
    for _, entry in ipairs(controls.skipPicker.characters) do
        if entry.key == "Player-4" then return false end
    end
    return true
end)())
-- Left alone, Confirm turns back to Forget.
Pick("Player-3")
Click()
suite.check("armed again", controls.forget.label:GetText() == "Confirm")
for _, fn in ipairs(timers) do fn() end
suite.check("Confirm times out", controls.forget.label:GetText() == "Forget" and not controls.forget.armed)
suite.check("and forgets nothing", ns.db.characterGear["Player-3"] ~= nil)
C_Timer.After = realAfter
ns.Print = realPrint

_G.BlackthornesTS = nil
suite.done()
