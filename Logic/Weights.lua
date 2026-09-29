-- Blackthornes Equipment -- Logic/Weights.lua
-- How much each stat is worth to a class and spec, and which spec the player
-- is judged as.
--
-- WoW: Forever hunters have classic-style talent trees (Beast Mastery,
-- Marksmanship, Survival) rather than a specialization picked from a menu, so
-- "spec" here means the tree with the most points in it. Below level 10 there
-- are no points, and the class default applies until the player picks one
-- with /beq spec. Forever has no classic talent-tab calls; its talents are one
-- trait tree per class (C_ClassTalents, C_Traits), so the points are counted
-- per spec from where each talent sits in that tree.
--
-- Every classic class has weights: warrior, paladin, hunter, rogue, priest,
-- shaman, mage, warlock and druid. The numbers are a starting guess for
-- levelling, per point of the stat with each spec's main stat as 1. Crit and
-- hit are per 1%, the way classic-era items print them. /beq probe shows what
-- the client really reports so they can be tuned. Only the hunter's and the
-- warlock's talent layouts have been checked on Forever; see CLASSIC_COLUMNS.

local _, ns = ...

local Weights = ns.NewModule("Weights")

--------------------------------------------------------------------------------
-- The weights
--------------------------------------------------------------------------------

-- Stats a weight can name. Anything else the client reports is ignored.
--   dps is weapon damage per second; Score applies it as rangedDps or
--   meleeDps depending on the weapon, because a hunter's bow matters far more
--   than a sword to Beast Mastery and far less to Survival.
-- Where a class's three specs split in its talent tree, by a talent's posX.
-- Measured on the hunter; assumed for every class until probed.
local CLASSIC_COLUMNS = { 4000, 8000 }

