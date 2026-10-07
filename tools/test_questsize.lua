-- The upgrade quest panel's size (the owner asked 2026-10-07, after
-- Tradeskills' window got the same).
--
-- What must hold:
--   1. A size is kept between 50% and 150%, to a whole percent; "small",
--      "80", "80%" and "0.8" all read as 80%; names read "Small (80%)", and
--      a dragged size reads as its percent.
--   2. The panel opens at the saved size, never bigger than the screen.
--   3. A new size keeps the top left corner where it was, is saved, and the
--      saved spot remembers the size it was taken at; a spot saved at
--      another size (or before sizes, at 1) lands on the same place.
--   4. Dragging the grip sizes the panel from its top left corner and saves
--      the size on release; right-click puts it back to normal.
--   5. /beq quest size and the Settings buttons do the same.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("questsize")

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end

local Panel = ns.QuestPanel

local SCREEN_W, SCREEN_H = 1280, 720
local function near(a, b) return type(a) == "number" and math.abs(a - b) < 0.001 end

-- The screen, and a panel that works out its edges from its one point, in
-- its own units, as the game does: an offset from UIParent's corner or
-- edge, divided by its scale.
UIParent.GetWidth = function() return SCREEN_W end
UIParent.GetHeight = function() return SCREEN_H end
UIParent.GetEffectiveScale = function() return 1 end

local cursorX, cursorY = 0, 0
_G.GetCursorPosition = function() return cursorX, cursorY end
GameTooltip.IsOwned = function(self, frame) return self._owner == frame end
GameTooltip.SetOwner = function(self, owner) self._owner, self._lines = owner, {} end
GameTooltip.SetText = function(self, text) self._lines = { text } end

-- 1. Sizes and their names.
suite.check("nothing saved: normal", Panel.ClampScale(nil) == 1)
suite.check("too small: 50%", Panel.ClampScale(0.1) == 0.5)
suite.check("too big: 150%", Panel.ClampScale(9) == 1.5)
suite.check("to a whole percent", near(Panel.ClampScale(0.873), 0.87))
suite.check("not a number: normal", Panel.ClampScale(0 / 0) == 1)
suite.check("\"small\"", Panel.ParseSize("small") == 0.8)
suite.check("\"Large\"", Panel.ParseSize("Large") == 1.2)
suite.check("\"80%\"", Panel.ParseSize("80%") == 0.8)
suite.check("\"80\"", Panel.ParseSize("80") == 0.8)
suite.check("\"0.8\"", Panel.ParseSize("0.8") == 0.8)
suite.check("\"tiny\": not a size", Panel.ParseSize("tiny") == nil)
suite.check("nothing: not a size", Panel.ParseSize("") == nil)
suite.check("named", Panel.ScaleText(1) == "Normal (100%)", Panel.ScaleText(1))
suite.check("named, small", Panel.ScaleText(0.8) == "Small (80%)")
suite.check("dragged to", Panel.ScaleText(0.87) == "87%")

-- 2. Opening at the saved size.
ns.db.questScale = 0.8
local frame = Panel:Build()

frame._scale = 1
frame.SetScale = function(self, s) self._scale = s end
frame.GetScale = function(self) return self._scale end
frame.ClearAllPoints = function(self) self._point = nil end
frame.SetPoint = function(self, point, relativeTo, relativePoint, x, y)
    self._point = { point, relativeTo, relativePoint, x or 0, y or 0 }
end
frame.GetLeft = function(self)
    local p = self._point
    if not p then return nil end
    if p[3] == "BOTTOMLEFT" then return p[4] end
    if p[3] == "RIGHT" then return SCREEN_W / self._scale + p[4] - 340 end
end
frame.GetTop = function(self)
    local p = self._point
    if not p then return nil end
    if p[3] == "BOTTOMLEFT" then return p[5] end
    if p[3] == "RIGHT" then return SCREEN_H / (2 * self._scale) + p[5] + self._height / 2 end
end
frame._height = 400

suite.check("it has a grip", Panel.sizeGrip ~= nil)
suite.check("hung below the bottom right corner", Panel.sizeGrip._point[3] == "BOTTOMRIGHT")
suite.check("it reads the saved size", Panel:GetScale() == 0.8)
ns.db.questScale = 1.5
frame._height = 700
suite.check("150% with a tall panel on a 1280x720 screen: as big as fits", Panel:GetScale() < 1.5,
    Panel:GetScale())
suite.check("and the whole panel fits", (700 + 50) * Panel:GetScale() <= SCREEN_H)
frame._height = 400

