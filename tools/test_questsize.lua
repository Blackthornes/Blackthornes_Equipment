-- The small panel's size (the owner asked 2026-10-07 for the quest panel,
-- after Tradeskills' window got the same; the small panel took it over in
-- rework step 4 and is the only panel since step 6).
--
-- What must hold:
--   1. "small", "80", "80%" and "0.8" all read as 80%; names read
--      "Small (80%)", and a dragged size reads as its percent.
--   2. A size is kept between 50% and 150%, saved as `questScale`, and the
--      panel is drawn at it.
--   3. A spot saved at another size (or before sizes, at 1) lands on the
--      same place.
--   4. /beq quest size and the Settings buttons do the same.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("questsize")

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end

local Panel = ns.SmallPanel

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

-- 2. Kept in range, saved and drawn.
ns.db.questScale = 0.8
local frame = Panel:Build()
frame._scale = 1
frame.SetScale = function(self, s) self._scale = s end
frame.GetScale = function(self) return self._scale end
suite.check("it reads the saved size", near(Panel:GetScale(), 0.8), Panel:GetScale())
local now = Panel:SetPanelScale(0.5)
suite.check("sized to 50%", near(frame._scale, 0.5), frame._scale)
suite.check("returns the size it took", near(now, 0.5), now)
suite.check("saved", near(ns.db.questScale, 0.5))
suite.check("too small: 50%", near(Panel:SetPanelScale(0.1), 0.5) and near(ns.db.questScale, 0.5))
suite.check("too big: 150%", near(Panel:SetPanelScale(9), 1.5) and near(ns.db.questScale, 1.5))
Panel:SetPanelScale(1)

-- 3. A spot saved at another size lands on the same place.
suite.check("a spot from before sizes, at 50%: doubled", near(Panel.PositionFactor(1, 0.5), 2))
suite.check("a spot saved at this size: as saved", near(Panel.PositionFactor(0.5, 0.5), 1))
suite.check("nothing saved counts as 1", near(Panel.PositionFactor(nil, 0.8), 1.25))

-- 4. /beq quest size and Settings.
ns.HandleSlash("quest size small")
suite.check("/beq quest size small", near(ns.db.questScale, 0.8))
ns.HandleSlash("quest size 115%")
suite.check("/beq quest size 115%", near(ns.db.questScale, 1.15))
ns.HandleSlash("quest size tiny")
suite.check("/beq quest size tiny changes nothing", near(ns.db.questScale, 1.15))
suite.check("and says what it takes", env.chat[#env.chat]:find("50%% to 150%%"), env.chat[#env.chat])

ns.HandleSlash("settings")
local SettingsUI = ns.SettingsUI
SettingsUI.pages:Show("quest")
local buttons = SettingsUI.controls.questSizes
suite.check("Settings has Small, Normal and Large", #buttons == 3)
suite.check("the row has no description", SettingsUI.questSizeRow.description == "")
buttons[3]._scripts.OnClick(buttons[3], "LeftButton")
suite.check("Large draws it at 120%", near(ns.db.questScale, 1.2) and near(frame._scale, 1.2), frame._scale)

suite.done()
