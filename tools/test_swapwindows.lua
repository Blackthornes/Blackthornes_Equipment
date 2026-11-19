-- The swap gem on Equipment's windows and the one window (UI/SharedWindow.lua
-- AddSwap and Swap, FinderUI's tab, show and hide; the owner said build it,
-- 2026-11-19).
--
-- What must hold:
--   1. The gear window and each tab's window carry a join gem; the one
--      window a split gem.
--   2. Split from the one window on Dungeon Quests: the one window closes,
--      Dungeon Quests opens on its own, and the One Window box reads
--      unticked.
--   3. Join from the own Settings window: the one window opens on
--      Equipment, still on Settings, and the box reads ticked.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("swapwindows")

_G.BlackthornesWindow = nil
local ns = env.Load()
local Finder, SettingsUI, SW = ns.FinderUI, ns.SettingsUI, ns.SharedWindow

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
Finder:ShowTab("dungeons")
HidesLikeTheGame(hub.frame)
local oneGem = Gem(hub.frame)
suite.check("the one window has the split gem", oneGem and rawget(oneGem, "join") == false)
SettingsUI:Build()
ns.DungeonLootUI:Build()
Finder:Build()
for _, frame in ipairs(Finder:TabFrames()) do
    local gem = Gem(frame)
    suite.check("a tab's window has the join gem", gem and rawget(gem, "join") == true
        and rawget(gem, "swapKey") == "equipment")
end
suite.check("on Dungeon Quests in the one window", Finder:Hosted() and ns.DungeonQuestsUI.frame:IsShown())

-- 2.
oneGem:GetScript("OnClick")(oneGem)
suite.check("split: the choice is off", not SW.On() and ns.db.oneWindow == false)
suite.check("the one window closed", not hub.frame:IsShown())
local dq = ns.DungeonQuestsUI.frame
suite.check("Dungeon Quests opens on its own", not Finder:Hosted() and dq:IsShown() and dq:GetParent() == UIParent)
suite.check("with its own rim and gems again", dq.titan == nil or dq.titan:IsShown())
Finder:ShowTab("settings")
SettingsUI:Refresh()
suite.check("the One Window box reads unticked", SettingsUI.controls.oneWindow:GetChecked() == false)

-- 3.
local settingsGem = Gem(SettingsUI.frame)
suite.check("Settings is up on its own", SettingsUI.frame:IsShown() and SettingsUI.frame:GetParent() == UIParent)
settingsGem:GetScript("OnClick")(settingsGem)
suite.check("join: the choice is on", SW.On() and ns.db.oneWindow == true)
suite.check("the one window opens on Equipment", hub.frame:IsShown() and hub.current == hub.entries.equipment)
suite.check("still on Settings, inside it", Finder:Hosted() and SettingsUI.frame:IsShown()
    and SettingsUI.frame:GetParent() == hub.frame.area)
suite.check("the other tabs stay out of the way", not dq:IsShown() and not (Finder.frame and Finder.frame:IsShown()))
SettingsUI:Refresh()
suite.check("the One Window box reads ticked", SettingsUI.controls.oneWindow:GetChecked() == true)

SW.SetOn(false)
_G.BlackthornesWindow = nil
suite.done()
