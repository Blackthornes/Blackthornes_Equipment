"""Tests for tools/forever_vendors.py. Run: python tools/test_forever_vendors.py"""

import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lupa import lua51  # noqa: E402
from forever_vendors import from_save, shared_from_save, merge, new_to_classic, render  # noqa: E402

checks = 0
failures = 0


def expect(label, ok):
    global checks, failures
    checks += 1
    if not ok:
        failures += 1
        print("FAIL: " + label)


def read(text):
    with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False, encoding="utf-8") as f:
        f.write(text)
        path = f.name
    try:
        return from_save(lua51.LuaRuntime(unpack_returned_tuples=True, register_eval=False), path)
    finally:
        os.remove(path)

def read_shared(text):
    with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False, encoding="utf-8") as f:
        f.write(text)
        path = f.name
    try:
        return shared_from_save(lua51.LuaRuntime(unpack_returned_tuples=True, register_eval=False), path)
    finally:
        os.remove(path)



SAVE = """
BlackthornesEquipmentDB = {
    ["learnedVendors"] = {
        [250001] = { name = "Aetheen", zone = "Zephras Isle", x = 40, y = 60.5, side = "A",
            items = { [1002] = { 120, 3, 8, false }, [1003] = { 300, 4, 0, true } }, at = 5 },
        [250002] = { name = "Nowhere", items = { [1001] = { 1, 1, 1, false } } },
    },
    ["characters"] = { ["Player-1-2"] = { name = "Private" } },
}
"""
found = read(SAVE)
expect("a vendor is read", 250001 in found and found[250001]["zone"] == "Zephras Isle")
expect("with its gear", found[250001]["items"][1003] == (300, 4, 0, True))
expect("and its side", found[250001]["side"] == "A")
expect("a vendor with no place is skipped", 250002 not in found)

merged = merge(found[250001], {"name": "", "zone": "Zephras Isle", "x": 41.0, "y": 60.0, "side": "H",
                               "items": {1003: (300, 4, 9, True)}})
expect("a reading from the other side serves both", merged["side"] == "AH")
expect("the item level, once known, is kept", merged["items"][1003] == (300, 4, 9, True))
expect("earlier gear stays", 1002 in merged["items"])
expect("the name stays when the newer reading lacks it", merged["name"] == "Aetheen")

trimmed = new_to_classic(250001, found[250001], {1002: {250001}})
expect("gear Classic lists for the vendor is left out", 1002 not in trimmed["items"] and 1003 in trimmed["items"])
expect("a vendor with nothing new is dropped", new_to_classic(250001, found[250001], {1002: {250001}, 1003: {250001}}) is None)

text = render({250001: found[250001]})
expect("the file names the vendor", '[250001] = { name = "Aetheen", zone = "Zephras Isle"' in text)
expect("with its gear", "[1003] = { 300, 4, 0, true }" in text)
expect("and leaves out anything private", "Private" not in text and "Player-1-2" not in text)

SHARED = """
BlackthornesEquipmentDB = {
    ["sharedData"] = {
        ["a1b2c3d4e5f6"] = { at = 5, hash = "x", quests = {},
            vendors = { [800005] = { name = "Sent Vendor", zone = "Zephras Isle", x = 30, y = 60, side = "A",
                items = { [2001] = { 500, 10, 15, false } } } } },
        ["badbadbadbad"] = "junk",
    },
}
"""
shares = read_shared(SHARED)
expect("a sender's vendors are read from sharedData", any(800005 in s for s in shares))
expect("junk in sharedData is skipped", len(shares) == 1)
expect("the save's own list is still empty", read(SHARED) == {})

print(f"{checks - failures}/{checks} checks passed")
sys.exit(1 if failures else 0)
