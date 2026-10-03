-- Blackthornes Equipment -- UI/QuestRewards.lua
-- When a quest lets you choose a reward, put the green arrow on the choice
-- that is the biggest upgrade for your spec, and say which in chat when you
-- hand the quest in.
--
-- Each choice is judged exactly as bag items are (Compare:Judge), so the
-- arrow here, the arrow in the bags and the tooltip line agree. Only an
-- upgrade that can be worn now is marked; when none of the choices is one,
-- nothing is marked and chat says so.
--
-- The reward buttons are the game's own quest window buttons. As in the
-- bags, the arrow is a texture this addon adds over one; nothing of
-- Blizzard's is changed.

local _, ns = ...

local QuestRewards = ns.NewModule("QuestRewards")

local Compare = ns.Compare
local Items = ns.Items

-- The most reward buttons the classic quest window names.
local MAX_BUTTONS = 10

local function Field(object, key)
    if type(object) ~= "table" then return nil end
    local ok, value = pcall(function() return object[key] end)
    if ok then return value end
    return nil
end

local function Ask(object, method, ...)
    local fn = Field(object, method)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, object, ...)
    if ok then return value end
    return nil
end

-- The same switch as the bag arrows: one setting for every upgrade arrow.
function QuestRewards:IsEnabled()
    return not (ns.db and ns.db.bagArrows == false)
end

--------------------------------------------------------------------------------
-- The choices
--------------------------------------------------------------------------------

--- How many rewards the open quest lets you choose between.
function QuestRewards:Count()
    return tonumber((Items.Call({ "GetNumQuestChoices" }))) or 0
end

--- The link of choice `index`, or nil.
function QuestRewards:Link(index)
    return Items.PlainLink(Items.Call({ "GetQuestItemLink" }, "choice", index))
end

--- Has the client got an item's details? True when it cannot say.
function QuestRewards:IsCached(link)
    local id = tonumber(link:match("item:(%d+)"))
    local cached = id and Items.Call({ "C_Item.IsItemDataCachedByID" }, id)
    if cached == nil then return Items:Info(link) ~= nil and Items:Stats(link) ~= nil end
    return cached == true
end

--- The choice that is the biggest upgrade that can be worn now.
-- @return index, link, result; or nil when none of them is one
-- The fourth return is how many choices are gear whose details the client
-- has not had yet, so they could not be judged.
function QuestRewards:Best()
    local bestIndex, bestLink, bestResult, bestGain
    local unknown = 0
    for index = 1, self:Count() do
        local link = self:Link(index)
        local ok, result = pcall(Compare.JudgeCarried, Compare, link)
        if ok and result == nil then
            -- No link yet, or gear whose stats have not arrived: worth
            -- waiting for. A cached item that still cannot be judged is not.
            if not link then
                unknown = unknown + 1
            else
                local okInfo, info = pcall(Items.Info, Items, link)
                local gear = okInfo and (info == nil or Compare.SLOTS[info.equipLoc])
                if gear and not Items:Stats(link) and not self:IsCached(link) then
                    unknown = unknown + 1
                end
            end
        end
        if ok and Compare.WearableUpgrade(result) then
            -- Gain in score, not percent: +5 on a slot worth 50 beats +50% on
            -- a slot worth 2. An empty slot counts its whole score.
            local gain = (result.score or 0) - (result.against or 0)
            if not bestGain or gain > bestGain then
                bestIndex, bestLink, bestResult, bestGain = index, link, result, gain
            end
        end
    end
    return bestIndex, bestLink, bestResult, unknown
end

--------------------------------------------------------------------------------
-- The buttons
--------------------------------------------------------------------------------

