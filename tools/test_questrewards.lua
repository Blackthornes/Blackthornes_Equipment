-- The arrow on the best quest reward, and the chat line on hand-in.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("questrewards")

local function Agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end

local ITEMS = {
    ["item:1"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = Agi(10) },
    ["item:2"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = Agi(12) },
    ["item:3"] = { loc = "INVTYPE_FEET", class = 4, subclass = 2, stats = Agi(4) },
    ["item:4"] = { loc = "INVTYPE_SHIELD", class = 4, subclass = 6, stats = Agi(40) },
    ["item:5"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = Agi(5) },
    ["item:6"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = Agi(40), minLevel = 30 },
}

--- A reward button as the game makes one.
local function Button(kind, id)
    local button = env.Stub({ type = kind, _textures = {} })
    button.GetID = function() return id end
    button.CreateTexture = function(self)
        local texture = env.Stub()
        self._textures[#self._textures + 1] = texture
        return texture
    end
    return button
end

local function Arrow(button) return button._textures[1] end

local function LoadWith(choices, named)
    local ns = env.Load()
    _G.UnitClass = function() return "HUNTER", "HUNTER" end
    env.InstallItems(ITEMS, { [5] = "item:1" })
    env.InstallHooks()
    _G.GetNumQuestChoices = function() return #choices end
    _G.GetQuestItemLink = function(kind, index)
        if kind == "choice" then return choices[index] end
    end

    local buttons = {}
    for i = 1, #choices do buttons[i] = Button("choice", i) end
    -- A fixed reward alongside the choices, which is never marked.
    buttons[#buttons + 1] = Button("reward", 1)

    _G.QuestInfoRewardsFrame = nil
    for i = 1, 10 do _G["QuestInfoRewardsFrameQuestInfoItem" .. i] = nil end
    if named then
        for i, button in ipairs(buttons) do _G["QuestInfoRewardsFrameQuestInfoItem" .. i] = button end
    else
        _G.QuestInfoRewardsFrame = env.Stub({ RewardButtons = buttons })
    end

    _G.QuestInfo_Display = function() end
    ns.QuestRewards:OnEnable()
    return ns, buttons
end

-- A chest a little better, boots for an empty slot, and a shield.
local ns, buttons = LoadWith({ "item:2", "item:3", "item:4" })
local index = ns.QuestRewards:Best()
suite.check("the empty boot slot is the bigger gain", index == 2, index)

_G.QuestInfo_Display()
suite.check("the hooked layout marks it", Arrow(buttons[2]) and Arrow(buttons[2]):IsShown())
suite.check("the others are not marked", not Arrow(buttons[1]) and not Arrow(buttons[3]))
suite.check("nor the fixed reward", not Arrow(buttons[4]))

ns.QuestRewards:QUEST_COMPLETE()
local chat = env.ChatText()
suite.check("hand-in names the best reward", chat:find("best reward for Beast Mastery: item:3", 1, true), chat)
suite.check("and why", chat:find("fills an empty slot", 1, true), chat)

-- Nothing worth taking.
ns, buttons = LoadWith({ "item:5", "item:4", "item:6" })
suite.check("no upgrade, no pick", ns.QuestRewards:Best() == nil)
suite.check("an item above your level is not picked", ns.QuestRewards:Mark() == nil)
ns.QuestRewards:QUEST_COMPLETE()
suite.check("and chat says none beats your gear",
    env.ChatText():find("none of these rewards beats what you wear", 1, true), env.ChatText())

-- The classic window, with named buttons.
ns, buttons = LoadWith({ "item:5", "item:2" }, true)
suite.check("named buttons are marked too", ns.QuestRewards:Mark() == 2)
suite.check("on the right one", Arrow(buttons[2]) and Arrow(buttons[2]):IsShown())

-- The arrow moves when the pick does, and the setting takes it off.
env.worn[5] = "item:2"
ns.QuestRewards:Mark()
suite.check("an arrow comes off when the choice stops being an upgrade", not Arrow(buttons[2]):IsShown())
env.worn[5] = "item:1"
ns.db.bagArrows = false
suite.check("the arrows setting switches it off", ns.QuestRewards:Mark() == nil)
suite.check("and hides the arrow", not Arrow(buttons[2]):IsShown())
ns.db.bagArrows = true

-- One reward, nothing to choose: no chat line.
ns = LoadWith({ "item:2" })
ns.QuestRewards:QUEST_COMPLETE()
suite.check("a single reward is not announced", not env.ChatText():find("reward", 1, true), env.ChatText())

-- A client that raises costs the arrow, not an error.
ns = LoadWith({ "item:2", "item:3" })
_G.GetQuestItemLink = function() error("secret value") end
suite.check("a link that raises does not break it", ns.QuestRewards:Refresh() == true)
suite.check("and marks nothing", ns.QuestRewards.lastMarked == nil)

suite.done()
