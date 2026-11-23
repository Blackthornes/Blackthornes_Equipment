-- Dark glass rows (asked 2026-10-10 to calm the gold glare behind list
-- rows, the standard for every list since 2026-10-12): the lists Settings
-- draws rest on glass and glassAlt in turn, and only the row under the
-- mouse lights. A gradient shows and hides itself, since faded with
-- SetAlpha alone it stayed lit on every row.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("rowglass")

local ns = env.Load()
local Theme = ns.Theme

-- The stand-in textures keep no colour, so each one watched notes the last
-- it was given.
local function Watch(texture)
    texture.SetColorTexture = function(self, r, g, b) self.seen = { r, g, b } end
end
local function Is(texture, key)
    local seen = rawget(texture, "seen")
    local r, g, b = Theme.Unpack(key)
    return type(seen) == "table" and seen[1] == r and seen[2] == g and seen[3] == b
end

-- The list of pages down the left of Settings.
ns.SettingsUI:Show("gear")
local pages = ns.SettingsUI.pages
local parts = {}
for _, part in ipairs(pages.switch) do
    if part.button:IsShown() then
        parts[#parts + 1] = part
        Watch(part.back)
    end
end
pages:Paint()
suite.check("the page showing is lit, gold down its left", parts[1].key == "gear"
    and Is(parts[1].back, "glassActive") and parts[1].underline:IsShown())
suite.check("the next rests on the other band", Is(parts[2].back, "glassAlt") and not parts[2].underline:IsShown())
suite.check("and the one after on glass", Is(parts[3].back, "glass"))
parts[3].button:GetScript("OnEnter")(parts[3].button)
suite.check("under the mouse a row lights with a gold edge", Is(parts[3].back, "glassHover") and parts[3].edge:IsShown())
suite.check("but not the row beside it", not parts[2].edge:IsShown() and Is(parts[2].back, "glassAlt"))
parts[3].button:GetScript("OnLeave")(parts[3].button)
suite.check("when the mouse leaves it goes dark", Is(parts[3].back, "glass") and not parts[3].edge:IsShown())

-- The stat rows of the Stat Weights page.
pages:Show("weights")
local shown = {}
for _, row in ipairs(ns.WeightsPage.rows) do
    if row:IsShown() then
        shown[#shown + 1] = row
        Watch(row.background)
    end
end
ns.WeightsPage:Refresh()
suite.check("stat rows rest on dark glass", shown[1].restKey == "glass" and Is(shown[1].background, "glass"))
suite.check("a band apart from the next", shown[2].restKey == "glassAlt" and Is(shown[2].background, "glassAlt"))
shown[1]:GetScript("OnEnter")(shown[1])
suite.check("under the mouse the row lights", Is(shown[1].background, "glassHover") and shown[1].edge:IsShown())
suite.check("but not the row beside it", not shown[2].edge:IsShown())
shown[1]:GetScript("OnLeave")(shown[1])
suite.check("leaving, it goes dark", Is(shown[1].background, "glass") and not shown[1].edge:IsShown())

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
