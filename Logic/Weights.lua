-- Blackthornes Equipment -- Logic/Weights.lua
-- How much each stat is worth to a class and spec, and which spec the player
-- is judged as.
--
-- WoW: Forever hunters have classic-style talent trees (Beast Mastery,
-- Marksmanship, Survival) rather than a specialization picked from a menu, so
-- "spec" here means the tree with the most points in it. Below level 10 there
-- are no points, and the class default applies until the player picks one
-- with /beq spec.
--
-- The numbers are a starting guess for levelling, per point of the stat with
-- Agility as 1. Crit and hit are per 1%, the way classic-era items print
-- them. /beq probe shows what the client really reports so they can be tuned.

local _, ns = ...

local Weights = ns.NewModule("Weights")

--------------------------------------------------------------------------------
-- The weights
--------------------------------------------------------------------------------

-- Stats a weight can name. Anything else the client reports is ignored.
--   dps is weapon damage per second; Score applies it as rangedDps or
--   meleeDps depending on the weapon, because a hunter's bow matters far more
--   than a sword to Beast Mastery and far less to Survival.
local SPECS = {
    HUNTER = {
        order = { "beast", "marks", "survival" },
        default = "beast",
        beast = {
            name = "Beast Mastery",
            weights = {
                agility = 1.0, strength = 0.1, stamina = 0.5, intellect = 0.25,
                spirit = 0.1, attackPower = 0.35, rangedAttackPower = 0.45,
                crit = 12, hit = 10, armor = 0.02,
                rangedDps = 6, meleeDps = 0.5,
            },
        },
        marks = {
            name = "Marksmanship",
            weights = {
                agility = 1.0, strength = 0.05, stamina = 0.35, intellect = 0.3,
                spirit = 0.05, attackPower = 0.3, rangedAttackPower = 0.5,
                crit = 15, hit = 14, armor = 0.01,
                rangedDps = 8, meleeDps = 0.3,
            },
        },
        survival = {
            -- Survival fights in melee on Forever (Mongoose Bite, bleeds, traps),
            -- so strength, melee attack power and the melee weapon count.
            name = "Survival",
            weights = {
                agility = 1.0, strength = 0.35, stamina = 0.5, intellect = 0.2,
                spirit = 0.1, attackPower = 0.55, rangedAttackPower = 0.3,
                crit = 14, hit = 12, armor = 0.03,
                rangedDps = 3, meleeDps = 5,
            },
        },
    },
}

-- Names a player can type after /beq spec.
local ALIASES = {
    beast = "beast", bm = "beast", ["beast mastery"] = "beast", beastmastery = "beast",
    marks = "marks", mm = "marks", marksmanship = "marks",
    survival = "survival", sv = "survival", surv = "survival",
}

-- What the client calls each stat, as returned by GetItemStats, mapped to the
-- names above. Both the modern ITEM_MOD keys and their ranged variants are
-- listed; /beq probe prints any key that is missing from here.
local STAT_KEYS = {
    ["ITEM_MOD_AGILITY_SHORT"] = "agility",
    ["ITEM_MOD_STRENGTH_SHORT"] = "strength",
    ["ITEM_MOD_STAMINA_SHORT"] = "stamina",
    ["ITEM_MOD_INTELLECT_SHORT"] = "intellect",
    ["ITEM_MOD_SPIRIT_SHORT"] = "spirit",
    ["ITEM_MOD_ATTACK_POWER_SHORT"] = "attackPower",
    ["ITEM_MOD_RANGED_ATTACK_POWER_SHORT"] = "rangedAttackPower",
    ["ITEM_MOD_CRIT_RATING_SHORT"] = "crit",
    ["ITEM_MOD_CRIT_RANGED_RATING_SHORT"] = "crit",
    ["ITEM_MOD_CRIT_MELEE_RATING_SHORT"] = "crit",
    ["ITEM_MOD_HIT_RATING_SHORT"] = "hit",
    ["ITEM_MOD_HIT_RANGED_RATING_SHORT"] = "hit",
    ["ITEM_MOD_HIT_MELEE_RATING_SHORT"] = "hit",
    ["RESISTANCE0_NAME"] = "armor",
    ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = "dps",
}

Weights.SPECS = SPECS
Weights.STAT_KEYS = STAT_KEYS

--------------------------------------------------------------------------------
-- Reading the player
--------------------------------------------------------------------------------

--- The player's class token, "HUNTER" say, or nil if the client will not say.
function Weights:PlayerClass()
    if type(UnitClass) ~= "function" then return nil end
    local ok, _, token = pcall(UnitClass, "player")
    if ok and type(token) == "string" then return token end
    return nil
