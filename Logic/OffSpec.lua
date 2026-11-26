-- Blackthornes Equipment -- Logic/OffSpec.lua
-- Main Spec and Off Spec (the owner said build it from the mockup,
-- 2026-11-25).
--
-- A player who fights alone as one spec and tanks or heals in dungeons as
-- another picks an Off Spec beside the Main Spec. The Main Spec is the old
-- "Judge Gear As" pick (`charDB.spec`, never renamed). The Off Spec is saved
-- per character as `charDB.offSpec` (never rename it) and starts on None:
-- with None nothing here runs.
--
-- Gear is judged for the Off Spec by setting two things for a moment:
--   Weights.judgeAs  the spec Weights:CurrentSpec answers with, so every
--                    weights table, the hit cap and the Protection
--                    no-two-hander rule follow the Off Spec;
--   Items.wornAs     what Items:Equipped answers with: the best piece the
--                    character owns for the Off Spec in each slot, worn or
--                    in the bags (the outfit). So a gain is measured against
--                    that, and a tank set carried in the bags counts.
-- The finder keeps a second set of verdicts for the Off Spec, swapped in
-- with them (Finder:SwapJudging). Enter and Leave always pair up; a scan
-- sliced over frames leaves before each pause and enters again after, so
-- nothing else ever sees the Off Spec. The worker settles any left open by
-- an error (Worker's Pump calls Settle).
--
-- What stays on the Main Spec: putting gear on (Logic/Wear.lua), the upgrade
-- quest, the small panel, Upgrade Done!, the character sheet's arrows, and
-- every answer Tradeskills and Butler ask for.

local _, ns = ...

local OffSpec = ns.NewModule("OffSpec")

local Items = ns.Items
local Weights = ns.Weights

local FIRST_BAG, LAST_BAG = 0, 4
-- An outfit with a piece whose stats were not in yet is made again after
-- this many seconds, not on every call.
local PARTIAL_WAIT = 2

local depth = 0
local saved = {}
-- Kept outfits by spec, the Off Spec's and the Main Spec's (for Switch
-- Gear, Logic/SwitchGear.lua):
-- [spec] = { key, slots = { [slot] = link or false }, owned = { [link] = true }, partial, at }
local outfits = {}

local function Now()
    local clock = rawget(_G, "GetTime")
    if type(clock) ~= "function" then return 0 end
    local ok, now = pcall(clock)
    return ok and type(now) == "number" and now or 0
end

--------------------------------------------------------------------------------
-- The pick
--------------------------------------------------------------------------------

--- The Off Spec saved for this character, or nil for None. A pick the class
--- has no weights for, or the same spec the Main Spec judges as, counts as
--- None, so no work is done twice.
function OffSpec:Key()
    local db = ns.charDB
    local key = type(db) == "table" and db.offSpec or nil
    if type(key) ~= "string" then return nil end
    local class = Weights:PlayerClass()
    local specs = class and Weights.SPECS[class]
    if not (specs and specs[key]) then return nil end
    if key == Weights:MainSpec() then return nil end
    return key
end

--- Is an Off Spec picked?
function OffSpec:On()
    return self:Key() ~= nil
end

--- The Off Spec's name ("Protection"), or nil for None.
function OffSpec:Name()
    local key = self:Key()
    if not key then return nil end
    return Weights:SpecName(Weights:PlayerClass(), key)
end

--- Pick the Off Spec: a spec key, or nil / "none" for None.
function OffSpec:Set(key)
    local db = ns.charDB
    if type(db) ~= "table" then return end
    if key == "none" or key == "" then key = nil end
    if db.offSpec == key then return end
    db.offSpec = key
    self:Forget()
    -- Every list and arrow can change with it.
    Weights:Changed()
end

--------------------------------------------------------------------------------
-- The outfit: the best piece owned for the Off Spec in each slot
--------------------------------------------------------------------------------

--- Forget the outfit (bags, gear worn, level or weights changed).
function OffSpec:Forget()
    outfits = {}
end

local function Score(link, weights)
    local ok, score = pcall(ns.Compare.ScoreOf, ns.Compare, link, weights)
    if ok then return score end
    return nil
end

-- Can the Off Spec wear this carried piece now? Judged against what is
-- worn, for the class, level, training and the Protection rule.
local function WearsNow(link)
    local ok, result = pcall(ns.Compare.Judge, ns.Compare, link)
    if not ok or type(result) ~= "table" then return nil end
    if result.verdict == "cantuse" or result.level or result.train or result.skill then return false end
    return true
end

local function Better(a, b)
    if not b then return true end
    return (a.score or 0) > (b.score or 0)
end

--- Work the outfit out. Must run with Weights.judgeAs set and Items.wornAs
--- not set.
local function MakeOutfit(weights)
    local Compare = ns.Compare
    local SLOTS = Compare.SLOTS
    -- The spec judged as now: the Off Spec inside Enter, else the Main.
    local shieldTank = Weights:ShieldTank(Weights:PlayerClass(), (Weights:CurrentSpec()))
    local canDual = Weights:CanDualWield(Weights:PlayerClass(), Items:PlayerLevel())
    local slots, owned, partial = {}, {}, false

    -- Every piece owned, worn first, then the bags.
    local pieces = {}
    for slot = 1, 19 do
        local link = Items:Equipped(slot)
        if link then pieces[#pieces + 1] = { link = link, worn = slot } end
    end
    for bag = FIRST_BAG, LAST_BAG do
        for bagSlot = 1, Items:BagSize(bag) do
            local link = Items:InBag(bag, bagSlot)
            if link then pieces[#pieces + 1] = { link = link, where = bag * 100 + bagSlot } end
        end
    end

    local best = {}  -- [slot] = { piece, ... } best first, for pairs two
    local mains, offs, twoHands = {}, {}, {}
    for _, piece in ipairs(pieces) do
        local info = Items:Info(piece.link)
        local fits = info and SLOTS[info.equipLoc]
        if fits then
            local wears = piece.worn and true or WearsNow(piece.link)
            if wears == nil then partial = true end
            local score = wears and Score(piece.link, weights)
            if wears and not score then
                partial = true
                -- A worn piece keeps its place while its stats load.
                if piece.worn then score = 0 end
            end
            if wears and score then
                piece.score, piece.loc = score, info.equipLoc
                local loc = info.equipLoc
                if fits[1] == 16 or fits[1] == 17 then
                    if loc == "INVTYPE_2HWEAPON" then
                        if not shieldTank then twoHands[#twoHands + 1] = piece end
                    else
                        if loc == "INVTYPE_WEAPON" or loc == "INVTYPE_WEAPONMAINHAND" then
                            mains[#mains + 1] = piece
                        end
                        if loc == "INVTYPE_SHIELD" or loc == "INVTYPE_HOLDABLE"
                            or (canDual and (loc == "INVTYPE_WEAPON" or loc == "INVTYPE_WEAPONOFFHAND")) then
                            offs[#offs + 1] = piece
                        end
                    end
                else
                    local list = best[fits[1]] or {}
                    best[fits[1]] = list
                    list[#list + 1] = piece
                end
            end
        end
    end

    local function Sort(list)
        table.sort(list, function(a, b)
            if (a.score or 0) ~= (b.score or 0) then return (a.score or 0) > (b.score or 0) end
            -- What is worn wins a tie, so nothing swaps for no gain.
            if (a.worn ~= nil) ~= (b.worn ~= nil) then return a.worn ~= nil end
            return (a.where or a.worn or 0) < (b.where or b.worn or 0)
        end)
        return list
    end

    for first, list in pairs(best) do
        Sort(list)
        slots[first] = list[1].link
        if first == 11 or first == 13 then
            -- The second ring or trinket: the next best that isn't the same
            -- piece (a link worn twice is two pieces, two worn slots).
            local second
            for index = 2, #list do
                local piece = list[index]
                if piece ~= list[1] then second = piece break end
            end
            slots[first + 1] = second and second.link or false
        end
    end

    -- The hands: the best two-hander alone, or the best main hand and off
    -- hand together, whichever scores more.
    Sort(mains)
    Sort(offs)
    Sort(twoHands)
    local main = mains[1]
    local off
    for _, piece in ipairs(offs) do
        if piece ~= main then off = piece break end
    end
    local pair = (main and main.score or 0) + (off and off.score or 0)
    local two = twoHands[1]
    if two and (not (main or off) or two.score > pair) then
        slots[16], slots[17] = two.link, false
    else
        slots[16] = main and main.link or false
        slots[17] = off and off.link or false
    end

    for slot = 1, 19 do
        if slots[slot] == nil then slots[slot] = Items:Equipped(slot) or false end
        if slots[slot] then owned[slots[slot]] = true end
    end
    return slots, owned, partial
end

--- What the outfit was made from: worn gear, bags, level, weights, spec.
local function OutfitKey(spec)
    local parts = { spec, tostring(Weights.generation or 0), tostring(Items:PlayerLevel() or 0),
        Items:WornSignature() }
    for bag = FIRST_BAG, LAST_BAG do
        for bagSlot = 1, Items:BagSize(bag) do
            parts[#parts + 1] = Items.LinkKey(Items:InBag(bag, bagSlot)) or "-"
        end
    end
    return table.concat(parts, ";")
end

--- The outfit for the spec judged as now (Weights.judgeAs set), kept until
--- something it was made from changes.
local function Outfit(spec)
    local outfit = outfits[spec]
    local now = Now()
    -- With no clock (the tests) every call checks the key; in the game one
    -- frame's calls share one check.
    local timed = now > 0
    if outfit and outfit.spec == spec and (not outfit.partial or (timed and now - outfit.at < PARTIAL_WAIT))
        and ((timed and outfit.checkedAt == now) or outfit.key == OutfitKey(spec)) then
        outfit.checkedAt = now
        return outfit
    end
    local weights = Weights:ForPlayer()
    if not weights then return nil end
    local slots, owned, partial = MakeOutfit(weights)
    outfit = { spec = spec, key = OutfitKey(spec), slots = slots, owned = owned, partial = partial,
        at = now, checkedAt = now }
    outfits[spec] = outfit
    return outfit
end

--- The outfit's piece in each slot, { [slot] = link or false }, or nil for
--- None. For the tests and the probe.
function OffSpec:Outfit()
    local key = self:Key()
    if not key then return nil end
    local made
    self:Run(function() made = outfits[key] and outfits[key].slots end)
    return made
end

--- The Main Spec's outfit, made the same way: the best piece owned for the
--- Main Spec in each slot, worn or in the bags. For Switch Gear's way back
--- when it kept no note of what was worn. Nil while judging for the Off
--- Spec, or for a class with no weights.
function OffSpec:MainOutfit()
    if depth > 0 then return nil end
    local main = Weights:MainSpec()
    if not main then return nil end
    local keptJudge, keptWorn = Weights.judgeAs, Items.wornAs
    Weights.judgeAs, Items.wornAs = nil, nil
    local ok, made = pcall(Outfit, "main:" .. main)
    Weights.judgeAs, Items.wornAs = keptJudge, keptWorn
    if not ok then
        ns.Debug("offspec:", tostring(made))
        return nil
    end
    return made and made.slots or nil
end

--- Is this carried link one of the outfit's pieces?
function OffSpec:InOutfit(link)
    if not (link and self:On()) then return false end
    self:Run(function() end)
    local plain = Items.PlainLink(link)
    local outfit = outfits[self:Key()]
    return outfit ~= nil and outfit.owned ~= nil and plain ~= nil and outfit.owned[plain] == true
end

--------------------------------------------------------------------------------
-- Entering and leaving
--------------------------------------------------------------------------------

--- Judge as the Off Spec from here until Leave. `spec` defaults to the
--- saved pick; `real` keeps what is really worn (no outfit). Nested calls
--- count, and only the outermost one changes anything.
function OffSpec:Enter(spec, real)
    depth = depth + 1
    if depth > 1 then return true end
    spec = spec or self:Key()
    saved.judgeAs, saved.wornAs = Weights.judgeAs, Items.wornAs
    Weights.judgeAs = spec
    Items.wornAs = nil
    if spec and not real then
        local ok, made = pcall(Outfit, spec)
        if ok and made then Items.wornAs = made.slots end
    end
    local Finder = ns.Finder
    if Finder and Finder.SwapJudging then Finder:SwapJudging(true) end
    return true
end

function OffSpec:Leave()
    if depth <= 0 then return end
    depth = depth - 1
    if depth > 0 then return end
    local Finder = ns.Finder
    if Finder and Finder.SwapJudging then Finder:SwapJudging(false) end
    Weights.judgeAs, Items.wornAs = saved.judgeAs, saved.wornAs
end

--- Leave every Enter left open (a scan that hit an error mid-slice).
function OffSpec:Settle()
    while depth > 0 do self:Leave() end
end

--- Is the Off Spec being judged right now?
function OffSpec:Inside()
    return depth > 0
end

local function Finish(ok, ...)
    if not ok then
        ns.Debug("offspec:", tostring((...)))
        return nil
    end
    return ...
end

--- Run fn(...) judged as the Off Spec and hand back what it returns.
--- Errors are caught (nil comes back). Never yields.
function OffSpec:Run(fn, ...)
    self:Enter()
    return Finish(self:LeaveWith(pcall(fn, ...)))
end

--- Same as Run, but against what is really worn, not the outfit: for a
--- carried outfit piece, to say how much it beats the gear on now.
function OffSpec:RunReal(fn, ...)
    self:Enter(nil, true)
    return Finish(self:LeaveWith(pcall(fn, ...)))
end

--- Leave, and hand back what was given.
function OffSpec:LeaveWith(...)
    self:Leave()
    return ...
end

--------------------------------------------------------------------------------
-- Answers
--------------------------------------------------------------------------------

--- An item's verdict for the Off Spec, or nil with None. A carried piece
--- of the outfit is measured against what is worn now (so the tank set in
--- the bags shows its arrow); anything else against the outfit.
function OffSpec:Judge(link, carried)
    if not (link and self:On()) then return nil end
    local Compare = ns.Compare
    local judge = carried and Compare.JudgeCarried or Compare.Judge
    if carried and self:InOutfit(link) then
        return self:RunReal(judge, Compare, link)
    end
    return self:Run(judge, Compare, link)
end

--- The Off Spec verdict, only when the item is an upgrade that can be worn
--- now for the Off Spec and not for the Main Spec: the blue arrow. `main`
--- is the Main Spec verdict when the caller has it.
function OffSpec:OnlyUpgrade(link, carried, main)
    if not self:On() then return nil end
    local Compare = ns.Compare
    if main == nil then
        local ok, judged = pcall(carried and Compare.JudgeCarried or Compare.Judge, Compare, link)
        main = ok and judged or nil
    end
    if Compare.WearableUpgrade(main) then return nil end
    local result = self:Judge(link, carried)
    if Compare.WearableUpgrade(result) then return result end
    return nil
end

--- The finder's kept Off Spec verdict for one item, judged now when there
--- is none: (best roll, ok, result), as Finder:JudgeOnce.
function OffSpec:JudgeOnce(itemID)
    local Finder = ns.Finder
    if not (Finder and self:On()) then return nil, false, nil end
    return self:Run(function()
        return Finder:JudgeOnce(Finder:Judged(), itemID)
    end)
end

--- One finder scan for the Off Spec, a slice at a time when `pause` is
--- given (it leaves the Off Spec at each pause and comes back after).
function OffSpec:Build(spec, ahead, pause)
    local Finder = ns.Finder
    if not pause then
        self:Enter(spec)
        local ok, found, why = pcall(Finder.Build, Finder, nil, ahead)
        self:Leave()
        if not ok then
            ns.Debug("offspec:", tostring(found))
            return nil, "error"
        end
        return found, why
    end
    local function Step()
        self:Leave()
        pause()
        self:Enter(spec)
    end
    self:Enter(spec)
    local found, why = Finder:Build(nil, ahead, Step)
    self:Leave()
    return found, why
end

function OffSpec:OnEnable()
    for _, event in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP" }) do
        ns.RegisterEvent(self, event, self.Forget)
    end
end
