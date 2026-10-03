-- The arrow and percentage on gear up for a group loot roll.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("lootrolls")

local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end

local ITEMS = {
    ["item:1"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = Agi(10) },
    ["item:2"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = Agi(12) },
    ["item:3"] = { loc = "INVTYPE_FEET", class = 4, subclass = 2, stats = Agi(4) },
    ["item:5"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = Agi(5) },
    ["item:6"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = Agi(40), minLevel = 30 },
}

--- An icon button as the roll window has one.
local function Icon(width)
    local icon = env.Stub({ _textures = {}, _fonts = {} })
    icon.GetWidth = function() return width or 34 end
    icon.CreateTexture = function(self)
        local texture = env.Stub()
        self._textures[#self._textures + 1] = texture
        return texture
    end
    icon.CreateFontString = function(self)
        local text = env.Stub()
        text.SetFont = function(t, _, size) t._size = size end
        -- Wider at bigger sizes, as a real font is.
        text.GetStringWidth = function(t) return #(t._text or "") * (t._size or 12) * 0.6 end
        self._fonts[#self._fonts + 1] = text
        return text
    end
    return icon
end

--- A roll window for roll `rollID`, shown.
local function RollFrame(name, rollID, iconWidth)
    local frame = env.Stub({ rollID = rollID, _shown = true })
    frame.GetName = function() return name end
    frame.IconFrame = Icon(iconWidth)
    return frame
end

local function Arrow(frame) return frame.IconFrame._textures[1] end
local function Label(frame) return frame.IconFrame._fonts[1] end

local rolls
local function Load(retail)
    local ns = env.Load()
    _G.UnitClass = function() return "HUNTER", "HUNTER" end
    env.InstallItems(ITEMS, { [5] = "item:1" })
    env.InstallHooks()
    rolls = {}
    _G.GetLootRollItemLink = function(rollID) return rolls[rollID] end
    _G.GroupLootFrame_OpenNewFrame = function() end
    _G.GroupLootContainer = nil
    for i = 1, 4 do _G["GroupLootFrame" .. i] = nil end

    local frames = {}
    for i = 1, 4 do frames[i] = RollFrame("GroupLootFrame" .. i, i) end
    if retail then
        _G.GroupLootContainer = env.Stub({ rollFrames = frames })
    else
        for i = 1, 4 do _G["GroupLootFrame" .. i] = frames[i] end
    end
    ns.LootRolls:OnEnable()
    return ns, frames
end

-- A slightly better chest, boots for an empty slot, a worse chest, and a
-- chest you are too low to wear.
local ns, frames = Load(true)
rolls[1], rolls[2], rolls[3], rolls[4] = "item:2", "item:3", "item:5", "item:6"
_G.GroupLootFrame_OpenNewFrame(1, 60)
suite.check("opening a roll marks the upgrades", ns.LootRolls.lastMarked == 2, ns.LootRolls.lastMarked)
suite.check("the better chest has the arrow", Arrow(frames[1]) and Arrow(frames[1]):IsShown())
suite.check("and says by how much", Label(frames[1]) and Label(frames[1]):GetText() == "+20%",
    Label(frames[1]) and Label(frames[1]):GetText())
suite.check("the percentage fits inside the icon",
    Label(frames[1]):IsShown() and Label(frames[1]):GetStringWidth() <= 32)
suite.check("the empty slot has the arrow", Arrow(frames[2]) and Arrow(frames[2]):IsShown())
suite.check("but no percentage", not Label(frames[2]) or not Label(frames[2]):IsShown())
suite.check("a worse chest is not marked", not Arrow(frames[3]))
suite.check("nor one you are too low to wear", not Arrow(frames[4]))

-- The window is reused for the next roll.
rolls[1] = "item:5"
frames[1]._scripts.OnShow(frames[1])
suite.check("a reused window loses its arrow", not Arrow(frames[1]):IsShown())
suite.check("and its percentage", not Label(frames[1]):IsShown())

-- A narrow icon shrinks the text rather than spill past it.
ns, frames = Load(false)
frames[1].IconFrame.GetWidth = function() return 22 end
rolls[1] = "item:2"
ns.LootRolls:Refresh()
local label = Label(frames[1])
suite.check("the classic named windows are marked too", Arrow(frames[1]) and Arrow(frames[1]):IsShown())
suite.check("a narrow icon gets smaller text", label:IsShown() and label._size < 12, label._size)
suite.check("that still fits", label:GetStringWidth() <= 20)
frames[1].IconFrame.GetWidth = function() return 10 end
ns.LootRolls:Refresh()
suite.check("text that cannot fit is left off", not label:IsShown())
suite.check("but the arrow stays", Arrow(frames[1]):IsShown())

-- Hidden windows, the setting, and a client that raises.
frames[1]._shown = false
suite.check("a hidden window is not marked", ns.LootRolls:Refresh() == 0)
frames[1]._shown = true
ns.db.bagArrows = false
suite.check("the arrows setting switches it off", ns.LootRolls:Refresh() == 0)
suite.check("and hides the arrow", not Arrow(frames[1]):IsShown())
ns.db.bagArrows = true
_G.GetLootRollItemLink = function() error("secret value") end
suite.check("a link that raises does not break it", pcall(ns.LootRolls.Refresh, ns.LootRolls))
suite.check("and marks nothing", ns.LootRolls.lastMarked == 0)

-- A client with no roll windows at all.
ns = env.Load()
_G.GroupLootContainer = nil
for i = 1, 4 do _G["GroupLootFrame" .. i] = nil end
suite.check("no roll windows is fine", pcall(ns.LootRolls.OnEnable, ns.LootRolls))
suite.check("and the probe says so", ns.LootRolls:Describe() == "none found yet")

suite.done()
