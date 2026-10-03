-- Blackthornes Equipment -- Core/Init.lua
-- Namespace, module registry, event dispatch and slash-command routing.
--
-- Same shape as Blackthornes Tradeskills and Blackthornes Farmer, and for the
-- same reason: Ace3 and LibStub are not known to be ported to WoW: Forever, so
-- the framework is ours and is small enough to read in one sitting.

local ADDON_NAME, ns = ...

_G.BlackthornesEquipment = ns

ns.ADDON_NAME = ADDON_NAME

local function GetMeta(field)
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        local ok, value = pcall(C_AddOns.GetAddOnMetadata, ADDON_NAME, field)
        if ok then return value end
    end
    if type(_G.GetAddOnMetadata) == "function" then
        local ok, value = pcall(_G.GetAddOnMetadata, ADDON_NAME, field)
        if ok then return value end
    end
    return nil
end

-- The TOC carries @project-version@, which the release packager rewrites to
-- the tag it is building, "v0.2.0" say. Running straight from the repository
-- there is no packager, so the keyword arrives unsubstituted and is shown as
-- "dev".
local function ReadVersion()
    local value = GetMeta("Version")
    if type(value) ~= "string" or value == "" then return "0.0.0" end
    if value:find("@", 1, true) then return "dev" end
    -- Tags start with a "v"; the version itself does not.
    return (value:gsub("^[vV]", ""))
end

ns.VERSION = ReadVersion()

--- The version as players see it: "v0.2.0", or "dev build" from a checkout.
function ns.VersionLabel()
    if ns.VERSION == "dev" then return "dev build" end
    return "v" .. ns.VERSION
end

--------------------------------------------------------------------------------
-- Output
--------------------------------------------------------------------------------

-- The house palette, shared with Tradeskills and Farmer so the three look
-- like one set. Upgrades borrow Tradeskills' profit green, downgrades its loss
-- red.
ns.COLORS = {
    accent    = "ffc8a44d",
    upgrade   = "ff4fd18b",
    downgrade = "ffe5604f",
    muted     = "ff7a8089",
    warn      = "ffe8c15a",
    text      = "ffe6e8ec",
}

local PREFIX = "|c" .. ns.COLORS.accent .. "Equipment|r "

local function Join(...)
    local n = select("#", ...)
    if n == 0 then return "" end

    local parts = {}
    for i = 1, n do
        parts[i] = tostring((select(i, ...)))
    end
    return table.concat(parts, " ")
end

function ns.Print(...)
    local frame = DEFAULT_CHAT_FRAME
    if frame then
        frame:AddMessage(PREFIX .. Join(...))
    end
end

-- Raw line with no prefix, for multi-line reports where the prefix is noise.
function ns.PrintRaw(...)
    local frame = DEFAULT_CHAT_FRAME
    if frame then
        frame:AddMessage(Join(...))
    end
end

function ns.Debug(...)
    if ns.db and ns.db.debug then
        ns.PrintRaw("|c" .. ns.COLORS.muted .. "Equipment debug|r " .. Join(...))
    end
end

function ns.Warn(...)
    ns.Print("|c" .. ns.COLORS.warn .. Join(...) .. "|r")
end

--------------------------------------------------------------------------------
-- Module registry
--------------------------------------------------------------------------------

ns.modules = {}
ns.moduleOrder = {}

local moduleProto = {}
moduleProto.__index = moduleProto

function moduleProto:RegisterEvent(event, fn)
    return ns.RegisterEvent(self, event, fn or self[event])
end

function moduleProto:UnregisterEvent(event)
    return ns.UnregisterEvent(self, event)
end

