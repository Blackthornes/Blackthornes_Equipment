-- A skill point is not a new skill.
--
-- Each skill point (a craft, a node, a weapon swing) fires
-- SKILL_LINES_CHANGED, and the profession window says its list changed after
-- every craft. Each threw away every upgrade verdict, started a new upgrade
-- scan and walked every recipe of every character in Tradeskills: a hitch on
-- some finished crafts (2026-10-11). Now only a skill learned or dropped is
-- passed on, and a craft only has the skill levels read again.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("skillpoint")

local ns = env.Load()

local skills = { { "Tailoring", 50 }, { "Swords", 20 } }
_G.GetNumSkillLines = function() return #skills end
_G.GetSkillLineInfo = function(index)
    local skill = skills[index]
    return skill[1], false, false, skill[2]
end

local function Fire(event)
    ns.eventFrame:GetScript("OnEvent")(ns.eventFrame, event)
end

-- Make sure the modules listen, as they do after login.
for _, name in ipairs({ "Crafting", "Finder" }) do
    if ns[name].OnEnable then pcall(ns[name].OnEnable, ns[name]) end
end

Fire("SKILL_LINES_CHANGED")
local generation = ns.Finder.judgeGeneration or 0

skills[1][2] = 51
Fire("SKILL_LINES_CHANGED")
suite.check("a skill point keeps the upgrade verdicts", (ns.Finder.judgeGeneration or 0) == generation)

skills[3] = { "Leatherworking", 1 }
Fire("SKILL_LINES_CHANGED")
suite.check("a new skill throws them away", (ns.Finder.judgeGeneration or 0) == generation + 1)

skills[3] = nil
Fire("SKILL_LINES_CHANGED")
suite.check("and so does dropping one", (ns.Finder.judgeGeneration or 0) == generation + 2)

-- A craft: the skill levels are read again, who knows what stays.
local known = { marker = true }
ns.Crafting.known, ns.Crafting.stale = known, false
Fire("TRADE_SKILL_LIST_UPDATE")
suite.check("a craft keeps who knows which recipe", ns.Crafting.known == known)
suite.check("and reads the skill levels again", ns.Crafting.stale == true)
Fire("NEW_RECIPE_LEARNED")
suite.check("a new recipe forgets who knows what", ns.Crafting.known == nil)

-- Nothing the client names: nothing is held back.
local saved = _G.GetNumSkillLines
_G.GetNumSkillLines = function() return 0 end
local gen = ns.Finder.judgeGeneration or 0
Fire("SKILL_LINES_CHANGED")
Fire("SKILL_LINES_CHANGED")
suite.check("a client that names no skills passes every event on",
    (ns.Finder.judgeGeneration or 0) >= gen + 1)
_G.GetNumSkillLines = saved

suite.done()
