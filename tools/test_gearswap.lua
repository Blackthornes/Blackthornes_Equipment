-- Swapping a fishing pole in and out is no gear change.
-- A player's report (2026-11-18): swapping between a fishing pole and a
-- weapon froze the game for 3 to 10 seconds every time. With the pole in
-- hand every weapon looked like an upgrade, so each swap passed on
-- PLAYER_EQUIPMENT_CHANGED and BAG_UPDATE_DELAYED and every verdict, scan
-- and window looked at all the gear again, both ways. While a pole is
-- worn the weapons from before it stand in for it (Data/Items.lua), so a
-- swap passes nothing on.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("gearswap")

local function Weapon(loc, subclass, agi)
    return { loc = loc, class = 2, subclass = subclass, stats = { ITEM_MOD_AGILITY_SHORT = agi } }
end
local sword, rod, mace, shield, axe, chest =
    "item:500", "item:501", "item:502", "item:503", "item:504", "item:505"
local ITEMS = {
    [sword] = Weapon("INVTYPE_2HWEAPON", 8, 10),
    [rod] = Weapon("INVTYPE_2HWEAPON", 20, 0),
    [mace] = Weapon("INVTYPE_WEAPON", 4, 6),
    [shield] = { loc = "INVTYPE_SHIELD", class = 4, subclass = 6, stats = {} },
    [axe] = Weapon("INVTYPE_2HWEAPON", 1, 30),
    [chest] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = { ITEM_MOD_AGILITY_SHORT = 5 } },
}

local ns = env.Load()
_G.UnitClass = function() return "Warrior", "WARRIOR", 1 end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitRace = function() return "Human", "Human", 1 end
local bags = { [0] = { [1] = rod, [2] = chest } }
env.InstallItems(ITEMS, { [16] = sword, [5] = chest }, bags, 30)
local Items = ns.Items

local frame = _G.BlackthornesEquipmentEventFrame
local fire = frame:GetScript("OnEvent")
fire(frame, "ADDON_LOADED", "Blackthornes_Equipment")
fire(frame, "PLAYER_LOGIN")

-- Count what gets past the dispatcher's "nothing changed" check.
local passed = {}
local probe = {}
for _, event in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED" }) do
    ns.RegisterEvent(probe, event, function() passed[event] = (passed[event] or 0) + 1 end)
end
local function Swap(changes)
    passed = {}
    for where, link in pairs(changes) do
        if where == "worn16" then env.worn[16] = link
        elseif where == "worn17" then env.worn[17] = link
        else bags[0][where] = link end
    end
    fire(frame, "PLAYER_EQUIPMENT_CHANGED", 16)
    fire(frame, "BAG_UPDATE_DELAYED")
    return (passed.PLAYER_EQUIPMENT_CHANGED or 0) + (passed.BAG_UPDATE_DELAYED or 0)
end

suite.check("a pole is a fishing pole", Items:IsFishingPole(rod) == true)
suite.check("a sword is not", Items:IsFishingPole(sword) == false)
suite.check("nothing is not", Items:IsFishingPole(nil) == false)

-- The gear as it stands is seen once.
Swap({})
suite.check("the sword worn is remembered", Items:WeaponsUnderPole() and Items:WeaponsUnderPole().main == sword)

-- Pole on, sword into the bag slot the pole came from.
local count = Swap({ worn16 = rod, [1] = sword })
suite.check("putting the pole on passes nothing on", count == 0, count)
suite.check("the sword stands in for the pole", Items:Equipped(16) == sword, tostring(Items:Equipped(16)))
suite.check("what is really worn is the pole", Items:WornNow(16) == rod)
suite.check("a pole in hand with weapons known", Items:PoleInHand() == true)
suite.check("the sword in the bags is judged as worn",
    ns.Compare:Judge(sword) and ns.Compare:Judge(sword).verdict == "equipped",
    ns.Compare:Judge(sword) and ns.Compare:Judge(sword).verdict)

count = Swap({ worn16 = sword, [1] = rod })
suite.check("taking it off passes nothing on", count == 0, count)
suite.check("the sword is worn again", Items:Equipped(16) == sword)

for _ = 1, 5 do
    Swap({ worn16 = rod, [1] = sword })
    count = count + Swap({ worn16 = sword, [1] = rod })
end
suite.check("five more swaps pass nothing on", count == 0, count)

-- A one-hander and a shield: the pole takes both hands, so the shield goes
-- to a free bag slot. Neither swap is a change.
count = Swap({ worn16 = mace, worn17 = shield, [1] = rod })
suite.check("a new weapon worn is passed on", count > 0, count)
suite.check("and is remembered with the shield",
    Items:WeaponsUnderPole().main == mace and Items:WeaponsUnderPole().off == shield)
count = Swap({ worn16 = rod, worn17 = false, [1] = mace, [5] = shield })
suite.check("the pole over a weapon and shield passes nothing on", count == 0, count)
suite.check("the shield stands in for the empty off hand", Items:Equipped(17) == shield)
count = Swap({ worn16 = mace, worn17 = shield, [1] = rod, [5] = false })
suite.check("and back passes nothing on", count == 0, count)

-- A real change while fishing still counts.
Swap({ worn16 = rod, worn17 = false, [1] = mace, [5] = shield })
count = Swap({ [3] = axe })
suite.check("new gear in the bags while fishing is passed on", count > 0, count)
Swap({ worn16 = mace, worn17 = shield, [1] = rod, [3] = false, [5] = false })

-- With no weapons seen before the pole (a new character fishing first), the
-- pole is what is worn.
ns.charDB.weaponsUnderPole = nil
env.worn[16], env.worn[17] = rod, nil
suite.check("with nothing remembered the pole is what is worn", Items:Equipped(16) == rod)
suite.check("and no pole stands in", Items:PoleInHand() == false)
suite.check("a bad save reads as nothing remembered",
    (function() ns.charDB.weaponsUnderPole = "x" return Items:WeaponsUnderPole() == nil end)())

suite.done()
