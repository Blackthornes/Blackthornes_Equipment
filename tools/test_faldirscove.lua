-- Land Ho! before Sunken Treasure at Faldir's Cove.
--
-- On Forever, Professor Phizzlethorpe offers Sunken Treasure only once Land
-- Ho! is handed in (the owner saw it in game, 2026-11-22). Classic's data
-- names no quest before it, so the upgrade quest for the Gnomish Zapper
-- sent a player to the Professor, who was not there for them yet. The
-- shipped record (tools/forever_facts.json, Data/ForeverQuests.lua) names
-- Land Ho!, and the chain starts with Lolo the Lookout.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local ns = env.Load()

local failures = 0
local function check(label, ok)
  if ok then
    print("  ok   " .. label)
  else
    failures = failures + 1
    print("  FAIL " .. label)
  end
end

print("")
print("faldir's cove")

ns.QuestLearn:LayAll()
local Finder = ns.Finder
local done = {}
Finder.QuestDone = function(_, id) return done[id] == true end

local chain = Finder:Chain(666)
check("the Gnomish Zapper's chain has two quests before it", #chain == 2)
check("it starts with Land Ho!", chain[1] and chain[1].questID == 663)
check("from Lolo the Lookout", chain[1] and chain[1].name == "Lolo the Lookout")
check("then the Professor's Sunken Treasure", chain[2] and chain[2].questID == 665)

done[663] = true
chain = Finder:Chain(666)
check("with Land Ho! done, the Professor comes first", #chain == 1 and chain[1].questID == 665)

if failures > 0 then error(failures .. " check(s) failed") end
