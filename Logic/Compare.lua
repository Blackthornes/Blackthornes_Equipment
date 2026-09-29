-- Blackthornes Equipment -- Logic/Compare.lua
-- Is this item better than what is worn in its slot, for the spec the
-- character is judged as?
--
-- Each item gets one number from Weights:Score (each stat times its weight),
-- and the verdict is that number against the worn item's. Rings and trinkets
-- have two slots, so a new one is measured against the weaker of the pair. A
-- two-handed weapon is measured against main hand and off hand together.
--
-- The tooltip line and the bag arrow both ask Judge, so they cannot disagree.

local _, ns = ...

local Compare = ns.NewModule("Compare")

local Items = ns.Items
local Weights = ns.Weights

-- Where each kind of item goes. Shirts, tabards, bags and ammunition are
-- left out: they carry no stats worth weighing.
local SLOTS = {
    INVTYPE_HEAD = { 1 },
    INVTYPE_NECK = { 2 },
    INVTYPE_SHOULDER = { 3 },
    INVTYPE_CHEST = { 5 },
    INVTYPE_ROBE = { 5 },
    INVTYPE_WAIST = { 6 },
    INVTYPE_LEGS = { 7 },
    INVTYPE_FEET = { 8 },
    INVTYPE_WRIST = { 9 },
    INVTYPE_HAND = { 10 },
    INVTYPE_FINGER = { 11, 12 },
    INVTYPE_TRINKET = { 13, 14 },
    INVTYPE_CLOAK = { 15 },
    INVTYPE_WEAPON = { 16 },
    INVTYPE_2HWEAPON = { 16 },
    INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 },
    INVTYPE_SHIELD = { 17 },
    INVTYPE_HOLDABLE = { 17 },
    INVTYPE_RANGED = { 18 },
    INVTYPE_RANGEDRIGHT = { 18 },
    INVTYPE_THROWN = { 18 },
    INVTYPE_RELIC = { 18 },
}

-- Weapon damage on these counts as ranged damage; on anything else, melee.
local RANGED = {
    INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true,
}

-- Closer than this, in percent, and the two are called the same: stat
-- weights are a guess, and a 0.3% "upgrade" would be noise.
local SAME_WITHIN = 1

Compare.SLOTS = SLOTS

--- One item's score for these weights, or nil if its stats cannot be read.
function Compare:ScoreOf(link, weights)
    local raw = Items:Stats(link)
    if not raw then return nil end

    local info = Items:Info(link)
    local stats = Weights:Normalize(raw)
    return Weights:Score(stats, weights, info and RANGED[info.equipLoc] or false)
end

--- What is worn where this item would go, and the score to beat.
-- @return against (number), empty (true when every slot it could go in is
--         empty), equipped (true when this very item is already worn)
function Compare:Against(link, equipLoc, weights)
    local slots = SLOTS[equipLoc]

    -- A one-handed weapon also fits the off hand, but only a character who
    -- already has a weapon there is dual wielding; otherwise an empty off
    -- hand would make every dagger look like an upgrade.
    if equipLoc == "INVTYPE_WEAPON" then
        local offHand = Items:Equipped(17)
        local offInfo = offHand and Items:Info(offHand)
        if offInfo and (offInfo.equipLoc == "INVTYPE_WEAPON"
            or offInfo.equipLoc == "INVTYPE_WEAPONOFFHAND") then
            slots = { 16, 17 }
        end
    end

    local weakest, empty = nil, true
    for _, slot in ipairs(slots) do
        local worn = Items:Equipped(slot)
        if worn == link then return 0, false, true end

        local score = 0
        if worn then
            empty = false
            score = self:ScoreOf(worn, weights) or 0
        end
        if not weakest or score < weakest then weakest = score end
    end

    -- A two-hander replaces the off hand too.
    if equipLoc == "INVTYPE_2HWEAPON" then
        local offHand = Items:Equipped(17)
        if offHand then
            empty = false
            weakest = weakest + (self:ScoreOf(offHand, weights) or 0)
        end
    end

    -- An off-hand item cannot go on beside a two-hander; it is up against
    -- the two-hander itself.
    if slots[1] == 17 then
        local mainHand = Items:Equipped(16)
        local mainInfo = mainHand and Items:Info(mainHand)
        if mainInfo and mainInfo.equipLoc == "INVTYPE_2HWEAPON" then
            empty = false
            weakest = self:ScoreOf(mainHand, weights) or 0
        end
    end

    return weakest or 0, empty, false
end

