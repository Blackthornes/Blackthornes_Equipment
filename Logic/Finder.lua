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
local L = ns.L

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

-- How many times one item is asked about before giving up on it for the
-- session. An item Forever's server does not have never arrives, and asking
-- again every scan kept the client's item queue busy, so the game's own
-- windows (the quest reward choices) waited behind it.
local ASK_TRIES = 3

-- How long a batch asked for may go without a single answer before the
-- next step is taken anyway (the server drops some of what it is asked).
-- An item is not asked about again sooner than this, so several scans in
-- a row (a tick box, a filter) spend one try on it between them, not one
-- each.
local ANSWER_WAIT = 5

-- How many upgrades to keep per slot.
local PER_SLOT = 3
Finder.PER_SLOT = PER_SLOT

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
local HORDE_RACES = 2 + 16 + 32 + 128
Finder.ALLIANCE_RACES, Finder.HORDE_RACES = ALLIANCE_RACES, HORDE_RACES

-- Forever's own races, by the game's race ID. Both Skyborne races share the
-- race name "Skyborne", so only the ID tells the High Order (Alliance) from
-- the Windshapers (Horde).
local RACE_SIDES = { [95] = "Alliance", [96] = "Horde" }

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

Finder.Band = Band

Finder.KINDS = { "vendor", "quest", "dungeon", "craft" }

--- Lay the Forever client's own numbers (Data/ForeverItems.lua) over the
--- Classic rows: required level, item level, classes and races, and the
--- vendor price of gear a vendor sells. Done once as the addon loads, so the
--- finder's level and class checks read Forever's numbers with no lookup
--- per item. Reputations and sources stay as they are.
function Finder.LayForeverItems(client, sources, crafts)
    for itemID, row in pairs(client or {}) do
        local item = sources and sources[itemID]
        if item then
            item[1], item[2], item[3], item[4] = row[1], row[2], row[3], row[4]
            if item.v then item[5] = row[5] end
        end
        local craft = crafts and crafts[itemID]
        if craft then
            craft[4], craft[5], craft[6], craft[7] = row[1], row[2], row[3], row[4]
        end
    end
end

Finder.LayForeverItems(ns.ForeverItems, ns.Sources and ns.Sources.ITEMS, ns.Crafts and ns.Crafts.ITEMS)

--- Leave out the Classic quests the Forever client does not have
--- (Data/ForeverGoneQuests.lua): their rows go, and so do their IDs in each
--- item's quest lists and any quest's `p`. Done once as the addon loads,
--- before QuestLearn lays what was learned in game, so a quest met in game
--- still shows.
function Finder.DropGoneQuests(gone, sources)
    if type(gone) ~= "table" or type(sources) ~= "table" then return 0 end
    local quests, items = sources.QUESTS, sources.ITEMS
    local dropped = 0
    if type(quests) == "table" then
        for questID in pairs(gone) do
            local quest = quests[questID]
            if quest and not quest.learned then
                quests[questID] = nil
                dropped = dropped + 1
            end
        end
        for _, quest in pairs(quests) do
            if quest.p and gone[quest.p] and not quests[quest.p] then quest.p = nil end
        end
    end
    local function Strip(list)
        if type(list) ~= "table" then return end
        for i = #list, 1, -1 do
            if gone[list[i]] and not (quests and quests[list[i]]) then table.remove(list, i) end
        end
    end
    for _, item in pairs(type(items) == "table" and items or {}) do
        Strip(item.q)
        Strip(item.g)
    end
    return dropped
end

Finder.DropGoneQuests(ns.ForeverGoneQuests, ns.Sources)

--------------------------------------------------------------------------------
-- The character
--------------------------------------------------------------------------------

--- A plain copy of a client string, or nil (a secret value raises when used).
local function Plain(value)
    local ok, copy = pcall(function()
        if type(value) == "string" and value ~= "" then return value .. "" end
    end)
    if ok then return copy end
    return nil
end

local function Read(fn, ...)
    if type(fn) ~= "function" then return nil end
    local result = { pcall(fn, ...) }
    if not result[1] then return nil end
    return unpack(result, 2)
end

