-- Blackthornes Equipment -- Logic/UpgradeQuest.lua
-- The upgrade quest: the character's best next upgrade, handed out like a
-- quest, with the steps to go and get it.
--
-- Off until the player turns it on (the "Upgrade quest" setting,
-- `upgradeQuest`, or /beq quest). Then it asks the upgrade finder for every
-- upgrade that can be worn now, picks the one most worth the trip (how much
-- better it is, and how easy it is to get), and keeps that one until it is
-- worn: no quest that changes under the player every time the bags do. Each
-- step (travel, find the vendor, pick up the quest, kill the boss, craft it,
-- put it on) ticks itself off as the game shows it done. Once the item is
-- worn the quest is complete, a banner says so, and the next one is picked.
--
-- One quest per kind of source, each on a tab of the panel: Vendor, Quest,
-- Dungeons and Raids, Crafted. The player flips between them freely; each
-- tab keeps its own upgrade until it is worn, and the panel shows the one
-- picked. The first time, the tab with the upgrade most worth the trip is
-- picked.
--
-- Kept per character, in BlackthornesEquipmentCharDB:
--   upgradeQuestTabs     { [tab] = quest } the quest on each tab, a quest
--                        being { itemID, link, slot, at, howMuch, source,
--                        here, followed }; `source` is the finder's source
--                        it was picked for, `here` set when it was picked
--                        while "This zone only" was ticked, `followed` when
--                        the player chose it in Where to get upgrades
--   upgradeQuestTab      the tab picked ("vendor", "quest", "dungeon",
--                        "craft")
--   upgradeQuest         a copy of the picked tab's quest, as versions
--                        before the tabs kept it; read once into the tabs
--   upgradeQuestSkipped  { [itemID] = true } upgrades the player skipped
--   upgradeQuestsDone    how many upgrade quests this character finished
-- And account wide, in BlackthornesEquipmentDB: `upgradeQuestZoneOnly`, the
-- quest panel's "This zone only" box (off: upgrades from anywhere).
-- Made the first time they are needed, and never renamed or cleared by an
-- update.

local _, ns = ...

local UpgradeQuest = ns.NewModule("UpgradeQuest")

-- Upgrades a level up offered that the player chose not to switch to, this
-- session: { [itemID] = true }.
UpgradeQuest.declined = {}

-- The tabs, in the panel's order: the finder's source kind each holds (a
-- raid is a dungeon), its name and its colour, as in the upgrade finder.
UpgradeQuest.TABS = {
    { key = "vendor", name = "Vendor", color = "accent" },
    { key = "quest", name = "Quest", color = "quest" },
    { key = "dungeon", name = "Dungeons and Raids", color = "dungeon" },
    { key = "craft", name = "Crafted", color = "craft" },
}
local TABS = UpgradeQuest.TABS
local IS_TAB = {}
for _, tab in ipairs(TABS) do IS_TAB[tab.key] = tab end

-- How each tab says it has nothing to chase.
local NONE = {
    vendor = "No upgrade a vendor sells right now.",
    quest = "No quest reward that is an upgrade right now.",
    dungeon = "No dungeon or raid drop that is an upgrade right now.",
    craft = "No crafted upgrade right now.",
}
UpgradeQuest.NONE = NONE

-- Where each tab stands: "active", "waiting" or "none". Not saved.
UpgradeQuest.states = {}

-- A tab with nothing to pick is only looked at again when something that can
-- open new gear happens (gear, level, talents, recipes, quests handed in, item
-- answers) or the player asks, so looting and quest log ticks stay cheap.
-- A bag change looks again at most once a minute (gear sold or thrown away
-- can be picked again). Not saved.
UpgradeQuest.rescan = true
local BAG_RESCAN = 60
local RESCAN_ON = {
    PLAYER_EQUIPMENT_CHANGED = true, PLAYER_LEVEL_UP = true, QUEST_TURNED_IN = true,
    GET_ITEM_INFO_RECEIVED = true, SKILL_LINES_CHANGED = true, NEW_RECIPE_LEARNED = true,
    TRAIT_CONFIG_UPDATED = true,
}

local Items = ns.Items

-- How long to wait for the server to answer about gear before picking
-- from what is known. Most answers arrive within a few seconds.
local WAIT_FOR_ITEMS = 12

-- How much each kind of source is worth the trip: buying beats a quest,
-- which beats a dungeon run that might not drop it.
local EASE = {
    vendor = 1.0,
    quest = 0.85,
    dungeon = 0.6,
    raid = 0.3,
    known = 1.0,
    alt = 0.9,
    learn = 0.75,
    skill = 0.45,
    other = 0.2,
}

-- Somewhere in the zone the character is standing in is worth this much more.
local HERE = 1.25

-- Each quest still to do before a quest reward opens makes it this much
-- more work: a reward at the end of four quests counts at half.
local PER_CHAIN_QUEST = 0.25

-- How many quests before the one with the reward are listed as steps of
-- their own; the rest are one step.
local CHAIN_SHOWN = 2

-- After a level up, how long to keep looking for gear the new level opened,
-- while the server answers about gear the client has not seen.
local LEVEL_LOOK = 20

-- How much more an upgrade the new level opened has to be worth than the
-- quest being followed before it is offered in its place.
local CLEARLY_BETTER = 1.5

-- The note on a quest step that needs more than the player.
local NEED_NOTES = {
    group = "Needs a group.",
    dungeon = "Done in a dungeon, so bring a group.",
    raid = "Needs a raid.",
    battleground = "Done in a battleground.",
}

local function Read(fn, ...)
    if type(fn) ~= "function" then return nil end
    local result = { pcall(fn, ...) }
    if not result[1] then return nil end
    return unpack(result, 2)
end

local function Now()
    local ok, value = pcall(function() return time() end)
    return ok and value or 0
end

--- A plain copy of a finder source, safe to save.
local function Copy(value, depth)
    if type(value) ~= "table" then return value end
    if (depth or 0) > 3 then return nil end
    local copy = {}
    for key, inner in pairs(value) do
        local kind = type(inner)
        if kind == "string" or kind == "number" or kind == "boolean" or kind == "table" then
            copy[key] = Copy(inner, (depth or 0) + 1)
        end
    end
    return copy
