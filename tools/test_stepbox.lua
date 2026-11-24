-- The step box (UI/TravelCard.lua, the same file in every addon whose arrow
-- takes trips): Your Way There as one small see-through row.
--
-- What matters: it shows only the step you are on, "Step 2 of 4" and about
-- how long; it hangs under the addon's panel when one shows, else under the
-- big arrow, else where it was put; the close gem shows only when it is not
-- under a panel; its small dial turns with the big arrow and shows a dot
-- when there is no way to point; the glass is thin until the mouse comes,
-- and the words carry a shadow; the big arrow keeps only its name while the
-- box shows; the close gem puts it away for this place only.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("stepbox")

local ns = env.Load()
local TravelCard, Travel = ns.TravelCard, ns.Travel
_G.InCombatLockdown = function() return false end

local function Step(kind, name, zone)
    return { kind = kind, to = { name = name, zone = zone } }
end
local plan = { key = "outhouse", done = 1, cost = 600,
    steps = { Step("zeppelin", "Grom'gol"), Step("fly", "Kargath"), Step("walk", "Wooden Outhouse", "Searing Gorge") },
    behind = { Step("hearth", "Orgrimmar") } }
local trip = { plan = plan, index = 2, count = 4, step = plan.steps[1],
    line = "Take the zeppelin to Grom'gol", small = "" }

-- Where it hangs: no panel and no dial, so it stands free.
local host = Travel.Host
local oldHang, oldDial = host.Hang, host.Dial
host.Hang, host.Dial = function() return nil end, function() return nil end

TravelCard:Update({ trip = trip, mode = "point", turn = 0, place = trip.line, note = "120 yd" })
local frame = TravelCard.frame
suite.check("it shows on a trip", frame and frame:IsShown())
suite.check("the step you are on", TravelCard.title:GetText() == "Take the zeppelin to Grom'gol",
    TravelCard.title:GetText())
suite.check("how far, from the arrow", TravelCard.sub:GetText() == "120 yd", TravelCard.sub:GetText())
local count = TravelCard.count:GetText()
suite.check("which step and about how long", count:find("2") and count:find("4") and count:find("10"), count)
suite.check("free, so the close gem shows", TravelCard.where == "free"
    and (not TravelCard.close or TravelCard.close:IsShown()))
suite.check("the small dial points", TravelCard.blade:IsShown() and not TravelCard.dot:IsShown())

-- No way to point (a Hearthstone or a ride): a still dot.
TravelCard:Update({ trip = trip, mode = "trip" })
suite.check("no way to point: a dot", TravelCard.dot:IsShown() and not TravelCard.blade:IsShown())
suite.check("no arrow words: the step's own small line", TravelCard.sub:GetText() == "Get on when it stops",
    TravelCard.sub:GetText())

-- Under the big arrow when it shows.
local dialFrame = CreateFrame("Frame", nil, UIParent)
local dial = CreateFrame("Frame", nil, dialFrame)
dialFrame:Show()
host.Dial = function() return { frame = dialFrame, dial = dial } end
TravelCard:Update({ trip = trip, mode = "trip" })
suite.check("under the big arrow", TravelCard.where == "dial" and TravelCard.anchor == dial)
suite.check("with its close gem", not TravelCard.close or TravelCard.close:IsShown())

-- Under the panel when it shows, as wide as it, with no gem of its own.
local panel = CreateFrame("Frame", nil, UIParent)
panel:SetWidth(270)
panel:Show()
host.Hang = function() return panel end
TravelCard:Update({ trip = trip, mode = "trip" })
suite.check("under the panel", TravelCard.where == "panel" and TravelCard.anchor == panel)
suite.check("as wide as the panel", TravelCard.width == 270, TravelCard.width)
suite.check("no close gem under the panel", not TravelCard.close or not TravelCard.close:IsShown())
panel:Hide()
TravelCard:Update({ trip = trip, mode = "trip" })
suite.check("panel put away: back under the arrow", TravelCard.where == "dial")

-- See-through and readable.
suite.check("thin glass while the mouse is away", not TravelCard.solid
    and TravelCard.glass == TravelCard.GLASS_CLEAR and TravelCard.GLASS_CLEAR < 0.5, TravelCard.glass)
suite.check("buttons wait for the mouse", not TravelCard.stop:IsShown() and not TravelCard.show:IsShown())
TravelCard:SetSolid(true)
suite.check("solid glass and the buttons on the mouse", TravelCard.solid and TravelCard.stop:IsShown()
    and TravelCard.show:IsShown())
TravelCard:SetSolid(false)

-- The big arrow keeps only its name while the box shows.
local d, p, n = TravelCard:Words({ trip = trip })
suite.check("the arrow's words step aside", d == "" and p == "" and n == "")
suite.check("no trip: the arrow speaks", TravelCard:Words({}) == nil)

-- The close gem: only the box goes, for this place.
TravelCard:Close()
TravelCard:Update({ trip = trip, mode = "trip" })
suite.check("closed for this place", not frame:IsShown())
suite.check("the arrow speaks again", TravelCard:Words({ trip = trip }) == nil)
TravelCard:Update({ trip = { plan = { key = "elsewhere", steps = plan.steps, done = 0 } }, mode = "trip" })
suite.check("a new place brings it back", frame:IsShown())

TravelCard:Update({})
suite.check("no trip: hidden", not frame:IsShown())

host.Hang, host.Dial = oldHang, oldDial
suite.done()