end

--- Points spent in each talent tree, in the client's tab order, or nil when
-- the client has no talent trees to read.
--
-- GetTalentTabInfo has two shapes in the wild: the classic one starts with the
-- tree's name and has the points third; the later one starts with a numeric
-- id and has them fifth. Forever is a modern engine running classic trees, so
-- both are handled rather than guessed.
function Weights:TreePoints()
    if type(GetNumTalentTabs) ~= "function" or type(GetTalentTabInfo) ~= "function" then
        return nil
    end

    local okCount, count = pcall(GetNumTalentTabs)
    if not okCount or type(count) ~= "number" or count < 1 then return nil end

    local points = {}
    for tab = 1, count do
        local info = { pcall(GetTalentTabInfo, tab) }
        if not info[1] then return nil end

        local spent
        if type(info[2]) == "number" then
            spent = info[6]     -- id, name, description, icon, pointsSpent
        else
            spent = info[4]     -- name, icon, pointsSpent
        end
        points[tab] = type(spent) == "number" and spent or 0
    end
    return points
end

--- The spec this character is judged as, and why: "picked", "talents" or
--- "default". Nil when there are no weights for the class yet.
function Weights:CurrentSpec()
    local class = self:PlayerClass()
    local specs = class and SPECS[class]
    if not specs then return nil, nil, class end

    local picked = ns.charDB and ns.charDB.spec
    if picked and specs[picked] then
        return picked, "picked", class
    end

    local points = self:TreePoints()
    if points then
        local best, bestPoints, tied = nil, 0, false
        for tab, spent in ipairs(points) do
            if spent > bestPoints then
                best, bestPoints, tied = tab, spent, false
            elseif spent == bestPoints and spent > 0 then
                tied = true
            end
        end
        if best and not tied and specs.order[best] then
            return specs.order[best], "talents", class
        end
    end

    return specs.default, "default", class
end

--- The weights to judge this character's gear by, or nil for a class that
--- has none yet.
function Weights:ForPlayer()
    local spec, _, class = self:CurrentSpec()
    if not spec then return nil end
    return SPECS[class][spec].weights, spec
end

--- Turn a spec a player typed into its key, or nil.
function Weights:ResolveSpec(text)
    text = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    return ALIASES[text]
end

--------------------------------------------------------------------------------
-- Scoring
--------------------------------------------------------------------------------

--- Convert what GetItemStats returned into the names above. Keys this addon
--- does not know are returned separately so the probe can show them.
function Weights:Normalize(clientStats)
    local stats, unknown = {}, {}
    for key, value in pairs(clientStats or {}) do
        local name = STAT_KEYS[key]
        if name and type(value) == "number" then
            stats[name] = (stats[name] or 0) + value
        else
            unknown[#unknown + 1] = key
        end
    end
    table.sort(unknown)
    return stats, unknown
end

--- One number for how good a set of stats is: each stat times its weight.
-- `ranged` says whether weapon dps counts as a ranged or a melee weapon.
function Weights:Score(stats, weights, ranged)
    local score = 0
    for name, value in pairs(stats or {}) do
        local weight
        if name == "dps" then
            weight = ranged and weights.rangedDps or weights.meleeDps
        else
            weight = weights[name]
        end
        if weight then
            score = score + value * weight
        end
    end
    return score
end

--------------------------------------------------------------------------------
-- /beq spec
--------------------------------------------------------------------------------

local WHY = {
    picked = "you picked it",
    talents = "from your talent points",
    default = "the default until you spend talent points",
}

local function ShowSpec()
    local spec, why, class = Weights:CurrentSpec()
    if not spec then
        ns.Print(("no stat weights for %s yet"):format(class or "this class"))
        return
    end
    ns.Print(("judging gear as |c%s%s|r (%s)"):format(
        ns.COLORS.accent, SPECS[class][spec].name, WHY[why]))
end

ns.RegisterCommand("spec", "show the spec gear is judged for, or pick one: bm, mm, sv or auto",
    function(rest)
        rest = (rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        if rest == "" then
            ShowSpec()
            return
        end

        if rest == "auto" then
            ns.charDB.spec = nil
            ShowSpec()
            return
        end

        local spec = Weights:ResolveSpec(rest)
        local class = Weights:PlayerClass()
        if not spec or not (class and SPECS[class] and SPECS[class][spec]) then
            ns.Warn(("not a spec: %s (try bm, mm, sv or auto)"):format(rest))
            return
        end

        ns.charDB.spec = spec
        ShowSpec()
    end)
