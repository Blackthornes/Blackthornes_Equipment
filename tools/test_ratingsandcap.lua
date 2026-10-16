-- Hit and crit rating read as the percent they give, the hit cap, and the
-- racial stat bonuses read from the game.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("ratingsandcap")

local ARMOR, MISC, LEATHER = 4, 0, 2

local ITEMS = {
    ["item:1"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = LEATHER,
        stats = { ITEM_MOD_AGILITY_SHORT = 20 } },
    ["item:2"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = LEATHER,
        stats = { ITEM_MOD_AGILITY_SHORT = 10, ITEM_MOD_HIT_RATING_SHORT = 20 } },
    ["item:3"] = { loc = "INVTYPE_FINGER", class = ARMOR, subclass = MISC,
        stats = { ITEM_MOD_CRIT_RATING_SHORT = 14 } },
    ["item:4"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = LEATHER,
        stats = { ITEM_MOD_STAMINA_SHORT = 10 } },
}

local function LoadAs(class, worn, level)
    local ns = env.Load()
    _G.UnitClass = function() return class, class end
    env.InstallItems(ITEMS, worn, {}, level or 60)
    _G.GetHitModifier, _G.GetSpellHitModifier, _G.GetCombatRatingBonus = nil, nil, nil
    return ns
end

-- Ratings: 10 hit rating is 1% at 60, less goes further below.
local ns = LoadAs("HUNTER", {})
local stats = ns.Weights:Normalize({ ITEM_MOD_HIT_RATING_SHORT = 10, ITEM_MOD_CRIT_RATING_SHORT = 28 })
suite.check("10 hit rating is 1% hit at 60", math.abs((stats.anyHit or 0) - 1) < 1e-6, stats.anyHit)
suite.check("28 crit rating is 2% crit at 60", math.abs((stats.anyCrit or 0) - 2) < 1e-6, stats.anyCrit)

ns = LoadAs("HUNTER", {}, 34)
stats = ns.Weights:Normalize({ ITEM_MOD_HIT_RATING_SHORT = 10 })
suite.check("and goes further at level 34", math.abs((stats.anyHit or 0) - 2) < 1e-6, stats.anyHit)

ns = LoadAs("HUNTER", {})
_G.GetCombatRatingBonusForCombatRatingValue = function(index, value)
    if index == 6 then return value / 20 end
end
stats = ns.Weights:Normalize({ ITEM_MOD_HIT_RATING_SHORT = 20 })
suite.check("the client's own rate wins when it gives one",
    math.abs((stats.anyHit or 0) - 1) < 1e-6, stats.anyHit)
_G.GetCombatRatingBonusForCombatRatingValue = nil

-- A caster counts plain crit rating as spell crit.
ns = LoadAs("MAGE", {})
local mage = ns.Weights:ForPlayer()
local score = ns.Compare:ScoreOf("item:3", mage)
suite.check("a mage counts crit rating as spell crit",
    math.abs(score - mage.spellCrit) < 1e-6, score)

-- The hit cap.
local hunter = LoadAs("HUNTER", { [5] = "item:1" }).Weights:ForPlayer()
suite.check("the test weighs hit", (hunter.hit or 0) > 0 and (hunter.agility or 0) > 0)
local agi, hit = hunter.agility, hunter.hit

ns = LoadAs("HUNTER", { [5] = "item:1" })
local result = ns.Compare:Judge("item:2")
suite.check("with no hit reading, hit counts in full",
    result.score and math.abs(result.score - (10 * agi + 2 * hit)) < 1e-6, result.score)

ns = LoadAs("HUNTER", { [5] = "item:1" })
_G.GetHitModifier = function() return 5 end
result = ns.Compare:Judge("item:2")
suite.check("at the cap, the item's hit counts for nothing",
    math.abs(result.score - 10 * agi) < 1e-6, result.score)
suite.check("and it is no upgrade", result.verdict == "downgrade", result.verdict)
suite.check("it says hit was capped", result.hitCapped == true)

ns = LoadAs("HUNTER", { [5] = "item:1" })
_G.GetHitModifier = function() return 4 end
result = ns.Compare:Judge("item:2")
suite.check("1% short of the cap, 1% of its 2% counts",
    math.abs(result.score - (10 * agi + hit)) < 1e-6, result.score)

ns = LoadAs("HUNTER", { [5] = "item:2" })
_G.GetHitModifier = function() return 0 end
_G.GetCombatRatingBonus = function(index) if index == 6 then return 7 end end
result = ns.Compare:Judge("item:1")
suite.check("worn hit past the cap is taken off the score to beat",
    math.abs(result.against - (10 * agi)) < 1e-6, result.against)
suite.check("so dropping it is an upgrade", result.verdict == "upgrade", result.verdict)

suite.check("two weapons still count past 5%, at half",
    math.abs(ns.Compare.HitThatCounts(4, 3, 5, 24, 0.5) - 3) < 1e-6)
suite.check("and nothing past 24%",
    ns.Compare.HitThatCounts(2, 24, 5, 24, 0.5) == 0)

_G.GetHitModifier = function() error("secret value") end
ns = LoadAs("HUNTER", { [5] = "item:1" })
_G.GetHitModifier = function() error("secret value") end
result = ns.Compare:Judge("item:2")
suite.check("a secret value means no cap, not an error",
    result and math.abs(result.score - (10 * agi + 2 * hit)) < 1e-6)

-- Racials.
ns = LoadAs("HUNTER", {})
_G.UnitRace = function() return "Tauren", "Tauren", 6 end
local tauren = ns.Weights:ForPlayer()
local base = ns.Weights:Get("HUNTER", "beast")
suite.check("a Tauren's Stamina is worth 5% more",
    math.abs(tauren.stamina - base.stamina * 1.05) < 1e-6, tauren.stamina)
suite.check("the merged weights are left alone", base.stamina ~= tauren.stamina)
suite.check("and the same table comes back each time", ns.Weights:ForPlayer() == tauren)

ns = LoadAs("HUNTER", {})
_G.UnitRace = function() return "Tauren", "Tauren", 6 end
_G.C_Spell = { GetSpellDescription = function(id)
    if id == 20550 then return "Total Health increased by 7%." end
end }
tauren = ns.Weights:ForPlayer()
base = ns.Weights:Get("HUNTER", "beast")
suite.check("the percent is read off the spell's own text",
    math.abs(tauren.stamina - base.stamina * 1.07) < 1e-6, tauren.stamina)
_G.C_Spell = nil

ns = LoadAs("HUNTER", {})
_G.UnitRace = function() return "Orc", "Orc", 2 end
suite.check("an Orc gets the plain weights",
    ns.Weights:ForPlayer() == ns.Weights:Get("HUNTER", "beast"))

ns = LoadAs("HUNTER", {})
_G.UnitRace = function() return "Human", "Human", 1 end
local human = ns.Weights:ForPlayer()
base = ns.Weights:Get("HUNTER", "beast")
suite.check("a Human's Spirit is worth 5% more",
    math.abs((human.spirit or 0) - (base.spirit or 0) * 1.05) < 1e-6)

suite.done()
