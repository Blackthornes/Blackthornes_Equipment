-- Stat weights checked against Forever's class guides (2026-11-07): the
-- spell hit cap, haste and expertise, and the numbers that moved.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("statweights")

local ns = env.Load()
local SPECS = ns.Weights.SPECS

-- The spell hit cap is Forever's 4%, weapons stay at 5%.
suite.check("spells stop missing at 4% hit", ns.Compare.HIT_CAP.spell == 4, ns.Compare.HIT_CAP.spell)
suite.check("weapons still stop missing at 5%", ns.Compare.HIT_CAP.melee == 5)
suite.check("at 3% hit, 1% more still counts in full",
    math.abs(ns.Compare.HitThatCounts(1, 3, 4) - 1) < 1e-6)

-- The numbers that moved.
local destro = SPECS.WARLOCK.destro.weights
suite.check("Destruction weighs crit below hit", destro.spellCrit == 8 and destro.spellHit == 12)
local ret = SPECS.PALADIN.ret.weights
suite.check("Retribution weighs hit 14", ret.hit == 14)
suite.check("Retribution puts agility with intellect", ret.agility == 0.3)
suite.check("Shadow weighs crit 6", SPECS.PRIEST.shadow.weights.spellCrit == 6)
local enh = SPECS.SHAMAN.enhancement.weights
suite.check("Enhancement still leans on strength",
    enh.strength == 1.0 and enh.agility == 0.7 and enh.intellect == 0.3)

-- Haste and expertise read off gear as the percent or points they give.
env.InstallItems({}, {}, {}, 60)
_G.GetHitModifier, _G.GetSpellHitModifier, _G.GetCombatRatingBonus = nil, nil, nil
_G.GetCombatRatingBonusForCombatRatingValue, _G.GetCombatRating = nil, nil
ns.Weights:ForgetRatings()
local stats = ns.Weights:Normalize({ ITEM_MOD_HASTE_RATING_SHORT = 10,
    ITEM_MOD_EXPERTISE_RATING_SHORT = 5 })
suite.check("10 haste rating is 1% haste at 60", math.abs((stats.haste or 0) - 1) < 1e-6, stats.haste)
suite.check("5 expertise rating is 2 expertise at 60", math.abs((stats.expertise or 0) - 2) < 1e-6, stats.expertise)
stats = ns.Weights:Normalize({ ITEM_MOD_HASTE_SPELL_RATING_SHORT = 10 })
suite.check("spell haste rating counts as haste", math.abs((stats.haste or 0) - 1) < 1e-6, stats.haste)

-- Haste is worth what the spec's crit is; expertise a quarter of weapon hit.
suite.check("Destruction weighs haste like its crit", destro.haste == 8, destro.haste)
suite.check("Retribution weighs expertise 3.5", ret.expertise == 3.5, ret.expertise)
suite.check("casters weigh no expertise", destro.expertise == nil)
suite.check("hunters weigh no expertise", SPECS.HUNTER.beast.weights.expertise == nil)
suite.check("a tank with no crit weight weighs no haste", SPECS.PALADIN.prot.weights.haste == nil)

local inOrder = {}
for _, row in ipairs(ns.Weights.STAT_ORDER or {}) do inOrder[row.key] = true end
suite.check("the weights window lists haste and expertise", inOrder.haste and inOrder.expertise)

suite.done()
