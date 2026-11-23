-- Our windows sit on the HIGH layer, under the game's own confirm boxes
-- (DIALOG), so a pop-up the game opens never ends up behind one of ours.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("strata")

local ns = env.Load({ ui = true })

-- The Equipment window holds every tab; the old windows are gone.
local windows = { "GearWindow", "SlotUpgrades" }
for _, name in ipairs(windows) do
    local module = ns[name] or (ns.modules and ns.modules[name])
    local ok, frame = pcall(function() return module:Build() end)
    frame = ok and (frame or module.frame) or nil
    suite.check(name .. " builds", frame ~= nil, tostring(frame))
    if frame then
        suite.check(name .. " sits under the game's pop-ups",
            frame:GetFrameStrata() == "HIGH", frame:GetFrameStrata())
    end
end

suite.done()
