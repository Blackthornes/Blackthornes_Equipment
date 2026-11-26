-- Switch Gear (Logic/SwitchGear.lua, the owner said build it from the
-- mockup, 2026-11-26).
--
-- What must hold:
--   1. With Off Spec on None there is nothing to switch, and /beq swap says
--      to pick one.
--   2. The button puts on the Off Spec's outfit from the bags, and notes
--      what came off as `swapBack`.
--   3. The way back puts those very pieces on again and lets the note go.
--   4. With no note, the way back is the Main Spec's own outfit.
--   5. In a fight nothing is tried; the swap goes ahead when it ends, and a
--      fight that starts mid-swap holds the rest.
--   6. Rings and trinkets count as a pair: one on the other finger is not
--      moved.
--   7. The dungeon door card: off at the start, asks once at a door with
--      the Main Spec's gear on, and Not Now keeps it quiet.
--   8. My Gear's row shows only while an Off Spec is picked.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("switchgear")

local ARMOR, WEAPON = 4, 2
local SHIELD, PLATE, MISC = 6, 4, 0
local SWORD1H, SWORD2H = 7, 8

local function Tank(n) return { ITEM_MOD_STAMINA_SHORT = n, ITEM_MOD_STRENGTH_SHORT = math.floor(n / 4) } end
local function Ret(n) return { ITEM_MOD_STRENGTH_SHORT = n } end

local ITEMS = {
    -- Worn: a Retribution two-hander and a chest.
    ["item:1"] = { loc = "INVTYPE_2HWEAPON", class = WEAPON, subclass = SWORD2H, stats = Ret(30) },
    ["item:10"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = PLATE, stats = Ret(40) },
    -- In the bags: a tank one-hander, shield and chest.
    ["item:3"] = { loc = "INVTYPE_WEAPON", class = WEAPON, subclass = SWORD1H, stats = Tank(10) },
    ["item:4"] = { loc = "INVTYPE_SHIELD", class = ARMOR, subclass = SHIELD, stats = Tank(10) },
    ["item:12"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = PLATE, stats = Tank(20) },
    -- Rings.
    ["item:30"] = { loc = "INVTYPE_FINGER", class = ARMOR, subclass = MISC, stats = Ret(5) },
    ["item:31"] = { loc = "INVTYPE_FINGER", class = ARMOR, subclass = MISC, stats = Ret(4) },
}

local ns = env.Load()
_G.UnitClass = function() return "Paladin", "PALADIN", 2 end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitRace = function() return "Human", "Human", 1 end
env.InstallItems(ITEMS, { [16] = "item:1", [5] = "item:10" },
    { [0] = { [1] = "item:3", [2] = "item:4", [3] = "item:12", [4] = false, [5] = false } }, 40)

local S = ns.Sources
ns.Crafts.ITEMS = {}
ns.RollData.ITEMS = {}
S.ZONES = { [12] = "Elwynn Forest" }
S.NPCS = {}
S.QUESTS, S.DUNGEONS, S.BOSSES, S.FOREVER = {}, {}, {}, {}
S.ITEMS = {}

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end

local fighting = false
_G.InCombatLockdown = function() return fighting end
_G.C_Timer = nil

-- The game's EquipItemByName, as far as these pieces need: the piece and
-- what was worn trade places; a two-hander pushes the off hand into the
-- first free bag slot.
local equipped = {}
local function FindInBags(link)
    for bag, slots in pairs(env.bags) do
        for slot, held in pairs(slots) do
            if held == link then return bag, slot end
        end
    end
end
local function FirstFree()
    for slot = 1, 5 do
        if env.bags[0][slot] == false or env.bags[0][slot] == nil then return 0, slot end
    end
