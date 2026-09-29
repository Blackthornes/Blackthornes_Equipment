-- Blackthornes Equipment -- Probe/Probe.lua
-- /beq probe: ask the running client what it actually supports, rather than
-- trusting documentation written for another version of the game.
--
-- Same idea as Tradeskills' /bts probe. It only reads: nothing is changed,
-- saved or sent anywhere. Every call is inside a pcall, because Forever hands
-- out secret values in instances that raise when touched.

local _, ns = ...

local Probe = ns.NewModule("Probe")

-- The equipment slots worth looking at for a hunter: main hand, off hand and
-- ranged. Forever may have no separate ranged slot; the probe says so.
local SLOTS = { { 16, "main hand" }, { 17, "off hand" }, { 18, "ranged" } }

-- The calls worth knowing about. Talents on Forever turned out to be the
-- newer trait system (C_ClassTalents, C_Traits), not the classic tabs.
local APIS = {
    "UnitClass", "UnitLevel", "GetNumTalentTabs", "GetTalentTabInfo",
    "GetNumTalents", "GetTalentInfo", "GetSpecialization",
    "C_SpecializationInfo.GetSpecialization", "C_ClassTalents.GetActiveConfigID",
    "C_Traits.GetConfigInfo", "C_Traits.GetTreeCurrencyInfo", "C_Traits.GetTreeNodes",
    "C_Item.GetItemStats", "GetItemStats", "GetInventoryItemLink",
    "GetQuestItemLink", "GetNumQuestChoices",
}

local function Has(path)
    local value = _G
    for part in path:gmatch("[^.]+") do
        if type(value) ~= "table" then return false end
        value = value[part]
    end
    return type(value) == "function"
end

local function Line(label, value)
    local ok, text = pcall(tostring, value)
    ns.PrintRaw(("  |c%s%s|r  %s"):format(ns.COLORS.muted, label, ok and text or "(unreadable)"))
end

--- Walk the active talent config as far as the client lets us: its id, its
--- trees, and for each tree how many points are spent and how many nodes it
--- has. This is what decides how Weights will read the spec on Forever.
function Probe:Traits()
    if not Has("C_ClassTalents.GetActiveConfigID") then return end

    local ok, configID = pcall(C_ClassTalents.GetActiveConfigID)
    if not ok or not configID then
        Line("talent config", "none active (no points yet?)")
        return
    end
    Line("talent config", configID)

    if not Has("C_Traits.GetConfigInfo") then return end
    local okInfo, info = pcall(C_Traits.GetConfigInfo, configID)
    if not okInfo or type(info) ~= "table" then
        Line("config info", "not readable")
        return
    end

    local trees = type(info.treeIDs) == "table" and info.treeIDs or {}
    Line("config", ("type %s, name %s, %d tree(s)"):format(
        tostring(info.type), tostring(info.name), #trees))

    for index, treeID in ipairs(trees) do
        local parts = { "id " .. tostring(treeID) }

        if Has("C_Traits.GetTreeCurrencyInfo") then
            local okCur, currencies = pcall(C_Traits.GetTreeCurrencyInfo, configID, treeID, false)
            if okCur and type(currencies) == "table" then
                for _, currency in ipairs(currencies) do
                    parts[#parts + 1] = ("spent %s of %s"):format(
                        tostring(currency.spent), tostring(currency.maxQuantity or currency.quantity))
                end
            end
        end

        if Has("C_Traits.GetTreeNodes") then
            local okNodes, nodes = pcall(C_Traits.GetTreeNodes, treeID)
            if okNodes and type(nodes) == "table" then
                parts[#parts + 1] = #nodes .. " nodes"
            end
        end

        Line("  tree " .. index, table.concat(parts, ", "))
    end
end

--- The raw table GetItemStats returns for a link, from whichever version of
--- the call the client has, or nil.
function Probe:ItemStats(link)
    if Has("C_Item.GetItemStats") then
        local ok, stats = pcall(C_Item.GetItemStats, link)
        if ok and type(stats) == "table" then return stats end
    end
    if Has("GetItemStats") then
        local ok, stats = pcall(GetItemStats, link)
        if ok and type(stats) == "table" then return stats end
    end
    return nil
end

function Probe:Run()
    ns.Print("probe: what this client supports")

    -- Two lines rather than one per call, so the whole probe fits in the
    -- chat window without scrolling.
    local present, missing = {}, {}
    for _, api in ipairs(APIS) do
        if Has(api) then
            present[#present + 1] = api
        else
            missing[#missing + 1] = api
        end
    end
    Line("has", #present > 0 and table.concat(present, ", ") or "none of them")
    Line("missing", #missing > 0 and table.concat(missing, ", ") or "nothing")

    if Has("UnitLevel") then
        local ok, level = pcall(UnitLevel, "player")
        Line("level", ok and level or "unreadable")
    end

    self:Traits()

    local Weights = ns.Weights
    Line("class", Weights:PlayerClass() or "unknown")

    local points = Weights:TreePoints()
    if points then
        local parts = {}
        for tab, spent in ipairs(points) do parts[tab] = tostring(spent) end
        Line("talent points", table.concat(parts, " / "))
    else
        Line("talent points", "no talent trees to read")
    end

    local spec, why = Weights:CurrentSpec()
    Line("judged as", spec and (spec .. " (" .. why .. ")") or "no weights for this class")

    if not Has("GetInventoryItemLink") then return end

    for _, slot in ipairs(SLOTS) do
        local ok, link = pcall(GetInventoryItemLink, "player", slot[1])
        if not ok or not link then
            Line(slot[2], "empty or not readable")
        else
            local stats = self:ItemStats(link)
            if not stats then
                Line(slot[2], "no stats readable")
            else
                local keys = {}
                for key, value in pairs(stats) do
                    keys[#keys + 1] = ("%s=%s"):format(tostring(key), tostring(value))
                end
                table.sort(keys)
                Line(slot[2], table.concat(keys, ", "))

                local _, unknown = Weights:Normalize(stats)
                if #unknown > 0 then
                    Line("  not weighted", table.concat(unknown, ", "))
                end
            end
        end
    end
end

ns.RegisterCommand("probe", "check what this client supports (reads only)", function()
    Probe:Run()
end)
