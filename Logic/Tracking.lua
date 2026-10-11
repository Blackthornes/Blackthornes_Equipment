-- Blackthornes Equipment -- Logic/Tracking.lua
-- Upgrades the player has picked to go after.
--
-- Track one from the upgrade finder or a character-sheet slot, and it goes
-- on the tracker (UI/TrackerPanel.lua) with where to get it, gets a pin on
-- the world map (UI/MapPins.lua), and a banner says so the moment it lands
-- in the bags (UI/Toast.lua). Once it is worn the hunt is done: it moves to
-- the list of finished ones.
--
-- Kept per character, since upgrades are, in BlackthornesEquipmentCharDB:
--   tracked      { [itemID] = { link, slot, at, got, place } }
--   trackedDone  { { itemID, link, at, done }, ... } newest first
-- Both are made the first time something is tracked, and like every saved
-- key they are never renamed or cleared by an update.

local _, ns = ...

local Tracking = ns.NewModule("Tracking")

local Items = ns.Items

-- How many finished hunts are kept.
local DONE_KEPT = 30

local function Now()
    local ok, value = pcall(function() return time() end)
    return ok and value or 0
end

local function Store(create)
    local char = ns.charDB
    if not char then return nil end
    if type(char.tracked) ~= "table" then
        if not create then return nil end
        char.tracked = {}
    end
    return char.tracked
end

local function DoneList(create)
    local char = ns.charDB
    if not char then return nil end
    if type(char.trackedDone) ~= "table" then
        if not create then return nil end
        char.trackedDone = {}
    end
    return char.trackedDone
end

--- Where to go for a source, kept with the hunt so the tracker and the map
--- pin need no new scan: { text, kind, zone, x, y }.
local function PlaceOf(source)
    if type(source) ~= "table" then return nil end
    local text = ns.Finder and ns.Finder.Label(source) .. "  " .. ns.Finder:Describe(source) or nil
    return {
        text = text, kind = source.kind, label = ns.Finder and ns.Finder.Label(source),
        name = source.name, zone = source.zone, x = source.x, y = source.y,
    }
end
Tracking.PlaceOf = PlaceOf

function Tracking:IsTracked(itemID)
    local store = Store(false)
    return store ~= nil and store[itemID] ~= nil
end

--- Track a finder pick (or anything with itemID, link, sources and a
--- result carrying the slot).
-- @return true when it is now tracked
function Tracking:Track(pick)
    local itemID = pick and tonumber(pick.itemID)
    if not itemID then return false end
    local store = Store(true)
    if not store then return false end
    store[itemID] = {
        link = Items.PlainLink(pick.link) or ("item:%d"):format(itemID),
        slot = pick.result and pick.result.slot or pick.slot,
        at = Now(),
        place = PlaceOf(pick.sources and pick.sources[1]),
    }
    self:Changed()
    return true
end

function Tracking:Untrack(itemID)
    local store = Store(false)
    if not (store and store[itemID]) then return false end
    store[itemID] = nil
    self:Changed()
    return true
end

--- Track it if it is not, stop if it is.
-- @return true when it is tracked afterwards
function Tracking:Toggle(pick)
    local itemID = pick and tonumber(pick.itemID)
    if not itemID then return false end
    if self:IsTracked(itemID) then
        self:Untrack(itemID)
        return false
    end
    return self:Track(pick)
end

--- The hunts, oldest first: { itemID, link, slot, at, got, place }.
function Tracking:List()
    local list = {}
    for itemID, hunt in pairs(Store(false) or {}) do
        if type(hunt) == "table" then
            list[#list + 1] = {
                itemID = itemID, link = hunt.link, slot = hunt.slot, at = hunt.at or 0,
                got = hunt.got, place = hunt.place,
            }
        end
    end
    table.sort(list, function(a, b)
        if a.at ~= b.at then return a.at < b.at end
        return a.itemID < b.itemID
    end)
    return list
end

function Tracking:Count()
    local count = 0
    for _ in pairs(Store(false) or {}) do count = count + 1 end
    return count
end

--- The finished hunts, newest first.
function Tracking:Done()
    return DoneList(false) or {}
