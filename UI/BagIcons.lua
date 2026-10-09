-- Blackthornes Equipment -- UI/BagIcons.lua
-- A green arrow on the corner of any item in the bags that is an upgrade
-- over what is worn, for the spec the character is judged as.
--
-- Only the game's own bags get arrows. How the client draws them is not
-- assumed, since Forever is a retail engine with classic content: both
-- shapes are handled. Retail has ContainerFrameCombinedBags and
-- ContainerFrame1..13 whose buttons list themselves through
-- EnumerateValidItems and know their bag through GetBagID; classic names each
-- button ContainerFrame<n>Item<m> and keeps the bag id on the frame.
-- /beq probe says which frames this client has.
--
-- The arrow is a texture this addon owns, laid over the item button. Nothing
-- of Blizzard's is changed or written to, so using an item from the bags in
-- combat is not affected.

local _, ns = ...

local BagIcons = ns.NewModule("BagIcons")

local Compare = ns.Compare
local Items = ns.Items

-- The most bag windows the game opens at once, when it does not say.
local MAX_FRAMES = 13
-- The most buttons a classic bag window names.
local MAX_BUTTONS = 36

-- Retail's own upgrade arrow; the fallback is a green arrow every client
-- has, turned to point up.
local ATLAS = "bags-greenarrow"
local FALLBACK_TEXTURE = [[Interface\Buttons\UI-MicroStream-Green]]

local arrows = setmetatable({}, { __mode = "k" })

local function Field(object, key)
    if type(object) ~= "table" then return nil end
    local ok, value = pcall(function() return object[key] end)
    if ok then return value end
    return nil
end

--- Call object:method(...) if it has it; the first return, or nil.
local function Ask(object, method, ...)
    local fn = Field(object, method)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, object, ...)
    if ok then return value end
    return nil
end

function BagIcons:IsEnabled()
    return not (ns.db and ns.db.bagArrows == false)
end

--------------------------------------------------------------------------------
-- Finding the bag buttons
--------------------------------------------------------------------------------

