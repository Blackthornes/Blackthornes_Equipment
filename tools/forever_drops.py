"""Writes Data/ForeverDrops.lua: what dungeon and raid bosses really drop on
WoW: Forever, from Blackthornes Farmer's loot records.

Run from the repository root with a Farmer checkout beside this one:

    python tools/forever_drops.py [path to Blackthornes_Farmer]

Farmer counts every corpse looted on Forever and writes the totals to its
Data/Data_Harvested.lua (tools/harvest_import.py there). That file names the
mob and the zone, never the player, so it is safe to read. This keeps the
rows looted inside a dungeon or raid this addon knows (by the zone's name),
and writes them out by item ID, mob name and dungeon. The finder lays them
over the Classic drops: a drop seen on Forever is tagged [Forever], with
Forever's own drop rate once enough corpses have been counted for one, and
gear Classic never had at that boss shows up too.

Dungeons and raids Forever added (Ruins of Lordaeron and the like) are not
in Classic's list, so FOREVER_DUNGEONS below names them, by the instance's
map ID from the Forever client's game tables (the number GetInstanceInfo
gives inside, as Classic's are keyed). A Forever dungeon Farmer saw drops in
is written into Sources.DUNGEONS too, with its level range from the levels
of the mobs Farmer looted there (1 to 60 when none could be read). A new
Forever dungeon needs one line in FOREVER_DUNGEONS.

Some of what Forever changed is known before anyone here loots it: a new
dungeon's level range and door, and which boss drops which new gear.
tools/forever_facts.json holds those facts, each checked by hand, item IDs
checked against the Forever client's game tables (pass --tables to check
them again). A fact never replaces what Farmer saw: Farmer's rate wins,
and a fact's drop has no rate (0). For Classic's dungeons only gear
Classic's data never had as a drop is added.

Everything Farmer saw is kept, gear or not: the game itself says what an
item is, and the finder only judges what can be worn. Item stats are never
copied from anywhere: the finder always reads them from the game, so gear
whose stats Forever changed is judged as it is now.

Options:
    --stdout          print the file instead of writing it
    --tables <folder> the Forever client's game tables: leave out a fact's
                      item the tables do not have
"""

import csv
import json
import os
import re
import sys

from lupa import lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT = os.path.join(ROOT, "Data", "ForeverDrops.lua")
FACTS = os.path.join(ROOT, "tools", "forever_facts.json")


# Forever's own dungeons and raids, by map ID: name as the game gives it
# inside, the zone the door is in (None when not known: the finder then names
# the dungeon alone and sends nobody anywhere), and True for a raid. Names
# that are also an open world zone (Forever's Deadwind Pass instance) are
# left out, or loot from the zone would be counted as the dungeon's.
FOREVER_DUNGEONS = {
    2784: ("Demon Fall Canyon", "Ashenvale", False),
    2806: ("Shadow Hold", None, False),
    2807: ("Burning of Andorhal", "Western Plaguelands", False),
    2817: ("Starfall Barrow Den", None, False),
    2875: ("Karazhan Crypts", "Deadwind Pass", False),
    2902: ("The Scarab Dais", None, False),
    2959: ("City of Dalaran", "Alterac Mountains", False),
    2998: ("Excavation Site: Wetlands", "Wetlands", False),
    2999: ("Ruins of Lordaeron", "Tirisfal Glades", False),
    3065: ("The Hall of Thanes", "Ironforge", False),
    3109: ("Manor Mistmantle", None, False),
    2720: ("The Searing Basin", None, False),
    2789: ("The Tainted Scar", "Blasted Lands", True),
    2791: ("Storm Cliffs", "Azshara", True),
    2804: ("The Crystal Vale", "Silithus", True),
    2832: ("Nightmare Grove", None, True),
    2856: ("Scarlet Enclave", "Eastern Plaguelands", True),
}

# A Forever dungeon whose mobs gave no level is listed for every level; the
# finder still asks the game what level the gear needs.
LOWEST, HIGHEST = 1, 60


def plain(name):
    """A zone or mob name as compared: lower case, no leading "The"."""
    return re.sub(r"^the\s+", "", (name or "").strip().lower())


def load_sources(lua):
    lua.execute("ns = {}")
    chunk = lua.eval("function(path) return assert(loadfile(path)) end")(
        os.path.join(ROOT, "Data", "Sources.lua"))
    chunk("Blackthornes_Equipment", lua.eval("ns"))
    return lua.eval("ns.Sources")


def load_harvest(lua, farmer):
    path = os.path.join(farmer, "Data", "Data_Harvested.lua")
    if not os.path.exists(path):
        raise SystemExit(f"no {path}: run tools/harvest_import.py in Farmer first")
    lua.execute("""
        harvested = {}
        farmerNS = { DB = { RegisterItem = function(_, item)
            harvested[#harvested + 1] = item
        end } }
    """)
    chunk = lua.eval("function(path) return assert(loadfile(path)) end")(path)
    chunk("Blackthornes_Farmer", lua.eval("farmerNS"))
    return lua.eval("harvested")


def load_facts(path=FACTS):
    """tools/forever_facts.json, or nothing when it is missing."""
    if not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def table_items(tables):
    """Every item ID in the client's Item table."""
    with open(os.path.join(tables, "Item.csv"), encoding="utf-8") as f:
        return {int(r["ID"]) for r in csv.DictReader(f)}