function ns.NewModule(name)
    assert(type(name) == "string", "module name must be a string")
    assert(not ns.modules[name], "duplicate module: " .. name)

    local module = setmetatable({ moduleName = name }, moduleProto)
    ns.modules[name] = module
    ns.moduleOrder[#ns.moduleOrder + 1] = module
    ns[name] = module
    return module
end

--------------------------------------------------------------------------------
-- Event dispatch
--------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame", "BlackthornesEquipmentEventFrame")
ns.eventFrame = eventFrame

local handlers = {}
local unknownEvents = {}

--- Register an event handler.
-- On Forever, registering an event the client does not know raises a Lua error
-- rather than failing quietly, so every registration goes through pcall.
function ns.RegisterEvent(owner, event, fn)
    if type(fn) ~= "function" then
        ns.Debug("RegisterEvent: no handler for", event)
        return false
    end

    local list = handlers[event]
    if not list then
        if unknownEvents[event] then return false end

        local ok, err = pcall(eventFrame.RegisterEvent, eventFrame, event)
        if not ok then
            unknownEvents[event] = err or true
            ns.Debug("event not supported by this client:", event)
            return false
        end
        list = {}
        handlers[event] = list
    end

    list[#list + 1] = { owner = owner, fn = fn }
    return true
end

function ns.UnregisterEvent(owner, event)
    local list = handlers[event]
    if not list then return false end

    for i = #list, 1, -1 do
        if list[i].owner == owner then
            table.remove(list, i)
        end
    end

    if #list == 0 then
        handlers[event] = nil
        pcall(eventFrame.UnregisterEvent, eventFrame, event)
    end
    return true
end

function ns.GetUnknownEvents()
    return unknownEvents
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end

    -- One handler erroring must not swallow the rest.
    for i = 1, #list do
        local entry = list[i]
        if entry then
            local ok, err = pcall(entry.fn, entry.owner, event, ...)
            if not ok then
                geterrorhandler()(err)
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

local initialized = false
local enabled = false

local function RunLifecycle(method)
    for i = 1, #ns.moduleOrder do
        local module = ns.moduleOrder[i]
        local fn = module[method]
        if type(fn) == "function" then
            local ok, err = pcall(fn, module)
            if not ok then
                ns.Warn(("module %s:%s failed"):format(module.moduleName, method))
                geterrorhandler()(err)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Saved variables
--------------------------------------------------------------------------------

local DEFAULTS = {
    point = "CENTER",
    relativePoint = "CENTER",
    x = 0,
    y = 40,
    debug = false,

    -- Minimap button: where it sits on the ring, how far off the edge, and
    -- whether it is there at all. A little further round than Farmer's and
    -- Tradeskills' buttons, so the three do not start stacked.
    minimapAngle = math.rad(230),
    minimapGap = 16,
    minimapHidden = false,

    -- The verdict on gear: a line on its tooltip, and an arrow on it in the
    -- bags and on the best quest reward when it is an upgrade. Both on unless
    -- switched off.
    tooltipLine = true,
    bagArrows = true,

    -- A line in chat when an upgrade you can wear now lands in the bags.
    upgradeChat = true,

    -- The "Where to get upgrades" window: where it sits, and which sources
    -- it shows ("all", "vendor", "quest" or "dungeon").
    finderPoint = "CENTER",
    finderRelativePoint = "CENTER",
    finderX = 40,
    finderY = 20,
    finderShow = "all",
    -- How many levels ahead the finder looks (0 for now).
    finderAhead = 0,

    -- Upgrade hunts: the banner when an upgrade or a tracked one lands in
    -- the bags, the tracker panel and where it sits, pins on the world map,
    -- upgrades on the character sheet's slots, and naming random rolls on
    -- tooltips. All on unless switched off. What is tracked is kept per
    -- character (`tracked`, `trackedDone`; Logic/Tracking.lua).
    upgradeToast = true,
    showTracker = true,
    mapPins = true,
    slotUpgrades = true,
    suffixLine = true,

    -- The player's own stat weights, by class and spec, are kept under
    -- `customWeights` (Logic/Weights.lua). Not given a default here: the
    -- table is made the first time a weight is changed, and once made it is
    -- never cleared or renamed by an update.
}

-- Per character, because class and spec are. `spec` is the spec the player
-- picked to be judged as; nil means work it out from the character.
local CHAR_DEFAULTS = {
    spec = nil,
}

local function ApplyDefaults(db, defaults)
    for key, value in pairs(defaults) do
        if db[key] == nil then
            db[key] = value
        end
    end
end

local function LoadSavedVariables()
    if type(BlackthornesEquipmentDB) ~= "table" then
        BlackthornesEquipmentDB = {}
    end
    if type(BlackthornesEquipmentCharDB) ~= "table" then
        BlackthornesEquipmentCharDB = {}
    end

    ApplyDefaults(BlackthornesEquipmentDB, DEFAULTS)
    ApplyDefaults(BlackthornesEquipmentCharDB, CHAR_DEFAULTS)

    ns.db = BlackthornesEquipmentDB
    ns.charDB = BlackthornesEquipmentCharDB
end

ns.LoadSavedVariables = LoadSavedVariables

-- Read-only: a settings page can put window positions back from here.
ns.DEFAULTS = DEFAULTS

local bootstrap = ns.NewModule("Bootstrap")

function bootstrap:ADDON_LOADED(_, loadedAddon)
    if loadedAddon ~= ADDON_NAME or initialized then return end
    initialized = true

    LoadSavedVariables()
    RunLifecycle("OnInitialize")
end

function bootstrap:PLAYER_LOGIN()
    if enabled then return end
    enabled = true
    RunLifecycle("OnEnable")
end

ns.RegisterEvent(bootstrap, "ADDON_LOADED", bootstrap.ADDON_LOADED)
ns.RegisterEvent(bootstrap, "PLAYER_LOGIN", bootstrap.PLAYER_LOGIN)

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------

ns.commands = {}
ns.commandOrder = {}

--- Register a `/beq <name>` subcommand.
function ns.RegisterCommand(name, usage, fn)
    ns.commands[name] = { usage = usage, fn = fn }
    ns.commandOrder[#ns.commandOrder + 1] = name
end

local function ShowHelp()
    ns.Print(("|c%sBlackthornes Equipment|r %s"):format(ns.COLORS.accent, ns.VersionLabel()))

    for i = 1, #ns.commandOrder do
        local name = ns.commandOrder[i]
        local command = ns.commands[name]
        ns.PrintRaw(("  |c%s/beq %s|r  |c%s%s|r"):format(
            ns.COLORS.accent, name, ns.COLORS.muted, command.usage or ""))
    end
end

ns.RegisterCommand("help", "show this list", ShowHelp)

SLASH_BLACKTHORNESEQUIPMENT1 = "/beq"
SLASH_BLACKTHORNESEQUIPMENT2 = "/equipment"

-- Named rather than anonymous so the test suite can drive it directly; the
-- slash routing is where a command goes wrong, so it is worth testing.
function ns.HandleSlash(input)
    input = (input or ""):gsub("^%s+", ""):gsub("%s+$", "")

    local keyword, rest = input:match("^(%S+)%s*(.*)$")
    if not keyword then
        if ns.UI and ns.UI.Toggle then
            ns.UI:Toggle()
        else
            ShowHelp()
        end
        return
    end

    local command = ns.commands[keyword:lower()]
    if not command then
        ns.Warn(("unknown command: %s"):format(keyword))
        ShowHelp()
        return
    end

    -- Wrapped because a command that errors is otherwise completely silent:
    -- this client does not show Lua errors unless scriptErrors is on, so a
    -- broken command and one that did nothing look identical from the chat
    -- frame.
    local ok, err = pcall(command.fn, rest or "")

    -- Most commands flip something the settings page shows; keep it honest
    -- if it happens to be open. Before the error handler, which may raise.
    if ns.SettingsUI then
        pcall(ns.SettingsUI.Refresh, ns.SettingsUI)
    end
    -- /beq spec changes what counts as an upgrade.
    if ns.BagIcons then
        pcall(ns.BagIcons.Refresh, ns.BagIcons)
    end
    if ns.UI then
        pcall(ns.UI.Refresh, ns.UI)
    end
    if ns.WeightsUI then
        pcall(ns.WeightsUI.Refresh, ns.WeightsUI)
    end

    if not ok then
        ns.Warn(("/beq %s failed: %s"):format(keyword, tostring(err)))
        geterrorhandler()(err)
    end
end

SlashCmdList["BLACKTHORNESEQUIPMENT"] = ns.HandleSlash
