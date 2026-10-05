-- Blackthornes Equipment -- Logic/WeaponSkills.lua
-- Which weapon skills the character knows, and for a weapon their class can
-- learn but has not, where its weapon master is.
--
-- Two ways to ask, both inside a pcall: the spell each weapon skill gives
-- (C_SpellBook.IsSpellKnown, IsPlayerSpell, IsSpellKnown, whichever the
-- client has), and classic's skill list (GetSkillLineInfo). A skill either
-- way says known counts as known. Every character starts with at least one
-- weapon skill, so when neither way finds any the client is not answering
-- and nothing is said: a wrong "go learn this" is worse than none.

local _, ns = ...

local WeaponSkills = ns.NewModule("WeaponSkills")

local Items = ns.Items
local Weights = ns.Weights
local WeaponTrainers = ns.WeaponTrainers

local CLASS_WEAPON = 2

local SPELL_CALLS = { "C_SpellBook.IsSpellKnown", "IsPlayerSpell", "IsSpellKnown" }

--- Does any of the client's spell calls say this spell is known?
local function SpellKnown(spellID)
    for _, path in ipairs(SPELL_CALLS) do
        local known = Items.Call({ path }, spellID)
        if known == true then return true end
    end
    return false
end

--- The names in classic's skill list, as a set, or an empty set.
local function SkillLines()
    local names = {}
    local count = tonumber((Items.Call({ "GetNumSkillLines" }))) or 0
    for index = 1, count do
        local name = Items.Call({ "GetSkillLineInfo" }, index)
        local ok, copy = pcall(function()
            if type(name) == "string" then return name .. "" end
        end)
        if ok and copy then names[copy] = true end
    end
    return names
end

--- The weapon skills this character knows, by weapon subclass ID, or nil
--- when the client gives no answer at all.
function WeaponSkills:Known()
    local lines = SkillLines()
    local known, any = {}, false
    for subclassID, skill in pairs(WeaponTrainers.SKILLS) do
        local has = SpellKnown(skill.spell)
        for _, line in ipairs(skill.lines) do
            if lines[line] then has = true end
        end
        if has then
            known[subclassID] = true
            any = true
        end
    end
    if not any then return nil end
    return known
end

--- "Horde" or "Alliance", or nil.
function WeaponSkills:Faction()
    local faction = Items.Call({ "UnitFactionGroup" }, "player")
    local ok, copy = pcall(function()
        if faction == "Horde" or faction == "Alliance" then return faction .. "" end
    end)
    if ok then return copy end
    return nil
end

--- Where to learn the weapon skill an item needs, when this character's
--- class can learn it and has not.
-- @return the skill's name and a list of cities, or nil
function WeaponSkills:TrainerFor(link)
    local info = Items:Info(link)
    if not info or info.classID ~= CLASS_WEAPON then return nil end

    local skill = WeaponTrainers.SKILLS[info.subclassID]
    if not skill then return nil end

    local usable = Weights:CanUse(Weights:PlayerClass(), info.classID, info.subclassID, info.equipLoc)
    if not usable then return nil end

    local faction = self:Faction()
    if not faction then return nil end

    local known = self:Known()
    if not known or known[info.subclassID] then return nil end

    local cities = WeaponTrainers:Cities(faction, info.subclassID)
    if #cities == 0 then return nil end
    return skill.name, cities
end

--- "A", "A or B", "A, B or C".
local function List(cities)
    if #cities == 1 then return cities[1] end
    return table.concat(cities, ", ", 1, #cities - 1) .. " or " .. cities[#cities]
end

--- The tooltip line for an item, and its colour, or nil.
function WeaponSkills:Describe(link)
    local name, cities = self:TrainerFor(link)
    if not name then return nil end
    return ("Learn %s from the weapon master in %s"):format(name, List(cities)), "warn"
end
