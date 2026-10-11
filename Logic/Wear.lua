-- Blackthornes Equipment -- Logic/Wear.lua
-- Put an upgrade on in one click (the owner, 2026-10-11: the addons should
-- do the work for the player). The upgrade banner's Put it on button and a
-- click on the gear window's BEST IN BAGS column come here.
--
-- Equipping is the game's own EquipItemByName, which addons may call out
-- of combat; in combat nothing is tried and the player is told. The slot
-- comes from Compare:JudgeCarried (a ring or trinket goes over the weaker
-- of the pair), and the item must still be in the bags. Gear that binds
-- when worn still shows the game's own "this will bind" box, so nothing is
-- bound without the player's say.

local _, ns = ...

local Wear = ns.NewModule("Wear")

local Items = ns.Items

local function InCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

local function Global(path)
    local fn = _G
    for part in path:gmatch("[^.]+") do
        fn = type(fn) == "table" and fn[part] or nil
    end
    return type(fn) == "function" and fn or nil
end

local function IDOf(link)
    return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

--- The bag and slot holding `link` (or the same item), or nil.
function Wear.Find(link)
    local wanted = Items.PlainLink(link)
    local id = IDOf(wanted)
    if not id then return nil end
    local sameItem
    for bag = 0, 4 do
        for slot = 1, Items:BagSize(bag) or 0 do
            local held = Items.PlainLink(Items:InBag(bag, slot))
            if held == wanted then return bag, slot end
            if not sameItem and IDOf(held) == id then sameItem = { bag, slot } end
        end
    end
    if sameItem then return sameItem[1], sameItem[2] end
end

--- Can `link` be put on with a click now? True, or false and why.
function Wear:Can(link)
    if InCombat() then return false, "in combat: put it on after the fight" end
    if not (Global("C_Item.EquipItemByName") or Global("EquipItemByName")) then
        return false, "this game client can't equip from an addon"
    end
    if not Wear.Find(link) then return false, "it's not in your bags" end
    local ok, result = pcall(ns.Compare.JudgeCarried, ns.Compare, link)
    if not (ok and ns.Compare.WearableUpgrade(result)) then
        return false, "it's not an upgrade you can wear now"
    end
    if result.skill then return false, ("train %s first"):format(result.skill) end
    return true, nil, result
end

--- Put `link` on, in the slot Equipment judged it for. True, or false and
--- why (said in chat).
function Wear:PutOn(link)
    local can, why, result = self:Can(link)
    if not can then
        ns.Print(("can't put that on: %s."):format(why))
        return false, why
    end
    local equip = Global("C_Item.EquipItemByName") or Global("EquipItemByName")
    local ok = pcall(equip, Items.PlainLink(link), result and result.slot or nil)
    if not ok then
        ns.Print("the game wouldn't put that on just now.")
        return false, "refused"
    end
    return true
end
