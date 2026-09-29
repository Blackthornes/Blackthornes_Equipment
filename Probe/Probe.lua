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

    for _, api in ipairs({
        "UnitClass", "GetNumTalentTabs", "GetTalentTabInfo", "GetSpecialization",
        "C_Item.GetItemStats", "GetItemStats", "GetInventoryItemLink",
        "GetQuestItemLink", "GetNumQuestChoices",
    }) do
        Line(api, Has(api) and "yes" or "no")
    end

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
