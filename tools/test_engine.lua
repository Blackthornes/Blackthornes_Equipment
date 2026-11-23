-- The speed engine: how much work a set of events costs. Each check counts
-- the work (items sorted, items judged, sources worked out, timers made),
-- so a change that brings the old cost back fails here.
--
--   the gear list sorts each item once a session, on the frame worker
--   a gear swap judges again only the slot that changed
--   a piece with hit, or a set piece, reaches the verdicts that lean on it
--   where an item comes from is worked out only for upgrades
--   the worker rests calm jobs (the gear list) during a fight
--   the minimap button listens for a resize in place of a clock

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("engine")

local ARMOR, WEAPON, CLOTH, LEATHER, MAIL, PLATE, MACE = 4, 2, 1, 2, 3, 4, 4
local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end
local function Piece(loc, n, subclass) return { loc = loc, class = ARMOR, subclass = subclass or LEATHER, stats = Agi(n) } end

local ITEMS = {
    ["item:800"] = Piece("INVTYPE_HEAD", 5),       -- worn at the start
    ["item:801"] = Piece("INVTYPE_HEAD", 6),       -- put on later
    ["item:802"] = { loc = "INVTYPE_HEAD", class = ARMOR, subclass = LEATHER,
        stats = { ITEM_MOD_AGILITY_SHORT = 6, ITEM_MOD_HIT_RATING_SHORT = 10 } },
    ["item:900"] = Piece("INVTYPE_CHEST", 10),     -- worn
    ["item:1001"] = Piece("INVTYPE_CHEST", 15),
    ["item:1002"] = Piece("INVTYPE_CHEST", 20),
    ["item:1003"] = Piece("INVTYPE_CHEST", 3),     -- worse than what is worn
    ["item:1101"] = Piece("INVTYPE_HEAD", 8),
    ["item:1102"] = Piece("INVTYPE_HEAD", 12),
    ["item:1103"] = Piece("INVTYPE_HEAD", 2),      -- worse
    ["item:1201"] = Piece("INVTYPE_LEGS", 5),
    ["item:1301"] = Piece("INVTYPE_CHEST", 40, PLATE),   -- a hunter never wears plate
    ["item:1302"] = Piece("INVTYPE_CHEST", 40),          -- kept to mages by the data
    ["item:1304"] = Piece("INVTYPE_CHEST", 40, MAIL),    -- mail: later, the finder's to say
    ["item:1305"] = { loc = "INVTYPE_WEAPON", class = WEAPON, subclass = MACE, stats = Agi(9) },
    ["item:1306"] = { loc = "INVTYPE_BAG", class = 1, subclass = 0 },   -- not gear
    ["item:1401"] = { loc = "INVTYPE_FINGER", class = ARMOR, subclass = 0,
        stats = { ITEM_MOD_HIT_RATING_SHORT = 10 } },
    ["item:1501"] = Piece("INVTYPE_HAND", 4),      -- a set piece
    ["item:1502"] = Piece("INVTYPE_FEET", 4),      -- the set's other piece, put on later
}

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitRace = function() return "Human", "Human", 1 end
local level = 20
env.InstallItems(ITEMS, { [1] = "item:800", [5] = "item:900" }, {}, level)
_G.UnitLevel = function() return level end
ns.ItemSetData = { SETS = { [1] = { items = { 1501, 1502 }, b = { [2] = { agility = 20 } }, name = "Wolf" } } }

local S = ns.Sources
ns.Crafts.ITEMS = {}
ns.RollData.ITEMS = {}
S.ZONES = { [12] = "Elwynn Forest" }
S.NPCS = { [1] = { "Corina Steele", 12, 41.5, 65.9, "A" } }
S.QUESTS, S.DUNGEONS, S.BOSSES, S.FOREVER = {}, {}, {}, {}
S.ITEMS = {}
local function Sold(id, classMask) S.ITEMS[id] = { 15, 15, classMask or 0, 0, 100, v = { 1, 0 } } end
for _, id in ipairs({ 1001, 1002, 1003, 1101, 1102, 1103, 1201, 1301, 1304, 1305, 1306, 1401, 1501 }) do Sold(id) end
Sold(1302, 128)   -- mages only

local Finder, Compare, GearList, Worker = ns.Finder, ns.Compare, ns.GearList, ns.Worker
suite.check("the test's hunter weighs hit", ns.Weights.HitKind(ns.Weights:ForPlayer()) ~= nil)

