-- Blackthornes Equipment -- Logic/SwitchGear.lua
-- Switch Gear (the owner said build it from the mockup, 2026-11-26): one
-- button puts the Off Spec's gear on, and the same button puts the Main
-- Spec's gear back.
--
-- Nothing is saved or set up by the player, and the game's own gear sets
-- are never read or written. The Off Spec's pieces are the outfit
-- Logic/OffSpec.lua already works out: the best piece the character owns
-- for the Off Spec in each slot, worn or in the bags. On the way there,
-- what was worn in each slot that changes is noted per character in
-- `charDB.swapBack` ({ [slot] = link }, never rename it), so the way back
-- puts those very pieces on again. Without a note (the Off Spec gear was
-- put on by hand) the way back is the Main Spec's own outfit
-- (OffSpec:MainOutfit).
--
-- Which gear is on is worked out, not saved: the Off Spec's when no piece
-- of its outfit waits in the bags and the way back has something to do.
--
-- Pieces go on one at a time through the game's EquipItemByName, which
-- addons may call out of combat. In a fight nothing is tried: the swap
-- waits for the fight's end (PLAYER_REGEN_ENABLED), as Put Them On does.
-- Only the carried bags are used, never the bank. A slot is never left
-- empty: a piece is only ever swapped for another.
--
-- The dungeon door card ("Ask at Dungeon Doors:", `swapAtDoors`, account
-- wide, off unless ticked; never rename it): standing at a dungeon's door
-- (Logic/DungeonDoors.lua notes the spot every few seconds) while the Main
-- Spec's gear is on, a banner offers Put It On and Not Now.

local _, ns = ...
local L = ns.L

local SwitchGear = ns.NewModule("SwitchGear")

local Items = ns.Items

-- Seconds between one piece and the next, so the game has put the first on.
SwitchGear.SETTLE = 0.4
-- How near a door counts as at it, on the zone map (0 to 100).
SwitchGear.DOOR_NEAR = 3
-- After Not Now, the same door asks again only after this many seconds.
SwitchGear.QUIET = 600

local PAIRS = { [11] = 12, [13] = 14 }
local MAIN_HAND, OFF_HAND = 16, 17

local function InCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

local function Now()
    local ok, now = pcall(function() return _G.GetTime() + 0 end)
    return ok and now or 0
end

local function Equipper()
    local item = rawget(_G, "C_Item")
    local fn = type(item) == "table" and item.EquipItemByName or nil
    if type(fn) ~= "function" then fn = rawget(_G, "EquipItemByName") end
    return type(fn) == "function" and fn or nil
end

local function Store()
    local db = ns.charDB
    return type(db) == "table" and db or nil
end

--------------------------------------------------------------------------------
-- What would change
--------------------------------------------------------------------------------

--- Is this link carried in the bags?
local function Carried(link)
    return ns.Wear and ns.Wear.Find(link) ~= nil
end

