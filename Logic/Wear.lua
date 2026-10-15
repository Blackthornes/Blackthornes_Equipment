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
local L = ns.L

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
    if InCombat() then return false, L["you're in combat, so put it on after the fight"] end
    if not (Global("C_Item.EquipItemByName") or Global("EquipItemByName")) then
        return false, L["this game client can't equip from an addon"]
    end
    if not Wear.Find(link) then return false, L["it's not in your bags"] end
    local ok, result = pcall(ns.Compare.JudgeCarried, ns.Compare, link)
    if not (ok and ns.Compare.WearableUpgrade(result)) then
        return false, L["it's not an upgrade you can wear now"]
    end
    if result.skill then return false, L.Format("train %s first", result.skill) end
    return true, nil, result
end

--- Put `link` on, in the slot Equipment judged it for. True, or false and
--- why (said in chat).
function Wear:PutOn(link)
    local can, why, result = self:Can(link)
    if not can then
        ns.Print(L.Format("can't put that on: %s.", why))
        return false, why
    end
    local equip = Global("C_Item.EquipItemByName") or Global("EquipItemByName")
    local ok = pcall(equip, Items.PlainLink(link), result and result.slot or nil)
    if not ok then
        ns.Print(L["the game didn't put that on."])
        return false, "refused"
    end
    return true
end

--------------------------------------------------------------------------------
-- Putting upgrades on by themselves
--
-- "Put on upgrades" (`autoEquip`, account wide, off unless ticked; never
-- rename it; the owner asked 2026-10-15). When an upgrade you can wear now
-- lands in the bags (UpgradeChat:Consider), it is put on with no click,
-- through the same judgement and the same Wear:Can as Put it on. Held back,
-- so the banner offers it as before:
--   * gear that is not soulbound yet and would bind when worn, so its
--     trade and sale value stay the player's call (the game would ask
--     anyway);
--   * gear a Farmer goal or a Tradeskills craft queue still needs
--     (read in a pcall, read only).
-- Never in a fight: it waits for PLAYER_REGEN_ENABLED and is judged again.
-- One piece at a time: each waits until the one before is worn (or not),
-- then is judged again against what is worn now, so two chests in one loot
-- never swap the better one off.
--------------------------------------------------------------------------------

-- Seconds to wait before checking the piece is worn.
Wear.SETTLE = 1

function Wear:AutoOn()
    return ns.db and ns.db.autoEquip == true or false
end

function Wear:SetAuto(on)
    if not ns.db then return end
    ns.db.autoEquip = on and true or false
end

--- Is `link` worn in any slot?
function Wear.IsWorn(link)
    local wanted = Items.PlainLink(link)
    if not wanted then return false end
    for slot = 1, 19 do
        if Items:Equipped(slot) == wanted then return true end
    end
    return false
end

--- Why `link` should be left for the player to put on, or nil.
function Wear:HoldBack(link)
    local bag, slot = Wear.Find(link)
    if not bag then return L["it's not in your bags"] end
    if not Items:SlotBound(bag, slot) then
        local bindType
        pcall(function()
            local info = { Items.Call({ "C_Item.GetItemInfo", "GetItemInfo" }, Items.PlainLink(link)) }
            bindType = tonumber(info[14])
        end)
        if bindType ~= 0 then return L["it would bind to you"] end
    end
    local itemID = IDOf(link)
    local farmer = rawget(_G, "BlackthornesFarmer")
    local goals = type(farmer) == "table" and farmer.Goals
    if goals and type(goals.Find) == "function" then
        local ok, goal = pcall(function()
            local name = Items.Call({ "C_Item.GetItemInfo", "GetItemInfo" }, Items.PlainLink(link))
            return name and goals:Find(name)
        end)
        if ok and goal then return L["a Farmer goal needs it"] end
    end
    local ts = rawget(_G, "BlackthornesTS")
    local butler = type(ts) == "table" and ts.Butler
    if itemID and butler and type(butler.Advise) == "function" then
        local ok, advice = pcall(butler.Advise, butler, itemID)
        if ok and type(advice) == "table" and ((tonumber(advice.need) or 0) > 0 or type(advice.mailTo) == "string") then
            return L["a craft in your queue needs it"]
        end
    end
    return nil
