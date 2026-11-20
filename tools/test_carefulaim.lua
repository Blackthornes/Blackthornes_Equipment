-- Careful Aim: Forever's Marksmanship talent gives melee and ranged attack
-- power equal to 20% of the hunter's Intellect per rank (five ranks). A
-- hunter with points in it gets more from Intellect on gear; one without
-- gets the plain weights.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("carefulaim")

local ARMOR, MAIL = 4, 3
local ITEMS = {
    -- 20 Intellect, nothing else.
    ["item:1"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = MAIL,
        stats = { ITEM_MOD_INTELLECT_SHORT = 20 } },
}

local CAREFUL, OTHER = 5620, 5020   -- two Marksmanship nodes
local SPELLS = {
    [77001] = { name = "Careful Aim", text = "Increases melee and ranged Attack Power by 20% of your Intellect." },
    [77002] = { name = "Hawk Eye", text = "Increases the range of your ranged weapons by 2 yards." },
    -- The same talent on a German client: found by its text.
    [77003] = { name = "Sorgfältiges Zielen", text = "Erhöht die Nah- und Distanzangriffskraft um 20% Eurer Intelligenz." },
}

--- A hunter with `ranks` in Careful Aim (whose spell is `spell`), and 3 in Hawk Eye.
local function LoadHunter(ranks, spell, opts)
    opts = opts or {}
    local ns = env.Load()
    _G.UnitClass = function() return opts.class or "HUNTER", opts.class or "HUNTER" end
    env.InstallItems(ITEMS, {}, {}, 60)
    _G.GetNumTalentTabs, _G.GetTalentTabInfo = nil, nil
    _G.UnitRace = function() return "Orc", "Orc", 2 end
    local layout = {
        [CAREFUL] = { posX = CAREFUL, posY = 0, ranksPurchased = ranks, activeEntry = { entryID = 1 } },
        [OTHER] = { posX = OTHER, posY = 0, ranksPurchased = 3, activeEntry = { entryID = 2 } },
    }
    local spellOf = { [1] = spell or 77001, [2] = 77002 }
    _G.C_ClassTalents = { GetActiveConfigID = function() return 9601568 end }
    _G.C_Traits = {
        GetConfigInfo = function() return { type = 4, name = "Hunter", treeIDs = { 1091 } } end,
        GetTreeNodes = function() return { OTHER, CAREFUL } end,
        GetNodeInfo = function(_, nodeID)
            if opts.raise then error("secret value") end
            return layout[nodeID]
        end,
        GetEntryInfo = function(_, entryID) return { definitionID = entryID + 10 } end,
        GetDefinitionInfo = function(definitionID) return { spellID = spellOf[definitionID - 10] } end,
    }
    _G.C_Spell = {
        GetSpellName = function(id) return SPELLS[id] and SPELLS[id].name end,
        GetSpellDescription = function(id) return SPELLS[id] and SPELLS[id].text end,
    }
    if opts.german then
        _G.ITEM_MOD_INTELLECT_SHORT, _G.ITEM_MOD_ATTACK_POWER_SHORT = "Intelligenz", "Angriffskraft"
    else
        _G.ITEM_MOD_INTELLECT_SHORT, _G.ITEM_MOD_ATTACK_POWER_SHORT = "Intellect", "Attack Power"
    end
    return ns
end

local function Near(a, b) return math.abs((a or 0) - (b or 0)) < 1e-6 end

-- No points: the plain weights, the same table.
local ns = LoadHunter(0)
local spec = ns.Weights:CurrentSpec()
local plain = ns.Weights:Get("HUNTER", spec)
suite.check("no points in Careful Aim leaves the weights alone", ns.Weights:ForPlayer() == plain)
local power = math.max(plain.attackPower or 0, plain.rangedAttackPower or 0)
suite.check("the hunter weighs attack power", power > 0, power)

-- Five ranks: each Intellect also brings one attack power.
ns = LoadHunter(5)
spec = ns.Weights:CurrentSpec()
plain = ns.Weights:Get("HUNTER", spec)
power = math.max(plain.attackPower or 0, plain.rangedAttackPower or 0)
local weights = ns.Weights:ForPlayer()
suite.check("five ranks make Intellect worth one attack power more",
    Near(weights.intellect, plain.intellect + power), weights.intellect)
suite.check("the built-in weights are left alone", plain.intellect ~= weights.intellect)
suite.check("other stats are unchanged", weights.agility == plain.agility)
suite.check("and the same table comes back each time", ns.Weights:ForPlayer() == weights)
local score = ns.Compare:ScoreOf("item:1", weights)
suite.check("20 Intellect scores as 20 Intellect and 20 attack power",
    Near(score, 20 * plain.intellect + 20 * power), score)

-- Two ranks: 40%.
ns = LoadHunter(2)
spec = ns.Weights:CurrentSpec()
plain = ns.Weights:Get("HUNTER", spec)
power = math.max(plain.attackPower or 0, plain.rangedAttackPower or 0)
suite.check("two ranks count 40% of Intellect",
    Near(ns.Weights:ForPlayer().intellect, plain.intellect + 0.4 * power))

-- A German client: the talent is found by its text.
ns = LoadHunter(3, 77003, { german = true })
spec = ns.Weights:CurrentSpec()
plain = ns.Weights:Get("HUNTER", spec)
power = math.max(plain.attackPower or 0, plain.rangedAttackPower or 0)
suite.check("another language finds it by its text",
    Near(ns.Weights:ForPlayer().intellect, plain.intellect + 0.6 * power))

-- Talents that can't be read change nothing and raise nothing.
ns = LoadHunter(5, nil, { raise = true })
local ok, result = pcall(function() return ns.Weights:ForPlayer() end)
suite.check("a talent tree that raises leaves the weights alone",
    ok and result == ns.Weights:Get("HUNTER", ns.Weights:CurrentSpec()))

-- Only hunters.
ns = LoadHunter(5, nil, { class = "MAGE" })
suite.check("a mage is never given Careful Aim",
    ns.Weights:ForPlayer() == ns.Weights:Get("MAGE", ns.Weights:CurrentSpec()))

-- Points bought later are seen once the talents change.
ns = LoadHunter(0)
ns.Weights:OnEnable()
spec = ns.Weights:CurrentSpec()
plain = ns.Weights:ForPlayer()
_G.C_Traits.GetNodeInfo = function(_, nodeID)
    return ({ [CAREFUL] = { posX = CAREFUL, ranksPurchased = 5, activeEntry = { entryID = 1 } },
        [OTHER] = { posX = OTHER, ranksPurchased = 3, activeEntry = { entryID = 2 } } })[nodeID]
end
ns.Weights:ForgetPoints()
suite.check("new points count once the talents change", ns.Weights:ForPlayer().intellect > plain.intellect)

_G.C_ClassTalents, _G.C_Traits, _G.C_Spell = nil, nil, nil
suite.done()