local judges, sources = 0, 0
local realJudge, realSources = Compare.Judge, Finder.SourcesFor
Compare.Judge = function(...) judges = judges + 1 return realJudge(...) end
Finder.SourcesFor = function(...) sources = sources + 1 return realSources(...) end
local function Scan()
    judges, sources = 0, 0
    return Finder:Scan()
end

--- A scan as one string: each slot's picks with their percent, and where
--- the first source is.
local function Picture(found)
    local lines = {}
    for slot = 1, 19 do
        for _, pick in ipairs(found.all[slot] or {}) do
            lines[#lines + 1] = ("%d:%d:%s:%.3f:%s:%s"):format(slot, pick.itemID,
                tostring(Finder.Shown(pick.result)), pick.gain or 0,
                tostring(pick.result.setChange), tostring(pick.sources[1] and pick.sources[1].name))
        end
    end
    return table.concat(lines, " ")
end

--- Does the scan kept from earlier work match one made from nothing?
local function MatchesFresh(found)
    local kept = Picture(found)
    local count, sorted = judges, GearList.sorted
    Finder.judged = nil
    GearList:Forget()
    local fresh = Picture(Finder:Scan())
    -- Put the counts back; the next scan reads what this fresh one kept.
    judges, GearList.sorted = count, sorted
    return kept == fresh, kept .. "  ~=  " .. fresh
end

--------------------------------------------------------------------------------
-- The frame worker
--------------------------------------------------------------------------------