end

--------------------------------------------------------------------------------
-- Watching the bags and the gear
--------------------------------------------------------------------------------

local function IDOf(link)
    local ok, id = pcall(function() return tonumber(link:match("item:(%d+)")) end)
    return ok and id or nil
end

--- The item IDs carried in the bags and worn, as two sets.
function Tracking:Holding()
    local carried, worn = {}, {}
    for bag = 0, 4 do
        for slot = 1, Items:BagSize(bag) do
            local id = IDOf(Items:InBag(bag, slot) or "")
            if id then carried[id] = true end
        end
    end
    for slot = 1, 19 do
        local id = IDOf(Items:Equipped(slot) or "")
        if id then worn[id] = true end
    end
    return carried, worn
end

--- Look at what is held: a tracked item that came into the bags is got
--- (and a banner says so), one that is worn is done.
function Tracking:Check()
    local store = Store(false)
    if not store or not next(store) then return end
    local carried, worn = self:Holding()
    local changed = false

    for itemID, hunt in pairs(store) do
        if type(hunt) ~= "table" then
            store[itemID] = nil
        elseif worn[itemID] then
            store[itemID] = nil
            local done = DoneList(true)
            table.insert(done, 1, { itemID = itemID, link = hunt.link, at = hunt.at, done = Now() })
            for i = #done, DONE_KEPT + 1, -1 do done[i] = nil end
            changed = true
            if ns.Toast then
                ns.Toast:Show({ title = "Hunt done", link = hunt.link, text = "Wearing it now. Nice." })
            end
        elseif carried[itemID] and not hunt.got then
            hunt.got = Now()
            changed = true
            if ns.Toast then
                ns.Toast:Show({ title = "Tracked upgrade in your bags", link = hunt.link, wear = true,
                    text = "Put it on to finish the hunt." })
            end
        elseif hunt.got and not carried[itemID] then
            -- Sold, banked or mailed away: back to being hunted.
            hunt.got = nil
            changed = true
        end
    end

    if changed then self:Changed() end
end

--- Tell whatever shows hunts to draw them again.
function Tracking:Changed()
    for _, name in ipairs({ "TrackerPanel", "MapPins", "FinderUI", "SlotUpgrades" }) do
        local module = ns[name]
        if module and module.OnTrackingChanged then pcall(module.OnTrackingChanged, module) end
    end
end

function Tracking:CheckSoon()
    if self.waiting then return end
    self.waiting = true
    local after = _G.C_Timer and _G.C_Timer.After
    if type(after) ~= "function" then
        self.waiting = false
        pcall(self.Check, self)
        return
    end
    after(0.3, function()
        Tracking.waiting = false
        pcall(Tracking.Check, Tracking)
    end)
end

function Tracking:OnEnable()
    ns.RegisterEvent(self, "BAG_UPDATE_DELAYED", self.CheckSoon)
    ns.RegisterEvent(self, "PLAYER_EQUIPMENT_CHANGED", self.CheckSoon)
end

--------------------------------------------------------------------------------
-- /beq tracked
--------------------------------------------------------------------------------

ns.RegisterCommand("tracked", "the upgrades you are tracking (/beq tracked clear stops them all)", function(rest)
    if (rest or ""):lower():match("^%s*clear") then
        local store = Store(false)
        if store then
            for itemID in pairs(store) do store[itemID] = nil end
        end
        Tracking:Changed()
        ns.Print("stopped tracking every upgrade")
        return
    end
    local list = Tracking:List()
    if #list == 0 then
        ns.Print("you are not tracking any upgrades. Right-click one in /beq find to track it.")
        return
    end
    ns.Print(("tracking %d upgrade%s"):format(#list, #list == 1 and "" or "s"))
    for _, hunt in ipairs(list) do
        local where = hunt.place and hunt.place.text or ""
        local state = hunt.got and ("|c%s in your bags|r"):format(ns.COLORS.upgrade) or ""
        ns.PrintRaw(("  %s%s  |c%s%s|r"):format(hunt.link or "?", state, ns.COLORS.muted, where))
    end
end)