--- The character's side, "Alliance" or "Horde", and its Classic race bit.
--- A race Classic never had (Forever's Skyborne) gets every race of its
--- side, so quests and gear are still kept to that side; without it, every
--- race-limited quest of both sides was offered.
-- @return the side and the race bit, or nil when the side cannot be read
function Finder.Side()
    local faction = Plain(Read(_G.UnitFactionGroup, "player"))
    local _, raceFile, raceID = Read(_G.UnitRace, "player")
    local raceBit = RACE_BITS[Plain(raceFile) or ""]
    if faction ~= "Alliance" and faction ~= "Horde" then
        local ok, id = pcall(function() return tonumber(raceID) end)
        faction = ok and id and RACE_SIDES[id] or nil
        if not faction and raceBit then
            faction = Band(raceBit, ALLIANCE_RACES) ~= 0 and "Alliance" or "Horde"
        end
    end
    if faction ~= "Alliance" and faction ~= "Horde" then return nil end
    return faction, raceBit or (faction == "Alliance" and ALLIANCE_RACES or HORDE_RACES)
end

--- Who is looking: level, faction ("A" or "H"), class and race bits.
-- @return a table, or nil when the level or faction cannot be read
function Finder:Player()
    local level = Items:PlayerLevel()

    local faction, raceBit = Finder.Side()
    if not level or not faction then return nil end

    local class = Weights:PlayerClass()
    local zone = Plain(Read(_G.GetRealZoneText))
    -- By the data's name for it, on a client in another language too.
    if ns.Waypoints then zone = ns.Waypoints:DataZone(zone) end
    return {
        level = level,
        zone = zone,
        faction = faction == "Alliance" and "A" or "H",
        class = class,
        classBit = CLASS_BITS[class] or 0,
        raceBit = raceBit,
    }
end

--- Has this character turned in a quest? False when the client cannot say.
function Finder:QuestDone(questID)
    local log = _G.C_QuestLog
    local done = Read(log and log.IsQuestFlaggedCompleted, questID)
    if done == nil then done = Read(_G.IsQuestFlaggedCompleted, questID) end
    if done == true then return true end
    -- Quests seen handed in, for a client that cannot say.
    local seen = ns.charDB and ns.charDB.questsTurnedIn
    return type(seen) == "table" and seen[questID] == true
end

--- Remember a quest handed in (QUEST_TURNED_IN), kept per character in
--- `questsTurnedIn`, in case the client has no call to ask.
function Finder:OnQuestTurnedIn(_, questID)
    local ok, id = pcall(function() return tonumber(questID) end)
    if ok and id and ns.charDB then
        if type(ns.charDB.questsTurnedIn) ~= "table" then ns.charDB.questsTurnedIn = {} end
        ns.charDB.questsTurnedIn[id] = true
    end
    -- A hand-in can open quests a giver would not offer before.
    if ns.charDB then ns.charDB.questsNotOffered = nil end
    self:MarkStale()
end

--------------------------------------------------------------------------------
-- Quests a giver did not offer
--------------------------------------------------------------------------------

-- The data is Classic's, and Forever changed some givers: Deathguard
-- Burgess offered a level 6 character nothing like Proof of Demise
-- (2026-11-13). When the giver's window shows and the quest is not in it,
-- the upgrade quest notes it here, per character, as
-- `questsNotOffered[questID] = level` (never rename it). It counts only at
-- that level, and every hand-in forgets them all, so a giver is asked
-- again once something changed.

--- Did this quest's giver show the character its quests without this one,
--- at the level the character is now?
function Finder:NotOffered(questID)
    local seen = ns.charDB and ns.charDB.questsNotOffered
    local level = type(seen) == "table" and questID and seen[questID]
    if not level then return false end
    local player = self:Player()
    return player ~= nil and level == player.level
end

--- Note that a quest's giver did not offer it, at this level.
function Finder:NoteNotOffered(questID)
    local player = self:Player()
    if not (ns.charDB and tonumber(questID) and player) then return end
    if type(ns.charDB.questsNotOffered) ~= "table" then ns.charDB.questsNotOffered = {} end
    ns.charDB.questsNotOffered[tonumber(questID)] = player.level
    self:MarkStale()
end

--- The quest to pick up first for a quest reward: the first quest still to
--- do in its chain, or the quest itself. Nil when the first is a quest the
--- data only names.
function Finder:FirstPickup(questID)
    local chain, unknown = self:Chain(questID)
    if unknown then return nil end
    return chain[1] and chain[1].questID or questID
end

--------------------------------------------------------------------------------
-- Quest chains
--------------------------------------------------------------------------------

-- How far back a chain is followed, as in tools/make_sources.py.
local CHAIN_MOST = 20

--- A quest's row: Sources.QUESTS, or Sources.NEEDED (Data/QuestNeeds.lua)
--- for a quest needed first that the data lacks or names no giver for.
function Finder.QuestRow(questID)
    local quest = ns.Sources.QUESTS[questID]
    local needed = type(ns.Sources.NEEDED) == "table" and ns.Sources.NEEDED[questID] or nil
    if needed and (not quest or ((quest[6] or "") == "" and (quest[7] or 0) == 0)) then return needed end
    return quest
end

local function QuestPlace(questID)
    local quest = Finder.QuestRow(questID)
    if not quest then return nil end
    return {
        questID = questID, title = quest[1], questLevel = quest[3], name = quest[6],
        zone = ns.Sources.ZONES[quest[7]],
        x = quest[8] ~= 0 and quest[8] or nil, y = quest[9] ~= 0 and quest[9] or nil,
        group = Finder.QuestNeed(questID, quest),
    }
end

--- Does a quest hand over the item outright (its "You will also receive"),
--- rather than as one of the rewards to choose from?
function Finder.Given(itemID, questID)
    local item = itemID and ns.Sources.ITEMS[itemID]
    for _, given in ipairs(item and item.g or {}) do
        if given == questID then return true end
    end
    return false
end

--- Is a quest in the quest log? Nil when the client cannot say.
function Finder.OnQuest(questID)
    local log = _G.C_QuestLog
    local on = Read(log and log.IsOnQuest, questID)
    if on ~= nil then return on == true end
    local index = Read(log and log.GetLogIndexForQuestID, questID)
    if index ~= nil then return (tonumber(index) or 0) > 0 end
    return nil
end

--- The quests to hand in before a quest opens: all of Sources.NEEDS
--- (Data/QuestNeeds.lua) when it lists them, else the one before it.
function Finder.QuestsFirst(questID, quest)
    local needs = type(ns.Sources.NEEDS) == "table" and ns.Sources.NEEDS[questID] or nil
    if needs then return needs end
    return quest and quest.p and { quest.p } or nil
end

--- The quests still to do before a quest opens, first one first: a list of
--- { questID, title, questLevel, name, zone, x, y, group }. A quest can need
--- several (The Hunt Completed needs all three beasts' quests), and each of
--- those its own first. A quest the item that starts it drops only for
--- (Sources.HOLD: Stonetalon Standstill for the Befouled Water Globe) comes
--- before it until it is in the log. A quest earlier in the chain that the
--- data does not have is named in the second return, by its title, so the
--- player can still be told to do it.
function Finder:Chain(questID)
    local chain, unknown, seen = {}, nil, { [questID] = true }
    local holds = type(ns.Sources.HOLD) == "table" and ns.Sources.HOLD or {}
    local function Walk(id, depth)
        local quest = Finder.QuestRow(id)
        if not quest or depth > CHAIN_MOST or #chain >= CHAIN_MOST then return end
        local befores = Finder.QuestsFirst(id, quest)
        local hold = holds[id]
        if not befores and not hold then
            -- Named, but not in the data: whether it is done cannot be
            -- asked, so the steps let a later quest tick it off.
            if (quest[10] or "") ~= "" and not unknown then unknown = quest[10] end
            return
        end
        for _, before in ipairs(befores or {}) do
            if not seen[before] and not self:QuestDone(before) then
                seen[before] = true
                Walk(before, depth + 1)
                local place = QuestPlace(before)
                if place then chain[#chain + 1] = place end
            end
        end
        if hold and not seen[hold] and not self:QuestDone(hold) and not Finder.OnQuest(hold) then
            seen[hold] = true
            Walk(hold, depth + 1)
            local place = QuestPlace(hold)
            if place then chain[#chain + 1] = place end
        end
    end
    Walk(questID, 0)
    return chain, unknown
end

--- Is a quest open to this character, all the way down its chain? Each
--- quest before it must be open to the character's race and class too: a
--- quest learned on Forever may not say its side, but the one before it
--- does (Twisted Hatred came after a night elf quest and was offered to a
--- Horde rogue).
function Finder:QuestOpenTo(questID, player)
    if not player then return false end
    local seen = {}
    local quest = ns.Sources.QUESTS[questID]
    for _ = 1, CHAIN_MOST + 1 do
        if not quest or seen[quest] then break end
        seen[quest] = true
        if not Finder.Allows(quest[4] or 0, player.raceBit or 0)
            or not Finder.Allows(quest[5] or 0, player.classBit or 0) then
            return false
        end
        quest = quest.p and ns.Sources.QUESTS[quest.p]
    end
    return true
end

--------------------------------------------------------------------------------
-- Solo quests
--------------------------------------------------------------------------------

-- What a quest can need besides the player, as Data/Sources.lua marks it
-- (tools/make_sources.py works it out from Classic's quest data).
Finder.NEEDS = { group = true, dungeon = true, raid = true, battleground = true }

--- What a quest needs besides the player ("group", "dungeon", "raid" or
--- "battleground"), or nil when it can be done alone.
function Finder.Need(group)
    return Finder.NEEDS[group] and group or nil
end

--- What a quest needs besides the player. The quest data's own mark wins;
--- a quest it leaves unmarked (learned on Forever, or some Classic ones)
--- that is on a dungeon quest list needs a dungeon, or a raid when that
--- list's place is one.
function Finder.QuestNeed(questID, quest)
    local need = Finder.Need(quest and quest[11])
    if need or not questID then return need end
    for _, list in ipairs({ ns.DUNGEON_QUESTS, ns.FOREVER_DUNGEON_QUESTS }) do
        local row = type(list) == "table" and list[questID]
        if type(row) == "table" then
            local place = ns.Sources and ns.Sources.DUNGEONS and ns.Sources.DUNGEONS[row[1]]
            return (type(place) == "table" and place[6]) and "raid" or "dungeon"
        end
    end
    return nil
end

--- Can a source be got alone? Everything but a quest that needs a group,
--- a dungeon, a raid or a battleground, or comes after one that does.
function Finder.Solo(source)
    if type(source) ~= "table" or source.kind ~= "quest" then return true end
    return not (Finder.Need(source.group) or Finder.Need(source.chainGroup))
end

--- Does the player want only quests they can do alone? Saved account wide
--- as `soloQuestsOnly`, off unless ticked.
function Finder:SoloOnly()
    return ns.db ~= nil and ns.db.soloQuestsOnly == true
end

--- Tell everything that shows where upgrades come from that the quest
--- filters changed.
function Finder:QuestFilterChanged()
    self:MarkStale()
    for _, name in ipairs({ "UpgradeQuest", "SettingsUI", "FindUpgrades", "QuestTab" }) do
        local module = ns[name]
        if module and module.OnQuestFilterChanged then pcall(module.OnQuestFilterChanged, module) end
    end
end

--- Tick or untick "Solo quests only", for the finder window, the upgrade
--- quest and everything else that shows where upgrades come from.
function Finder:SetSoloOnly(on)
    if not ns.db then return end
    ns.db.soloQuestsOnly = on and true or false
    self:QuestFilterChanged()
end

-- How far above the character's level a quest may be, as the finder's
-- stepper sets it: 0 to QUEST_LEVELS_MOST, or QUEST_LEVELS_ANY for no limit.
-- Classic shows a quest 5 or more levels up in red.
Finder.QUEST_LEVELS_MOST = 10
Finder.QUEST_LEVELS_ANY = 11
Finder.QUEST_LEVELS_DEFAULT = 4

--- How many levels above the character a quest may be, or nil for any.
--- Saved account wide as `questLevelsAbove`.
function Finder:QuestLevelsAbove()
    local value = tonumber(ns.db and ns.db.questLevelsAbove) or self.QUEST_LEVELS_DEFAULT
    value = math.max(0, math.min(self.QUEST_LEVELS_ANY, math.floor(value)))
    if value >= self.QUEST_LEVELS_ANY then return nil end
    return value
end

function Finder:SetQuestLevelsAbove(value)
    if not ns.db then return end
    value = math.max(0, math.min(self.QUEST_LEVELS_ANY, math.floor(tonumber(value) or 0)))
    ns.db.questLevelsAbove = value
    self:QuestFilterChanged()
end

--- Does a quest source pass the quest filters at `level`? Anything that
--- is not a quest always does.
function Finder:QuestAllowed(source, level)
    if type(source) ~= "table" or source.kind ~= "quest" then return true end
    if self:SoloOnly() and not Finder.Solo(source) then return false end
    local above = self:QuestLevelsAbove()
    if above and level and (tonumber(source.questLevel) or 0) > level + above then return false end
    return true
end

--------------------------------------------------------------------------------
-- Sources
--------------------------------------------------------------------------------

local function Allows(mask, flag)
    return mask == 0 or flag == 0 or Band(mask, flag) ~= 0
end
Finder.Allows = Allows

local function ZoneName(zoneID)
    return ns.Sources.ZONES[zoneID]
end

-- The game's standings, 1 Hated to 8 Exalted.
local STANDINGS = {
    L["Hated"], L["Hostile"], L["Unfriendly"], L["Neutral"], L["Friendly"], L["Honored"], L["Revered"], L["Exalted"],
}
Finder.STANDINGS = STANDINGS

--- This character's standing with a faction (1 Hated to 8 Exalted) and the
--- faction's name, or nil when the game cannot say (never met them, say).
function Finder:Standing(factionID)
    local reputation = _G.C_Reputation
    local data = Read(reputation and reputation.GetFactionDataByID, factionID)
    if type(data) == "table" and tonumber(data.reaction) then
        return tonumber(data.reaction), data.name
    end
    local name, _, standing = Read(_G.GetFactionInfoByID, factionID)
    if tonumber(standing) then return tonumber(standing), name end
    return nil, name
end

--- Does an item ask for a standing with a faction at all, reached or not?
--- The upgrade quest offers such gear last.
function Finder.Rep(itemID)
    local item = ns.Sources.ITEMS[itemID]
    local craft = ns.Crafts and ns.Crafts.ITEMS[itemID]
    return ((item and item.r) or (craft and craft.f)) ~= nil
end

--- What an item asks of the character's reputation that they do not have
--- yet: { faction, standing, have } in words, or nil when nothing.
function Finder:Needs(itemID)
    local item = ns.Sources.ITEMS[itemID]
    local craft = ns.Crafts and ns.Crafts.ITEMS[itemID]
    local rep = (item and item.r) or (craft and craft.f)
    if not rep then return nil end

    -- Standing in the data counts from 0 (Hated); the game's from 1.
    local need = rep[2] + 1
    local have, name = self:Standing(rep[1])
    if have and have >= need then return nil end
    if type(name) ~= "string" or name == "" then
        name = ns.Sources.FACTIONS[rep[1]] or L["a faction"]
    end
    return { faction = name, standing = STANDINGS[need] or "?", have = have and STANDINGS[have] }
end

-- Stand-ins for what an item's row lacks, shared by every item. Read only.
local NO_ITEM = { 0, 0, 0, 0, 0 }
local NONE = {}

--- Every place this character can get an item from now, as a list of
--- tables { kind, ... }, vendors first, then quests, then dungeons.
function Finder:SourcesFor(itemID, player)
    local S = ns.Sources
    -- Gear only seen on Forever has no Classic entry; the game says what
    -- level it needs when it is judged.
    local item = S.ITEMS[itemID] or NO_ITEM
    local seen = S.FOREVER and S.FOREVER[itemID]
    -- Gear players make: whoever on the account can make it, or where to
    -- learn it (Logic/Crafting.lua).
    local craft = ns.Crafting and ns.Crafting:SourceFor(itemID, player, Band)
    -- On the auction house at Tradeskills' last scan (Logic/AuctionGear.lua).
    local auction = ns.AuctionGear and ns.AuctionGear:Source(itemID)
    if not S.ITEMS[itemID] and not seen then
        local only = {}
        only[#only + 1] = craft
        only[#only + 1] = auction
        return only
    end

    local found = {}
    if item[1] > player.level or not Allows(item[3], player.classBit)
        or not Allows(item[4], player.raceBit) then
        return found
    end

    local vendors = item.v or NONE
    for i = 1, #vendors, 2 do
        local npc = S.NPCS[vendors[i]]
        if npc and npc[5]:find(player.faction, 1, true) then
            -- Where Forever has the vendor, when seen there (Logic/NPCSpots.lua).
            local name, zone, x, y = npc[1], ZoneName(npc[2]), npc[3], npc[4]
            if ns.NPCSpots then name, zone, x, y = ns.NPCSpots:Place(vendors[i], name, zone, x, y) end
            -- What the vendor charges on Forever, once a merchant window showed it.
            local seenPrice = ns.NPCSpots and ns.NPCSpots:Price(itemID)
            found[#found + 1] = {
                kind = "vendor", name = name, zone = zone, x = x, y = y,
                price = seenPrice or item[5], priceSeen = seenPrice ~= nil, limited = vendors[i + 1] > 0,
            }
        end
    end

    for _, questID in ipairs(item.q or NONE) do
        local quest = S.QUESTS[questID]
        if quest and quest[2] <= player.level and self:QuestOpenTo(questID, player)
            and not self:QuestDone(questID) then
            local chain, unknown = self:Chain(questID)
            -- The first quest still to do in the chain that needs others.
            local chainGroup
            for _, before in ipairs(chain) do
                chainGroup = chainGroup or Finder.Need(before.group)
            end
            local source = {
                chain = #chain + (unknown and 1 or 0), first = unknown or (chain[1] and chain[1].title),
                kind = "quest", questID = questID, title = quest[1], questLevel = quest[3],
                name = quest[6], zone = ZoneName(quest[7]),
                x = quest[8] ~= 0 and quest[8] or nil, y = quest[9] ~= 0 and quest[9] or nil,
                after = quest[10] ~= "" and quest[10] or nil, group = Finder.QuestNeed(questID, quest),
                chainGroup = chainGroup,
                -- Handed over with the quest, not picked from its choices.
                given = Finder.Given(itemID, questID) or nil,
            }
            -- The giver was asked and did not offer the first quest to do.
            local first = not unknown and (chain[1] and chain[1].questID or questID)
            if self:QuestAllowed(source, player.level) and not (first and self:NotOffered(first)) then
                found[#found + 1] = source
            end
        end
    end

    local drops = item.d or NONE
    for i = 1, #drops, 2 do
        local boss = S.BOSSES[drops[i]]
        local dungeon = boss and S.DUNGEONS[boss[2]]
        if dungeon and dungeon[2] <= player.level
            and (dungeon[5] == "" or dungeon[5] == player.faction) then
            found[#found + 1] = {
                kind = "dungeon", name = boss[1], dungeon = dungeon[1],
                minLevel = dungeon[2], maxLevel = dungeon[3], zone = dungeon[4],
                raid = dungeon[6] or false,
                chance = drops[i + 1],
            }
        end
    end

    -- What Farmer's loot records saw drop on Forever: it marks the Classic
    -- drop as confirmed, with Forever's own rate where there is one, or adds
    -- a drop Classic never had.
    for _, drop in ipairs(seen or NONE) do
        local dungeon = S.DUNGEONS[drop[2]]
        if dungeon and dungeon[2] <= player.level
            and (dungeon[5] == "" or dungeon[5] == player.faction) then
            local rate = drop[3] > 0 and drop[3] or nil
            local match
            for _, source in ipairs(found) do
                if source.kind == "dungeon" and source.name:lower() == drop[1]:lower() then
                    match = source
                end
            end
            if match then
                match.forever = true
                match.chance = rate or match.chance
            else
                found[#found + 1] = {
                    kind = "dungeon", name = drop[1], dungeon = dungeon[1],
                    minLevel = dungeon[2], maxLevel = dungeon[3], zone = dungeon[4],
                    raid = dungeon[6] or false, chance = rate, forever = true,
                }
            end
        end
    end

    found[#found + 1] = craft
    found[#found + 1] = auction

    -- Somewhere in the zone the character is standing in comes first: a
    -- vendor down the road beats the same item across the world.
    if player.zone then
        -- Most gear has nothing in this zone, or nothing out of it: then
        -- the order stands as it is and no new lists are made.
        local inZone = 0
        for _, source in ipairs(found) do
            if source.zone == player.zone then inZone = inZone + 1 end
        end
        if inZone > 0 and inZone < #found then
            local here, there = {}, {}
            for _, source in ipairs(found) do
                local list = source.zone == player.zone and here or there
                list[#list + 1] = source
            end
            for _, source in ipairs(there) do here[#here + 1] = source end
            found = here
        end
    end

    return found
end

--- The item IDs a scan looks at for this character: in level range, lowest
--- first. Gear the gear list has already found is never for them
--- (Logic/GearList.lua) is passed by with one lookup. `from`, when given,
--- is the level the range starts from (My Gear's Gear Road looks from
--- today's level all the way to 60).
function Finder:CandidateIDs(player, from)
    local list = ns.GearList
    local floor = (tonumber(from) or player.level) - LEVELS_BELOW
    local ids = {}
    for itemID, item in pairs(ns.Sources.ITEMS) do
        if item[2] >= floor and item[1] <= player.level and not (list and list:Out(itemID)) then
            ids[#ids + 1] = itemID
        end
    end
    for itemID in pairs(ns.Sources.FOREVER or {}) do
        if not ns.Sources.ITEMS[itemID] and not (list and list:Out(itemID)) then ids[#ids + 1] = itemID end
    end
    -- Recipes the characters learned that Classic's data lacks.
    if ns.Crafting and ns.Crafting.LayLearned then ns.Crafting:LayLearned() end
    for itemID, craft in pairs(ns.Crafts and ns.Crafts.ITEMS or {}) do
        if not ns.Sources.ITEMS[itemID] and not (ns.Sources.FOREVER or {})[itemID]
            and craft[5] >= floor and craft[4] <= player.level and not (list and list:Out(itemID)) then
            ids[#ids + 1] = itemID
        end
    end
    -- Gear on the auction house at Tradeskills' last scan
    -- (Logic/AuctionGear.lua) that no other place offers.
    local auction = ns.AuctionGear
    if auction and auction:On() then
        local crafts = ns.Crafts and ns.Crafts.ITEMS or {}
        for _, itemID in ipairs(auction:IDs()) do
            if not ns.Sources.ITEMS[itemID] and not (ns.Sources.FOREVER or {})[itemID] and not crafts[itemID]
                and not (list and list:Out(itemID)) then
                ids[#ids + 1] = itemID
            end
        end
    end
    table.sort(ids)
    return ids
end

--- One item as something to judge: { itemID, sources, needs, rep,
--- wearable }, or nil when the class can never wear it or nothing is open
--- to the character that gives it.
function Finder:Candidate(itemID, player, only)
    -- Sorted once a session: never for this class or race, or a weapon
    -- the class has no skill for.
    local list = ns.GearList
    local state = list and list:State(itemID, player)
    if state == false or state == "skill" then return nil end
    -- Gear the class can never wear (plate for a mage) is dropped by the
    -- scan anyway; asked first, from the client's instant item info, its
    -- vendors, quests, drops and crafts are never worked out.
    local wearable = Finder.Wearable(player.class, itemID)
    if wearable == false then return nil end
    local sources = self:SourcesFor(itemID, player)
    if only then
        local kept = {}
        for _, source in ipairs(sources) do
            if source.kind == only then kept[#kept + 1] = source end
        end
        sources = kept
    end
    if #sources == 0 then return nil end
    return {
        itemID = itemID, sources = sources, needs = self:Needs(itemID), rep = Finder.Rep(itemID),
        wear = ns.Crafting and ns.Crafting.Wear and ns.Crafting:Wear(itemID) or nil,
        -- Found a moment ago, so the scan need not ask again.
        -- Only a yes is kept: an item still loading is asked
        -- about again when the scan reaches it.
        wearable = wearable == true or nil,
    }
end

--- The items worth judging for this character: in level range, with at least
--- one source open to them. A list of { itemID, sources }.
function Finder:Candidates(player, only, pause)
    local list = {}
    for _, itemID in ipairs(self:CandidateIDs(player)) do
        if pause then pause() end
        list[#list + 1] = self:Candidate(itemID, player, only)
    end
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
--- What was asked is remembered, so an answer about some other item (a chat
--- link, another addon's window) does not set off a scan.
--- Nothing is asked while a quest giver's window is open: the reward
--- choices there wait on the same queue, and the scan can ask again once it
--- closes. An item asked ASK_TRIES times without arriving is not asked again,
--- and one asked a moment ago is not asked twice while its answer is due.
--- @return true when the server was asked
function Finder:Request(itemID)
    self.asked = self.asked or {}
    self.tries = self.tries or {}
    if (self.tries[itemID] or 0) >= ASK_TRIES then return false end
    if self.QuestWindowOpen() then return false end
    if self:Awaited(itemID) then return false end
    self.asked[itemID] = true
    -- Waiting on the server for this one. Only its answer counts; the client
    -- says the same event again whenever it loads the item for anyone else.
    self.pending = self.pending or {}
    self.pending[itemID] = true
    self.askedAt = self.askedAt or {}
    self.askedAt[itemID] = self.Now()
    self.tries[itemID] = (self.tries[itemID] or 0) + 1
    local C = _G.C_Item
    local request = C and C.RequestLoadItemDataByID
    if type(request) == "function" then
        Read(request, itemID)
    else
        Read(C and C.GetItemInfo or _G.GetItemInfo, itemID)
    end
    return true
end

--- Was the server asked about this item a moment ago, with no answer yet?
--- Its answer is still due, so asking again would only spend a try.
function Finder:Awaited(itemID)
    if not (self.pending and self.pending[itemID]) then return false end
    local at = self.askedAt and self.askedAt[itemID]
    if type(at) ~= "number" then return false end
    local waited = self.Now() - at
    return waited >= 0 and waited < ANSWER_WAIT
end

--- Has the server been asked about this item as often as it will be?
function Finder:GaveUp(itemID)
    return self.tries ~= nil and (self.tries[itemID] or 0) >= ASK_TRIES
end

--- Is the game's quest giver window (offer, progress or hand-in) open?
function Finder.QuestWindowOpen()
    local frame = _G.QuestFrame
    if type(frame) ~= "table" then return false end
    local ok, shown = pcall(function() return frame:IsShown() and true or false end)
    return ok and shown or false
end

--- Can this class wear the item at all? Read from the client's own item
--- table, which needs no server answer, so nothing is asked about gear the
--- class could never use. Nil when the client cannot say without asking.
local function Wearable(class, itemID)
    local info = Items:Info(("item:%d"):format(itemID))
    if not info then return nil end
    if not Compare.SLOTS[info.equipLoc] then return false end
    local usable = Weights:CanUse(class, info.classID, info.subclassID, info.equipLoc)
        and Compare:ClassAllows(class, itemID)
    return usable and true or false
end
Finder.Wearable = Wearable

local ITEM_INFO = { "C_Item.GetItemInfo", "GetItemInfo" }

-- An item's whole link, once the client gave it: its name and colour never
-- change, and every scan asked again for every pick.
local linkOf = {}

--- The item's own link, quality colour and all, where the client has it.
local function LinkFor(itemID)
    local kept = linkOf[itemID]
    if kept then return kept end
    local _, link = Items.Call(ITEM_INFO, itemID)
    link = Items.PlainLink(link)
    -- Kept only whole, with its name in: a link read while the item loads
    -- has none ("[]").
    if link and link:find("|H", 1, true) and not link:find("[]", 1, true) then linkOf[itemID] = link end
    return link or ("item:%d"):format(itemID)
end

--- A rolled item's link from the client ("[Chain Vest of the Monkey]"),
--- or the plain item's when the client has none for the roll.
local function RolledLink(rolled, itemID)
    local _, link = Items.Call(ITEM_INFO, rolled)
    link = Items.PlainLink(link)
    if link and link:find("|H", 1, true) then return link end
    return LinkFor(itemID)
end

--- The item IDs in the carried bags, as a set.
function Finder:Carried()
    local carried = {}
    for bag = 0, 4 do
        for slot = 1, Items:BagSize(bag) do
            local link = Items:InBag(bag, slot)
            local id = link and tonumber(link:match("item:(%d+)"))
            if id then carried[id] = true end
        end
    end
    return carried
end

--- Gear the character playing owns already, as { [itemID] = "bags" or
--- "bank" }: the carried bags, and its own bank as last seen open
--- (Alts:ReadBank). No GUID (a dungeon can keep it back): the bags only.
--- Nothing owned is an upgrade to go and get (a player's report,
--- 2026-11-25: dungeon drops already in the bags were listed).
function Finder:Owned()
    local owned = {}
    local Alts = ns.Alts
    local me = Alts and Alts.PlayerGUID()
    local note = me and Alts:Notes()[me]
    for _, entry in ipairs(type(note) == "table" and type(note.bank) == "table" and note.bank or {}) do
        local link = type(entry) == "table" and entry.link or entry
        local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
        if id then owned[id] = "bank" end
    end
    for id in pairs(self:Carried()) do owned[id] = "bags" end
    return owned
end

--------------------------------------------------------------------------------
-- The scan
--------------------------------------------------------------------------------

--- Is a verdict an upgrade worth listing? Wearable now, or, when planning
--- ahead, wearable by the level planned for.
local function Counts(result, reach, level)
    if Compare.WearableUpgrade(result) then return true end
    return reach > level and result.verdict == "upgrade" and result.level ~= nil
        and result.level <= reach and not result.train
end

--- Every pick's sources are gear nobody on the account can make: a
--- crafter or the auction house would have to supply it.
local function Remote(sources)
    for _, source in ipairs(sources) do
        if not (source.kind == "craft" and source.state == "other") then return false end
    end
    return true
end

--- The verdicts kept from earlier scans, for gear, level, talents, weapon
--- skills and stat weights as they are now. Judging thousands of items on
--- every scan made the game hitch; most scans only need the few items whose
--- details just arrived judged. Started afresh when any of those changes.
local function WornStatsRead()
    local read = 0
    for slot = 1, 19 do
        local link = Items:Equipped(slot)
        if link and Items:Stats(link) then read = read + 1 end
    end
    return read
end

--- The gear worn as one string, by item string only. A worn link the
--- client has let go of reads with no name ("[]"), and its name coming and
--- going must not count as a gear change: that threw every verdict away
--- and the window scanned over and over (a player's report, 2026-11-13).
local function WornKey()
    local parts = {}
    for slot = 1, 19 do
        local link = Items:Equipped(slot)
        parts[slot] = link and (link:match("item:[^|%[]+") or link) or "-"
    end
    return table.concat(parts, ";")
end
Finder.WornKey = WornKey

--- The worn gear's key, the most of its stats ever read for that gear, and
--- how many read now. The client lets worn gear go from its memory now and
--- then; the count falling then is not a change, and judging meanwhile
--- would weigh every item against nothing.
function Finder:WornState()
    local key, read = WornKey(), WornStatsRead()
    if key ~= self.wornKey then
        self.wornKey, self.wornBest = key, read
    elseif read > (self.wornBest or 0) then
        self.wornBest = read
    end
    return key, self.wornBest, read
end

function Finder:JudgeKey()
    -- Worn gear whose stats had not loaded yet (just after login) scores
    -- nothing, so the most of its stats read is part of the key too.
    local wornKey, wornBest = self:WornState()
    return table.concat({
        tostring(wornKey), tostring(wornBest), tostring(Items:PlayerLevel()),
        tostring(Weights.generation or 0), tostring(self.judgeGeneration or 0),
        -- A character skipped for upgrades has none (Alts:SetSkipped).
        tostring(ns.Alts and ns.Alts:PlayerSkipped() or false),
        -- Learning Dual Wield changes what an off-hand weapon is judged
        -- against, and may come with no skill or talent event.
        tostring(Weights:CanDualWield(Weights:PlayerClass(), Items:PlayerLevel())),
    }, "|")
end

--- What every kept verdict leans on besides the gear worn: level, stat
--- weights, talents and weapon skills, the skip setting and dual wield.
--- When it changes, every verdict is made again.
function Finder:VerdictKey()
    return table.concat({
        tostring(Weights.judgeAs or ""),
        tostring(Items:PlayerLevel()),
        tostring(Weights.generation or 0), tostring(self.judgeGeneration or 0),
        tostring(ns.Alts and ns.Alts:PlayerSkipped() or false),
        tostring(Weights:CanDualWield(Weights:PlayerClass(), Items:PlayerLevel())),
    }, "|")
end

-- The two hands lean on each other (a two-hander empties the off hand, a
-- one-hander may go in either), so a change in one looks at both.
local HANDS = { 16, 17 }

--- The slots a verdict on this kind of gear leans on.
local function GroupOf(equipLoc)
    local slots = Compare.SLOTS[equipLoc]
    if not slots then return nil end
    if slots[1] == 16 or slots[1] == 17 then return HANDS end
    return slots
end

local function HitOf(link, weights)
    if not link then return 0 end
    local ok, score, hit = pcall(Compare.ScoreOf, Compare, link, weights)
    -- Not readable: counted as having hit, to be safe.
    if not ok or not score then return nil end
    return hit or 0
end

--- The gear worn changed in one slot. Verdicts for that slot (and the
--- other hand) are made again; the rest are kept, unless the piece taken
--- off or put on reaches further: hit counts against the cap with every
--- other piece's hit, and a set piece changes what its set is worth.
function Finder:SlotChanged(slot, was, now)
    local looks = self.slotLooks
    looks[slot] = (looks[slot] or 0) + 1
    self.toLook[slot] = true
    local weights = Weights:ForPlayer()
    local far = false
    if weights and Weights.HitKind(weights) then
        -- Swinging two weapons moves the cap itself.
        if slot == 16 or slot == 17 then far = true end
        if HitOf(was, weights) ~= 0 or HitOf(now, weights) ~= 0 then far = true end
    end
    if far then self.hitLooks = (self.hitLooks or 0) + 1 end
    local sets = ns.ItemSets
    if sets and sets.SetOf then
        local okWas, setWas = pcall(sets.SetOf, sets, was)
        local okNow, setNow = pcall(sets.SetOf, sets, now)
        if not okWas or not okNow or setWas or setNow then self.setLooks = (self.setLooks or 0) + 1 end
    end
end

--- Compare the gear worn with what was worn at the last look, slot by
--- slot. Read from the gear itself, not from an event, so a change whose
--- event was missed is still caught.
function Finder:LookAtWorn()
    self.slotLooks = self.slotLooks or {}
    self.toLook = self.toLook or {}
    local seen, links = self.wornSeen, self.wornLinks
    local first = seen == nil
    if first then
        seen, links = {}, {}
        self.wornSeen, self.wornLinks = seen, links
    end
    for slot = 1, 19 do
        local link = Items:Equipped(slot)
        -- By item string only: a link the client let go of reads with no
        -- name, and that is no change (WornKey).
        local key = link and (link:match("item:[^|%[]+") or link) or "-"
        if seen[slot] ~= key then
            local was = links[slot]
            seen[slot], links[slot] = key, link
            if not first then self:SlotChanged(slot, was, link) end
        elseif link and not link:find("[]", 1, true) then
            -- The whole link, name and all, once the client has it.
            links[slot] = link
        end
    end
end

--- Does this slot need a new look: has what is worn there changed since
--- the last whole scan?
function Finder:NeedsLook(slot)
    return self.toLook ~= nil and self.toLook[slot] == true
end

--- What a kept verdict leans on, as one number: it moves when any of the
--- slots, the hit or the sets the verdict reads have changed.
local function Stamp(self, entry)
    local looks = self.slotLooks or {}
    local stamp = 0
    for _, slot in ipairs(entry.slots) do stamp = stamp + (looks[slot] or 0) end
    if entry.hit then stamp = stamp + (self.hitLooks or 0) end
    if entry.set then stamp = stamp + (self.setLooks or 0) end
    return stamp
end

--- A new verdict to keep, with what it leans on. Nil when that can't be
--- told (then it is judged again next time).
local function Entry(self, link, best, result)
    local info = Items:Info(link)
    local slots = info and GroupOf(info.equipLoc)
    if not slots then return nil end
    local entry = { best = best, result = result, slots = slots }
    local weights = Weights:ForPlayer()
    if weights and Weights.HitKind(weights) and result.verdict ~= "cantuse" then
        -- Gear with random rolls: any roll may carry hit.
        entry.hit = best ~= nil or HitOf(link, weights) ~= 0
        for _, slot in ipairs(slots) do
            if not entry.hit and HitOf(Items:Equipped(slot), weights) ~= 0 then entry.hit = true end
        end
    end
    local sets = ns.ItemSets
    if sets and sets.SetOf then
        local ok, set = pcall(sets.SetOf, sets, link)
        entry.set = not ok or set ~= nil
        for _, slot in ipairs(slots) do
            if not entry.set then
                local okWorn, wornSet = pcall(sets.SetOf, sets, Items:Equipped(slot))
                entry.set = not okWorn or wornSet ~= nil
            end
        end
    end
    entry.stamp = Stamp(self, entry)
    return entry
end

--- The verdicts kept from earlier scans. All of them start afresh when
--- the level, weights, talents or weapon skills change; a change of gear
--- drops only the verdicts that lean on the slot that changed (Kept).
function Finder:Judged()
    local key = self:JudgeKey()
    local verdictKey = self:VerdictKey()
    -- `judgedKey` cleared by hand starts afresh too.
    if verdictKey ~= self.verdictKey or self.judgedKey == nil or type(self.judged) ~= "table" then
        self.verdictKey, self.judged = verdictKey, {}
        -- Every slot is looked at again.
        self.toLook = self.toLook or {}
        for slot = 1, 19 do self.toLook[slot] = true end
    end
    self.judgedKey = key
    self:LookAtWorn()
    return self.judged
end

--- An item's kept verdict, if nothing it leans on has changed since:
--- { best, result, main }, or nil.
function Finder:Kept(judged, itemID)
    local entry = judged[itemID]
    if not entry then return nil end
    if entry.stamp ~= Stamp(self, entry) then
        judged[itemID] = nil
        return nil
    end
    return entry
end

--- Forget the kept verdicts (talents or weapon skills changed).
function Finder:ForgetVerdicts()
    self.judgeGeneration = (self.judgeGeneration or 0) + 1
    -- A skill learned may open weapons the gear list had set aside.
    if ns.GearList then ns.GearList:SkillsChanged() end
    self:MarkStale()
end

--- One item's verdict, judged once per Judged() set. Gear with random rolls
--- is judged at its best roll.
-- @return best roll (or nil), ok, result
function Finder:JudgeOnce(judged, itemID)
    local kept = self:Kept(judged, itemID)
    if kept then return kept.best, true, kept.result end
    local best = ns.Rolls and ns.Rolls.Best and ns.Rolls:Best(itemID)
    local link = best and best.link or ("item:%d"):format(itemID)
    local ok, result = true, best and best.result
    if not best then ok, result = pcall(Compare.Judge, Compare, link) end
    -- Only a full answer is kept: an item still loading, or rolled gear with
    -- rolls the client has not seen yet, is judged again next time.
    local data = ns.RollData
    local group = data and data.ITEMS and data.ITEMS[itemID]
    local rolls = group and data.GROUPS and data.GROUPS[group]
    local allRolls = not rolls or (best and (best.rolls or 0) * 2 >= #rolls)
    if ok and type(result) == "table" and allRolls then
        judged[itemID] = Entry(self, link, best, result)
    end
    return best, ok, result
end

--- A one-hand weapon judged against the off hand (the weaker hand), judged
--- again in the main hand: that verdict when it is an upgrade there too,
--- else nil. Kept with the item's verdict, so later scans ask no more.
function Finder:MainHandToo(judged, itemID, best, result)
    if type(result) ~= "table" or result.slot ~= 17 or result.verdict ~= "upgrade" then return nil end
    local link = best and best.link or ("item:%d"):format(itemID)
    local info = Items:Info(link)
    if not info or info.equipLoc ~= "INVTYPE_WEAPON" then return nil end
    local kept = judged[itemID]
    if kept and kept.main ~= nil then return kept.main or nil end
    local ok, main = pcall(Compare.Judge, Compare, link, 16)
    if not ok or type(main) ~= "table" then return nil end
    if main.slot ~= 16 or main.verdict ~= "upgrade" then main = false end
    if kept then kept.main = main end
    return main or nil
end

--- The order picks show in, best first: what can be had now before gear
--- that waits on a reputation, both before gear someone else would have to
--- make, then by the percent shown (an empty slot, which shows none, ahead
--- of any), then nearest first, then by gain. The percent comes before
--- nearness so a tie broken by nearness never fights the gain: mixing the
--- two could order three picks in a circle, which table.sort may refuse
--- with an error. Upgrades that show the same "+12%" come nearest first (a
--- player asked, 2026-10-09). The finder window sorts its rings and
--- trinkets, two slots shown as one, by it too.
function Finder.Order(a, b)
    if (a.needs == nil) ~= (b.needs == nil) then return a.needs == nil end
    if a.remote ~= b.remote then return not a.remote end
    -- A scan keeps each pick's percent beside the verdict it came from
    -- (sorting hundreds of picks worked it out thousands of times).
    local pa, pb
    if a.shownFor == a.result then pa = a.shown or nil else pa = Finder.Shown(a.result) end
    if b.shownFor == b.result then pb = b.shown or nil else pb = Finder.Shown(b.result) end
    if (pa == nil) ~= (pb == nil) then return pa == nil end
    if pa and pa ~= pb then return pa > pb end
    if (a.near or 0) ~= (b.near or 0) then return (a.near or 0) < (b.near or 0) end
    if (a.gain or 0) ~= (b.gain or 0) then return (a.gain or 0) > (b.gain or 0) end
    return a.itemID < b.itemID
end

--- Look for upgrades, from every kind of source or only `only` ("vendor",
--- "quest", "dungeon" or "craft"), and `ahead` levels past the character's
--- (0 or nil for now).
-- @return nil and why, or a table:
--   slots     { [inventory slot] = { pick, ... } } best first, at most
--             PER_SLOT each; a pick is { itemID, link, result, gain,
--             sources, needs, rep, roll, at }: `rep` for gear tied to
--             a reputation (reached or not), `roll` for gear with random rolls
--             (Logic/Rolls.lua's best), `at` the level it can be worn from
--             when that is still ahead
--   all       { [inventory slot] = { pick, ... } } the same, every pick
--             kept, for the upgrade quest's "This zone only", whose best
--             here is seldom among the best anywhere
--   count     how many picks in all
--   checked   how many items were judged
--   waiting   how many the server has still to answer about
--   player    the player table
--   reach     the level looked at
function Finder:Scan(only, ahead)
    return self:Build(only, ahead)
end

--------------------------------------------------------------------------------
-- A pair of one-handers against a worn two-hander
--------------------------------------------------------------------------------

-- How many pairs a scan keeps: the best partner for each of the strongest
-- main hands.
Finder.PAIRS_KEPT = 3
local MAIN_LOCS = { INVTYPE_WEAPON = true, INVTYPE_WEAPONMAINHAND = true }
local OFF_LOCS = { INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true, INVTYPE_WEAPONOFFHAND = true }

--- The worn two-hander's score, when the main hand holds one: a pair of
--- one-handers is weighed against it. Nil otherwise.
function Finder:PairAgainst(weights)
    local link = Items:Equipped(16)
    local info = link and Items:Info(link)
    if not (info and info.equipLoc == "INVTYPE_2HWEAPON") then return nil end
    local score = Compare:ScoreOf(link, weights)
    if type(score) ~= "number" or score <= 0 then return nil end
    return score
end

--- Can a verdict go in a pair? Wearable now (no level, training or skill
--- to wait on) and judged for the hands.
local function Pairable(result)
    if type(result) ~= "table" or type(result.score) ~= "number" then return false end
    local verdict = result.verdict
    if verdict ~= "upgrade" and verdict ~= "same" and verdict ~= "downgrade" then return false end
    if result.level or result.train or result.skill then return false end
    return result.slot == 16 or result.slot == 17
end

--- Note an item judged in a scan as a main hand or off hand for a pair.
function Finder.NotePair(notes, itemID, best, result, dualWield)
    if not (notes and Pairable(result)) then return end
    local link = best and best.link and RolledLink(best.link, itemID) or LinkFor(itemID)
    local info = Items:Info(link)
    local loc = info and info.equipLoc
    if not loc then return end
    local entry = { itemID = itemID, link = link, result = result, score = result.score }
    if MAIN_LOCS[loc] then notes.mains[#notes.mains + 1] = entry end
    if OFF_LOCS[loc] or (loc == "INVTYPE_WEAPON" and dualWield) then notes.offs[#notes.offs + 1] = entry end
end

local function ByScore(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return a.itemID < b.itemID
end

--- The best pairs from what a scan noted: each of the strongest main hands
--- with its best partner, kept only when the two beat the two-hander.
--- Where each comes from is worked out for these few only.
function Finder:MakePairs(notes, plan, only, skip)
    local out = {}
    if not (notes and notes.against) then return out end
    table.sort(notes.mains, ByScore)
    table.sort(notes.offs, ByScore)
    local sources = {}
    local function Sources(itemID)
        if sources[itemID] == nil then
            local candidate = self:Candidate(itemID, plan, only)
            sources[itemID] = candidate or false
        end
        return sources[itemID] or nil
    end
    -- Each item goes in one pair at most, the best it makes.
    local used = {}
    -- First a new piece with the best partner you own for the other hand
    -- (Logic/BackupWeapons.lua): "with Sample Dagger, in your bags".
    local owned, mine = notes.owned, {}
    if owned then
        local function Partner(list, itemID)
            for _, piece in ipairs(list or {}) do
                if tonumber(piece.link:match("item:(%d+)")) ~= itemID then return piece end
            end
            return nil
        end
        local function Try(entry, list, slot)
            if #mine >= Finder.PAIRS_KEPT or used[entry.itemID] or (skip and skip[entry.itemID]) then return end
            local partner = Partner(list, entry.itemID)
            if not partner then return end
            local total = entry.score + partner.score
            local percent = (total - notes.against) / notes.against * 100
            if percent < 1 then return end
            local from = Sources(entry.itemID)
            if not from then return end
            mine[#mine + 1] = {
                itemID = entry.itemID, link = entry.link, sources = from.sources,
                needs = from.needs, rep = from.rep, wear = from.wear, remote = Remote(from.sources),
                gain = total - notes.against,
                result = {
                    verdict = "upgrade", slot = slot, score = total, against = notes.against,
                    percent = percent, pair = true,
                },
                pair = {
                    itemID = tonumber(partner.link:match("item:(%d+)")), link = partner.link,
                    owned = partner.where, sources = {},
                },
            }
            used[entry.itemID] = true
        end
        -- Best first across both hands.
        local tries = {}
        for _, main in ipairs(notes.mains) do tries[#tries + 1] = { main, owned.offs, 16 } end
        for _, off in ipairs(notes.offs) do tries[#tries + 1] = { off, owned.mains, 17 } end
        table.sort(tries, function(a, b) return ByScore(a[1], b[1]) end)
        for _, try in ipairs(tries) do Try(try[1], try[2], try[3]) end
    end
    for _, pick in ipairs(mine) do out[#out + 1] = pick end
    local kept = #out
    for _, main in ipairs(notes.mains) do
        if #out - kept >= Finder.PAIRS_KEPT then break end
        local mainFrom = not used[main.itemID] and not (skip and skip[main.itemID]) and Sources(main.itemID) or nil
        if mainFrom then
            for _, off in ipairs(notes.offs) do
                if off.itemID ~= main.itemID and not used[off.itemID] and not (skip and skip[off.itemID]) then
                    local total = main.score + off.score
                    if (total - notes.against) / notes.against * 100 < 1 then break end
                    local offFrom = Sources(off.itemID)
                    if offFrom then
                        out[#out + 1] = {
                            itemID = main.itemID, link = main.link, sources = mainFrom.sources,
                            needs = mainFrom.needs or offFrom.needs, rep = mainFrom.rep or offFrom.rep,
                            wear = mainFrom.wear, remote = Remote(mainFrom.sources) or Remote(offFrom.sources),
                            gain = total - notes.against,
                            result = {
                                verdict = "upgrade", slot = 16, score = total, against = notes.against,
                                percent = (total - notes.against) / notes.against * 100, pair = true,
                            },
                            pair = {
                                itemID = off.itemID, link = off.link, sources = offFrom.sources,
                                result = off.result,
                            },
                        }
                        used[main.itemID], used[off.itemID] = true, true
                        break
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.gain ~= b.gain then return a.gain > b.gain end
        return a.itemID < b.itemID
    end)
    return out, self:BackupUps(notes, Sources, skip)
end

-- How many new pieces a scan keeps for each hand of the backup set.
Finder.BACKUP_KEPT = 2

--- New pieces that beat the backup set's main hand or off hand, even while
--- the pair still loses to the two-hander (the owner asked, 2026-11-26).
--- Each is a pick with `backup` = { link, where } (the piece it beats) and
--- its gain against that piece. Main Spec only, with Backup Weapon Set on.
function Finder:BackupUps(notes, Sources, skip)
    local out = {}
    local set = notes and notes.backup
    if not set then return out end
    for _, hand in ipairs({ { notes.mains, set.main, 16 }, { notes.offs, set.off, 17 } }) do
        local list, piece, slot = hand[1], hand[2], hand[3]
        local count = 0
        for _, entry in ipairs(list) do
            if count >= Finder.BACKUP_KEPT then break end
            if piece.score <= 0 then break end
            local percent = (entry.score - piece.score) / piece.score * 100
            if percent < 1 then break end
            local from = not (skip and skip[entry.itemID]) and Sources(entry.itemID) or nil
            if from and entry.itemID ~= tonumber(piece.link:match("item:(%d+)")) then
                count = count + 1
                out[#out + 1] = {
                    itemID = entry.itemID, link = entry.link, sources = from.sources,
                    needs = from.needs, rep = from.rep, wear = from.wear, remote = Remote(from.sources),
                    gain = entry.score - piece.score,
                    result = {
                        verdict = "upgrade", slot = slot, score = entry.score, against = piece.score,
                        percent = percent, backup = true,
                    },
                    backup = { link = piece.link, where = piece.where },
                }
            end
        end
    end
    return out
end

--- The scan itself. `pause`, when given, is called between items: the
--- background scan hands one in that yields once a frame's share is used.
--- With `wide` a scan ahead keeps the gear from today's level up too, not
--- only gear near the level planned for (UI/GearRoad.lua).
function Finder:Build(only, ahead, pause, wide)
    local player = self:Player()
    if not player then return nil, "nolevel" end
    -- What had changed when this scan began. A sliced scan runs over many
    -- frames, and a change that lands meanwhile leaves it out of date.
    local changes = self.changes or 0
    -- How many item answers had come in; one after this is not in it.
    local answersAt = self.answers or 0

    local weights = Weights:ForPlayer()
    if not weights then return nil, "noweights" end

    -- Looking ahead: everything open to the character at the level planned
    -- for, judged against what is worn today.
    local level = player.level
    local reach = math.min(60, level + math.max(0, math.floor(tonumber(ahead) or 0)))
    local plan = player
    if reach > level then
        plan = {}
        for key, value in pairs(player) do plan[key] = value end
        plan.level = reach
    end

    -- Gear already in the bags or bank is the gear window's to show, not
    -- something to go and buy or farm again.
    local carried = self:Owned()

    local judged = self:Judged()
    -- The key these verdicts were made under; a scan made meanwhile may move
    -- self.judgedKey on before this one finishes.
    local judgedKey = self.judgedKey
    local worn = Compare:WornIDs()
    local slots, checked, waiting, asked = {}, 0, 0, 0
    local queue = {}
    -- Items an earlier scan asked about a moment ago, their answers still due.
    local held = 0
    -- Worn gear the client let go of: ask for it back, and judge nothing new
    -- until it is in, since every item would be weighed against nothing.
    local _, wornBest, wornRead = self:WornState()
    local wornShort = wornRead < (wornBest or 0)
    if wornShort then
        for slot = 1, 19 do
            local link = Items:Equipped(slot)
            local id = link and tonumber(link:match("item:(%d+)"))
            if id and not Items:Stats(link) then self:Request(id) end
        end
    end
    -- The slots waiting for a look as this scan begins.
    local looking = {}
    for slot, yes in pairs(self.toLook or {}) do
        if yes then looking[slot] = (self.slotLooks or {})[slot] or 0 end
    end
    -- A worn two-hander: one-handers and off hands are noted as they are
    -- judged, to weigh pairs of them against it (Finder:MakePairs). The
    -- Main Spec's own scan of today only.
    local pairNotes
    if not self.offPass and not wide and reach == level then
        local against = self:PairAgainst(weights)
        if against then
            pairNotes = { against = against, mains = {}, offs = {},
                dual = Weights:CanDualWield(Weights:PlayerClass(), level) }
            -- The best main hands and off hands you own already, to pair a
            -- new piece with (Logic/BackupWeapons.lua).
            local Backup = ns.BackupWeapons
            local okOwned, owned = pcall(function() return Backup and Backup:Pieces(weights) end)
            if okOwned and owned then pairNotes.owned = owned end
            -- With Backup Weapon Set on: the backup set itself, so a new
            -- piece that beats its main hand or off hand is listed too.
            if Backup and Backup.On() then
                local okSet, set = pcall(Backup.Set, Backup)
                if okSet and set and set.mode == "pair" then pairNotes.backup = set end
            end
        end
    end
    for _, itemID in ipairs(self:CandidateIDs(plan, wide and level or nil)) do
        if pause then pause() end
        -- An item judged before keeps its verdict, even when the client has
        -- let go of its details since: asking again would start the scans
        -- over and over, and the list would change each time.
        local entry = not carried[itemID] and not worn[itemID] and self:Kept(judged, itemID) or nil
        local kept = entry ~= nil
        -- A kept verdict that is no upgrade has nothing to list: where the
        -- item comes from is not worked out again. Most items end here.
        local candidate
        if entry and not (Counts(entry.result, reach, level) and entry.result.slot) then
            checked = checked + 1
            if pairNotes and not carried[itemID] and not worn[itemID] then
                Finder.NotePair(pairNotes, itemID, entry.best, entry.result, pairNotes.dual)
            end
        else
            candidate = self:Candidate(itemID, plan, only)
            if candidate and pause then pause() end
        end
        local wearable = candidate and (kept or (not carried[itemID]
            and (candidate.wearable or Wearable(player.class, itemID))))
        if candidate and wearable ~= false then
            if not kept and (wearable == nil or not self:IsCached(itemID)) then
                -- One the server never answered is not waited on for ever.
                if not self:GaveUp(itemID) then
                    waiting = waiting + 1
                    if self:Awaited(itemID) then
                        -- Asked by the scan before this one. It counts
                        -- toward this batch and is not asked twice.
                        held = held + 1
                    elseif asked + held < ASK_PER_SCAN then
                        if self:Request(itemID) then asked = asked + 1 end
                    else
                        -- Asked for a batch at a time once these answers
                        -- settle (AskMore), without scanning again.
                        queue[#queue + 1] = itemID
                    end
                end
            elseif not kept and wornShort then
                waiting = waiting + 1
            elseif not worn[itemID] then
                local best, ok, result = self:JudgeOnce(judged, itemID)
                if ok and result and pairNotes then
                    Finder.NotePair(pairNotes, itemID, best, result, pairNotes.dual)
                end
                if ok and result then
                    checked = checked + 1
                    if Counts(result, reach, level) and result.slot then
                        local list = slots[result.slot] or {}
                        slots[result.slot] = list
                        list[#list + 1] = {
                            itemID = itemID, link = best and RolledLink(best.link, itemID) or LinkFor(itemID),
                            result = result,
                            gain = (result.score or 0) - (result.against or 0),
                            sources = candidate.sources, needs = candidate.needs, rep = candidate.rep,
                            wear = candidate.wear,
                            roll = best, at = result.level, remote = Remote(candidate.sources),
                        }
                        -- A one-hander that beats the off hand may beat the
                        -- main hand too, where it hits harder for most.
                        local main = self:MainHandToo(judged, itemID, best, result)
                        if main and Counts(main, reach, level) then
                            local mainList = slots[16] or {}
                            slots[16] = mainList
                            local pick = {}
                            for key, value in pairs(list[#list]) do pick[key] = value end
                            pick.result = main
                            pick.gain = (main.score or 0) - (main.against or 0)
                            pick.at = main.level
                            pick.mainToo = true
                            mainList[#mainList + 1] = pick
                        end
                    end
                elseif ok then
                    -- Known to the client but its stats are not in yet.
                    waiting = waiting + 1
                end
            end
        end
    end

    local count, all = 0, {}
    local spot = Finder.Spot(player.zone)
    -- The slots in a list of their own, since the loop below changes `slots`
    -- and may be left and come back to between frames.
    local order = {}
    for slot in pairs(slots) do order[#order + 1] = slot end
    for _, slot in ipairs(order) do
        local list = slots[slot]
        -- Sorting every slot in one go was the scan's longest frame.
        if pause then pause() end
        -- Best first, by Finder.Order.
        for _, pick in ipairs(list) do
            pick.near = Finder.Nearness(pick.sources, player.zone, spot)
            pick.shown, pick.shownFor = Finder.Shown(pick.result) or false, pick.result
        end
        table.sort(list, Finder.Order)
        local copy = {}
        for i, pick in ipairs(list) do copy[i] = pick end
        all[slot] = copy
        for i = #list, PER_SLOT + 1, -1 do list[i] = nil end
        -- A one-hander shown under both hands is one upgrade to go and get.
        for _, pick in ipairs(list) do
            if not pick.mainToo then count = count + 1 end
        end
        slots[slot] = list
    end

    local skipped = ns.UpgradeQuest and ns.UpgradeQuest.Skipped and ns.UpgradeQuest:Skipped() or nil
    local found = {
        slots = slots, all = all, count = count, checked = checked, waiting = waiting, player = player,
        reach = reach,
    }
    found.pairs, found.backup = self:MakePairs(pairNotes, plan, only, skipped)
    -- An Off Spec scan (Logic/OffSpec.lua) is kept apart: the shared scan
    -- the upgrade quest and the small panel read stays the Main Spec's.
    if not only and reach == level and not self.offPass then
        self.latest, self.latestAt, self.latestKey = found, self.Now(), judgedKey
        self.latestAnswers = answersAt
        -- A whole scan with nothing changed meanwhile is up to date, whoever
        -- made it, so the upgrade quest and the character sheet read this
        -- one and start no second scan of their own.
        if (self.changes or 0) == changes then self.stale = false end
        -- The slots that waited for a look have had it, unless one changed
        -- again while the scan ran.
        for slot, was in pairs(looking) do
            if ((self.slotLooks or {})[slot] or 0) == was then self.toLook[slot] = nil end
        end
    end
    -- What this scan left unasked. Set only by a scan that finished, so one
    -- dropped half way keeps the list the last whole scan made.
    if not self.offPass then self.queue = queue end
    -- Something is due from the server. If none of it comes, the next step
    -- is taken anyway, so a batch the server drops is not waited on for ever.
    if asked > 0 or held > 0 then self:WaitForAnswers() end
    return found
end

--- The whole percent an upgrade shows ("+12%"), or nil for one that shows
--- no percent (an empty slot).
function Finder.Shown(result)
    local percent = type(result) == "table" and tonumber(result.percent)
    return percent and math.floor(percent + 0.5) or nil
end

--- Where the character stands on the map of `zone`: { x, y } from 0 to 1,
--- or nil when the client does not say, or the map it gives is not that
--- zone's (a city or a cave inside it). Never guessed.
function Finder.Spot(zone)
    if not zone or not (ns.QuestArrow and ns.Waypoints) then return nil end
    local ok, spot = pcall(function()
        local here = ns.QuestArrow:Here()
        if here and here.x and here.y and here.map == ns.Waypoints:MapFor(zone) then
            return { x = here.x, y = here.y }
        end
    end)
    return ok and spot or nil
end

--- How near the nearest of some sources is, smaller nearer: the squared
--- map distance (0 to 2) for one in `zone` with a spot when `spot` is
--- known, 2.5 for one in the zone without, 3 for one elsewhere.
function Finder.Nearness(sources, zone, spot)
    local best = 3
    if not zone then return best end
    local zoneOf = ns.UpgradeQuest and ns.UpgradeQuest.SourceZone
    for _, source in ipairs(sources or {}) do
        local where = zoneOf and zoneOf(source) or source.zone
        if where == zone or source.dungeon == zone then
            local near = 2.5
            local x, y = tonumber(source.x), tonumber(source.y)
            if spot and x and y and where == zone then
                near = (x / 100 - spot.x) ^ 2 + (y / 100 - spot.y) ^ 2
            end
            if near < best then best = near end
        end
    end
    return best
end

--- Seconds, for how old a kept scan is.
function Finder.Now()
    local now = _G.GetTime and Read(_G.GetTime)
    return tonumber(now) or os.time()
end

--- The latest scan of everything for now, made again (in the background,
--- once there is one) only when something it reads changed since: the gear
--- worn, the level, a setting. For the character sheet's slots, which ask
--- on every hover. No clock makes it old.
function Finder:Latest()
    if self.background then return self.latest end
    -- Kept until something it reads changes (an event marks it stale, the
    -- key catches one whose event was missed).
    local fresh = self.latest and not self.stale and self.latestKey == self:JudgeKey()
    if not fresh and (not self.latest or (self.Now() - (self.latestAt or 0)) >= 2) then
        -- Made a slice per frame, the last one kept on show meanwhile. The
        -- very first is too: done in one go, a hover froze the game.
        self:ScanInBackground()
    end
    return self.latest
end

--- Was this item asked about by a scan? (GET_ITEM_INFO_RECEIVED's item.)
function Finder:Asked(itemID)
    local ok, id = pcall(function() return tonumber(itemID) end)
    return ok and id ~= nil and self.asked ~= nil and self.asked[id] == true
end

--- Something the scan reads changed (gear worn, level, a setting). The
--- next scan may look once more when the items it asked about come in.
function Finder:MarkStale()
    self.stale = true
    self.followUp = true
    self.changes = (self.changes or 0) + 1
end

-- How long after the last answer the server sent about items a scan asked
-- for before it counts as settled. The answers come in bursts of dozens.
local ANSWER_SETTLE = 2
Finder.ANSWER_SETTLE = ANSWER_SETTLE

Finder.ANSWER_WAIT = ANSWER_WAIT

--- What wants to hear once a burst of item answers has settled, each
--- called with two arguments: true when the scan may be made again (the
--- upgrade quest looks only then), and true when nothing more was asked for
--- just now, so every answer the last scan waited on is in (the open finder
--- window scans again only on one of the two).
Finder.answerWatchers = Finder.answerWatchers or {}

function Finder:WatchAnswers(fn)
    if type(fn) == "function" then self.answerWatchers[#self.answerWatchers + 1] = fn end
end

--- The burst of answers is over. Only the first burst after a real change
--- makes the scan out of date; the scan after that asks about more items,
--- and their answers must not start another, or it never stops (a full
--- scan every few seconds until every item in the data has loaded).
function Finder:AnswersSettled()
    local again = self.followUp == true
    self.followUp = false
    if again then
        self.stale = true
        self.changes = (self.changes or 0) + 1
    end
    -- The items the last scan had no room to ask about are asked for here,
    -- a batch at a time, with no scan in between: scanning the whole list
    -- for every batch froze the game every few seconds until all were in.
    local done = true
    if not again and self:KeepsAsking() then
        done = self:AskMore() == 0
        -- Every batch is in, and some came after the last scan began, so
        -- that scan lacks them: the page showing looks once more. My Gear
        -- read the old scan and showed fewer upgrades until Judge Gear As
        -- made a new one (a player's report on 1.18.0). The scan that
        -- follows asks for nothing new, so this stops there.
        if done and self.latest and (self.answers or 0) > (self.latestAnswers or 0) then
            self.stale = true
            self.changes = (self.changes or 0) + 1
        end
    end
    for _, fn in ipairs(self.answerWatchers) do
        local ok, err = pcall(fn, again, done)
        if not ok then ns.Debug("finder:", tostring(err)) end
    end
    return again, done
end

--- Should the items a scan left unasked be asked for as answers come in?
--- Only while something that shows them is up (the finder window says).
function Finder:KeepsAsking()
    local fn = self.keepAsking
    if type(fn) ~= "function" then return false end
    local ok, yes = pcall(fn)
    return ok and yes and true or false
end

--- Ask the server about the next batch the last scan left unasked.
--- @return how many answers are now due (asked here, or a moment ago)
function Finder:AskMore()
    local queue = self.queue
    local asked, held = 0, 0
    -- First what was asked before and never answered: the server drops some
    -- of a burst. Asked again here, with no scan in between, until each has
    -- had its tries. One asked a moment ago is left to wait.
    for itemID in pairs(self.pending or {}) do
        if self:GaveUp(itemID) then
            -- Left as it is: should its answer come late, it still counts.
        elseif self:IsCached(itemID) then
            -- The client has it now, though its answer was never heard.
            self.pending[itemID] = nil
        elseif self:Awaited(itemID) then
            held = held + 1
        elseif asked < ASK_PER_SCAN and self:Request(itemID) then
            asked = asked + 1
        end
    end
    while queue and #queue > 0 and asked < ASK_PER_SCAN do
        local itemID = table.remove(queue)
        if not self:IsCached(itemID) and self:Request(itemID) then
            asked = asked + 1
        end
    end
    if asked > 0 or held > 0 then self:WaitForAnswers() end
    return asked + held
end

--- A batch was asked for. Should not one answer come within ANSWER_WAIT
--- seconds, go on as if they had settled, so the rest are still asked for.
function Finder:WaitForAnswers()
    local after = _G.C_Timer and _G.C_Timer.After
    if type(after) ~= "function" then return end
    local mine = self.answers or 0
    self.waits = (self.waits or 0) + 1
    local wait = self.waits
    after(ANSWER_WAIT, function()
        if Finder.waits == wait and (Finder.answers or 0) == mine then
            Finder:AnswersSettled()
        end
    end)
end

--- GET_ITEM_INFO_RECEIVED: an answer about an item a scan asked for waits
--- until no more have come for ANSWER_SETTLE seconds. Without timers it
--- counts at once.
function Finder:OnItemAnswer(itemID)
    -- One answer for each time we asked. An item asked about once is loaded
    -- again and again by the client (a tooltip, a link, our own list), and
    -- each of those used to start another scan with the window open.
    local ok, id = pcall(function() return tonumber(itemID) end)
    local pending = self.pending
    if not (ok and id and pending and pending[id]) then return false end
    pending[id] = nil
    -- Each answer starts its own wait; only the wait of the last answer in
    -- a burst finds the count unchanged and settles.
    self.answers = (self.answers or 0) + 1
    local mine = self.answers
    local after = _G.C_Timer and _G.C_Timer.After
    if type(after) ~= "function" then
        self:AnswersSettled()
        return true
    end
    after(ANSWER_SETTLE, function()
        if Finder.answers == mine then Finder:AnswersSettled() end
    end)
    return true
end

--- The gear the finder could list that is in the bags, as one string:
--- only that changes a scan (Carried leaves it out). Sorted by item ID, so
--- moving a piece or a stack growing says nothing changed.
function Finder:CarriedSignature()
    local items = ns.Sources and ns.Sources.ITEMS or {}
    local forever = ns.Sources and ns.Sources.FOREVER or {}
    local crafts = ns.Crafts and ns.Crafts.ITEMS or {}
    local seen, ids = {}, {}
    for id in pairs(self:Carried()) do
        if not seen[id] and (items[id] or forever[id] or crafts[id]) then
            seen[id] = true
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    return table.concat(ids, ",")
end

--- Did the gear the finder could list in the bags change since `who` last
--- asked? True the first time each asks.
function Finder:CarriedMoved(who)
    local ok, now = pcall(self.CarriedSignature, self)
    if not ok then return true end
    self.carriedSeen = self.carriedSeen or {}
    local key = who or "finder"
    if self.carriedSeen[key] == now then return false end
    self.carriedSeen[key] = now
    return true
end

--- BAG_UPDATE_DELAYED: a scan is out of date only when gear it could list
--- came into or left the bags. Loot, crafting and stacks leave it alone.
function Finder:OnBags()
    if self:CarriedMoved("finder") then self:MarkStale() end
end

--------------------------------------------------------------------------------
-- Scanning in the background
--
-- A full scan after the gear or level changes judges hundreds of items. Done
-- in one go it freezes the game for a moment, so the upgrade quest has it
-- done a slice per frame instead, and is told when it is finished.
--------------------------------------------------------------------------------

--- The latest full scan, if nothing has changed since it was started.
function Finder:Fresh()
    -- While a scan runs, the last one is out of date. The key catches a
    -- change whose event was missed.
    if self.background or self.stale or not self.latest then return nil end
    if self.latestKey == self:JudgeKey() then return self.latest end
    return nil
end

--- Is a background scan under way?
function Finder:Scanning()
    return self.background ~= nil
end

--- Run `build(pause)` a slice per frame on the frame worker
--- (Core/Worker.lua) and hand what it returns to `finish(found, why)`.
--- With `calm` the scan rests while the character fights and goes on when
--- the fight ends. The shared scan is calm (rework step 4): it judges every
--- item, and the small panel says "Your next upgrade comes after the
--- fight." meanwhile. A window's own scan still runs, since the player
--- opened that window and waits on it.
local function Sliced(build, finish, calm)
    ns.Worker:Run(build, finish, calm)
end

--- How many scans are under way (for the tests).
function Finder.SlicedNow()
    return ns.Worker.Count()
end

--- Make a full scan for now, a slice per frame, then call each of the
--- waiting `done` functions with it (or with nil and why). A scan already
--- under way takes the new caller too. Without timers it runs at once.
function Finder:ScanInBackground(done)
    if self.background then
        if done then self.background.waiting[#self.background.waiting + 1] = done end
        return
    end
    local job = { waiting = { done } }
    self.background = job
    -- Whatever changes from here on makes this scan stale.
    self.stale = false

    Sliced(function(pause) return Finder:Build(nil, nil, pause) end, function(found, why)
        Finder.background = nil
        for _, fn in ipairs(job.waiting) do
            local ok, err = pcall(fn, found, why)
            if not ok then ns.Debug("finder:", tostring(err)) end
        end
    end, true)
end

--- The finder window's own scan (its filter and how far ahead it looks), a
--- slice per frame, for a refresh after an event: a bag change or an item
--- answer no longer freezes the game while the window is open. Only the
--- latest one asked for calls `done`; one it replaces is left to finish
--- quietly. Kept apart from ScanInBackground, whose scan the upgrade
--- quest and the character sheet share.
function Finder:ScanSliced(only, ahead, done)
    local job = {}
    self.sliced = job
    Sliced(function(pause) return Finder:Build(only, ahead, pause) end, function(found, why)
        if Finder.sliced ~= job then return end
        Finder.sliced = nil
        if done then
            local ok, err = pcall(done, found, why)
            if not ok then ns.Debug("finder:", tostring(err)) end
        end
    end)
end

--------------------------------------------------------------------------------
-- The Off Spec's scans (Logic/OffSpec.lua, 2026-11-25)
--
-- The same scan, judged for the Off Spec against the best pieces owned for
-- it. Its verdicts are kept apart from the Main Spec's: the fields below
-- are swapped in while the Off Spec is entered. Its scans are kept by how
-- far ahead they look, until the gear, bags, level, weights or the pick
-- change. Nothing runs with Off Spec on None.
--------------------------------------------------------------------------------

local OFF_STATE = { "judged", "verdictKey", "judgedKey", "toLook", "slotLooks", "wornSeen",
    "wornLinks", "hitLooks", "setLooks", "wornKey", "wornBest" }

--- Swap the kept verdicts and what they lean on with the Off Spec's set
--- (`entering` true) or back (false). Called by OffSpec:Enter and Leave.
function Finder:SwapJudging(entering)
    if (self.offPass == true) == (entering == true) then return end
    local other = self.offState or {}
    local mine = {}
    for _, key in ipairs(OFF_STATE) do
        mine[key] = self[key]
        self[key] = other[key]
    end
    self.offState = mine
    self.offPass = entering == true or nil
end

--- What an Off Spec scan `ahead` levels on is made from, or nil with None.
function Finder:OffKey(ahead)
    local OffSpec = ns.OffSpec
    local spec = OffSpec and OffSpec:Key()
    if not spec then return nil end
    local judgeKey = OffSpec:Run(function() return Finder:JudgeKey() end)
    return table.concat({ spec, tostring(ahead or 0), tostring(judgeKey), tostring(self.changes or 0) }, "|")
end

--- The Off Spec scan kept for `ahead` (0 for now), while nothing it was
--- made from has changed; else nil.
function Finder:OffFound(ahead)
    ahead = ahead or 0
    local kept = self.offKept and self.offKept[ahead]
    if not kept then return nil end
    local key = self:OffKey(ahead)
    if key and kept.key == key then return kept.found end
    return nil
end

--- The last Off Spec scan for now, fresh or not (for drawing meanwhile).
function Finder:OffLatest()
    local kept = self.offKept and self.offKept[0]
    return kept and kept.found or nil
end

--- Make an Off Spec scan, a slice per frame on the worker, and hand it to
--- `done(found, why)`. A fresh kept one is handed over at once, and one
--- under way for the same key takes the new caller too. With None,
--- done(nil, "none").
function Finder:ScanOff(ahead, done)
    ahead = ahead or 0
    local OffSpec = ns.OffSpec
    local spec = OffSpec and OffSpec:Key()
    local key = spec and self:OffKey(ahead)
    if not key then
        if done then pcall(done, nil, "none") end
        return
    end
    local kept = self:OffFound(ahead)
    if kept then
        if done then pcall(done, kept) end
        return
    end
    self.offJobs = self.offJobs or {}
    local job = self.offJobs[ahead]
    if job and job.key == key then
        if done then job.waiting[#job.waiting + 1] = done end
        return
    end
    job = { key = key, waiting = { done } }
    self.offJobs[ahead] = job
    Sliced(function(pause) return OffSpec:Build(spec, ahead, pause) end, function(found, why)
        if Finder.offJobs[ahead] == job then Finder.offJobs[ahead] = nil end
        if found then
            Finder.offKept = Finder.offKept or {}
            Finder.offKept[ahead] = { key = key, found = found }
        end
        for _, fn in ipairs(job.waiting) do
            local ok, err = pcall(fn, found, why)
            if not ok then ns.Debug("finder:", tostring(err)) end
        end
    end, ahead == 0)
end

--- Is an Off Spec scan under way?
function Finder:ScanningOff()
    return self.offJobs ~= nil and next(self.offJobs) ~= nil
end

function Finder:OnEnable()
    for _, event in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP", "TRAIT_CONFIG_UPDATED" }) do
        ns.RegisterEvent(self, event, self.MarkStale)
    end
    ns.RegisterEvent(self, "BAG_UPDATE_DELAYED", self.OnBags)
    -- Only answers a scan asked for: the client loads items for chat links
    -- and the auction house all the time. Counted once the burst settles.
    ns.RegisterEvent(self, "GET_ITEM_INFO_RECEIVED", function(_, _, itemID)
        Finder:OnItemAnswer(itemID)
    end)
    ns.RegisterEvent(self, "QUEST_TURNED_IN", self.OnQuestTurnedIn)
    ns.RegisterEvent(self, "TRAIT_CONFIG_UPDATED", self.ForgetVerdicts)
    -- Passed on only when a skill is learned or dropped (ns.NothingChanged),
    -- never for a skill point.
    ns.RegisterEvent(self, "SKILL_LINES_CHANGED", self.ForgetVerdicts)
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

--- The character's money in copper, or nil when it can't be read.
function Finder.MoneyHeld()
    local ok, copper = pcall(function()
        local money = _G.GetMoney and _G.GetMoney()
        local n = tonumber(money)
        if n and n == n then return n + 0 end
    end)
    return ok and copper or nil
end

--- How much more copper the character needs to buy at `price`, or nil when
--- they can afford it or either side is unknown.
function Finder.Short(price)
    price = tonumber(price)
    if not price or price <= 0 then return nil end
    local held = Finder.MoneyHeld()
    if not held or held >= price then return nil end
    return price - held
end

-- What a quest needs besides the player, in words.
local NEED_WORDS = {
    group = L["group"], dungeon = L["dungeon"], raid = L["raid"], battleground = L["battleground"],
}

--- A zone or dungeon in the client's language, for showing only.
function Finder.ShownZone(zone)
    local waypoints = ns.Waypoints
    if not (type(zone) == "string" and waypoints and waypoints.ShowZone) then return zone end
    local ok, shown = pcall(waypoints.ShowZone, zone)
    return ok and type(shown) == "string" and shown or zone
end

--- A quest's title as the game gives it in the client's language, else the
--- data's, for showing only.
function Finder.ShownTitle(questID, title)
    local quests = ns.DungeonQuests
    if not (questID and type(title) == "string" and quests and quests.TitleOf) then return title end
    local ok, shown = pcall(quests.TitleOf, quests, { questID = questID, title = title })
    return ok and type(shown) == "string" and shown ~= "" and shown or title
end

local function Place(source, plain)
    if not source.zone then return nil end
    local zone = plain and source.zone or Finder.ShownZone(source.zone)
    if source.x and source.y then
        return ("%s (%s, %s)"):format(zone, source.x, source.y)
    end
    return zone
end

--- The item a quest starts from, by its ID, when the source names one.
function Finder.StartsItem(source)
    if type(source) ~= "table" or source.kind ~= "quest" or source.x then return nil end
    local starts = ns.Sources.STARTS
    local row = type(starts) == "table" and source.questID and starts[source.questID]
    return type(row) == "table" and row[1] or nil
end

--- The items a source's words name, as { { id, name } }, so text kept plain
--- can show them in their rarity colour when drawn.
function Finder.NamedItems(source)
    if type(source) ~= "table" then return nil end
    if source.kind == "quest" and not source.x and type(source.name) == "string" then
        return { { Finder.StartsItem(source), source.name } }
    end
    local learn = source.kind == "craft" and (source.state == "learn" or source.state == "skill")
        and source.learn
    if type(learn) == "table" and type(learn.recipe) == "string"
        and (learn.how == "recipe" or learn.how == "drop") then
        return { { learn.recipeID, learn.recipe } }
    end
    return nil
end

--- One source in words, without its kind: what the window shows after the
--- coloured "Vendor", "Quest" or "Dungeon" tag. `plain` leaves item names
--- uncoloured, for text that is saved.
function Finder:Describe(source, plain)
    if source.kind == "auction" then return self.Money(source.price) or "" end
    if source.kind == "vendor" then
        local text = source.name
        local where = Place(source, plain)
        if where then text = text .. ", " .. where end
        local price = self.Money(source.price)
        if price then text = text .. "  " .. price end
        local short = self.Money(self.Short(source.price))
        if short then
            text = L.Format("%s  |c%sneed|r %s |c%smore|r", text, ns.COLORS.downgrade, short, ns.COLORS.downgrade)
        end
        if source.limited then text = L.Format("%s  (limited stock)", text) end
        return text
    elseif source.kind == "quest" then
        local title = plain and source.title or Finder.ShownTitle(source.questID, source.title)
        local text = L.Format("%s (level %d)", title, source.questLevel or 0)
        local need = Finder.Need(source.group)
        if need then text = text .. ", " .. (NEED_WORDS[need] or need) end
        if (source.chain or 0) > 1 then
            text = L.Format("%s, after %d earlier quests", text, source.chain)
        elseif (source.chain or 0) == 1 and source.first then
            text = L.Format("%s, after %s", text, source.first)
        end
        local where = Place(source, plain)
        if source.x then
            if where then
                text = L.Format("%s, from %s in %s", text, source.name, where)
            else
                text = L.Format("%s, from %s", text, source.name)
            end
        else
            -- The item that starts it, in its rarity colour (plain for text
            -- that is saved).
            local shown = plain and source.name or Items.ColorName(Finder.StartsItem(source), source.name)
            text = L.Format("%s, starts from %s", text, shown)
        end
        return text
    elseif source.kind == "dungeon" then
        local dungeon = plain and source.dungeon or Finder.ShownZone(source.dungeon)
        local text = L.Format("%s in %s", source.name, dungeon)
        if not source.raid then
            text = text .. (" (%d-%d)"):format(source.minLevel, source.maxLevel)
        end
        if source.chance then text = L.Format("%s, %s%% drop", text, tostring(source.chance)) end
        return text
    elseif source.kind == "craft" and ns.Crafting then
        return ns.Crafting:Describe(source, self.Money, plain)
    end
    return ""
end

Finder.LABELS = { vendor = L["Vendor"], quest = L["Quest"], dungeon = L["Dungeon"], craft = L["Crafted"],
    auction = L["Auction House"] }

--- The tag a source shows: "Vendor", "Quest", "Dungeon", "Raid" or
--- "Crafted".
function Finder.Label(source)
    if source.kind == "dungeon" and source.raid then return L["Raid"] end
    return Finder.LABELS[source.kind] or ""
end

--- What a reputation still asks for, in words: "Needs Honored with
--- Warsong Outriders (you are Friendly)".
function Finder.NeedsText(needs)
    if needs.have then
        return L.Format("Needs %s with %s (you are %s)", needs.standing, needs.faction, needs.have)
    end
    return L.Format("Needs %s with %s", needs.standing, needs.faction)
end

--------------------------------------------------------------------------------
-- /beq find
--------------------------------------------------------------------------------

--- A pick's random roll in words: "best roll of the Monkey, 4.5% of drops;
--- 38% of drops are an upgrade", or nil for gear without rolls.
function Finder.RollText(pick)
    local roll = pick and pick.roll
    if not (roll and ns.Rolls) then return nil end
    local name = ns.Rolls:Describe(roll.link)
    local text = name and L.Format("Best roll %s: %s of drops", name, ns.Rolls.Percent(roll.chance))
        or L.Format("Best roll: %s of drops", ns.Rolls.Percent(roll.chance))
    if roll.upgradeChance and roll.upgradeChance > roll.chance then
        text = L.Format("%s, and %s of drops are an upgrade", text, ns.Rolls.Percent(roll.upgradeChance))
    end
    return text
end

ns.RegisterCommand("find", L["where to get upgrades: vendors, quests, dungeons and crafting"], function()
    local Gear = ns.GearWindow
    if not Gear then return end
    if Gear:IsShown() and Gear.tab == "find" then Gear:Close() else Gear:Open("find") end
end)
