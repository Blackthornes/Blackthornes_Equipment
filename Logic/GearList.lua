-- The gear list: the gear this character could ever use, sorted once.
--
-- The data tables hold thousands of items, and most are not for the
-- character playing: plate for a mage, gear kept to another class or race.
-- Each item is sorted once a session, from the data's own class and race
-- limits and the client's instant item table (no server answer needed):
--
--   false     never for this character. Scans pass it by with one lookup.
--   "skill"   a weapon or off-hand piece the class can't use with the
--             skills it has now. Sorted again when a skill is learned.
--   a string  gear it can use: the kind of slot it goes in ("INVTYPE_HEAD").
--   nil       the client does not know the item yet. Asked again next time.
--
-- At login the whole list is made on the frame worker (Core/Worker.lua), a
-- few items a frame and never in a fight, so the first scan finds every
-- item sorted. An item met before that, or learned in play (a quest reward
-- or a vendor's stock seen in game), is sorted when a scan reaches it.
--
-- Only what can never change is decided here. Level, sources, quests done
-- and the "Classes:" line on a tooltip are still the finder's to check on
-- each scan, so the list never hides gear the finder would have shown.
-- Nothing is saved: the list is made again each session.

local _, ns = ...

local GearList = ns.NewModule("GearList")

local Items = ns.Items
local Compare = ns.Compare
local Weights = ns.Weights

-- [itemID] = false, "skill" or the item's equipLoc.
local state = {}
-- What the answers were worked out for. Another class or race, or other
-- data tables (the tests swap them), starts the list again.
local madeFor
-- [inventory slot] = { itemID, ... }, made when asked for.
local bySlot
-- Every "skill" answer, so a skill learned clears only those.
local waitingOnSkill = {}

-- How many items were sorted this session (for the tests and the probe).
GearList.sorted = 0

local function HasBit(mask, bit)
    return math.floor(mask / bit) % 2 == 1
end

--- Does a class or race limit from the data let this bit in? The finder's
--- own test (Finder.Allows), so the list and a scan never disagree.
local function Allows(mask, bit)
    if type(mask) ~= "number" or type(bit) ~= "number" then return true end
    return ns.Finder.Allows(mask, bit)
end

--- Start again when the character or the data tables are not the ones the
--- answers were made for. Asked for every item, so nothing is built here.
local function Check(player)
    local S = ns.Sources or {}
    local crafts = ns.Crafts and ns.Crafts.ITEMS
    local made = madeFor
    if made and made.class == player.class and made.classBit == player.classBit
        and made.raceBit == player.raceBit and made.items == S.ITEMS and made.forever == S.FOREVER
        and made.crafts == crafts and made.client == ns.ForeverItems then
        return
    end
    madeFor = {
        class = player.class, classBit = player.classBit, raceBit = player.raceBit,
        items = S.ITEMS, forever = S.FOREVER, crafts = crafts, client = ns.ForeverItems,
    }
    state, bySlot, waitingOnSkill = {}, nil, {}
    GearList.ready = nil
end

--- Sort one item for `player` (Finder:Player()). Nil when the client does
--- not know the item yet; nothing is kept then.
local function Sort(itemID, player)
    GearList.sorted = GearList.sorted + 1
    -- The data's own limits first: they need nothing from the client.
    local S = ns.Sources
    local row = S and S.ITEMS and S.ITEMS[itemID]
    if row and (not Allows(row[3], player.classBit) or not Allows(row[4], player.raceBit)) then
        return false
    end
    local mask = Compare.ClassMask(itemID)
    local bit = Compare.CLASS_BITS[player.class]
    if mask and mask > 0 and bit and not HasBit(mask, bit) then return false end

    local equipLoc, classID, subclassID = Items:Kind(itemID)
    if not equipLoc then return nil end
    local slots = Compare.SLOTS[equipLoc]
    if not slots then return false end
    if not Weights:CanUse(player.class, classID, subclassID, equipLoc) then
        -- A weapon skill learned later can open a weapon or an off-hand
        -- piece. Armor the class can't wear stays that way.
        if classID == 2 or slots[1] >= 16 then return "skill" end
        return false
    end
    return equipLoc
end

--- What the list says about an item, sorting it now if it has not been.
-- @return false, "skill", the equipLoc, or nil (not known yet)
function GearList:State(itemID, player)
    player = player or (ns.Finder and ns.Finder:Player())
    if not player then return nil end
    Check(player)
    local answer = state[itemID]
    if answer ~= nil then return answer end
    answer = Sort(itemID, player)
    if answer == nil then return nil end
    state[itemID] = answer
    if answer == "skill" then waitingOnSkill[itemID] = true end
    if type(answer) == "string" and answer ~= "skill" then bySlot = nil end
    return answer
end

--- Is this item out for the character, as far as the list knows without
--- sorting anything? For the scan's first pass over the data.
function GearList:Out(itemID)
    local answer = state[itemID]
    return answer == false or answer == "skill"
end

--- A weapon skill was learned or dropped: weapons set aside are sorted again.
function GearList:SkillsChanged()
    for itemID in pairs(waitingOnSkill) do state[itemID] = nil end
    waitingOnSkill = {}
end

--- Forget every answer (the tests; nothing in play needs it).
function GearList:Forget()
    madeFor = nil
    state, bySlot, waitingOnSkill = {}, nil, {}
    self.ready = nil
end

--- Every item in the data, as a list of IDs. Made in one pass, so a row
--- learned in play while the list is being made upsets nothing.
local function EveryID()
    local ids, seen = {}, {}
    local function Take(rows)
        for itemID in pairs(type(rows) == "table" and rows or {}) do
            if type(itemID) == "number" and not seen[itemID] then
                seen[itemID] = true
                ids[#ids + 1] = itemID
            end
        end
    end
    Take(ns.Sources and ns.Sources.ITEMS)
    Take(ns.Sources and ns.Sources.FOREVER)
    Take(ns.Crafts and ns.Crafts.ITEMS)
    return ids
end

--- Make the whole list on the frame worker. `done`, when given, is called
--- once it is ready. One making at a time.
function GearList:Make(done)
    local finder = ns.Finder
    local player = finder and finder:Player()
    if not player or self.making then return false end
    Check(player)
    if self.ready then
        if done then done() end
        return true
    end
    self.making = true
    ns.Worker:Run(function(pause)
        for _, itemID in ipairs(EveryID()) do
            if pause then pause() end
            GearList:State(itemID, player)
        end
        return true
    end, function()
        GearList.making = nil
        GearList.ready = true
        if done then pcall(done) end
    end, true)
    return true
end

--- The gear the character can use in an inventory slot (1 to 19), as a
--- list of item IDs, lowest first. Only items sorted so far.
function GearList:ForSlot(slot)
    if not bySlot then
        bySlot = {}
        for itemID, answer in pairs(state) do
            local slots = type(answer) == "string" and Compare.SLOTS[answer]
            for _, into in ipairs(slots or {}) do
                bySlot[into] = bySlot[into] or {}
                bySlot[into][#bySlot[into] + 1] = itemID
            end
        end
        for _, list in pairs(bySlot) do table.sort(list) end
    end
    return bySlot[slot] or {}
end

--- For /beq probe.
function GearList:Describe()
    local usable, never, skill = 0, 0, 0
    for _, answer in pairs(state) do
        if answer == false then
            never = never + 1
        elseif answer == "skill" then
            skill = skill + 1
        else
            usable = usable + 1
        end
    end
    return ("%d usable, %d never, %d waiting on a skill, %s"):format(usable, never, skill,
        self.ready and "ready" or (self.making and "being made" or "not made yet"))
end

function GearList:OnEnable()
    self:Make()
    -- The level or side can't always be read at login.
    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function()
        if not GearList.ready then GearList:Make() end
    end)
end