--- The bag windows this client has, open or not.
function BagIcons:Frames()
    local frames = {}
    if type(_G.ContainerFrameCombinedBags) == "table" then
        frames[#frames + 1] = _G.ContainerFrameCombinedBags
    end
    local count = tonumber(_G.NUM_CONTAINER_FRAMES) or MAX_FRAMES
    for i = 1, count do
        local frame = _G["ContainerFrame" .. i]
        if type(frame) == "table" then frames[#frames + 1] = frame end
    end
    return frames
end

--- The item buttons in one bag window.
function BagIcons:Buttons(frame)
    local buttons = {}

    local enumerate = Field(frame, "EnumerateValidItems")
    if type(enumerate) == "function" then
        local ok = pcall(function()
            for _, button in enumerate(frame) do
                buttons[#buttons + 1] = button
            end
        end)
        if ok and #buttons > 0 then return buttons end
        buttons = {}
    end

    local name = Ask(frame, "GetName")
    if type(name) == "string" then
        for i = 1, MAX_BUTTONS do
            local button = _G[name .. "Item" .. i]
            if type(button) ~= "table" then break end
            buttons[#buttons + 1] = button
        end
    end
    return buttons
end

--- Which bag and slot a button shows, or nil.
function BagIcons:Location(button, frame)
    local bag = Ask(button, "GetBagID")
    if type(bag) ~= "number" then
        bag = Ask(Ask(button, "GetParent") or frame, "GetID")
    end
    local slot = Ask(button, "GetID")
    if type(bag) ~= "number" or type(slot) ~= "number" then return nil end
    return bag, slot
end

--------------------------------------------------------------------------------
-- The arrow
--------------------------------------------------------------------------------

local function HasAtlas(name)
    local info = Field(_G.C_Texture, "GetAtlasInfo")
    if type(info) ~= "function" then return false end
    local ok, found = pcall(info, name)
    return ok and found ~= nil
end

--- The arrow already made for a button, or nil; never makes one.
function BagIcons:ExistingArrow(button)
    return arrows[button]
end

--- The arrow for a button, made the first time it is asked for. The quest
--- reward buttons use it too.
function BagIcons:Arrow(button)
    local arrow = arrows[button]
    if arrow then return arrow end

    local create = Field(button, "CreateTexture")
    if type(create) ~= "function" then return nil end

    local ok, texture = pcall(create, button, nil, "OVERLAY", nil, 7)
    if not ok or not texture then return nil end

    texture:SetSize(16, 16)
    texture:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)

    local usedAtlas = HasAtlas(ATLAS) and pcall(texture.SetAtlas, texture, ATLAS)
    if not usedAtlas then
        texture:SetTexture(FALLBACK_TEXTURE)
        -- The stream arrow points down; flipped, it points up.
        texture:SetTexCoord(0, 1, 1, 0)
    end
    texture:Hide()

    arrows[button] = texture
    return texture
end

--- Show or hide the arrow on one button.
function BagIcons:UpdateButton(button, frame)
    local show = false
    if self:IsEnabled() then
        local bag, slot = self:Location(button, frame)
        local link = bag and Items:InBag(bag, slot)
        show = link ~= nil and Compare:IsUpgradeNow(link, true)
    end

    if show then
        local arrow = self:Arrow(button)
        if arrow then arrow:Show() end
    elseif arrows[button] then
        arrows[button]:Hide()
    end
    return show
end

--- Look again at every open bag window.
function BagIcons:Refresh()
    local shown = 0
    for _, frame in ipairs(self:Frames()) do
        if Ask(frame, "IsShown") then
            shown = shown + self:RefreshFrame(frame)
        end
    end
    self.lastShown = shown
    return shown
end

function BagIcons:RefreshFrame(frame)
    local shown = 0
    for _, button in ipairs(self:Buttons(frame)) do
        local ok, on = pcall(self.UpdateButton, self, button, frame)
        if ok and on then shown = shown + 1 end
    end
    return shown
end

--- Refresh once things settle, so a burst of bag events costs one pass.
function BagIcons:RefreshSoon()
    if self.pending then return end
    self.pending = true

    local after = Field(_G.C_Timer, "After")
    if type(after) ~= "function" then
        self.pending = false
        self:Refresh()
        return
    end

    after(0.2, function()
        BagIcons.pending = false
        BagIcons:Refresh()
    end)
end

--------------------------------------------------------------------------------
-- Being told the bags changed
--------------------------------------------------------------------------------

function BagIcons:InstallHooks()
    local hook = _G.hooksecurefunc
    local hooked = {}
    if type(hook) ~= "function" then return hooked end

    -- Classic redraws every bag window through this one function.
    if type(_G.ContainerFrame_Update) == "function" then
        if pcall(hook, "ContainerFrame_Update", function(frame)
            pcall(BagIcons.RefreshFrame, BagIcons, frame)
        end) then
            hooked[#hooked + 1] = "ContainerFrame_Update"
        end
    end

    -- Retail redraws each window through its own UpdateItems, and opening
    -- one shows it; both are hooked per window.
    local updateItems = false
    for _, frame in ipairs(self:Frames()) do
        if type(Field(frame, "UpdateItems")) == "function" then
            if pcall(hook, frame, "UpdateItems", function(shown)
                pcall(BagIcons.RefreshFrame, BagIcons, shown)
            end) then
                updateItems = true
            end
        end
        local hookScript = Field(frame, "HookScript")
        if type(hookScript) == "function" then
            pcall(hookScript, frame, "OnShow", function(shown)
                pcall(BagIcons.RefreshFrame, BagIcons, shown)
                pcall(BagIcons.ApplyGamepadBag, BagIcons)
            end)
        end
    end
    if updateItems then hooked[#hooked + 1] = "UpdateItems" end
    return hooked
end

--- What the probe prints about the bags: which windows there are, how their
--- buttons are found, and what got hooked.
function BagIcons:Describe()
    local names = {}
    for _, frame in ipairs(self:Frames()) do
        local name = Ask(frame, "GetName") or "?"
        local how = type(Field(frame, "EnumerateValidItems")) == "function" and "list" or "named"
        names[#names + 1] = ("%s (%s)"):format(name, how)
    end
    local frames = #names > 0 and table.concat(names, ", ") or "none found"
    local hooks = self.hooked and #self.hooked > 0 and table.concat(self.hooked, ", ") or "none"
    return frames, hooks
end

--------------------------------------------------------------------------------
-- Forever's controller bag button
--------------------------------------------------------------------------------

-- Forever's client puts a controller bag button (GamepadBackpackButton, on
-- its GamepadBagBar) right over the combined backpack's sort button. While
-- hideGamepadBag is on it is hidden; nothing else about it is touched, and
-- unticking the setting shows it again if it was showing. A protected button
-- is never hidden in combat: that waits for combat to end.
local GAMEPAD_BUTTON = "GamepadBackpackButton"

function BagIcons:HidesGamepadBag()
    return not (ns.db and ns.db.hideGamepadBag == false)
end

local function InCombat()
    local fn = _G.InCombatLockdown
    if type(fn) ~= "function" then return false end
    local ok, value = pcall(fn)
    return ok and value == true
end

--- Hide the button now, or once combat ends. True when it was hidden.
function BagIcons:HideGamepadButton(button)
    if not Ask(button, "IsShown") then return false end
    if Ask(button, "IsProtected") and InCombat() then
        if not self.gamepadWaiting then
            self.gamepadWaiting = ns.RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
                ns.UnregisterEvent(BagIcons, "PLAYER_REGEN_ENABLED")
                BagIcons.gamepadWaiting = false
                BagIcons:ApplyGamepadBag()
            end)
        end
        return false
    end
    local hide = Field(button, "Hide")
    if type(hide) ~= "function" or not pcall(hide, button) then return false end
    self.gamepadHidden = true
    return true
end

--- Hide or show the controller bag button as the setting says.
function BagIcons:ApplyGamepadBag()
    local button = _G[GAMEPAD_BUTTON]
    if type(button) ~= "table" then return false end

    if not self.gamepadHooked then
        local hookScript = Field(button, "HookScript")
        if type(hookScript) == "function" and pcall(hookScript, button, "OnShow", function(shown)
            if BagIcons:HidesGamepadBag() then pcall(BagIcons.HideGamepadButton, BagIcons, shown) end
        end) then
            self.gamepadHooked = true
        end
    end

    if self:HidesGamepadBag() then
        return self:HideGamepadButton(button)
    end
    if self.gamepadHidden then
        self.gamepadHidden = false
        if not (Ask(button, "IsProtected") and InCombat()) then
            local show = Field(button, "Show")
            if type(show) == "function" then pcall(show, button) end
        end
    end
    return false
end

-- Anything that can change what is an upgrade: the bags, what is worn, the
-- level, the talents, weapon skills (Dual Wield) and an item's details
-- arriving from the server.
local EVENTS = {
    "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP",
    "GET_ITEM_INFO_RECEIVED", "TRAIT_CONFIG_UPDATED", "SKILL_LINES_CHANGED",
}

function BagIcons:OnEnable()
    self.hooked = self:InstallHooks()
    pcall(self.ApplyGamepadBag, self)
    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function()
        pcall(BagIcons.ApplyGamepadBag, BagIcons)
    end)
    for _, event in ipairs(EVENTS) do
        ns.RegisterEvent(self, event, self.RefreshSoon)
    end
end
