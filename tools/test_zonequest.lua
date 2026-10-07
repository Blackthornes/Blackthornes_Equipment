-- The upgrade quest panel's filters: "This zone only" keeps each tab to the
-- zone the character is in (off: anywhere), and the panel shows the same
-- "Solo quests only" and "Quest level" as Where to get upgrades, with a
-- button to open Settings.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("zonequest")

local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end
local function Chest(n) return { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = Agi(n) } end

local ITEMS = {
    ["item:900"] = Chest(10),    -- worn
    ["item:1001"] = Chest(20),   -- a vendor's in Elwynn Forest
    ["item:1002"] = Chest(40),   -- a vendor's in Westfall, better
    ["item:1003"] = Chest(30),   -- a quest in Elwynn Forest
    ["item:1004"] = Chest(50),   -- a quest in Westfall, better
}

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitRace = function() return "Human", "Human", 1 end
local zone = "Elwynn Forest"
_G.GetRealZoneText = function() return zone end
env.InstallItems(ITEMS, { [5] = "item:900" }, { [0] = {} }, 20)
_G.C_QuestLog = { IsQuestFlaggedCompleted = function() return false end }

local S = ns.Sources
ns.Crafts.ITEMS = {}
ns.RollData.ITEMS = {}
S.ZONES = { [12] = "Elwynn Forest", [40] = "Westfall" }
S.NPCS = {
    [1] = { "Corina Steele", 12, 41.5, 65.9, "A" },
    [2] = { "Kirsta Deepshadow", 40, 56.3, 31.0, "A" },
}
S.QUESTS = {
    [10] = { "Wolves of the Forest", 15, 18, 0, 0, "Marshal Dughan", 12, 42.1, 65.9, "" },
    [11] = { "The Killing Fields", 15, 18, 0, 0, "Farmer Saldean", 40, 56.0, 31.0, "" },
}
S.DUNGEONS = {}
S.BOSSES = {}
S.FOREVER = {}
S.ITEMS = {
    [1001] = { 15, 18, 0, 0, 500, v = { 1, 0 } },
    [1002] = { 15, 18, 0, 0, 500, v = { 2, 0 } },
    [1003] = { 15, 18, 0, 0, 0, q = { 10 } },
    [1004] = { 15, 18, 0, 0, 0, q = { 11 } },
}

local Finder, Quest, Panel = ns.Finder, ns.UpgradeQuest, ns.QuestPanel

local function On(tab)
    local quest = Quest:QuestOn(tab)
    return quest and quest.itemID
end

--------------------------------------------------------------------------------
-- Off: anywhere
--------------------------------------------------------------------------------

suite.check("off by default", ns.db.upgradeQuestZoneOnly == false and not Quest:ZoneOnly())
Quest:SetEnabled(true)
suite.check("off, the vendor tab picks the best anywhere", On("vendor") == 1002, On("vendor"))
suite.check("and the quest tab", On("quest") == 1004, On("quest"))

--------------------------------------------------------------------------------
-- The panel's filters
--------------------------------------------------------------------------------

Panel:Refresh()
suite.check("the panel has the zone box", Panel.zoneBox ~= nil and not Panel.zoneBox:GetChecked())
suite.check("named plainly", Panel.zoneBox.label:GetText() == "This zone only")
Panel.zoneBox:GetScript("OnEnter")(Panel.zoneBox)
local tip = table.concat(GameTooltip._lines, "\n")
suite.check("hovering says what it does", tip:find("zone you are in", 1, true) ~= nil, tip)
Panel.zoneBox:GetScript("OnLeave")(Panel.zoneBox)

suite.check("the panel has the solo box", Panel.soloBox ~= nil and Panel.soloBox.label:GetText() == "Solo quests only")
suite.check("and the level stepper, at the finder's value", Panel.levelStepper ~= nil
    and Panel.levelStepper:GetValue() == 4, Panel.levelStepper and Panel.levelStepper:GetValue())
suite.check("in the finder's words", Panel.QuestLevelsText(0) == "Up to my level"
    and Panel.QuestLevelsText(11) == "Any" and Panel.QuestLevelsText(4) == "Up to +4")

-- Everything fits inside the panel, measured.
local Theme = ns.Theme
local zoneWidth = Theme.TextWidth("small", "This zone only") + 24
local soloWidth = Theme.TextWidth("small", "Solo quests only") + 24
suite.check("the tick boxes fit on one row", 10 + zoneWidth + 16 + soloWidth <= 340 - 10,
    10 + zoneWidth + 16 + soloWidth)
local labelWidth = Theme.TextWidth("small", "Quest level")
local rowWidth = 10 + labelWidth + 8 + Panel.levelStepper:GetWidth() + 10 + Panel.settingsButton:GetWidth() + 10
suite.check("the level and Settings fit on the next", rowWidth <= 340, rowWidth)
suite.check("the stepper holds its longest words", Panel.levelStepper:GetWidth()
    >= Theme.TextWidth("small", "Up to my level") + 52)