--- The verdict on one item for this character.
--
-- @return nil when the item is not gear this addon judges, or its details are
--         not known yet. Otherwise a table:
--   verdict   "upgrade", "downgrade", "same", "equipped" or "cantuse"
--   specName  the spec it was judged for, "Beast Mastery"
--   className the class it was judged for, "HUNTER"
--   percent   how much better or worse, when there is something to measure
--             against
--   empty     true when it would go in an empty slot
--   level     the level it can be worn from, when that is above the player's
--             (an upgrade that has to wait)
function Compare:Judge(link)
    link = Items.PlainLink(link)
    if not link then return nil end

    local info = Items:Info(link)
    if not info or not SLOTS[info.equipLoc] then return nil end

    local weights, spec = Weights:ForPlayer()
    if not weights then return nil end

    local class = Weights:PlayerClass()
    local result = {
        className = class,
        specName = Weights.SPECS[class][spec].name,
    }

    local usable, fromLevel = Weights:CanUse(class, info.classID, info.subclassID)
    if not usable then
        result.verdict = "cantuse"
        return result
    end

    local playerLevel = Items:PlayerLevel()
    local needs = math.max(info.minLevel or 0, fromLevel or 0)
    if playerLevel and needs > playerLevel then
        result.level = needs
    end

    local score = self:ScoreOf(link, weights)
    if not score then return nil end

    local against, empty, equipped = self:Against(link, info.equipLoc, weights)
    if equipped then
        result.verdict = "equipped"
        return result
    end

    result.score, result.against, result.empty = score, against, empty

    if empty then
        result.verdict = "upgrade"
    elseif against > 0 then
        result.percent = (score - against) / against * 100
        if math.abs(result.percent) < SAME_WITHIN then
            result.verdict = "same"
        elseif result.percent > 0 then
            result.verdict = "upgrade"
        else
            result.verdict = "downgrade"
        end
    elseif score > against then
        -- The worn item scores nothing (a plain shirt-like piece), so any
        -- stats at all are better; there is no percentage to give.
        result.verdict = "upgrade"
    else
        result.verdict = "same"
    end

    return result
end

--- Should this item get the upgrade arrow in the bags? Only a real upgrade
--- that can be worn now.
function Compare:IsUpgradeNow(link)
    local ok, result = pcall(self.Judge, self, link)
    return ok and result ~= nil and result.verdict == "upgrade" and not result.level
end

--------------------------------------------------------------------------------
-- Words
--------------------------------------------------------------------------------

local CLASS_NAMES = { HUNTER = "Hunters" }

--- The line a tooltip shows for a verdict, and the colour to show it in, or
--- nil when there is nothing worth saying (the item is the one worn).
function Compare:Describe(result)
    if not result then return nil end

    local verdict, spec = result.verdict, result.specName
    local percent = result.percent and ("%+d%%"):format(math.floor(result.percent + 0.5)) or nil

    if verdict == "cantuse" then
        return ("%s can't use this"):format(CLASS_NAMES[result.className] or "Your class"), "muted"
    elseif verdict == "equipped" then
        return nil
    elseif verdict == "upgrade" then
        local how = result.empty and "fills an empty slot" or percent or "better stats"
        if result.level then
            return ("Upgrade for %s at level %d: %s"):format(spec, result.level, how), "warn"
        end
        return ("Upgrade for %s: %s"):format(spec, how), "upgrade"
    elseif verdict == "downgrade" then
        return ("Worse for %s: %s"):format(spec, percent), "downgrade"
    end
    return ("About the same for %s"):format(spec), "muted"
end

--------------------------------------------------------------------------------
-- /beq bags
--------------------------------------------------------------------------------

-- The backpack and the four bags beside it.
local FIRST_BAG, LAST_BAG = 0, 4

function Compare:ReportBags()
    local weights, spec = Weights:ForPlayer()
    if not weights then
        ns.Print(("no stat weights for %s yet"):format(Weights:PlayerClass() or "this class"))
        return
    end

    ns.Print(("gear in your bags, judged as |c%s%s|r"):format(ns.COLORS.accent,
        Weights.SPECS[Weights:PlayerClass()][spec].name))

    local shown = 0
    for bag = FIRST_BAG, LAST_BAG do
        for slot = 1, Items:BagSize(bag) do
            local link = Items:InBag(bag, slot)
            local ok, result = pcall(self.Judge, self, link)
            local text, color = nil, nil
            if ok then text, color = self:Describe(result) end
            if text then
                shown = shown + 1
                ns.PrintRaw(("  %s  |c%s%s|r"):format(link, ns.COLORS[color], text))
            end
        end
    end

    if shown == 0 then
        ns.PrintRaw(("  |c%snothing in your bags to wear|r"):format(ns.COLORS.muted))
    end
end

ns.RegisterCommand("bags", "judge every piece of gear in your bags", function()
    Compare:ReportBags()
end)
