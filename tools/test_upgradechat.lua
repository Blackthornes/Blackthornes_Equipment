-- The chat line when an upgrade lands in the bags: said once for an item
-- that is new, never for what was already there, moved, split or taken off.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("upgradechat")

local function Chest(agility, minLevel)
    return { loc = "INVTYPE_CHEST", class = 4, subclass = 2, minLevel = minLevel,
        stats = { ITEM_MOD_AGILITY_SHORT = agility } }
end

local ITEMS = {
    ["item:1"] = Chest(10),  -- worn
    ["item:2"] = Chest(15),  -- an upgrade already in the bags at login
    ["item:3"] = Chest(5),   -- worse
    ["item:4"] = Chest(20),  -- an upgrade that arrives later
    ["item:5"] = Chest(5),   -- worse, arrives later
    ["item:6"] = Chest(30),  -- an upgrade in a stack of two
    ["item:7"] = Chest(40, 30), -- an upgrade from level 30
    ["item:9"] = Chest(50),  -- arrives while the setting is off
    ["item:10"] = Chest(60), -- arrives in the bank
    ["item:11"] = Chest(70), -- arrives on a loading screen
}

local ns = env.Load()
_G.UnitClass = function() return "HUNTER", "HUNTER" end
env.InstallItems(ITEMS, { [5] = "item:1" },
    { [0] = { [1] = "item:2", [2] = "item:3" }, [1] = { [1] = "item:6" } })

-- Stack sizes, as the client reports them.
local stacks = { [1] = { [1] = 2 } }
_G.C_Container.GetContainerItemInfo = function(bag, slot)
    if not env.bags[bag] or not env.bags[bag][slot] then return nil end
    return { stackCount = stacks[bag] and stacks[bag][slot] or 1 }
end

local UpgradeChat = ns.UpgradeChat
UpgradeChat:OnEnable()

local function Lines() return #env.chat end

-- Logging in: the upgrade already carried is not news.
UpgradeChat:PLAYER_ENTERING_WORLD()
suite.check("logging in says nothing", Lines() == 0, env.ChatText())
suite.check("but the bags were counted", UpgradeChat.counts and UpgradeChat.counts["item:2"] == 1)

-- A new upgrade lands.
env.bags[0][3] = "item:4"
UpgradeChat:Scan()
suite.check("a new upgrade is said once", Lines() == 1, env.ChatText())
suite.check("with the item and how much better",
    env.chat[1]:find("upgrade in your bags: item:4", 1, true)
        and env.chat[1]:find("+100%", 1, true), env.chat[1])
suite.check("in the upgrade green", env.chat[1]:find("|c" .. ns.COLORS.upgrade, 1, true))

UpgradeChat:Scan()
suite.check("and not again on the next scan", Lines() == 1, env.ChatText())

-- Moving it to another bag.
env.bags[0][3] = nil
env.bags[1][2] = "item:4"
UpgradeChat:Scan()
suite.check("moving an item between bags says nothing", Lines() == 1, env.ChatText())

-- Splitting a stack of two into two slots of one.
stacks[1][1] = 1
env.bags[1][3] = "item:6"
UpgradeChat:Scan()
suite.check("splitting a stack says nothing", Lines() == 1, env.ChatText())

-- Something worse lands.
env.bags[0][4] = "item:5"
UpgradeChat:Scan()
suite.check("a new item that is not an upgrade says nothing", Lines() == 1, env.ChatText())

-- An upgrade that has to wait for a level.
env.bags[0][5] = "item:7"
UpgradeChat:Scan()
suite.check("an upgrade for a later level says nothing", Lines() == 1, env.ChatText())

-- An item whose details have not arrived yet gets another look when they do.
env.bags[0][6] = "item:8"
UpgradeChat:Scan()
suite.check("an item the client does not know yet waits", Lines() == 1
    and UpgradeChat.pending["item:8"], env.ChatText())
ITEMS["item:8"] = Chest(25)
UpgradeChat:GET_ITEM_INFO_RECEIVED()
suite.check("and is said once its details arrive", Lines() == 2
    and env.chat[2]:find("item:8", 1, true), env.ChatText())
UpgradeChat:Scan()
suite.check("only once", Lines() == 2, env.ChatText())

-- Taking the chest off: it goes back to the bags, and with the slot empty
-- it would fill it. Nothing new arrived, so nothing is said.
env.worn[5] = nil
env.bags[0][7] = "item:1"
UpgradeChat:PLAYER_EQUIPMENT_CHANGED()
UpgradeChat:Scan()
suite.check("taking a piece off says nothing", Lines() == 2, env.ChatText())
suite.check("nor does gear carried all along that is an upgrade now",
    ns.Compare:IsUpgradeNow("item:3") and Lines() == 2)

-- Put on from the bags and taken straight off again before a scan.
env.bags[0][7] = nil
env.worn[5] = "item:1"
UpgradeChat:PLAYER_EQUIPMENT_CHANGED()
env.worn[5] = nil
env.bags[1][4] = "item:1"
UpgradeChat:PLAYER_EQUIPMENT_CHANGED()
UpgradeChat:Scan()
suite.check("a quick swap between scans says nothing", Lines() == 2, env.ChatText())

-- The setting off.
ns.db.upgradeChat = false
env.bags[0][8] = "item:9"
UpgradeChat:Scan()
suite.check("with the setting off nothing is said", Lines() == 2, env.ChatText())
ns.db.upgradeChat = true
UpgradeChat:Scan()
suite.check("and switching it back on does not catch up", Lines() == 2, env.ChatText())

-- The bank is not the bags.
env.bags[5] = { [1] = "item:10" }
env.bags[-1] = { [1] = "item:10" }
UpgradeChat:Scan()
suite.check("an upgrade in the bank says nothing", Lines() == 2, env.ChatText())

-- A loading screen is a fresh start.
env.bags[0][9] = "item:11"
UpgradeChat:PLAYER_ENTERING_WORLD()
suite.check("a loading screen says nothing", Lines() == 2, env.ChatText())

-- A client call that raises costs the line, not an error.
local GetLink = _G.C_Container.GetContainerItemLink
_G.C_Container.GetContainerItemLink = function() error("secret value") end
local ok = pcall(UpgradeChat.Scan, UpgradeChat)
suite.check("a bag that raises does not break the scan", ok)
suite.check("and says nothing", Lines() == 2, env.ChatText())
_G.C_Container.GetContainerItemLink = GetLink
UpgradeChat:Scan()
suite.check("once it reads again, what was there all along is not news",
    Lines() == 2, env.ChatText())

-- And after all that, a new upgrade is still said.
ITEMS["item:12"] = Chest(80)
env.bags[0][10] = "item:12"
UpgradeChat:Scan()
suite.check("a later upgrade is still said", Lines() == 3
    and env.chat[3]:find("item:12 |c" .. ns.COLORS.upgrade .. "fills an empty slot", 1, true),
    env.ChatText())

suite.check("it is on by default", ns.DEFAULTS.upgradeChat == true)

suite.done()
