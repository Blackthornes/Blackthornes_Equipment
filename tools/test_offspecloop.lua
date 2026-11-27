-- The Off Spec ring loop (a Discord report on 2.1.1).
--
-- A Feral druid with a Restoration Off Spec put on a healing set by hand.
-- Both sets share one ring. My Gear then said "1 upgrade in your bags":
-- swap the shared ring for the Feral ring. Putting it on made the page
-- think the Feral gear was on and offer "Put On Restoration Gear", which
-- put the shared ring back, and round it went. What must hold:
--   1. With the healing set on, Ready Now offers no Feral piece.
--   2. One stray piece does not flip which gear counts as on.
--   3. With the healing set on, the page shows what is worn.

local lfs_cwd = os.getenv("PWD") or "."
local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("offspecloop")

local ARMOR, LEATHER = 4, 2

local ITEMS = {
    -- Bounty Hunter's Ring: Feral only.
    ["item:21"] = { loc = "INVTYPE_FINGER", class = ARMOR, subclass = 0,
        stats = { ITEM_MOD_AGILITY_SHORT = 3, ITEM_MOD_STAMINA_SHORT = 1 } },
    -- Lead Band of the Gorilla: in both sets.
    ["item:22"] = { loc = "INVTYPE_FINGER", class = ARMOR, subclass = 0,
        stats = { ITEM_MOD_STRENGTH_SHORT = 2, ITEM_MOD_INTELLECT_SHORT = 2 } },
    -- A healer's ring.
    ["item:23"] = { loc = "INVTYPE_FINGER", class = ARMOR, subclass = 0,
        stats = { ITEM_MOD_INTELLECT_SHORT = 3, ITEM_MOD_SPIRIT_SHORT = 2 } },
    -- Two chests, one for each set.
    ["item:31"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = LEATHER,
        stats = { ITEM_MOD_AGILITY_SHORT = 6, ITEM_MOD_STAMINA_SHORT = 3 } },
    ["item:32"] = { loc = "INVTYPE_CHEST", class = ARMOR, subclass = LEATHER,
        stats = { ITEM_MOD_INTELLECT_SHORT = 6, ITEM_MOD_SPIRIT_SHORT = 3 } },
    -- Two belts, one for each set.
    ["item:41"] = { loc = "INVTYPE_WAIST", class = ARMOR, subclass = LEATHER,
        stats = { ITEM_MOD_AGILITY_SHORT = 4 } },
    ["item:42"] = { loc = "INVTYPE_WAIST", class = ARMOR, subclass = LEATHER,
        stats = { ITEM_MOD_INTELLECT_SHORT = 4 } },
}

local ns = env.Load()
_G.UnitClass = function() return "Druid", "DRUID", 11 end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitRace = function() return "Night Elf", "NightElf", 4 end
-- The healing set on, put on by hand (a game gear set): no Switch Gear note.
local HEAL = { [5] = "item:32", [6] = "item:42", [11] = "item:23", [12] = "item:22" }
local FERAL = { [5] = "item:31", [6] = "item:41", [11] = "item:21", [12] = "item:22" }
local function Copy(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end
env.InstallItems(ITEMS, Copy(HEAL),
    { [0] = { [1] = "item:31", [2] = "item:41", [3] = "item:21" } }, 24)

local S = ns.Sources
ns.Crafts.ITEMS = {}
ns.RollData.ITEMS = {}
S.ZONES, S.NPCS, S.QUESTS, S.DUNGEONS, S.BOSSES, S.FOREVER, S.ITEMS = {}, {}, {}, {}, {}, {}, {}

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end

_G.InCombatLockdown = function() return false end
_G.C_Timer = nil
-- The game's EquipItemByName: the piece and what was worn trade places.
_G.C_Item.EquipItemByName = function(link, slot)
    for bag, slots in pairs(env.bags) do
        for bagSlot, held in pairs(slots) do
            if held == link then
                slots[bagSlot] = env.worn[slot] or false
                env.worn[slot] = link
                return
            end
        end
    end
end

local OffSpec, SwitchGear, MyGear = ns.OffSpec, ns.SwitchGear, ns.MyGear
ns.charDB.spec = "feral"
ns.charDB.offSpec = "resto"
ns.charDB.swapBack = nil
OffSpec:Forget()

local function ReadyNow()
    MyGear.bagsFor, MyGear.bags = nil, nil
    local state = MyGear:Read({}, nil)
    return state.ready
end
local function Join(list) return table.concat(list or {}, ",") end

-- 1.
local state = SwitchGear:State()
suite.check("with the healing set on, the healing gear counts as on",
    state and state.on == "off", state and state.on)
suite.check("Ready Now offers no Feral ring with the healing set on",
    #ReadyNow() == 0, Join(ReadyNow()))

-- 2. Put on the Feral ring anyway, over the shared ring.
env.worn[12] = "item:21"
env.bags[0][3] = "item:22"
OffSpec:Forget()
state = SwitchGear:State()
suite.check("one Feral ring does not flip the gear to Feral",
    state and state.on == "off", state and state.on)
suite.check("so the button still offers the Feral gear",
    state and state.go == "main", state and state.go)

local ready = ReadyNow()
suite.check("Ready Now offers the shared ring back, for the healing set",
    Join(ready) == "item:22", Join(ready))
MyGear.state = MyGear:Read({}, nil)
suite.check("Put It On goes through Switch Gear", MyGear:PutThemOn() == 1)
suite.check("which puts the shared ring back on", env.worn[11] == "item:22" or env.worn[12] == "item:22",
    tostring(env.worn[11]) .. " " .. tostring(env.worn[12]))
OffSpec:Forget()
state = SwitchGear:State()
suite.check("the healing gear still counts as on", state and state.on == "off", state and state.on)
suite.check("and Ready Now is empty again", #ReadyNow() == 0, Join(ReadyNow()))

-- 3. Back to the healing set: what the page shows is what is worn.
env.worn = Copy(HEAL)
env.bags = { [0] = { [1] = "item:31", [2] = "item:41", [3] = "item:21" } }
ns.charDB.swapBack = nil
OffSpec:Forget()
MyGear.bagsFor, MyGear.bags = nil, nil
local read = MyGear:Read({}, nil)
local shown = {}
for _, info in pairs(read.slots) do shown[info.slot] = info.link end
for slot, link in pairs(HEAL) do
    suite.check("slot " .. slot .. " shows the piece worn", shown[slot] == link, tostring(shown[slot]))
end

-- 4. The Feral set on: its own gear counts, nothing to put on.
env.worn = Copy(FERAL)
env.bags = { [0] = { [1] = "item:32", [2] = "item:42", [3] = "item:23" } }
OffSpec:Forget()
state = SwitchGear:State()
suite.check("with the Feral set on, the Feral gear counts as on", state and state.on == "main", state and state.on)
suite.check("and Ready Now offers no healing piece", #ReadyNow() == 0, Join(ReadyNow()))

suite.done()
