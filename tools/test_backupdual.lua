-- The backup weapon set for those who swing two weapons (the owner said
-- build it from the mockup equipment-weapon-set-dual, 2026-11-27).
--
-- What must hold:
--   1. A weapon in the off hand deals half its damage, so it counts for
--      that much less when a pair meets a two-hander. Before, the off hand's
--      damage counted in full and a pair looked better than it was.
--   2. The plain verdict on a two-hander, while a pair is worn, weighs it
--      against the main hand and the off hand at half damage.
--   3. A one-hander is weighed in whichever hand makes the better pair.
--   4. Someone who swings two keeps the best pair of one-handers, with the
--      switch off and the two-hander winning: no sell coin, and the tooltip
--      says "Kept for your backup set." A spare shield still sells.
--   5. Before the level a second weapon opens, nothing changes.
--   6. A rogue, who can't use a two-hander, has no backup set.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("backupdual")

local ARMOR, WEAPON = 4, 2
local AXE1H, AXE2H, SHIELD, SWORD1H = 0, 1, 6, 7
local function Melee(agility, dps, strength)
    return { ITEM_MOD_AGILITY_SHORT = agility, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = dps,
        ITEM_MOD_STRENGTH_SHORT = strength }
end

local ITEMS = {
    ["item:1"] = { loc = "INVTYPE_2HWEAPON", class = WEAPON, subclass = AXE2H, stats = Melee(20, 55) },   -- worn
    ["item:3"] = { loc = "INVTYPE_WEAPON", class = WEAPON, subclass = SWORD1H, stats = Melee(12, 30) },   -- bags
    ["item:4"] = { loc = "INVTYPE_WEAPON", class = WEAPON, subclass = AXE1H, stats = Melee(10, 28) },     -- bags
    ["item:8"] = { loc = "INVTYPE_SHIELD", class = ARMOR, subclass = SHIELD, stats = { ITEM_MOD_STRENGTH_SHORT = 120 } },
}

local ns = env.Load()
local class = "HUNTER"
_G.UnitClass = function() return class, class, 3 end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitRace = function() return "Dwarf", "Dwarf", 3 end
env.InstallItems(ITEMS, { [16] = "item:1" },
    { [0] = { [1] = "item:3", [2] = "item:4", [3] = false, [4] = false } }, 44)
_G.C_QuestLog = { IsQuestFlaggedCompleted = function() return false end }
local S = ns.Sources
ns.Crafts.ITEMS = {}
ns.RollData.ITEMS = {}
S.FOREVER, S.QUESTS, S.DUNGEONS, S.BOSSES, S.ITEMS = {}, {}, {}, {}, {}
for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end
_G.InCombatLockdown = function() return false end
_G.C_Timer = nil
ns.charDB.spec = "survival"

local Backup, Compare, Tooltip, Weights = ns.BackupWeapons, ns.Compare, ns.Tooltip, ns.Weights
local function Fresh()
    Compare:ForgetScores()
    Backup:Forget()
    Tooltip.ForgetLines()
end

local weights = Weights:ForPlayer()
suite.check("the sample: Survival weights count melee damage", weights and weights.meleeDps == 5)
local s1, s3, s4 = Compare:ScoreOf("item:1", weights), Compare:ScoreOf("item:3", weights),
    Compare:ScoreOf("item:4", weights)
suite.check("the sample: at full damage the pair would beat the two-hander", s3 + s4 > s1, s3 + s4 .. " vs " .. s1)

-- 1.
suite.check("an off hand axe loses half its damage", math.abs(Compare:OffHandCut("item:4", weights) - 28 * 5 / 2) < 0.01,
    Compare:OffHandCut("item:4", weights))
suite.check("a shield loses nothing", Compare:OffHandCut("item:8", weights) == 0)
local set = Backup:Set()
suite.check("wearing the two-hander, the backup is the two one-handers", set and set.mode == "pair"
    and set.main.link == "item:3" and set.off.link == "item:4", set and set.mode)
suite.check("the pair counts the off hand at half damage", set
    and math.abs(set.score - (s3 + s4 - 70)) < 0.01, set and set.score)
suite.check("so the two-hander wins", set and not set.beats, set and set.percent)

-- 3.
local alone = Compare:JudgeCarried("item:4")
local paired = Backup:WithPartner("item:4", alone)
suite.check("a one-hander is weighed in the hand that makes the better pair", paired
    and paired.partner and paired.partner.link == "item:3"
    and math.abs(paired.score - (s3 + s4 - 70)) < 0.01, paired and paired.score)

-- 4.
suite.check("Backup Weapon Set is off", not Backup.On())
suite.check("the main hand of the pair is kept", Backup:InSet("item:3"))
suite.check("the off hand of the pair is kept", Backup:InSet("item:4"))
Fresh()
local lines = Tooltip:WorkOutLines("item:4", true, 0, 2)
local kept = false
for _, line in ipairs(lines) do
    if line[1] == "Kept for your backup set." then kept = true end
end
suite.check("the tooltip says it is kept", kept)
local worn = Tooltip:WorkOutLines("item:1", false)
local keptWorn = false
for _, line in ipairs(worn) do
    if line[1] == "Kept for your backup set." then keptWorn = true end
end
suite.check("no kept line on what is worn", not keptWorn)

-- 2.
env.worn[16], env.worn[17] = "item:3", "item:4"
env.bags[0][1], env.bags[0][2] = "item:1", false
Fresh()
local two = Compare:JudgeCarried("item:1")
suite.check("a two-hander is weighed against the pair at half off hand damage", two
    and math.abs(two.against - (s3 + s4 - 70)) < 0.01, two and two.against)
suite.check("and wins", two and two.verdict == "upgrade", two and two.verdict)
local back = Backup:Set()
suite.check("wearing the pair, the backup is the two-hander", back and back.mode == "two"
    and back.two.link == "item:1" and back.beats, back and back.mode)

-- 5.
env.worn[16], env.worn[17] = "item:1", nil
env.bags[0][1], env.bags[0][2] = "item:3", "item:4"
_G.UnitLevel = function() return 15 end
Fresh()
suite.check("at level 15 a hunter can't swing two", not Weights:CanDualWield("HUNTER", 15))
suite.check("so the second one-hander is not kept", not Backup:InSet("item:4"))
_G.UnitLevel = function() return 44 end

-- 4. A warrior's spare shield.
class = "WARRIOR"
ns.charDB.spec = "arms"
env.bags[0][2] = "item:8"
env.bags[0][3] = "item:4"
Fresh()
weights = Weights:ForPlayer()
local wset = Backup:Set()
suite.check("a warrior's best off hand here is the shield", wset and wset.mode == "pair"
    and wset.off.link == "item:8", wset and wset.off and wset.off.link)
suite.check("the two-hander wins", wset and not wset.beats, wset and wset.percent)
suite.check("the shield is not kept with the switch off", not Backup:InSet("item:8"))
suite.check("the one-hander is kept", Backup:InSet("item:3"))

-- 6.
class = "ROGUE"
ns.charDB.spec = "combat"
env.worn[16], env.worn[17] = "item:3", "item:4"
env.bags[0] = { [1] = "item:1", [2] = false, [3] = false, [4] = false }
Fresh()
local rset = Backup:Set()
suite.check("a rogue has no backup set: a two-hander is not for it", rset == nil, rset and rset.mode)

suite.done()
