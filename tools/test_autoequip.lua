-- "Put on upgrades" (the owner asked 2026-10-15): an upgrade that lands in
-- the bags goes on by itself, off unless ticked. Gear that would bind, gear
-- a Farmer goal or a Tradeskills craft needs, and anything in a fight waits.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("autoequip")

local function Chest(agility, bind)
    return { loc = "INVTYPE_CHEST", class = 4, subclass = 2, bind = bind,
        stats = { ITEM_MOD_AGILITY_SHORT = agility } }
end

local ITEMS = {
    ["item:1"] = Chest(10, 0),   -- worn
    ["item:2"] = Chest(20, 0),   -- never binds
    ["item:3"] = Chest(30, 2),   -- binds when worn, not bound yet
    ["item:4"] = Chest(40, 1),   -- bound when picked up
    ["item:5"] = Chest(50, 0),   -- a Farmer goal wants it
    ["item:6"] = Chest(60, 0),   -- a Tradeskills craft wants it
    ["item:7"] = Chest(25, 0),   -- arrives in a fight
    ["item:8"] = Chest(26, 0),   -- arrives with ...
    ["item:9"] = Chest(27, 0),   -- ... this better one
}

local ns = env.Load()
_G.UnitClass = function() return "HUNTER", "HUNTER" end
env.InstallItems(ITEMS, { [5] = "item:1" }, { [0] = { [1] = "item:20" } })

local realInfo = _G.C_Item.GetItemInfo
_G.C_Item.GetItemInfo = function(link)
    local item = ITEMS[link]
    if not item then return nil end
    local values = { realInfo(link) }
    values[1] = "Item " .. link:match("%d+")
    values[14] = item.bind
    return unpack(values, 1, 14)
end
local bound = {}
_G.C_Container.GetContainerItemInfo = function(bag, slot)
    local link = env.bags[bag] and env.bags[bag][slot]
    if not link then return nil end
    return { stackCount = 1, isBound = bound[link] == true }
end

local fighting = false
_G.InCombatLockdown = function() return fighting end
local equipped = {}
_G.C_Item.EquipItemByName = function(link)
    equipped[#equipped + 1] = link
    for bag, slots in pairs(env.bags) do
        for slot, held in pairs(slots) do
            if held == link then
                slots[slot] = env.worn[5]
                env.worn[5] = link
                return
            end
        end
    end
end

local UpgradeChat, Wear = ns.UpgradeChat, ns.Wear
UpgradeChat:OnEnable()
Wear:OnEnable()
UpgradeChat:PLAYER_ENTERING_WORLD()

local function Land(link)
    env.bags[0][#env.bags[0] + 1] = link
    UpgradeChat:Scan()
end

suite.check("it is off by default", ns.DEFAULTS.autoEquip == false and not Wear:AutoOn())

Land("item:2")
suite.check("off, nothing is put on", #equipped == 0)
suite.check("and the usual line is said", env.ChatText():find("upgrade in your bags: item:2", 1, true), env.ChatText())

ns.HandleSlash("autoequip on")
suite.check("/beq autoequip on turns it on", Wear:AutoOn())

local before = #env.chat
Land("item:3")
suite.check("gear that would bind waits for a click", #equipped == 0)
suite.check("and gets the usual line", env.chat[before + 1] and env.chat[before + 1]:find("item:3", 1, true), env.ChatText())

bound["item:4"] = true
Land("item:4")
suite.check("soulbound gear goes on", equipped[1] == "item:4", equipped[1])
suite.check("and says so", env.ChatText():find("put on item:4", 1, true), env.ChatText())
suite.check("it is worn", env.worn[5] == "item:4")

_G.BlackthornesFarmer = { Goals = { Find = function(_, name) return name == "Item 5" and {} or nil end } }
Land("item:5")
suite.check("a Farmer goal's gear waits", #equipped == 1, equipped[2])
_G.BlackthornesFarmer = nil

_G.BlackthornesTS = { Butler = { Advise = function(_, id) return id == 6 and { need = 1 } or {} end } }
Land("item:6")
suite.check("a queued craft's gear waits", #equipped == 1, equipped[2])
_G.BlackthornesTS = nil

-- Put back to a plain worn chest for the next ones.
env.worn[5] = "item:1"
env.bags = { [0] = { [1] = "item:20" } }
UpgradeChat:PLAYER_ENTERING_WORLD()
equipped = {}

fighting = true
Land("item:7")
suite.check("nothing goes on in a fight", #equipped == 0)
suite.check("and nothing is said yet", not env.ChatText():find("upgrade in your bags: item:7", 1, true))
fighting = false
Wear:Next()
suite.check("it goes on once the fight ends", equipped[1] == "item:7", equipped[1])

-- Two in one loot: the better one is worn at the end.
env.bags[0][#env.bags[0] + 1] = "item:9"
env.bags[0][#env.bags[0] + 1] = "item:8"
UpgradeChat:Scan()
suite.check("the best of two ends up worn", env.worn[5] == "item:9", env.worn[5])

-- A game that would not put it on: the usual line instead.
env.worn[5] = "item:1"
env.bags = { [0] = { [1] = "item:20" } }
UpgradeChat:PLAYER_ENTERING_WORLD()
_G.C_Item.EquipItemByName = function() end
before = #env.chat
Land("item:2")
suite.check("a refusal falls back to the usual line",
    env.ChatText():find("upgrade in your bags: item:2", 1, true) and env.worn[5] == "item:1", env.ChatText())

ns.HandleSlash("autoequip off")
suite.check("/beq autoequip off turns it off", not Wear:AutoOn())

-- The What's New card turns it on.
local card
for _, tip in ipairs(ns.WHATS_NEW_TIPS or {}) do
    if tip.key == "autoEquip" then card = tip end
end
suite.check("What's New has a card for it", card ~= nil)
suite.check("due while it is off", card and card.due())
card.run()
suite.check("its button turns it on", Wear:AutoOn() and not card.due())

suite.done()
