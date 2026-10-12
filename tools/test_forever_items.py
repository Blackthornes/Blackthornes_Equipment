"""Tests for tools/forever_items.py. Run: python tools/test_forever_items.py"""

import os
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from forever_items import ALL_CLASSES, differences, mask, read_items, read_table, render  # noqa: E402

checks = 0
failures = 0


def expect(label, ok):
    global checks, failures
    checks += 1
    if not ok:
        failures += 1
        print("FAIL: " + label)


# Masks: every Classic class or race is "anyone", as the Classic data has it.
expect("-1 is anyone", mask("-1", ALL_CLASSES) == 0)
expect("a mask with every class is anyone", mask(1535, ALL_CLASSES) == 0 and mask(32767, ALL_CLASSES) == 0)
expect("one class stays", mask(4, ALL_CLASSES) == 4)
expect("classes Classic never had are dropped", mask(4 | 32 | 512, ALL_CLASSES) == 4)

HEADER = "ID,Display_lang,RequiredLevel,ItemLevel,AllowableClass,AllowableRace_0,BuyPrice,Bonding\n"
ROWS = [
    '100,"Vendor Vest",18,24,-1,-1,480,2\n',
    '101,"Quest Boots",10,15,-1,-1,1,1\n',
    '102,"Same Ring",30,35,4,-1,900,2\n',
    '200,"Crafted Pants",40,45,-1,-1,0,2\n',
    'bad,"Broken",x,y,z,w,v,u\n',
]
folder = tempfile.mkdtemp()
try:
    with open(os.path.join(folder, "ItemSparse.csv"), "w", encoding="utf-8") as f:
        f.write(HEADER + "".join(ROWS))
    client = read_table(folder)
finally:
    shutil.rmtree(folder)

expect("rows are read", client.get(100) == (18, 24, 0, 0, 480))
expect("a broken row is skipped", len(client) == 4)

DATA = """
Sources.ITEMS = {
    [100] = { 20, 25, 1, 0, 500, v = { 1, 0 } },
    [101] = { 10, 15, 0, 0, 700, q = { 5 } },
    [102] = { 30, 35, 4, 255, 900, v = { 1, 0 } },
    [103] = { 1, 1, 0, 0, 0 },
}
Crafts.ITEMS = {
    [200] = { 164, 150, 9999, 37, 42, 0, 0, 0, m = { 2840, 4 } },
}
"""
folder = tempfile.mkdtemp()
try:
    path = os.path.join(folder, "Data.lua")
    with open(path, "w", encoding="utf-8") as f:
        f.write(DATA)
    sources, vendors = read_items(path, "Sources.ITEMS")
    crafts, _ = read_items(path, "Crafts.ITEMS")
finally:
    shutil.rmtree(folder)

expect("the Classic rows are read", sources[100] == [20, 25, 1, 0, 500] and sources[103] == [1, 1, 0, 0, 0])
expect("vendors are told apart", vendors == {100, 102})
expect("crafts stop at their own table", list(crafts) == [200] and crafts[200][3] == 37)

rows = differences(client, sources, vendors, crafts)
expect("a changed vendor item is listed", rows.get(100) == (18, 24, 0, 0, 480))
expect("a quest reward's price alone is no change", 101 not in rows)
expect("an item the client agrees on is left out", 102 not in rows)
expect("an item the client lacks is left out", 103 not in rows)
expect("a changed craft is listed", rows.get(200) == (40, 45, 0, 0, 0))

text = render(rows, "1.60.1.70338")
expect("the file is sorted rows", "[100] = { 18, 24, 0, 0, 480 }," in text and text.index("[100]") < text.index("[200]"))
expect("the header names the build", "(build 1.60.1.70338)" in text)
for word in ("http", "www.", ".tools", ".com"):
    expect("the file names no site (" + word + ")", word not in text)

print(f"{checks} checks, {failures} failed")
sys.exit(1 if failures else 0)
