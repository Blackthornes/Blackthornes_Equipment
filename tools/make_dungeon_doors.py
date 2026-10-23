"""Writes Data/DungeonDoorSpots.lua: where each dungeon's door stands, so
the arrow and the map pin point at the door before a player has ever
walked in.

Run from the repository root:

    python tools/make_dungeon_doors.py <tables folder> [--build 1.60.1.70450] [--stdout]

The tables folder holds the Forever client's game tables as CSV, one file
per table. Four are read: Map (each instance's entrance spot on its
continent), AreaPOI (the map's own label for a dungeon, nearer the cave
mouth where there is one), UiMap and UiMapAssignment (to turn a spot in
the world into a spot on a zone's map). The tables are never copied into
the repository; only a zone and a spot for each dungeon go in the file.

The dungeons are those in Data/Sources.lua and Data/DungeonQuests.lua. A
spot is kept only when it lands in the zone the data names for the door
(Blackrock Mountain's doors land in Searing Gorge, else Burning Steppes),
so a wrong spot is left out rather than shipped. A dungeon with no spot
in the tables keeps only its zone, as before. A door the player walked
through (Logic/DungeonDoors.lua) always wins over these.

Rerun it whenever the client tables are pulled again, and after
tools/make_dungeon_quests.py or tools/forever_drops.py add a dungeon.

Options:
    --build    the client build, written in the file's header
    --stdout   print the file instead of writing it
"""

import csv
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT = os.path.join(ROOT, "Data", "DungeonDoorSpots.lua")
SOURCES = os.path.join(ROOT, "Data", "Sources.lua")
PLACES = os.path.join(ROOT, "Data", "DungeonQuests.lua")

# The zones Blackrock Mountain's doors are reached from, first wins.
MOUNTAIN = "Blackrock Mountain"
MOUNTAIN_ZONES = ("Searing Gorge", "Burning Steppes")

# The map's label for a dungeon the data calls by another name.
LABELS = {"Sunken Temple": "Temple of Atal'Hakkar"}

# A zone map on UiMap's Type column.
ZONE_TYPE = "3"

ROW = re.compile(r'^\s+\["(\w+)"\] = \{ "((?:[^"\\]|\\.)*)", (?:-?\d+, -?\d+, )?"((?:[^"\\]|\\.)*)"', re.M)