-- Settings opens from the panel.
suite.check("Settings is shut", not (ns.SettingsUI.frame and ns.SettingsUI.frame:IsShown()))
Panel.settingsButton:GetScript("OnClick")(Panel.settingsButton)
suite.check("the Settings button opens it", ns.SettingsUI.frame and ns.SettingsUI.frame:IsShown())
Panel.settingsButton:GetScript("OnEnter")(Panel.settingsButton)
tip = table.concat(GameTooltip._lines, "\n")
suite.check("and says so", tip:find("settings", 1, true) ~= nil, tip)
Panel.settingsButton:GetScript("OnLeave")(Panel.settingsButton)
ns.SettingsUI:Hide()

--------------------------------------------------------------------------------
-- This zone only
--------------------------------------------------------------------------------

Panel.zoneBox:GetScript("OnClick")(Panel.zoneBox)
suite.check("ticking it saves it", ns.db.upgradeQuestZoneOnly == true and Quest:ZoneOnly())
suite.check("the vendor tab picks again here", On("vendor") == 1001, On("vendor"))
suite.check("and so does the quest tab", On("quest") == 1003, On("quest"))
suite.check("nothing is counted as skipped", not Quest:Skipped()[1002] and not Quest:Skipped()[1004])

zone = "Westfall"
Quest:OnEvent("ZONE_CHANGED_NEW_AREA")
suite.check("in a new zone, each tab picks from there", On("vendor") == 1002 and On("quest") == 1004,
    tostring(On("vendor")) .. "," .. tostring(On("quest")))

zone = "Duskwood"
Quest:OnEvent("ZONE_CHANGED_NEW_AREA")
suite.check("a zone with nothing leaves the tabs empty", On("vendor") == nil and On("quest") == nil)
Panel:Refresh()
suite.check("and the panel says why", Panel.empty:GetText():find("This zone only", 1, true) ~= nil,
    Panel.empty:GetText())

-- Chosen by hand in Where to get upgrades: stays wherever the player goes.
local found = Finder:Scan()
local pick
for _, entry in ipairs(found.all[5] or {}) do
    if entry.itemID == 1001 then pick = entry end
end
suite.check("followed from the finder", pick and Quest:Follow(pick) ~= nil)
zone = "Westfall"
Quest:OnEvent("ZONE_CHANGED_NEW_AREA")
suite.check("a followed upgrade stays in another zone", On("vendor") == 1001, On("vendor"))
suite.check("the other tab picks from here", On("quest") == 1004, On("quest"))

-- Unticked: what it picked is let go and the tabs look anywhere again.
zone = "Elwynn Forest"
Quest:OnEvent("ZONE_CHANGED_NEW_AREA")
suite.check("back home, the quest tab picks here", On("quest") == 1003, On("quest"))
Panel:Refresh()
suite.check("the box shows it ticked", Panel.zoneBox:GetChecked())
Panel.zoneBox:GetScript("OnClick")(Panel.zoneBox)
suite.check("unticking saves it", ns.db.upgradeQuestZoneOnly == false)
suite.check("the quest tab picks the best anywhere again", On("quest") == 1004, On("quest"))
suite.check("the followed upgrade is kept", On("vendor") == 1001, On("vendor"))

zone = "Duskwood"
Quest:OnEvent("ZONE_CHANGED_NEW_AREA")
suite.check("unticked, travelling changes nothing", On("quest") == 1004, On("quest"))

--------------------------------------------------------------------------------
-- The shared quest filters
--------------------------------------------------------------------------------

Panel:Refresh()
Panel.levelStepper.minus:GetScript("OnClick")(Panel.levelStepper.minus)
suite.check("the panel's stepper sets the finder's limit", ns.db.questLevelsAbove == 3
    and Finder:QuestLevelsAbove() == 3, ns.db.questLevelsAbove)
ns.FinderUI:Show()
suite.check("the finder's stepper follows", ns.FinderUI.questLevels:GetValue() == 3,
    ns.FinderUI.questLevels:GetValue())
Finder:SetQuestLevelsAbove(Finder.QUEST_LEVELS_ANY)
Panel:Refresh()
suite.check("and the panel follows the finder", Panel.levelStepper:GetValue() == Finder.QUEST_LEVELS_ANY,
    Panel.levelStepper:GetValue())

Panel.soloBox:GetScript("OnClick")(Panel.soloBox)
suite.check("the panel's solo box is the same switch", ns.db.soloQuestsOnly == true
    and ns.FinderUI.solo:GetChecked())
Finder:SetSoloOnly(false)
Panel:Refresh()
suite.check("and follows it back", not Panel.soloBox:GetChecked())

-- Folded, only the header shows.
Panel:ToggleFold()
suite.check("folded, the filters hide", not Panel.filters:IsShown())
Panel:ToggleFold()
suite.check("unfolded, they are back", Panel.filters:IsShown())

suite.done()
