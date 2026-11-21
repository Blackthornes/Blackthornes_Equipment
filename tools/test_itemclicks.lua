-- Item rows answer the game's item clicks (the owner, 2026-11-21): Shift-click
-- with a chat box open puts the item's link in it, Ctrl-click tries gear on,
-- and a row's own click is left alone otherwise (UI/Widgets.lua ItemClick and
-- ItemTryOn, the same helper as the sister addons).

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("itemclicks")

local ns = env.Load({ ui = true })
local Widgets = ns.Widgets

local LINK = "|cff1eff00|Hitem:15012::::::::18:1485:::1:12722|h[Slayer's Gloves]|h|r"
local keys, chatOpen, inserted, dressed, handled = {}, false, {}, {}, 0
local function Reset() keys, chatOpen, inserted, dressed, handled = {}, false, {}, {}, 0 end

_G.IsModifiedClick = function(kind)
    if kind == "CHATLINK" then return keys.shift and true or false end
    if kind == "DRESSUP" then return keys.ctrl and true or false end
    return false
end
_G.ChatEdit_GetActiveWindow = function() return chatOpen and {} or nil end
_G.ChatEdit_InsertLink = function(link)
    if not chatOpen then return false end
    inserted[#inserted + 1] = link
    return true
end
_G.DressUpItemLink = function(link) dressed[#dressed + 1] = link; return true end

-- 1. The helper.
do
    Reset()
    suite.check("a plain click is left to the row", Widgets.ItemClick(nil, LINK) == false)
    keys.shift = true
    suite.check("Shift with the chat box shut is left to the row", Widgets.ItemClick(nil, LINK) == false)
    chatOpen = true
    suite.check("Shift with the chat box open links it", Widgets.ItemClick(nil, LINK) == true and inserted[1] == LINK)
    suite.check("ItemTryOn leaves Shift to the row's own link", Widgets.ItemTryOn(nil, LINK) == false)
    keys.shift, keys.ctrl = false, true
    suite.check("Ctrl tries it on", Widgets.ItemTryOn(nil, LINK) == true and dressed[1] == LINK)
    suite.check("and so does ItemClick", Widgets.ItemClick(nil, LINK) == true and dressed[2] == LINK)
    suite.check("Ctrl tries on by number while the item loads",
        Widgets.ItemClick(99999) == true and dressed[3] == "item:99999")
end

-- 2. The game's own handler does the work where it is there.
do
    Reset()
    _G.HandleModifiedItemClick = function(link)
        handled = handled + 1
        if keys.ctrl then return _G.DressUpItemLink(link) end
        return false
    end
    keys.ctrl = true
    suite.check("the game's handler tries it on", Widgets.ItemClick(nil, LINK) == true and handled == 1 and #dressed == 1)
    _G.HandleModifiedItemClick = function() error("secret") end
    suite.check("a handler that raises falls back", Widgets.ItemClick(nil, LINK) == true and #dressed == 2)
    _G.HandleModifiedItemClick = nil
end

_G.IsModifiedClick, _G.ChatEdit_GetActiveWindow, _G.ChatEdit_InsertLink, _G.DressUpItemLink = nil, nil, nil, nil

suite.done()
