-- Best Armor Only (the owner, 2026-10-18): ticked on a character, armor
-- lighter than the heaviest kind it wears is never an upgrade. A kind the
-- class learns at 40 counts only once a piece of it is worn.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("bestarmor")

local ARMOR, CLOTH, LEATHER, MAIL, PLATE = 4, 1, 2, 3, 4
local function Str(n) return { ITEM_MOD_STRENGTH_SHORT = n, ITEM_MOD_STAMINA_SHORT = n } end

local ITEMS = {
    -- Worn: a weak mail chest.
    ["item:1"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = MAIL, stats = Str(1) },
    -- In the bags, all better than it.
    ["item:2"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = LEATHER, stats = Str(20) },
    ["item:3"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = MAIL, stats = Str(20) },
    ["item:4"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = CLOTH, stats = Str(20) },
    ["item:5"] = { loc = "INVTYPE_CLOAK", class = ARMOR, subclass = CLOTH, stats = Str(20) },
    ["item:6"] = { loc = "INVTYPE_FINGER", class = ARMOR, subclass = 0, stats = Str(20) },
    -- Plate, for later.
    ["item:7"] = { loc = "INVTYPE_HEAD", class = ARMOR, subclass = PLATE, stats = Str(5) },
    ["item:8"] = { loc = "INVTYPE_WRIST", class = ARMOR, subclass = MAIL, stats = Str(20) },
}

local ns = env.Load()
_G.UnitClass = function() return "WARRIOR", "WARRIOR" end
local level = 20
local worn = { [5] = "item:1" }
env.InstallItems(ITEMS, worn, {})
_G.UnitLevel = function() return level end

local Compare, Weights = ns.Compare, ns.Weights
local function Verdict(link) local r = Compare:Judge(link); return r and r.verdict end

suite.check("off at first", Compare.BestArmorOnly() == false)
suite.check("leather is an upgrade while off", Verdict("item:2") == "upgrade", Verdict("item:2"))

local redraws = 0
_G.BlackthornesTS = { Upgrades = { RedrawSoon = function() redraws = redraws + 1 end } }
Compare:SetBestArmorOnly(true)
suite.check("saved for this character", ns.charDB.bestArmorOnly == true)
suite.check("everything is judged again", redraws == 1, redraws)

local leather = Compare:Judge("item:2")
suite.check("leather is not for a mail wearer", leather.verdict == "cantuse" and leather.lighterArmor, leather.verdict)
suite.check("no tooltip line for it", Compare:Describe(leather) == nil)
suite.check("cloth chest too", Verdict("item:4") == "cantuse")
suite.check("mail still an upgrade", Verdict("item:3") == "upgrade", Verdict("item:3"))
suite.check("a cloak still shows", Verdict("item:5") == "upgrade", Verdict("item:5"))
suite.check("a ring still shows", Verdict("item:6") == "upgrade", Verdict("item:6"))
suite.check("no bag arrow on leather", Compare:IsUpgrade("item:2") == false)
suite.check("an upgrade quest for leather is let go",
    ns.UpgradeQuest:LighterArmor({ link = "item:2" }) == true
    and ns.UpgradeQuest:LighterArmor({ link = "item:3" }) == false)

-- Level 40: plate opens, but mail keeps showing until a plate piece is worn.
level = 40
suite.check("mail still shows at 40 with no plate", Verdict("item:8") == "upgrade", Verdict("item:8"))
suite.check("leather still not", Verdict("item:2") == "cantuse")
worn[1] = "item:7"
suite.check("once plate is worn, mail goes", Verdict("item:8") == "cantuse", Verdict("item:8"))
suite.check("the plate itself is fine", Verdict("item:7") == "equipped", Verdict("item:7"))

-- A hunter under 40 still sees leather: mail is not open yet.
_G.UnitClass = function() return "HUNTER", "HUNTER" end
worn[1], worn[5] = nil, nil
level = 20
suite.check("a young hunter sees leather", Verdict("item:2") == "upgrade", Verdict("item:2"))
suite.check("and not cloth", Verdict("item:4") == "cantuse")

-- Alts keep their own rule, untouched.
suite.check("alts' check unchanged", Weights:IsBestArmor("WARRIOR", 40, ARMOR, MAIL, "INVTYPE_CHEST") == false)

Compare:SetBestArmorOnly(false)
suite.check("unticked clears it", ns.charDB.bestArmorOnly == nil)
suite.check("cloth is back", Verdict("item:4") == "upgrade", Verdict("item:4"))

suite.done()
