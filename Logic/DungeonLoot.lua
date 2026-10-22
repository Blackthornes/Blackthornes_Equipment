-- Dungeon Loot (the owner said build it, 2026-10-22, from a mockup): what
-- each dungeon's bosses drop, with the pieces that are upgrades for the
-- character playing marked by how much. UI/DungeonLootWindow.lua draws it.
--
-- The drops are the data's: a Classic boss's from an item's `d` list in
-- Sources.ITEMS, Forever's own from Sources.FOREVER (what was seen drop
-- there, its rate winning). They are laid out by dungeon once, the first
-- time the window opens. Each item is judged by Compare:Judge through the
-- finder's kept verdicts, so a list is cheap to draw again; an item the
-- client has not loaded is asked for, and the window draws again when it
-- comes in.

local _, ns = ...

local DL = ns.NewModule("DungeonLoot")
local L = ns.L

-- The armor chips, by the client's armor subclass.
DL.ARMOR = { cloth = 1, leather = 2, mail = 3 }
-- The stat chips, by the stat the item's stats name.
DL.STATS = {
    strength = "ITEM_MOD_STRENGTH_SHORT", agility = "ITEM_MOD_AGILITY_SHORT",
    stamina = "ITEM_MOD_STAMINA_SHORT", intellect = "ITEM_MOD_INTELLECT_SHORT",
    spirit = "ITEM_MOD_SPIRIT_SHORT",
}
-- Items asked of the server each time a dungeon's list is laid out.
DL.ASK = 30

local function Sources()
    return ns.Sources
end

--- Every dungeon's drops: [key] = { [itemID] = { boss, chance, forever } }.
--- Laid out once.
function DL:Index()
    if self.index then return self.index end
    local S = Sources()
    local index = {}
    if not S then return index end
    local function Add(key, itemID, boss, chance, forever)
        if not (key and itemID and boss) then return end
        local list = index[key] or {}
        index[key] = list
        local kept = list[itemID]
        chance = tonumber(chance) or 0
        if not kept or forever and not kept.forever or (forever == kept.forever and chance > kept.chance) then
            list[itemID] = { boss = boss, chance = chance, forever = forever == true }
        end
    end
    for itemID, item in pairs(S.ITEMS or {}) do
        local drops = type(item) == "table" and item.d
        if type(drops) == "table" then
            for i = 1, #drops, 2 do
                local boss = S.BOSSES and S.BOSSES[drops[i]]
                if type(boss) == "table" then Add(boss[2], itemID, boss[1], drops[i + 1], false) end
            end
        end
    end
    for itemID, seen in pairs(S.FOREVER or {}) do
        for _, drop in ipairs(type(seen) == "table" and seen or {}) do
            if type(drop) == "table" then Add(drop[2], itemID, drop[1], drop[3], true) end
        end
    end
    self.index = index
    return index
end

--- The dungeons with drops for this side: { key, name, low, high, door,
--- raid, forever, count }, Classic's by level, raids after, Forever's last.
function DL:Dungeons(player)
    local S = Sources()
    local DQ = ns.DungeonQuests
    local list = {}
    for key, items in pairs(self:Index()) do
        local row = S and S.DUNGEONS and S.DUNGEONS[key]
        local side = type(row) == "table" and row[5] or ""
        local dungeon = DQ and DQ.Dungeon(key)
        if dungeon and (side == "" or not player or side == player.faction) then
            local count = 0
            for _ in pairs(items) do count = count + 1 end
            dungeon.count = count
            list[#list + 1] = dungeon
        end
    end
    table.sort(list, function(a, b)
        if (a.forever or false) ~= (b.forever or false) then return not a.forever end
        if (a.raid or false) ~= (b.raid or false) then return not a.raid end
        if (a.low or 0) ~= (b.low or 0) then return (a.low or 0) < (b.low or 0) end
        return a.name < b.name
    end)
    return list
end

local function Link(itemID)
    return ("item:%d"):format(itemID)
end

--- Is a piece the armor chip asks for? Cloth, leather and mail chips leave
--- out other body armor; cloaks, jewelry, shields and weapons always stay.
function DL.ArmorMatches(info, armor)
    if not armor or armor == "all" then return true end
    if not info or info.classID ~= 4 or info.equipLoc == "INVTYPE_CLOAK" then return true end
    local sub = info.subclassID
    if sub == nil or sub < 1 or sub > 4 then return true end
    return sub == DL.ARMOR[armor]
end

--- Does a piece give the stat the chip asks for? Nil while its stats have
--- not come in.
function DL.StatMatches(link, stat)
    if not stat or stat == "all" then return true end
    local stats = ns.Items and ns.Items:Stats(link)
    if not stats then return nil end
    return (tonumber(stats[DL.STATS[stat]]) or 0) > 0
end

--- What the slot column says: "Legs, Leather" for body armor, the weapon's
--- kind for a weapon, else the slot.
function DL.SlotText(link, info)
    if not info then return "" end
    local slot = rawget(_G, info.equipLoc)
    slot = type(slot) == "string" and slot or ""
    local okInfo, _, _, _, _, _, _, subType = pcall(function()
        local get = _G.C_Item and _G.C_Item.GetItemInfo or _G.GetItemInfo
        return get(link)
    end)
    subType = okInfo and type(subType) == "string" and subType or nil
    if info.classID == 2 and subType then return subType end
    if info.classID == 4 and info.equipLoc ~= "INVTYPE_CLOAK" and subType
        and (info.subclassID or 0) >= 1 and (info.subclassID or 0) <= 4 and slot ~= "" then
        return L.Format("%s, %s", slot, subType)
    end
    return slot
end

--- One dungeon's rows for the chips picked: { rows = { { itemID, link,
--- boss, chance, slot, upgrade, gain (whole percent or nil), result } },
--- waiting, upgrades }. Rows come best first: upgrades by gain, an empty
--- slot's ahead of any, then the rest by name.
function DL:Rows(key, armor, stat, upgradesOnly)
    local items = self:Index()[key] or {}
    local Finder, Compare = ns.Finder, ns.Compare
    local judged = Finder and Finder:Judged()
    local rows, waiting, upgrades, asked = {}, 0, 0, 0
    for itemID, drop in pairs(items) do
        local link = Link(itemID)
        local info = ns.Items and ns.Items:Info(link)
        local gear = info and Compare and Compare.SLOTS[info.equipLoc]
        if info == nil or (gear and Finder and not Finder:IsCached(itemID)) then
            waiting = waiting + 1
            if Finder and asked < DL.ASK and Finder:Request(itemID) then asked = asked + 1 end
        elseif gear and DL.ArmorMatches(info, armor) then
            local statOK = DL.StatMatches(link, stat)
            if statOK == nil then
                waiting = waiting + 1
            elseif statOK then
                local result
                if Finder and judged then
                    local _, ok, judgedResult = Finder:JudgeOnce(judged, itemID)
                    result = ok and judgedResult or nil
                end
                local upgrade = result ~= nil and Compare.WearableUpgrade(result) == true
                if upgrade then upgrades = upgrades + 1 end
                if upgrade or not upgradesOnly then
                    rows[#rows + 1] = {
                        itemID = itemID, link = link, boss = drop.boss, chance = drop.chance,
                        slot = DL.SlotText(link, info), upgrade = upgrade,
                        gain = upgrade and Finder.Shown(result) or nil, result = result,
                        name = DL.NameOf(itemID),
                    }
                end
            end
        end
    end
    table.sort(rows, DL.Best)
    return { rows = rows, waiting = waiting, upgrades = upgrades }