end

function UpgradeQuest:IsEnabled()
    return ns.db ~= nil and ns.db.upgradeQuest == true
end

local function Valid(quest)
    if type(quest) == "table" and tonumber(quest.itemID) then return quest end
    return nil
end

--- The tab a source belongs on, or nil.
function UpgradeQuest.TabOf(source)
    local kind = type(source) == "table" and source.kind
    return IS_TAB[kind] and kind or nil
end

--- Each tab's quest: { [tab] = quest }. A quest saved before there were
--- tabs goes on its own tab, picked.
function UpgradeQuest:Quests()
    local char = ns.charDB
    if not char then return {} end
    if type(char.upgradeQuestTabs) ~= "table" then
        char.upgradeQuestTabs = {}
        local old = Valid(char.upgradeQuest)
        local tab = old and self.TabOf(old.source)
        if tab then
            char.upgradeQuestTabs[tab] = old
            if not IS_TAB[char.upgradeQuestTab] then char.upgradeQuestTab = tab end
        end
    end
    return char.upgradeQuestTabs
end

--- The tab picked: "vendor" until one is.
function UpgradeQuest:Tab()
    local tab = ns.charDB and ns.charDB.upgradeQuestTab
    return IS_TAB[tab] and tab or "vendor"
end

--- The quest on the picked tab, or nil.
function UpgradeQuest:Current()
    return Valid(self:Quests()[self:Tab()])
end

--- The quest on a tab, or nil.
function UpgradeQuest:QuestOn(tab)
    return Valid(self:Quests()[tab])
end

--- Keep the copy older versions read in step with the picked tab.
function UpgradeQuest:Mirror()
    if ns.charDB then ns.charDB.upgradeQuest = self:Current() end
end

--- Show another tab; it gets its quest at once if it has none yet.
function UpgradeQuest:SelectTab(tab)
    if not (IS_TAB[tab] and ns.charDB) then return false end
    if tab == self:Tab() and ns.charDB.upgradeQuestTab then return true end
    ns.charDB.upgradeQuestTab = tab
    self.rescan = true
    self.offer = nil
    self.lastStep = nil
    self:Mirror()
    if self:IsEnabled() then self:Update() else self:Changed() end
    return true
end

function UpgradeQuest:Skipped()
    local char = ns.charDB
    if not char then return {} end
    if type(char.upgradeQuestSkipped) ~= "table" then char.upgradeQuestSkipped = {} end
    return char.upgradeQuestSkipped
end

function UpgradeQuest:DoneCount()
    return tonumber(ns.charDB and ns.charDB.upgradeQuestsDone) or 0
end

--------------------------------------------------------------------------------
-- Picking the next upgrade
--------------------------------------------------------------------------------

--- How easy a source is, 0 to 1 and a little over for one close by.
function UpgradeQuest.Ease(source, zone)
    local key = source.kind
    if source.kind == "dungeon" and source.raid then key = "raid" end
    if source.kind == "craft" then key = source.state or "other" end
    local ease = EASE[key] or 0.5
    -- A rare drop means many runs.
    if source.kind == "dungeon" and source.chance and source.chance < 10 then
        ease = ease * (0.5 + source.chance / 20)
    end
    -- A reward at the end of a chain is more work.
    if source.kind == "quest" and source.questID and ns.Finder then
        local chain, unknown = ns.Finder:Chain(source.questID)
        local count = #chain + (unknown and 1 or 0)
        ease = ease / (1 + PER_CHAIN_QUEST * count)
    end
    if zone and source.zone == zone then ease = ease * HERE end
    return ease
end

--- Is "This zone only" ticked on the quest panel? Saved account wide as
--- `upgradeQuestZoneOnly`, off unless ticked (the quest looks anywhere).
function UpgradeQuest:ZoneOnly()
    return ns.db ~= nil and ns.db.upgradeQuestZoneOnly == true
end

--- Is a source in the zone `here`? A dungeon counts from its entrance's
--- zone and from inside. Gear made from what you know has no place, so it
--- is in every zone, and so is anything when the zone is not known.
function UpgradeQuest.InZone(source, here)
    if not here or type(source) ~= "table" or not source.zone then return true end
    return source.zone == here or source.dungeon == here
end

--- The easiest of a pick's sources (only those for one tab, when `tab` is
--- given, and only those in the zone `here`, when it is), and how easy it is.
function UpgradeQuest.BestSource(sources, zone, tab, here)
    local best, bestEase
    for _, source in ipairs(sources or {}) do
        if (not tab or source.kind == tab) and UpgradeQuest.InZone(source, here) then
            local ease = UpgradeQuest.Ease(source, zone)
            if not best or ease > bestEase then best, bestEase = source, ease end
        end
    end
    return best, bestEase or 0
end

--- How much a pick is worth going after: how much better it is, times how
--- easy its source is.
local function Worth(result, gain, ease)
    -- Filling an empty slot counts as a big step up.
    if result and result.empty then gain = math.max(gain, 1) * 1.5 end
    return gain * ease
end

--- From a finder scan, the pick most worth going after: { pick, source },
--- or nil. Gear that waits on a reputation, that nobody on the account can
--- make, or that the player skipped is left out, and so is anything in
--- `except` ({ [itemID] = true }). With `tab`, only that tab's sources count;
--- with "This zone only" ticked, only those in the zone the character is in.
--- Gear tied to a reputation, even one already reached, comes last: it is
--- picked only when nothing else will do (the player can still follow one
--- from the finder by hand).
function UpgradeQuest:Choose(found, except, tab)
    if type(found) ~= "table" or type(found.slots) ~= "table" then return nil end
    local skipped = self:Skipped()
    local zone = found.player and found.player.zone
    -- Read now: the scan may be from before the last zone change.
    local here = self:ZoneOnly() and (self.Zone() or zone) or nil
    local everything = type(found.all) == "table" and found.all or nil
    -- Only a few of the best per slot are kept for the finder's window; the
    -- best in this zone is seldom among them, so look at them all.
    local slots = here and everything or found.slots
    local best, bestRep
    -- The slots whose short list holds reputation gear.
    local crowded = {}
    local function Look(slot, list, repToo)
        for _, pick in ipairs(list) do
            if pick.rep then crowded[slot] = true end
            if not pick.needs and not pick.remote and not pick.at and not skipped[pick.itemID]
                and not (except and except[pick.itemID]) and (repToo or not pick.rep) then
                local source, ease = self.BestSource(pick.sources, zone, tab, here)
                if source then
                    local worth = Worth(pick.result, pick.gain or 0, ease)
                    local held = best
                    if pick.rep then held = bestRep end
                    if not held or worth > held.worth
                        or (worth == held.worth and pick.itemID < held.pick.itemID) then
                        held = { pick = pick, source = source, worth = worth }
                        if pick.rep then bestRep = held else best = held end
                    end
                end
            end
        end
    end
    for slot, list in pairs(slots) do Look(slot, list, true) end
    -- Reputation gear among a slot's few best may have pushed the rest of
    -- that slot out of the short list, so those slots are looked at whole.
    if slots ~= everything and everything then
        for slot in pairs(crowded) do
            if type(everything[slot]) == "table" then Look(slot, everything[slot], false) end
        end
    end
    return best or bestRep
