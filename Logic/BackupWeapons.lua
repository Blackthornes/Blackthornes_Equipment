-- Blackthornes Equipment -- Logic/BackupWeapons.lua
-- The backup weapon set (the owner said build it from the mockup,
-- 2026-11-26). Many casters carry a one-hander and an off hand in case the
-- pair beats their staff.
--
-- Nothing is picked or saved by the player. While a two-hander is worn,
-- the backup set is the best main hand and the best off hand the character
-- owns (the carried bags, and its bank as last seen open); while a pair is
-- worn, it is the best two-hander owned. Only gear that can be worn now
-- counts (no level, training or weapon skill to wait on). Main Spec only.
--
-- What it fixes for everyone, with no switch (a wrong number):
--   * A new off hand or one-hander looked at while a two-hander is worn
--     was weighed against the whole two-hander, on its own. Now it is
--     weighed with the best partner owned (`Backup:WithPartner`), for the
--     tooltip ("Main Spec: +5% with ...").
--   * Find Upgrades pairs new pieces with owned ones (Finder:MakePairs reads
--     `Backup:Pieces`).
--   * A piece of the backup set is never offered for sale (BagIcons:Sells,
--     which Butler asks too).
-- Behind "Backup Weapon Set:" (`backupWeapons`, account wide, off unless
-- ticked; never rename it): the card on My Gear (UI/MyGear.lua) and the
-- banner when the backup set starts to beat what is worn.
--
-- Nothing here scans. The pieces are worked out from the bags and the
-- kept bank once, and again only after gear, bags, level or weights change.

local _, ns = ...
local L = ns.L

local Backup = ns.NewModule("BackupWeapons")

local Items = ns.Items
local Weights = ns.Weights
local Compare = ns.Compare

local MAIN_HAND, OFF_HAND = 16, 17
-- Seconds between the main hand and the off hand going on.
Backup.SETTLE = 0.4
-- How many of each kind are kept, so a piece looked at can skip itself.
local KEEP = 3
-- Within this many percent counts as the same, as Compare has it.
local SAME_WITHIN = 1

local MAIN_LOCS = { INVTYPE_WEAPON = true, INVTYPE_WEAPONMAINHAND = true }
local OFF_LOCS = { INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true, INVTYPE_WEAPONOFFHAND = true }
Backup.MAIN_LOCS, Backup.OFF_LOCS = MAIN_LOCS, OFF_LOCS

local function InCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

local function Key(link)
    return Items.LinkKey(link)
end

local function IDOf(link)
    return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

--- Is the card and banner switched on? Off unless ticked.
function Backup.On()
    return type(ns.db) == "table" and ns.db.backupWeapons == true
end

function Backup:SetOn(on)
    if type(ns.db) ~= "table" then return end
    ns.db.backupWeapons = on and true or nil
    self:Forget()
    -- Ticked now: what wins already is not news, so no banner for it.
    self.seen = nil
    self:Changed()
end

--------------------------------------------------------------------------------
-- What the character owns
--------------------------------------------------------------------------------

