-- The swap gem on the Equipment window and the one window
-- (UI/SharedWindow.lua AddSwap and Swap, the Equipment window's tab, show
-- and hide in UI/GearWindow.lua; the owner said build it, 2026-11-19).
--
-- What must hold:
--   1. The Equipment window carries a join gem; the one window a split gem.
--   2. Split from the one window on Dungeons: the one window closes,
--      the Equipment window opens on its own on Dungeons, and the One
--      Window box reads unticked.
--   3. Join from the Equipment window on Settings: the one window opens on
--      Equipment, still on Settings, and the box reads ticked.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("swapwindows")

_G.BlackthornesWindow = nil
local ns = env.Load()
local SettingsUI, SW, Gear = ns.SettingsUI, ns.SharedWindow, ns.GearWindow
local Dungeons = ns.DungeonsTab

ns.MinimapButton.button = ns.MinimapButton.button or env.Stub()
ns.MinimapButton:JoinShared()
local hub = _G.BlackthornesWindow

-- The game runs a frame's OnHide as it hides; the fake game does not.
local function HidesLikeTheGame(frame)
    local hide = frame.Hide
    frame.Hide = function(self)
        local was = self:IsShown()
        hide(self)
        local onHide = was and self:GetScript("OnHide")
        if onHide then onHide(self) end
    end
end

local function Gem(frame) return frame and rawget(frame, "blackthornesSwap") end

-- 1.
SW.SetOn(true)
Gear:Open("instances")
HidesLikeTheGame(hub.frame)
HidesLikeTheGame(Gear.frame)
local oneGem = Gem(hub.frame)
suite.check("the one window has the split gem", oneGem and rawget(oneGem, "join") == false)
local gearGem = Gem(Gear.frame)
suite.check("the Equipment window has the join gem", gearGem and rawget(gearGem, "join") == true
    and rawget(gearGem, "swapKey") == "equipment")
suite.check("on Dungeons in the one window", Gear.hostArea ~= nil and Dungeons:IsShown()
    and Gear.tab == "instances")

-- 2.
oneGem:GetScript("OnClick")(oneGem)
suite.check("split: the choice is off", not SW.On() and ns.db.oneWindow == false)
suite.check("the one window closed", not hub.frame:IsShown())
suite.check("the Equipment window opens on its own, on Dungeons", not Gear.hostArea
    and Gear.frame:IsShown() and Gear.frame:GetParent() == UIParent and Dungeons:IsShown()
    and Gear.tab == "instances")
suite.check("with its own rim and gems again", Gear.frame.titan == nil or Gear.frame.titan:IsShown())
Gear:ShowTab("settings")
SettingsUI:Refresh()
suite.check("the One Window box reads unticked", SettingsUI.controls.oneWindow:GetChecked() == false)

-- 3.
suite.check("Settings is up in Equipment's own window", SettingsUI.frame:IsShown() and not Gear.hostArea)
gearGem:GetScript("OnClick")(gearGem)
suite.check("join: the choice is on", SW.On() and ns.db.oneWindow == true)
suite.check("the one window opens on Equipment", hub.frame:IsShown() and hub.current == hub.entries.equipment)
suite.check("still on Settings, inside it", Gear.hostArea ~= nil and SettingsUI.frame:IsShown()
    and Gear.frame:GetParent() == hub.frame.area and Gear.tab == "settings")
suite.check("the other tabs stay out of the way", not Dungeons:IsShown() and not ns.FindUpgrades:IsShown()
    and not ns.MyGear:IsShown())
SettingsUI:Refresh()
suite.check("the One Window box reads ticked", SettingsUI.controls.oneWindow:GetChecked() == true)

SW.SetOn(false)
_G.BlackthornesWindow = nil
suite.done()
