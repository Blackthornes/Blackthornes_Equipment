"""Writes Data/QuestStarts.lua: where to get the item that starts a quest.

Run from the repository root, after tools/make_sources.py, with pfQuest
checked out somewhere and a Farmer checkout beside this one:

    python tools/make_quest_starts.py <pfQuest> [path to Blackthornes_Farmer]

Some quests start from an item rather than a person: The Demon Scarred
Cloak starts from a cloak that Ghost Howl drops in Mulgore. Data/Sources.lua
names only the item for those (its zone is 0), which tells the player
nothing about where to go. For each such quest in Sources.QUESTS this writes
the item and up to three places to get it: the mobs that drop it (zone, one
real spawn spot, level, drop chance, and whether it is a rare), the objects
it is found in, the dungeon boss that drops it (the dungeon is its place,
with no spot), or the vendors that sell it.

What Farmer saw dropping on WoW: Forever comes first (its Data/Data_Harvested
.lua names mob, zone, spot, levels and chance, never the player), then
pfQuest's Classic data. A spot is always one that a source gives; none is
made up. Without a Farmer checkout, only Classic data is used.

Options:
    --stdout   print the file instead of writing it
"""

import collections
import os
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_sources import load_pfquest, lua_string, num  # noqa: E402
from forever_drops import load_harvest, load_sources  # noqa: E402
from lupa import lua51  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT = os.path.join(ROOT, "Data", "QuestStarts.lua")

MOST = 3          # places kept per item
RARE = {"2", "4"}  # pfQuest unit rank: 2 rare elite, 4 rare
ELITE = {"1", "2", "3"}


def spot(entry, prefer=None):
    """The zone a mob or object is mostly in (the `prefer` zone ID when it
    has any spawn there), and the real spawn there nearest the middle of
    its spawns: a spot it does stand at."""
    coords = entry and entry["coords"]
    if not coords:
        return None
    spots = [coords[i] for i in coords]
    spots = [s for s in spots if s and s[3]]
    if not spots:
        return None
    zone = collections.Counter(s[3] for s in spots).most_common(1)[0][0]
    if prefer and any(s[3] == prefer for s in spots):
        zone = prefer
    here = [s for s in spots if s[3] == zone]
    mx = sum(float(s[1]) for s in here) / len(here)
    my = sum(float(s[2]) for s in here) / len(here)
    best = min(here, key=lambda s: (float(s[1]) - mx) ** 2 + (float(s[2]) - my) ** 2)
    return zone, round(float(best[1]), 1), round(float(best[2]), 1), len(here)


def levels(text):
    """pfQuest's "12" or "10-12" as (low, high)."""
    if not text:
        return 0, 0
    parts = [int(p) for p in str(text).split("-") if p.strip().isdigit()]
    if not parts:
        return 0, 0
    return min(parts), max(parts)


def load_forever(lua, farmer):
    """What Farmer saw dropping on Forever, by item name: rows of (mob, zone,
    x, y, lowest level, highest level, chance). Empty without a Farmer
    checkout."""
    forever = collections.defaultdict(list)
    if not os.path.exists(os.path.join(farmer, "Data", "Data_Harvested.lua")):
        return forever
    harvested = load_harvest(lua, farmer)
    for i in harvested:
        item = harvested[i]
        rows = item["sources"]
        for j in (rows or {}):
            row = rows[j]
            coords = row["coords"]
            if not (row["name"] and row["zone"] and coords):
                continue
            forever[item["name"]].append((
                row["name"], row["zone"], round(float(coords[1]), 1), round(float(coords[2]), 1),
                int(row["minLevel"] or 0), int(row["maxLevel"] or 0), row["chance"]))
    return forever


