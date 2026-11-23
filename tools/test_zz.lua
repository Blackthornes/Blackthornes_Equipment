local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER" end
local ok, err = pcall(ns.HandleSlash, "weights")
print("slash", ok, err)
local S, W, G = ns.SettingsUI, ns.WeightsPage, ns.GearWindow
print("gear frame", G.frame, G.frame and G.frame:IsShown(), G.tab)
print("settings frame", S.frame, S.frame and S.frame:IsShown(), S:IsShown())
print("pages.shown", S.pages and S.pages.shown, ns.db.settingsPage, W.frame, W:IsShown())
