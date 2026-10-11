-- Blackthornes Equipment -- Logic/Alts.lua
-- The player's other characters, so gear carried by one can be judged for
-- the rest (the owner asked 2026-10-11: "if an item you find is an upgrade
-- for another of your characters, butler should offer it as a mail").
--
-- Each character, when it plays, keeps a note of itself account wide in
-- BlackthornesEquipmentDB.characterGear[guid] (never rename it):
--
--   { class, level, spec, realm, faction, worn = { [slot] = link }, at }
--
-- Only what judging needs: no bags, no names (Butler names characters from
-- Tradeskills' record, by the same GUID). A character counts once it has
-- been played with this version.
--
-- Alts:BestFor(link) judges one item for every other character on the
-- same realm and side, with that character's class, spec, level and worn
-- gear, through the same scoring as the character playing
-- (Compare:ScoreOf), and answers the one it helps most.
--
-- Smooth play: the note is written once, 1 second after a burst of gear,
-- level or talent events, and is a handful of reads. Judging only reads
-- the notes and the per-link scores Compare keeps.

local _, ns = ...

local Alts = ns.NewModule("Alts")

local Items = ns.Items
local Weights = ns.Weights
local Compare = ns.Compare

Alts.SETTLE = 1

-- Every slot a judged item can go in.
local WORN_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }

-- Closer than this, in percent, is no upgrade (as Compare's SAME_WITHIN).
local SAME_WITHIN = 1

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local results = { pcall(fn, ...) }
    if not results[1] then return nil end
    return select(2, unpack(results))
end

--- A plain string from the client, or nil (a secret value reads as nil).
local function Text(value)
    local ok, copy = pcall(function()
        if type(value) == "string" and value ~= "" then return value .. "" end
    end)
    return ok and copy or nil
end

function Alts.PlayerGUID()
    return Text(Call(_G.UnitGUID, "player"))
end

function Alts.Realm()
    return Text(Call(_G.GetRealmName))
end

function Alts.Faction()
    return Text((Call(_G.UnitFactionGroup, "player")))
end

--- Every character's note, account wide.
function Alts:Notes()
    local db = ns.db
    if type(db) ~= "table" then return {} end
    if type(db.characterGear) ~= "table" then db.characterGear = {} end
    return db.characterGear
end

--- Write the character playing's note now.
function Alts:Record()
    self.settling = false
    local guid = self.PlayerGUID()
    local class = Weights:PlayerClass()
    local level = Items:PlayerLevel()
    if not (guid and class and level) then return false end

    local worn = {}
    for _, slot in ipairs(WORN_SLOTS) do
        worn[slot] = Items:Equipped(slot)
    end
    local spec = Weights:CurrentSpec()
    local note = {
        class = class,
        level = level,
        spec = spec,
        realm = self.Realm(),
        faction = self.Faction(),
        worn = worn,
        at = Call(_G.time),
    }
    self:Notes()[guid] = note
    self.version = (self.version or 0) + 1
    return true
end

--- Gear, a level or talents changed: write the note once the burst is over.
function Alts:Changed()
    if self.settling then return end
    self.settling = true
    C_Timer.After(self.SETTLE, function() Alts:Record() end)
end

--- The weaker score of what a character wears where this item would go,
--- by the note's worn gear (Compare:Against for the character playing).
-- @return against, empty, equipped
local function Against(note, link, info, weights)
    local slots = Compare.SLOTS[info.equipLoc]
    local worn = note.worn or {}

    local function Score(slot)
        local item = worn[slot]
        if not item then return 0, true end
        return Compare:ScoreOf(item, weights) or 0, false
    end
    local function Kind(slot)
        local item = worn[slot]
        local kind = item and Items:Info(item)
        return kind and kind.equipLoc
    end

    if info.equipLoc == "INVTYPE_WEAPON" then
        local from = Weights:DualWieldLevel(note.class)
        if from and (note.level or 0) >= from then
            local off, main = Kind(17), Kind(16)
            local offIsWeapon = off == "INVTYPE_WEAPON" or off == "INVTYPE_WEAPONOFFHAND"
            if offIsWeapon or (not worn[17] and worn[16] and main ~= "INVTYPE_2HWEAPON") then
                slots = { 16, 17 }
            end
        end
    end

    local weakest, empty = nil, true
    for _, slot in ipairs(slots) do
        if worn[slot] == link then return 0, false, true end
        local score, none = Score(slot)
        if not none then empty = false end
        if not weakest or score < weakest then weakest = score end
    end
    if info.equipLoc == "INVTYPE_2HWEAPON" and worn[17] then
        empty = false
        weakest = weakest + (Score(17))
    end
    if slots[1] == 17 and Kind(16) == "INVTYPE_2HWEAPON" then
        empty = false
        weakest = (Score(16))
    end
    return weakest or 0, empty, false
end

--- How one item does for one character's note: nil when it is no upgrade,
--- else { gain (whole percent, nil for an empty slot), level (when it can
--- only be worn later) }.
function Alts:Judge(note, link)
    if type(note) ~= "table" or not note.class then return nil end
    local info = Items:Info(link)
    if not info or not Compare.SLOTS[info.equipLoc] then return nil end

    local specs = Weights.SPECS[note.class]
    local spec = note.spec
    if not (specs and spec and specs[spec]) then spec = specs and specs.default end
    local weights = spec and Weights:Get(note.class, spec)
    if not weights then return nil end

    local usable, fromLevel = Weights:CanUse(note.class, info.classID, info.subclassID, info.equipLoc)
    if not usable then return nil end
    if info.equipLoc == "INVTYPE_WEAPONOFFHAND" then
        local learns = Weights:DualWieldLevel(note.class)
        if not learns then return nil end
        fromLevel = math.max(fromLevel or 0, learns)
    end

    local score = Compare:ScoreOf(link, weights)
    if not score or score <= 0 then return nil end
    local against, empty, equipped = Against(note, link, info, weights)
    if equipped then return nil end

    local result = {}
    local needs = math.max(info.minLevel or 0, fromLevel or 0)
    if needs > (note.level or 0) then result.level = needs end
    if empty then return result end
    if against > 0 then
        local percent = (score - against) / against * 100
        if percent < SAME_WITHIN then return nil end
        result.gain = math.floor(percent + 0.5)
        return result
    end
    if score > against then return result end
    return nil
end

--- The other character this item helps most: { key (its GUID), gain,
--- level }, or nil. Only characters on the same realm and side as the one
--- playing, so it can be mailed; an empty slot beats any percent, and an
--- upgrade to wear now beats one that waits on a level.
function Alts:BestFor(link)
    link = Items.PlainLink(link)
    if not link then return nil end
    local me = self.PlayerGUID()
    local realm, faction = self.Realm(), self.Faction()
    local best, bestKey
    for key, note in pairs(self:Notes()) do
        if key ~= me and type(note) == "table"
            and (not realm or not note.realm or note.realm == realm)
            and (not faction or not note.faction or note.faction == faction) then
            local result = self:Judge(note, link)
            if result then
                local rank = (result.level and 0 or 2) + (result.gain == nil and 1 or 0)
                local bestRank = best and ((best.level and 0 or 2) + (best.gain == nil and 1 or 0))
                if not best or rank > bestRank
                    or (rank == bestRank and (result.gain or 0) > (best.gain or 0))
                    or (rank == bestRank and (result.gain or 0) == (best.gain or 0) and key < bestKey) then
                    best, bestKey = result, key
                end
            end
        end
    end
    if not best then return nil end
    best.key = bestKey
    return best
end

function Alts:OnEnable()
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP",
        "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED" }) do
        ns.RegisterEvent(self, event, function() Alts:Changed() end)
    end
end
