-- The backup set shown on My Gear and marked in the bags (the owner said
-- build it from the mockup, 2026-11-27).
--
-- What must hold:
--   1. With "Backup Weapon Set:" off: no strip, no swords mark, and Butler
--      hears nothing new (`backup` unset).
--   2. On: the strip shows under the figure with any slot picked (the owner
--      had Shoulder picked and saw nothing), naming both pieces.
--   3. The bag squares of the two pieces wear the blue swords; others none.
--   4. Butler hears `backup = true` for each piece, never `sell` or `alt`
--      (it told the owner to disenchant his backup off hand).
--   5. When the pair wins, the strip says so and offers Put Them On.
--   6. Carrying no main hand or off hand: the strip says so, and no piece.
--   7. Not on Gear Road.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("backupshown")

local ARMOR, WEAPON = 4, 2
local SHIELD, SWORD1H, SWORD2H = 6, 7, 8
local function Str(n) return { ITEM_MOD_STRENGTH_SHORT = n } end

local ITEMS = {
    ["item:1"] = { loc = "INVTYPE_2HWEAPON", class = WEAPON, subclass = SWORD2H, stats = Str(30) },  -- worn
    ["item:3"] = { loc = "INVTYPE_WEAPON", class = WEAPON, subclass = SWORD1H, stats = Str(14) },    -- bags
    ["item:4"] = { loc = "INVTYPE_SHIELD", class = ARMOR, subclass = SHIELD, stats = Str(12) },      -- bags
    ["item:5"] = { loc = "INVTYPE_SHIELD", class = ARMOR, subclass = SHIELD, stats = Str(20) },      -- for 5.
    ["item:8"] = { loc = "INVTYPE_SHIELD", class = ARMOR, subclass = SHIELD, stats = Str(2) },       -- a weak spare
}

local ns = env.Load()
_G.UnitClass = function() return "Paladin", "PALADIN", 2 end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitRace = function() return "Human", "Human", 1 end
env.InstallItems(ITEMS, { [16] = "item:1" },
    { [0] = { [1] = "item:3", [2] = "item:4", [3] = "item:8", [4] = false } }, 40)
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
ns.charDB.spec = "ret"
_G.C_Container.GetContainerItemInfo = function() return { quality = 2, isBound = true, stackCount = 1 } end
_G.C_TooltipInfo = { GetHyperlink = function() return { lines = { { type = 11, price = 50 } } } end }

local Backup, BagIcons, Butler, MyGear = ns.BackupWeapons, ns.BagIcons, ns.Butler, ns.MyGear

local function Button(bag, slot)
    local button = env.Stub({ _textures = {} })
    button.GetID = function() return slot end
    button.GetBagID = function() return bag end
    button.CreateTexture = function(self)
        local texture = env.Stub()
        texture.SetTexture = function(t, path) t._path = path end
        self._textures[#self._textures + 1] = texture
        return texture
    end
    return button
end
local buttons = { Button(0, 1), Button(0, 2), Button(0, 3) }
local function Marked(index)
    BagIcons:UpdateButton(buttons[index])
    local mark = BagIcons:ExistingSwords(buttons[index])
    return mark ~= nil and mark:IsShown()
end

ns.UI:Show()
ns.GearWindow:ShowTab("gear")
MyGear:Refresh()
MyGear:PickSlot(3)
local strip = MyGear.strip

-- 1.
suite.check("off at the start: no strip", strip and not strip:IsShown())
suite.check("off: no swords on the sword", not Marked(1))
local advice = Butler:Advise("item:3", 0, 1)
suite.check("off: Butler hears nothing new", advice and advice.backup == nil)

-- 2.
Backup:SetOn(true)
MyGear:PickSlot(3)
suite.check("no room left under the figure: hidden, not over it", not strip:IsShown())
-- The page's body is about 554 tall with cards over it (668 less cards and footer).
MyGear.left:SetHeight(554)
MyGear:PickSlot(3)
suite.check("on: the strip shows with Shoulder picked", strip:IsShown())
suite.check("it says the two-hander wins", strip.status:GetText() == "Your two-hander wins for now.",
    strip.status:GetText())
suite.check("it names the sword and the shield", strip.pieces[1]:IsShown()
    and strip.pieces[1].name:GetText():find("item:3", 1, true) ~= nil
    and strip.pieces[2].name:GetText():find("item:4", 1, true) ~= nil,
    strip.pieces[1].name:GetText())
suite.check("with both scores and no Put Them On", not strip.button:IsShown()
    and strip.scores:GetText():find("Your two-hander:", 1, true) ~= nil
    and strip.scores:GetText():find("Backup set:", 1, true) ~= nil, strip.scores:GetText())
suite.check("it sits under the figure", select(5, strip:GetPoint(1)) ~= nil)
strip:GetScript("OnClick")(strip)
suite.check("a click picks the main hand", MyGear.slot == 16)

-- 3.
suite.check("the sword wears the swords", Marked(1))
suite.check("so does the shield", Marked(2))
suite.check("drawn with our own texture", BagIcons:ExistingSwords(buttons[1])._path ~= nil)
suite.check("the weak spare does not", not Marked(3))

-- 4.
for _, link in ipairs({ "item:3", "item:4" }) do
    advice = Butler:Advise(link, 0, link == "item:3" and 1 or 2)
    suite.check(link .. ": Butler hears backup, never sell or alt", advice and advice.backup == true
        and advice.sell == false and advice.alt == nil)
end
advice = Butler:Advise("item:8", 0, 3)
suite.check("the weak spare is no backup piece", advice and advice.backup == nil)

-- 5.
env.bags[0][4] = "item:5"
Backup:Forget()
MyGear:PickSlot(3)
suite.check("the pair wins: the strip says by how much",
    strip.status:GetText():find("Beats your two-hander by", 1, true) ~= nil, strip.status:GetText())
suite.check("and offers Put Them On", strip.button:IsShown() and strip.scores:GetText() == "")

-- 6.
env.bags[0] = { [1] = false, [2] = false, [3] = false, [4] = false }
Backup:Forget()
MyGear:PickSlot(3)
suite.check("nothing to switch to: the strip says so", strip:IsShown()
    and strip.status:GetText() == "You carry no main hand and off hand to switch to yet.", strip.status:GetText())
suite.check("with no pieces", not strip.pieces[1]:IsShown() and not strip.pieces[2]:IsShown())

-- 7.
if ns.GearRoad then
    MyGear:SetView("road")
    suite.check("not on Gear Road", not strip:IsShown())
    MyGear:SetView("figure")
end

Backup:SetOn(false)
MyGear:PickSlot(3)
suite.check("off again: gone", not strip:IsShown())

suite.done()
