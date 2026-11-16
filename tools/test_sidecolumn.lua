-- The Upgrade Quest panel and the Upgrade Tracker, never dragged, stand in
-- one column left of the game's quest list, each under the one above, and
-- close up when one hides. A dragged panel keeps its own spot.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("sidecolumn")

local ns = env.Load({ ui = true })
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
local Column = ns.SideColumn

local function Show(frame) frame:Show(); local f = frame._scripts.OnShow; if f then f(frame) end end
local function Hide(frame) frame:Hide(); local f = frame._scripts.OnHide; if f then f(frame) end end

for _, key in ipairs({ "questPoint", "questRelativePoint", "questX", "questY",
    "trackerPoint", "trackerRelativePoint", "trackerX", "trackerY" }) do
    ns.db[key] = nil
end

local quest = ns.QuestPanel:Build() or ns.QuestPanel.frame
local tracker = ns.TrackerPanel:Build() or ns.TrackerPanel.frame
suite.check("both panels build", quest ~= nil and tracker ~= nil)
quest._scale, tracker._scale = 1, 1
quest.GetScale = function(self) return self._scale end
tracker.GetScale = function(self) return self._scale end

-- No quest list on screen: the column sits on the right edge.
Show(quest); Show(tracker)
Column:Layout()
suite.check("the quest panel heads the column", quest._point[1] == "TOPRIGHT" and quest._point[2] == UIParent
    and quest._point[4] == -Column.EDGE and quest._point[5] == Column.TOP)
suite.check("the tracker stands under it", tracker._point[2] == quest and tracker._point[3] == "BOTTOMRIGHT"
    and tracker._point[5] == -Column.GAP)

Hide(quest)
suite.check("the quest panel shut: the tracker moves up", tracker._point[2] == UIParent
    and tracker._point[4] == -Column.EDGE)
Show(quest)
suite.check("and back under it when it opens", tracker._point[2] == quest)

-- The game's quest list on screen: the column sits left of it.
local list = env.Stub({ _left = 1600, _top = 900 })
list.IsVisible = function() return true end
list.GetRight = function() return 1900 end
UIParent.GetRight = function() return 1920 end
UIParent.GetTop = function() return 1080 end
_G.ObjectiveTrackerFrame = list
Column:Layout()
suite.check("left of the game's quest list", quest._point[4] == 1600 - 1920 - Column.BESIDE, quest._point[4])
suite.check("level with its top", quest._point[5] == 900 - 1080, quest._point[5])

-- Put out of sight by Hide Game's Tracker: back to the edge.
local hidden = ns.QuestLogUI.TrackerHidden
ns.QuestLogUI.TrackerHidden = function() return true end
Column:Layout()
suite.check("the game's list out of sight: on the right edge", quest._point[4] == -Column.EDGE)
ns.QuestLogUI.TrackerHidden = hidden
_G.ObjectiveTrackerFrame = nil

-- A dragged panel leaves the column; the rest close up.
quest:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 300, 500)
ns.QuestPanel:SavePosition()
suite.check("dragged: out of the column", not Column:Holds("quest") and ns.db.questX == 300)
suite.check("the tracker heads the column now", tracker._point[2] == UIParent)
ns.QuestPanel:RestorePosition()
suite.check("and the quest panel keeps its spot", quest._point[1] == "TOPLEFT" and quest._point[4] == 300)

-- Set Default clears the saved spots: back in the column.
ns.db.questPoint, ns.db.questRelativePoint, ns.db.questX, ns.db.questY = nil, nil, nil, nil
ns.QuestPanel:RestorePosition()
suite.check("Set Default: back at the top", Column:Holds("quest") and quest._point[2] == UIParent
    and tracker._point[2] == quest)

suite.done()
