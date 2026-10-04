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
-- Kept per character, in BlackthornesEquipmentCharDB:
--   upgradeQuest         { itemID, link, slot, at, howMuch, source } the
--                        quest being followed; `source` is the finder's
--                        source it was picked for
--   upgradeQuestSkipped  { [itemID] = true } upgrades the player skipped
--   upgradeQuestsDone    how many upgrade quests this character finished
-- Made the first time they are needed, and never renamed or cleared by an
-- update.

local _, ns = ...

local UpgradeQuest = ns.NewModule("UpgradeQuest")

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

--- The quest being followed, or nil.
function UpgradeQuest:Current()
    local char = ns.charDB
    local quest = char and char.upgradeQuest
    if type(quest) == "table" and tonumber(quest.itemID) then return quest end
    return nil
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

--- The easiest of a pick's sources, and how easy it is.
function UpgradeQuest.BestSource(sources, zone)
    local best, bestEase
    for _, source in ipairs(sources or {}) do
        local ease = UpgradeQuest.Ease(source, zone)
        if not best or ease > bestEase then best, bestEase = source, ease end
    end
    return best, bestEase or 0
end

--- From a finder scan, the pick most worth going after: { pick, source },
--- or nil. Gear that waits on a reputation, that nobody on the account can
--- make, or that the player skipped is left out.
function UpgradeQuest:Choose(found)
    if type(found) ~= "table" or type(found.slots) ~= "table" then return nil end
    local skipped = self:Skipped()
    local zone = found.player and found.player.zone
    local best
    for _, list in pairs(found.slots) do
        for _, pick in ipairs(list) do
            if not pick.needs and not pick.remote and not pick.at and not skipped[pick.itemID] then
                local source, ease = self.BestSource(pick.sources, zone)
                if source then
                    -- Filling an empty slot counts as a big step up.
                    local gain = pick.gain or 0
                    if pick.result and pick.result.empty then gain = math.max(gain, 1) * 1.5 end
                    local worth = gain * ease
                    if not best or worth > best.worth
                        or (worth == best.worth and pick.itemID < best.pick.itemID) then
                        best = { pick = pick, source = source, worth = worth }
                    end
                end
            end
        end
    end
    return best
end

--- Make a pick the quest being followed.
function UpgradeQuest:Start(pick, source)
    local char = ns.charDB
    if not (char and pick) then return nil end
    local quest = {
        itemID = pick.itemID,
        link = Items.PlainLink(pick.link) or ("item:%d"):format(pick.itemID),
        slot = pick.result and pick.result.slot,
        at = Now(),
        howMuch = pick.result and ns.Compare:HowMuch(pick.result) or nil,
        source = Copy(source),
    }
    char.upgradeQuest = quest
    return quest
end

