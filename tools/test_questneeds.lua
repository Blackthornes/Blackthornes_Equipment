-- Quests a quest needs first (Data/QuestNeeds.lua).
--
-- The owner, 2026-11-25: Upgrade Quest for the Deftkin Belt sent him to kill
-- Tideress for the Befouled Water Globe, and it never dropped. It drops only
-- while Stonetalon Standstill is in the quest log. And for the Wildhunter
-- Cloak it sent him to The Hunt Completed, which opens only once all three
-- Ashenvale beasts' quests are handed in. "If a quest has a prerequisite
-- quest that needs to be said first."

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("questneeds")

local ITEMS = {
    ["item:900"] = { loc = "INVTYPE_WAIST", class = 4, subclass = 2, stats = { ITEM_MOD_AGILITY_SHORT = 2 } },
    ["item:16659"] = { loc = "INVTYPE_WAIST", class = 4, subclass = 2, stats = { ITEM_MOD_AGILITY_SHORT = 9 } },
}

local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
_G.UnitFactionGroup = function() return "Horde", "Horde" end
_G.UnitRace = function() return "Orc", "Orc", 2 end
_G.GetRealZoneText = function() return "Ashenvale" end
env.InstallItems(ITEMS, { [6] = "item:900" }, { [0] = {} }, 26)

local done, inLog = {}, {}
_G.C_QuestLog = {
    IsQuestFlaggedCompleted = function(id) return done[id] == true end,
    IsOnQuest = function(id) return inLog[id] == true end,
    ReadyForTurnIn = function() return false end,
}

ns.QuestLearn:LayAll()
local Finder = ns.Finder

local function Ids(chain)
    local ids = {}
    for _, step in ipairs(chain) do ids[#ids + 1] = tostring(step.questID) end
    return table.concat(ids, " ")
end

-- The Deftkin Belt: Je'neu of the Earthen Ring, after The Befouled Element,
-- whose globe drops only while Stonetalon Standstill is in the log.
local chain = Finder:Chain(824)
suite.check("Stonetalon Standstill comes before the globe", Ids(chain) == "25 1918", Ids(chain))
suite.check("from Mastok Wrilehiss", chain[1] and chain[1].name == "Mastok Wrilehiss", chain[1] and chain[1].name)
inLog[25] = true
chain = Finder:Chain(824)
suite.check("with Stonetalon Standstill in the log, the globe is next", Ids(chain) == "1918", Ids(chain))
inLog[25] = nil

-- The Wildhunter Cloak: The Hunt Completed needs all three beasts' quests,
-- and each of those The Ashenvale Hunt.
chain = Finder:Chain(247)
suite.check("The Ashenvale Hunt, then all three beasts", Ids(chain) == "6383 2 23 24", Ids(chain))
suite.check("The Ashenvale Hunt from Senani Thunderheart in Ashenvale",
    chain[1] and chain[1].name == "Senani Thunderheart" and chain[1].zone == "Ashenvale", chain[1] and chain[1].name)
done[6383], done[2], done[24] = true, true, true
chain = Finder:Chain(247)
suite.check("with two beasts handed in, only Ursangous's Paw is left", Ids(chain) == "23", Ids(chain))
done[6383], done[2], done[24] = nil, nil, nil

-- A chain with one quest before each still reads as before.
chain = Finder:Chain(666)
suite.check("Land Ho! before Sunken Treasure still", Ids(chain) == "663 665", Ids(chain))

-- The steps for the Deftkin Belt say to pick up Stonetalon Standstill
-- first, and the globe's step says why.
local Quest = ns.UpgradeQuest
local belt = { itemID = 16659, link = "item:16659", source = { kind = "quest", questID = 824,
    title = "Je'neu of the Earthen Ring", questLevel = 27, name = "Mastok Wrilehiss", zone = "Ashenvale",
    x = 73.7, y = 60 } }
local texts, notes = {}, {}
for _, step in ipairs((Quest:Steps(belt))) do
    texts[#texts + 1] = step.text
    notes[#notes + 1] = step.note or ""
end
local all = table.concat(texts, " | ")
local stone = all:find("Stonetalon Standstill", 1, true)
local globe = all:find("Befouled Water Globe from Tideress", 1, true)
suite.check("the steps name Stonetalon Standstill before Tideress", stone and globe and stone < globe, all)
suite.check("the globe's step says it drops only with the quest in the log",
    table.concat(notes, " | "):find("It only drops while Stonetalon Standstill is in your quest log.", 1, true) ~= nil,
    table.concat(notes, " | "))

suite.done()
