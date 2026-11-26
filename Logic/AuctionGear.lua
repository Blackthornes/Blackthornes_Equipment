-- Blackthornes Equipment -- Logic/AuctionGear.lua
-- Auction house gear as upgrades, from Blackthornes Tradeskills' last scan.
--
-- The owner said build it from a mockup (2026-11-26, players asked on
-- Discord): Find Upgrades lists gear on the auction house that beats what
-- you wear. Nothing here scans the auction house. It reads, inside a pcall
-- and read only, what Tradeskills saw listed at its own recent scans
-- (`Prices:OnSale()`), and reads again when Tradeskills says a scan
-- finished (`Prices:WatchScans`). Without Tradeskills there is nothing to
-- read, and the Auction House box is hidden.
--
-- Gear with random suffixes is left out for now: the game's best roll is
-- not the roll on sale.

local _, ns = ...
local L = ns.L

local AuctionGear = ns.NewModule("AuctionGear")

-- Gear slots worth reading; anything else on the auction house is not gear.
local NOT_WORN = { [""] = true, INVTYPE_NON_EQUIP = true, INVTYPE_NON_EQUIP_IGNORE = true,
    INVTYPE_BAG = true, INVTYPE_AMMO = true, INVTYPE_QUIVER = true, INVTYPE_TABARD = true,
    INVTYPE_BODY = true }

--- Tradeskills' prices, when it is loaded and has the call this needs.
local function TSPrices()
    local ts = _G.BlackthornesTS
    if type(ts) ~= "table" then return nil end
    local ok, prices = pcall(function() return ts.Prices end)
    if not ok or type(prices) ~= "table" or type(prices.OnSale) ~= "function" then return nil end
    return prices
end

--- Can the auction house be read? Tradeskills is loaded with the call.
function AuctionGear:On()
    return TSPrices() ~= nil
end

--- Listen for Tradeskills' scans, once.
function AuctionGear:Watch()
    if self.watching then return end
    local prices = TSPrices()
    if not (prices and type(prices.WatchScans) == "function") then return end
    self.watching = true
    pcall(prices.WatchScans, prices, function() AuctionGear:ScanFinished() end)
end

--- Tradeskills finished a scan: read again, and look for upgrades again.
function AuctionGear:ScanFinished()
    self.list, self.ids = nil, nil
    if ns.Finder then ns.Finder:MarkStale() end
    local find = ns.FindUpgrades
    if find and find.RefreshSoon then pcall(find.RefreshSoon, find) end
end

--- What was on sale at the recent scans: { [itemID] = { price, count,
--- seen } }, and when the last scan was. Read once a scan.
function AuctionGear:List()
    self:Watch()
    if self.list then return self.list, self.at end
    local prices = TSPrices()
    local list, at = {}, nil
    if prices then
        local ok, got, when = pcall(prices.OnSale, prices)
        if ok and type(got) == "table" then list, at = got, tonumber(when) end
    end
    self.list, self.at = list, at
    return list, at
end

--- When the last scan was (seconds since the epoch), or nil.
function AuctionGear:LastScan()
    local _, at = self:List()
    return at
end

--- One item's entry, or nil when it was not on sale. Random suffix gear is
--- never offered.
function AuctionGear:For(itemID)
    local entry = self:List()[itemID]
    if type(entry) ~= "table" or not tonumber(entry.price) then return nil end
    local rolls = ns.RollData and ns.RollData.ITEMS
    if rolls and rolls[itemID] then return nil end
    return entry
end

--- Is this item gear, by the client's instant item info? Nil while it can't say.
local function IsGear(itemID)
    local Items = ns.Items
    local _, _, _, equipLoc, _, classID = Items.Call({ "C_Item.GetItemInfoInstant", "GetItemInfoInstant" },
        ("item:%d"):format(itemID))
    classID = tonumber(classID)
    if classID == nil then return nil end
    if classID ~= 2 and classID ~= 4 then return false end
    return type(equipLoc) == "string" and not NOT_WORN[equipLoc]
end

--- The gear on sale, as item IDs in order. Kept until the next scan.
function AuctionGear:IDs()
    if self.ids then return self.ids end
    local ids = {}
    for itemID in pairs(self:List()) do
        if type(itemID) == "number" and self:For(itemID) and IsGear(itemID) ~= false then
            ids[#ids + 1] = itemID
        end
    end
    table.sort(ids)
    self.ids = ids
    return ids
end

--- An item on sale as a finder source: { kind = "auction", price, count,
--- seen, at }, or nil.
function AuctionGear:Source(itemID)
    local entry = self:For(itemID)
    if not entry then return nil end
    return {
        kind = "auction", price = tonumber(entry.price), count = tonumber(entry.count),
        seen = tonumber(entry.seen), at = self.at,
    }
end

--- "2 hours", "5 minutes", "1 day": how long ago, for "your last scan, 2
--- hours ago". Nil without a time.
function AuctionGear.Ago(at)
    at = tonumber(at)
    if not at then return nil end
    local now = (_G.time and _G.time()) or at
    local seconds = math.max(0, now - at)
    if seconds < 3600 then
        local minutes = math.max(1, math.floor(seconds / 60))
        return minutes == 1 and L["1 minute"] or L.Format("%d minutes", minutes)
    end
    if seconds < 86400 then
        local hours = math.floor(seconds / 3600)
        return hours == 1 and L["1 hour"] or L.Format("%d hours", hours)
    end
    local days = math.floor(seconds / 86400)
    return days == 1 and L["1 day"] or L.Format("%d days", days)
end

--------------------------------------------------------------------------------
-- The most to pay (Find Upgrades' Auction Price)
--------------------------------------------------------------------------------

-- The choices, in copper: Any, Up to 1g, Up to 5g, Up to 20g.
AuctionGear.MOST = { 0, 10000, 50000, 200000 }

--- The most the player would pay, in copper, or nil for any. Saved account
--- wide as `findAuctionMost`.
function AuctionGear:Most()
    local most = tonumber(ns.db and ns.db.findAuctionMost)
    if not most or most <= 0 then return nil end
    return most
end

function AuctionGear:SetMost(copper)
    if not ns.db then return end
    copper = tonumber(copper)
    ns.db.findAuctionMost = (copper and copper > 0) and copper or nil
end

--- Can the player pay for it? Within the Auction Price picked and the
--- gold they carry.
function AuctionGear:Affords(source)
    local price = type(source) == "table" and tonumber(source.price)
    if not price then return false end
    local most = self:Most()
    if most and price > most then return false end
    local held = ns.Finder and ns.Finder.MoneyHeld and ns.Finder.MoneyHeld()
    if held and price > held then return false end
    return true
end

function AuctionGear:OnEnable()
    self:Watch()
end
