-- The gold coin on bag gear better sold than kept: white gear, and soulbound
-- green or better gear when the character cannot disenchant it. Never on an
-- upgrade, a grey, or gear a vendor will not buy.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("sellcoins")

local ITEMS = {
    ["item:1"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = { ITEM_MOD_AGILITY_SHORT = 10 } },
    -- Worse than the worn chest, in each quality.
    ["item:2"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = { ITEM_MOD_AGILITY_SHORT = 3 } },
    ["item:3"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = { ITEM_MOD_AGILITY_SHORT = 4 } },
    ["item:4"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = { ITEM_MOD_AGILITY_SHORT = 5 } },
    ["item:5"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = { ITEM_MOD_AGILITY_SHORT = 6 } },
    -- An upgrade.
    ["item:6"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = { ITEM_MOD_AGILITY_SHORT = 20 } },
    -- A white shirt, and one a vendor will not buy.
    ["item:7"] = { loc = "INVTYPE_BODY", class = 4, subclass = 0, stats = {} },
    ["item:8"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = { ITEM_MOD_AGILITY_SHORT = 2 } },
    -- The mining pick, and a dagger that adds to Skinning.
    ["item:2901"] = { loc = "INVTYPE_WEAPON", class = 2, subclass = 0, stats = {} },
    ["item:9"] = { loc = "INVTYPE_WEAPON", class = 2, subclass = 15, stats = {} },
}

-- Quality, soulbound and sell price for each bag slot.
local SLOTS = {
    [1] = { quality = 1, price = 50 },                 -- white
    [2] = { quality = 0, price = 10 },                 -- grey
    [3] = { quality = 2, price = 80, bound = true },   -- soulbound green
    [4] = { quality = 2, price = 80, bound = false },  -- green, not bound
    [5] = { quality = 3, price = 200, bound = true },  -- upgrade, blue
    [6] = { quality = 1, price = 5 },                  -- shirt
    [7] = { quality = 1, price = 0 },                  -- no sell price
    [8] = { quality = 1, price = 20 },                 -- mining pick
    [9] = { quality = 2, price = 300, bound = true },  -- skinning dagger
}

local function Button(bag, slot)
    local button = env.Stub({ _textures = {} })
    button.GetID = function() return slot end
    button.GetBagID = function() return bag end
    button.CreateTexture = function(self)
        local texture = env.Stub()
        texture.SetAtlas = function(t, name) t._atlas = name end
        texture.SetTexture = function(t, path) t._path = path end
        self._textures[#self._textures + 1] = texture
        return texture
    end
    return button
end

local ns = env.Load()
_G.UnitClass = function() return "HUNTER", "HUNTER" end
env.InstallItems(ITEMS, { [5] = "item:1" }, { [0] = {
    [1] = "item:2", [2] = "item:3", [3] = "item:4", [4] = "item:5",
    [5] = "item:6", [6] = "item:7", [7] = "item:8", [8] = "item:2901", [9] = "item:9",
} })
env.InstallHooks()
_G.C_Container.GetContainerItemInfo = function(bag, slot)
    local s = SLOTS[slot]
    if bag ~= 0 or not s then return nil end
    return { quality = s.quality, isBound = s.bound == true, stackCount = 1 }
end
local PRICES = { ["item:2"] = 50, ["item:3"] = 10, ["item:4"] = 80, ["item:5"] = 80,
    ["item:6"] = 200, ["item:7"] = 5, ["item:8"] = 0, ["item:2901"] = 20, ["item:9"] = 300 }
_G.C_TooltipInfo = { GetHyperlink = function(link)
    local lines = { { type = 11, price = PRICES[link] } }
    if link == "item:9" then lines[2] = { type = 0, leftText = "Equip: Skinning +10." } end
    return { lines = lines }
end }
local priceReads = 0
local readPrice = ns.Items.SellPrice
ns.Items.SellPrice = function(...)
    priceReads = priceReads + 1
    return readPrice(...)
end
local enchanter = false
_G.IsPlayerSpell = function(id) return enchanter and id == 13262 end

local buttons = {}
for slot = 1, 9 do buttons[slot] = Button(0, slot) end
_G.ContainerFrameCombinedBags = env.Stub({ _shown = true })
_G.ContainerFrameCombinedBags.EnumerateValidItems = function()
    local i = 0
    return function()
        i = i + 1
        if buttons[i] then return i, buttons[i] end
    end
end
ns.BagIcons:OnEnable()

local function Coin(slot)
    local coin = ns.BagIcons:ExistingCoin(buttons[slot])
    return coin ~= nil and coin:IsShown()
end
local function Arrow(slot)
    local arrow = ns.BagIcons:ExistingArrow(buttons[slot])
    return arrow ~= nil and arrow:IsShown()
end

ns.BagIcons:Refresh()
suite.check("white gear gets a coin", Coin(1))
suite.check("drawn with the gold coin", ns.BagIcons:ExistingCoin(buttons[1])._path:find("UI-GoldIcon", 1, true))
suite.check("a grey gets none", not Coin(2))
suite.check("a soulbound green gets one without Enchanting", Coin(3))
suite.check("a green not yet bound gets none", not Coin(4))
suite.check("an upgrade gets the arrow, not a coin", Arrow(5) and not Coin(5))
suite.check("a shirt gets none", not Coin(6))
suite.check("gear no vendor buys gets none", not Coin(7))
suite.check("the mining pick gets none", not Coin(8))
suite.check("a weapon that adds to Skinning gets none", not Coin(9))

local reads = priceReads
ns.BagIcons:Refresh()
suite.check("a sell price is read once per item", priceReads == reads, priceReads - reads)

-- Learning Enchanting takes the coin off soulbound greens, not whites.
enchanter = true
ns.eventFrame:GetScript("OnEvent")(ns.eventFrame, "SKILL_LINES_CHANGED")
ns.BagIcons:Refresh()
suite.check("an enchanter's soulbound green gets none", not Coin(3))
suite.check("an enchanter's white gear still does", Coin(1))
enchanter = false
ns.eventFrame:GetScript("OnEvent")(ns.eventFrame, "SPELLS_CHANGED")
ns.BagIcons:Refresh()
suite.check("and it comes back without Enchanting", Coin(3))

-- The profession list counts as knowing Enchanting too.
_G.GetProfessions = function() return 1 end
_G.GetProfessionInfo = function() return "Enchanting", "icon", 1, 75, 1, 0, 333 end
ns.BagIcons.enchanter = nil
ns.BagIcons:Refresh()
suite.check("the profession list says Enchanting", not Coin(3))
_G.GetProfessions, _G.GetProfessionInfo = nil, nil
ns.BagIcons.enchanter = nil

-- The setting.
ns.db.bagSellCoins = false
ns.BagIcons:Refresh()
suite.check("unticking hides the coins", not Coin(1) and not Coin(3))
suite.check("and leaves the arrows", Arrow(5))
ns.db.bagSellCoins = true
ns.db.bagArrows = false
ns.BagIcons:Refresh()
suite.check("arrows off leaves the coins", Coin(1) and not Arrow(5))
suite.check("and still no coin on an upgrade", not Coin(5))
ns.db.bagArrows = true

-- A client that raises costs the coin, not an error.
_G.C_Container.GetContainerItemInfo = function() error("secret value") end
suite.check("a slot that raises does not break the rest", pcall(ns.BagIcons.Refresh, ns.BagIcons))

suite.done()
