-- Blackthornes Equipment -- Logic/Finder.lua
-- Where to go for an upgrade: gear a vendor sells, a quest gives or a dungeon
-- boss drops, that beats what the character wears today.
--
-- Data/Sources.lua says where each item comes from (Classic data). The game
-- says what the item is: its stats arrive from the server the first time an
-- item is asked about, and GET_ITEM_INFO_RECEIVED says when. So a scan judges
-- what the client already knows, asks for a batch of what it does not, and
-- the window scans again as answers come in.
--
-- Only what the character can get now is offered: their own faction's
-- vendors and quest givers, quests open at their level that they have not
-- done, and dungeons whose recommended range starts at or below their level.
-- Every verdict comes from Compare:Judge, so the finder, the tooltip and the
-- bag arrow always agree.

local _, ns = ...

local Finder = ns.NewModule("Finder")

local Items = ns.Items
local Compare = ns.Compare
local Weights = ns.Weights

-- Gear more than this many item levels under the character's level is not
-- looked at: it would almost never be an upgrade, and asking the server
-- about all of it would be a flood.
local LEVELS_BELOW = 12

-- How many items to ask the server about per scan. The rest wait for the
-- next scan, which the answers trigger.
local ASK_PER_SCAN = 40

-- How many upgrades to keep per slot.
local PER_SLOT = 3

-- Classic's class and race bits, as quests and items carry them.
local CLASS_BITS = {
    WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16,
    SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024,
}
local RACE_BITS = {
    Human = 1, Orc = 2, Dwarf = 4, NightElf = 8, Scourge = 16, Undead = 16,
    Tauren = 32, Gnome = 64, Troll = 128,
}
local ALLIANCE_RACES = 1 + 4 + 8 + 64

--- a AND b, bit by bit. The game has bit.band; written out for a Lua without
--- it (the test runner).
local function Band(a, b)
    if bit and bit.band then return bit.band(a, b) end
    local result, place = 0, 1
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then result = result + place end
        a, b, place = math.floor(a / 2), math.floor(b / 2), place * 2
    end
    return result
end

Finder.KINDS = { "vendor", "quest", "dungeon" }

--------------------------------------------------------------------------------
-- The character
--------------------------------------------------------------------------------

local function Read(fn, ...)
    if type(fn) ~= "function" then return nil end
    local result = { pcall(fn, ...) }
    if not result[1] then return nil end
    return unpack(result, 2)
end

--- Who is looking: level, faction ("A" or "H"), class and race bits.
-- @return a table, or nil when the level or faction cannot be read
function Finder:Player()
    local level = Items:PlayerLevel()

    local faction = Read(_G.UnitFactionGroup, "player")
    local _, raceFile = Read(_G.UnitRace, "player")
    local raceBit = RACE_BITS[raceFile]
    if faction ~= "Alliance" and faction ~= "Horde" and raceBit then
        faction = Band(raceBit, ALLIANCE_RACES) ~= 0 and "Alliance" or "Horde"
    end
    if not level or (faction ~= "Alliance" and faction ~= "Horde") then return nil end

    local class = Weights:PlayerClass()
    local zone = Read(_G.GetRealZoneText)
    return {
        level = level,
        zone = type(zone) == "string" and zone ~= "" and zone or nil,
        faction = faction == "Alliance" and "A" or "H",
        class = class,
        classBit = CLASS_BITS[class] or 0,
        raceBit = raceBit or 0,
    }
end

--- Has this character turned in a quest? False when the client cannot say.
function Finder:QuestDone(questID)
    local log = _G.C_QuestLog
    local done = Read(log and log.IsQuestFlaggedCompleted, questID)
    if done == nil then done = Read(_G.IsQuestFlaggedCompleted, questID) end
    return done == true
end

--------------------------------------------------------------------------------
-- Sources
--------------------------------------------------------------------------------

local function Allows(mask, flag)
    return mask == 0 or flag == 0 or Band(mask, flag) ~= 0
end

local function ZoneName(zoneID)
    return ns.Sources.ZONES[zoneID]
end

