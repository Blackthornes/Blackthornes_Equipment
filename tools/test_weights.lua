-- Hunter stat weights, and working out which spec a character is judged as
-- from WoW: Forever's classic-style talent trees.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("weights")

--- Load the addon as a character of `class` with `points` in each tree.
-- `shape` is "classic" (name, icon, points) or "modern" (id, name, desc,
-- icon, points), the two ways GetTalentTabInfo answers.
local function LoadAs(class, points, shape)
    local ns = env.Load()
    _G.UnitClass = function() return class, class end
    if points then
        _G.GetNumTalentTabs = function() return #points end
        _G.GetTalentTabInfo = function(tab)
            if shape == "modern" then
                return 100 + tab, "Tree " .. tab, "", "icon", points[tab]
            end
            return "Tree " .. tab, "icon", points[tab]
        end
    else
        _G.GetNumTalentTabs = nil
        _G.GetTalentTabInfo = nil
    end
    return ns
end

local ns = LoadAs("HUNTER", nil)
local spec, why = ns.Weights:CurrentSpec()
suite.check("a hunter with no trees to read is Beast Mastery", spec == "beast", spec)
suite.check("and says it is the default", why == "default", why)

ns = LoadAs("HUNTER", { 0, 0, 0 })
spec, why = ns.Weights:CurrentSpec()
suite.check("no points spent is still the default", spec == "beast" and why == "default", why)

ns = LoadAs("HUNTER", { 2, 11, 0 })
spec, why = ns.Weights:CurrentSpec()
suite.check("most points in the second tree is Marksmanship", spec == "marks", spec)
suite.check("read from talents", why == "talents", why)

ns = LoadAs("HUNTER", { 0, 1, 14 }, "modern")
spec = ns.Weights:CurrentSpec()
suite.check("the modern tab shape is read too", spec == "survival", spec)

ns = LoadAs("HUNTER", { 5, 5, 0 })
spec, why = ns.Weights:CurrentSpec()
suite.check("a tie falls back to the default", spec == "beast" and why == "default", why)

_G.GetTalentTabInfo = function() error("secret value") end
spec, why = ns.Weights:CurrentSpec()
suite.check("a client that raises does not break it", spec == "beast" and why == "default", why)

-- Picking a spec wins over talents, and auto hands it back.
ns = LoadAs("HUNTER", { 0, 0, 20 })
ns.HandleSlash("spec mm")
spec, why = ns.Weights:CurrentSpec()
suite.check("/beq spec mm picks Marksmanship", spec == "marks" and why == "picked", why)
suite.check("and remembers it per character", ns.charDB.spec == "marks", ns.charDB.spec)
suite.check("and says so", env.ChatText():find("Marksmanship", 1, true), env.ChatText())

ns.HandleSlash("spec auto")
spec, why = ns.Weights:CurrentSpec()
suite.check("/beq spec auto goes back to talents", spec == "survival" and why == "talents", why)

env.chat = {}
ns.HandleSlash("spec tank")
suite.check("a spec that is not one is refused",
    env.ChatText():find("not a spec: tank", 1, true), env.ChatText())
suite.check("and nothing is saved", ns.charDB.spec == nil)

ns = LoadAs("WARLOCK", nil)
suite.check("a class without weights has none", ns.Weights:ForPlayer() == nil)
env.chat = {}
ns.HandleSlash("spec")
suite.check("and /beq spec says so",
    env.ChatText():find("no stat weights for WARLOCK", 1, true), env.ChatText())

-- Scoring.
ns = LoadAs("HUNTER", nil)
local stats, unknown = ns.Weights:Normalize({
    ITEM_MOD_AGILITY_SHORT = 5,
    ITEM_MOD_STAMINA_SHORT = 4,
    ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 10,
    ITEM_MOD_SOMETHING_NEW = 3,
})
suite.check("known stats are renamed", stats.agility == 5 and stats.stamina == 4 and stats.dps == 10)
suite.check("unknown ones are listed, not scored",
    #unknown == 1 and unknown[1] == "ITEM_MOD_SOMETHING_NEW", unknown[1])

local weights = ns.Weights:ForPlayer()
local bow = ns.Weights:Score({ agility = 5, dps = 10 }, weights, true)
local sword = ns.Weights:Score({ agility = 5, dps = 10 }, weights, false)
suite.check("to Beast Mastery a bow's dps is worth more than a sword's", bow > sword,
    bow .. " vs " .. sword)

local sv = ns.Weights.SPECS.HUNTER.survival.weights
suite.check("to Survival the sword is worth more",
    ns.Weights:Score({ dps = 10 }, sv, false) > ns.Weights:Score({ dps = 10 }, sv, true))

suite.check("agility beats the same points of stamina for every hunter spec", (function()
    for _, key in ipairs(ns.Weights.SPECS.HUNTER.order) do
        local w = ns.Weights.SPECS.HUNTER[key].weights
        if not (w.agility > w.stamina) then return false end
    end
    return true
end)())

suite.done()
