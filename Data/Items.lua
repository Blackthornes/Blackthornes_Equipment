-- Blackthornes Equipment -- Data/Items.lua
-- Everything this addon reads about an item: what it is, where it goes, the
-- level it needs, its stats, and what is worn or sitting in a bag slot.
--
-- Read only, and every call is in a pcall. Forever is a retail engine, so the
-- C_Item and C_Container calls come first and the older globals are the
-- fallback. /beq probe says which of them this client has.

local _, ns = ...

local Items = ns.NewModule("Items")

-- Each path split into its parts once, not on every call.
local partsOf = {}

local function Resolve(path)
    local parts = partsOf[path]
    if not parts then
        parts = {}
        for part in path:gmatch("[^.]+") do parts[#parts + 1] = part end
        partsOf[path] = parts
    end
    local fn = _G
    for i = 1, #parts do
        fn = type(fn) == "table" and fn[parts[i]] or nil
    end
    return fn
end

--- Call the first of `paths` the client has, inside a pcall, and hand back
--- everything it returned (nothing if none answered).
-- Everything is read through here (each bag slot, each worn item, each item
-- judged), so it makes no table or function per call: the returns are held
-- in locals, enough for the longest the client gives (GetItemInfo's 18).
local function Call(paths, ...)
    for i = 1, #paths do
        local fn = Resolve(paths[i])
        if type(fn) == "function" then
            local ok, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12, r13, r14, r15,
                r16, r17, r18, r19, r20 = pcall(fn, ...)
            if ok then
                return r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12, r13, r14, r15,
                    r16, r17, r18, r19, r20
            end
        end
    end
end

-- The paths read most, made once.
local INSTANT = { "C_Item.GetItemInfoInstant", "GetItemInfoInstant" }
local ITEM_INFO = { "C_Item.GetItemInfo", "GetItemInfo" }
local ITEM_STATS = { "C_Item.GetItemStats", "GetItemStats" }
local WORN_LINK = { "GetInventoryItemLink" }
local BAG_LINK = { "C_Container.GetContainerItemLink", "GetContainerItemLink" }
local BAG_SLOTS = { "C_Container.GetContainerNumSlots", "GetContainerNumSlots" }
local SLOT_INFO = { "C_Container.GetContainerItemInfo" }
local OLD_SLOT_INFO = { "GetContainerItemInfo" }

local function CopyLink(link)
    if link:find("item:", 1, true) then return link .. "" end
end

--- A link or item string as a plain Lua string, or nil. Links the game will
--- not let an addon read (in an instance) raise when touched, so the copy is
--- made inside a pcall.
function Items.PlainLink(link)
    if type(link) ~= "string" then return nil end
    local ok, copy = pcall(CopyLink, link)
    if ok then return copy end
    return nil
end

-- What Info found, by link, once the client had the whole item.
local infoOf = {}

--- What kind of item a link is.
-- @return a table { equipLoc, classID, subclassID, minLevel }, or nil when the
--         client does not know the item yet. minLevel is nil until the item is
--         in the client's cache; GET_ITEM_INFO_RECEIVED says when it arrives.
function Items:Info(link)
    link = self.PlainLink(link)
    if not link then return nil end

    -- What kind of item a link is never changes, and every verdict asks
    -- (the finder asks thousands of times a scan), so the answer is kept
    -- once the client has the whole item. Read only: never change it.
    local kept = infoOf[link]
    if kept then return kept end

    local _, _, _, equipLoc, _, classID, subclassID =
        Call(INSTANT, link)

    local name, _, _, _, minLevel, _, _, _, fullLoc, _, _, fullClass, fullSub =
        Call(ITEM_INFO, link)

    equipLoc = equipLoc or fullLoc
    classID = classID or fullClass
    subclassID = subclassID or fullSub

    if type(equipLoc) ~= "string" then return nil end

    local info = {
        equipLoc = equipLoc,
        classID = tonumber(classID),
        subclassID = tonumber(subclassID),
        minLevel = name and tonumber(minLevel) or nil,
    }
    -- Kept only with its name in: until then the level it needs is missing.
    if name then infoOf[link] = info end
    return info
end

--- What kind of gear an item is, from the client's own item table alone:
--- the slot kind ("INVTYPE_HEAD"), class and subclass. Nothing is asked of
--- the server, so thousands can be read at login (Logic/GearList.lua). Nil
--- when the client does not know the item.
function Items:Kind(itemID)
    local _, _, _, equipLoc, _, classID, subclassID = Call(INSTANT, ("item:%d"):format(itemID))
    if type(equipLoc) ~= "string" then return nil end
    return equipLoc, tonumber(classID), tonumber(subclassID)
end

--- The raw stats table for a link (ITEM_MOD_* keys), or nil.
function Items:Stats(link)
    link = self.PlainLink(link)
    if not link then return nil end

    local stats = Call(ITEM_STATS, link)
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
local NO_SCHOOLS = {}

--- The school a line names and by how much, or nil for any other line.
function Items.SchoolLine(text)
    if type(text) ~= "string" then return nil end
    local school, amount = text:match("[Ii]ncreases damage done by (%a+) spells and effects by up to (%d+)")
    local stat = school and SCHOOLS[school:lower()]
    if stat then return stat, tonumber(amount) end
    return nil
end

--- Health every 5 sec a line names ("Equip: Restores 3 health per 5 sec."),
--- or nil. In the client's words when it has the line's format, so other
--- languages match too; English otherwise.
function Items.HealthLine(text)
    if type(text) ~= "string" then return nil end
    local format = type(_G.ITEM_MOD_HEALTH_REGEN) == "string" and _G.ITEM_MOD_HEALTH_REGEN
        or "Restores %s health per 5 sec."
    local pattern = format:gsub("%.$", ""):gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
        :gsub("%%%%s", "(%%d+)"):gsub("%%%%d", "(%%d+)")
    local ok, amount = pcall(string.match, text, pattern)
    amount = ok and tonumber(amount)
    if amount then return "hp5", amount end
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
--- tooltip cannot be read. An empty table when it has none. Health every 5
--- sec rides along as `hp5`, for clients whose stats leave it out.
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
        local text = LineText(line)
        local stat, amount = Items.SchoolLine(text)
        if not stat then stat, amount = Items.HealthLine(text) end
        if stat then found[stat] = (found[stat] or 0) + amount end
    end
    -- Most gear has none, and the finder reads thousands of links, so they
    -- all share one empty table rather than keeping one each. Read only.
    if next(found) == nil then found = NO_SCHOOLS end
    -- A tooltip for an item the client has not loaded yet is one line
    -- ("Retrieving item information"); that is not "none", so not kept.
    if lines > 1 then schoolCache[link] = found end
    return found
end

-- The classes an item's tooltip names on its "Classes:" line, by item ID:
-- a set of lower case names, or false when it names none. Only kept once
-- the whole tooltip was read.
local classLines = {}

--- The class names on an item's "Classes: Hunter" line, as a set of lower
--- case names; false when the tooltip has no such line; nil while the
--- client has not loaded the item. For gear none of the data knows.
function Items:ClassesOnTooltip(itemID)
    itemID = tonumber(itemID)
    if not itemID then return nil end
    local known = classLines[itemID]
    if known ~= nil then return known end

    local format = type(_G.ITEM_CLASSES_ALLOWED) == "string" and _G.ITEM_CLASSES_ALLOWED or "Classes: %s"
    local pattern = "^" .. format:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)") .. "$"
    local data = Call({ "C_TooltipInfo.GetItemByID" }, itemID)
    if type(data) ~= "table" or type(data.lines) ~= "table" then return nil end

    local found, lines = false, 0
    for _, line in ipairs(data.lines) do
        lines = lines + 1
        local list = LineText(line)
        list = list and list:match(pattern)
        if list then
            found = {}
            -- Chinese clients part the names with a wide comma or 、.
            list = list:gsub("\239\188\140", ","):gsub("\227\128\129", ",")
            for name in list:gmatch("[^,]+") do
                name = name:match("^%s*(.-)%s*$")
                if name ~= "" then found[name:lower()] = true end
            end
        end
    end
    if lines > 1 then classLines[itemID] = found end
    return found
end

--- True once SchoolDamage has read `link`'s whole tooltip and kept it.
function Items:SchoolDamageKnown(link)
    link = self.PlainLink(link)
    return link ~= nil and schoolCache[link] ~= nil
end

-- The tooltip line type retail gives "Sell Price:"; 11 where the client
-- has no enum to say.
local function SellPriceLineType()
    local ok, kind = pcall(function() return _G.Enum.TooltipDataLineType.SellPrice end)
    return ok and tonumber(kind) or 11
end

--- What a vendor pays for one of an item, in copper, or nil when it cannot
--- be told. The tooltip's Sell Price wins: Forever changed some prices and
--- only the tooltip has the new one (Tradeskills found it first). Then the
--- item info's.
function Items:SellPrice(link)
    link = self.PlainLink(link)
    if not link then return nil end
    local data = Call({ "C_TooltipInfo.GetHyperlink" }, link)
    if type(data) ~= "table" then
        local itemID = tonumber(link:match("item:(%d+)"))
        if itemID then data = Call({ "C_TooltipInfo.GetItemByID" }, itemID) end
    end
    local sellType = SellPriceLineType()
    local ok, price = pcall(function()
        for _, line in ipairs(type(data) == "table" and type(data.lines) == "table" and data.lines or {}) do
            if type(line) == "table" and line.type == sellType and type(line.price) == "number" then
                return line.price + 0
            end
        end
        return nil
    end)
    if ok and price then return price end
    local name, _, _, _, _, _, _, _, _, _, sellPrice = Call(ITEM_INFO, link)
    ok, price = pcall(function()
        if name and type(sellPrice) == "number" then return sellPrice + 0 end
        return nil
    end)
    return ok and price or nil
end

--------------------------------------------------------------------------------
-- A fishing pole in the hands
--
-- Fishing means swapping a pole into the main hand and back, again and again.
-- A pole is no weapon to measure gear by: with it in hand every weapon looked
-- like an upgrade, so each swap threw every verdict away and looked at all
-- the gear again, both ways, and the game froze for seconds (a player's
-- report, 2026-11-18). So while a pole is worn, the weapons worn before it
-- stand in for it: Equipped answers with them, and the worn and bag
-- signatures read as they did before the swap, so nothing is looked at
-- again. Kept per character (`weaponsUnderPole`, never rename it) so a
-- /reload with the pole in hand still knows them.
--------------------------------------------------------------------------------

local CLASS_WEAPON, FISHING_POLE = 2, 20
local MAIN_HAND, OFF_HAND = 16, 17
Items.MAIN_HAND, Items.OFF_HAND = MAIN_HAND, OFF_HAND

-- Whether each item is a fishing pole, by item string; a kind never changes.
local poles = {}

--- Is `link` a fishing pole? False while the client cannot say.
function Items:IsFishingPole(link)
    local key = Items.LinkKey(self.PlainLink(link))
    if not key then return false end
    local known = poles[key]
    if known ~= nil then return known end
    local _, _, _, _, _, classID, subclassID = Call(INSTANT, link)
    if classID == nil then return false end
    local yes = tonumber(classID) == CLASS_WEAPON and tonumber(subclassID) == FISHING_POLE
    poles[key] = yes
    return yes
end

--- What is really worn in an inventory slot right now, pole or not.
function Items:WornNow(slot)
    return self.PlainLink(Call(WORN_LINK, "player", slot))
end

--- The weapons worn before the pole, as { main = link or false, off = link
--- or false }, or nil when none were seen yet.
function Items:WeaponsUnderPole()
    local db = ns.charDB
    local under = type(db) == "table" and db.weaponsUnderPole
    if type(under) == "table" and type(under.main) == "string" then return under end
    return nil
end

--- Remember the weapons in hand, for the next time a pole goes on.
local function Remember(main, off)
    local db = ns.charDB
    if type(db) ~= "table" then return end
    off = off or false
    local under = db.weaponsUnderPole
    if type(under) == "table" and under.main == main and under.off == off then return end
    db.weaponsUnderPole = { main = main, off = off }
end

--- Is a fishing pole in the main hand, with the weapons from before it
--- known? Then they stand in for it.
function Items:PoleInHand()
    local main = self:WornNow(MAIN_HAND)
    return main ~= nil and self:IsFishingPole(main) and self:WeaponsUnderPole() ~= nil, main
end

--- The link of what is worn in an inventory slot, or nil when it is empty.
--- While a fishing pole is in hand, the weapons worn before it.
function Items:Equipped(slot)
    -- While Logic/OffSpec.lua judges for the Off Spec: the best piece owned
    -- for it in this slot (false for none).
    local as = Items.wornAs
    if as then
        local stand = as[slot]
        if stand ~= nil then return stand or nil end
    end
    local link = self:WornNow(slot)
    if slot ~= MAIN_HAND and slot ~= OFF_HAND then return link end
    local main = slot == MAIN_HAND and link or self:WornNow(MAIN_HAND)
    if not main then return link end
    if self:IsFishingPole(main) then
        local under = self:WeaponsUnderPole()
        if not under then return link end
        local stand = slot == MAIN_HAND and under.main or under.off
        return type(stand) == "string" and stand or nil
    end
    -- A real weapon in hand: remember it (and the off hand) for the pole.
    Remember(main, slot == OFF_HAND and link or self:WornNow(OFF_HAND))
    return link
end

--- The link of the item in a bag slot, or nil.
function Items:InBag(bag, slot)
    if type(bag) ~= "number" or type(slot) ~= "number" then return nil end
    return self.PlainLink(Call(BAG_LINK, bag, slot))
end

--- The quality of the item in a bag slot (0 grey, 1 white, 2 green and up),
--- or nil when the client cannot say.
function Items:SlotQuality(bag, slot, link)
    local info = Call(SLOT_INFO, bag, slot)
    local ok, quality = pcall(function()
        if type(info) == "table" and type(info.quality) == "number" then return info.quality + 0 end
    end)
    if ok and quality then return quality end
    link = self.PlainLink(link)
    if not link then return nil end
    local name, _, itemQuality = Call(ITEM_INFO, link)
    ok, quality = pcall(function()
        if name and type(itemQuality) == "number" then return itemQuality + 0 end
    end)
    return ok and quality or nil
end

--- Is the item in a bag slot soulbound? False when the client cannot say.
function Items:SlotBound(bag, slot)
    local info = Call(SLOT_INFO, bag, slot)
    local ok, bound = pcall(function()
        if type(info) == "table" and info.isBound ~= nil then return info.isBound == true end
    end)
    if ok and bound ~= nil then return bound end
    local make = Resolve("ItemLocation.CreateFromBagAndSlot")
    if type(make) ~= "function" then return false end
    local made, location = pcall(make, _G.ItemLocation, bag, slot)
    if not made or not location then return false end
    local answer = Call({ "C_Item.IsBound" }, location)
    local same, yes = pcall(function() return answer == true end)
    return same and yes or false
end

--- Does the item bind when picked up (or as a quest item), so it can never
--- be traded or mailed? False when the client cannot say.
function Items:BindsOnPickup(link)
    link = self.PlainLink(link)
    if not link then return false end
    local info = { Call(ITEM_INFO, link) }
    local ok, yes = pcall(function()
        local bindType = tonumber(info[14])
        return bindType == 1 or bindType == 4
    end)
    return ok and yes or false
end

--- How many slots a bag has (0 when there is no bag there).
function Items:BagSize(bag)
    local size = Call(BAG_SLOTS, bag)
    return tonumber(size) or 0
end

--- The player's level, or nil.
local UNIT_LEVEL = { "UnitLevel" }

function Items:PlayerLevel()
    return tonumber((Call(UNIT_LEVEL, "player")))
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
    local _, _, _, equipLoc, _, classID = Call(INSTANT, link)
    return equipLoc == "INVTYPE_AMMO" or tonumber(classID) == 6
end

--- How many are in a bag slot (1 when the client cannot say).
function Items:SlotCount(bag, slot)
    local info = Call(SLOT_INFO, bag, slot)
    if type(info) == "table" then return tonumber(info.stackCount) or 1 end
    local _, count = Call(OLD_SLOT_INFO, bag, slot)
    return tonumber(count) or 1
end

--- A link without its name: the item string alone. The client lets an item
--- go from its memory now and then, and its link then reads with no name
--- ("[]"); that is no change to what is worn or carried.
function Items.LinkKey(link)
    if type(link) ~= "string" then return nil end
    return link:match("item:[^|%[]+") or link
end

--- Everything in the bags with how many, ammo without its count, as one
--- string: the same string means nothing changed but the ammo spent.
--- While a fishing pole is in hand, it reads as still in the bags where its
--- weapon now lies, and the off hand taken off for it as still worn: the
--- swap is no change.
function Items:BagSignature()
    local parts = {}
    local inHand, pole = self:PoleInHand()
    local under = inHand and self:WeaponsUnderPole()
    local main = under and Items.LinkKey(under.main)
    local off = under and type(under.off) == "string" and Items.LinkKey(under.off) or nil
    for bag = 0, 4 do
        for slot = 1, self:BagSize(bag) do
            local link = self:InBag(bag, slot)
            if link then
                local key = Items.LinkKey(link)
                local count = self.IsAmmo(link) and "" or ("x" .. self:SlotCount(bag, slot))
                if main and key == main then
                    key, count, main = Items.LinkKey(pole), "x1", nil
                elseif off and key == off then
                    key, off = nil, nil
                end
                if key then parts[#parts + 1] = bag .. ":" .. slot .. "=" .. key .. count end
            end
        end
    end
    return table.concat(parts, ";")
end

--- The skills the character has, without their points, as one string:
--- the weapon skills it knows (WeaponSkills:ReadKnown) and its professions
--- by name. nil when the client names none, so nothing is held back.
function Items:SkillSignature()
    local parts = {}
    local weapons = ns.WeaponSkills
    local known = weapons and weapons.ReadKnown and weapons:ReadKnown()
    if type(known) == "table" then
        for subclassID in pairs(known) do parts[#parts + 1] = "w" .. tostring(subclassID) end
    end

    local lines = Call({ "C_TradeSkillUI.GetAllProfessionTradeSkillLines" })
    if type(lines) == "table" then
        for _, skillLineID in ipairs(lines) do
            local info = Call({ "C_TradeSkillUI.GetProfessionInfoBySkillLineID" }, skillLineID)
            local ok, name = pcall(function()
                if type(info) == "table" and type(info.professionName) == "string" then
                    return info.professionName .. ""
                end
            end)
            if ok and name and name ~= "" then parts[#parts + 1] = "p" .. name end
        end
    end
    local count = tonumber((Call({ "GetNumSkillLines" }))) or 0
    for index = 1, count do
        local name = Call({ "GetSkillLineInfo" }, index)
        local ok, copy = pcall(function()
            if type(name) == "string" then return name .. "" end
        end)
        if ok and copy then parts[#parts + 1] = "s" .. copy end
    end

    if #parts == 0 then return nil end
    table.sort(parts)
    return table.concat(parts, ";")
end

--- Everything worn, leaving out the ammo slot, as one string.
function Items:WornSignature()
    local parts = {}
    for slot = 1, 19 do parts[slot] = Items.LinkKey(self:Equipped(slot)) or "-" end
    return table.concat(parts, ";")
end

--- The talents bought, as one string (Weights:TalentSignature), or nil.
function Items:TalentSignature()
    local weights = ns.Weights
    if not (weights and type(weights.TalentSignature) == "function") then return nil end
    return weights:TalentSignature()
end

Items.Call = Call

--------------------------------------------------------------------------------
-- Item names in their quality colour
--
-- The owner (2026-10-18): an item's name always shows its rarity colour,
-- grey, white, green, blue, purple or orange, wherever it is drawn. Saved
-- data and anything compared or put in a macro stays plain; only the text
-- put on screen is coloured, at the moment it is drawn. A quality is kept
-- per item once the client has said it; until then the item is asked for
-- once (GET_ITEM_INFO_RECEIVED says when it arrives, and the windows that
-- show names already draw again then) and the name keeps the colour of
-- the line it sits in.
--------------------------------------------------------------------------------

local qualityOf = {}       -- [itemID] = quality, once known
local qualityByName = {}   -- [name] = quality, for a name with no ID
local hexOf = {}           -- [quality] = "ffrrggbb"
local asked = {}           -- [itemID] = true once asked for this session

local function ItemIDOf(item)
    if type(item) == "number" then return item end
    if type(item) ~= "string" then return nil end
    local ok, id = pcall(function() return tonumber(item:match("item:(%d+)")) end)
    return ok and id or nil
end
Items.ItemIDOf = ItemIDOf

local function Hex(r, g, b)
    local ok, hex = pcall(function()
        return ("ff%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
            math.floor(b * 255 + 0.5))
    end)
    return ok and hex or nil
end

--- The colour code of a quality ("ff1eff00" for green), or nil.
function Items.QualityHex(quality)
    if type(quality) ~= "number" then return nil end
    if hexOf[quality] then return hexOf[quality] end
    local hex
    local colors = rawget(_G, "ITEM_QUALITY_COLORS")
    local color = type(colors) == "table" and colors[quality] or nil
    if type(color) == "table" and type(color.r) == "number" then
        hex = Hex(color.r, color.g, color.b)
    end
    if not hex then
        local r, g, b, h = Call({ "C_Item.GetItemQualityColor", "GetItemQualityColor" }, quality)
        if type(h) == "string" and h:match("^%x%x%x%x%x%x%x%x$") then
            hex = h:lower()
        elseif type(r) == "number" and type(g) == "number" and type(b) == "number" then
            hex = Hex(r, g, b)
        end
    end
    if hex then hexOf[quality] = hex end
    return hex
end

--- Ask the server about an item once a session, so its quality comes in.
local function Ask(id)
    if asked[id] then return end
    asked[id] = true
    local C = rawget(_G, "C_Item")
    if type(C) == "table" and type(C.RequestLoadItemDataByID) == "function" then
        pcall(C.RequestLoadItemDataByID, id)
    end
end

--- An item's quality (0 grey to 5 orange and up), or nil while not known.
--- `item` is an ID, a link or item string, or (with no ID to go on) a name,
--- which the client answers only once it has that item.
function Items:Quality(item)
    local id = ItemIDOf(item)
    if id and qualityOf[id] then return qualityOf[id] end
    local name = not id and type(item) == "string" and item ~= "" and item or nil
    if name and qualityByName[name] then return qualityByName[name] end
    local key = id or name
    if not key then return nil end
    -- A link carries its own colour; the client's answer is the same.
    local _, _, quality = Call(ITEM_INFO, type(item) == "string" and item or key)
    local ok, number = pcall(function()
        local value = tonumber(quality)
        if value and value >= 0 and value <= 9 then return value end
    end)
    if ok and number then
        if id then qualityOf[id] = number else qualityByName[name] = number end
        return number
    end
    if id then Ask(id) end
    return nil
end

--- `name` in the quality colour of `item` (an ID, link or the name itself),
--- or `name` as it is while the quality is not known. Text that already
--- carries a colour is left alone.
function Items.ColorName(item, name)
    if type(name) ~= "string" or name == "" then return name end
    if name:find("|c", 1, true) then return name end
    local hex = Items.QualityHex(Items:Quality(item or name))
    if not hex then return name end
    return "|c" .. hex .. name .. "|r"
end

--- A link to show: a real link (coloured by the game) as it is; an item
--- string ("item:123", kept while the client had not sent the item) as the
--- item's link once the client has it, else as it was.
function Items.ShowLink(link)
    if type(link) ~= "string" then return link end
    if link:find("|H", 1, true) then return link end
    local id = ItemIDOf(link)
    if not id then return Items.ColorName(nil, link) end
    local _, real = Call(ITEM_INFO, id)
    real = Items.PlainLink(real)
    if real and real:find("|H", 1, true) then return real end
    Ask(id)
    return link
end

--- Is a name drawn plain while its item's quality is on its way?
function Items:Waiting(itemID)
    local ok, id = pcall(function() return tonumber(itemID) end)
    return ok and id ~= nil and asked[id] == true and qualityOf[id] == nil
end

-- Windows that draw names again when an item they showed plain arrives.
-- One redraw for a burst of answers, never for items nobody here asked for.
local watchers = {}
local redrawSoon = false

--- Call `fn` (in a pcall) a moment after items whose names were drawn
--- plain arrive, once for a burst.
function Items:WatchNames(fn)
    if type(fn) == "function" then watchers[#watchers + 1] = fn end
end

local function Redraw()
    redrawSoon = false
    for _, fn in ipairs(watchers) do pcall(fn) end
end

function Items:OnItemInfo(_, itemID)
    if not self:Waiting(itemID) or redrawSoon then return end
    redrawSoon = true
    local timer = rawget(_G, "C_Timer")
    if type(timer) == "table" and type(timer.After) == "function" then
        timer.After(0.2, Redraw)
    else
        Redraw()
    end
end

function Items:OnEnable()
    ns.RegisterEvent(self, "GET_ITEM_INFO_RECEIVED", self.OnItemInfo)
end
