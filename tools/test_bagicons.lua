-- The upgrade arrow on items in the bags, for both ways a client can draw
-- its bag windows.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("bagicons")

local ITEMS = {
    ["item:1"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = { ITEM_MOD_AGILITY_SHORT = 10 } },
    ["item:2"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = { ITEM_MOD_AGILITY_SHORT = 15 } },
    ["item:3"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = { ITEM_MOD_AGILITY_SHORT = 5 } },
}

--- An item button whose textures the test can look at.
local function Button(bag, slot)
    local button = env.Stub({ _textures = {} })
    button.GetID = function() return slot end
    if bag then button.GetBagID = function() return bag end end
    button.CreateTexture = function(self)
        local texture = env.Stub()
        texture.SetAtlas = function(t, name) t._atlas = name end
        texture.SetTexture = function(t, path) t._path = path end
        self._textures[#self._textures + 1] = texture
        return texture
    end
    return button
end

local function Arrow(button) return button._textures[1] end

local function Load()
    local ns = env.Load()
    _G.UnitClass = function() return "HUNTER", "HUNTER" end
    env.InstallItems(ITEMS, { [5] = "item:1" }, { [0] = { [1] = "item:2", [2] = "item:3" } })
    env.InstallHooks()
    return ns
end

-- Retail's shape: one combined window listing its own buttons.
local ns = Load()
_G.C_Texture = { GetAtlasInfo = function(name) if name == "bags-greenarrow" then return {} end end }
local upgrade, worse = Button(0, 1), Button(0, 2)
_G.ContainerFrameCombinedBags = env.Stub({ _shown = true })
_G.ContainerFrameCombinedBags.EnumerateValidItems = function()
    local list, i = { upgrade, worse }, 0
    return function()
        i = i + 1
        if list[i] then return i, list[i] end
    end
end
local updates = 0
_G.ContainerFrameCombinedBags.UpdateItems = function() updates = updates + 1 end

ns.BagIcons:OnEnable()
suite.check("UpdateItems is hooked", ns.BagIcons.hooked[1] == "UpdateItems", ns.BagIcons.hooked[1])

_G.ContainerFrameCombinedBags:UpdateItems()
suite.check("the game's own update still runs", updates == 1)
suite.check("the upgrade gets an arrow", Arrow(upgrade) and Arrow(upgrade):IsShown())
suite.check("drawn with the game's upgrade arrow", Arrow(upgrade)._atlas == "bags-greenarrow")
suite.check("the worse item gets none", not Arrow(worse))

suite.check("a refresh counts the arrows", ns.BagIcons:Refresh() == 1)
suite.check("and only one texture is made per button", #upgrade._textures == 1)

ns.db.bagArrows = false
ns.BagIcons:Refresh()
suite.check("the setting hides it", not Arrow(upgrade):IsShown())
ns.db.bagArrows = true

-- Wearing the upgrade makes the arrow go.
env.worn[5] = "item:2"
env.bags[0][1] = "item:1"
ns.BagIcons:Refresh()
suite.check("an arrow goes when the item stops being an upgrade", not Arrow(upgrade):IsShown())

-- /beq spec re-judges the bags.
env.worn[5] = "item:1"
env.bags[0][1] = "item:2"
ns.HandleSlash("spec mm")
suite.check("/beq spec refreshes the arrows", Arrow(upgrade):IsShown())

-- Classic's shape: numbered windows, named buttons, one update function.
ns = Load()
_G.C_Texture = nil
local frame = env.Stub({ _shown = true })
frame.GetName = function() return "ContainerFrame1" end
frame.GetID = function() return 0 end
_G.ContainerFrame1 = frame
local classicUpgrade, classicWorse = Button(nil, 1), Button(nil, 2)
_G.ContainerFrame1Item1 = classicUpgrade
_G.ContainerFrame1Item2 = classicWorse
_G.ContainerFrame_Update = function() end

ns.BagIcons:OnEnable()
suite.check("ContainerFrame_Update is hooked", ns.BagIcons.hooked[1] == "ContainerFrame_Update")
_G.ContainerFrame_Update(frame)
suite.check("a named button gets its arrow", Arrow(classicUpgrade) and Arrow(classicUpgrade):IsShown())
suite.check("from the fallback texture", Arrow(classicUpgrade)._path ~= nil)
suite.check("and the worse one none", not Arrow(classicWorse))

local frames = ns.BagIcons:Describe()
suite.check("the probe names the window", frames:find("ContainerFrame1", 1, true), frames)

-- Closed windows are skipped.
frame._shown = false
suite.check("closed windows are not looked at", ns.BagIcons:Refresh() == 0)

-- A button that raises costs its arrow, not an error.
frame._shown = true
classicUpgrade.GetID = function() error("secret value") end
local ok = pcall(ns.BagIcons.Refresh, ns.BagIcons)
suite.check("a button that raises does not break the rest", ok)

-- Forever's controller bag button, which covers the combined backpack's
-- sort button, is put out of sight (and lets clicks through) unless the
-- setting is unticked. Hide and Show are never called on it: they would run
-- the game's bag bar code as this addon and taint Edit Mode's layout.
ns = Load()
local touched = false
local pad = env.Stub({ _shown = true, _alpha = 1, _mouse = true })
pad.Hide = function() touched = true end
pad.Show = function() touched = true end
pad.SetAlpha = function(self, value) self._alpha = value end
pad.GetAlpha = function(self) return self._alpha end
-- The retail engine's calls, clicks and mouse-over apart.
pad.IsMouseClickEnabled = function(self) return self._mouse end
pad.IsMouseMotionEnabled = function(self) return self._mouse end
pad.SetMouseClickEnabled = function(self, on)
    if self._protected and _G.InCombatLockdown and _G.InCombatLockdown() then error("blocked in combat") end
    self._mouse = on and true or false
end
pad.SetMouseMotionEnabled = pad.SetMouseClickEnabled
pad.IsProtected = function(self) return self._protected end
pad.GetChildren = function() end
_G.GamepadBackpackButton = pad
ns.BagIcons:OnEnable()
suite.check("the controller bag button is out of sight", pad._alpha == 0 and ns.BagIcons:GamepadHidden())
suite.check("and lets clicks through to the sort button", not pad._mouse)

ns.db.hideGamepadBag = false
ns.BagIcons:ApplyGamepadBag()
suite.check("unticking puts it back", pad._alpha == 1 and pad._mouse and not ns.BagIcons:GamepadHidden())
ns.db.hideGamepadBag = true

-- A protected button lets clicks through once combat ends.
pad._protected = true
_G.InCombatLockdown = function() return true end
ns.BagIcons:ApplyGamepadBag()
suite.check("in combat a protected button keeps its mouse", pad._mouse)
_G.InCombatLockdown = function() return false end
ns.eventFrame:GetScript("OnEvent")(ns.eventFrame, "PLAYER_REGEN_ENABLED")
suite.check("and lets clicks through once combat ends", not pad._mouse and pad._alpha == 0)
suite.check("the button is never hidden or shown by the addon", not touched)
_G.InCombatLockdown = nil
_G.GamepadBackpackButton = nil

-- A client without it is fine.
suite.check("no button, no error", pcall(ns.BagIcons.ApplyGamepadBag, ns.BagIcons))

suite.done()
