-- Blackthornes Equipment -- Logic/Rolls.lua
-- Random rolls: gear "of the Monkey", "of the Owl" and the rest.
--
-- In Classic a green can drop with one of several rolls, each adding its own
-- stats. Data/Rolls.lua says which rolls an item can have and how often
-- (Classic data); the game says what each roll gives when asked about a
-- link that carries it. So the finder can judge every roll an item might
-- come with, show the best one, and say how likely it is.
--
-- Forever's tooltips leave the roll's name off the item, so the tooltip line
-- here names it from the stats it adds.

local _, ns = ...

local Rolls = ns.NewModule("Rolls")

local Items = ns.Items
local Weights = ns.Weights

-- Classic's roll names, by the stats a roll adds. Only names we are sure
-- of; any other roll is described by its stats alone.
local NAMES = {
    strength = "of Strength", agility = "of Agility", stamina = "of Stamina",
    intellect = "of Intellect", spirit = "of Spirit", defense = "of Defense",
    healing = "of Healing", attackPower = "of Power", rangedAttackPower = "of Marksmanship",
    ["stamina+strength"] = "of the Bear", ["agility+strength"] = "of the Tiger",
    ["intellect+strength"] = "of the Gorilla", ["spirit+strength"] = "of the Boar",
    ["agility+stamina"] = "of the Monkey", ["agility+intellect"] = "of the Falcon",
    ["agility+spirit"] = "of the Wolf", ["intellect+stamina"] = "of the Eagle",
    ["intellect+spirit"] = "of the Owl", ["spirit+stamina"] = "of the Whale",
}

-- What a stat reads as, where the client gives no name for it.
local LABELS = {
    ITEM_MOD_STRENGTH_SHORT = "Strength", ITEM_MOD_AGILITY_SHORT = "Agility",
    ITEM_MOD_STAMINA_SHORT = "Stamina", ITEM_MOD_INTELLECT_SHORT = "Intellect",
    ITEM_MOD_SPIRIT_SHORT = "Spirit", ITEM_MOD_ATTACK_POWER_SHORT = "Attack Power",
    ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "Ranged Attack Power",
    ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "Defense", ITEM_MOD_SPELL_HEALING_DONE_SHORT = "Healing",
    ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "Spell Damage", ITEM_MOD_SPELL_POWER_SHORT = "Spell Power",
    ITEM_MOD_MANA_REGENERATION_SHORT = "Mana every 5 sec", RESISTANCE0_NAME = "Armor",
}

--- The roll an item link carries (its suffix ID), or nil for none.
function Rolls.RollOf(link)
    link = Items.PlainLink(link)
    if not link then return nil end
    local itemString = link:match("item:[%-%d:]*")
    if not itemString then return nil end

    -- item:id:enchant:gem1:gem2:gem3:gem4:suffix, empty fields and all.
    local fields, start = {}, 1
    while true do
        local stop = itemString:find(":", start, true)
        fields[#fields + 1] = itemString:sub(start, (stop or 0) - 1)
        if not stop then break end
        start = stop + 1
    end
    local roll = tonumber(fields[8])
    if roll and roll ~= 0 then return roll end
    return nil
end

--- A link for an item with a given roll.
function Rolls.Link(itemID, roll)
    return ("item:%d::::::%d"):format(itemID, roll)
end

--- The stats a roll adds: the link's stats less the plain item's.
-- @return { [ITEM_MOD key] = amount }, or nil when they cannot be read
function Rolls:Added(link)
    local itemID = tonumber((Items.PlainLink(link) or ""):match("item:(%d+)"))
    if not itemID then return nil end
    local rolled = Items:Stats(link)
    if not rolled then return nil end
    local plain = Items:Stats(("item:%d"):format(itemID)) or {}

    local added, any = {}, false
    for key, value in pairs(rolled) do
        local more = (tonumber(value) or 0) - (tonumber(plain[key]) or 0)
        if more > 0 and key ~= "ITEM_MOD_DAMAGE_PER_SECOND_SHORT" then
            added[key], any = more, true
        end
    end
    return any and added or nil
end

local function Label(key)
    local name = _G[key]
    local ok, copy = pcall(function()
        if type(name) == "string" and name ~= "" and not name:find("%%") then return name .. "" end
    end)
    return (ok and copy) or LABELS[key] or key:gsub("^ITEM_MOD_", ""):gsub("_SHORT$", ""):lower()
end

--- A roll in words: its name when known, "of the Monkey", and what it adds,
--- "+5 Agility, +5 Stamina". Either can be nil.
function Rolls:Describe(link)
    local added = self:Added(link)
    if not added then return nil, nil end

    local keys, parts = {}, {}
    for key in pairs(added) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return added[a] > added[b] or (added[a] == added[b] and a < b) end)
    local named = {}
    for _, key in ipairs(keys) do
        parts[#parts + 1] = ("+%d %s"):format(added[key], Label(key))
        local stat = Weights.STAT_KEYS[key]
        if stat then named[#named + 1] = stat end
    end
    table.sort(named)
    local name = #named == #keys and NAMES[table.concat(named, "+")] or nil
    return name, table.concat(parts, ", ")
end

--- The best roll an item can come with for this character, judged the
--- same way as everything else.
-- @return nil when the item has no rolls or none can be judged yet, or a
--         table { link, result, roll, chance, upgradeChance, rolls } where
--         chance is the best roll's chance in percent and upgradeChance
--         the chance that the item drops with any roll that is an upgrade
function Rolls:Best(itemID)
    local data = ns.RollData
    local group = data and data.ITEMS[itemID]
    local list = group and data.GROUPS[group]
    if not list then return nil end

    local best, upgradeChance, judged = nil, 0, 0
    for i = 1, #list, 2 do
        local link = self.Link(itemID, list[i])
        if self:Added(link) then
            local ok, result = pcall(ns.Compare.Judge, ns.Compare, link)
            if ok and result then
                judged = judged + 1
                if result.verdict == "upgrade" then upgradeChance = upgradeChance + list[i + 1] end
                local score = result.score or 0
                if not best or score > (best.result.score or 0) then
                    best = { link = link, result = result, roll = list[i], chance = list[i + 1] }
                end
            end
        end
    end
    if not best then return nil end
    best.upgradeChance = math.min(100, upgradeChance)
    best.rolls = judged
    return best
end

--- "9.5%", "40%", "< 1%".
function Rolls.Percent(value)
    value = tonumber(value) or 0
    if value < 1 then return "< 1%" end
    if value >= 10 then return ("%d%%"):format(math.floor(value + 0.5)) end
    return (("%.1f"):format(value):gsub("%.0$", "")) .. "%"
end
