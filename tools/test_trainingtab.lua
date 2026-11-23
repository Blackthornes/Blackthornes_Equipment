-- The Training tab, the Equipment window's fifth (UI/TrainingTab.lua,
-- rework step 5, the owner approved the mockup 2026-11-22).
--
-- What must hold:
--   1. It is a tab of the Equipment window, after Dungeons, and its name
--      carries how many spells wait.
--   2. TRAIN NOW and COMING SOON list the spells with level and cost; the
--      top says what it costs and what the character carries.
--   3. A right-click skips a spell; Show Skipped lists the skipped ones
--      and a right-click there brings one back.
--   4. Character: shows what another of the player's characters has
--      waiting, and nothing there can be skipped or shown the way.
--   5. WEAPON SKILLS lists every skill the class can learn, known or not,
--      with this side's cities and Show the Way. One an upgrade waits on
--      says so.
--   6. Class training asks the tab for the way to a trainer; the old
--      drawer is gone.
--   7. Nothing here judges gear or starts a scan, and a hidden page draws
--      nothing.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("trainingtab")

local ITEMS = {
    ["item:900"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = { ITEM_MOD_AGILITY_SHORT = 10 } },
    ["item:7001"] = { loc = "INVTYPE_2HWEAPON", class = 2, subclass = 6, stats = { ITEM_MOD_AGILITY_SHORT = 30 } }, -- polearm
}

local ns = env.Load()
ns.CLASS_SPELL_PRICES = { [3] = 200 }
ns.CLASS_SPELLS = { HUNTER = {
    { 1, 4, 1, "Serpent Sting" },
    { 2, 10, 2, "Serpent Sting", nil, 1 },
    { 3, 10, 0, "Aspect of the Hawk" },
    { 4, 14, 0, "Arcane Shot" },
    { 5, 14, 0, "Scare Beast" },
    { 6, 16, 2, "Arcane Shot", nil, 4 },
    { 7, 16, 0, "Immolation Trap" },
} }

-- A level 12 hunter who knows axes and bows.
local known = { [1] = true, [196] = true, [197] = true, [264] = true }
local money = 310412
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitLevel = function() return 12 end
_G.UnitRace = function() return "Orc", "Orc", 2 end
_G.UnitFactionGroup = function() return "Horde", "Horde" end
_G.UnitName = function() return "Grommak Ironhide" end
_G.UnitGUID = function() return "Player-1-AAA" end
_G.GetRealmName = function() return "Test Realm" end
_G.IsPlayerSpell = function(id) return known[id] == true end
_G.GetRealZoneText = function() return "Orgrimmar" end
_G.GetMoney = function() return money end
env.InstallItems(ITEMS, { [5] = "item:900" }, { [0] = {} }, 12)

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end

local Window, Tab, CT, Finder, Compare = ns.GearWindow, ns.TrainingTab, ns.ClassTraining, ns.Finder, ns.Compare

local judges, scans = 0, 0
local realJudge, realBuild = Compare.Judge, Finder.Build
Compare.Judge = function(...) judges = judges + 1 return realJudge(...) end
Finder.Build = function(...) scans = scans + 1 return realBuild(...) end

