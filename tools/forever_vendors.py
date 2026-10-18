"""Writes Data/ForeverVendors.lua: gear WoW: Forever's vendors sell that the
Classic data in Data/Sources.lua does not list for them.

Run from the repository root:

    python tools/forever_vendors.py [saved file ...]

A saved file is the addon's account save, Blackthornes_Equipment.lua from
the game's WTF/Account/<account>/SavedVariables folder. Only its
`learnedVendors` table is read (Logic/NPCSpots.lua: NPC ID -> name, where it
stands, the side it serves and the gear it sells), so nothing about the
player or their characters is copied.

The vendors already in Data/ForeverVendors.lua are kept, and a newer reading
of the same vendor adds to them. Gear Classic already lists for that vendor
is left out, since there is nothing to add.

Options:
    --stdout   print the file instead of writing it
    --shared   also fold in the vendors players sent (sharedData, from
               Logic/Contribute.lua). Only each sender's vendors are read,
               never who sent them, and the save is never changed. They go
               in before the save's own, so the player's own readings win.
"""

import os
import sys

from lupa import lua51

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from forever_npcs import READ_SAVE, lua_string, num, run_file  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT = os.path.join(ROOT, "Data", "ForeverVendors.lua")


def classic(lua):
    """{itemID: set of vendor NPC IDs} from Data/Sources.lua."""
    lua.execute("ns = {}")
    run_file(lua, os.path.join(ROOT, "Data", "Sources.lua"))
    data = lua.eval("ns.Sources")
    sold = {}
    for item_id in data.ITEMS:
        v = data.ITEMS[item_id].v
        if v:
            values = [int(v[i]) for i in sorted(v.keys())]
            sold[int(item_id)] = set(values[0::2])
    return sold


def join_sides(a, b):
    if a is None or a == b:
        return b
    if b is None:
        return a
    return "AH"


def clean(raw):
    """One vendor record, checked field by field; None when it is unusable."""
    try:
        if not raw["zone"] or raw["x"] is None or raw["y"] is None:
            return None
        rec = {
            "name": str(raw["name"] or ""),
            "zone": str(raw["zone"]),
            "x": float(raw["x"]),
            "y": float(raw["y"]),
            "side": str(raw["side"]) if raw["side"] in ("A", "H", "AH") else "AH",
        }
        items = {}
        for item_id in raw["items"] or {}:
            r = raw["items"][item_id]
            items[int(item_id)] = (int(r[1] or 0), int(r[2] or 0), int(r[3] or 0), bool(r[4]))
        rec["items"] = items
        return rec if items else None
    except (TypeError, ValueError, KeyError):
        return None


def table_to_records(lua_table):
    found = {}
    for npc_id in lua_table or {}:
        rec = clean(lua_table[npc_id])
        if rec:
            found[int(npc_id)] = rec
        else:
            print(f"skipped a row that could not be read: {npc_id}", file=sys.stderr)
    return found


def from_save(lua, path):
    with open(path, encoding="utf-8") as f:
        db, why = lua.eval(READ_SAVE)(f.read())
    if why:
        print(f"could not read {path}: {why}", file=sys.stderr)
    return table_to_records(db and db.learnedVendors)


def shared_from_save(lua, path):
    """What players sent, by Logic/Contribute.lua, in one account save: each
    sender's `vendors` from `sharedData`. The sender ids are only keys."""
    with open(path, encoding="utf-8") as f:
        db, why = lua.eval(READ_SAVE)(f.read())
    if why:
        print(f"could not read {path}: {why}", file=sys.stderr)
    found = []
    shared = db and db.sharedData
    for sender in shared or {}:
        entry = shared[sender]
        try:
            found.append(table_to_records(entry["vendors"]))
        except (TypeError, KeyError):
            print("skipped a share that could not be read", file=sys.stderr)
    return found


def shipped(lua):
    if not os.path.exists(OUTPUT):
        return {}
    lua.execute("ns = {}")
    run_file(lua, OUTPUT)
    return table_to_records(lua.eval("ns.ForeverVendors"))


def merge(old, new):
    """Add a newer reading of a vendor to an older one: the newer spot and
    name, both sides, and every item (an item level, once known, kept)."""
    rec = dict(new)
    rec["name"] = new["name"] or old["name"]
    rec["side"] = join_sides(old["side"], new["side"])
    items = dict(old["items"])
    for item_id, row in new["items"].items():
        have = items.get(item_id)
        items[item_id] = (row[0], row[1] or (have and have[1]) or 0, row[2] or (have and have[2]) or 0, row[3])
    rec["items"] = items
    return rec


def new_to_classic(npc_id, rec, sold):
    """The record with only the items Classic does not list for this vendor."""
    items = {i: r for i, r in rec["items"].items() if npc_id not in sold.get(i, set())}
    if not items:
        return None
    return dict(rec, items=items)


def render(records):
    lines = [
        "-- Blackthornes Equipment -- Data/ForeverVendors.lua",
        "-- Gear WoW: Forever's vendors sell that the Classic data in",
        "-- Data/Sources.lua does not list for them.",
        "--",
        "-- Generated by tools/forever_vendors.py from vendors seen in game",
        "-- (Logic/NPCSpots.lua keeps what a merchant window shows). Do not edit",
        "-- by hand: rerun the tool. Each NPC ID lists { name, zone, x, y, side,",
        "-- items = { [itemID] = { price in copper, required level, item level,",
        "-- limited stock } } }; side is \"A\", \"H\" or \"AH\", who the vendor serves.",
        "",
        "local _, ns = ...",
        "",
        "ns.ForeverVendors = {",
    ]
    for npc_id in sorted(records):
        rec = records[npc_id]
        items = ", ".join(
            "[%d] = { %d, %d, %d, %s }" % (i, price, req, ilvl, "true" if limited else "false")
            for i, (price, req, ilvl, limited) in sorted(rec["items"].items())
        )
        lines.append(
            f"    [{npc_id}] = {{ name = {lua_string(rec['name'])}, zone = {lua_string(rec['zone'])}, "
            f"x = {num(rec['x'])}, y = {num(rec['y'])}, side = {lua_string(rec['side'])}, "
            f"items = {{ {items} }} }},"
        )
    lines.append("}")
    return "\n".join(lines) + "\n"


def main(argv):
    to_stdout = "--stdout" in argv
    with_shared = "--shared" in argv
    saves = [a for a in argv if a not in ("--stdout", "--shared")]
    lua = lua51.LuaRuntime(unpack_returned_tuples=True, register_eval=False)
    sold = classic(lua)
    records = shipped(lua)
    if with_shared:
        for path in saves:
            for share in shared_from_save(lua, path):
                for npc_id, rec in share.items():
                    records[npc_id] = merge(records[npc_id], rec) if npc_id in records else rec
    for path in saves:
        for npc_id, rec in from_save(lua, path).items():
            records[npc_id] = merge(records[npc_id], rec) if npc_id in records else rec
    kept = {}
    for npc_id, rec in records.items():
        rec = new_to_classic(npc_id, rec, sold)
        if rec:
            kept[npc_id] = rec
    text = render(kept)
    if to_stdout:
        sys.stdout.write(text)
    else:
        with open(OUTPUT, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        print(f"{len(kept)} vendors written to Data/ForeverVendors.lua")


if __name__ == "__main__":
    main(sys.argv[1:])
