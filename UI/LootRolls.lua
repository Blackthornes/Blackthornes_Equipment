-- Blackthornes Equipment -- UI/LootRolls.lua
-- When gear comes up for a group loot roll (the Need / Greed window), put
-- the green arrow on its icon if it is an upgrade you can wear now, with how
-- much better it is underneath ("+14%").
--
-- The item is judged exactly as bag items are (Compare:Judge), so the arrow
-- here, the arrow in the bags and the tooltip line agree. An upgrade you are
-- not high enough level to wear yet gets no arrow, as in the bags.
--
-- Forever is a retail engine with classic content, so how its roll windows
-- are built is not assumed. Both shapes are handled: retail keeps the
-- windows in GroupLootContainer.rollFrames, classic names them
-- GroupLootFrame1..4; each knows its roll through `rollID` and has its icon
-- button as `IconFrame` (or <name>IconFrame). /beq probe says which this
-- client has. As in the bags, the arrow and the text are this addon's own,
-- laid over the game's button; nothing of Blizzard's is changed, so rolling
-- in combat is not affected.

local _, ns = ...

local LootRolls = ns.NewModule("LootRolls")

local Compare = ns.Compare
local Items = ns.Items
local Theme = ns.Theme

-- The most roll windows the game shows at once, when it does not say.
local MAX_FRAMES = 4
-- The percentage under the icon: the size it starts at, and the smallest it
-- is shrunk to before it is left off rather than spill past the icon.
local LABEL_SIZE, LABEL_MIN_SIZE = 12, 8
-- The icon's width when the client does not say.
local ICON_WIDTH = 34

local labels = setmetatable({}, { __mode = "k" })
local hookedFrames = setmetatable({}, { __mode = "k" })

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
function LootRolls:IsEnabled()
    return not (ns.db and ns.db.bagArrows == false)
end

--------------------------------------------------------------------------------
-- The roll windows
--------------------------------------------------------------------------------

