-- Shared test environment: enough of the WoW client to load the addon.
--
-- Not a test itself -- runtests.py only runs tools/test_*.lua -- this is what
-- each suite calls to get a loaded addon and a chat frame that remembers what
-- was printed to it.
--
--   local env = dofile(lfs_cwd .. "/tools/testenv.lua")
--   local ns = env.Load()

local env = {}

local ROOT = lfs_cwd or "."
local ADDON = "Blackthornes_Equipment"

--------------------------------------------------------------------------------
-- Widgets
--------------------------------------------------------------------------------

-- Any method a test does not care about answers as a no-op, so a window can
-- build its panels, labels and anchors undisturbed.
local function Stub(fields)
    local frame = fields or {}

    frame._shown = frame._shown or false
    frame._text = frame._text or ""
    frame._scripts = frame._scripts or {}
    frame._events = frame._events or {}

    function frame:Show() self._shown = true end
    function frame:Hide() self._shown = false end
    function frame:IsShown() return self._shown end
    function frame:SetShown(value) self._shown = value and true or false end

    function frame:SetText(value) self._text = tostring(value or "") end
    function frame:GetText() return self._text end

    function frame:SetScript(script, fn) self._scripts[script] = fn end
    function frame:GetScript(script) return self._scripts[script] end

    function frame:RegisterEvent(event) self._events[event] = true end
    function frame:UnregisterEvent(event) self._events[event] = nil end

    function frame:CreateTexture() return Stub() end
    function frame:CreateFontString() return Stub() end

    return setmetatable(frame, { __index = function(self, key)
        local noop = function() end
        rawset(self, key, noop)
        return noop
    end })
end

env.Stub = Stub

--------------------------------------------------------------------------------
-- Client
--------------------------------------------------------------------------------

function env.InstallClient()
    env.chat = {}

    _G.UIParent = Stub()

    _G.CreateFrame = function(_, name, parent)
        local frame = Stub({ _parent = parent })
        if name then _G[name] = frame end
        return frame
    end

    _G.DEFAULT_CHAT_FRAME = {
        AddMessage = function(_, message) env.chat[#env.chat + 1] = message end,
    }

    _G.SlashCmdList = {}
    _G.UISpecialFrames = {}
    _G.geterrorhandler = function() return function(err) error(err, 0) end end

    -- Suites share one Lua state; what one suite saved must not leak into the
    -- next.
    _G.BlackthornesEquipmentDB = nil
    _G.BlackthornesEquipmentCharDB = nil
    _G.UnitClass = nil
    _G.GetNumTalentTabs = nil
    _G.GetTalentTabInfo = nil
    _G.GetInventoryItemLink = nil
    _G.GetItemStats = nil
    _G.C_Item = nil
end

--------------------------------------------------------------------------------
-- Loading
--------------------------------------------------------------------------------

--- The Lua files the TOC loads, in order. Read from the TOC itself, so a new
-- file is tested the moment it is listed and there is no second list here to
-- forget.
function env.TocFiles()
    local files = {}
    local handle = assert(io.open(ROOT .. "/" .. ADDON .. ".toc", "r"))
    for line in handle:lines() do
        line = line:gsub("\r$", "")
        if line ~= "" and not line:find("^#") and line:find("%.lua$") then
            files[#files + 1] = (line:gsub("\\", "/"))
        end
    end
    handle:close()
    return files
end

--- Load the addon exactly as the TOC does, and return its namespace.
function env.Load()
    env.InstallClient()

    local ns = {}
    for _, file in ipairs(env.TocFiles()) do
        local chunk = assert(loadfile(ROOT .. "/" .. file))
        chunk(ADDON, ns)
    end

    -- ADDON_LOADED installs saved variables; tests that skip the event loop
    -- still need ns.db to exist.
    ns.LoadSavedVariables()

    env.ns = ns
    return ns
end

--- Everything printed to chat since the addon loaded, as one string.
function env.ChatText()
    return table.concat(env.chat, "\n")
end

--------------------------------------------------------------------------------
-- Assertions
--------------------------------------------------------------------------------

function env.NewSuite(name)
    local suite = { name = name, checks = 0 }

    function suite.check(label, ok, detail)
        suite.checks = suite.checks + 1
        if not ok then
            error(("%s: %s%s"):format(name, label,
                detail and ("  -> " .. tostring(detail)) or ""), 0)
        end
    end

    function suite.done()
        print(("  %s: %d checks passed"):format(name, suite.checks))
    end

    return suite
end

return env
