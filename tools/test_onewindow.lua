-- The Equipment window in the one Blackthornes window (UI/GearWindow.lua;
-- the owner said build the one window, 2026-10-30, and the Equipment
-- window with its tab bar, 2026-11-22).
--
-- What must hold:
--   1. On unless unticked; unticked, the Equipment window opens in its own
--      frame.
--   2. Ticked, opening Equipment opens the one window on it, with the
--      Equipment window laid into its area, bare of its own rim and grip,
--      its tab bar still along the top.
--   3. The old tabs (Dungeon Quests, Dungeon Loot, Settings) show in the
--      Equipment window's page area, also when opened by themselves; one
--      tab at a time.
--   Swapping addons on the rail keeps the one window up.
--   4. Closing the one window gives the Equipment window back its own place.
--   5. "One Window:" on the General page writes every save.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("onewindow")

_G.BlackthornesWindow = nil
local ns = env.Load()
local Finder, SettingsUI, SW, Gear = ns.FinderUI, ns.SettingsUI, ns.SharedWindow, ns.GearWindow

ns.MinimapButton.button = ns.MinimapButton.button or env.Stub()
ns.MinimapButton:JoinShared()
local hub = _G.BlackthornesWindow
suite.check("Equipment joins with its window", hub.entries.equipment and hub.entries.equipment.host == Gear.host)
suite.check("the one window is Equipment's own copy", Finder.One() == SW)

-- 1.
ns.db.oneWindow = nil
suite.check("on unless unticked", SW.On())
ns.db.oneWindow = false
ns.UI:Show()
suite.check("off: the Equipment window opens by itself", Gear.frame:IsShown() and not Finder:Hosted()
    and Gear.frame:GetParent() == UIParent)
suite.check("on My Gear", Gear.tab == "gear" and ns.MyGear:IsShown())
Finder:Show()
suite.check("the Upgrades tab's old window is laid into it", Finder.frame:GetParent() == Gear.area
    and Finder.frame:IsShown() and not ns.MyGear:IsShown())
suite.check("without its own rim", Finder.frame.titan == nil or not Finder.frame.titan:IsShown())
suite.check("its own size grip", Finder.sizeGrip and not Finder.sizeGrip:IsShown())
suite.check("or its hanging tabs", not Finder.tabStrip:IsShown())
ns.UI:Hide()
suite.check("closing it closes the tab too", not Gear.frame:IsShown() and not Finder.frame:IsShown())

-- 2.
SW.SetOn(true)
ns.UI:Show()
local area = hub.frame and hub.frame.area
suite.check("on: the one window opens", hub.frame and hub.frame:IsShown())
suite.check("on Equipment", hub.current == hub.entries.equipment and ns.db.oneWindowPick == "equipment")
suite.check("the Equipment window is in it", Finder:Hosted() and Gear.frame:GetParent() == area
    and Gear.frame:IsShown())
suite.check("on My Gear", Gear.tab == "gear" and ns.MyGear:IsShown())
suite.check("without its own rim", Gear.frame.titan == nil or not Gear.frame.titan:IsShown())
suite.check("or its own size grip", Gear.sizeGrip and not Gear.sizeGrip:IsShown())
suite.check("its tab bar still along the top", Gear.strip ~= nil and Gear.strip.selected == "gear")

-- 3.
Gear:ShowTab("dungeons")
local dq = ns.DungeonQuestsUI.frame
suite.check("Dungeon Quests shows in the page area", dq:GetParent() == Gear.area and dq:IsShown())
suite.check("and My Gear stepped aside", not ns.MyGear:IsShown())
suite.check("the one window stays up", hub.frame:IsShown() and Finder:Hosted())
SettingsUI:Build()
local settings = SettingsUI.frame
settings._point = false
function settings:SetAlpha(value) self._alpha = value end
SettingsUI:Show()
suite.check("Settings opened by itself goes in as a tab", SettingsUI.frame:GetParent() == Gear.area
    and SettingsUI.frame:IsShown() and not dq:IsShown() and Gear.strip.selected == "settings")
-- A player saw it dimmed there (2026-10-31): its opening fade was left
-- running with a spot of its own on the screen.
suite.check("at full strength, its fade let go", settings._alpha == 1
    and not ns.Motion:Running(settings, "open"))