end

--- The item's name from the client, or "" while it is on its way.
function DL.NameOf(itemID)
    local ok, name = pcall(function()
        local get = _G.C_Item and _G.C_Item.GetItemNameByID
        local value = get and get(itemID)
        if type(value) ~= "string" then value = (_G.GetItemInfo and _G.GetItemInfo(itemID)) end
        return type(value) == "string" and value or nil
    end)
    return ok and name or ""
end

--- Best first: upgrades before the rest, an empty slot's first, then the
--- biggest gain; then by name.
function DL.Best(a, b)
    if a.upgrade ~= b.upgrade then return a.upgrade end
    if a.upgrade then
        if (a.gain == nil) ~= (b.gain == nil) then return a.gain == nil end
        if a.gain ~= b.gain then return a.gain > b.gain end
    end
    if a.name ~= b.name then return a.name < b.name end
    return a.itemID < b.itemID
end

--- A sorted copy by a column (item, slot, boss, gain), flipped on a second
--- click; nil key keeps best first.
function DL.SortRows(rows, key, flip)
    if not key then return rows end
    local function Value(row)
        if key == "item" then return row.name ~= "" and row.name or nil end
        if key == "slot" then return row.slot ~= "" and row.slot or nil end
        if key == "boss" then return row.boss end
        if key == "gain" then return row.gain or (row.upgrade and math.huge) or nil end
    end
    local keyed = {}
    for index, row in ipairs(rows) do keyed[index] = { row = row, index = index, value = Value(row) } end
    table.sort(keyed, function(a, b)
        if a.value ~= b.value then
            if a.value == nil then return false end
            if b.value == nil then return true end
            if key == "gain" then return a.value > b.value end
            return a.value < b.value
        end
        return a.index < b.index
    end)
    local sorted = {}
    for index, entry in ipairs(keyed) do sorted[index] = entry.row end
    if flip then
        local flipped = {}
        for index = #sorted, 1, -1 do flipped[#flipped + 1] = sorted[index] end
        sorted = flipped
    end
    return sorted
end

--- Where the dungeon's door is, for the arrow and the map pin: the spot
--- learned walking in (DungeonDoors), else only the zone. Nil when the data
--- names no door.
function DL.Door(dungeon)
    if not (dungeon and dungeon.door) then return nil end
    local place = { zone = dungeon.door, name = dungeon.name }
    if ns.DungeonDoors then ns.DungeonDoors:Fill(place, dungeon.name) end
    return place
end

--- The quest arrow to the door.
function DL:Follow(dungeon)
    local place = DL.Door(dungeon)
    local arrow = ns.QuestArrow
    if not (place and arrow and arrow.AimAtQuest) then return false end
    local ok, aimed = pcall(arrow.AimAtQuest, arrow, nil, dungeon.name, place)
    return ok and aimed == true
end

--- The game's map pin on the door.
function DL:ShowTheWay(dungeon)
    local place = DL.Door(dungeon)
    if not (place and ns.Waypoints) then return false end
    local ok, shown = pcall(ns.Waypoints.Show, ns.Waypoints, place, dungeon.name)
    return ok and shown == true
end

ns.RegisterCommand("loot", L["what each dungeon drops, with your upgrades"], function()
    if ns.DungeonLootUI then ns.DungeonLootUI:Toggle() end
end)
