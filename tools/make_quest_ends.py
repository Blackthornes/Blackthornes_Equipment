"""Writes Data/QuestEnds.lua: where a quest is done and where it is handed in.

Run from the repository root, after tools/make_sources.py, with pfQuest
checked out somewhere and a Farmer checkout beside this one:

    python tools/make_quest_ends.py <pfQuest> [path to Blackthornes_Farmer]

Data/Sources.lua says who starts each quest. Once the quest is in the log,
that is the wrong place to send the player: The Ravaged Caravan is taken
from Morin Cloudstalker but done, and handed in, at a supply crate across
Mulgore. For every quest in Sources.QUESTS this writes who or what takes it
back (an NPC or an object, with one real spawn spot) and one place to work
on it: the first objective that has a spot, whether a mob to kill, an
object to use, or an item to collect (then the mob, object or vendor it
comes from, the dungeon for a dungeon boss).

For items, what Farmer saw dropping on WoW: Forever comes first (its
Data/Data_Harvested.lua names mob, zone and spot, never the player), then
pfQuest's Classic data. A spot is always one that a source gives; none is
made up, and a quest with nothing known is left out.

Options:
    --stdout   print the file instead of writing it
"""

import os
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_sources import load_pfquest, lua_string, num  # noqa: E402
from forever_drops import load_sources  # noqa: E402
from make_quest_starts import load_forever, spot  # noqa: E402
from lupa import lua51  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT = os.path.join(ROOT, "Data", "QuestEnds.lua")


def ids(table):
    """A pfQuest list of IDs as a Python list, in its order."""
    if table is None:
        return []
    return [table[k] for k in sorted(table)]


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

    # Where a mob stands in two zones, the one the quest is given in wins:
    # Supervisor Fizsprocket has a stray spawn in The Barrens beside his
    # mine in Mulgore.
    home = [None]

    def unit_place(uid, kind="mob"):
        """(kind, name, zone, x, y) for an NPC, or a boss's dungeon."""
        who = unit_names[uid]
        if not who:
            return None
        boss = sources.BOSSES[uid]
        if boss and sources.DUNGEONS[boss[2]]:
            return ("boss", who, sources.DUNGEONS[boss[2]][1], 0, 0)
        where = spot(units[uid], home[0])
        if not (where and zone_names[where[0]]):
            return None
        return (kind, who, zone_names[where[0]], where[1], where[2])

    def object_place(oid):
        what, where = object_names[oid], spot(objects[oid], home[0])
        if not (what and where and zone_names[where[0]]):
            return None
        return ("object", what, zone_names[where[0]], where[1], where[2])

    def item_place(iid):
        """Where to get an item: Forever's best drop, else Classic's."""
        name = item_names[iid]
        if not name:
            return None
        rows = sorted(forever.get(name, []), key=lambda r: -(r[6] or 0))
        if rows:
            row = rows[0]
            return ("mob", row[0], row[1], row[2], row[3])
        entry = pf_items[iid]
        if not entry:
            return None
        found = []
        for key, kind in (("U", "mob"), ("O", "object")):
            table = entry[key]
            for k in (table or {}):
                place = unit_place(k) if kind == "mob" else object_place(k)
                if place:
                    found.append((float(table[k] or 0), place))
        for uid in ([k for k in entry["V"]] if entry["V"] else []):
            place = unit_place(uid, "vendor")
            if place:
                found.append((100.0, place))
        if not found:
            return None
        return sorted(found, key=lambda f: (-f[0], f[1][1]))[0][1]

    ends = {}
    for qid in sources.QUESTS:
        pq = pf_quests[qid]
        if not pq:
            continue
        home[0] = sources.QUESTS[qid][7] or None
        done = None
        end = pq["end"]
        if end:
            for uid in ids(end["U"]):
                done = unit_place(uid, "npc")
                if done:
                    break
            if not done:
                for oid in ids(end["O"]):
                    done = object_place(oid)
                    if done:
                        break
        goal, item = None, None
        obj = pq["obj"]
        if obj:
            for uid in ids(obj["U"]):
                goal = unit_place(uid)
                if goal:
                    break
            if not goal:
                for oid in ids(obj["O"]):
                    goal = object_place(oid)
                    if goal:
                        break
            if not goal:
                for iid in ids(obj["I"]):
                    goal = item_place(iid)
                    if goal:
                        item = item_names[iid]
                        break
        if done or goal:
            ends[qid] = (done, goal, item)

    def row(place):
        kind, name, zone, x, y = place
        return f"\"{kind}\", {lua_string(name)}, {lua_string(zone)}, {num(x)}, {num(y)}"

    out = []
    w = out.append
    w("-- Blackthornes Equipment -- Data/QuestEnds.lua")
    w("-- Where a quest in Sources.QUESTS is done and where it is handed in, so")
    w("-- a quest already in the log sends the player there, not to its giver.")
    w("--")
    w("-- Generated by tools/make_quest_ends.py, never typed by hand: pfQuest's")
    w("-- Classic data, with what Farmer saw dropping on WoW: Forever first for")
    w("-- items. Every spot is one a source gives (a real spawn), never a made-up one.")
    w("")
    w("local _, ns = ...")
    w("")
    w("local Sources = ns.Sources")
    w("")
    w("-- [quest] = { who or what takes it back: kind (\"npc\" or \"object\"), name,")
    w("-- zone, x, y; o = where to work on it: kind (\"mob\", \"object\", \"vendor\"")
    w("-- or \"boss\", whose zone is its dungeon with x and y 0), name, zone, x, y,")
    w("-- and the item to collect there, if that is the objective }.")
    w("-- Either part can be missing when the data does not say.")
    w("Sources.ENDS = {")
    for qid in sorted(ends):
        done, goal, item = ends[qid]
        parts = [row(done)] if done else []
        if goal:
            extra = f", {lua_string(item)}" if item else ""
            parts.append(f"o = {{ {row(goal)}{extra} }}")
        w(f"    [{qid}] = {{ " + ", ".join(parts) + " },")
    w("}")
    text = "\n".join(out) + "\n"
    if "--stdout" in argv:
        sys.stdout.write(text)
        return
    with open(OUTPUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print(f"wrote {OUTPUT}: {len(ends)} quests, "
          f"{sum(1 for e in ends.values() if e[0])} with a hand-in, "
          f"{sum(1 for e in ends.values() if e[1])} with a place to work on it")


if __name__ == "__main__":
    main(sys.argv[1:])