def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    if not args:
        raise SystemExit(__doc__)
    pfq = load_pfquest(Path(args[0]))
    farmer = args[1] if len(args) > 1 else os.path.join(os.path.dirname(ROOT), "Blackthornes_Farmer")

    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    sources = load_sources(lua)

    forever = load_forever(lua, farmer)

    pf_quests = pfq["quests"]["data"]
    pf_items = pfq["items"]["data"]
    units, objects = pfq["units"]["data"], pfq["objects"]["data"]
    unit_names, object_names = pfq["units"]["enUS"], pfq["objects"]["enUS"]
    item_names, zone_names = pfq["items"]["enUS"], pfq["zones"]["enUS"]

    starts = {}
    for qid in sources.QUESTS:
        quest = sources.QUESTS[qid]
        if quest[7] != 0:
            continue
        pq = pf_quests[qid]
        start = pq and pq["start"]
        if not (start and start["I"]):
            continue
        iid = start["I"][1]
        name = item_names[iid]
        if not name:
            continue
        places = []
        seen = set()
        for row in sorted(forever.get(name, []), key=lambda r: -(r[6] or 0)):
            if row[0] in seen:
                continue
            seen.add(row[0])
            places.append(("mob", row[0], row[1], row[2], row[3], row[4], row[5],
                           row[6], "", True))
        entry = pf_items[iid]
        classic = []
        for uid, chance in ((entry and entry["U"]) and {k: entry["U"][k] for k in entry["U"]} or {}).items():
            who, where = unit_names[uid], spot(units[uid])
            boss = sources.BOSSES[uid]
            if who and boss and who not in seen:
                # A dungeon or raid boss: no spot outside, the dungeon is the place.
                dungeon = sources.DUNGEONS[boss[2]]
                if dungeon:
                    classic.append((float(chance or 0), ("boss", who, dungeon[1], 0, 0,
                                                         int(boss[3] or 0), int(boss[3] or 0),
                                                         chance, "", False)))
                    continue
            if not (who and where and zone_names[where[0]]) or who in seen:
                continue
            low, high = levels(units[uid]["lvl"])
            rank = str(units[uid]["rnk"] or "")
            kind = "rare" if rank in RARE else "elite" if rank in ELITE else ""
            classic.append((float(chance or 0), ("mob", who, zone_names[where[0]], where[1], where[2],
                                                 low, high, chance, kind, False)))
        for oid, chance in ((entry and entry["O"]) and {k: entry["O"][k] for k in entry["O"]} or {}).items():
            what, where = object_names[oid], spot(objects[oid])
            if not (what and where and zone_names[where[0]]) or what in seen:
                continue
            classic.append((float(chance or 0), ("object", what, zone_names[where[0]], where[1], where[2],
                                                 0, 0, chance, "", False)))
        for uid in ((entry and entry["V"]) and [k for k in entry["V"]] or []):
            who, where = unit_names[uid], spot(units[uid])
            if not (who and where and zone_names[where[0]]) or who in seen:
                continue
            classic.append((100.0, ("vendor", who, zone_names[where[0]], where[1], where[2],
                                    0, 0, None, "", False)))
        for _, row in sorted(classic, key=lambda c: (-c[0], c[1][1])):
            if row[1] in seen:
                continue
            seen.add(row[1])
            places.append(row)
        total = len(places)
        starts[qid] = (iid, name, places[:MOST], total)

    out = []
    w = out.append
    w("-- Blackthornes Equipment -- Data/QuestStarts.lua")
    w("-- Where to get the item that starts a quest, for quests in")
    w("-- Sources.QUESTS that start from an item rather than a person.")
    w("--")
    w("-- Generated by tools/make_quest_starts.py, never typed by hand: what Farmer")
    w("-- saw dropping on WoW: Forever first, then pfQuest's Classic data. Every")
    w("-- spot is one a source gives (a real spawn), never a made-up one.")
    w("")
    w("local _, ns = ...")
    w("")
    w("local Sources = ns.Sources")
    w("")
    w("-- [quest] = { item ID, item name, how many places in all, then up to")
    w(f"-- {MOST} places: {{ kind (\"mob\", \"object\", \"boss\" or \"vendor\"), name, zone")
    w("-- (a boss's is its dungeon or raid, with x and y 0), x, y,")
    w("-- lowest level, highest level, drop chance %, \"rare\" or \"elite\" or \"\",")
    w("-- f = true when seen on Forever } }.")
    w("Sources.STARTS = {")
    for qid in sorted(starts):
        iid, name, places, total = starts[qid]
        rows = []
        for kind, who, zone, x, y, low, high, chance, rank, f in places:
            chance_text = num(round(float(chance), 1)) if chance is not None else "nil"
            rows.append(f"{{ \"{kind}\", {lua_string(who)}, {lua_string(zone)}, {num(x)}, {num(y)}, "
                        f"{low}, {high}, {chance_text}, \"{rank}\"{', f = true' if f else ''} }}")
        w(f"    [{qid}] = {{ {iid}, {lua_string(name)}, {total}" + "".join(", " + r for r in rows) + " },")
    w("}")
    text = "\n".join(out) + "\n"
    if "--stdout" in argv:
        sys.stdout.write(text)
        return
    with open(OUTPUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print(f"wrote {OUTPUT}: {len(starts)} quests, "
          f"{sum(1 for s in starts.values() if s[2])} with a place to get their item")


if __name__ == "__main__":
    main(sys.argv[1:])