--- Every place this character can get an item from now, as a list of
--- tables { kind, ... }, vendors first, then quests, then dungeons.
function Finder:SourcesFor(itemID, player)
    local S = ns.Sources
    local item = S.ITEMS[itemID]
    if not item then return {} end

    local found = {}
    if item[1] > player.level or not Allows(item[3], player.classBit)
        or not Allows(item[4], player.raceBit) then
        return found
    end

    local vendors = item.v or {}
    for i = 1, #vendors, 2 do
        local npc = S.NPCS[vendors[i]]
        if npc and npc[5]:find(player.faction, 1, true) then
            found[#found + 1] = {
                kind = "vendor", name = npc[1], zone = ZoneName(npc[2]), x = npc[3], y = npc[4],
                price = item[5], limited = vendors[i + 1] > 0,
            }
        end
    end

    for _, questID in ipairs(item.q or {}) do
        local quest = S.QUESTS[questID]
        if quest and quest[2] <= player.level and Allows(quest[4], player.raceBit)
            and Allows(quest[5], player.classBit) and not self:QuestDone(questID) then
            found[#found + 1] = {
                kind = "quest", questID = questID, title = quest[1], questLevel = quest[3],
                name = quest[6], zone = ZoneName(quest[7]),
                x = quest[8] ~= 0 and quest[8] or nil, y = quest[9] ~= 0 and quest[9] or nil,
                after = quest[10] ~= "" and quest[10] or nil, group = quest[11] or false,
            }
        end
    end

    local drops = item.d or {}
    for i = 1, #drops, 2 do
        local boss = S.BOSSES[drops[i]]
        local dungeon = boss and S.DUNGEONS[boss[2]]
        if dungeon and dungeon[2] <= player.level
            and (dungeon[5] == "" or dungeon[5] == player.faction) then
            found[#found + 1] = {
                kind = "dungeon", name = boss[1], dungeon = dungeon[1],
                minLevel = dungeon[2], maxLevel = dungeon[3], zone = dungeon[4],
                chance = drops[i + 1],
            }
        end
    end

    -- Somewhere in the zone the character is standing in comes first: a
    -- vendor down the road beats the same item across the world.
    if player.zone then
        local here, there = {}, {}
        for _, source in ipairs(found) do
            local list = source.zone == player.zone and here or there
            list[#list + 1] = source
        end
        for _, source in ipairs(there) do here[#here + 1] = source end
        found = here
    end

    return found
end

--- The items worth judging for this character: in level range, with at least
--- one source open to them. A list of { itemID, sources }.
function Finder:Candidates(player, only)
    local list = {}
    local floor = player.level - LEVELS_BELOW
    for itemID, item in pairs(ns.Sources.ITEMS) do
        if item[2] >= floor and item[1] <= player.level then
            local sources = self:SourcesFor(itemID, player)
            if only then
                local kept = {}
                for _, source in ipairs(sources) do
                    if source.kind == only then kept[#kept + 1] = source end
                end
                sources = kept
            end
            if #sources > 0 then
                list[#list + 1] = { itemID = itemID, sources = sources }
            end
        end
    end
    table.sort(list, function(a, b) return a.itemID < b.itemID end)
    return list
end

--------------------------------------------------------------------------------
-- Asking the client
--------------------------------------------------------------------------------

--- Does the client have this item's details yet? True when it cannot say,
--- so a client without the call is simply asked through Judge.
function Finder:IsCached(itemID)
    local C = _G.C_Item
    local cached = Read(C and C.IsItemDataCachedByID, itemID)
    if cached == nil then return true end
    return cached
end

--- Ask the server about an item; GET_ITEM_INFO_RECEIVED answers.
function Finder:Request(itemID)
    local C = _G.C_Item
    if Read(C and C.RequestLoadItemDataByID, itemID) == nil then
        Read(C and C.GetItemInfo or _G.GetItemInfo, itemID)
    end
end

--- Can this class wear the item at all? Read from the client's own item
--- table, which needs no server answer, so nothing is asked about gear the
--- class could never use. Nil when the client cannot say without asking.
local function Wearable(class, itemID)
    local info = Items:Info(("item:%d"):format(itemID))
    if not info then return nil end
    if not Compare.SLOTS[info.equipLoc] then return false end
    local usable = Weights:CanUse(class, info.classID, info.subclassID)
    return usable and true or false
end

--- The item's own link, quality colour and all, where the client has it.
local function LinkFor(itemID)
    local _, link = Items.Call({ "C_Item.GetItemInfo", "GetItemInfo" }, itemID)
    return Items.PlainLink(link) or ("item:%d"):format(itemID)
end

--------------------------------------------------------------------------------
-- The scan
--------------------------------------------------------------------------------

--- Look for upgrades, from every kind of source or only `only` ("vendor",
--- "quest" or "dungeon").
-- @return nil and why, or a table:
--   slots     { [inventory slot] = { pick, ... } } best first, at most
--             PER_SLOT each; a pick is { itemID, link, result, gain, sources }
--   count     how many picks in all
--   checked   how many items were judged
--   waiting   how many the server has still to answer about
--   player    the player table
function Finder:Scan(only)
    local player = self:Player()
    if not player then return nil, "nolevel" end

    local weights = Weights:ForPlayer()
    if not weights then return nil, "noweights" end

    local slots, checked, waiting, asked = {}, 0, 0, 0
    for _, candidate in ipairs(self:Candidates(player, only)) do
        local itemID = candidate.itemID
        local wearable = Wearable(player.class, itemID)
        if wearable ~= false then
            if wearable == nil or not self:IsCached(itemID) then
                waiting = waiting + 1
                if asked < ASK_PER_SCAN then
                    asked = asked + 1
                    self:Request(itemID)
                end
            elseif not Compare:IsWornID(itemID) then
                local link = ("item:%d"):format(itemID)
                local ok, result = pcall(Compare.Judge, Compare, link)
                if ok and result then
                    checked = checked + 1
                    if result.verdict == "upgrade" and not result.level and result.slot then
                        local list = slots[result.slot] or {}
                        slots[result.slot] = list
                        list[#list + 1] = {
                            itemID = itemID, link = LinkFor(itemID), result = result,
                            gain = (result.score or 0) - (result.against or 0),
                            sources = candidate.sources,
                        }
                    end
                elseif ok then
                    -- Known to the client but its stats are not in yet.
                    waiting = waiting + 1
                end
            end
        end
    end

    local count = 0
    for slot, list in pairs(slots) do
        table.sort(list, function(a, b)
            if a.gain ~= b.gain then return a.gain > b.gain end
            return a.itemID < b.itemID
        end)
        for i = #list, PER_SLOT + 1, -1 do list[i] = nil end
        count = count + #list
        slots[slot] = list
    end

    return { slots = slots, count = count, checked = checked, waiting = waiting, player = player }
end

--------------------------------------------------------------------------------
-- Words
--------------------------------------------------------------------------------

local MONEY = {
    { 10000, "g", "ffffd700" },
    { 100, "s", "ffc7c7cf" },
    { 1, "c", "ffeda55f" },
}

--- Copper as "1g 20s 5c", each part in its coin's colour.
function Finder.Money(copper)
    copper = math.floor(tonumber(copper) or 0)
    if copper <= 0 then return nil end
    local parts = {}
    for _, coin in ipairs(MONEY) do
        local amount = math.floor(copper / coin[1])
        copper = copper - amount * coin[1]
        if amount > 0 then
            parts[#parts + 1] = ("|c%s%d%s|r"):format(coin[3], amount, coin[2])
        end
    end
    return table.concat(parts, " ")
end

local function Place(source)
    if not source.zone then return nil end
    if source.x and source.y then
        return ("%s (%s, %s)"):format(source.zone, source.x, source.y)
    end
    return source.zone
end

--- One source in words, without its kind: what the window shows after the
--- coloured "Vendor", "Quest" or "Dungeon" tag.
function Finder:Describe(source)
    if source.kind == "vendor" then
        local text = source.name
        local where = Place(source)
        if where then text = text .. ", " .. where end
        local price = self.Money(source.price)
        if price then text = text .. "  " .. price end
        if source.limited then text = text .. "  (limited stock)" end
        return text
    elseif source.kind == "quest" then
        local text = ("%s (level %d)"):format(source.title, source.questLevel or 0)
        if source.group then text = text .. ", group" end
        local where = Place(source)
        if source.x then
            text = text .. ", from " .. source.name
            if where then text = text .. " in " .. where end
        else
            text = text .. ", starts from " .. source.name
        end
        return text
    elseif source.kind == "dungeon" then
        return ("%s in %s (%d-%d), %s%% drop"):format(source.name, source.dungeon,
            source.minLevel, source.maxLevel, tostring(source.chance))
    end
    return ""
end

Finder.LABELS = { vendor = "Vendor", quest = "Quest", dungeon = "Dungeon" }

--------------------------------------------------------------------------------
-- /beq find
--------------------------------------------------------------------------------

ns.RegisterCommand("find", "where to get upgrades: vendors, quests and dungeons", function()
    if ns.FinderUI then ns.FinderUI:Toggle() end
end)