end

--- Make a pick the quest on its source's tab.
function UpgradeQuest:Start(pick, source)
    local char = ns.charDB
    local tab = self.TabOf(source)
    if not (char and pick and tab) then return nil end
    local quest = {
        itemID = pick.itemID,
        link = Items.PlainLink(pick.link) or ("item:%d"):format(pick.itemID),
        slot = pick.result and pick.result.slot,
        at = Now(),
        howMuch = pick.result and ns.Compare:HowMuch(pick.result) or nil,
        source = Copy(source),
        -- Picked while "This zone only" was ticked: let go when it is
        -- unticked, so the tab picks again from anywhere.
        here = self:ZoneOnly() or nil,
    }
    self:Quests()[tab] = quest
    self:Mirror()
    return quest
end

--- Can a pick from the upgrade finder be followed as an upgrade quest?
--- Gear that waits on a reputation, a level or another player's craft
--- cannot be yet.
-- @return the source to follow, or nil and why not
function UpgradeQuest.CanFollow(pick)
    if type(pick) ~= "table" or not tonumber(pick.itemID) then return nil, "nothing to follow" end
    if pick.needs then
        return nil, ("it needs %s with %s first"):format(tostring(pick.needs.standing),
            tostring(pick.needs.faction))
    end
    if pick.at then return nil, ("you can wear it from level %d"):format(pick.at) end
    local usable = {}
    for _, source in ipairs(pick.sources or {}) do
        if not (source.kind == "craft" and source.state == "other") then usable[#usable + 1] = source end
    end
    local source = UpgradeQuest.BestSource(usable, UpgradeQuest.Zone())
    if not (source and UpgradeQuest.TabOf(source)) then
        return nil, "only another player can make it"
    end
    return source
end

--- Follow a pick the player chose in the upgrade finder: it becomes the
--- quest on its source's tab, that tab is shown, and the upgrade quest is
--- turned on. The quest it replaces is not skipped, so it can come back.
-- @return the quest, or nil and why not
function UpgradeQuest:Follow(pick)
    if not (ns.db and ns.charDB) then return nil, "not loaded yet" end
    local source, why = self.CanFollow(pick)
    if not source then return nil, why end
    self:Skipped()[pick.itemID] = nil
    self.declined[pick.itemID] = nil
    local quest = self:Start(pick, source)
    if not quest then return nil, "nothing to follow" end
    -- Picked by hand: "This zone only" never lets it go.
    quest.followed = true
    ns.charDB.upgradeQuestTab = self.TabOf(source)
    -- Chosen by hand: no level-up offer to swap it straight away.
    self.offer = nil
    self.levelledAt = nil
    self.lastStep = nil
    self:Mirror()
    ns.db.upgradeQuest = true
    self:Update()
    if ns.QuestPanel and ns.QuestPanel.Unfold then pcall(ns.QuestPanel.Unfold, ns.QuestPanel) end
    return quest
end

--- Is an item the quest on one of the tabs?
function UpgradeQuest:IsFollowing(itemID)
    if not self:IsEnabled() then return false end
    for _, quest in pairs(self:Quests()) do
        if type(quest) == "table" and quest.itemID == itemID then return true end
    end
    return false
end

--- The finder's latest full scan, when nothing has changed since. If there
--- is none, one is started in the background (a slice per frame, so the
--- game never stops for it) and the quest looks again when it is done.
-- @return the scan, or nil and "waiting" (scanning) or "none"
function UpgradeQuest:FreshScan()
    local finder = ns.Finder
    if not finder then return nil, "none" end
    local found = finder:Fresh()
    if found then return found end
    if not finder:Scanning() then
        finder:ScanInBackground(function(result)
            UpgradeQuest.scanFailed = not result
            -- Something changed while it ran. After a few in a row (item
            -- answers still pouring in), the last one is good enough.
            UpgradeQuest.staleScans = finder:Fresh() and 0 or (UpgradeQuest.staleScans or 0) + 1
            -- Finished at once (no timers): the caller picks it up below.
            if not UpgradeQuest.updating then UpgradeQuest:UpdateSoon(0) end
        end)
    end
    found = finder:Fresh()
    if found then return found end
    if not finder:Scanning() and (self.staleScans or 0) >= 3 and finder.latest then
        self.staleScans = 0
        return finder.latest
    end
    if not finder:Scanning() and self.scanFailed then return nil, "none" end
    return nil, "waiting"
end

--- A finder scan to pick from. Waits a little for the server to answer
--- about gear the client has not seen, so the pick is made from all of it.
-- @return the scan, or nil and "waiting" or "none"
function UpgradeQuest:Look()
    local found, why = self:FreshScan()
    if why == "waiting" then return nil, "waiting" end
    if not found then
        self.lookingSince = nil
        return nil, "none"
    end
    self.lookingSince = self.lookingSince or ns.Finder.Now()
    if found.waiting > 0 and ns.Finder.Now() - self.lookingSince < WAIT_FOR_ITEMS then
        return nil, "waiting"
    end
    self.lookingSince = nil
    return found
end

--- Whether the empty tabs need a fresh scan: not when each already found
--- nothing and nothing since could have opened new gear.
function UpgradeQuest:WorthLooking(empty)
    if self.rescan or not IS_TAB[ns.charDB.upgradeQuestTab] then return true end
    for _, tab in ipairs(empty) do
        if self.states[tab] ~= "none" then return true end
    end
    return self.bagsChanged and Now() - (self.lookedAt or 0) >= BAG_RESCAN or false
end

--- Give every tab without a quest its best upgrade, and pick the tab the
--- first time: the one whose upgrade is most worth the trip.
function UpgradeQuest:PickEmpty()
    local quests = self:Quests()
    local empty = {}
    for _, tab in ipairs(TABS) do
        if not Valid(quests[tab.key]) then empty[#empty + 1] = tab.key end
    end
    if #empty == 0 and IS_TAB[ns.charDB.upgradeQuestTab] then return end
    -- "This zone only" on a flight: the zone below is not where the player
    -- is going, so the tabs wait for the landing.
    if self:ZoneOnly() and self.OnTaxi() then return end
    if not self:WorthLooking(empty) then return end

    local found, why = self:Look()
    if not found then
        for _, tab in ipairs(empty) do self.states[tab] = why end
        return
    end
    self.rescan = false
    self.bagsChanged = false
    self.lookedAt = Now()
    for _, tab in ipairs(empty) do
        local best = self:Choose(found, nil, tab)
        if best then self:Start(best.pick, best.source) end
        self.states[tab] = best and "active" or "none"
    end
    if not IS_TAB[ns.charDB.upgradeQuestTab] then
        local best = self:Choose(found)
        ns.charDB.upgradeQuestTab = best and self.TabOf(best.source) or "vendor"
    end
end

--- The picked tab's next upgrade, when it has none.
-- @return the quest, or nil and "waiting" or "none"
function UpgradeQuest:PickNext()
    self:PickEmpty()
    local quest = self:Current()
    if quest then return quest end
    return nil, self.states[self:Tab()] or "none"
end

--------------------------------------------------------------------------------
-- What the game says is done
--------------------------------------------------------------------------------

local function Plain(value)
    local ok, copy = pcall(function()
        if type(value) == "string" and value ~= "" then return value .. "" end
    end)
    return ok and copy or nil
end

--- The zone the character is in: the instance's name inside a dungeon.
function UpgradeQuest.Zone()
    return Plain(Read(_G.GetRealZoneText))
end

--- How many of an item the bags hold.
function UpgradeQuest.Count(itemID)
    local count = tonumber((Items.Call({ "C_Item.GetItemCount", "GetItemCount" }, itemID)))
    if count then return count end
    count = 0
    for bag = 0, 4 do
        for slot = 1, Items:BagSize(bag) do
            local link = Items:InBag(bag, slot)
            if link and tonumber(link:match("item:(%d+)")) == itemID then count = count + 1 end
        end
    end
    return count
end

--- Is the item worn?
function UpgradeQuest.Worn(itemID)
    for slot = 1, 19 do
        local link = Items:Equipped(slot)
        if link and tonumber(link:match("item:(%d+)")) == itemID then return true end
    end
    return false
end

--- Is a quest in the quest log? Nil when the client cannot say.
local function OnQuest(questID)
    local log = _G.C_QuestLog
    local on = Read(log and log.IsOnQuest, questID)
    if on ~= nil then return on == true end
    local index = Read(log and log.GetLogIndexForQuestID, questID)
    if index ~= nil then return (tonumber(index) or 0) > 0 end
    return nil
end

--- Are a quest's objectives done, ready to hand in?
local function QuestReady(questID)
    local log = _G.C_QuestLog
    if Read(log and log.ReadyForTurnIn, questID) == true then return true end
    return Read(log and log.IsComplete, questID) == true
end


--------------------------------------------------------------------------------
-- The steps
--------------------------------------------------------------------------------

local function At(place)
    if place.x and place.y then return (" (%s, %s)"):format(place.x, place.y) end
    return ""
end

local function Who(names)
    if type(names) ~= "table" or #names == 0 then return "An alt" end
    if #names == 1 then return names[1] end
    return names[1] .. " or " .. names[2]
end

--- The steps to get the quest's upgrade, worked out from where it comes
--- from and what the game shows. A list of { text, done, place, note },
--- every step before the furthest one done counted as done too.
-- @return steps, and the index of the step to do now
function UpgradeQuest:Steps(quest)
    quest = quest or self:Current()
    if not quest then return {}, 0 end
    local source = quest.source or {}
    local itemID = quest.itemID
    local link = quest.link
    local zone = self.Zone()
    local have = self.Count(itemID) > 0
    local worn = self.Worn(itemID)
    local money = ns.Finder and ns.Finder.Money or function() return nil end
    local steps = {}

    local function Add(text, done, place, note)
        steps[#steps + 1] = { text = text, done = done and true or false, place = place, note = note }
    end

    local function Travel(where)
        if where and where.zone then
            Add(("Travel to %s"):format(where.zone), zone == where.zone, { zone = where.zone, name = where.zone })
            -- Standing in the zone says nothing about the steps before it.
            steps[#steps].soft = true
        end
    end

    if source.kind == "vendor" then
        local place = { zone = source.zone, x = source.x, y = source.y, name = source.name }
        Travel(place)
        local text = ("Find %s%s"):format(source.name or "the vendor", At(place))
        Add(text, false, place)
        local price = money(source.price)
        Add(("Buy %s%s"):format(link, price and (" for " .. price) or ""), have, place,
            source.limited and "Limited stock: if it is sold out, wait for the vendor to restock." or nil)
    elseif source.kind == "quest" then
        local questID = source.questID
        local turnedIn = questID and ns.Finder and ns.Finder:QuestDone(questID)
        local onQuest = questID and OnQuest(questID)
        -- The quests before it in its chain, first one first. The first
        -- two are spelled out; the rest wait as one step, so a long chain
        -- does not bury the quest it leads to.
        local chain, unknown = {}, nil
        if questID and ns.Finder then chain, unknown = ns.Finder:Chain(questID) end
        local count = #chain + (unknown and 1 or 0)
        local lead = count > 1 and ("%d quests to do before %s."):format(count, source.title or "it") or nil
        if unknown then
            local after = chain[1] and chain[1].questID or questID
            Add(("Do %s"):format(unknown), OnQuest(after), nil,
                (lead and lead .. " " or "") .. "Skip this one if you have done it.")
            lead = nil
        end
        for index, before in ipairs(chain) do
            if index > CHAIN_SHOWN then
                local rest = #chain - CHAIN_SHOWN
                Add(("Then %d more quest%s in the chain, up to %s"):format(rest, rest == 1 and "" or "s",
                    chain[#chain].title or "it"), false, nil,
                    ("The quests come one after another; %s opens after them."):format(source.title or "the quest"))
                break
            end
            local spot = before.x and { zone = before.zone, x = before.x, y = before.y, name = before.name } or nil
            local text
            if OnQuest(before.questID) then
                text = ("Complete %s (level %d)"):format(before.title, before.questLevel or 0)
            elseif spot then
                text = ("Do %s: pick it up from %s in %s%s"):format(before.title, before.name or "?",
                    before.zone or "?", At(spot))
            else
                text = ("Do %s: it starts from %s"):format(before.title, before.name or "an item")
            end
            local note = lead
            lead = nil
            local need = NEED_NOTES[before.group]
            if need then note = (note and note .. " " or "") .. need end
            Add(text, false, spot, note)
        end
        local place = source.x and { zone = source.zone, x = source.x, y = source.y, name = source.name } or nil
        if place then Travel(place) end
        if place then
            Add(("Pick up %s from %s%s"):format(source.title or "the quest", source.name or "?", At(place)),
                onQuest, place)
        else
            Add(("Pick up %s: it starts from %s"):format(source.title or "the quest", source.name or "an item"),
                onQuest, nil)
        end
        local note = NEED_NOTES[source.group]
        Add(("Complete %s (level %d)"):format(source.title or "the quest", source.questLevel or 0),
            questID and QuestReady(questID), nil, note)
        -- Classic's data names who starts a quest, not always who takes it
        -- back, so the hand-in names nobody.
        Add(("Hand it in and choose %s"):format(link), have or turnedIn, nil)
    elseif source.kind == "dungeon" then
        local door = source.zone and { zone = source.zone, name = source.dungeon } or nil
        if door and door.zone ~= source.dungeon then Travel(door) end
        local group = source.raid and "Gather a raid" or "Gather a group"
        local range = (not source.raid and source.minLevel)
            and (" (levels %d to %d)"):format(source.minLevel, source.maxLevel or source.minLevel) or ""
        Add(("%s and enter %s%s"):format(group, source.dungeon or "the dungeon", range),
            zone == source.dungeon, door)
        local chance = source.chance and ("%s%% drop"):format(tostring(source.chance)) or nil
        local note = chance and ("It is a %s, so it can take a few runs."):format(chance) or nil
        if source.forever then note = (note and note .. " " or "") .. "Seen dropping on Forever." end
        Add(("Defeat %s and loot %s"):format(source.name or "the boss", link), have, nil, note)
    elseif source.kind == "craft" then
        local crafting = ns.Crafting
        local profession = source.profession or "the profession"
        local learn = source.learn
        local place = source.zone and { zone = source.zone, x = source.x, y = source.y, name = source.name } or nil
        local craft = ns.Crafts and ns.Crafts.ITEMS[itemID]
        local skill = craft and crafting and crafting:Professions()[craft[1]]
        local knows = craft and crafting and crafting:Knows(craft[3])

        if source.state == "alt" then
            Add(("Ask %s to make %s (%s) and mail it to you"):format(Who(source.who), link, profession),
                have, nil)
            Add("Collect it from a mailbox", have, nil)
        elseif source.state == "other" then
            Add(("Buy %s at the auction house, or ask a %s crafter"):format(link, profession), have, nil)
        else
            if source.state == "skill" then
                Add(("Raise %s to %d"):format(profession, source.skill or 0),
                    (skill or 0) >= (source.skill or 0), nil,
                    ("You have %d."):format(skill or source.have or 0))
            end
            if source.state == "skill" or source.state == "learn" then
                if place then Travel(place) end
                local how = crafting and learn and crafting:LearnText(learn, money)
                Add(how and ("Learn the recipe: %s"):format(how) or "Learn the recipe", knows == true, place)
            end
            local materials = crafting and crafting:MaterialsText(itemID) or ""
            if materials ~= "" then
                local all = true
                local list = craft and craft.m or {}
                for i = 1, #list, 2 do
                    if self.Count(list[i]) < list[i + 1] then all = false end
                end
                local cost = money(source.cost)
                Add(("Gather the materials: %s"):format(materials), all, nil,
                    cost and ("About %s%s to buy."):format(source.partial and "over " or "", cost) or nil)
            end
            Add(("Make %s (%s)"):format(link, profession), have, nil)
        end
    else
        Add(("Get %s"):format(link), have, nil)
    end

    Add(("Put on %s"):format(link), worn, nil, quest.howMuch and ("%s over what you wear now."):format(quest.howMuch) or nil)

    -- A later step done means the ones before it are too: the vendor was
    -- found once the item is bought, wherever the character is now.
    local furthest = 0
    for index, step in ipairs(steps) do
        if step.done and not step.soft then furthest = index end
    end
    local current = #steps
    for index, step in ipairs(steps) do
        if index < furthest then step.done = true end
    end
    for index, step in ipairs(steps) do
        if not step.done then
            current = index
            break
        end
    end
    return steps, current
end

--- The next step with a spot to put on the map, from the current one on.
function UpgradeQuest:NextPlace()
    local steps, current = self:Steps()
    for index = math.max(current, 1), #steps do
        local place = steps[index].place
        if place and place.zone then return place end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Keeping it up to date
--------------------------------------------------------------------------------

--- Tell whatever shows the quest to draw it again.
function UpgradeQuest:Changed()
    for _, name in ipairs({ "QuestPanel", "MapPins", "SettingsUI", "FinderUI", "QuestArrow" }) do
        local module = ns[name]
        if module and module.OnUpgradeQuestChanged then pcall(module.OnUpgradeQuestChanged, module) end
    end
end

--- Is the quest's item still an upgrade worth the trip? False when
--- something as good or better is worn now (found elsewhere, say).
function UpgradeQuest:StillWanted(quest)
    local ok, result = pcall(ns.Compare.Judge, ns.Compare, quest.link)
    if not ok or not result then return true end
    if result.verdict == "downgrade" or result.verdict == "same" then return false end
    return true
end

--- Was the quest that gives this upgrade handed in, with the upgrade
--- neither carried nor worn? Only after a few seconds of it missing, since
--- the reward can reach the bags a moment after the hand-in.
function UpgradeQuest:HandedInWithout(quest)
    local source = quest.source
    if not (source and source.kind == "quest" and source.questID and ns.Finder) then return false end
    if not ns.Finder:QuestDone(source.questID) or self.Count(quest.itemID) > 0 then
        self.missingSince = nil
        return false
    end
    local now = ns.Finder.Now()
    if not self.missingSince then
        self.missingSince = now
        self.recheck = true
        return false
    end
    return now - self.missingSince >= 5
end

--------------------------------------------------------------------------------
-- A level up that opens something better
--------------------------------------------------------------------------------

--- How much the quest being followed is worth now, judged like a pick.
function UpgradeQuest:QuestWorth(quest, zone)
    local ok, result = pcall(ns.Compare.Judge, ns.Compare, quest.link)
    if not (ok and result) then return nil end
    local gain = (result.score or 0) - (result.against or 0)
    return Worth(result, gain, self.Ease(quest.source or {}, zone))
end

--- After a level up: is there now an upgrade clearly more worth the trip
--- than the quest being followed? The quest is kept either way; a better
--- one is only offered, for the player to switch to or not.
function UpgradeQuest:LookForBetter(quest)
    local found, why = self:FreshScan()
    if why == "waiting" then return end
    if not found then
        self.levelledAt = nil
        return
    end
    local now = ns.Finder.Now()
    local looking = now - self.levelledAt < LEVEL_LOOK
    -- The scan was made before the client caught up with the new level.
    if looking and self.newLevel and found.player and (found.player.level or 0) < self.newLevel then
        ns.Finder:MarkStale()
        self.recheck = true
        return
    end
    if looking and found.waiting > 0 then
        self.recheck = true
    else
        self.levelledAt = nil
    end

    local except = { [quest.itemID] = true }
    for itemID in pairs(self.declined) do except[itemID] = true end
    local tab = self.TabOf(quest.source) or self:Tab()
    local best = self:Choose(found, except, tab)
    local worth = self:QuestWorth(quest, found.player and found.player.zone)
    if not (best and worth) or best.worth < worth * CLEARLY_BETTER then return end
    if self.offer and self.offer.pick.itemID == best.pick.itemID then return end

    self.offer = {
        pick = best.pick,
        source = best.source,
        questItemID = quest.itemID,
        level = (found.player and found.player.level) or self.newLevel,
        howMuch = best.pick.result and ns.Compare:HowMuch(best.pick.result) or nil,
    }
    if ns.Toast then
        ns.Toast:Show({ title = "New upgrade unlocked", link = best.pick.link,
            text = "Your new level opened a better upgrade. Switch to it on the quest panel." })
    end
end

--- The upgrade the last level up opened, while it is on offer, or nil:
--- { pick, source, level, howMuch }.
function UpgradeQuest:Offer()
    return self.offer
end

--- Follow the upgrade on offer instead of the quest being followed.
function UpgradeQuest:SwitchToOffer()
    local offer = self.offer
    if not offer then return false end
    self.offer = nil
    self:Start(offer.pick, offer.source)
    self.lastStep = nil
    self:Update()
    return true
end

--- Keep the quest being followed: the upgrade on offer is not offered
--- again this session.
function UpgradeQuest:KeepCurrent()
    local offer = self.offer
    if not offer then return false end
    self.declined[offer.pick.itemID] = true
    self.offer = nil
    self:Changed()
    return true
end

--- Look at the quest: finish it when the item is worn, drop it when it is
--- no longer an upgrade, and pick the next one when there is none.
function UpgradeQuest:Update()
    self.updating = true
    local ok, err = pcall(self.Check, self)
    self.updating = false
    if not ok then error(err, 0) end
    -- Still waiting on the server: look again shortly, in case no more
    -- answers come in to prompt it.
    if self.state == "waiting" or self.recheck then
        self.recheck = nil
        self:RetrySoon()
    end
end

function UpgradeQuest:RetrySoon()
    local after = _G.C_Timer and _G.C_Timer.After
    if self.retryPending or type(after) ~= "function" then return end
    self.retryPending = true
    local scheduling = true
    after(6, function()
        UpgradeQuest.retryPending = false
        -- Run at once, by a client without real timers: looking again now
        -- would only go round in circles.
        if scheduling then return end
        local ok, err = pcall(UpgradeQuest.Update, UpgradeQuest)
        if not ok then ns.Debug("upgrade quest:", tostring(err)) end
    end)
    scheduling = false
end

function UpgradeQuest:Check()
    if not self:IsEnabled() then
        self:Changed()
        return
    end

    local quests = self:Quests()
    local shownBefore = self:Current()
    local before = shownBefore and shownBefore.itemID
    local beforeTab = self:Tab()
    local firstPick = not IS_TAB[ns.charDB.upgradeQuestTab]
    local lastStep = self.lastStep
    local completed = {}

    for _, tab in ipairs(TABS) do
        local quest = Valid(quests[tab.key])
        local shown = tab.key == beforeTab
        if quest and self.Worn(quest.itemID) then
            quests[tab.key] = nil
            -- The same upgrade on two tabs is one quest done.
            if not completed[quest.itemID] then
                completed[quest.itemID] = true
                ns.charDB.upgradeQuestsDone = self:DoneCount() + 1
                if ns.Toast then
                    ns.Toast:Show({ title = "Upgrade quest complete", link = quest.link,
                        text = ("Upgrade quests done: %d. Picking your next one."):format(self:DoneCount()) })
                end
            end
            if ns.Finder then ns.Finder:MarkStale() end
        elseif quest and not self:StillWanted(quest) then
            -- Something as good or better was put on first (looted, bought,
            -- made): this one is beaten, carried or not. Only the tab on
            -- show says so; the others quietly pick again.
            quests[tab.key] = nil
            if shown then
                ns.Print(("dropped the upgrade quest for %s: you wear something as good now."):format(quest.link))
                if ns.Toast then
                    ns.Toast:Show({ title = "You already beat this one", link = quest.link,
                        text = "You wear something as good. Picking your next upgrade." })
                end
            end
            if ns.Finder then ns.Finder:MarkStale() end
        elseif quest and self:HandedInWithout(quest) then
            -- The quest was handed in and another reward taken: it cannot be
            -- done again, so this upgrade is out of reach.
            quests[tab.key] = nil
            self:Skipped()[quest.itemID] = true
            ns.Print(("dropped the upgrade quest for %s: that quest is already done."):format(quest.link))
        end
        if Valid(quests[tab.key]) then self.states[tab.key] = "active" end
    end

    self:PickEmpty()
    local quest = self:Current()
    self.state = quest and "active" or self.states[self:Tab()] or "none"
    if quest and quest.itemID ~= before and (firstPick or beforeTab == self:Tab()) then
        self.lastStep = nil
        if ns.Toast then
            ns.Toast:Show({ title = "New upgrade quest", link = quest.link,
                text = quest.howMuch and ("%s over what you wear now."):format(quest.howMuch)
                    or "Follow the steps on the quest panel." })
        end
    end

    -- An offer is only for the quest it was made against.
    if self.offer and not (quest and self.offer.questItemID == quest.itemID) then self.offer = nil end
    if quest and quest.itemID == before and self.levelledAt then
        self:LookForBetter(quest)
    elseif not (quest and quest.itemID == before) then
        -- A quest picked after the level up already counts the new level.
        self.levelledAt = nil
    end

    -- A step ticked off since last time: a little cheer.
    if quest and quest.itemID == before then
        local _, current = self:Steps(quest)
        if lastStep and current > lastStep then self.stepDone = current - 1 end
        self.lastStep = current
    elseif quest then
        local _, current = self:Steps(quest)
        self.lastStep = current
    end

    self:Mirror()
    self:Changed()
end

--- Update after a short pause, so a burst of bag events is one update.
function UpgradeQuest:UpdateSoon(delay)
    -- Never from inside an update: a client whose timers run at once would
    -- go round for ever while it waits on the server.
    if self.waiting or self.updating or not self:IsEnabled() then return end
    self.waiting = true
    local after = _G.C_Timer and _G.C_Timer.After
    if type(after) ~= "function" then
        self.waiting = false
        pcall(self.Update, self)
        return
    end
    after(delay or 0.5, function()
        UpgradeQuest.waiting = false
        local ok, err = pcall(UpgradeQuest.Update, UpgradeQuest)
        if not ok then ns.Debug("upgrade quest:", tostring(err)) end
    end)
end

--- Leave this upgrade and pick another for the tab.
function UpgradeQuest:Skip()
    local quest = self:Current()
    if not quest then return false end
    self:Skipped()[quest.itemID] = true
    self:Quests()[self:Tab()] = nil
    self.lastStep = nil
    self.rescan = true
    self:Update()
    return true
end

--- Turn the upgrade quest on or off.
function UpgradeQuest:SetEnabled(on)
    if not ns.db then return end
    ns.db.upgradeQuest = on and true or false
    if on then
        self.rescan = true
        self:Update()
    else
        self.state = nil
        self:Changed()
    end
end

--- A quest filter changed ("Solo quests only", or how far above the
--- character a quest may be). A tab following a quest the filters now
--- leave out lets it go (not skipped, so it can come back) and picks
--- again; either way the empty tabs look again.
function UpgradeQuest:OnQuestFilterChanged()
    local finder = ns.Finder
    if not finder then return end
    local player = finder:Player()
    local quests = self:Quests()
    for _, tab in ipairs(TABS) do
        local quest = Valid(quests[tab.key])
        local source = quest and quest.source
        if source and source.kind == "quest" then
            local allowed = finder:QuestAllowed(source, player and player.level)
            if allowed and finder:SoloOnly() and source.questID then
                for _, before in ipairs((finder:Chain(source.questID))) do
                    if finder.Need(before.group) then allowed = false end
                end
            end
            if not allowed then quests[tab.key] = nil end
        end
    end
    self:Mirror()
    self.rescan = true
    self.offer = nil
    self.lastStep = nil
    if self:IsEnabled() then self:Update() else self:Changed() end
end

--- Is the character only passing through: on a flight, or inside a
--- dungeon or raid? Then the zone it is in says nothing about where it
--- will look for gear, so "This zone only" lets go of nothing. Unreadable
--- counts as passing: keeping a quest a little longer does no harm.
function UpgradeQuest.Passing()
    local ok, passing = pcall(function()
        if type(_G.UnitOnTaxi) == "function" and _G.UnitOnTaxi("player") then return true end
        if type(_G.IsInInstance) == "function" and _G.IsInInstance() then return true end
        return false
    end)
    return not ok or passing == true
end

--- Is the character on a flight?
function UpgradeQuest.OnTaxi()
    local ok, flying = pcall(function()
        return type(_G.UnitOnTaxi) == "function" and _G.UnitOnTaxi("player") and true or false
    end)
    return ok and flying == true
end

--- Let go of the tabs' quests that are not in the zone the character is
--- in (not skipped: they come back in their own zone), while "This zone
--- only" is ticked. A quest followed from Where to get upgrades stays, and
--- nothing is let go on a flight or inside a dungeon (UpgradeQuest.Passing).
-- @return true when one was let go
function UpgradeQuest:LetGoOutOfZone()
    if not self:ZoneOnly() or self.Passing() then return false end
    local here = self.Zone()
    if not here then return false end
    local quests = self:Quests()
    local any = false
    for _, tab in ipairs(TABS) do
        local quest = Valid(quests[tab.key])
        if quest and not quest.followed and not self.InZone(quest.source, here) then
            quests[tab.key] = nil
            any = true
        end
    end
    return any
end

--- Tick or untick "This zone only". Ticked, the tabs' quests elsewhere are
--- let go and each tab picks again from the zone the character is in;
--- unticked, the quests it picked are let go and every tab picks again
--- from anywhere. A quest followed from Where to get upgrades stays.
function UpgradeQuest:SetZoneOnly(on)
    if not ns.db then return end
    ns.db.upgradeQuestZoneOnly = on and true or false
    if on then
        self:LetGoOutOfZone()
    else
        local quests = self:Quests()
        for _, tab in ipairs(TABS) do
            local quest = Valid(quests[tab.key])
            if quest and quest.here and not quest.followed then quests[tab.key] = nil end
        end
    end
    self:Mirror()
    self.rescan = true
    self.offer = nil
    self.lastStep = nil
    if self:IsEnabled() then self:Update() else self:Changed() end
end

--- Is an item answer from the server about gear the quest cares about: an
--- item a finder scan asked for, or one of the tabs' upgrades?
function UpgradeQuest:WantsItem(itemID)
    if ns.Finder and ns.Finder:Asked(itemID) then return true end
    local ok, id = pcall(function() return tonumber(itemID) end)
    if not (ok and id) then return false end
    for _, quest in pairs(self:Quests()) do
        if type(quest) == "table" and quest.itemID == id then return true end
    end
    return false
end

function UpgradeQuest:OnEvent(event, level)
    -- Control comes back after every stun and fear; it only matters at the
    -- end of a flight that crossed a zone.
    if event == "PLAYER_CONTROL_GAINED" then
        if not self.landing then return end
        self.landing = nil
        event = "ZONE_CHANGED_NEW_AREA"
    end
    -- The client loads items for chat links, vendors and other addons all
    -- the time; only answers this addon asked for are worth looking again.
    if event == "GET_ITEM_INFO_RECEIVED" and not self:WantsItem(level) then return end
    if event == "PLAYER_LEVEL_UP" then
        -- Look for gear the new level opened, for a little while.
        self.levelledAt = ns.Finder and ns.Finder.Now() or Now()
        local ok, value = pcall(function()
            local number = tonumber(level)
            if number and number > 0 and number < 1000 then return number end
        end)
        self.newLevel = ok and value or nil
    end
    if RESCAN_ON[event] then self.rescan = true end
    -- A new zone has its own upgrades while "This zone only" is ticked.
    -- On a flight, every zone flown over would pick (and announce) its own,
    -- so that waits for the landing.
    if event == "ZONE_CHANGED_NEW_AREA" and self:ZoneOnly() then
        if self.OnTaxi() then
            self.landing = true
            return
        end
        self:LetGoOutOfZone()
        self:Mirror()
        self.rescan = true
    end
    if event == "BAG_UPDATE_DELAYED" then self.bagsChanged = true end
    self:UpdateSoon()
end

function UpgradeQuest:OnEnable()
    for _, event in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP",
        "ZONE_CHANGED_NEW_AREA", "QUEST_ACCEPTED", "QUEST_LOG_UPDATE", "QUEST_TURNED_IN",
        "GET_ITEM_INFO_RECEIVED", "SKILL_LINES_CHANGED", "NEW_RECIPE_LEARNED", "TRAIT_CONFIG_UPDATED",
        "PLAYER_CONTROL_GAINED" }) do
        ns.RegisterEvent(self, event, self.OnEvent)
    end
    if self:IsEnabled() then self:UpdateSoon(3) end
end

--------------------------------------------------------------------------------
-- /beq quest
--------------------------------------------------------------------------------

-- The words that pick a tab.
local TAB_WORDS = {
    vendor = "vendor", vendors = "vendor",
    quest = "quest", quests = "quest", reward = "quest", rewards = "quest",
    dungeon = "dungeon", dungeons = "dungeon", raid = "dungeon", raids = "dungeon",
    craft = "craft", crafted = "craft", crafting = "craft",
}

ns.RegisterCommand("quest", "a quest for your next upgrade (/beq quest off, skip, switch, reset, size, or a tab: vendor, quest, dungeon, crafted)", function(rest)
    local word = (rest or ""):lower():match("^%s*(%a*)") or ""
    -- How big the panel is drawn: small, normal, large or a percent, as its
    -- gold corner grip and the Settings row do (UI/QuestPanel.lua).
    if word == "size" then
        local panel = ns.QuestPanel
        if not panel then return end
        local scale = panel.ParseSize((rest or ""):lower():match("^%s*size%s*(.-)%s*$"))
        if not scale then
            ns.Print(("the quest panel is at %s. /beq quest size small, normal, large or a percent from 50%% to 150%% changes it, or drag the gold corner below its bottom right."):format(
                panel.ScaleText(panel:GetScale())))
            return
        end
        panel:Build()
        ns.Print(("quest panel size: %s."):format(panel.ScaleText(panel:SetPanelScale(scale))))
        return
    end
    local tab = TAB_WORDS[word]
    if tab then
        if not UpgradeQuest:IsEnabled() then UpgradeQuest:SetEnabled(true) end
        UpgradeQuest:SelectTab(tab)
        ns.Print(("upgrade quest: showing the %s tab."):format(IS_TAB[tab].name))
        if ns.QuestPanel then ns.QuestPanel:Unfold() end
        return
    end
    if word == "off" then
        UpgradeQuest:SetEnabled(false)
        ns.Print("upgrade quest off. /beq quest turns it back on.")
        return
    end
    if word == "skip" then
        if UpgradeQuest:Skip() then
            ns.Print("skipped that upgrade.")
        else
            ns.Print("there is no upgrade quest to skip.")
        end
        return
    end
    if word == "switch" then
        if UpgradeQuest:SwitchToOffer() then
            ns.Print("switched to the upgrade your new level opened.")
        else
            ns.Print("no new upgrade is on offer.")
        end
        return
    end
    if word == "reset" then
        if ns.charDB then ns.charDB.upgradeQuestSkipped = {} end
        ns.Print("skipped upgrades can come up again.")
        UpgradeQuest.rescan = true
        UpgradeQuest:Update()
        return
    end
    if not UpgradeQuest:IsEnabled() then
        UpgradeQuest:SetEnabled(true)
        ns.Print("upgrade quest on. Follow the steps on the quest panel.")
    else
        UpgradeQuest.rescan = true
        UpgradeQuest:Update()
    end
    if ns.QuestPanel then ns.QuestPanel:Unfold() end
end)