def read_csv(folder, name):
    with open(os.path.join(folder, name + ".csv"), encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def number(value):
    try:
        n = float(value)
    except (TypeError, ValueError):
        return None
    return n if n == n else None


def block(text, start):
    """The text of one table in a Lua file, from its opening line to its close."""
    at = text.find(start)
    if at < 0:
        return ""
    end = text.find("\n}", at)
    return text[at:end if end >= 0 else len(text)]


def read_dungeons(sources_path, places_path):
    """{ key: (name, door zone or None) } from both data files."""
    dungeons = {}
    with open(sources_path, encoding="utf-8") as f:
        for key, name, door in ROW.findall(block(f.read(), "Sources.DUNGEONS = {")):
            dungeons[key] = (name, door or None)
    if os.path.exists(places_path):
        with open(places_path, encoding="utf-8") as f:
            for key, name, door in ROW.findall(block(f.read(), "ns.FOREVER_DUNGEON_PLACES = {")):
                if key not in dungeons or door:
                    dungeons[key] = (name, door or None)
    return dungeons


class Zones:
    """Turns a spot in the world into a spot on each zone map holding it."""

    def __init__(self, folder):
        names = {}
        for row in read_csv(folder, "UiMap"):
            if row.get("Type") == ZONE_TYPE:
                names[row["ID"]] = row["Name_lang"]
        self.parts = []
        for row in read_csv(folder, "UiMapAssignment"):
            name = names.get(row.get("UiMapID"))
            values = [number(row.get(k)) for k in
                      ("Region_0", "Region_1", "Region_3", "Region_4", "UiMin_0", "UiMin_1", "UiMax_0", "UiMax_1")]
            if name and all(v is not None for v in values) and values[2] > values[0] and values[3] > values[1]:
                self.parts.append((row.get("MapID"), name, values))

    def at(self, continent, wx, wy):
        """{ zone name: (x, y) } on a 0 to 100 map, for every zone holding the spot."""
        found = {}
        for mapid, name, (x0, y0, x1, y1, u0, v0, u1, v1) in self.parts:
            if mapid != continent or not (x0 <= wx <= x1 and y0 <= wy <= y1):
                continue
            u = u0 + (u1 - u0) * (y1 - wy) / (y1 - y0)
            v = v0 + (v1 - v0) * (x1 - wx) / (x1 - x0)
            if 0 <= u <= 1 and 0 <= v <= 1 and name not in found:
                found[name] = (round(u * 100, 1), round(v * 100, 1))
        return found


def pick(found, door):
    """The zone and spot to keep for a door zone, or None."""
    if not door:
        return None
    wanted = MOUNTAIN_ZONES if door == MOUNTAIN else (door,)
    for zone in wanted:
        if zone in found:
            return (zone,) + found[zone]
    return None


def spots(folder, dungeons):
    zones = Zones(folder)
    maps = {row["ID"]: row for row in read_csv(folder, "Map")}
    labels = {}
    for row in read_csv(folder, "AreaPOI"):
        labels.setdefault(row.get("Name_lang", "").lower(), []).append(row)
    out = {}
    for key, (name, door) in dungeons.items():
        mapid = re.match(r"\d+", key).group(0)
        info = maps.get(mapid)
        tries = []
        # The map's own label first, then the instance's entrance spot.
        names = [name, LABELS.get(name, ""), (info or {}).get("MapName_lang", "")]
        for label in dict.fromkeys(n.lower() for n in names if n):
            for row in labels.get(label, []):
                tries.append((row.get("ContinentID"), number(row.get("Pos_0")), number(row.get("Pos_1"))))
        if info and info.get("CorpseMapID") not in (None, "", "-1"):
            tries.append((info["CorpseMapID"], number(info.get("Corpse_0")), number(info.get("Corpse_1"))))
        for continent, wx, wy in tries:
            if wx is None or wy is None or (wx == 0 and wy == 0):
                continue
            chosen = pick(zones.at(continent, wx, wy), door)
            if chosen:
                out[key] = chosen
                break
    return out


def lua_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def render(found, build):
    lines = [
        "-- Blackthornes Equipment -- Data/DungeonDoorSpots.lua",
        "-- Where each dungeon's door stands: the zone and a spot on that zone's",
        "-- map, 0 to 100, by the same key as Sources.DUNGEONS. A door the player",
        "-- walked through (Logic/DungeonDoors.lua) wins over these.",
        "--",
        "-- Generated by tools/make_dungeon_doors.py from the Forever client's",
        "-- game tables (build %s). Do not edit by hand: rerun the tool." % build,
        "",
        "local _, ns = ...",
        "",
        "ns.DUNGEON_DOOR_SPOTS = {",
    ]

    def order(key):
        digits = re.match(r"\d+", key).group(0)
        return (int(digits), key)

    for key in sorted(found, key=order):
        zone, x, y = found[key]
        lines.append('    ["%s"] = { %s, %s, %s },' % (key, lua_string(zone), repr(x), repr(y)))
    lines.append("}")
    return "\n".join(lines) + "\n"


def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    build = "unknown"
    if "--build" in argv:
        at = argv.index("--build")
        if at + 1 < len(argv):
            build = argv[at + 1]
            if build in args:
                args.remove(build)
    if not args:
        print(__doc__)
        return 2
    found = spots(args[0], read_dungeons(SOURCES, PLACES))
    if not found:
        print("No door spots found; the data file was left as it was.")
        return 1
    text = render(found, build)
    if "--stdout" in argv:
        sys.stdout.write(text)
    else:
        with open(OUTPUT, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        print("Wrote %d door spots to %s" % (len(found), os.path.relpath(OUTPUT, ROOT)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