end

--- Should `link` be put on by itself? True, or false and why.
function Wear:CanAuto(link)
    if not self:AutoOn() then return false, "off" end
    local why = self:HoldBack(link)
    if why then return false, why end
    return true
end

local function TellWorn(link, result)
    local ok, how = pcall(ns.Compare.HowMuch, ns.Compare, result)
    if ok and type(how) == "string" then
        ns.Print(L.Format("put on %s |c%s%s|r", link, ns.COLORS.upgrade, how))
    else
        ns.Print(L.Format("put on %s", link))
    end
end

--- Take `link` in hand: put it on now, or after the fight, or after the
--- piece before it. True when it was taken; false when the player should
--- be offered it the usual way. `fallback(link, result)` is called later if
--- the game would not put it on.
function Wear:Auto(link, fallback)
    if not self:CanAuto(link) then return false end
    self.queue = self.queue or {}
    for _, entry in ipairs(self.queue) do
        if entry.link == link then return true end
    end
    self.queue[#self.queue + 1] = { link = link, fallback = fallback }
    self:Next()
    return true
end

--- Put the next waiting piece on, if nothing else is under way.
function Wear:Next()
    if self.busy or InCombat() then return end
    local entry = self.queue and table.remove(self.queue, 1)
    if not entry then return end
    local link = entry.link

    -- Judged again: the bags, what is worn and the fight may have moved.
    local can, _, result = self:Can(link)
    if not can or not self:CanAuto(link) then
        local ok, judged = pcall(ns.Compare.JudgeCarried, ns.Compare, link)
        if Wear.Find(link) and ok and ns.Compare.WearableUpgrade(judged) and entry.fallback then
            pcall(entry.fallback, link, judged)
        end
        return self:Next()
    end

    local equip = Global("C_Item.EquipItemByName") or Global("EquipItemByName")
    local ok = pcall(equip, Items.PlainLink(link), result and result.slot or nil)
    self.busy = true
    local function Check()
        Wear.busy = false
        if ok and Wear.IsWorn(link) then
            TellWorn(link, result)
        elseif entry.fallback then
            pcall(entry.fallback, link, result)
        end
        Wear:Next()
    end
    if rawget(_G, "C_Timer") and type(C_Timer.After) == "function" then
        C_Timer.After(Wear.SETTLE, Check)
    else
        Check()
    end
end

function Wear:OnEnable()
    ns.RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
        if Wear.queue and #Wear.queue > 0 then Wear:Next() end
    end)
end

-- /beq autoequip [on|off]
ns.RegisterCommand("autoequip", L["put upgrades on by themselves when they land in your bags (on, off)"], function(rest)
    local word = (rest or ""):lower():match("^%s*(%S*)")
    local on
    if word == "on" then on = true elseif word == "off" then on = false else on = not Wear:AutoOn() end
    Wear:SetAuto(on)
    if on then
        ns.Print(L["Upgrades go on by themselves when they land in your bags. Gear that would bind to you waits for your click."])
    else
        ns.Print(L["Upgrades wait for your click again."])
    end
end)

-- One card in What's New the first time this ships (UI/WhatsNew.lua).
ns.WHATS_NEW_TIPS = ns.WHATS_NEW_TIPS or {}
table.insert(ns.WHATS_NEW_TIPS, {
    key = "autoEquip",
    title = L["Put on upgrades"],
    icon = [[Interface\Icons\INV_Chest_Chain]],
    paragraphs = {
        L["Equipment can put an upgrade on for you as soon as it lands in your bags. Gear that would bind to you, or that a goal or craft still needs, waits for your click. It's off until you turn it on."],
    },
    hint = L["You can also find it in Equipment's Settings or type /beq autoequip."],
    button = L["Turn it on"],
    due = function() return not Wear:AutoOn() end,
    run = function() Wear:SetAuto(true) end,
})