local function Click(frame, ...) frame:GetScript("OnClick")(frame, ...) end
local function Lines()
    local out = {}
    for _, row in ipairs(Tab.rows) do
        if row:IsShown() then
            out[#out + 1] = (row.name:GetText() or "") .. "|" .. (row.level:GetText() or "") .. "|"
                .. (row.cost:GetText() or "")
        end
    end
    return table.concat(out, "\n")
end
local function SpellRow(name)
    for _, row in ipairs(Tab.rows) do
        if row:IsShown() and row.name:GetText() == name then return row end
    end
end
local function SkillRow(name)
    for _, row in ipairs(Tab.skillRows) do
        if row:IsShown() and row.name:GetText() == name then return row end
    end
end
local function TabName()
    for _, button in ipairs(Window.strip.tabs) do
        if button.key == "training" then return button.label:GetText() end
    end
end

--------------------------------------------------------------------------------
-- 1. A tab of the Equipment window, its name carrying the count
--------------------------------------------------------------------------------

do
    local keys = {}
    for _, tab in ipairs(Window.TABS) do keys[#keys + 1] = tab.key end
    suite.check("Training comes after Dungeons",
        table.concat(keys, ","):find("instances,training,", 1, true) ~= nil, table.concat(keys, ","))
    suite.check("the window knows its page", Window.pages.training == Tab)
end

Window:Open("training")
Tab.page.GetHeight = function() return 668 end
Tab:Refresh()
suite.check("the tab opens", Window.tab == "training" and Tab:IsShown())
suite.check("its name says two spells wait", TabName() == "Training (2)", TabName())

--------------------------------------------------------------------------------
-- 2. Train now and coming soon
--------------------------------------------------------------------------------

local text = Lines()
suite.check("TRAIN NOW heads what can be trained", text:find("TRAIN NOW||\n", 1, true) == 1, text)
suite.check("a ranked spell, not priced yet",
    text:find("Serpent Sting (Rank 2)|10|Not priced yet", 1, true) ~= nil, text)
suite.check("a spell at its usual price", text:find("Aspect of the Hawk|10|", 1, true) ~= nil
    and SpellRow("Aspect of the Hawk").cost:GetText() == CT.Money(200), text)
suite.check("COMING SOON heads the next level's", text:find("COMING SOON||\nArcane Shot|14|", 1, true) ~= nil
    and text:find("Scare Beast|14|", 1, true) ~= nil, text)
suite.check("a later level waits its turn", text:find("Immolation Trap", 1, true) == nil
    and text:find("Arcane Shot (Rank 2)", 1, true) == nil, text)
suite.check("the top says what training costs now",
    Tab.costLabel:GetText() == "Train now: " .. CT.CostText(200, 1, 2), Tab.costLabel:GetText())
suite.check("and what the character carries", Tab.haveLabel:GetText() == "You have " .. CT.Money(money),
    Tab.haveLabel:GetText())
suite.check("the foot counts them", Tab.foot:GetText() == "2 spells to train now. 2 more at level 14.",
    Tab.foot:GetText())
suite.check("the way to the trainer is offered", Tab.wayButton:IsShown())

--------------------------------------------------------------------------------
-- 3. Skipping
--------------------------------------------------------------------------------

suite.check("it says how to skip", Tab.skipNote:GetText() == "Right-click a spell to skip it.", Tab.skipNote:GetText())
suite.check("with nothing skipped there is no Show Skipped", not Tab.skippedButton:IsShown())
Click(SpellRow("Aspect of the Hawk"), "RightButton")
suite.check("a right-click skips the spell", CT:IsSkipped(3) and SpellRow("Aspect of the Hawk") == nil, Lines())
suite.check("the count says so", Tab.skipNote:GetText() == "Right-click a spell to skip it. 1 skipped.",
    Tab.skipNote:GetText())
suite.check("the tab's name follows", TabName() == "Training (1)", TabName())
suite.check("Show Skipped is offered", Tab.skippedButton:IsShown()
    and Tab.skippedButton.label:GetText() == "Show Skipped", Tab.skippedButton.label:GetText())
Click(Tab.skippedButton)
suite.check("it lists the skipped spell", Lines():find("SKIPPED||\nAspect of the Hawk|10|", 1, true) ~= nil, Lines())
suite.check("and turns into Hide Skipped", Tab.skippedButton.label:GetText() == "Hide Skipped")
Click(SpellRow("Aspect of the Hawk"), "RightButton")
suite.check("a right-click there brings it back", not CT:IsSkipped(3)
    and Lines():find("TRAIN NOW||\nSerpent Sting (Rank 2)|10|Not priced yet\nAspect of the Hawk", 1, true) ~= nil,
    Lines())
suite.check("a left click skips nothing", (function()
    Click(SpellRow("Aspect of the Hawk"), "LeftButton")
    return not CT:IsSkipped(3)
end)())
Click(Tab.skippedButton)

--------------------------------------------------------------------------------
-- 4. Another character
--------------------------------------------------------------------------------

CT:Data().characters["Player-1-BBB"] = { name = "Bob Stone", class = "HUNTER", level = 10, faction = "Horde",
    realm = "Test Realm", ready = { 2, 3 }, at = 1 }
Tab:Refresh()
local options = rawget(Tab.whoChoice, "options") or {}
suite.check("Character: lists the one playing, then the other", Tab.whoChoice:GetValue() == "me")
Tab.who = "Player-1-BBB"
Tab:Refresh()
text = Lines()
suite.check("the other character's spells show", text:find("Serpent Sting (Rank 2)|10|", 1, true) ~= nil
    and text:find("Aspect of the Hawk|10|", 1, true) ~= nil, text)
suite.check("with no coming soon", text:find("COMING SOON", 1, true) == nil, text)
suite.check("it says whose and when", Tab.skipNote:GetText() == "As last seen on Bob Stone, at level 10.",
    Tab.skipNote:GetText())
suite.check("the way to the trainer is not offered for another character", not Tab.wayButton:IsShown())
suite.check("nor what this one carries", Tab.haveLabel:GetText() == "")
Click(SpellRow("Aspect of the Hawk"), "RightButton")
suite.check("a right-click skips nothing for another character", not CT:IsSkipped(3))
suite.check("weapon skills say they are the one playing's",
    Tab.skillNote:IsShown() and Tab.skillNote:GetText():find("the character you are playing", 1, true) ~= nil,
    Tab.skillNote:GetText())
Tab.who = nil
Tab:Refresh()

--------------------------------------------------------------------------------
-- 5. Weapon skills
--------------------------------------------------------------------------------

local axes, polearms, daggers = SkillRow("One-Handed Axes"), SkillRow("Polearms"), SkillRow("Daggers")
suite.check("a known skill reads Known", axes ~= nil and axes.known:IsShown() and not axes.way:IsShown())
suite.check("known ones come first", Tab.skillRows[1].known:IsShown() and rawget(Tab.skillRows[1], "line").known)
suite.check("one to learn names this side's city", polearms ~= nil
    and polearms.sub:GetText() == "Learn from the weapon master in Undercity.", polearms and polearms.sub:GetText())
suite.check("with Show the Way", polearms.way:IsShown() and not polearms.known:IsShown())
suite.check("two cities read as a list", daggers ~= nil
    and daggers.sub:GetText() == "Learn from the weapon master in Orgrimmar or Undercity.", daggers and daggers.sub:GetText())
suite.check("a skill the class can never learn is not listed", SkillRow("One-Handed Maces") == nil)

local aimed
ns.QuestArrow.AimAtQuest = function(_, id, title, place) aimed = { title = title, place = place } return true end
Click(polearms.way)
suite.check("Show the Way points at the weapon master", aimed ~= nil and aimed.place.name == "Archibald"
    and aimed.place.zone == "Undercity", aimed and aimed.place.name)

-- A polearm in the bags that would be an upgrade once trained.
ns.UI.untrained = { { link = "item:7001", skill = "Polearms" } }
Tab:Refresh()
polearms = SkillRow("Polearms")
suite.check("a skill an upgrade waits on says so",
    polearms.sub:GetText() == "Learn from the weapon master in Undercity. An upgrade waits on it.",
    polearms.sub:GetText())
ns.UI.untrained = {}

-- Learned: it reads Known, with no trip to the page's own events.
known[200] = true
ns.WeaponSkills:Forget()
ns.WeaponSkills:Look()
Tab:Refresh()
suite.check("a skill learned reads Known", SkillRow("Polearms").known:IsShown())

--------------------------------------------------------------------------------
-- 6. Class training asks the tab (the drawer is gone)
--------------------------------------------------------------------------------

suite.check("there is no Training drawer", ns.TrainingDrawer == nil)
suite.check("Show the way is the tab's", CT.Guide == Tab.Guide)
suite.check("a change to the spells redraws the tab", type(CT.OnChanged) == "function")

--------------------------------------------------------------------------------
-- 7. No judging, and nothing while hidden
--------------------------------------------------------------------------------

suite.check("none of that judged gear or started a scan", judges == 0 and scans == 0, judges .. " " .. scans)
Window:ShowTab("gear")
Tab.foot:SetText("untouched")
known[2] = true
CT:Changed()
Tab:Refresh()
suite.check("hidden, the page draws nothing", Tab.foot:GetText() == "untouched")
suite.check("but the tab's name still counts", TabName() == "Training (1)", TabName())

-- Class training turned off in Settings: the page says so, the name loses
-- its count, weapon skills stay.
Window:ShowTab("training")
CT:SetOn(false)
Tab:Refresh()
Tab:PaintTab()
suite.check("off, it says so", Lines() == "Class training is turned off in Settings.||", Lines())
suite.check("the tab's name is plain", TabName() == "Training", TabName())
suite.check("weapon skills still show", SkillRow("One-Handed Axes") ~= nil)
CT:SetOn(true)

Compare.Judge, Finder.Build = realJudge, realBuild
suite.done()
