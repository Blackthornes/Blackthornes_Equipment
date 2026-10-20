"""Writes Data/ForeverDungeonQuests.lua: Forever's own dungeon and raid
quests, met in game, that Classic's data in Data/DungeonQuests.lua lacks.

Run from the repository root at each release:

    python tools/forever_dungeon_quests.py --tables <tables folder> \
        [--cache questcache.wdb ...] [saved file ...]

Two kinds of reading, both from the owner's own game, both read only:

- the game's English quest cache (Cache/WDB/enUS/questcache.wdb beside
  WTF), which holds every quest the client has shown: its ID, title,
  levels, the zone it is filed under and the quest after it. A quest
  counts as a dungeon's when that zone lies inside a dungeon or raid the
  addon knows (AreaTable's ContinentID is the instance's map).
- the addon's account save, Blackthornes_Equipment.lua: only its
  `learnedDungeonQuests` table (Logic/DungeonQuests.lua), which adds the
  side, who gives it and where.

Nothing about the player or their characters is copied. Never commit the
cache or a save, and never edit the output by hand.

The quests already in Data/ForeverDungeonQuests.lua are kept, and a newer
reading fills in what they lack. A quest Data/DungeonQuests.lua already has
is left out.

Options:
    --stdout   print the file instead of writing it
"""

import argparse
import csv
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lupa import lua51  # noqa: E402

import make_sources as ms  # noqa: E402
from forever_drops import FOREVER_DUNGEONS  # noqa: E402
from forever_npcs import READ_SAVE, lua_string, num, run_file  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT = os.path.join(ROOT, "Data", "ForeverDungeonQuests.lua")
CLASSIC = os.path.join(ROOT, "Data", "DungeonQuests.lua")

# The string lengths before a quest's text, packed in bits: title, log
# text, description, area text, then the portrait and completion texts.
STRING_BITS = (9, 12, 12, 9, 10, 8, 10, 8, 11)
# Fields from the start of a record, four bytes each.
F_ID, F_LEVEL, F_MIN, F_SORT, F_NEXT = 0, 2, 4, 6, 9


def known_dungeons():
    """The dungeon keys the addon knows, as strings."""
    keys = {str(m) for m in ms.INSTANCES}
    keys |= {str(m) for m in FOREVER_DUNGEONS}
    return keys


def area_maps(tables, keys):
    """Area ID -> dungeon key, for areas inside a dungeon the addon knows."""
    out = {}
    with open(os.path.join(tables, "AreaTable.csv"), encoding="utf-8") as f:
        for r in csv.DictReader(f):
            key = r["ContinentID"]
            if key in keys:
                out[int(r["ID"])] = key
    return out


def _lengths(block):
    value, size, used, out = int.from_bytes(block, "big"), len(block) * 8, 0, []
    for width in STRING_BITS:
        out.append((value >> (size - used - width)) & ((1 << width) - 1))
        used += width
    return out


def read_record(qid, rec):
    """{ id, title, level, min, sort, next } from one cache record, or None."""
    if len(rec) < 48:
        return None
    fields = struct.unpack("<12i", rec[:48])
    if fields[F_ID] != qid:
        return None
    # The text runs to the end of the record, so its lengths sit just before
    # it, packed into 12 bytes. Look for the one place where they add up.
    found = None
    for at in range(48, len(rec) - 12):
        lengths = _lengths(rec[at:at + 12])
        if not 1 <= lengths[0] <= 255 or at + 12 + sum(lengths) != len(rec):
            continue
        title = rec[at + 12:at + 12 + lengths[0]]
        if all(32 <= c < 127 or c >= 128 for c in title):
            if found:
                return None   # not sure which, so leave it
            found = title
    if not found:
        return None
    try:
        title = found.decode("utf-8")
    except UnicodeDecodeError:
        return None
    return {"id": qid, "title": title, "level": fields[F_LEVEL], "min": fields[F_MIN],
            "sort": fields[F_SORT], "next": fields[F_NEXT]}


def read_cache(data):
    """[record] from an English questcache.wdb, or [] for another."""
    if len(data) < 24 or data[:4] != b"TSQW" or data[8:12] != b"SUne":
        return []
    out, pos = [], 24
    while pos + 8 <= len(data):
        qid, size = struct.unpack("<II", data[pos:pos + 8])
        record = data[pos + 8:pos + 8 + size]
        pos += 8 + size
        if size == 0 or len(record) < size:
            break
        rec = read_record(qid, record)
        if rec:
            out.append(rec)
    return out


def from_cache(records, areas):
    """Dungeon quests from cache records: { id: row }."""
    after = {r["next"]: r["id"] for r in records if r["next"] > 0}
    found = {}
    for r in records:
        key = areas.get(r["sort"]) if r["sort"] > 0 else None
        if not key:
            continue
        level = max(r["level"], 0)
        found[r["id"]] = {"dungeon": key, "title": r["title"], "min": max(r["min"], 0) or level,
                          "level": level, "prev": after.get(r["id"], 0)}
    return found