def collect(sources, items, facts=None, known=None):
    """What dungeons and raids were seen dropping on Forever, and the Forever
    dungeons among them: ({itemID: {(mob, key): chance}}, {key: row}).
    `facts` adds what tools/forever_facts.json knows; `known`, when given,
    is the item IDs the client has, and a fact's item outside it is left
    out."""
    facts = facts or {}
    dungeons = {}          # plain name -> key
    for key in sources.DUNGEONS:
        name = sources.DUNGEONS[key][1]
        if not re.search(r"\d(Graveyard|Library|Armory|Cathedral)$", key):
            dungeons[plain(name)] = key
    forever = {}           # plain name -> key, only the ones Classic lacks
    for mapID, (name, _, _) in FOREVER_DUNGEONS.items():
        if str(mapID) not in sources.DUNGEONS and plain(name) not in dungeons:
            forever[plain(name)] = str(mapID)
    bosses = {}            # (plain name, dungeon key) -> key with wing
    for uid in sources.BOSSES:
        boss = sources.BOSSES[uid]
        base = re.sub(r"[A-Za-z]+$", "", boss[2])
        bosses[(plain(boss[1]), base)] = boss[2]

    drops = {}             # itemID -> {(mob, key): chance or 0}
    levels = {}            # Forever dungeon key -> [lowest, highest]
    for item in items.values():
        if not item.id or not item.sources:
            continue
        for source in item.sources.values():
            if source.provenance != "forever":
                continue
            zone = plain(source.zone)
            key = dungeons.get(zone) or forever.get(zone)
            if not key:
                continue
            mob = source.name
            if zone in forever:
                seen = levels.setdefault(key, [None, None])
                if source.minLevel and (seen[0] is None or source.minLevel < seen[0]):
                    seen[0] = int(source.minLevel)
                top = source.maxLevel or source.minLevel
                if top and (seen[1] is None or top > seen[1]):
                    seen[1] = int(top)
            else:
                key = bosses.get((plain(mob), key), key)
            chance = float(source.chance) if source.chance else 0
            drops.setdefault(int(item.id), {})[(mob, key)] = chance

    forever_keys = set(forever.values())
    for key, by_boss in (facts.get("loot") or {}).items():
        base = re.sub(r"[A-Za-z]+$", "", key)
        if base not in forever_keys and base not in sources.DUNGEONS:
            continue
        for mob, ids in by_boss.items():
            where = key if base in forever_keys else bosses.get((plain(mob), base), key)
            for itemID in ids:
                itemID = int(itemID)
                if known is not None and itemID not in known:
                    continue
                classic = sources.ITEMS and sources.ITEMS[itemID]
                if base not in forever_keys and classic and classic.d:
                    continue
                if base in forever_keys:
                    levels.setdefault(base, [None, None])
                seen = drops.setdefault(itemID, {})
                if not any(plain(m) == plain(mob) and re.sub(r"[A-Za-z]+$", "", k) == base
                           for m, k in seen):
                    seen[(mob, where)] = 0

    places = facts.get("dungeons") or {}
    added = {}
    for key, (low, high) in levels.items():
        name, door, raid = FOREVER_DUNGEONS[int(key)]
        place = places.get(key) or {}
        low = place.get("low") or low or LOWEST
        high = max(place.get("high") or high or HIGHEST, low)
        added[key] = (name, low, high, door or name, raid)
    return drops, added


def lua_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def render(drops, added):
    out = [
        "-- Blackthornes Equipment -- Data/ForeverDrops.lua",
        "-- What dungeon and raid mobs have been seen dropping on WoW: Forever.",
        "--",
        "-- Generated by tools/forever_drops.py from Blackthornes Farmer's loot",
        "-- records (its Data/Data_Harvested.lua) and tools/forever_facts.json. Do",
        "-- not edit by hand: the next import overwrites this file. Each item lists",
        "-- { mob, dungeon, drop chance % (0 when too few corpses were counted for a",
        "-- rate, or no one here has looted it yet) }.",
        "",
        "local _, ns = ...",
        "",
    ]
    if added:
        out += [
            "-- Dungeons and raids Forever added, laid beside Classic's: name, levels",
            "-- (the known range, else those of the mobs looted there), the zone the",
            "-- door is in (its own name when not known), \"\" for both sides, and true",
            "-- for a raid.",
        ]
        for key in sorted(added, key=int):
            name, low, high, door, raid = added[key]
            row = f'{{ {lua_string(name)}, {low}, {high}, {lua_string(door)}, ""'
            row += ", true }" if raid else " }"
            out.append(f'ns.Sources.DUNGEONS["{key}"] = ns.Sources.DUNGEONS["{key}"] or {row}')
        out.append("")
    out.append("ns.Sources.FOREVER = {")
    for itemID in sorted(drops):
        parts = []
        for (mob, key), chance in sorted(drops[itemID].items()):
            parts.append(f'{{ {lua_string(mob)}, "{key}", {chance:g} }}')
        out.append(f"    [{itemID}] = {{ {', '.join(parts)} }},")
    out += ["}", ""]
    return "\n".join(out)


def main(argv):
    tables = None
    if "--tables" in argv:
        at = argv.index("--tables")
        tables = argv[at + 1]
        argv = argv[:at] + argv[at + 2:]
    farmer = next((a for a in argv if not a.startswith("--")),
                  os.path.join(os.path.dirname(ROOT), "Blackthornes_Farmer"))
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    sources = load_sources(lua)
    known = table_items(tables) if tables else None
    drops, added = collect(sources, load_harvest(lua, farmer), load_facts(), known)
    text = render(drops, added)

    if "--stdout" in argv:
        print(text)
    else:
        with open(OUTPUT, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        print(f"{len(drops)} item(s) seen dropping in dungeons and raids on Forever"
              + (f", {len(added)} of Forever's own dungeon(s)" if added else ""))


if __name__ == "__main__":
    main(sys.argv[1:])
