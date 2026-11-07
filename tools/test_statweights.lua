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

suite.done()
