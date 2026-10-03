-- Blackthornes Equipment -- UI/UpgradeChat.lua
-- One line in chat when an upgrade you can wear now lands in your bags:
-- looted, bought, sent by mail or traded.
--
-- What counts is an item that is new in the bags, not one that was there and
-- became an upgrade later (a level up, a spec change). Each scan counts the
-- carried bags by item, and only an item whose count went up since the last
-- scan is judged, the same way the bag arrow judges it (Compare:JudgeCarried).
-- Moving an item between bags or splitting a stack leaves the counts as they
-- were, so it says nothing.
--
-- Quiet on purpose:
--   * the first scan after a login, /reload or loading screen, and any scan
--     while the bags settle after one, only takes the counts;
--   * an item that was worn at the last scan, or put on since, is skipped,
--     so taking a piece off (or swapping it for one from the bags) is not
--     news;
--   * the bank and the mailbox are never looked at, only the carried bags;
--   * when a bag slot cannot be read (the game hides links from addons in
--     instances), nothing is said and the next good scan starts afresh.

local _, ns = ...

local UpgradeChat = ns.NewModule("UpgradeChat")

local Compare = ns.Compare
local Items = ns.Items

-- The backpack and the four bags beside it, as Compare counts them.
local FIRST_BAG, LAST_BAG = 0, 4
-- Every slot gear can be worn in.
local LAST_WORN_SLOT = 19
-- Seconds after a loading screen during which the bags are still filling in.
local SETTLE = 3
-- How many scans an item whose details have not arrived gets before it is
-- let go.
local TRIES = 5

local function Field(object, key)
    if type(object) ~= "table" then return nil end
    local ok, value = pcall(function() return object[key] end)
    if ok then return value end
    return nil
end

function UpgradeChat:IsEnabled()
    return not (ns.db and ns.db.upgradeChat == false)
end

--------------------------------------------------------------------------------
-- What is carried and worn
--------------------------------------------------------------------------------

--- How many are in one bag slot: the stack size when the client says, else 1.
local function StackCount(bag, slot)
    local info = Items.Call({ "C_Container.GetContainerItemInfo" }, bag, slot)
    local count = Field(info, "stackCount")
    if count == nil then
        local _, legacy = Items.Call({ "GetContainerItemInfo" }, bag, slot)
        count = legacy
    end
    local ok, number = pcall(tonumber, count)
    if ok and number and number > 0 then return number end
    return 1
end

--- The link in one bag slot. The second return is false when the slot could
--- not be read: the call raised, or the link is one the game will not let an
--- addon touch (in an instance).
local function ReadSlot(bag, slot)
    local fn = Field(_G.C_Container, "GetContainerItemLink")
    if type(fn) ~= "function" then fn = _G.GetContainerItemLink end
    if type(fn) ~= "function" then return nil, false end
    local ok, raw = pcall(fn, bag, slot)
    if not ok then return nil, false end
    if raw == nil then return nil, true end
    local link = Items.PlainLink(raw)
    return link, link ~= nil
end

--- How many of each item the carried bags hold, by plain link. The second
--- return is false when some slot could not be read, so the counts are not
--- to be trusted.
function UpgradeChat:Counts()
    local counts, readable = {}, true
    for bag = FIRST_BAG, LAST_BAG do
        for slot = 1, Items:BagSize(bag) do
            local link, ok = ReadSlot(bag, slot)
            if not ok then readable = false end
            if link then
                counts[link] = (counts[link] or 0) + StackCount(bag, slot)
            end
        end
    end
    return counts, readable
end

--- Every link worn right now, as a set.
function UpgradeChat:Worn()
    local worn = {}
    for slot = 1, LAST_WORN_SLOT do
        local link = Items:Equipped(slot)
        if link then worn[link] = true end
    end
    return worn
end

--------------------------------------------------------------------------------
-- Scanning
--------------------------------------------------------------------------------

