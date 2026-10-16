-- Quests the Forever client does not have: Data/ForeverGoneQuests.lua names
-- them, and the finder leaves them out, while a quest learned in game still
-- shows.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("gonequests")

local ns = env.Load()
local Finder = ns.Finder

--------------------------------------------------------------------------------
-- The shipped file
--------------------------------------------------------------------------------

suite.check("the shipped file loads", type(ns.ForeverGoneQuests) == "table" and next(ns.ForeverGoneQuests) ~= nil)

local left, linked = nil, nil
for questID in pairs(ns.ForeverGoneQuests) do
    if ns.Sources.QUESTS[questID] and not ns.Sources.QUESTS[questID].learned then left = questID end
end
for itemID, item in pairs(ns.Sources.ITEMS) do
    for _, list in ipairs({ item.q or {}, item.g or {} }) do
        for _, questID in ipairs(list) do
            if ns.ForeverGoneQuests[questID] and not ns.Sources.QUESTS[questID] then linked = itemID end
        end
    end
end
suite.check("no quest the client lacks is left in the data", left == nil)
suite.check("no item still points at one", linked == nil)
suite.check("quests the client has stay", ns.Sources.QUESTS[962] ~= nil)

--------------------------------------------------------------------------------
-- Leaving them out
--------------------------------------------------------------------------------

local sources = {
    QUESTS = {
        [1] = { "Kept", 10, 12, 0, 0, "", 0, 0, 0, "" },
        [2] = { "Gone", 58, 60, 0, 0, "", 0, 0, 0, "" },
        [3] = { "After gone", 60, 60, 0, 0, "", 0, 0, 0, "Gone", p = 2 },
        [4] = { "Learned", 20, 20, 0, 0, "", 0, 0, 0, "", learned = true },
    },
    ITEMS = {
        [100] = { 10, 15, 0, 0, 0, q = { 1, 2 }, g = { 2 } },
        [101] = { 60, 70, 0, 0, 0, q = { 2 } },
        [102] = { 20, 25, 0, 0, 0, q = { 4 } },
    },
}
local dropped = Finder.DropGoneQuests({ [2] = true, [4] = true, [9] = true }, sources)
suite.check("one quest is dropped", dropped == 1 and sources.QUESTS[2] == nil)
suite.check("a quest the client has stays", sources.QUESTS[1] ~= nil)
suite.check("a learned quest stays", sources.QUESTS[4] ~= nil and sources.ITEMS[102].q[1] == 4)
suite.check("a quest after it no longer waits on it", sources.QUESTS[3].p == nil)
suite.check("its rewards forget it",
    #sources.ITEMS[100].q == 1 and sources.ITEMS[100].q[1] == 1 and #sources.ITEMS[100].g == 0
        and #sources.ITEMS[101].q == 0)
suite.check("nothing to leave out does nothing", Finder.DropGoneQuests(nil, sources) == 0)

-- Learned in game later, it is laid back over the data.
ns.Sources.ITEMS[101] = { 60, 70, 0, 0, 0, q = {} }
ns.QuestLearn:Lay(2, { title = "Gone", level = 60, rewards = { { 101, 60, 70, false } } })
suite.check("learned in game, it shows again", ns.Sources.QUESTS[2] ~= nil and ns.Sources.ITEMS[101].q[1] == 2)

suite.done()
