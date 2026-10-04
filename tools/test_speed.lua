-- Keeping the game smooth: the finder judges each item once until something
-- that changes a verdict happens, item answers nobody asked for set off no
-- scan, and /beq perf says what took longest when the game still hitches.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("speed")

local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end
local function Chest(n) return { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = Agi(n) } end

local ITEMS = {
    ["item:900"] = Chest(10),      -- worn
    ["item:901"] = Chest(50),      -- put on later
    ["item:1001"] = Chest(15),
    ["item:1002"] = Chest(20),
    ["item:1003"] = Chest(30),
}

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitRace = function() return "Human", "Human", 1 end
env.InstallItems(ITEMS, { [5] = "item:900" }, {}, 20)

local S = ns.Sources
ns.Crafts.ITEMS = {}
ns.RollData.ITEMS = {}
S.ZONES = { [12] = "Elwynn Forest" }
S.NPCS = { [1] = { "Corina Steele", 12, 41.5, 65.9, "A" } }
S.QUESTS, S.DUNGEONS, S.BOSSES, S.FOREVER = {}, {}, {}, {}
S.ITEMS = {
    [1001] = { 15, 15, 0, 0, 100, v = { 1, 0 } },
    [1002] = { 15, 15, 0, 0, 100, v = { 1, 0 } },
    [1003] = { 15, 15, 0, 0, 100, v = { 1, 0 } },
}

local Finder, Compare = ns.Finder, ns.Compare
local realJudge, judges = Compare.Judge, 0
Compare.Judge = function(...) judges = judges + 1 return realJudge(...) end

--------------------------------------------------------------------------------
-- Each item is judged once
--------------------------------------------------------------------------------

local found = Finder:Scan()
suite.check("the first scan finds the three upgrades", found and found.count == 3, found and found.count)
suite.check("and judges each once", judges == 3, judges)
judges = 0
for _ = 1, 10 do Finder:Scan() end
suite.check("ten more scans judge nothing again", judges == 0, judges)
found = Finder:Scan()
suite.check("and still find the same upgrades", found.count == 3 and found.slots[5][1].itemID == 1003)

env.worn[5] = "item:901"
judges = 0
found = Finder:Scan()
suite.check("new gear worn judges them again", judges == 3, judges)
suite.check("and none beats it now", found.count == 0, found.count)
env.worn[5] = "item:900"
Finder:Scan()

judges = 0
_G.UnitLevel = function() return 21 end
Finder:Scan()
suite.check("a level up judges them again", judges == 3, judges)

ns.Weights:Changed()
judges = 0
Finder:Scan()
suite.check("changed stat weights judge them again", judges == 3, judges)

judges = 0
Finder:ForgetVerdicts()
Finder:Scan()
suite.check("new talents or weapon skills judge them again", judges == 3, judges)

-- An item whose details have not arrived is asked again next time.
ITEMS["item:1004"] = nil
S.ITEMS[1004] = { 15, 15, 0, 0, 100, v = { 1, 0 } }
judges = 0
found = Finder:Scan()
suite.check("an item not loaded yet is waited on", found.waiting == 1, found.waiting)
suite.check("and asked for", Finder:Asked(1004) and not Finder:Asked(4242))
ITEMS["item:1004"] = Chest(40)
found = Finder:Scan()
suite.check("once loaded it is judged and listed", found.slots[5][1].itemID == 1004, found.slots[5][1].itemID)

--------------------------------------------------------------------------------
-- Item answers nobody asked for
--------------------------------------------------------------------------------

local Quest = ns.UpgradeQuest
ns.db.upgradeQuest = true
local updates = 0
local realUpdate = Quest.Update
Quest.Update = function(...) updates = updates + 1 return realUpdate(...) end
Quest.waiting, Quest.updating = false, false
for _ = 1, 20 do Quest:OnEvent("GET_ITEM_INFO_RECEIVED", 4242, true) end
suite.check("twenty answers about a chat link look at nothing", updates == 0, updates)
Quest:OnEvent("GET_ITEM_INFO_RECEIVED", 1004, true)
suite.check("an answer a scan asked for looks again", updates == 1, updates)
Quest.Update = realUpdate

--------------------------------------------------------------------------------
-- /beq perf
--------------------------------------------------------------------------------

local Perf = ns.Perf
local now = 0
_G.debugprofilestop = function() return now end

local listener = { moduleName = "Listener" }
ns.RegisterEvent(listener, "PLAYER_REGEN_ENABLED", function() now = now + 120 end)
ns.eventFrame:GetScript("OnEvent")(ns.eventFrame, "PLAYER_REGEN_ENABLED")
local row = Perf.rows["Listener on PLAYER_REGEN_ENABLED"]
suite.check("an event handler is timed", row and row.worst == 120 and row.runs == 1,
    row and row.worst)

local slow = { moduleName = "Slow" }
function slow:Work(ms) now = now + ms return "done" end
Perf:Wrap(slow, "Work")
suite.check("a wrapped method still answers", slow:Work(30) == "done")
slow:Work(250)
row = Perf.rows["Slow:Work"]
suite.check("and keeps its worst and its total", row.worst == 250 and row.total == 280 and row.runs == 2)

function slow:Broken() error("boom", 0) end
Perf:Wrap(slow, "Broken")
local ok, err = pcall(slow.Broken, slow)
suite.check("an error passes through unchanged", not ok and err == "boom", err)

Perf:WrapAll()
suite.check("the finder's scan is watched", Perf.rows["Finder:Scan"] == nil and (function()
    Finder:Scan()
    return Perf.rows["Finder:Scan"] ~= nil
end)())

env.chat = {}
ns.HandleSlash("perf")
local text = env.ChatText()
suite.check("/beq perf lists the slowest first", text:find("Slow:Work  worst 250 ms, 2 runs", 1, true) ~= nil
    and text:find("Slow:Work", 1, true) < text:find("Listener on", 1, true), text)
ns.HandleSlash("perf clear")
suite.check("/beq perf clear starts over", Perf.rows["Slow:Work"] == nil
    and Perf.rows["Listener on PLAYER_REGEN_ENABLED"] == nil)
Perf:Reset()
env.chat = {}
Perf:Report(10)
suite.check("and says when nothing is measured yet", env.ChatText():find("nothing measured yet", 1, true) ~= nil)

-- The Settings buttons do what the commands do.
ns.SettingsUI:Show()
local controls = ns.SettingsUI.controls
slow:Work(5)
env.chat = {}
controls.perfShow:GetScript("OnClick")(controls.perfShow)
suite.check("the Show button lists them", env.ChatText():find("Slow:Work", 1, true) ~= nil)
controls.perfClear:GetScript("OnClick")(controls.perfClear)
suite.check("the Clear button clears them", Perf.rows["Slow:Work"] == nil)
for _, key in ipairs({ "perfShow", "perfClear" }) do
    suite.check(key .. " has a tooltip", pcall(controls[key]:GetScript("OnEnter"), controls[key]))
end

_G.debugprofilestop = nil
env.chat = {}
ns.HandleSlash("perf")
suite.check("a client with no timer says so", env.ChatText():find("no timer", 1, true) ~= nil)

Compare.Judge = realJudge
suite.done()