-- Show Descriptions makes the pages taller: the one window grows to hold
-- them. The test's frames don't follow their anchors, so the area keeps
-- its old height; the one window around it is what grows.
do
    local before, oneBefore = area:GetHeight(), hub.frame:GetHeight()
    SettingsUI.pages:ShowDescriptions(true)
    local need = SettingsUI.pages.need
    suite.check("descriptions on: the pages say how tall they are", type(need) == "table" and need[2] > before)
    suite.check("Settings says what the pages need", Finder.needs.settings and Finder.needs.settings[2] == need[2])
    suite.check("and the one window grows to hold them",
        hub.frame:GetHeight() - oneBefore >= need[2] - before
        or hub.frame:GetHeight() >= SW.Room(hub.frame))
    suite.check("but never taller than the screen", hub.frame:GetHeight() <= SW.Room(hub.frame))
    SettingsUI.pages:ShowDescriptions(false)
end
suite.check("and not placed at its own saved spot", not (rawget(settings, "_point") and settings._point[2] == UIParent))
ns.DungeonLootUI:Show()
suite.check("so does Dungeon Loot", ns.DungeonLootUI.frame:GetParent() == Gear.area
    and not SettingsUI.frame:IsShown())

-- A window built for the first time hides itself before it is laid in
-- (a player's report, 2026-10-30: picking another addon on the rail once
-- turned the one window into that addon's own window).
local fresh = { GetParent = function() return UIParent end }
Finder:Closed(fresh)
suite.check("a window not yet laid in hiding keeps the one window", hub.frame:IsShown() and Finder:Hosted())

-- Swapping to another addon on the rail hands the Equipment window back
-- without closing the one window, so Equipment never falls back to its own.
local entered, left = 0, 0
SW:Join({ key = "farmer", order = 1, name = "Farmer", db = function() return {} end,
    host = { enter = function() entered = entered + 1 end, leave = function() left = left + 1 end } })
SW.Pick("farmer")
suite.check("swapping keeps the one window up", hub.frame:IsShown() and hub.current == hub.entries.farmer)
suite.check("the other addon moved in", entered == 1)
suite.check("the Equipment window went home, hidden", not Finder:Hosted() and Gear.frame:GetParent() == UIParent
    and not Gear.frame:IsShown() and not ns.DungeonLootUI.frame:IsShown())
SW.Pick("equipment")
suite.check("back on Equipment in the same window", hub.frame:IsShown() and hub.current == hub.entries.equipment
    and Finder:Hosted() and left == 1)
suite.check("on the tab it was on", Gear.tab == "loot" and ns.DungeonLootUI.frame:IsShown())
hub.entries.farmer = nil

-- 4.
hub.frame:Hide()
local onHide = hub.frame:GetScript("OnHide")
if onHide then onHide(hub.frame) end
suite.check("closing it lets Equipment go", not Finder:Hosted() and hub.current == nil)
suite.check("the Equipment window is back on its own", Gear.frame:GetParent() == UIParent)
suite.check("hidden, with its tabs", not Gear.frame:IsShown() and not ns.DungeonLootUI.frame:IsShown()
    and not ns.MyGear:IsShown())
suite.check("with its grip", Gear.sizeGrip:IsShown())
suite.check("the old tabs stay in its page area", dq:GetParent() == Gear.area and SettingsUI.frame:GetParent() == Gear.area)

-- 5.
local other = {}
SW:Join({ key = "pets", order = 3, name = "Pets", db = function() return other end })
SettingsUI:Show()
suite.check("Settings opens in the one window", Finder:Hosted() and Gear.frame:GetParent() == hub.frame.area
    and SettingsUI.frame:IsShown())
SettingsUI:SetOneWindow(false)
local onHideAgain = hub.frame:GetScript("OnHide")
if onHideAgain then onHideAgain(hub.frame) end
suite.check("unticked in every save", ns.db.oneWindow == false and other.oneWindow == false)
SettingsUI:Show()
suite.check("Settings opens in Equipment's own window again", not Finder:Hosted()
    and Gear.frame:GetParent() == UIParent and Gear.frame:IsShown() and SettingsUI.frame:IsShown())
SettingsUI:SetOneWindow(true)
suite.check("ticked again in every save", ns.db.oneWindow == true and other.oneWindow == true)
suite.check("and Settings moves into the one window", Finder:Hosted() and Gear.frame:GetParent() == hub.frame.area
    and SettingsUI.frame:IsShown() and Gear.tab == "settings")

-- 6. Window Position's Set Default while hosted leaves the window where it is
-- (a player's report, 2026-10-31: it pulled the page out of the one window).
rawset(SettingsUI.frame, "_point", nil)
rawset(Gear.frame, "_point", nil)
SettingsUI:ResetPositions()
suite.check("Set Default keeps Settings in the one window", Finder:Hosted()
    and SettingsUI.frame:GetParent() == Gear.area and Gear.frame:GetParent() == hub.frame.area
    and rawget(SettingsUI.frame, "_point") == nil and rawget(Gear.frame, "_point") == nil)

SW.SetOn(false)
_G.BlackthornesWindow = nil
suite.done()
