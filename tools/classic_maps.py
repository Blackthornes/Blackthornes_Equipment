"""Moves Classic's map spots onto Forever's own maps.

Classic's spots (vendors, trainers, quest givers, mobs and objects in
Data/Sources.lua, Data/Crafts.lua, Data/DungeonQuests.lua,
Data/QuestStarts.lua and Data/QuestEnds.lua) are numbers on a zone's map.
Most of Forever's zone maps cover the same ground as Classic's, so the
numbers point at the same place. Mulgore's does not: Forever's map reaches
further on every side, so a Classic spot read on it lands north and west of
where the NPC stands. Thunder Bluff's vendors and trainers are kept on
Mulgore's map in that data, so they landed just north of the city.
Tradeskills found it first (2026-11-17); its tools/classic_maps.py holds
the same bounds.

The bounds below are where each map starts and ends in the world, as
{ left, right, top, bottom } in world Y (east to west) and world X (north to
south). Forever's come from its client's UiMapAssignment table. Classic's
are the ones its numbers were measured on. Every other zone already
matched, Thunder Bluff's own map too, so only Mulgore is listed.

make_sources.py's place() and make_quest_starts.py's spot() call
forever_spot() on every Classic spot, so the files they write (and
make_crafts.py, make_dungeon_quests.py and make_quest_ends.py, which use
them) are on Forever's map. To move the spots in files written before that:

    python tools/classic_maps.py [path to Blackthornes_Farmer]

It changes only Mulgore's numbers, and only once: a moved file says so in
its header and is left alone after that. In QuestStarts and QuestEnds a
spot Farmer saw on Forever (Data/Data_Harvested.lua) is already right and
is kept as it is: make_quest_ends.py and make_quest_starts.py take a mob's
spot from Farmer first. Farmer's spots have grown since, so a spot within
NEAR of one Farmer has for that mob counts as Farmer's.
"""

import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# zone: (Classic's bounds, Forever's bounds)
MOVED = {
    "Mulgore": (
        (2047.917, -3089.583, -272.917, -3697.917),
        (2479.167, -3675.0, 266.666, -3835.416),
    ),
}
# The Classic data's zone IDs for the zones above.
ZONE_IDS = {215: "Mulgore"}

# How near (in map steps) a QuestEnds or QuestStarts spot must be to one of
# Farmer's for that mob to count as Farmer's own.
NEAR = 1.5

MARK = "-- Mulgore's spots are on Forever's Mulgore map (tools/classic_maps.py)."


def forever_spot(zone, x, y):
    """(x, y) on Forever's map of the zone (a name, or a Classic zone ID),
    from Classic's x, y on it."""
    zone = ZONE_IDS.get(zone, zone)
    if zone not in MOVED:
        return x, y
    (cl, cr, ct, cb), (fl, fr, ft, fb) = MOVED[zone]
    world_y = cl - x / 100 * (cl - cr)
    world_x = ct - y / 100 * (ct - cb)
    return (fl - world_y) / (fl - fr) * 100, (ft - world_x) / (ft - fb) * 100


def _plain(v):
    """A number as make_sources.num() writes it: 37 or 37.5."""
    v = round(v, 1)
    return str(int(v)) if v == int(v) else str(v)


STR = r'"(?:\\.|[^"\\])*"'
NUM = r"(-?\d+(?:\.\d+)?)"
# A spot: the name before it, the zone (an ID or a name), then x, y.
BY_ID = re.compile("(" + STR + ", 215, )" + NUM + ", " + NUM)
BY_NAME = re.compile("(" + "(" + STR + ")" + ', "Mulgore", )' + NUM + ", " + NUM
)
FILES = {
    "Data/Sources.lua": BY_ID,
    "Data/Crafts.lua": BY_ID,
    "Data/DungeonQuests.lua": BY_NAME,
    "Data/QuestStarts.lua": BY_NAME,
    "Data/QuestEnds.lua": BY_NAME,
}


def farmer_spots(farmer):
    """Where Farmer saw each mob in Mulgore on Forever
    (Data/Data_Harvested.lua): { mob: {(x, y), ...} }."""
    from lupa import lua51
    path = Path(farmer) / "Data" / "Data_Harvested.lua"
    if not path.exists():
        raise SystemExit("no Farmer checkout at %s (its spots must be kept)" % farmer)
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        rows = {}
        local DB = {}
        function DB:RegisterItem(item)
            for _, s in ipairs(item.sources or {}) do
                if s.zone == "Mulgore" and s.coords then
                    rows[#rows + 1] = { item.name, s.name, s.coords[1], s.coords[2] }
                end
            end
        end
        ns = { DB = DB }
    """)
    lua.globals().chunk = path.read_text(encoding="utf-8")
    lua.execute("assert(loadstring(chunk))('Blackthornes_Farmer', ns)")
    spots = {}
    for row in lua.globals().rows.values():
        spots.setdefault(row[2], set()).add((float(row[3]), float(row[4])))
    return spots


def move_file(rel, seen=None):
    path = ROOT / rel
    text = path.read_text(encoding="utf-8")
    if MARK in text:
        return 0, 0
    moved = kept = 0
    pattern = FILES[rel]
    named = pattern is BY_NAME
    spots = seen or {}

    def swap(m):
        nonlocal moved, kept
        if named:
            x, y = float(m.group(3)), float(m.group(4))
            # Near where Farmer saw this mob: Forever's spot, kept.
            if any(max(abs(x - fx), abs(y - fy)) <= NEAR for fx, fy in spots.get(m.group(2)[1:-1], ())):
                kept += 1
                return m.group(0)
        else:
            x, y = float(m.group(2)), float(m.group(3))
        moved += 1
        nx, ny = forever_spot("Mulgore", x, y)
        return "%s%s, %s" % (m.group(1), _plain(nx), _plain(ny))

    text = pattern.sub(swap, text)
    text = text.replace("\nlocal _, ns = ...", "\n" + MARK + "\n\nlocal _, ns = ...", 1)
    path.write_text(text, encoding="utf-8", newline="\n")
    return moved, kept


def main(argv):
    farmer = argv[0] if argv else os.path.join(os.path.dirname(ROOT), "Blackthornes_Farmer")
    seen = farmer_spots(farmer)
    for rel in FILES:
        moved, kept = move_file(rel, seen)
        print(f"{rel}: {moved} Mulgore spot(s) moved, {kept} seen on Forever kept")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
