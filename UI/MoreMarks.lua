-- Blackthornes Equipment -- UI/MoreMarks.lua
-- The green upgrade arrow in two more places: on a vendor's wares and in the
-- loot window.
--
-- The same arrow as the bags (BagIcons:Arrow), shown on the same verdict:
-- an upgrade that can be worn now. A vendor's page is marked whenever the
-- game redraws it (a new vendor, a new page, the buyback tab), the loot
-- window when it opens or changes. Every frame and call is looked up and
-- used inside a pcall; a client whose windows are built differently simply
-- gets no arrows there. Switched off with the bag arrows setting, since
-- it is the same mark.

local _, ns = ...

local MoreMarks = ns.NewModule("MoreMarks")

local Compare = ns.Compare
local Items = ns.Items

local MERCHANT_BUTTONS = 12
local LOOT_BUTTONS = 4

function MoreMarks:IsEnabled()
    return not (ns.db and ns.db.bagArrows == false)
end

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok then return value end
    return nil
end

local function Mark(button, link)
    if type(button) ~= "table" or not ns.BagIcons then return end
    local show = MoreMarks:IsEnabled() and link ~= nil and Compare:IsUpgradeNow(link)
    local arrow = show and ns.BagIcons:Arrow(button) or ns.BagIcons:ExistingArrow(button)
    if arrow then arrow:SetShown(show and true or false) end
end

--------------------------------------------------------------------------------
-- Vendors
--------------------------------------------------------------------------------

--- The item a vendor's button `i` on the page shows, as a link.
function MoreMarks:MerchantLink(i)
    local frame = _G.MerchantFrame
    if type(frame) ~= "table" then return nil end
    -- The buyback tab shows what was sold, which is never new.
    if rawget(frame, "selectedTab") == 2 then return nil end
    local perPage = tonumber(_G.MERCHANT_ITEMS_PER_PAGE) or 10
    local page = tonumber(rawget(frame, "page")) or 1
    local index = (page - 1) * perPage + i
    local info = _G.C_MerchantFrame
    local link = info and Call(info.GetItemLink, index)
    link = link or Call(_G.GetMerchantItemLink, index)
    return Items.PlainLink(link)
end

function MoreMarks:RefreshMerchant()
    for i = 1, MERCHANT_BUTTONS do
        local button = _G["MerchantItem" .. i .. "ItemButton"]
        if button then Mark(button, self:MerchantLink(i)) end
    end
end

--------------------------------------------------------------------------------
-- Loot
--------------------------------------------------------------------------------

function MoreMarks:RefreshLoot()
    for i = 1, LOOT_BUTTONS do
        local button = _G["LootButton" .. i]
        if button then
            local slot = tonumber(rawget(button, "slot"))
            local link = slot and Items.PlainLink(Call(_G.GetLootSlotLink, slot))
            Mark(button, link)
        end
    end
end

--------------------------------------------------------------------------------
-- Hooks
--------------------------------------------------------------------------------

function MoreMarks:Soon(what)
    local after = _G.C_Timer and _G.C_Timer.After
    local run = function() pcall(what, MoreMarks) end
    if type(after) == "function" then after(0.05, run) else run() end
end

function MoreMarks:OnEnable()
    if type(_G.hooksecurefunc) == "function" then
        for _, name in ipairs({ "MerchantFrame_UpdateMerchantInfo", "MerchantFrame_Update" }) do
            if type(_G[name]) == "function" then
                pcall(_G.hooksecurefunc, name, function() MoreMarks:Soon(MoreMarks.RefreshMerchant) end)
            end
        end
        if type(_G.LootFrame_Update) == "function" then
            pcall(_G.hooksecurefunc, "LootFrame_Update", function() MoreMarks:Soon(MoreMarks.RefreshLoot) end)
        end
    end
    ns.RegisterEvent(self, "MERCHANT_SHOW", function() MoreMarks:Soon(MoreMarks.RefreshMerchant) end)
    ns.RegisterEvent(self, "MERCHANT_UPDATE", function() MoreMarks:Soon(MoreMarks.RefreshMerchant) end)
    ns.RegisterEvent(self, "LOOT_OPENED", function() MoreMarks:Soon(MoreMarks.RefreshLoot) end)
    ns.RegisterEvent(self, "LOOT_SLOT_CLEARED", function() MoreMarks:Soon(MoreMarks.RefreshLoot) end)
end