--- Is this an item worth waiting for: gear, or something the client has not
--- described yet?
local function MaybeGear(link)
    local ok, info = pcall(Items.Info, Items, link)
    if not ok then return false end
    return info == nil or Compare.SLOTS[info.equipLoc] ~= nil
end

--- Say so for one new item, if it is an upgrade that can be worn now.
-- @return true when it was judged (announced or not), false when its details
--         are not known yet
function UpgradeChat:Consider(link)
    local ok, result = pcall(Compare.JudgeCarried, Compare, link)
    if not ok then return true end
    if not result then return not MaybeGear(link) end

    if Compare.WearableUpgrade(result) then
        ns.Print(("upgrade in your bags: %s |c%s%s|r"):format(
            link, ns.COLORS.upgrade, Compare:HowMuch(result)))
    end
    return true
end

--- Look at the bags once. A baseline scan only takes the counts.
function UpgradeChat:Scan()
    local counts, readable = self:Counts()
    local wornNow = self:Worn()
    local wornBefore = self.worn or {}
    local before = self.counts
    local quiet = before == nil or self.baseline or self.settling or not self:IsEnabled()

    -- A slot that could not be read would make everything in it look new on
    -- the next scan, so the next good scan only takes the counts again.
    if not readable then
        for link in pairs(wornNow) do wornBefore[link] = true end
        self.worn = wornBefore
        self.baseline = true
        return
    end

    -- Items still waiting for their details from the server.
    local pending = {}
    if not quiet then
        for link, tries in pairs(self.pending or {}) do
            if counts[link] and not wornNow[link] and not self:Consider(link) and tries < TRIES then
                pending[link] = tries + 1
            end
        end

        for link, count in pairs(counts) do
            local isNew = count > (before[link] or 0)
            if isNew and not wornBefore[link] and not wornNow[link] and not pending[link]
                and not (self.pending and self.pending[link]) then
                if not self:Consider(link) then pending[link] = 1 end
            end
        end
    end

    self.counts = counts
    self.worn = wornNow
    self.pending = pending
    self.baseline = false
end

--- Scan once things settle, so a burst of bag events costs one pass.
function UpgradeChat:ScanSoon()
    if self.waiting then return end
    self.waiting = true

    local after = Field(_G.C_Timer, "After")
    if type(after) ~= "function" then
        self.waiting = false
        pcall(self.Scan, self)
        return
    end

    after(0.2, function()
        UpgradeChat.waiting = false
        pcall(UpgradeChat.Scan, UpgradeChat)
    end)
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

--- A login, /reload or loading screen: the next scans only take the counts
--- until the bags have had a moment to fill in.
function UpgradeChat:PLAYER_ENTERING_WORLD()
    self.baseline = true
    self.settling = true
    local after = Field(_G.C_Timer, "After")
    if type(after) == "function" then
        after(SETTLE, function()
            UpgradeChat.settling = false
            UpgradeChat:ScanSoon()
        end)
    else
        self.settling = false
    end
    self:ScanSoon()
end

--- Something was put on or taken off. What is worn now joins the set of
--- worn items, so a piece worn even briefly between two scans is still
--- known when it comes back to the bags.
function UpgradeChat:PLAYER_EQUIPMENT_CHANGED()
    local ok, wornNow = pcall(self.Worn, self)
    if not ok then return end
    self.worn = self.worn or {}
    for link in pairs(wornNow) do self.worn[link] = true end
end

--- An item's details arrived: worth another look only if one is waiting.
function UpgradeChat:GET_ITEM_INFO_RECEIVED()
    if self.pending and next(self.pending) then self:ScanSoon() end
end

function UpgradeChat:OnEnable()
    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", self.PLAYER_ENTERING_WORLD)
    ns.RegisterEvent(self, "BAG_UPDATE_DELAYED", self.ScanSoon)
    ns.RegisterEvent(self, "PLAYER_EQUIPMENT_CHANGED", self.PLAYER_EQUIPMENT_CHANGED)
    ns.RegisterEvent(self, "GET_ITEM_INFO_RECEIVED", self.GET_ITEM_INFO_RECEIVED)
end