--- The steps from what is worn to `target` ({ [slot] = link or false }):
--- { { slot, from = link or nil, to = link }, ... } in slot order. Rings and
--- trinkets count as a pair, so a ring worn on the other finger is not
--- moved. A slot the target leaves empty is left as it is.
function SwitchGear.Steps(target, only)
    local steps = {}
    if type(target) ~= "table" then return steps end
    local worn = {}
    for slot = 1, 19 do worn[slot] = Items:WornNow(slot) end
    -- A fishing pole in hand: the weapons stay out of it.
    local pole = Items.IsFishingPole and worn[MAIN_HAND] and Items:IsFishingPole(worn[MAIN_HAND]) == true
    local done = {}
    for slot = 1, 19 do
        if not done[slot] and (not only or only[slot]) then
            local partner = PAIRS[slot]
            if partner then
                done[partner] = true
                -- Each piece wanted that is not worn goes over a worn piece
                -- that is not wanted.
                local wanted = {}
                if target[slot] then wanted[#wanted + 1] = target[slot] end
                if target[partner] then wanted[#wanted + 1] = target[partner] end
                local spare = {}
                for _, link in ipairs(wanted) do spare[link] = (spare[link] or 0) + 1 end
                local free = {}
                for _, s in ipairs({ slot, partner }) do
                    local link = worn[s]
                    if link and (spare[link] or 0) > 0 then
                        spare[link] = spare[link] - 1
                    else
                        free[#free + 1] = s
                    end
                end
                for _, link in ipairs(wanted) do
                    if (spare[link] or 0) > 0 then
                        spare[link] = spare[link] - 1
                        local s = table.remove(free, 1)
                        if s and Carried(link) then
                            steps[#steps + 1] = { slot = s, from = worn[s], to = link }
                        end
                    end
                end
            elseif not (pole and (slot == MAIN_HAND or slot == OFF_HAND)) then
                local link = target[slot]
                if link and link ~= worn[slot] and Carried(link) then
                    steps[#steps + 1] = { slot = slot, from = worn[slot], to = link }
                end
            end
        end
    end
    table.sort(steps, function(a, b) return a.slot < b.slot end)
    return steps
end

--- The Off Spec's pieces, { [slot] = link or false }, or nil with Off Spec
--- on None.
function SwitchGear:OffTarget()
    local OffSpec = ns.OffSpec
    if not (OffSpec and OffSpec:On()) then return nil end
    return OffSpec:Outfit()
end

--- The way back: the pieces noted on the way there, while still carried,
--- else the Main Spec's own outfit. Also says which slots to look at.
function SwitchGear:MainTarget()
    local db = Store()
    local back = db and type(db.swapBack) == "table" and db.swapBack or nil
    if back and next(back) then
        local target, only = {}, {}
        for slot, link in pairs(back) do
            slot = tonumber(slot)
            if slot and type(link) == "string" then
                target[slot] = link
                only[slot] = true
                local partner = PAIRS[slot] or (slot == 12 and 11) or (slot == 14 and 13)
                if partner and only[partner] == nil then only[partner] = true end
            end
        end
        -- A pair's other piece stays as it is unless noted.
        for slot in pairs(only) do
            if target[slot] == nil then target[slot] = Items:WornNow(slot) or false end
        end
        return target, only
    end
    local OffSpec = ns.OffSpec
    return OffSpec and OffSpec:MainOutfit() or nil, nil
end

--- Where things stand: { on = "main" or "off", go = "off" or "main" or
--- nil, steps = { ... } }, or nil with Off Spec on None.
function SwitchGear:State()
    local off = self:OffTarget()
    if not off then return nil end
    local toOff = SwitchGear.Steps(off)
    if #toOff > 0 then return { on = "main", go = "off", steps = toOff } end
    local target, only = self:MainTarget()
    local toMain = SwitchGear.Steps(target, only)
    if #toMain > 0 then return { on = "off", go = "main", steps = toMain } end
    -- Both specs wear the same pieces: nothing to switch.
    return { on = "main", steps = {} }
end

--- Is a swap under way, or waiting for the fight to end?
function SwitchGear:Busy()
    return self.queue ~= nil or self.waiting ~= nil
end

--------------------------------------------------------------------------------
-- Putting it on
--------------------------------------------------------------------------------

--- Put the other spec's gear on (or `want`, "off" or "main"). In a fight
--- it waits for the fight's end. True when a swap was started or set to wait.
function SwitchGear:Go(want)
    local state = self:State()
    if not state then
        ns.Print(L["Pick an Off Spec first, on the My Gear tab."])
        return false
    end
    if self.queue then return true end
    local steps = state.steps
    if want and want ~= state.go then
        -- A swap cut short by a fight goes on the way it was going, even
        -- though half the pieces are on. Asked by name otherwise, the way
        -- already worn does nothing.
        if not self.resuming then return false end
        if want == "off" then
            steps = SwitchGear.Steps(self:OffTarget())
        else
            steps = SwitchGear.Steps(self:MainTarget())
        end
        if #steps == 0 then return false end
        state = { on = state.on, go = want, steps = steps }
    end
    if not state.go then return false end
    if InCombat() then
        self.waiting = state.go
        ns.Print(L["They go on after the fight."])
        self:Changed()
        return true
    end
    if not Equipper() then
        ns.Print(ns.Wear and ns.Wear.NO_EQUIP or L["the game didn't put that on."])
        return false
    end
    local db = Store()
    if state.go == "off" and db then
        -- Note what comes off, so the way back puts it on again. A note
        -- already kept (a swap cut short) keeps its pieces.
        local back = type(db.swapBack) == "table" and db.swapBack or {}
        for _, step in ipairs(state.steps) do
            if back[step.slot] == nil and step.from then back[step.slot] = step.from end
        end
        db.swapBack = back
    end
    self.going = state.go
    self.queue = state.steps
    self:Changed()
    self:Next()
    return true
end

--- Put the next piece on, then wait a moment before the one after.
function SwitchGear:Next()
    if not self.queue then return end
    if InCombat() then
        -- A fight began mid-swap: the rest waits for its end.
        self.waiting, self.queue = self.going, nil
        self:Changed()
        return
    end
    local step = table.remove(self.queue, 1)
    if not step then return self:Finish() end
    local equip = Equipper()
    if equip and Items:WornNow(step.slot) ~= step.to and Carried(step.to) then
        local ok = pcall(equip, step.to, step.slot)
        if not ok then ns.Print(L["the game didn't put that on."]) end
    end
    local after = rawget(_G, "C_Timer") and _G.C_Timer.After
    if type(after) == "function" and SwitchGear.SETTLE > 0 then
        after(SwitchGear.SETTLE, function() SwitchGear:Next() end)
    else
        self:Next()
    end
end

function SwitchGear:Finish()
    local going = self.going
    self.queue, self.going = nil, nil
    local db = Store()
    if going == "main" and db then
        -- Every noted piece that is back on is let go; one that would not go
        -- on stays noted for the next try.
        local back = type(db.swapBack) == "table" and db.swapBack or {}
        for slot, link in pairs(back) do
            if Items:WornNow(tonumber(slot) or 0) == link or not Carried(link) then back[slot] = nil end
        end
        db.swapBack = next(back) and back or nil
    end
    if ns.OffSpec then ns.OffSpec:Forget() end
    self:Changed()
end

--- After a fight: the swap that waited goes ahead.
function SwitchGear:FightOver()
    local want = self.waiting
    if not want then return end
    self.waiting = nil
    self.resuming = true
    pcall(self.Go, self, want)
    self.resuming = nil
end

--- Something changed that the button shows.
function SwitchGear:Changed()
    local MyGear = ns.MyGear
    if MyGear and MyGear.PaintSwitch then pcall(MyGear.PaintSwitch, MyGear) end
end

--------------------------------------------------------------------------------
-- The dungeon door card
--------------------------------------------------------------------------------

function SwitchGear:AskAtDoors()
    return type(ns.db) == "table" and ns.db.swapAtDoors == true
end

function SwitchGear:SetAskAtDoors(on)
    if type(ns.db) ~= "table" then return end
    ns.db.swapAtDoors = on and true or nil
end

-- Every door in a zone, worked out once per zone: { { key, x, y } }.
local doorsIn = {}

local function DoorsIn(zone)
    if doorsIn[zone] then return doorsIn[zone] end
    local list, seen = {}, {}
    local Doors = ns.DungeonDoors
    local function Add(key)
        if seen[key] or not Doors then return end
        seen[key] = true
        local spot = Doors:Spot(key)
        if spot and spot.zone == zone then list[#list + 1] = { key = key, x = spot.x, y = spot.y } end
    end
    for key in pairs(ns.FOREVER_DUNGEON_PLACES or {}) do Add(key) end
    for key in pairs(ns.Sources and ns.Sources.DUNGEONS or {}) do Add(key) end
    doorsIn[zone] = list
    return list
end

--- The door the spot stands at, by key, or nil.
function SwitchGear.DoorAt(spot)
    if type(spot) ~= "table" or type(spot.zone) ~= "string" then return nil end
    for _, door in ipairs(DoorsIn(spot.zone)) do
        if math.abs(door.x - spot.x) <= SwitchGear.DOOR_NEAR and math.abs(door.y - spot.y) <= SwitchGear.DOOR_NEAR then
            return door.key
        end
    end
    return nil
end

--- The dungeon's name, as the data has it.
local function DungeonName(key)
    local DQ = ns.DungeonQuests
    local dungeon = DQ and DQ.Dungeon(key)
    return dungeon and dungeon.name or ""
end

--- The spot outside was noted (Logic/DungeonDoors.lua): at a door with the
--- Main Spec's gear on, ask once.
function SwitchGear:NoteSpot(spot)
    if not self:AskAtDoors() or InCombat() or self:Busy() then return end
    local key = SwitchGear.DoorAt(spot)
    if not key then
        self.atDoor = nil
        return
    end
    if self.atDoor == key then return end
    self.atDoor = key
    self.quiet = self.quiet or {}
    if (self.quiet[key] or -math.huge) > Now() then return end
    local state = self:State()
    if not (state and state.go == "off" and #state.steps > 0) then return end
    self:AskAt(key, state)
end

function SwitchGear:AskAt(key, state)
    local Toast = ns.Toast
    if not Toast then return false end
    local name = ns.OffSpec and ns.OffSpec:Name() or ""
    local count = #state.steps
    return Toast:Show({
        title = DungeonName(key):upper(),
        line = L.Format("Put on your %s gear.", name),
        text = count == 1 and L["1 piece from your bags."] or L.Format("%d pieces from your bags.", count),
        icon = state.steps[1] and state.steps[1].to,
        always = true,
        actions = {
            { text = L["Put It On"], fn = function() SwitchGear:Go("off") end },
            { text = L["Not Now"], fn = function()
                SwitchGear.quiet = SwitchGear.quiet or {}
                SwitchGear.quiet[key] = Now() + SwitchGear.QUIET
            end },
        },
    })
end

--------------------------------------------------------------------------------
-- Start-up, the command and the key
--------------------------------------------------------------------------------

function SwitchGear:OnEnable()
    -- My Gear draws the row again on its own gear and bag events.
    ns.RegisterEvent(self, "PLAYER_REGEN_ENABLED", function() SwitchGear:FightOver() end)
end

-- The key under Options, Keybindings, AddOns (Bindings.xml).
_G.BINDING_NAME_BLACKTHORNESEQUIPMENT_SWITCHGEAR = L["Switch Gear"]

-- /beq swap
ns.RegisterCommand("swap", L["put on your Off Spec gear, or your Main Spec gear again"], function()
    SwitchGear:Go()
end)