end
_G.C_Item.EquipItemByName = function(link, slot)
    equipped[#equipped + 1] = tostring(slot) .. "=" .. link
    local bag, bagSlot = FindInBags(link)
    if not bag then return end
    env.bags[bag][bagSlot] = env.worn[slot] or false
    env.worn[slot] = link
    if ITEMS[link].loc == "INVTYPE_2HWEAPON" and env.worn[17] then
        local freeBag, freeSlot = FirstFree()
        env.bags[freeBag][freeSlot] = env.worn[17]
        env.worn[17] = nil
    end
end

local SwitchGear, OffSpec = ns.SwitchGear, ns.OffSpec
ns.charDB.spec = "ret"

local function Worn() return tostring(env.worn[16]) .. "/" .. tostring(env.worn[17]) .. "/" .. tostring(env.worn[5]) end

-- 1.
suite.check("with None there is nothing to switch", SwitchGear:State() == nil)
local before = #env.chat
ns.HandleSlash("swap")
suite.check("/beq swap says to pick an Off Spec", #env.chat > before
    and env.ChatText():find("Pick an Off Spec first", 1, true) ~= nil, env.ChatText())
suite.check("and puts nothing on", #equipped == 0)

-- 2.
OffSpec:Set("prot")
local state = SwitchGear:State()
suite.check("with Protection picked the Main Spec's gear is on", state and state.on == "main" and state.go == "off")
suite.check("three pieces will change", state and #state.steps == 3, state and #state.steps)
suite.check("in slot order", state and state.steps[1].slot == 5 and state.steps[2].slot == 16
    and state.steps[3].slot == 17)
SwitchGear:Go()
suite.check("the button puts the tank set on", Worn() == "item:3/item:4/item:12", Worn())
local back = ns.charDB.swapBack
suite.check("what came off is noted as swapBack", back and back[16] == "item:1" and back[5] == "item:10"
    and back[17] == nil)
suite.check("nothing is left waiting", not SwitchGear:Busy())
state = SwitchGear:State()
suite.check("now the Off Spec's gear is on", state and state.on == "off" and state.go == "main"
    and #state.steps == 2, state and #state.steps)

-- 3.
SwitchGear:Go()
suite.check("the way back puts the same pieces on", Worn() == "item:1/nil/item:10", Worn())
suite.check("the shield went back to the bags", FindInBags("item:4") ~= nil)
suite.check("the note is let go", ns.charDB.swapBack == nil)
state = SwitchGear:State()
suite.check("and the Main Spec's gear is on again", state and state.on == "main" and state.go == "off")

-- 4.
SwitchGear:Go("off")
ns.charDB.swapBack = nil
OffSpec:Forget()
state = SwitchGear:State()
suite.check("with no note the way back is the Main Spec's own outfit", state and state.go == "main"
    and state.steps[1].to == "item:10" and state.steps[2].to == "item:1",
    state and (tostring(state.go) .. " " .. #state.steps .. " " .. tostring(state.steps[1] and state.steps[1].to)
        .. " " .. tostring(state.steps[2] and state.steps[2].to)))
SwitchGear:Go("main")
suite.check("and it goes back on", Worn() == "item:1/nil/item:10", Worn())
suite.check("Go names the way: asking for the way already worn does nothing", SwitchGear:Go("main") == false)

-- 5.
fighting = true
equipped = {}
before = #env.chat
suite.check("in a fight the swap is held", SwitchGear:Go() == true and #equipped == 0 and SwitchGear:Busy())
suite.check("and the player is told", env.ChatText():find("They go on after the fight.", 1, true) ~= nil)
fighting = false
SwitchGear:FightOver()
suite.check("it goes ahead when the fight ends", Worn() == "item:3/item:4/item:12" and not SwitchGear:Busy(), Worn())

-- A fight that starts after the first piece holds the rest.
local realEquip = _G.C_Item.EquipItemByName
_G.C_Item.EquipItemByName = function(link, slot)
    realEquip(link, slot)
    fighting = true
end
SwitchGear:Go()
suite.check("a fight mid-swap holds the rest", env.worn[16] ~= "item:1" or env.worn[5] == "item:10")
suite.check("one piece went on before the fight", Worn() == "item:3/item:4/item:10", Worn())
suite.check("the rest waits", SwitchGear.waiting == "main" and SwitchGear.queue == nil)
_G.C_Item.EquipItemByName = realEquip
fighting = false
SwitchGear:FightOver()
suite.check("and goes on after", Worn() == "item:1/nil/item:10" and ns.charDB.swapBack == nil, Worn())

-- 6.
env.worn[11], env.worn[12] = "item:31", "item:30"
local steps = SwitchGear.Steps({ [11] = "item:30", [12] = "item:31" })
suite.check("a ring on the other finger is not moved", #steps == 0, #steps)
env.worn[11], env.worn[12] = nil, nil

-- 7.
ns.DungeonDoors.Spot = function(_, key)
    if key == "189" then return { zone = "Tirisfal Glades", x = 84.5, y = 30.5 } end
end
ns.FOREVER_DUNGEON_PLACES = { ["189"] = { "Scarlet Monastery", "", false } }
local shown = {}
local realShow = ns.Toast.Show
ns.Toast.Show = function(_, banner) shown[#shown + 1] = banner return true end
local door = { zone = "Tirisfal Glades", x = 85, y = 31 }
OffSpec:Forget()
SwitchGear:NoteSpot(door)
suite.check("the door card is off at the start", #shown == 0 and not SwitchGear:AskAtDoors())
ns.db.swapAtDoors = true
SwitchGear:NoteSpot({ zone = "Tirisfal Glades", x = 20, y = 20 })
suite.check("away from a door it asks nothing", #shown == 0)
SwitchGear:NoteSpot(door)
local card = shown[1]
suite.check("at the door it asks", card ~= nil and card.title == "SCARLET MONASTERY", card and card.title)
suite.check("in the card's words", card and card.line == "Put on your Protection gear."
    and card.text == "3 pieces from your bags." and card.always == true, card and card.text)
SwitchGear:NoteSpot(door)
suite.check("once while standing there", #shown == 1, #shown)
card.actions[2].fn()
SwitchGear:NoteSpot({ zone = "Tirisfal Glades", x = 20, y = 20 })
SwitchGear:NoteSpot(door)
suite.check("Not Now keeps that door quiet a while", #shown == 1, #shown)
SwitchGear.quiet = {}
SwitchGear:NoteSpot({ zone = "Tirisfal Glades", x = 20, y = 20 })
SwitchGear:NoteSpot(door)
card = shown[2]
suite.check("later it asks again", card ~= nil)
card.actions[1].fn()
suite.check("Put It On puts the Off Spec's gear on", Worn() == "item:3/item:4/item:12", Worn())
SwitchGear:NoteSpot({ zone = "Tirisfal Glades", x = 20, y = 20 })
SwitchGear:NoteSpot(door)
suite.check("with the Off Spec's gear on it asks nothing", #shown == 2, #shown)
ns.Toast.Show = realShow

-- The banner takes words in the item's place, and shows with the upgrade
-- banner switched off.
ns.db.upgradeToast = false
suite.check("the door card shows with the upgrade banner off",
    ns.Toast:Show({ title = "X", line = "Put on your Protection gear.", always = true }) == true
    and ns.Toast.item:GetText() == "Put on your Protection gear.")
suite.check("an upgrade banner still does not", ns.Toast:Show({ title = "Y", link = "item:12" }) == false)
ns.Toast:Dismiss()
ns.db.upgradeToast = nil

-- 8.
local Gear = ns.GearWindow
if Gear and Gear.Open then
    Gear:Open("gear")

end
local MyGear = ns.MyGear
if MyGear.page and MyGear:IsShown() then
    MyGear:Refresh()
    suite.check("My Gear shows the row with an Off Spec picked", MyGear.switchBar:IsShown())
    suite.check("naming both specs", MyGear.switchMain.label:GetText() == "Main Spec (Retribution)"
        and MyGear.switchOff.label:GetText() == "Off Spec (Protection)", MyGear.switchMain.label:GetText())
    suite.check("the button puts the Main Spec's gear back", MyGear.switchGo.label:GetText() == "Put On Retribution Gear",
        MyGear.switchGo.label:GetText())
    MyGear.switchGo:GetScript("OnClick")(MyGear.switchGo)
    suite.check("a click switches", Worn() == "item:1/nil/item:10", Worn())
    OffSpec:Set(nil)
    MyGear:PaintSwitch()
    suite.check("with None the row is gone", not MyGear.switchBar:IsShown())
else
    suite.check("My Gear opens in the fake game", false)
end

-- The key and the command.
suite.check("the key has a name", type(_G.BINDING_NAME_BLACKTHORNESEQUIPMENT_SWITCHGEAR) == "string")
suite.check("/beq swap is listed", ns.commands.swap ~= nil)

suite.done()
