-- Blackthornes Equipment -- Data/Items.lua
-- Everything this addon reads about an item: what it is, where it goes, the
-- level it needs, its stats, and what is worn or sitting in a bag slot.
--
-- Read only, and every call is in a pcall. Forever is a retail engine, so the
-- C_Item and C_Container calls come first and the older globals are the
-- fallback. /beq probe says which of them this client has.

local _, ns = ...

local Items = ns.NewModule("Items")

--- Call the first of `paths` the client has, inside a pcall, and hand back
--- everything it returned (nothing if none answered).
local function Call(paths, ...)
    for _, path in ipairs(paths) do
        local fn = _G
        for part in path:gmatch("[^.]+") do
            fn = type(fn) == "table" and fn[part] or nil
        end
        if type(fn) == "function" then
            -- The count is kept, because a return list with a nil in the
            -- middle has no reliable length once it is in a table.
            local result = { n = 0 }
            local function Keep(ok, ...)
                result.n = select("#", ...)
                for i = 1, result.n do result[i] = (select(i, ...)) end
                return ok
            end
            if Keep(pcall(fn, ...)) then
                return unpack(result, 1, result.n)
            end
        end
    end
end

--- A link or item string as a plain Lua string, or nil. Links the game will
--- not let an addon read (in an instance) raise when touched, so the copy is
--- made inside a pcall.
function Items.PlainLink(link)
    if type(link) ~= "string" then return nil end
    local ok, copy = pcall(function()
        if link:find("item:", 1, true) then return link .. "" end
    end)
    if ok then return copy end
    return nil
end

--- What kind of item a link is.
-- @return a table { equipLoc, classID, subclassID, minLevel }, or nil when the
--         client does not know the item yet. minLevel is nil until the item is
--         in the client's cache; GET_ITEM_INFO_RECEIVED says when it arrives.
function Items:Info(link)
    link = self.PlainLink(link)
    if not link then return nil end

    local _, _, _, equipLoc, _, classID, subclassID =
        Call({ "C_Item.GetItemInfoInstant", "GetItemInfoInstant" }, link)

    local name, _, _, _, minLevel, _, _, _, fullLoc, _, _, fullClass, fullSub =
        Call({ "C_Item.GetItemInfo", "GetItemInfo" }, link)

    equipLoc = equipLoc or fullLoc
    classID = classID or fullClass
    subclassID = subclassID or fullSub

    if type(equipLoc) ~= "string" then return nil end

    return {
        equipLoc = equipLoc,
        classID = tonumber(classID),
        subclassID = tonumber(subclassID),
        minLevel = name and tonumber(minLevel) or nil,
    }
end

--- The raw stats table for a link (ITEM_MOD_* keys), or nil.
function Items:Stats(link)
    link = self.PlainLink(link)
    if not link then return nil end

    local stats = Call({ "C_Item.GetItemStats", "GetItemStats" }, link)
    if type(stats) == "table" then return stats end
    return nil
end

--- The link of what is worn in an inventory slot, or nil when it is empty.
function Items:Equipped(slot)
    return self.PlainLink(Call({ "GetInventoryItemLink" }, "player", slot))
end

--- The link of the item in a bag slot, or nil.
function Items:InBag(bag, slot)
    if type(bag) ~= "number" or type(slot) ~= "number" then return nil end
    return self.PlainLink(Call({ "C_Container.GetContainerItemLink", "GetContainerItemLink" }, bag, slot))
end

--- How many slots a bag has (0 when there is no bag there).
function Items:BagSize(bag)
    local size = Call({ "C_Container.GetContainerNumSlots", "GetContainerNumSlots" }, bag)
    return tonumber(size) or 0
end

--- The player's level, or nil.
function Items:PlayerLevel()
    return tonumber((Call({ "UnitLevel" }, "player")))
end

Items.Call = Call
