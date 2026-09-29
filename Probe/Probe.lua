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
    "C_Traits.GetNodeInfo", "C_Traits.GetEntryInfo", "C_Traits.GetDefinitionInfo",
    "C_Spell.GetSpellName", "GetSpellInfo",
    "C_Item.GetItemInfo", "C_Item.GetItemInfoInstant", "GetItemInfo",
    "C_Container.GetContainerItemLink", "GetContainerItemLink", "ContainerFrame_Update",
    "TooltipDataProcessor.AddTooltipPostCall", "TooltipUtil.GetDisplayedItem",
    "C_Texture.GetAtlasInfo", "QuestInfo_Display", "C_CreatureInfo.GetClassInfo",
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

        local nodes
        if Has("C_Traits.GetTreeNodes") then
            local okNodes, list = pcall(C_Traits.GetTreeNodes, treeID)
            if okNodes and type(list) == "table" then
                nodes = list
                parts[#parts + 1] = #nodes .. " nodes"
            end
        end

        Line("  tree " .. index, table.concat(parts, ", "))
        if nodes then self:Nodes(configID, nodes) end
    end
end

--- The name of the talent a node grants, or nil. Node, entry, definition,
--- spell: four calls, any of which may be missing or raise.
function Probe:NodeName(configID, info)
    local entryID = type(info.entryIDs) == "table" and info.entryIDs[1]
    if not entryID or not Has("C_Traits.GetEntryInfo") then return nil end

    local ok, entry = pcall(C_Traits.GetEntryInfo, configID, entryID)
    if not ok or type(entry) ~= "table" or not entry.definitionID then return nil end
    if not Has("C_Traits.GetDefinitionInfo") then return nil end

    local okDef, definition = pcall(C_Traits.GetDefinitionInfo, entry.definitionID)
    if not okDef or type(definition) ~= "table" then return nil end
    if type(definition.overrideName) == "string" and definition.overrideName ~= "" then
        return definition.overrideName
    end

    local spellID = definition.spellID
    if not spellID then return nil end
    if Has("C_Spell.GetSpellName") then
        local okName, name = pcall(C_Spell.GetSpellName, spellID)
        if okName and type(name) == "string" then return name end
    end
    if Has("GetSpellInfo") then
        local okName, name = pcall(GetSpellInfo, spellID)
        if okName and type(name) == "string" then return name end
    end
    return "spell " .. tostring(spellID)
end

--- How the nodes of one tree are laid out, so the three specs can be told
--- apart: each column (by horizontal position) with its node count and the
--- name of its top talent, and every talent with points in it.
function Probe:Nodes(configID, nodes)
    if not Has("C_Traits.GetNodeInfo") then return end

    local columns, purchased = {}, {}
    for _, nodeID in ipairs(nodes) do
        local ok, info = pcall(C_Traits.GetNodeInfo, configID, nodeID)
        if ok and type(info) == "table" and type(info.posX) == "number" then
            local x = math.floor(info.posX + 0.5)
            local column = columns[x]
            if not column then
                column = { x = x, count = 0 }
                columns[x] = column
            end
            column.count = column.count + 1

            local y = tonumber(info.posY) or 0
            if not column.topY or y < column.topY then
                column.topY = y
                column.top = self:NodeName(configID, info)
            end

            local ranks = tonumber(info.ranksPurchased) or tonumber(info.currentRank) or 0
            if ranks > 0 then
                purchased[#purchased + 1] = ("%s %d at x%d"):format(
                    self:NodeName(configID, info) or ("node " .. tostring(nodeID)), ranks, x)
            end
        end
    end

    local sorted = {}
    for _, column in pairs(columns) do sorted[#sorted + 1] = column end
    table.sort(sorted, function(a, b) return a.x < b.x end)

    local parts = {}
    for _, column in ipairs(sorted) do
        parts[#parts + 1] = ("x%d: %d (%s)"):format(column.x, column.count, column.top or "?")
    end
    Line("  columns", #parts > 0 and table.concat(parts, "; ") or "no positions readable")
    Line("  spent in", #purchased > 0 and table.concat(purchased, "; ") or "nothing yet")
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

--- Every class this client knows, as class tokens, with any this addon has
--- no weights for marked. Forever may have classes classic did not.
function Probe:Classes()
    if not Has("C_CreatureInfo.GetClassInfo") then return "not readable" end

    local names = {}
    for id = 1, 30 do
        local ok, info = pcall(C_CreatureInfo.GetClassInfo, id)
        if ok and type(info) == "table" and type(info.classFile) == "string" then
            local token = info.classFile
            if not ns.Weights.SPECS[token] then token = token .. " (no weights)" end
            names[#names + 1] = token
        end
    end
    return #names > 0 and table.concat(names, ", ") or "none listed"
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

    if Has("C_SpecializationInfo.GetSpecialization") then
        local ok, index = pcall(C_SpecializationInfo.GetSpecialization)
        Line("spec index", ok and tostring(index) or "raised")
    end

    self:Traits()

    local Weights = ns.Weights
    Line("class", Weights:PlayerClass() or "unknown")
    Line("classes", self:Classes())

    local points = Weights:TreePoints(Weights:PlayerClass())
    if points then
        local parts = {}
        for tab, spent in ipairs(points) do parts[tab] = tostring(spent) end
        Line("points per spec", table.concat(parts, " / "))
    else
        Line("points per spec", "no talents to read")
    end

    local spec, why = Weights:CurrentSpec()
    Line("judged as", spec and (spec .. " (" .. why .. ")") or "no weights for this class")

    if ns.BagIcons then
        local frames, hooks = ns.BagIcons:Describe()
        Line("bag windows", frames)
        Line("bag hooks", hooks)
        Line("arrows showing", ns.BagIcons.lastShown or "bags not looked at yet")
    end
    if ns.Tooltip and ns.Tooltip.fired then
        local parts = {}
        for source, count in pairs(ns.Tooltip.fired) do
            parts[#parts + 1] = ("%s %d"):format(source, count)
        end
        Line("tooltip lines added", #parts > 0 and table.concat(parts, ", ") or "none yet")
    end

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
