-- Thunder Bluff and Mulgore spots on Forever's own Mulgore map.
--
-- Classic's spots for Thunder Bluff's vendors, trainers and quest givers are
-- kept on Mulgore's map, and Forever's Mulgore map covers more ground than
-- the one Classic's numbers were measured on, so they landed just north of
-- the city, and Mulgore's own spots north and west of the NPC (Tradeskills
-- found it first, 2026-11-17). tools/classic_maps.py moved them. What must
-- hold:
--   1. Every Mulgore vendor and trainer sits where the game showed it
--      (Data/ForeverNPCs.lua), Thunder Bluff's too.
--   2. Every Mulgore quest giver sits where the game showed them
--      (Data/ForeverQuests.lua).
--   3. Thunder Bluff's NPCs land inside the city, and another zone's spots
--      are left as they were.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local ns = env.Load()

local failures = 0
local function check(label, got, want)
  if got == want then
    print("  ok   " .. label)
  else
    failures = failures + 1
    print(string.format("  FAIL %s: got %s, want %s", label, tostring(got), tostring(want)))
  end
end

-- World bounds of each map on Forever, from the client's UiMapAssignment
-- table: { left, right, top, bottom } as world Y (east to west) and world X
-- (north to south).
local MAPS = {
  ["Mulgore"] = { 2479.167, -3675.0, 266.666, -3835.416 },
  ["Thunder Bluff"] = { 516.667, -527.083, -850.0, -1545.833 },
}
local function World(map, x, y)
  local b = MAPS[map]
  return b[1] - x / 100 * (b[1] - b[2]), b[3] - y / 100 * (b[3] - b[4])
end
local function OnMap(map, wy, wx)
  local b = MAPS[map]
  return (b[1] - wy) / (b[1] - b[2]) * 100, (b[3] - wx) / (b[3] - b[4]) * 100
end
-- A spot the game showed, on Forever's Mulgore map.
local function OnMulgore(map, x, y)
  if map == "Mulgore" then return x, y end
  return OnMap("Mulgore", World(map, x, y))
end
local function Off(ax, ay, bx, by) return math.max(math.abs(ax - bx), math.abs(ay - by)) end

local S = ns.Sources
local MULGORE = 215

print("")
print("bluff spots")

-- 1. Vendors and trainers.
local compared, near, bluff, inCity = 0, 0, 0, 0
for npc, row in pairs(S.NPCS) do
  local seen = ns.ForeverNPCs[npc]
  if row[2] == MULGORE and seen and MAPS[seen[2]] then
    local x, y = OnMulgore(seen[2], seen[3], seen[4])
    compared = compared + 1
    if Off(x, y, row[3], row[4]) <= 1.5 then
      near = near + 1
    else
      print(string.format("  %s: data %.1f, %.1f, game %.1f, %.1f", row[1], row[3], row[4], x, y))
    end
    if seen[2] == "Thunder Bluff" then
      bluff = bluff + 1
      local cx, cy = OnMap("Thunder Bluff", World("Mulgore", row[3], row[4]))
      if cx > 5 and cx < 95 and cy > 5 and cy < 95 then inCity = inCity + 1 end
    end
  end
end
check("vendors and trainers the game showed are compared", compared >= 5, true)
check("every Mulgore vendor and trainer sits where the game showed it", near, compared)
check("Thunder Bluff's vendors and trainers are compared", bluff >= 6, true)
check("every Thunder Bluff vendor and trainer lands in the city", inCity, bluff)

-- 2. Quest givers, matched by name: Forever's own quests are given by the
-- same people. Some were seen at more than one spot (Morin Cloudstalker
-- walks his camp); the nearest counts.
local shown = {}
for _, q in pairs(ns.ForeverQuests) do
  if MAPS[q.zone] and q.giver and q.x then
    local x, y = OnMulgore(q.zone, q.x, q.y)
    shown[q.giver] = shown[q.giver] or {}
    table.insert(shown[q.giver], { x, y })
  end
end
local function Nearest(list, x, y)
  local best
  for _, p in ipairs(list) do
    if not best or Off(p[1], p[2], x, y) < Off(best[1], best[2], x, y) then best = p end
  end
  return best
end
local givers, close, done = 0, 0, {}
for _, q in pairs(S.QUESTS) do
  local seen = shown[q[6]] and Nearest(shown[q[6]], q[8], q[9])
  if q[7] == MULGORE and seen and not done[q[6]] then
    done[q[6]] = true
    givers = givers + 1
    if Off(seen[1], seen[2], q[8], q[9]) <= 1.5 then
      close = close + 1
    else
      print(string.format("  %s: data %.1f, %.1f, game %.1f, %.1f", q[6], q[8], q[9], seen[1], seen[2]))
    end
  end
end
check("quest givers the game showed are compared", givers >= 10, true)
check("every Mulgore quest giver sits where the game showed them", close, givers)

-- 3. Another zone stays as Classic had it.
local corina = S.NPCS[54]
check("Elwynn's spots are left alone", corina and corina[3] == 41.5 and corina[4] == 65.9, true)

print("")
if failures > 0 then error(string.format("%d bluff spot check(s) failed", failures)) end
print("  all bluff spot checks passed")
print("")