def from_save(lua, path, keys):
    """learnedDungeonQuests in one account save, checked field by field."""
    with open(path, encoding="utf-8") as f:
        db, why = lua.eval(READ_SAVE)(f.read())
    if why:
        print(f"could not read {path}: {why}", file=sys.stderr)
    learned = db and db.learnedDungeonQuests
    found = {}
    for qid in learned or {}:
        raw = learned[qid]
        try:
            if str(raw["dungeon"]) not in keys or not raw["title"]:
                continue
            row = {"dungeon": str(raw["dungeon"]), "title": str(raw["title"])}
            for key in ("level", "min", "reward"):
                if raw[key] is not None:
                    row[key] = int(raw[key])
            for key in ("giver", "zone"):
                if raw[key] is not None:
                    row[key] = str(raw[key])
            for key in ("x", "y"):
                if raw[key] is not None:
                    row[key] = float(raw[key])
            if raw["side"] in ("A", "H"):
                row["side"] = str(raw["side"])
            found[int(qid)] = row
        except (TypeError, ValueError, KeyError):
            print(f"skipped a row that could not be read: {qid}", file=sys.stderr)
    return found


ORDER = ("dungeon", "title", "min", "level", "side", "classes", "giver", "zone",
         "x", "y", "reward", "prev")


def lua_rows(lua, path, name):
    """{ id: row } from a data file in the DUNGEON_QUESTS shape."""
    if not os.path.exists(path):
        return {}
    lua.execute("ns = {}")
    run_file(lua, path)
    table = lua.eval("ns." + name)
    out = {}
    for qid in table or {}:
        q = table[qid]
        out[int(qid)] = {k: q[i + 1] for i, k in enumerate(ORDER) if q[i + 1] not in (None, "", 0)}
    return out


def merge(old, new):
    """A newer reading fills in what the older one lacks; levels follow it."""
    row = dict(old)
    for key, value in new.items():
        if value in (None, "", 0):
            continue
        if key not in row or key in ("level", "min", "title"):
            row[key] = value
    return row


def render(rows):
    lines = [
        "-- Blackthornes Equipment -- Data/ForeverDungeonQuests.lua",
        "-- Forever's own dungeon and raid quests, met in game.",
        "--",
        "-- Generated by tools/forever_dungeon_quests.py. Do not edit by hand:",
        "-- rerun the tool. Each row is in Data/DungeonQuests.lua's shape:",
        "-- { dungeon, title, lowest level, quest level, side (\"A\", \"H\" or \"\"),",
        "--   classes (0 for any), who starts it, its zone, x, y, a reward item,",
        "--   the quest before }",
        "",
        "local _, ns = ...",
        "",
        "ns.FOREVER_DUNGEON_QUESTS = {",
    ]
    for qid in sorted(rows):
        r = rows[qid]
        lines.append("    [%d] = { %s, %s, %d, %d, %s, %d, %s, %s, %s, %s, %d, %d }," % (
            qid, lua_string(r["dungeon"]), lua_string(r["title"]), r.get("min", 0),
            r.get("level", 0), lua_string(r.get("side", "")), r.get("classes", 0),
            lua_string(r.get("giver", "")), lua_string(r.get("zone", "")),
            num(r.get("x", 0)), num(r.get("y", 0)), r.get("reward", 0), r.get("prev", 0)))
    lines.append("}")
    return "\n".join(lines) + "\n"


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--tables", required=True)
    ap.add_argument("--cache", action="append", default=[])
    ap.add_argument("--stdout", action="store_true")
    ap.add_argument("saves", nargs="*")
    args = ap.parse_args(argv)

    keys = known_dungeons()
    lua = lua51.LuaRuntime(unpack_returned_tuples=True, register_eval=False)
    classic = set(lua_rows(lua, CLASSIC, "DUNGEON_QUESTS"))
    rows = lua_rows(lua, OUTPUT, "FOREVER_DUNGEON_QUESTS")

    def add(found):
        for qid, row in found.items():
            rows[qid] = merge(rows[qid], row) if qid in rows else row

    if args.cache:
        areas = area_maps(args.tables, keys)
        for path in args.cache:
            with open(path, "rb") as f:
                records = read_cache(f.read())
            if not records:
                print(f"{path} is not an English quest cache", file=sys.stderr)
            add(from_cache(records, areas))
    for path in args.saves:
        add(from_save(lua, path, keys))

    kept = {q: r for q, r in rows.items() if q not in classic}
    text = render(kept)
    if args.stdout:
        sys.stdout.write(text)
    else:
        with open(OUTPUT, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        print(f"{len(kept)} Forever dungeon quests written to Data/ForeverDungeonQuests.lua")


if __name__ == "__main__":
    main(sys.argv[1:])