--- Every roll window this client has, shown or not, each once.
function LootRolls:Frames()
    local frames, seen = {}, {}
    local function Add(frame)
        if type(frame) == "table" and not seen[frame] then
            seen[frame] = true
            frames[#frames + 1] = frame
        end
    end

    local list = Field(_G.GroupLootContainer, "rollFrames")
    if type(list) == "table" then
        pcall(function()
            for _, frame in pairs(list) do Add(frame) end
        end)
    end

    local count = tonumber(_G.NUM_GROUP_LOOT_FRAMES) or MAX_FRAMES
    for i = 1, count do Add(_G["GroupLootFrame" .. i]) end
    return frames
end

--- The icon button of one roll window, or nil.
function LootRolls:IconOf(frame)
    local icon = Field(frame, "IconFrame")
    if type(icon) == "table" then return icon end
    local name = Ask(frame, "GetName")
    if type(name) == "string" then
        icon = _G[name .. "IconFrame"]
        if type(icon) == "table" then return icon end
    end
    return nil
end

--- The link of the item a roll window is for, or nil.
function LootRolls:LinkOf(frame)
    local rollID = Field(frame, "rollID")
    if rollID == nil then return nil end
    return Items.PlainLink(Items.Call({ "GetLootRollItemLink" }, rollID))
end

--------------------------------------------------------------------------------
-- The marker
--------------------------------------------------------------------------------

--- The percentage under the icon, made the first time it is asked for.
function LootRolls:Label(icon)
    local label = labels[icon]
    if label then return label end

    local create = Field(icon, "CreateFontString")
    if type(create) ~= "function" then return nil end
    local ok, text = pcall(create, icon, nil, "OVERLAY")
    if not ok or not text then return nil end

    text:SetPoint("BOTTOM", icon, "BOTTOM", 0, 2)
    text:Hide()
    labels[icon] = text
    return text
end

--- Write `words` under the icon in the largest size that fits inside it,
--- outlined so it reads over any icon. Left off when even the smallest size
--- would spill past the icon's edges.
-- @return true when it is showing
function LootRolls:FitLabel(label, icon, words)
    local width = (tonumber(Ask(icon, "GetWidth")) or ICON_WIDTH) - 2
    for size = LABEL_SIZE, LABEL_MIN_SIZE, -1 do
        pcall(label.SetFont, label, Theme.FONT, size, "OUTLINE")
        label:SetText(words)
        local measured = tonumber(Ask(label, "GetStringWidth")) or 0
        if measured <= width then
            label:SetTextColor(Theme.Unpack("good"))
            label:Show()
            return true
        end
    end
    label:Hide()
    return false
end

--- What to write under the icon: the percentage, when there is one. An
--- empty slot or a piece with no stats worn has no percentage to give; the
--- arrow and the tooltip say the rest.
local function Words(result)
    if result.empty or not result.percent then return nil end
    return ("%+d%%"):format(math.floor(result.percent + 0.5))
end

--- Mark one roll window, or take its marker off.
-- @return true when it is marked
function LootRolls:UpdateFrame(frame)
    local icon = self:IconOf(frame)
    if not icon then return false end

    local result
    if self:IsEnabled() and Ask(frame, "IsShown") then
        local link = self:LinkOf(frame)
        local ok, judged = pcall(Compare.Judge, Compare, link)
        if ok and judged and judged.verdict == "upgrade" and not judged.level then
            result = judged
        end
    end

    if not result then
        local arrow = ns.BagIcons:ExistingArrow(icon)
        if arrow then arrow:Hide() end
        if labels[icon] then labels[icon]:Hide() end
        return false
    end

    local arrow = ns.BagIcons:Arrow(icon)
    if arrow then arrow:Show() end

    local words = Words(result)
    local label = words and self:Label(icon)
    if label then
        self:FitLabel(label, icon, words)
    elseif labels[icon] then
        labels[icon]:Hide()
    end
    return arrow ~= nil
end

--- Look again at every roll window, hooking any that is new.
function LootRolls:Refresh()
    local marked, shown = 0, 0
    for _, frame in ipairs(self:Frames()) do
        self:HookFrame(frame)
        if Ask(frame, "IsShown") then shown = shown + 1 end
        local ok, on = pcall(self.UpdateFrame, self, frame)
        if ok and on then marked = marked + 1 end
    end
    self.lastMarked = marked
    self.lastShown = shown
    return marked
end

--- Mark once the game has filled the window in: the roll event can reach
--- this addon before the window has been given its roll.
function LootRolls:RefreshSoon()
    local after = Field(_G.C_Timer, "After")
    if type(after) == "function" then
        after(0, function() pcall(LootRolls.Refresh, LootRolls) end)
    else
        pcall(self.Refresh, self)
    end
end

--------------------------------------------------------------------------------
-- Being told a roll started
--------------------------------------------------------------------------------

--- Look again whenever a roll window shows; it is reused for the next roll.
function LootRolls:HookFrame(frame)
    if hookedFrames[frame] then return end
    local hookScript = Field(frame, "HookScript")
    if type(hookScript) ~= "function" then return end
    if pcall(hookScript, frame, "OnShow", function(shown)
        pcall(LootRolls.UpdateFrame, LootRolls, shown)
    end) then
        hookedFrames[frame] = true
    end
end

--- What the probe prints: which roll windows there are and what got hooked.
function LootRolls:Describe()
    local names = {}
    for _, frame in ipairs(self:Frames()) do
        local name = Ask(frame, "GetName") or "?"
        names[#names + 1] = name .. (self:IconOf(frame) and "" or " (no icon)")
    end
    local frames = #names > 0 and table.concat(names, ", ") or "none found yet"
    local hooks = self.hooked and #self.hooked > 0 and table.concat(self.hooked, ", ") or "none"
    return frames, hooks
end

function LootRolls:OnEnable()
    self.hooked = {}
    local hook = _G.hooksecurefunc
    if type(hook) == "function" then
        -- The game opens a roll window through one of these, depending on
        -- the client; marking after it runs is marking the window as shown.
        for _, name in ipairs({ "GroupLootFrame_OpenNewFrame", "GroupLootContainer_AddFrame" }) do
            if type(_G[name]) == "function" and pcall(hook, name, function()
                LootRolls:RefreshSoon()
            end) then
                self.hooked[#self.hooked + 1] = name
            end
        end
    end
    for _, frame in ipairs(self:Frames()) do self:HookFrame(frame) end

    ns.RegisterEvent(self, "START_LOOT_ROLL", self.RefreshSoon)
    -- An item the client had not seen before arrives a moment later, and
    -- putting gear on can change the answer while the roll is open.
    local function IfRolling()
        if LootRolls:AnyShown() then LootRolls:RefreshSoon() end
    end
    ns.RegisterEvent(self, "GET_ITEM_INFO_RECEIVED", IfRolling)
    ns.RegisterEvent(self, "PLAYER_EQUIPMENT_CHANGED", IfRolling)
end

--- Is any roll window up?
function LootRolls:AnyShown()
    for _, frame in ipairs(self:Frames()) do
        if Ask(frame, "IsShown") then return true end
    end
    return false
end