local SPECS = {
    HUNTER = {
        order = { "beast", "marks", "survival" },
        default = "beast",
        -- Forever puts all three hunter specs in one talent tree, side by
        -- side. A talent left of 4000 is Beast Mastery (Focused Fire,
        -- Endurance Training), left of 8000 Marksmanship (Hawk Eye, Lone
        -- Wolf), and anything further right Survival (Entrapment, Deflection,
        -- Lightning Reflexes, which sits far out at 102800). Read with
        -- /beq probe on 2026-09-29; see docs/FOREVER_API_FINDINGS.md.
        columns = CLASSIC_COLUMNS,
        -- What a hunter can equip, by the client's item subclass, and the
        -- level each opens at (0 for any level). Classic rules: mail from 40,
        -- no plate, shields, maces or wands. Not yet checked on Forever; if it
        -- differs, the tooltip will say "can't use" on something a hunter can
        -- wear.
        armor = {
            [0] = 0,    -- miscellaneous: rings, necks, trinkets
            [1] = 0,    -- cloth (cloaks are cloth)
            [2] = 0,    -- leather
            [3] = 40,   -- mail
        },
        weapons = {
            [0] = 0, [1] = 0,       -- one- and two-handed axes
            [2] = 0, [3] = 0,       -- bows, guns
            [6] = 0,                -- polearms
            [7] = 0, [8] = 0,       -- one- and two-handed swords
            [10] = 0,               -- staves
            [13] = 0,               -- fist weapons
            [15] = 0,               -- daggers
            [16] = 0,               -- thrown
            [18] = 0,               -- crossbows
        },
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

    ----------------------------------------------------------------------------
    -- The other eight classic classes. Only the warlock's talent tree has
    -- been probed on Forever (split at 4000 and 8000 in classic's order, as assumed);
    -- the rest are assumed to sit side by side like the hunter's, in classic's tab order, split at the same columns. /beq probe
    -- on a character of the class shows its layout, and CLASSIC_COLUMNS is
    -- replaced per class once that is known. Equip rules are classic's too.
    ----------------------------------------------------------------------------

    WARRIOR = {
        order = { "arms", "fury", "prot" },
        default = "arms",
        columns = CLASSIC_COLUMNS,
        armor = { [0] = 0, [1] = 0, [2] = 0, [3] = 0, [4] = 40, [6] = 0 },
        weapons = {
            [0] = 0, [1] = 0, [2] = 0, [3] = 0, [4] = 0, [5] = 0, [6] = 0,
            [7] = 0, [8] = 0, [10] = 0, [13] = 0, [15] = 0, [16] = 0, [18] = 0,
        },
        arms = {
            name = "Arms",
            weights = {
                strength = 1.0, agility = 0.6, stamina = 0.5, attackPower = 0.5,
                crit = 14, hit = 12, armor = 0.02, meleeDps = 7, rangedDps = 0.3,
            },
        },
        fury = {
            name = "Fury",
            weights = {
                strength = 1.0, agility = 0.7, stamina = 0.4, attackPower = 0.5,
                crit = 16, hit = 16, armor = 0.01, meleeDps = 5, rangedDps = 0.3,
            },
        },
        prot = {
            name = "Protection",
            weights = {
                stamina = 1.0, strength = 0.6, agility = 0.6, armor = 0.1,
                defense = 1.2, dodge = 12, parry = 10, block = 6, blockValue = 0.4,
                hit = 6, attackPower = 0.2, meleeDps = 2, rangedDps = 0.2,
            },
        },
    },

    PALADIN = {
        order = { "holy", "prot", "ret" },
        default = "ret",
        columns = CLASSIC_COLUMNS,
        -- 7 is a libram.
        armor = { [0] = 0, [1] = 0, [2] = 0, [3] = 0, [4] = 40, [6] = 0, [7] = 0 },
        weapons = { [0] = 0, [1] = 0, [4] = 0, [5] = 0, [6] = 0, [7] = 0, [8] = 0 },
        holy = {
            name = "Holy",
            weights = {
                intellect = 1.0, healing = 0.8, spellPower = 0.9, spirit = 0.5,
                stamina = 0.3, mp5 = 2, spellCrit = 10, armor = 0.005,
            },
        },
        prot = {
            name = "Protection",
            weights = {
                stamina = 1.0, strength = 0.5, agility = 0.4, intellect = 0.3,
                armor = 0.08, defense = 1.0, dodge = 10, parry = 8, block = 6,
                blockValue = 0.3, spellPower = 0.5, meleeDps = 2,
            },
        },
        ret = {
            name = "Retribution",
            weights = {
                strength = 1.0, agility = 0.5, stamina = 0.5, intellect = 0.3,
                attackPower = 0.45, crit = 12, hit = 12, spellPower = 0.3,
                armor = 0.02, meleeDps = 7,
            },
        },
    },

    ROGUE = {
        order = { "assassination", "combat", "sub" },
        default = "combat",
        columns = CLASSIC_COLUMNS,
        armor = { [0] = 0, [1] = 0, [2] = 0 },
        weapons = {
            [2] = 0, [3] = 0, [4] = 0, [7] = 0, [13] = 0, [15] = 0, [16] = 0, [18] = 0,
        },
        assassination = {
            name = "Assassination",
            weights = {
                agility = 1.0, strength = 0.5, stamina = 0.4, attackPower = 0.5,
                crit = 15, hit = 14, armor = 0.01, meleeDps = 5, rangedDps = 0.3,
            },
        },
        combat = {
            name = "Combat",
            weights = {
                agility = 1.0, strength = 0.5, stamina = 0.4, attackPower = 0.5,
                crit = 13, hit = 16, armor = 0.01, meleeDps = 6, rangedDps = 0.3,
            },
        },
        sub = {
            name = "Subtlety",
            weights = {
                agility = 1.0, strength = 0.5, stamina = 0.5, attackPower = 0.5,
                crit = 14, hit = 13, armor = 0.02, meleeDps = 5, rangedDps = 0.3,
            },
        },
    },

    PRIEST = {
        order = { "disc", "holy", "shadow" },
        default = "shadow",
        columns = CLASSIC_COLUMNS,
        armor = { [0] = 0, [1] = 0 },
        weapons = { [4] = 0, [10] = 0, [15] = 0, [19] = 0 },
        disc = {
            name = "Discipline",
            weights = {
                intellect = 1.0, spirit = 0.7, stamina = 0.4, healing = 0.8,
                spellPower = 0.8, mp5 = 2, spellCrit = 8, rangedDps = 2,
            },
        },
        holy = {
            name = "Holy",
            weights = {
                intellect = 1.0, spirit = 0.9, stamina = 0.3, healing = 1.0,
                spellPower = 0.8, mp5 = 2.5, spellCrit = 10, rangedDps = 2,
            },
        },
        shadow = {
            name = "Shadow",
            weights = {
                intellect = 0.8, spirit = 0.8, stamina = 0.6, spellPower = 1.1,
                spellHit = 12, spellCrit = 4, mp5 = 1.5, rangedDps = 3,
            },
        },
    },

    SHAMAN = {
        order = { "elemental", "enhancement", "resto" },
        default = "enhancement",
        columns = CLASSIC_COLUMNS,
        -- 9 is a totem.
        armor = { [0] = 0, [1] = 0, [2] = 0, [3] = 40, [6] = 0, [9] = 0 },
        weapons = { [0] = 0, [1] = 0, [4] = 0, [5] = 0, [10] = 0, [13] = 0, [15] = 0 },
        elemental = {
            name = "Elemental",
            weights = {
                intellect = 1.0, stamina = 0.5, spirit = 0.3, spellPower = 1.1,
                spellCrit = 12, spellHit = 12, mp5 = 2, armor = 0.01, meleeDps = 1,
            },
        },
        enhancement = {
            name = "Enhancement",
            weights = {
                strength = 1.0, agility = 0.7, stamina = 0.5, intellect = 0.3,
                attackPower = 0.5, crit = 14, hit = 12, armor = 0.02, meleeDps = 7,
            },
        },
        resto = {
            name = "Restoration",
            weights = {
                intellect = 1.0, spirit = 0.3, stamina = 0.4, healing = 1.0,
                spellPower = 0.8, mp5 = 3, spellCrit = 10,
            },
        },
    },

    MAGE = {
        order = { "arcane", "fire", "frost" },
        default = "frost",
        columns = CLASSIC_COLUMNS,
        armor = { [0] = 0, [1] = 0 },
        weapons = { [7] = 0, [10] = 0, [15] = 0, [19] = 0 },
        arcane = {
            name = "Arcane",
            weights = {
                intellect = 1.0, spirit = 0.4, stamina = 0.5, spellPower = 1.2,
                spellCrit = 10, spellHit = 12, mp5 = 1.5, rangedDps = 3,
            },
        },
        fire = {
            name = "Fire",
            weights = {
                intellect = 0.9, spirit = 0.4, stamina = 0.5, spellPower = 1.2,
                spellCrit = 14, spellHit = 12, mp5 = 1.5, rangedDps = 3,
            },
        },
        frost = {
            name = "Frost",
            weights = {
                intellect = 0.9, spirit = 0.5, stamina = 0.6, spellPower = 1.2,
                spellCrit = 10, spellHit = 12, mp5 = 1.5, rangedDps = 3,
            },
        },
    },

    WARLOCK = {
        order = { "affliction", "demo", "destro" },
        default = "affliction",
        columns = CLASSIC_COLUMNS,
        armor = { [0] = 0, [1] = 0 },
        weapons = { [7] = 0, [10] = 0, [15] = 0, [19] = 0 },
        affliction = {
            name = "Affliction",
            weights = {
                stamina = 0.8, intellect = 0.8, spirit = 0.4, spellPower = 1.2,
                spellHit = 12, spellCrit = 5, mp5 = 1, rangedDps = 3,
            },
        },
        demo = {
            name = "Demonology",
            weights = {
                stamina = 1.0, intellect = 0.8, spirit = 0.4, spellPower = 1.1,
                spellHit = 12, spellCrit = 5, mp5 = 1, rangedDps = 3,
            },
        },
        destro = {
            name = "Destruction",
            weights = {
                stamina = 0.7, intellect = 0.8, spirit = 0.3, spellPower = 1.2,
                spellHit = 12, spellCrit = 12, mp5 = 1, rangedDps = 3,
            },
        },
    },

    DRUID = {
        order = { "balance", "feral", "resto" },
        default = "feral",
        columns = CLASSIC_COLUMNS,
        -- 8 is an idol.
        armor = { [0] = 0, [1] = 0, [2] = 0, [8] = 0 },
        weapons = { [4] = 0, [5] = 0, [10] = 0, [13] = 0, [15] = 0 },
        balance = {
            name = "Balance",
            weights = {
                intellect = 1.0, spirit = 0.5, stamina = 0.4, spellPower = 1.1,
                spellCrit = 10, spellHit = 10, mp5 = 2,
            },
        },
        feral = {
            -- Cat and bear forms ignore the weapon's damage, so it counts for
            -- nothing here.
            name = "Feral Combat",
            weights = {
                agility = 1.0, strength = 1.0, stamina = 0.8, attackPower = 0.5,
                crit = 14, hit = 12, armor = 0.05, dodge = 6, defense = 0.4,
            },
        },
        resto = {
            name = "Restoration",
            weights = {
                intellect = 1.0, spirit = 0.8, stamina = 0.4, healing = 1.0,
                spellPower = 0.8, mp5 = 2.5, spellCrit = 8,
            },
        },
    },
}

-- Names a player can type after /beq spec. One list for every class: a name
-- only counts when the player's own class has that spec.
local ALIASES = {
    beast = "beast", bm = "beast", ["beast mastery"] = "beast", beastmastery = "beast",
    marks = "marks", mm = "marks", marksmanship = "marks",
    survival = "survival", sv = "survival", surv = "survival",
    arms = "arms", fury = "fury",
    prot = "prot", protection = "prot", tank = "prot",
    holy = "holy", ret = "ret", retribution = "ret",
    assassination = "assassination", assa = "assassination", mut = "assassination",
    combat = "combat", sub = "sub", subtlety = "sub",
    disc = "disc", discipline = "disc", shadow = "shadow", spriest = "shadow",
    elemental = "elemental", ele = "elemental",
    enhancement = "enhancement", enh = "enhancement", enhance = "enhancement",
    resto = "resto", restoration = "resto",
    arcane = "arcane", fire = "fire", frost = "frost",
    affliction = "affliction", affli = "affliction", aff = "affliction",
    demo = "demo", demonology = "demo", destro = "destro", destruction = "destro",
    balance = "balance", boomkin = "balance", moonkin = "balance",
    feral = "feral", ["feral combat"] = "feral", cat = "feral", bear = "feral",
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
    -- Casters and healers.
    ["ITEM_MOD_SPELL_POWER_SHORT"] = "spellPower",
    ["ITEM_MOD_SPELL_DAMAGE_DONE_SHORT"] = "spellPower",
    ["ITEM_MOD_SPELL_HEALING_DONE_SHORT"] = "healing",
    ["ITEM_MOD_MANA_REGENERATION_SHORT"] = "mp5",
    ["ITEM_MOD_POWER_REGEN0_SHORT"] = "mp5",
    ["ITEM_MOD_CRIT_SPELL_RATING_SHORT"] = "spellCrit",
    ["ITEM_MOD_SPELL_CRIT_RATING_SHORT"] = "spellCrit",
    ["ITEM_MOD_HIT_SPELL_RATING_SHORT"] = "spellHit",
    ["ITEM_MOD_SPELL_HIT_RATING_SHORT"] = "spellHit",
    -- Tanks.
    ["ITEM_MOD_DEFENSE_SKILL_RATING_SHORT"] = "defense",
    ["ITEM_MOD_DODGE_RATING_SHORT"] = "dodge",
    ["ITEM_MOD_PARRY_RATING_SHORT"] = "parry",
    ["ITEM_MOD_BLOCK_RATING_SHORT"] = "block",
    ["ITEM_MOD_BLOCK_VALUE_SHORT"] = "blockValue",
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
function Weights:TreePoints(class)
    if type(GetNumTalentTabs) ~= "function" or type(GetTalentTabInfo) ~= "function" then
        return self:TraitPoints(class)
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

--- Points per spec from Forever's trait tree: every talent with ranks bought
--- counts toward the spec whose columns it sits in. Nil when there is no
--- config to read or no split known for the class. Each call is in a pcall,
--- and a node that will not answer is skipped rather than guessed.
function Weights:TraitPoints(class)
    local specs = class and SPECS[class]
    local columns = specs and specs.columns
    if not columns then return nil end

    local talents = type(C_ClassTalents) == "table" and C_ClassTalents
    local traits = type(C_Traits) == "table" and C_Traits
    if not (talents and traits and type(talents.GetActiveConfigID) == "function"
        and type(traits.GetConfigInfo) == "function"
        and type(traits.GetTreeNodes) == "function"
        and type(traits.GetNodeInfo) == "function") then
        return nil
    end

    local ok, configID = pcall(talents.GetActiveConfigID)
    if not ok or not configID then return nil end

    local okInfo, info = pcall(traits.GetConfigInfo, configID)
    if not okInfo or type(info) ~= "table" or type(info.treeIDs) ~= "table" then return nil end

    local points = {}
    for index = 1, #specs.order do points[index] = 0 end

    for _, treeID in ipairs(info.treeIDs) do
        local okNodes, nodes = pcall(traits.GetTreeNodes, treeID)
        if okNodes and type(nodes) == "table" then
            for _, nodeID in ipairs(nodes) do
                local okNode, node = pcall(traits.GetNodeInfo, configID, nodeID)
                if okNode and type(node) == "table" and type(node.posX) == "number" then
                    local ranks = tonumber(node.ranksPurchased) or 0
                    if ranks > 0 then
                        local index = #columns + 1
                        for column, edge in ipairs(columns) do
                            if node.posX < edge then
                                index = column
                                break
                            end
                        end
                        points[index] = points[index] + ranks
                    end
                end
            end
        end
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

    local points = self:TreePoints(class)
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

-- The client's item classes that `armor` and `weapons` above describe.
local CLASS_WEAPON, CLASS_ARMOR = 2, 4

--- Can this class equip an item of this kind?
-- @return false if never; else true and the level it opens at, or nil when
--         it is open from the start
function Weights:CanUse(class, classID, subclassID)
    local specs = class and SPECS[class]
    local list
    if classID == CLASS_ARMOR then
        list = specs and specs.armor
    elseif classID == CLASS_WEAPON then
        list = specs and specs.weapons
    end
    -- Anything else that goes in a slot (a shirt, a quiver) is not judged by
    -- class, and a class with no list yet is not second-guessed.
    if not list then return true end

    local level = list[subclassID]
    if not level then return false, nil end
    return true, level > 0 and level or nil
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

ns.RegisterCommand("spec", "show the spec gear is judged for, or pick one by name (or auto)",
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
            local names = {}
            for _, key in ipairs(class and SPECS[class] and SPECS[class].order or {}) do
                names[#names + 1] = key
            end
            names[#names + 1] = "auto"
            ns.Warn(("not a spec: %s (try %s)"):format(rest, table.concat(names, ", ")))
            return
        end

        ns.charDB.spec = spec
        ShowSpec()
    end)
