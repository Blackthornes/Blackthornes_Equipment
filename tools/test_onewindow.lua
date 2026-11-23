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
--   3. Every tab, Settings too, shows in the Equipment window's page area,
--      also when opened by itself or by a key an old tab had; one at a
--      time.
--   Swapping addons on the rail keeps the one window up.
--   4. Closing the one window gives the Equipment window back its own place.
--   5. "One Window:" on the General page writes every save.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("onewindow")

_G.BlackthornesWindow = nil
local ns = env.Load()
local SettingsUI, SW, Gear = ns.SettingsUI, ns.SharedWindow, ns.GearWindow
local function Hosted() return Gear.hostArea ~= nil end

ns.MinimapButton.button = ns.MinimapButton.button or env.Stub()
ns.MinimapButton:JoinShared()
local hub = _G.BlackthornesWindow
suite.check("Equipment joins with its window", hub.entries.equipment and hub.entries.equipment.host == Gear.host)
suite.check("the one window is Equipment's own copy", Gear.One() == SW)

-- 1.
ns.db.oneWindow = nil
suite.check("on unless unticked", SW.On())
ns.db.oneWindow = false
ns.UI:Show()
suite.check("off: the Equipment window opens by itself", Gear.frame:IsShown() and not Hosted()
    and Gear.frame:GetParent() == UIParent)
suite.check("on My Gear", Gear.tab == "gear" and ns.MyGear:IsShown())
Gear:Open("find")
suite.check("Find Upgrades is a page of it", ns.FindUpgrades:IsShown() and not ns.MyGear:IsShown())
ns.UI:Hide()
suite.check("closing it closes the page too", not Gear.frame:IsShown() and not ns.FindUpgrades:IsShown())

-- 2.
SW.SetOn(true)
ns.UI:Show()
local area = hub.frame and hub.frame.area
suite.check("on: the one window opens", hub.frame and hub.frame:IsShown())
suite.check("on Equipment", hub.current == hub.entries.equipment and ns.db.oneWindowPick == "equipment")
suite.check("the Equipment window is in it", Hosted() and Gear.frame:GetParent() == area
    and Gear.frame:IsShown())
suite.check("on My Gear", Gear.tab == "gear" and ns.MyGear:IsShown())
suite.check("without its own rim", Gear.frame.titan == nil or not Gear.frame.titan:IsShown())
suite.check("or its own size grip", Gear.sizeGrip and not Gear.sizeGrip:IsShown())
suite.check("its tab bar still along the top", Gear.strip ~= nil and Gear.strip.selected == "gear")

-- 3.
Gear:ShowTab("dungeons")
suite.check("the old Dungeon Quests key shows Dungeons in the page area", ns.DungeonsTab:IsShown()
    and Gear.tab == "instances")
suite.check("and My Gear stepped aside", not ns.MyGear:IsShown())
suite.check("the one window stays up", hub.frame:IsShown() and Hosted())
SettingsUI:Show()
suite.check("Settings opened by itself goes in as a tab", SettingsUI.frame:GetParent() == Gear.area
    and SettingsUI:IsShown() and not ns.DungeonsTab:IsShown() and Gear.strip.selected == "settings")
suite.check("All Addons is off the list there, behind the one window's gear",
    SettingsUI.pages:Hidden("all"))

-- Show Descriptions makes the pages taller. They scroll; the one window
-- keeps its size.
do
    local oneBefore = hub.frame:GetHeight()
    local before = SettingsUI.pages.need[2]
    SettingsUI.pages:ShowDescriptions(true)
    local need = SettingsUI.pages.need
    suite.check("descriptions on: the pages say how tall they are", type(need) == "table" and need[2] >= before)
    suite.check("Settings asks the window for width only", Gear.needs.settings ~= nil
        and Gear.needs.settings[1] == need[1] and Gear.needs.settings[2] == nil)
    suite.check("so the one window does not grow", hub.frame:GetHeight() == oneBefore, hub.frame:GetHeight())
    SettingsUI.pages:ShowDescriptions(false)
end
Gear:Open("loot")
suite.check("the old Dungeon Loot key takes Settings' place", ns.DungeonsTab:IsShown() and not SettingsUI:IsShown())

-- Swapping to another addon on the rail hands the Equipment window back
-- without closing the one window, so Equipment never falls back to its own.
local entered, left = 0, 0
SW:Join({ key = "farmer", order = 1, name = "Farmer", db = function() return {} end,
    host = { enter = function() entered = entered + 1 end, leave = function() left = left + 1 end } })
SW.Pick("farmer")
suite.check("swapping keeps the one window up", hub.frame:IsShown() and hub.current == hub.entries.farmer)
suite.check("the other addon moved in", entered == 1)
suite.check("the Equipment window went home, hidden", not Hosted() and Gear.frame:GetParent() == UIParent
    and not Gear.frame:IsShown() and not ns.DungeonsTab:IsShown())
SW.Pick("equipment")
suite.check("back on Equipment in the same window", hub.frame:IsShown() and hub.current == hub.entries.equipment
    and Hosted() and left == 1)
suite.check("on the tab it was on", Gear.tab == "instances" and ns.DungeonsTab:IsShown())
hub.entries.farmer = nil

-- 4.
hub.frame:Hide()
local onHide = hub.frame:GetScript("OnHide")
if onHide then onHide(hub.frame) end
suite.check("closing it lets Equipment go", not Hosted() and hub.current == nil)
suite.check("the Equipment window is back on its own", Gear.frame:GetParent() == UIParent)
suite.check("hidden, with its pages", not Gear.frame:IsShown() and not ns.DungeonsTab:IsShown()
    and not ns.MyGear:IsShown())
suite.check("with its grip", Gear.sizeGrip:IsShown())
suite.check("Settings stays in its page area", SettingsUI.frame:GetParent() == Gear.area)

-- 5.
local other = {}
SW:Join({ key = "pets", order = 3, name = "Pets", db = function() return other end })
SettingsUI:Show()
suite.check("Settings opens in the one window", Hosted() and Gear.frame:GetParent() == hub.frame.area
    and SettingsUI:IsShown())
SettingsUI:SetOneWindow(false)
local onHideAgain = hub.frame:GetScript("OnHide")
if onHideAgain then onHideAgain(hub.frame) end
suite.check("unticked in every save", ns.db.oneWindow == false and other.oneWindow == false)
SettingsUI:Show()
suite.check("Settings opens in Equipment's own window again", not Hosted()
    and Gear.frame:GetParent() == UIParent and Gear.frame:IsShown() and SettingsUI:IsShown())
SettingsUI:SetOneWindow(true)
suite.check("ticked again in every save", ns.db.oneWindow == true and other.oneWindow == true)
suite.check("and Settings moves into the one window", Hosted() and Gear.frame:GetParent() == hub.frame.area
    and SettingsUI:IsShown() and Gear.tab == "settings")

-- 6. Window Position's Set Default while hosted leaves the window where it is
-- (a player's report, 2026-10-31: it pulled the page out of the one window).
rawset(SettingsUI.frame, "_point", nil)
rawset(Gear.frame, "_point", nil)
SettingsUI:ResetPositions()
suite.check("Set Default keeps Settings in the one window", Hosted()
    and SettingsUI.frame:GetParent() == Gear.area and Gear.frame:GetParent() == hub.frame.area
    and rawget(SettingsUI.frame, "_point") == nil and rawget(Gear.frame, "_point") == nil)

SW.SetOn(false)
_G.BlackthornesWindow = nil
suite.done()