local frames, realAfter = {}, _G.C_Timer.After
_G.C_Timer.After = function(_, fn) frames[#frames + 1] = fn end
local function RunFrames(most)
    local run = 0
    while #frames > 0 and run < (most or 500) do
        table.remove(frames, 1)()
        run = run + 1
    end
    return run
end

local fighting = false
_G.InCombatLockdown = function() return fighting end

do
    local calmDone, plainDone = false, false
    fighting = true
    Worker:Run(function(pause) for _ = 1, 100 do pause() end return "calm" end,
        function(found) calmDone = found end, true)
    Worker:Run(function(pause) for _ = 1, 100 do pause() end return "plain" end,
        function(found) plainDone = found end)
    suite.check("a job starts on a later frame, not at once", plainDone == false and #frames == 1)
    local run = RunFrames()
    suite.check("a job takes several frames", run > 2, run)
    suite.check("in a fight a plain job still finishes", plainDone == "plain", tostring(plainDone))
    suite.check("and a calm job rests", calmDone == false and Worker.Count() == 1, Worker.Count())
    suite.check("with no frame used while it rests", #frames == 0, #frames)
    fighting = false
    Worker.FightOver()
    RunFrames()
    suite.check("when the fight ends the calm job goes on", calmDone == "calm" and Worker.Count() == 0,
        tostring(calmDone))

    local saw
    Worker:Run(function() error("broken") end, function(found, why) saw = why end)
    RunFrames()
    suite.check("a job that breaks is handed over with why", saw == "error", tostring(saw))
end

--------------------------------------------------------------------------------
-- The gear list
--------------------------------------------------------------------------------

local player = Finder:Player()
suite.check("plate is never for a hunter", GearList:State(1301, player) == false)
suite.check("gear the data keeps to another class is never", GearList:State(1302, player) == false)
suite.check("what is not gear is never", GearList:State(1306, player) == false)
suite.check("mail stays in: the finder says when", GearList:State(1304, player) == "INVTYPE_CHEST")
suite.check("a weapon with no skill for it waits on the skill", GearList:State(1305, player) == "skill")
suite.check("leather is usable, by its slot", GearList:State(1101, player) == "INVTYPE_HEAD")
suite.check("an item the client does not know is not decided", GearList:State(1303, player) == nil)
suite.check("and is asked again", GearList:State(1303, player) == nil and GearList:Out(1303) == false)

GearList:Forget()
GearList.sorted = 0
local made = false
fighting = true
GearList:Make(function() made = true end)
RunFrames()
suite.check("the list is not made during a fight", not made and not GearList.ready and GearList.sorted == 0,
    GearList.sorted)
fighting = false
Worker.FightOver()
local listFrames = RunFrames()
suite.check("it is made once the fight ends", made and GearList.ready == true)
suite.check("every item in the data is sorted", GearList.sorted == 14, GearList.sorted)
local function Same(list, want)
    return table.concat(list, ",") == table.concat(want, ",")
end
suite.check("heads are listed for the head slot", Same(GearList:ForSlot(1), { 1101, 1102, 1103 }),
    table.concat(GearList:ForSlot(1), ","))
suite.check("chests for the chest, without plate or mage gear",
    Same(GearList:ForSlot(5), { 1001, 1002, 1003, 1304 }), table.concat(GearList:ForSlot(5), ","))
suite.check("a ring for both fingers", Same(GearList:ForSlot(11), { 1401 }) and Same(GearList:ForSlot(12), { 1401 }))
suite.check("the weapon waiting on a skill is not listed", #GearList:ForSlot(16) == 0)
suite.check("making it again does nothing", GearList:Make() == true and GearList.sorted == 14 and #frames == 0)
suite.check("it took at least one frame", listFrames >= 1, listFrames)

_G.C_Timer.After = realAfter

--------------------------------------------------------------------------------
-- A scan judges each item once and sorts none again
--------------------------------------------------------------------------------

local found = Scan()
-- Ten usable items in range: three chests, mail, three heads, legs, a ring, gloves.
suite.check("the first scan judges each usable item once", judges == 10, judges)
suite.check("and works out where each comes from once", sources == 10, sources)
suite.check("it finds the upgrades", found and found.count == 7
    and found.slots[1][1].itemID == 1102 and found.slots[5][1].itemID == 1002, found and found.count)
suite.check("no item is sorted again", GearList.sorted == 14, GearList.sorted)
suite.check("no slot waits for a look after a whole scan", not Finder:NeedsLook(1) and not Finder:NeedsLook(5))

found = Scan()
suite.check("a second scan judges nothing", judges == 0, judges)
-- Seven upgrades: two chests, two heads, legs, the ring, the gloves.
-- The three that are no upgrade (a worse chest and head, mail) cost a lookup.
suite.check("and looks up sources only for the upgrades", sources == 7, sources)
suite.check("with the same picks", found.count == 7 and found.slots[1][1].itemID == 1102)

--------------------------------------------------------------------------------
-- A swap looks again only at its own slot
--------------------------------------------------------------------------------

env.worn[1] = "item:801"
Finder:Judged()
suite.check("a new helm marks the head for a look", Finder:NeedsLook(1) == true)
suite.check("and no other slot", not Finder:NeedsLook(5) and not Finder:NeedsLook(7) and not Finder:NeedsLook(11))
found = Scan()
suite.check("the scan judges only the three heads again", judges == 3, judges)
suite.check("and shows what a scan from nothing shows", MatchesFresh(found))
suite.check("the head has had its look", not Finder:NeedsLook(1))
suite.check("the picks follow the new helm", found.slots[1][1].itemID == 1102 and #found.slots[1] == 2
    and found.slots[5][1].itemID == 1002)
found = Scan()
suite.check("and the scan after judges nothing", judges == 0, judges)

-- A helm with hit: hit counts against the cap with every other piece's
-- hit, so the ring with hit is judged again too. The chests are not.
-- The character sits just under the cap, so the helm's hit takes them
-- over it and the ring's hit is worth less.
local clock = 0
_G.GetTime = function() clock = clock + 2 return clock end
_G.GetCombatRatingBonus = function() return 0 end
_G.GetHitModifier = function() return env.worn[1] == "item:802" and 6 or 4.9 end
Finder.judged = nil
found = Scan()
local ringBefore = found.slots[11][1].gain
env.worn[1] = "item:802"
found = Scan()
suite.check("over the cap the ring's hit is worth less", found.slots[11][1].gain < ringBefore,
    found.slots[11][1].gain .. " against " .. ringBefore)
suite.check("a helm with hit judges the heads and the ring with hit", judges == 4, judges)
suite.check("with a helm with hit it shows what a scan from nothing shows", MatchesFresh(found))
env.worn[1] = "item:801"
found = Scan()
suite.check("and taking it off does the same", judges == 4, judges)
suite.check("and again with it off", MatchesFresh(found))

-- A set piece put on changes what the set's other piece is worth.
env.worn[8] = "item:1502"
ns.ItemSets:GearChanged()   -- PLAYER_EQUIPMENT_CHANGED tells the sets
found = Scan()
suite.check("a set piece put on judges the set's other piece again", judges == 1, judges)
suite.check("with the set piece on it shows what a scan from nothing shows", MatchesFresh(found))
suite.check("which now counts the bonus", (found.slots[10][1].result.setChange or 0) > 0,
    tostring(found.slots[10][1].result.setChange))

-- The same gear read again (an event with nothing changed) costs nothing.
for _ = 1, 5 do found = Scan() end
suite.check("five scans with nothing changed judge nothing", judges == 0, judges)

--------------------------------------------------------------------------------
-- What still judges everything again
--------------------------------------------------------------------------------

level = 21
found = Scan()
suite.check("a level judges everything again", judges == 10, judges)
suite.check("and still sorts nothing again", GearList.sorted == 14, GearList.sorted)

Finder:ForgetVerdicts()
suite.check("a skill learned sorts the set-aside weapon again", GearList:Out(1305) == false)
found = Scan()
suite.check("and judges everything again", judges == 10, judges)
suite.check("the weapon is still set aside without the skill", GearList:Out(1305) == true)

--------------------------------------------------------------------------------
-- In a fight the shared scan rests; a window's own scan still runs
--------------------------------------------------------------------------------

do
    frames = {}
    _G.C_Timer.After = function(_, fn) frames[#frames + 1] = fn end
    fighting = true
    Finder:MarkStale()
    local shared, own
    Finder:ScanInBackground(function(result) shared = result end)
    Finder:ScanSliced(nil, 0, function(result) own = result end)
    RunFrames()
    suite.check("in a fight the window's own scan finishes", own ~= nil)
    suite.check("the shared scan rests until the fight ends", shared == nil and Finder:Scanning())
    fighting = false
    ns.Worker.FightOver()
    RunFrames()
    suite.check("and finishes once it does", shared ~= nil and not Finder:Scanning())
    _G.C_Timer.After = realAfter
end

--------------------------------------------------------------------------------
-- The Dungeons and Training tabs (rework step 5) lean on the scan made
--------------------------------------------------------------------------------

do
    local builds, realBuild = 0, Finder.Build
    local tickers, realTicker = 0, _G.C_Timer.NewTicker
    _G.C_Timer.NewTicker = function(...) tickers = tickers + 1 return realTicker(...) end
    if not Finder:Fresh() then Finder:Scan() end
    suite.check("a whole scan is in hand", Finder:Fresh() ~= nil)
    Finder.Build = function(...) builds = builds + 1 return realBuild(...) end
    local Gear = ns.GearWindow
    Gear:Open("instances")
    suite.check("the Dungeons tab shows", ns.DungeonsTab:IsShown())
    suite.check("and starts no scan of its own", builds == 0, builds)
    judges = 0
    Gear:ShowTab("training")
    suite.check("the Training tab shows", ns.TrainingTab:IsShown())
    suite.check("and judges no gear", judges == 0 and builds == 0, judges .. " " .. builds)
    Gear:ShowTab("instances")
    ns.DungeonsTab:Draw()
    ns.DungeonsTab:SortBy("upgrades")
    suite.check("a second look at Dungeons judges nothing", judges == 0 and builds == 0, judges .. " " .. builds)
    suite.check("neither tab runs on a clock", tickers == 0, tickers)
    Gear:Close()
    Finder.Build = realBuild
    _G.C_Timer.NewTicker = realTicker
end

--------------------------------------------------------------------------------
-- No clock for the minimap button
--------------------------------------------------------------------------------

do
    local tickers, realTicker = 0, _G.C_Timer.NewTicker
    _G.C_Timer.NewTicker = function(...) tickers = tickers + 1 return realTicker(...) end
    local MB = ns.MinimapButton
    MB:OnEnable()
    suite.check("the minimap button starts no ticker", tickers == 0 and MB.ticker == nil, tickers)
    Minimap._width = 222
    Minimap:GetScript("OnSizeChanged")(Minimap)
    suite.check("a resized minimap moves the button", MB.lastMinimapWidth == 222, MB.lastMinimapWidth)

    -- A minimap that can't be listened to keeps the look every few seconds.
    local hook = Minimap.HookScript
    Minimap.HookScript = function() error("this minimap takes no hooks") end
    MB:OnEnable()
    suite.check("without the hook it falls back on the ticker", tickers == 1, tickers)
    Minimap.HookScript = hook
    _G.C_Timer.NewTicker = realTicker
end

suite.done()
