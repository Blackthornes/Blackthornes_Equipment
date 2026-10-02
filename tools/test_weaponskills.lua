-- The weapon master line on a weapon's tooltip: only for a skill the class
-- can learn and the character has not, only the player's faction's cities,
-- and nothing when the client will not say what is known.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("weaponskills")

local ITEMS = {
    ["item:1"] = { loc = "INVTYPE_WEAPON", class = 2, subclass = 15, stats = { ITEM_MOD_AGILITY_SHORT = 5 } },   -- dagger
    ["item:2"] = { loc = "INVTYPE_2HWEAPON", class = 2, subclass = 8, stats = { ITEM_MOD_AGILITY_SHORT = 9 } },  -- two-handed sword
    ["item:3"] = { loc = "INVTYPE_2HWEAPON", class = 2, subclass = 1, stats = { ITEM_MOD_AGILITY_SHORT = 3 } },  -- two-handed axe
    ["item:4"] = { loc = "INVTYPE_WEAPON", class = 2, subclass = 4, stats = { ITEM_MOD_AGILITY_SHORT = 3 } },    -- mace
    ["item:5"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = { ITEM_MOD_AGILITY_SHORT = 3 } },
    ["item:6"] = { loc = "INVTYPE_2HWEAPON", class = 2, subclass = 10, stats = { ITEM_MOD_AGILITY_SHORT = 3 } }, -- staff
}

-- A hunter who knows axes and bows, by spell.
local KNOWN = { [196] = true, [197] = true, [264] = true }

local function Load(faction, spells)
    local ns = env.Load()
    _G.UnitClass = function() return "Hunter", "HUNTER" end
    _G.UnitFactionGroup = function() return faction end
    _G.IsPlayerSpell = function(id) return (spells or KNOWN)[id] == true end
    env.InstallItems(ITEMS, {})
    return ns
end

local ns = Load("Horde")
local skills = ns.WeaponSkills
suite.check("daggers: Orgrimmar and Undercity",
    skills:Describe("item:1") == "Learn Daggers from the weapon master in Orgrimmar or Undercity",
    skills:Describe("item:1"))
suite.check("two-handed swords: Undercity",
    skills:Describe("item:2") == "Learn Two-Handed Swords from the weapon master in Undercity",
    skills:Describe("item:2"))
suite.check("in the warning colour", select(2, skills:Describe("item:2")) == "warn")
suite.check("a known skill says nothing", skills:Describe("item:3") == nil)
suite.check("a skill the class can never learn says nothing", skills:Describe("item:4") == nil)
suite.check("armour says nothing", skills:Describe("item:5") == nil)
suite.check("staves: Orgrimmar once, then Thunder Bluff",
    skills:Describe("item:6") == "Learn Staves from the weapon master in Orgrimmar or Thunder Bluff",
    skills:Describe("item:6"))

ns = Load("Alliance")
suite.check("Alliance daggers: three cities",
    ns.WeaponSkills:Describe("item:1") == "Learn Daggers from the weapon master in Stormwind, Ironforge or Darnassus",
    ns.WeaponSkills:Describe("item:1"))

ns = Load(nil)
suite.check("no faction, no line", ns.WeaponSkills:Describe("item:1") == nil)

ns = Load("Horde", {})
suite.check("nothing known reads as no answer", ns.WeaponSkills:Known() == nil)
suite.check("and says nothing", ns.WeaponSkills:Describe("item:1") == nil)

-- Classic's skill list counts too, and a spell call that raises does not.
ns = Load("Horde", {})
_G.IsPlayerSpell = function() error("secret value") end
_G.GetNumSkillLines = function() return 3 end
_G.GetSkillLineInfo = function(i) return ({ "Weapon Skills", "Axes", "Daggers" })[i] end
suite.check("the skill list says daggers are known", ns.WeaponSkills:Describe("item:1") == nil)
suite.check("and swords are not",
    ns.WeaponSkills:Describe("item:2") == "Learn Two-Handed Swords from the weapon master in Undercity")

_G.UnitFactionGroup = function() error("secret value") end
suite.check("a faction that raises says nothing", ns.WeaponSkills:Describe("item:2") == nil)

-- On the tooltip, under the verdict and wrapped.
ns = Load("Horde")
_G.Enum = { TooltipDataType = { Item = 0 } }
local postCall
_G.TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) postCall = fn end }
local wraps = {}
_G.GameTooltip.AddLine = function(self, text, _, _, _, wrap)
    self._lines[#self._lines + 1] = text
    wraps[#self._lines] = wrap
end
ns.Tooltip:OnEnable()
postCall(_G.GameTooltip, { id = 2, hyperlink = "item:2" })
local lines = _G.GameTooltip._lines
suite.check("two lines on the tooltip", #lines == 2, #lines)
suite.check("the trainer line second",
    lines[2] == "|cffe8c15aLearn Two-Handed Swords from the weapon master in Undercity|r", lines[2])
suite.check("and only it wraps", wraps[2] == true and not wraps[1])

suite.done()