--- Every reward button in the quest window, choices and fixed rewards alike.
function QuestRewards:Buttons()
    local buttons = {}
    local list = Field(_G.QuestInfoRewardsFrame, "RewardButtons")
    if type(list) == "table" then
        for _, button in ipairs(list) do buttons[#buttons + 1] = button end
    end
    if #buttons == 0 then
        for i = 1, MAX_BUTTONS do
            local button = _G["QuestInfoRewardsFrameQuestInfoItem" .. i]
            if type(button) ~= "table" then break end
            buttons[#buttons + 1] = button
        end
    end
    return buttons
end

--- The button showing choice `index`: the game marks choices with
--- type "choice" and numbers them through GetID.
function QuestRewards:ButtonFor(index)
    for _, button in ipairs(self:Buttons()) do
        if Field(button, "type") == "choice" and Ask(button, "GetID") == index then
            return button
        end
    end
    return nil
end

--- Put the arrow on the best choice and take it off the rest.
-- @return the index marked, or nil
function QuestRewards:Mark()
    local best = self:IsEnabled() and self:Best() or nil
    local marked = nil

    for _, button in ipairs(self:Buttons()) do
        local isBest = best ~= nil and Field(button, "type") == "choice"
            and Ask(button, "GetID") == best
        if isBest then
            local arrow = ns.BagIcons:Arrow(button)
            if arrow then
                arrow:Show()
                marked = best
            end
        else
            local arrow = ns.BagIcons:ExistingArrow(button)
            if arrow then arrow:Hide() end
        end
    end
    self.lastMarked = marked
    return marked
end

--- Take the arrow off every reward button.
function QuestRewards:HideArrows()
    for _, button in ipairs(self:Buttons()) do
        local arrow = ns.BagIcons:ExistingArrow(button)
        if arrow then arrow:Hide() end
    end
end

--------------------------------------------------------------------------------
-- Saying so in chat
--------------------------------------------------------------------------------

--- One line when a quest is handed in with rewards to choose from.
-- A reward the client has not described yet cannot be judged, so the line
-- waits for its details (GET_ITEM_INFO_RECEIVED) rather than saying none of
-- them helps.
-- It waits once: if a reward is still unknown after the next answer, a
-- best pick is still named, but "none of these" is never said on a guess.
function QuestRewards:Announce(retry)
    self.announcePending = false
    if not self:IsEnabled() or self:Count() < 2 then return end

    local index, link, result, unknown = self:Best()
    if unknown > 0 and not retry then
        self.announcePending = true
        return
    end
    if unknown > 0 and not index then return end
    if index then
        local how = result.empty and "fills an empty slot"
            or result.percent and ("%+d%%"):format(math.floor(result.percent + 0.5))
            or "better stats"
        ns.Print(("best reward for %s: %s |c%s%s|r"):format(
            result.specName, link, ns.COLORS.upgrade, how))
    else
        ns.Print(("|c%snone of these rewards beats what you wear|r"):format(ns.COLORS.muted))
    end
end

--------------------------------------------------------------------------------
-- Being told a quest window opened
--------------------------------------------------------------------------------

function QuestRewards:Refresh()
    return (pcall(self.Mark, self))
end

--- Mark once the game has laid the window out: the quest events can reach
--- this addon before the quest frame has drawn its buttons.
function QuestRewards:RefreshSoon()
    local after = Field(_G.C_Timer, "After")
    if type(after) == "function" then
        after(0, function() QuestRewards:Refresh() end)
    else
        self:Refresh()
    end
end

function QuestRewards:QUEST_COMPLETE()
    self:RefreshSoon()
    pcall(self.Announce, self)
end

--- A choice the client had not seen before arrives a moment later: mark
--- again, and say the hand-in line that was waiting on it.
function QuestRewards:GET_ITEM_INFO_RECEIVED()
    if not Ask(_G.QuestFrame, "IsShown") then
        self.announcePending = false
        return
    end
    self:Refresh()
    if self.announcePending then pcall(self.Announce, self, true) end
end

--- The window moved on to another quest (or closed): a line still waiting
--- would describe the wrong rewards, so it is dropped.
function QuestRewards:Moved()
    self.announcePending = false
end

function QuestRewards:OnEnable()
    -- The game lays out the reward buttons in QuestInfo_Display, for the
    -- offer, the progress and the hand-in alike; marking after it runs is
    -- marking the buttons as they are.
    local hook = _G.hooksecurefunc
    if type(hook) == "function" and type(_G.QuestInfo_Display) == "function" then
        -- The quest log draws its rewards through the same function, but
        -- the choice calls describe the quest giver's window, so arrows are
        -- only marked while that window is open.
        self.hooked = pcall(hook, "QuestInfo_Display", function()
            if Ask(_G.QuestFrame, "IsShown") then
                QuestRewards:Refresh()
            else
                QuestRewards:HideArrows()
            end
        end)
    end

    ns.RegisterEvent(self, "QUEST_DETAIL", function()
        QuestRewards:Moved()
        QuestRewards:RefreshSoon()
    end)
    ns.RegisterEvent(self, "QUEST_GREETING", self.Moved)
    ns.RegisterEvent(self, "QUEST_FINISHED", self.Moved)
    ns.RegisterEvent(self, "QUEST_COMPLETE", self.QUEST_COMPLETE)
    ns.RegisterEvent(self, "GET_ITEM_INFO_RECEIVED", self.GET_ITEM_INFO_RECEIVED)
end
