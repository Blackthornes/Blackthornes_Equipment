-- Dark glass rows (asked 2026-10-10 to calm the gold glare behind list
-- rows): the finder's rows sit in the well's own dark, a faint band apart,
-- and the gold wash lights only the row under the mouse. The wash shows and
-- hides itself, since faded with SetAlpha alone it stayed lit on every row.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("rowglass")

local ns = env.Load()
local Theme, Motion = ns.Theme, ns.Motion

local function Is(texture, key)
    local r, g, b = Theme.Unpack(key)
    local c = texture._color or {}
    return c[1] == r and c[2] == g and c[3] == b
end

ns.FinderUI:Build()
local first = ns.FinderUI:BuildRow(1)
local second = ns.FinderUI:BuildRow(2)
suite.check("rows rest on dark glass", first.restKey == "glass", first.restKey)
suite.check("a band apart from the next", second.restKey == "glassAlt", second.restKey)

first.pick = false   -- no tooltip: the row is empty
first.hoverWash:Hide()
first:GetScript("OnEnter")(first)
Motion:FinishAll()
suite.check("under the mouse the gold wash shows", first.hoverWash:IsShown())
suite.check("but not on the row beside it", not second.hoverWash:IsShown())

first:GetScript("OnLeave")(first)
Motion:FinishAll()
suite.check("when the mouse leaves it goes dark", not first.hoverWash:IsShown())

-- LightGradient itself: strength into the gradient, hidden at nothing.
local texture = { _shown = true }
function texture:SetShown(v) self._shown = v and true or false end
function texture:SetColorTexture() end
local from
function texture:SetGradient(_, a) from = a end
_G.CreateColor = _G.CreateColor or function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
Theme.LightGradient(texture, "HORIZONTAL", "accent", 0.10, 0, 0)
suite.check("at nothing it hides", texture._shown == false)
Theme.LightGradient(texture, "HORIZONTAL", "accent", 0.10, 0, 0.5)
suite.check("part lit shows", texture._shown == true)
local a = from and (from.a or (from.GetRGBA and select(4, from:GetRGBA())))
suite.check("at half strength", a and math.abs(a - 0.05) < 1e-6, tostring(a))

suite.done()
