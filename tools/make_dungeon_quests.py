"""Writes Data/DungeonQuests.lua: every quest done inside a dungeon or raid.

Run from the repository root, after make_sources.py, with the same two
Classic 1.12 databases and the Forever client's game tables:

    python tools/make_dungeon_quests.py <mangoszero database> <pfQuest> \
        --tables <tables folder>

A quest counts as a dungeon's when Classic files it under that dungeon's
zone, or when what it asks for (a creature to kill, an object to use, an
item only creatures there drop) is inside one. Seasonal quests and quests
with no known start are left out, and so is every quest the Forever
client's QuestV2 table lacks. The tables hold quest IDs only, no names, so
Forever's own dungeon quests are learned in game (Logic/DungeonQuests.lua)
and folded in later, never typed here. Never edit the output by hand.
"""

import argparse
import collections
import csv
from pathlib import Path

import make_sources as ms
from forever_drops import FOREVER_DUNGEONS

OUTPUT = Path(__file__).resolve().parent.parent / "Data" / "DungeonQuests.lua"


def area_maps(tables):
    """Classic zone ID -> instance map ID, from the client's AreaTable."""
    out = {}
    with open(tables / "AreaTable.csv", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            m = int(r["ContinentID"])
            if m in ms.INSTANCES:
                out[int(r["ID"])] = m
    return out


def forever_quests(tables):
    with open(tables / "QuestV2.csv", encoding="utf-8") as f:
        return {int(r["ID"]) for r in csv.DictReader(f)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mangos")
    ap.add_argument("pfquest")
    ap.add_argument("--tables", required=True)
    ap.add_argument("--build", default="")
    args = ap.parse_args()

    mangos = Path(args.mangos) / "World" / "Setup" / "FullDB"
    pfq = ms.load_pfquest(Path(args.pfquest))
    tables = Path(args.tables)
    zone_map = area_maps(tables)
    on_forever = forever_quests(tables)

    units, objects = pfq["units"]["data"], pfq["objects"]["data"]
    unit_names, object_names = pfq["units"]["enUS"], pfq["objects"]["enUS"]
    item_names, quest_text = pfq["items"]["enUS"], pfq["quests"]["enUS"]
    pf_quests = pfq["quests"]["data"]
    zone_names = pfq["zones"]["enUS"]

    # Where creatures and objects stand, for quests filed under no zone.
    where_map = {}
    for r in ms.rows(mangos / "creature.sql", "creature"):
        if r["map"] in ms.INSTANCES:
            where_map.setdefault(r["id"], r["map"])
    for uid, m in ms.SUMMONED.items():
        where_map.setdefault(uid, m)
    instance_objects = {}
    for r in ms.rows(mangos / "gameobject.sql", "gameobject"):
        if r["map"] in ms.INSTANCES:
            instance_objects.setdefault(r["id"], r["map"])
    templates = {r["Entry"]: r for r in ms.rows(mangos / "creature_template.sql",
                                                "creature_template")}
    loot_users = collections.defaultdict(set)
    for uid, t in templates.items():
        if t["LootId"]:
            loot_users[t["LootId"]].add(uid)
    dropped_by = collections.defaultdict(set)
    for r in ms.rows(mangos / "creature_loot_template.sql", "creature_loot_template"):
        if r["mincountOrRef"] >= 0:
            dropped_by[r["item"]] |= loot_users.get(r["entry"], set())
    from_elsewhere = {r["item"] for r in ms.rows(mangos / "gameobject_loot_template.sql",
                                                 "gameobject_loot_template")}

    gear = set()
    for r in ms.rows(mangos / "item_template.sql", "item_template"):
        if r["class"] in (2, 4) and r["InventoryType"] in ms.EQUIPPABLE:
            gear.add(r["entry"])

    def objective_map(r):
        maps = collections.Counter()
        for i in range(1, 5):
            target = r[f"ReqCreatureOrGOId{i}"]
            if target > 0 and target in where_map:
                maps[where_map[target]] += 1
            elif target < 0 and -target in instance_objects:
                maps[instance_objects[-target]] += 1
            item = r[f"ReqItemId{i}"]
            owners = dropped_by.get(item) if item and item not in from_elsewhere else None
            if owners and all(o in where_map for o in owners):
                for o in owners:
                    maps[where_map[o]] += 1
        return maps.most_common(1)[0][0] if maps else None

    out = {}
    for r in ms.rows(mangos / "quest_template.sql", "quest_template"):
        qid = r["entry"]
        if qid not in on_forever:
            continue
        pq = pf_quests[qid]
        if not pq or not pq["start"] or pq["event"]:
            continue
        title = (quest_text[qid] and quest_text[qid]["T"]) or r["Title"]
        if not title or ms.BAD_TITLE.search(title):
            continue
        zone = r["ZoneOrSort"]
        m = zone_map.get(zone) if zone > 0 else None
        if m is None:
            m = objective_map(r)
        if m is None:
            continue

        start = pq["start"]
        giver = None
        if start["U"]:
            for i in start["U"]:
                uid = start["U"][i]
                where = ms.place(units[uid])
                if where and unit_names[uid]:
                    giver = (unit_names[uid], where[0], where[1], where[2],
                             ms.faction_of(units[uid]))
                    break
        if not giver and start["O"]:
            for i in start["O"]:
                oid = start["O"][i]
                where = ms.place(objects[oid])
                if where and object_names[oid]:
                    giver = (object_names[oid], where[0], where[1], where[2],
                             ms.faction_of(objects[oid]))
                    break
        if not giver and start["I"]:
            iid = start["I"][1]
            if item_names[iid]:
                giver = (item_names[iid], 0, 0, 0, "")
        if not giver:
            continue

        races = r["RequiredRaces"] or 0
        side = ""
        both = ms.ALLIANCE_RACES | ms.HORDE_RACES
        if races & both == races & ms.ALLIANCE_RACES and races & ms.ALLIANCE_RACES:
            side = "A"
        elif races & both == races & ms.HORDE_RACES and races & ms.HORDE_RACES:
            side = "H"
        elif giver[4] in ("A", "H"):
            side = giver[4]

        rewards = [r[f"RewChoiceItemId{i}"] for i in range(1, 7)] + \
                  [r[f"RewItemId{i}"] for i in range(1, 5)]
        reward = next((i for i in rewards if i in gear), 0) or next((i for i in rewards if i), 0)
        key = str(m)
        if m == ms.SM_MAP:
            key = "189"
        prev = r["PrevQuestId"] if r["PrevQuestId"] and r["PrevQuestId"] > 0 else 0
        out[qid] = (key, title, r["MinLevel"], r["QuestLevel"], side,
                    r["RequiredClasses"] or 0, giver[0], giver[1], giver[2], giver[3],
                    reward, prev)

    lines = [
        "-- Generated by tools/make_dungeon_quests.py from Classic's quest data,",
        "-- kept only for quests the Forever client has. Do not edit by hand.",
        "local _, ns = ...",
        "",
        "-- [questID] = { dungeon (a Sources.DUNGEONS key), title, lowest level,",
        "--   quest level, side (\"A\", \"H\" or \"\"), classes (0 for any), who or what",
        "--   starts it, its zone, x, y, a reward item (0 for none), the quest before }",
        "ns.DUNGEON_QUESTS = {",
    ]
    for qid in sorted(out):
        q = out[qid]
        lines.append("    [%d] = { %s, %s, %d, %d, %s, %d, %s, %s, %s, %s, %d, %d }," % (
            qid, ms.lua_string(q[0]), ms.lua_string(q[1]), q[2], q[3], ms.lua_string(q[4]),
            q[5], ms.lua_string(q[6]), ms.lua_string((q[7] and zone_names[q[7]]) or ""), ms.num(q[8]), ms.num(q[9]),
            q[10], q[11]))
    lines.append("}")
    lines.append("")
    lines += [
        "-- Forever's own dungeons and raids, by the map ID the game gives inside:",
        "-- name, the zone the door is in (\"\" when not known) and true for a",
        "-- raid. Their quests are learned in game (Logic/DungeonQuests.lua).",
        "ns.FOREVER_DUNGEON_PLACES = {",
    ]
    for m in sorted(FOREVER_DUNGEONS):
        name, door, raid = FOREVER_DUNGEONS[m]
        lines.append('    ["%d"] = { %s, %s%s },' % (m, ms.lua_string(name), ms.lua_string(door or ""),
                                                  ", true" if raid else ""))
    lines.append("}")
    lines.append("")
    OUTPUT.write_text("\n".join(lines), encoding="utf-8", newline="\n")
    by = collections.Counter(q[0] for q in out.values())
    print(f"wrote {len(out)} dungeon quests to {OUTPUT}")
    for k, n in sorted(by.items(), key=lambda x: -x[1]):
        print(" ", ms.INSTANCES.get(int(k), (k,))[0], n)


if __name__ == "__main__":
    main()
