-- Blackthornes Equipment -- Logic/ItemSets.lua
-- Set bonuses when judging gear.
--
-- The owner asked (2026-11-08): when the player wears enough pieces of a set
-- for a bonus, that bonus counts when judging what would replace a piece.
-- Data/ItemSets.lua (from the Forever client's game tables) says which items
-- are in each set and the stats each bonus gives. A swap is judged on what
-- the worn sets give before and after it: a bonus it would break counts
-- against the new item, and a bonus it would finish or keep counts for it.
-- Bonuses that change a spell or proc give nothing here.
--
-- Only the character playing: alts are judged without sets. Nothing is
-- scanned; Compare asks for one swap at a time, and the worn sets are read
-- again only after the gear changes.

local _, ns = ...

local ItemSets = ns.NewModule("ItemSets")

local Items = ns.Items
local Weights = ns.Weights

-- Health and mana count as the stamina and intellect that give them, as
-- they do for enchants.
local HEALTH_PER_STAMINA, MANA_PER_INTELLECT = 10, 15

-- Every slot a set piece can be worn in.
local FIRST_SLOT, LAST_SLOT = 1, 19

local setOf      -- [item ID] = set ID, laid out once
local worn       -- [slot] = item ID, read again after a gear change
local values = setmetatable({}, { __mode = "k" })   -- [weights][set][count] = score

local function Data()
    return ns.ItemSetData or { SETS = {} }
end

local function IDOf(link)
    if type(link) == "number" then return link end
    return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end
ItemSets.IDOf = IDOf

--- The set an item is in, or nil.
function ItemSets:SetOf(item)
    if not setOf then
        setOf = {}
        for setID, set in pairs(Data().SETS) do
            for _, itemID in ipairs(set.items or {}) do
                if not setOf[itemID] then setOf[itemID] = setID end
            end
        end
    end
    local id = IDOf(item)
    return id and setOf[id] or nil
end

--- Can the character playing get a set's bonuses at all? A set that asks
--- for a profession counts only once Crafting reads that skill high enough.
function ItemSets:Allowed(set)
    if not set.skill or set.skill == 0 then return true end
    local crafting = ns.Crafting
    if not (crafting and crafting.Professions) then return false end
    local ok, known = pcall(crafting.Professions, crafting)
    local rank = ok and type(known) == "table" and known[set.skill]
    return type(rank) == "number" and rank >= (set.rank or 0)
end

--- What one bonus gives, as stats Weights:Score reads.
function ItemSets.StatsOf(bonus)
    local stats = {}
    for key, value in pairs(bonus or {}) do
        if key == "health" then
            stats.stamina = (stats.stamina or 0) + value / HEALTH_PER_STAMINA
        elseif key == "mana" then
            stats.intellect = (stats.intellect or 0) + value / MANA_PER_INTELLECT
        else
            stats[key] = (stats[key] or 0) + value
        end
    end
    return stats
end

--- What a set gives with `count` of its pieces worn, scored with these
--- weights. Kept per weights table.
function ItemSets:Value(setID, count, weights)
    local set = Data().SETS[setID]
    if not set or count < 2 or not self:Allowed(set) then return 0 end
    local byWeights = values[weights]
    if not byWeights then byWeights = {}; values[weights] = byWeights end
    local bySet = byWeights[setID]
    if not bySet then bySet = {}; byWeights[setID] = bySet end
    if bySet[count] then return bySet[count] end
    local total = 0
    for pieces, bonus in pairs(set.b or {}) do
        if count >= pieces then
            total = total + (Weights:Score(ItemSets.StatsOf(bonus), weights, false) or 0)
        end
    end
    bySet[count] = total
    return total
end

--- What the character wears, { [slot] = item ID }.
function ItemSets:Worn()
    if worn then return worn end
    worn = {}
    for slot = FIRST_SLOT, LAST_SLOT do
        local id = IDOf(Items:Equipped(slot))
        if id then worn[slot] = id end
    end
    return worn
end

-- How many different pieces of each set a worn table holds.
local function Counts(wornIDs)
    local counts, seen = {}, {}
    for _, id in pairs(wornIDs) do
        local setID = not seen[id] and ItemSets:SetOf(id)
        seen[id] = true
        if setID then counts[setID] = (counts[setID] or 0) + 1 end
    end
    return counts
end

--- How much the worn sets' bonuses change if `link` goes on in place of
--- what is in `slots` (every slot it would empty: a two-hander empties the
--- off hand too). Above 0 the swap gains bonuses, below 0 it loses them.
--- Nil when no set is touched, so most items cost one lookup a slot.
function ItemSets:Change(link, slots, weights)
    if type(slots) ~= "table" or not weights then return nil end
    local newSet = self:SetOf(link)
    local touched = newSet ~= nil
    if not touched then
        for _, slot in ipairs(slots) do
            if self:SetOf(Items:Equipped(slot)) then touched = true; break end
        end
    end
    if not touched then return nil end

    local before = self:Worn()
    local after = {}
    for slot, id in pairs(before) do after[slot] = id end
    for _, slot in ipairs(slots) do after[slot] = nil end
    after[slots[1] or 0] = IDOf(link)

    local was, will = Counts(before), Counts(after)
    local change, sets = 0, {}
    for setID in pairs(was) do sets[setID] = true end
    for setID in pairs(will) do sets[setID] = true end
    for setID in pairs(sets) do
        change = change + self:Value(setID, will[setID] or 0, weights)
            - self:Value(setID, was[setID] or 0, weights)
    end
    return change
end

--- Fold a swap's set change into the two scores Compare weighs: a gain
--- adds to the new item's score, a loss to the score it has to beat. The
--- third return is the change, or nil when no set was touched.
function ItemSets:Apply(link, slots, weights, score, against)
    local change = self:Change(link, slots, weights)
    if not change or change == 0 then return score, against, change end
    if change > 0 then return score + change, against, change end
    return score, (against or 0) - change, change
end

--- Forget the worn gear, read again on the next ask.
function ItemSets:GearChanged()
    worn = nil
end

--- Forget kept bonus values: a profession's skill moved.
function ItemSets:Forget()
    worn = nil
    values = setmetatable({}, { __mode = "k" })
end

function ItemSets:OnEnable()
    ns.RegisterEvent(self, "PLAYER_EQUIPMENT_CHANGED", self.GearChanged)
    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", self.GearChanged)
    ns.RegisterEvent(self, "SKILL_LINES_CHANGED", self.Forget)
    ns.RegisterEvent(self, "PLAYER_LEVEL_UP", self.Forget)
end