-- 3. A new size from its top left corner.
ns.db.questScale = 1
frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 100, 600)
local now = Panel:SetPanelScale(0.5)
suite.check("sized to 50%", frame._scale == 0.5)
suite.check("returns the size it took", now == 0.5)
suite.check("saved", ns.db.questScale == 0.5)
suite.check("left edge stays on screen at 100", near(frame:GetLeft() * frame._scale, 100))
suite.check("top edge stays on screen at 600", near(frame:GetTop() * frame._scale, 600))
suite.check("the spot is saved with its size", ns.db.questScaleAt == 0.5)

ns.db.questPoint, ns.db.questRelativePoint, ns.db.questX, ns.db.questY = "RIGHT", "RIGHT", -100, 50
ns.db.questScaleAt = nil
Panel:RestorePosition()
suite.check("a spot from before sizes, at 50%: x doubled", frame._point[4] == -200, frame._point[4])
suite.check("and y doubled", frame._point[5] == 100)

ns.db.questScaleAt = 0.5
Panel:RestorePosition()
suite.check("a spot saved at this size: as saved", frame._point[4] == -100)

ns.db.questPoint, ns.db.questRelativePoint, ns.db.questX, ns.db.questY, ns.db.questScaleAt = nil, nil, nil, nil, nil
Panel:RestorePosition()
suite.check("never moved: its starting spot, on the same place on screen",
    frame._point[4] == -80 and frame._point[5] == -240)

-- 4. The grip.
local grip = Panel.sizeGrip
frame._scale = 1
frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 50, 700)
-- Pressed 10 right of and 15 below the corner, where the grip hangs.
cursorX, cursorY = 50 + 340 + 10, 700 - 400 - 15
grip._scripts.OnMouseDown(grip, "LeftButton")
suite.check("sizing", grip.sizing == true)
-- Moved to where the corner would be at 80%.
cursorX, cursorY = 50 + 340 * 0.8 + 10, 700 - 400 * 0.8 - 15
grip._scripts.OnUpdate(grip)
suite.check("drawn at 80% while dragging", near(frame._scale, 0.8), frame._scale)
suite.check("top left stays put (left)", near(frame:GetLeft() * frame._scale, 50))
suite.check("top left stays put (top)", near(frame:GetTop() * frame._scale, 700))
cursorX, cursorY = 50 + 340 * 0.3, 700 - 400 * 0.3
grip._scripts.OnUpdate(grip)
suite.check("never under 50%", frame._scale == 0.5)
cursorX, cursorY = 50 + 340 * 0.8 + 10, 700 - 400 * 0.8 - 15
grip._scripts.OnUpdate(grip)
grip._scripts.OnMouseUp(grip, "LeftButton")
suite.check("saved on release", near(ns.db.questScale, 0.8), ns.db.questScale)
suite.check("and the spot with it", near(ns.db.questScaleAt, 0.8))
suite.check("stopped", grip._scripts.OnUpdate == nil)
grip._scripts.OnMouseDown(grip, "RightButton")
suite.check("right-click: normal again", frame._scale == 1)
suite.check("and saved", ns.db.questScale == 1)
grip._scripts.OnEnter(grip)
suite.check("its tooltip names the size", GameTooltip._lines[1] == "Normal (100%)", GameTooltip._lines[1])

-- 5. /beq quest size and Settings.
ns.HandleSlash("quest size small")
suite.check("/beq quest size small", ns.db.questScale == 0.8)
ns.HandleSlash("quest size 115%")
suite.check("/beq quest size 115%", near(ns.db.questScale, 1.15))
ns.HandleSlash("quest size tiny")
suite.check("/beq quest size tiny changes nothing", near(ns.db.questScale, 1.15))
suite.check("and says what it takes", env.chat[#env.chat]:find("50%% to 150%%"), env.chat[#env.chat])

ns.HandleSlash("settings")
local SettingsUI = ns.SettingsUI
local buttons = SettingsUI.controls.questSizes
suite.check("Settings has Small, Normal and Large", #buttons == 3)
suite.check("naming a dragged size", SettingsUI.questSizeRow.hint:GetText():find("Now 115%", 1, true),
    SettingsUI.questSizeRow.hint:GetText())
buttons[3]._scripts.OnClick(buttons[3], "LeftButton")
suite.check("Large draws it at 120%", ns.db.questScale == 1.2 and frame._scale == 1.2)
suite.check("and the line under it says so",
    SettingsUI.questSizeRow.hint:GetText():find("Now Large (120%)", 1, true))

suite.done()
