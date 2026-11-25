-- The frame worker: big jobs done a small share of each frame.
--
-- A job that judges hundreds of items in one go freezes the game for a
-- moment. Handed to the worker, it runs for a few milliseconds a frame and
-- rests until the next. Every job shares the one frame's share, so two at
-- once (the upgrade quest's scan and the finder window's own) never make a
-- frame twice as long. A job marked `calm` rests while the character
-- fights and goes on when the fight ends.
--
-- The finder's scans ran this way before (Logic/Finder.lua); the worker is
-- that code moved here, so the gear list and later screens can use it too.

local _, ns = ...

local Worker = {}
ns.Worker = Worker

-- How long one frame's share may run, in milliseconds, and how many steps a
-- share takes on a client without a timer to measure with.
Worker.SLICE_MS = 4
Worker.SLICE_ITEMS = 40

-- The jobs under way, the one whose turn it is first.
local jobs = {}
-- Jobs that finished, waiting to be handed over at the start of the next
-- frame: what takes a job's answer (a window drawing its rows, the upgrade
-- quest picking) is work of its own, and no share is stacked on top of it.
local finished = {}
local pumping, queued = false, false
local sliceStarted, sliceCount

local function NoClock() return nil end

local function Clock()
    return ns.Perf and ns.Perf.Clock or NoClock
end

--- Is the character in a fight?
function Worker.InCombat()
    local fn = _G.InCombatLockdown
    if type(fn) ~= "function" then return false end
    local ok, fighting = pcall(fn)
    return ok and fighting == true
end

local function SliceSpent(clock)
    local now = clock()
    if now and sliceStarted then return now - sliceStarted >= Worker.SLICE_MS end
    return (sliceCount or 0) >= Worker.SLICE_ITEMS
end

--- Is there anything to do this frame? Calm jobs wait out a fight.
local function Due()
    if #finished > 0 then return true end
    if #jobs == 0 then return false end
    if not Worker.InCombat() then return true end
    for _, job in ipairs(jobs) do
        if not job.calm then return true end
    end
    return false
end

local Pump

local function PumpSoon()
    if queued or pumping or not Due() then return end
    queued = true
    _G.C_Timer.After(0, Pump)
end

--- One frame's share of the jobs under way.
Pump = function()
    queued = false
    if pumping then return end
    pumping = true
    local clock = Clock()
    local started = clock()
    sliceStarted, sliceCount = started, 0
    local handed = #finished > 0
    while finished[1] do
        local job = table.remove(finished, 1)
        local ok, err = pcall(job.finish, job.found, job.why)
        if not ok then ns.Debug("worker:", tostring(err)) end
    end
    local fighting = Worker.InCombat()
    -- Each job gets at most one turn a frame.
    local turns = #jobs
    while turns > 0 and jobs[1] and not handed do
        turns = turns - 1
        local job = table.remove(jobs, 1)
        if fighting and job.calm then
            -- Waits for the fight to end, at the back of the line.
            jobs[#jobs + 1] = job
        else
            local ok, found, why = coroutine.resume(job.worker)
            -- A slice that stopped on an error mid-way may have left the
            -- Off Spec entered (Logic/OffSpec.lua).
            if ns.OffSpec then ns.OffSpec:Settle() end
            if not ok then
                ns.Debug("worker:", tostring(found))
                job.found, job.why = nil, "error"
                finished[#finished + 1] = job
            elseif coroutine.status(job.worker) == "dead" then
                job.found, job.why = found, why
                finished[#finished + 1] = job
            else
                -- It stopped because the frame's share is used: to the back
                -- of the line, and the rest wait for the next frame.
                jobs[#jobs + 1] = job
                break
            end
            if SliceSpent(clock) then break end
        end
    end
    local ended = clock()
    if ns.Perf and started and ended then ns.Perf:Add("Finder:background slice", ended - started) end
    pumping = false
    PumpSoon()
end

--- Run `build(pause)` a share per frame and hand what it returns to
--- `finish(found, why)`. `build` calls `pause()` between its steps; that
--- rests until the next frame once this frame's share is used. With `calm`
--- the job also rests while the character fights. Without timers or
--- coroutines it runs at once.
function Worker:Run(build, finish, calm)
    local after = _G.C_Timer and _G.C_Timer.After
    local canYield = type(after) == "function" and type(coroutine) == "table"
    if not canYield then
        finish(build(nil))
        return
    end

    local clock = Clock()
    local function Pause()
        sliceCount = (sliceCount or 0) + 1
        if SliceSpent(clock) then coroutine.yield() end
    end
    jobs[#jobs + 1] = {
        worker = coroutine.create(function() return build(Pause) end), finish = finish,
        calm = calm and true or nil,
    }
    -- Its first share waits for the next frame: whatever asked for the job
    -- (a bag or gear event, the upgrade quest's own look) has its own work
    -- to do in this one.
    PumpSoon()
end

--- How many jobs are under way or waiting to be handed over.
function Worker.Count()
    return #jobs + #finished
end

--- The fight is over: calm jobs go on.
function Worker.FightOver()
    if type(_G.C_Timer) == "table" and type(_G.C_Timer.After) == "function" then PumpSoon() end
end

ns.RegisterEvent(Worker, "PLAYER_REGEN_ENABLED", Worker.FightOver)
