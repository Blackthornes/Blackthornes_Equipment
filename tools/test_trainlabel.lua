-- A weapon whose skill the character has not learned says "Train" in red
-- wherever an upgrade's gain shows: the Find Upgrades tab and the character
-- sheet's list (a player asked, the owner agreed 2026-10-10).

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("trainlabel")

local ITEMS = {
    ["item:1"] = { loc = "INVTYPE_WEAPON", class = 2, subclass = 15, stats = { ITEM_MOD_AGILITY_SHORT = 5 } },   -- dagger
    ["item:3"] = { loc = "INVTYPE_2HWEAPON", class = 2, subclass = 1, stats = { ITEM_MOD_AGILITY_SHORT = 3 } },  -- two-handed axe
    ["item:5"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = { ITEM_MOD_AGILITY_SHORT = 3 } },
}

-- A Horde hunter who knows axes and bows, not daggers.
local known = { [196] = true, [197] = true, [264] = true }
local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER" end
_G.UnitFactionGroup = function() return "Horde" end
local asked = 0
_G.IsPlayerSpell = function(id) asked = asked + 1; return known[id] == true end
env.InstallItems(ITEMS, {})

local skills = ns.WeaponSkills
skills:Forget()
suite.check("an untrained dagger needs training", skills:NeedsTraining("item:1"))
suite.check("a known axe does not", not skills:NeedsTraining("item:3"))
suite.check("armour never does", not skills:NeedsTraining("item:5"))
suite.check("no link never does", not skills:NeedsTraining(nil))

-- The answer is kept, so a long list asks the client once.
asked = 0
for _ = 1, 20 do skills:NeedsTraining("item:1") end
suite.check("kept between rows", asked == 0, asked)

-- Learning daggers: the event forgets, and the label goes.
known[1180] = true
skills:Forget()
suite.check("learned daggers need nothing", not skills:NeedsTraining("item:1"))
known[1180] = nil
skills:Forget()

-- A client that raises means unsure, so no label.
_G.IsPlayerSpell = function() error("secret value") end
skills:Forget()
suite.check("a raising client is not Train", not skills:NeedsTraining("item:1"))
_G.IsPlayerSpell = function(id) return known[id] == true end
skills:Forget()

-- The character sheet's list.
local SU = ns.SlotUpgrades
local dagger = { link = "item:1", result = { percent = 12 } }
local axe = { link = "item:3", result = { percent = 12 } }
suite.check("slot list says Train", SU.Gain(dagger) == "Train: +12%", SU.Gain(dagger))
suite.check("in red", SU.GainKey(dagger) == "loss", SU.GainKey(dagger))
suite.check("a known weapon keeps its gain", SU.Gain(axe) == "+12%", SU.Gain(axe))
suite.check("in green", SU.GainKey(axe) == "good", SU.GainKey(axe))

-- The Find Upgrades row.
local Find = ns.FindUpgrades
local function Pick(link) return { link = link, itemID = 1, result = { percent = 12 } } end
local text, key = Find.GainText(Pick("item:1"))
suite.check("Find Upgrades says Train", text == "Train: +12%", text)
suite.check("in red", key == "loss", key)
text, key = Find.GainText(Pick("item:3"))
suite.check("a known weapon keeps its gain", text == "+12%", text)
suite.check("in green", key == "good", key)

suite.done()