--- Every weapon and off-hand piece owned: { { link, where = "bags" or
--- "bank" } }. The bank as last seen open (Alts:ReadBank); no GUID, the
--- bags only.
function Backup:Owned()
    local out = {}
    for bag = 0, 4 do
        for slot = 1, Items:BagSize(bag) do
            local link = Items:InBag(bag, slot)
            if link then out[#out + 1] = { link = link, where = "bags" } end
        end
    end
    local Alts = ns.Alts
    local me = Alts and Alts.PlayerGUID and Alts.PlayerGUID()
    local note = me and Alts:Notes()[me]
    for _, entry in ipairs(type(note) == "table" and type(note.bank) == "table" and note.bank or {}) do
        local link = type(entry) == "table" and entry.link or entry
        if type(link) == "string" then out[#out + 1] = { link = link, where = "bank" } end
    end
    return out
end

--- Can this piece go on now? Judged as the bags are: not for another
--- class, no level, training or weapon skill to wait on.
local function WearsNow(link)
    local ok, result = pcall(Compare.Judge, Compare, link)
    if not ok or type(result) ~= "table" then return false end
    if result.verdict == "cantuse" then return false end
    return not (result.level or result.train or result.skill)
end

local function ByScore(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return (a.key or "") < (b.key or "")
end

--- Forget what was worked out: gear, bags, level or weights changed.
function Backup:Forget()
    self.kept = nil
end

--- The owned pieces by kind, best first, a few of each: { mains, offs,
--- twos, weights }, each entry { link, where, score, key }. Nil while the
--- weights can't be read or a fishing pole is in hand.
function Backup:Pieces(weights)
    weights = weights or Weights:ForPlayer()
    if not weights then return nil end
    if Items.PoleInHand and Items:PoleInHand() then return nil end
    local generation = Weights.generation or 0
    local kept = self.kept
    if kept and kept.weights == weights and kept.generation == generation then return kept end

    local dual = Weights:CanDualWield(Weights:PlayerClass(), Items:PlayerLevel())
    local mains, offs, twos = {}, {}, {}
    local seen = {}
    for _, piece in ipairs(self:Owned()) do
        local info = Items:Info(piece.link)
        local loc = info and info.equipLoc
        local isMain, isOff = loc and MAIN_LOCS[loc], loc and (OFF_LOCS[loc] or (dual and loc == "INVTYPE_WEAPON"))
        local isTwo = loc == "INVTYPE_2HWEAPON"
        if (isMain or isOff or isTwo) and WearsNow(piece.link) then
            local score = Compare:ScoreOf(piece.link, weights)
            if type(score) == "number" then
                local key = Key(piece.link)
                -- Two copies of one piece count twice (a pair of daggers);
                -- the same copy seen in the bags and the kept bank once.
                local copy = (seen[key] or 0) + 1
                seen[key] = copy
                local entry = { link = piece.link, where = piece.where, score = score, key = key, copy = copy }
                if isMain then mains[#mains + 1] = entry end
                if isOff then offs[#offs + 1] = entry end
                if isTwo then twos[#twos + 1] = entry end
            end
        end
    end
    for _, list in ipairs({ mains, offs, twos }) do
        table.sort(list, ByScore)
        for i = #list, KEEP + 1, -1 do list[i] = nil end
    end
    kept = { mains = mains, offs = offs, twos = twos, weights = weights, generation = generation }
    self.kept = kept
    return kept
end

--- The best of a list that is not `skip` (a link): the piece looked at
--- can't be its own partner.
local function BestBut(list, skip)
    local skipKey = skip and Key(skip)
    for _, entry in ipairs(list or {}) do
        if not skipKey or entry.key ~= skipKey then return entry end
    end
    return nil
end

--------------------------------------------------------------------------------
-- The backup set
--------------------------------------------------------------------------------

--- The worn hands and what they are worth: mode "pair" while a two-hander
--- is worn (the backup is a main hand and off hand), "two" while one-handers
--- are (the backup is a two-hander). Nil otherwise.
local function Worn(weights)
    local main = Items:Equipped(MAIN_HAND)
    local info = main and Items:Info(main)
    if not info then return nil end
    local score = Compare:ScoreOf(main, weights)
    if type(score) ~= "number" then return nil end
    if info.equipLoc == "INVTYPE_2HWEAPON" then
        return { mode = "pair", main = main, score = score }
    end
    if not MAIN_LOCS[info.equipLoc] then return nil end
    local off = Items:Equipped(OFF_HAND)
    if off then
        local offScore = Compare:ScoreOf(off, weights)
        if type(offScore) ~= "number" then return nil end
        score = score + offScore
    end
    return { mode = "two", main = main, off = off, score = score }
end

--- The backup set now: { mode, main, off (pieces, for "pair"), two (a
--- piece, for "two"), score, against (what is worn), percent, beats,
--- worn (the worn main hand's link) }, or nil when there is none.
function Backup:Set()
    local weights, spec = Weights:ForPlayer()
    if not weights then return nil end
    -- A shield tank wants a shield there; a two-hander is not for it.
    if Weights:ShieldTank(Weights:PlayerClass(), spec) then return nil end
    local worn = Worn(weights)
    if not worn then return nil end
    local pieces = self:Pieces(weights)
    if not pieces then return nil end
    local set = { mode = worn.mode, against = worn.score, worn = worn.main }
    if worn.mode == "pair" then
        -- The best two different copies: the strongest main hand with the
        -- best off hand left, or the other way round when one dagger is
        -- best for both.
        local best
        for _, main in ipairs(pieces.mains) do
            for _, off in ipairs(pieces.offs) do
                if not (main.key == off.key and main.copy == off.copy) then
                    local total = main.score + off.score
                    if not best or total > best.score then best = { main = main, off = off, score = total } end
                end
            end
        end
        if not best then return nil end
        set.main, set.off, set.score = best.main, best.off, best.score
    else
        local two = pieces.twos[1]
        if not two then return nil end
        set.two, set.score = two, two.score
    end
    if set.against > 0 then
        set.percent = (set.score - set.against) / set.against * 100
        set.beats = set.percent >= SAME_WITHIN
    else
        set.beats = set.score > 0
    end
    return set
end

--- Is this link a piece of the backup set? Kept, never sold, while the
--- switch is on or while the set beats what is worn (a warrior's spare
--- shield beside a big axe still sells with the switch off).
function Backup:InSet(link)
    local key = type(link) == "string" and Key(link)
    if not key then return false end
    local ok, set = pcall(self.Set, self)
    if not (ok and set) then return false end
    if not (Backup.On() or set.beats) then return false end
    for _, piece in ipairs({ set.main, set.off, set.two }) do
        if piece and piece.key == key then return true end
    end
    return false
end

--- Are both pieces in the bags, so they can go on?
function Backup.Carried(set)
    if type(set) ~= "table" then return false end
    for _, piece in ipairs({ set.main, set.off, set.two }) do
        if piece.where ~= "bags" or not (ns.Wear and ns.Wear.Find(piece.link)) then return false end
    end
    return true
end

--------------------------------------------------------------------------------
-- A new piece with its partner
--------------------------------------------------------------------------------

--- A main hand or off hand judged while a two-hander is worn, weighed
--- with the best partner owned for the other hand against the two-hander.
--- Returns a new verdict with `partner` ({ link, where }), or nil when
--- there is no partner to weigh it with (the verdict stands).
function Backup:WithPartner(link, result)
    if type(result) ~= "table" or result.partner or type(link) ~= "string" then return nil end
    if result.slot ~= MAIN_HAND and result.slot ~= OFF_HAND then return nil end
    local verdict = result.verdict
    if verdict ~= "upgrade" and verdict ~= "downgrade" and verdict ~= "same" then return nil end
    local weights, spec = Weights:ForPlayer()
    if not weights or Weights:ShieldTank(Weights:PlayerClass(), spec) then return nil end
    local worn = Worn(weights)
    if not (worn and worn.mode == "pair") then return nil end
    local info = Items:Info(link)
    local loc = info and info.equipLoc
    if not loc then return nil end
    local pieces = self:Pieces(weights)
    if not pieces then return nil end
    local partner
    if result.slot == MAIN_HAND and MAIN_LOCS[loc] then
        partner = BestBut(pieces.offs, link)
    elseif result.slot == OFF_HAND or OFF_LOCS[loc] then
        partner = BestBut(pieces.mains, link)
    end
    if not partner then return nil end
    local mine = Compare:ScoreOf(link, weights)
    if type(mine) ~= "number" then return nil end

    local out = {}
    for key, value in pairs(result) do out[key] = value end
    out.score = mine + partner.score
    out.against = worn.score
    out.empty = false
    out.partner = { link = partner.link, where = partner.where }
    -- Why It's Better counts the partner's stats too (Compare:Why).
    out.added = { partner.link }
    out.replaced = { worn.main }
    out.weights = weights
    if worn.score > 0 then
        out.percent = (out.score - worn.score) / worn.score * 100
        if math.abs(out.percent) < SAME_WITHIN then
            out.verdict = "same"
        else
            out.verdict = out.percent > 0 and "upgrade" or "downgrade"
        end
    else
        out.percent = nil
        out.verdict = out.score > 0 and "upgrade" or "same"
    end
    return out
end

--- The words a partner is shown with: "in your bags" or "in your bank".
function Backup.WhereWords(where)
    return where == "bank" and L["in your bank"] or L["in your bags"]
end

--------------------------------------------------------------------------------
-- Put Them On
--------------------------------------------------------------------------------

local function Equipper()
    local item = rawget(_G, "C_Item")
    local fn = type(item) == "table" and item.EquipItemByName or nil
    if type(fn) ~= "function" then fn = rawget(_G, "EquipItemByName") end
    return type(fn) == "function" and fn or nil
end

--- The steps that put the backup set on: { { slot, link } }.
function Backup.Steps(set)
    if type(set) ~= "table" then return {} end
    if set.mode == "pair" then
        return { { slot = MAIN_HAND, link = set.main.link }, { slot = OFF_HAND, link = set.off.link } }
    end
    return { { slot = MAIN_HAND, link = set.two.link } }
end

--- Put the backup set on. In a fight it waits for the fight's end. True
--- when it started or was set to wait.
function Backup:PutOn()
    local set = self:Set()
    if not (set and Backup.Carried(set)) then return false end
    if self.queue then return true end
    if InCombat() then
        self.waiting = true
        ns.Print(L["They go on after the fight."])
        return true
    end
    if not Equipper() then
        ns.Print(ns.Wear and ns.Wear.NO_EQUIP or L["the game didn't put that on."])
        return false
    end
    self.queue = Backup.Steps(set)
    self:Next()
    return true
end

function Backup:Next()
    if not self.queue then return end
    if InCombat() then
        self.queue, self.waiting = nil, true
        return
    end
    local step = table.remove(self.queue, 1)
    if not step then
        self.queue = nil
        self:Forget()
        self:Changed()
        return
    end
    local equip = Equipper()
    if equip and Items:WornNow(step.slot) ~= step.link and ns.Wear and ns.Wear.Find(step.link) then
        local ok = pcall(equip, step.link, step.slot)
        if not ok then ns.Print(L["the game didn't put that on."]) end
    end
    local after = rawget(_G, "C_Timer") and _G.C_Timer.After
    if type(after) == "function" and Backup.SETTLE > 0 then
        after(Backup.SETTLE, function() Backup:Next() end)
    else
        self:Next()
    end
end

function Backup:FightOver()
    if not self.waiting then return end
    self.waiting = nil
    pcall(self.PutOn, self)
end

--------------------------------------------------------------------------------
-- The banner
--------------------------------------------------------------------------------

--- The set as one string: which pieces, and whether they win.
local function SetKey(set)
    if not set then return "" end
    local parts = { set.mode, Key(set.worn) or "" }
    for _, piece in ipairs({ set.main, set.off, set.two }) do parts[#parts + 1] = piece.key end
    return table.concat(parts, ";")
end
Backup.SetKey = SetKey

--- "Sample Orb with Sample Dagger: +5%" or "Sample Staff: +5%".
function Backup.SetLine(set)
    local how = set.percent and ("%+d%%"):format(math.floor(set.percent + 0.5)) or L["better stats"]
    if set.mode == "pair" then
        local first, second = set.off, set.main
        return L.Format("%s with %s: %s", Items.ShowLink(first.link), Items.ShowLink(second.link), how)
    end
    return Items.ShowLink(set.two.link) .. ": " .. how
end

--- Look again after a change. With the switch on, a banner says so once
--- when the backup set starts to beat what is worn. The first look after
--- logging in only notes what is so.
function Backup:Check()
    if not Backup.On() then return end
    local ok, set = pcall(self.Set, self)
    if not ok then set = nil end
    local winning = set and set.beats and Backup.Carried(set) and SetKey(set) or ""
    local before = self.seen
    self.seen = winning
    if before == nil or winning == "" or winning == before then return end
    self.quiet = self.quiet or {}
    if self.quiet[winning] or InCombat() then return end
    self:Banner(set, winning)
end

function Backup:Banner(set, key)
    local Toast = ns.Toast
    if not Toast then return false end
    return Toast:Show({
        title = L["BACKUP WEAPON SET"],
        line = L.Format("Your backup set beats your %s.", Items.ShowLink(set.worn)),
        text = Backup.SetLine(set),
        icon = (set.off or set.two).link,
        always = true,
        actions = {
            { text = L["Put Them On"], fn = function() Backup:PutOn() end },
            { text = L["Not Now"], fn = function()
                Backup.quiet = Backup.quiet or {}
                Backup.quiet[key] = true
            end },
        },
    })
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

--- Something changed: forget, look once for a burst, and draw the card.
function Backup:Soon()
    self:Forget()
    if self.pending then return end
    self.pending = true
    local after = rawget(_G, "C_Timer") and _G.C_Timer.After
    local function Go()
        Backup.pending = false
        Backup:Check()
        Backup:Changed()
    end
    if type(after) == "function" then after(0.5, Go) else Go() end
end

--- Draw My Gear's card again, if it shows.
function Backup:Changed()
    local MyGear = ns.MyGear
    if MyGear and MyGear.PaintBackup then pcall(MyGear.PaintBackup, MyGear) end
end

function Backup:OnEnable()
    for _, event in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED", "PLAYER_LEVEL_UP",
        "TRAIT_CONFIG_UPDATED", "PLAYER_ENTERING_WORLD" }) do
        ns.RegisterEvent(self, event, function() Backup:Soon() end)
    end
    ns.RegisterEvent(self, "PLAYER_REGEN_ENABLED", function() Backup:FightOver() end)
end

Backup.IDOf = IDOf
