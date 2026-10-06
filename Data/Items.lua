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

--------------------------------------------------------------------------------
-- Spell damage for one school ("Increases damage done by Frost spells and
-- effects by up to 10.")
--
-- Classic's school damage is an Equip: line, not one of the stats
-- GetItemStats hands back, so it is read off the item's tooltip. Kept per
-- link, because the finder judges hundreds of items a scan.
--------------------------------------------------------------------------------

local SCHOOLS = {
    arcane = "arcaneDamage", fire = "fireDamage", frost = "frostDamage",
    nature = "natureDamage", shadow = "shadowDamage", holy = "holyDamage",
}
Items.SCHOOLS = SCHOOLS

local schoolCache = {}

--- The school a line names and by how much, or nil for any other line.
function Items.SchoolLine(text)
    if type(text) ~= "string" then return nil end
    local school, amount = text:match("[Ii]ncreases damage done by (%a+) spells and effects by up to (%d+)")
    local stat = school and SCHOOLS[school:lower()]
    if stat then return stat, tonumber(amount) end
    return nil
end

--- What one tooltip line says, inside a pcall: in an instance the text can
--- be a secret value that raises when read.
local function LineText(line)
    local ok, text = pcall(function()
        if type(line) ~= "table" then return nil end
        local left = line.leftText
        if type(left) ~= "string" then return nil end
        return left .. ""
    end)
    return ok and text or nil
end

--- School spell damage on an item, as { frostDamage = 10 }, or nil when the
--- tooltip cannot be read. An empty table when it has none.
function Items:SchoolDamage(link)
    link = self.PlainLink(link)
    if not link then return nil end
    local known = schoolCache[link]
    if known then return known end

    -- By link first, so a random roll's own line is read; by item ID when
    -- the client has only that (Tradeskills reads sell prices that way).
    local data = Call({ "C_TooltipInfo.GetHyperlink" }, link)
    if type(data) ~= "table" then
        local itemID = tonumber(link:match("item:(%d+)"))
        if itemID then data = Call({ "C_TooltipInfo.GetItemByID" }, itemID) end
    end
    if type(data) ~= "table" or type(data.lines) ~= "table" then return nil end

    local found, lines = {}, 0
    for _, line in ipairs(data.lines) do
        lines = lines + 1
        local stat, amount = Items.SchoolLine(LineText(line))
        if stat then found[stat] = (found[stat] or 0) + amount end
    end
    -- A tooltip for an item the client has not loaded yet is one line
    -- ("Retrieving item information"); that is not "none", so not kept.
    if lines > 1 then schoolCache[link] = found end
    return found
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

--------------------------------------------------------------------------------
-- What the bags and gear hold, to tell a real change from an arrow shot
--
-- Every shot a hunter fires spends ammo, and the client says the bags (and
-- the ammo slot) changed each time. Looking again at every upgrade on each
-- of those hangs the game, so the events are only passed on when what is
-- carried or worn has really changed (Core/Init.lua).
--------------------------------------------------------------------------------

--- Is a link arrows or bullets?
function Items.IsAmmo(link)
    local _, _, _, equipLoc, _, classID = Call({ "C_Item.GetItemInfoInstant", "GetItemInfoInstant" }, link)
    return equipLoc == "INVTYPE_AMMO" or tonumber(classID) == 6
end

--- How many are in a bag slot (1 when the client cannot say).
function Items:SlotCount(bag, slot)
    local info = Call({ "C_Container.GetContainerItemInfo" }, bag, slot)
    if type(info) == "table" then return tonumber(info.stackCount) or 1 end
    local _, count = Call({ "GetContainerItemInfo" }, bag, slot)
    return tonumber(count) or 1
end

--- Everything in the bags with how many, ammo without its count, as one
--- string: the same string means nothing changed but the ammo spent.
function Items:BagSignature()
    local parts = {}
    for bag = 0, 4 do
        for slot = 1, self:BagSize(bag) do
            local link = self:InBag(bag, slot)
            if link then
                local count = self.IsAmmo(link) and "" or ("x" .. self:SlotCount(bag, slot))
                parts[#parts + 1] = bag .. ":" .. slot .. "=" .. link .. count
            end
        end
    end
    return table.concat(parts, ";")
end

--- Everything worn, leaving out the ammo slot, as one string.
function Items:WornSignature()
    local parts = {}
    for slot = 1, 19 do parts[slot] = self:Equipped(slot) or "-" end
    return table.concat(parts, ";")
end

Items.Call = Call
