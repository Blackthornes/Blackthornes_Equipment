"""Tests for tools/forever_dungeon_quests.py. Run: python tools/test_forever_dungeon_quests.py"""

import os
import struct
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lupa import lua51  # noqa: E402
from forever_dungeon_quests import (STRING_BITS, from_cache, from_facts, from_save,  # noqa: E402
                                    known_dungeons, merge, read_cache, render, shared_from_save)

checks = 0
failures = 0


def expect(label, ok):
    global checks, failures
    checks += 1
    if not ok:
        failures += 1
        print("FAIL: " + label)


def record(qid, title, level, low, sort, after=0, texts=("Do the thing.", "Go on.")):
    """One made-up cache record, laid out as the game keeps them."""
    fields = [0] * 12
    fields[0], fields[1], fields[2], fields[4], fields[6], fields[9] = qid, 2, level, low, sort, after
    body = struct.pack("<12i", *fields) + b"\0" * 40
    strings = [title.encode()] + [t.encode() for t in texts]
    lengths = [len(s) for s in strings] + [0] * (len(STRING_BITS) - len(strings))
    value, used = 0, 0
    for width, n in zip(STRING_BITS, lengths):
        value = (value << width) | n
        used += width
    value <<= 96 - used
    body += value.to_bytes(12, "big") + b"".join(strings)
    return struct.pack("<II", qid, len(body)) + body


def cache(*records, locale=b"SUne"):
    head = b"TSQW" + b"2\x13\x01\x00" + locale + struct.pack("<III", 0, 12, 0)
    return head + b"".join(records) + struct.pack("<II", 0, 0)


AREAS = {9001: "2999", 9002: "3065"}

data = cache(record(95001, "Into the Ruins", 25, 20, 9001, after=95002),
             record(95002, "Deeper Still", 26, 21, 9001),
             record(95003, "Out in the Fields", 20, 15, 85),
             record(95004, "Thane's Due", 30, 28, 9002))
records = read_cache(data)
expect("every record is read", len(records) == 4)
expect("the title comes out whole", records[0]["title"] == "Into the Ruins")
expect("levels come out", records[0]["level"] == 25 and records[0]["min"] == 20)

found = from_cache(records, AREAS)
expect("only quests filed inside a dungeon", set(found) == {95001, 95002, 95004})
expect("the dungeon is the area's map", found[95001]["dungeon"] == "2999" and found[95004]["dungeon"] == "3065")
expect("the quest before comes from the one after", found[95002]["prev"] == 95001 and found[95001]["prev"] == 0)

expect("another language's cache is not read", read_cache(cache(record(1, "Eins", 1, 1, 9001), locale=b"EDed")) == [])
expect("a broken file reads as nothing", read_cache(b"junk") == [])

keys = known_dungeons()
expect("Forever's dungeons are known", "2999" in keys and "3065" in keys and "36" in keys)

save = """BlackthornesEquipmentDB = {
    learnedDungeonQuests = {
        [95002] = { dungeon = "2999", title = "Deeper Still", level = 26, side = "H",
            giver = "Someone", zone = "Tirisfal Glades", x = 61.5, y = 50.2, at = 1 },
        [95009] = { dungeon = "nowhere", title = "Lost" },
        [95010] = { dungeon = "2999", title = 7 },
    },
    characterGear = { ["Player-1"] = { name = "Never Copied" } },
}"""
with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False, encoding="utf-8") as f:
    f.write(save)
    path = f.name
try:
    learned = from_save(lua51.LuaRuntime(unpack_returned_tuples=True, register_eval=False), path, keys)
finally:
    os.remove(path)
expect("a learned quest is read", 95002 in learned and learned[95002]["giver"] == "Someone")
expect("an unknown dungeon is left out", 95009 not in learned)

row = merge(found[95002], learned[95002])
expect("the save fills in the giver and side", row["giver"] == "Someone" and row["side"] == "H")
expect("the cache's quest before is kept", row["prev"] == 95001)

text = render({95002: row})
expect("the row is written in the data's shape",
       '[95002] = { "2999", "Deeper Still", 21, 26, "H", 0, "Someone", "Tirisfal Glades", 61.5, 50.2, 0, 95001 },' in text)
expect("nothing about the player is written", "Never Copied" not in text and "Player-1" not in text)

shared_save = """BlackthornesEquipmentDB = {
    learnedDungeonQuests = {},
    sharedData = {
        ["a1b2c3d4e5f6"] = { at = 5, quests = {}, vendors = {},
            dungeons = { [95020] = { dungeon = "2999", title = "Sent Down", level = 24, side = "A" },
                         [95021] = { dungeon = "nowhere", title = "Lost" } } },
        ["olderolder12"] = { at = 4, quests = {}, vendors = {} },
        ["badbadbadbad"] = "junk",
    },
    sharedDataLog = { { at = 5, name = "Somebody", vendors = 0, quests = 1 } },
}"""
with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False, encoding="utf-8") as f:
    f.write(shared_save)
    path = f.name
try:
    shares = shared_from_save(lua51.LuaRuntime(unpack_returned_tuples=True, register_eval=False), path, keys)
finally:
    os.remove(path)
expect("a sender's dungeon quests are read", any(95020 in sh and sh[95020]["side"] == "A" for sh in shares))
expect("an unknown dungeon in a share is left out", not any(95021 in sh for sh in shares))
expect("an older sender with no dungeon quests is fine", len(shares) == 2)

facts = {"quests": {
    "95030": {"dungeon": "3065", "title": "Checked Ahead", "min": 10, "level": 15, "side": "A",
              "giver": "Someone", "zone": "Ironforge", "x": 32.6, "y": 44.6, "reward": 279898},
    "95031": {"dungeon": "3065", "title": "Not in the Client", "min": 10, "level": 15},
    "95032": {"dungeon": "nowhere", "title": "Lost", "min": 1},
    "95033": {"dungeon": "2999", "title": "Class Only", "min": 16, "classes": 2},
}}
checked = from_facts(facts, keys, {95030, 95032, 95033})
expect("a fact the client has is read", checked[95030]["giver"] == "Someone" and checked[95030]["reward"] == 279898)
expect("a fact the client lacks is left out", 95031 not in checked)
expect("a fact in an unknown dungeon is left out", 95032 not in checked)
expect("a class quest keeps its classes", checked[95033]["classes"] == 2)
expect("a quest with no level takes its lowest", checked[95033]["level"] == 16)
later = merge(checked[95030], {"dungeon": "3065", "title": "Checked Ahead", "level": 16, "min": 11})
expect("the game's own reading wins over a fact", later["level"] == 16 and later["giver"] == "Someone")

lua = lua51.LuaRuntime(unpack_returned_tuples=True, register_eval=False)
lua.execute("ns = {}")
lua.execute(text.replace("local _, ns = ...", ""))
expect("the file loads", lua.eval("ns.FOREVER_DUNGEON_QUESTS[95002][2]") == "Deeper Still")

print(f"{checks - failures}/{checks} checks passed")
sys.exit(1 if failures else 0)