--- Look for the next upgrade. Waits a little for the server to answer
--- about gear the client has not seen, so the pick is made from all of it.
-- @return the new quest, or nil and "waiting" or "none"
function UpgradeQuest:PickNext()
    local found = ns.Finder and ns.Finder:Scan()
    if not found then
        self.lookingSince = nil
        return nil, "none"
    end
    self.lookingSince = self.lookingSince or ns.Finder.Now()
    if found.waiting > 0 and ns.Finder.Now() - self.lookingSince < WAIT_FOR_ITEMS then
        return nil, "waiting"
    end
    self.lookingSince = nil
    local best = self:Choose(found)
    if not best then return nil, "none" end
    return self:Start(best.pick, best.source)
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
            if before.group == "group" then note = (note and note .. " " or "") .. "Needs a group." end
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
        local note
        if source.group == "group" then note = "Needs a group." end
        if source.group == "raid" then note = "Needs a raid." end
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
    for _, name in ipairs({ "QuestPanel", "MapPins" }) do
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

    local quest = self:Current()
    local before = quest and quest.itemID
    local lastStep = self.lastStep

    if quest and self.Worn(quest.itemID) then
        ns.charDB.upgradeQuest = nil
        ns.charDB.upgradeQuestsDone = self:DoneCount() + 1
        self.lastStep = nil
        if ns.Toast then
            ns.Toast:Show({ title = "Upgrade quest complete", link = quest.link,
                text = ("Upgrade quests done: %d. Picking your next one."):format(self:DoneCount()) })
        end
        if ns.Finder then ns.Finder:MarkStale() end
        quest = nil
    elseif quest and not self:StillWanted(quest) then
        -- Something as good or better was put on first (looted, bought,
        -- made): this one is beaten, carried or not.
        ns.charDB.upgradeQuest = nil
        self.lastStep = nil
        ns.Print(("dropped the upgrade quest for %s: you wear something as good now."):format(quest.link))
        if ns.Toast then
            ns.Toast:Show({ title = "You already beat this one", link = quest.link,
                text = "You wear something as good. Picking your next upgrade." })
        end
        if ns.Finder then ns.Finder:MarkStale() end
        quest = nil
    elseif quest and self:HandedInWithout(quest) then
        -- The quest was handed in and another reward taken: it cannot be
        -- done again, so this upgrade is out of reach.
        ns.charDB.upgradeQuest = nil
        self:Skipped()[quest.itemID] = true
        self.lastStep = nil
        ns.Print(("dropped the upgrade quest for %s: that quest is already done."):format(quest.link))
        quest = nil
    end

    if not quest then
        local why
        quest, why = self:PickNext()
        self.state = quest and "active" or why
        if quest then
            self.lastStep = nil
            if ns.Toast then
                ns.Toast:Show({ title = "New upgrade quest", link = quest.link,
                    text = quest.howMuch and ("%s over what you wear now."):format(quest.howMuch)
                        or "Follow the steps on the quest panel." })
            end
        end
    else
        self.state = "active"
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

--- Leave this upgrade and pick another.
function UpgradeQuest:Skip()
    local quest = self:Current()
    if not quest then return false end
    self:Skipped()[quest.itemID] = true
    ns.charDB.upgradeQuest = nil
    self.lastStep = nil
    self:Update()
    return true
end

--- Turn the upgrade quest on or off.
function UpgradeQuest:SetEnabled(on)
    if not ns.db then return end
    ns.db.upgradeQuest = on and true or false
    if on then
        self:Update()
    else
        self.state = nil
        self:Changed()
    end
end

function UpgradeQuest:OnEvent()
    self:UpdateSoon()
end

function UpgradeQuest:OnEnable()
    for _, event in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP",
        "ZONE_CHANGED_NEW_AREA", "QUEST_ACCEPTED", "QUEST_LOG_UPDATE", "QUEST_TURNED_IN",
        "GET_ITEM_INFO_RECEIVED", "SKILL_LINES_CHANGED", "NEW_RECIPE_LEARNED", "TRAIT_CONFIG_UPDATED" }) do
        ns.RegisterEvent(self, event, self.OnEvent)
    end
    if self:IsEnabled() then self:UpdateSoon(3) end
end

--------------------------------------------------------------------------------
-- /beq quest
--------------------------------------------------------------------------------

ns.RegisterCommand("quest", "a quest for your next upgrade (/beq quest off, skip, or reset)", function(rest)
    local word = (rest or ""):lower():match("^%s*(%a*)") or ""
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
    if word == "reset" then
        if ns.charDB then ns.charDB.upgradeQuestSkipped = {} end
        ns.Print("skipped upgrades can come up again.")
        UpgradeQuest:Update()
        return
    end
    if not UpgradeQuest:IsEnabled() then
        UpgradeQuest:SetEnabled(true)
        ns.Print("upgrade quest on. Follow the steps on the quest panel.")
    else
        UpgradeQuest:Update()
    end
    if ns.QuestPanel then ns.QuestPanel:Unfold() end
end)
