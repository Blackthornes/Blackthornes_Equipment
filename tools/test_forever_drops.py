"""Tests for tools/forever_drops.py. Run: python tools/test_forever_drops.py"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lupa import lua51  # noqa: E402
from forever_drops import FACTS, collect, load_facts, render  # noqa: E402

checks = 0
failures = 0


def expect(label, ok):
    global checks, failures
    checks += 1
    if not ok:
        failures += 1
        print("FAIL: " + label)


lua = lua51.LuaRuntime(unpack_returned_tuples=True, register_eval=False)
sources = lua.execute("""
    return {
        DUNGEONS = { ["43"] = { "Wailing Caverns", 17, 24, "The Barrens", "" } },
        BOSSES = { [1] = { "Mutanus the Devourer", "43" } },
    }
""")
items = lua.execute("""
    return {
        { id = 100, sources = {
            { name = "Deviate Creeper", zone = "The Wailing Caverns", minLevel = 15, maxLevel = 16, chance = 0, provenance = "forever" },
            { name = "Mutanus the Devourer", zone = "Wailing Caverns", chance = 12, provenance = "forever" },
        } },
        { id = 200, sources = {
            { name = "Scourge Ghoul", zone = "Ruins of Lordaeron", minLevel = 24, maxLevel = 25, chance = 3, provenance = "forever" },
            { name = "Plague Lord", zone = "Ruins of Lordaeron", minLevel = 27, maxLevel = 27, chance = 0, provenance = "forever" },
        } },
        { id = 300, sources = {
            { name = "Creature A", zone = "Karazhan Crypts", chance = 0, provenance = "forever" },
            { name = "Wolf", zone = "Elwynn Forest", chance = 5, provenance = "forever" },
            { name = "Old Classic", zone = "Ruins of Lordaeron", chance = 5, provenance = "classic" },
        } },
    }
""")

drops, added = collect(sources, items)
expect("a Classic dungeon's drop is kept", drops[100][("Deviate Creeper", "43")] == 0)
expect("a Classic boss keeps its rate", drops[100][("Mutanus the Devourer", "43")] == 12)
expect("a Classic dungeon is not added again", "43" not in added)
expect("a Forever dungeon's drop is kept, by its map ID", drops[200][("Scourge Ghoul", "2999")] == 3)
expect("and the dungeon is added", "2999" in added)
expect("with the levels of the mobs looted there", added["2999"][1:3] == (24, 27))
expect("and the zone its door is in", added["2999"][3] == "Tirisfal Glades")
expect("a Forever dungeon with no mob levels is open to every level",
       added["2875"][1:3] == (1, 60))
expect("an open world drop is left out", ("Wolf", "Elwynn Forest") not in drops[300])
expect("a record not seen on Forever is left out", ("Old Classic", "2999") not in drops[300])

text = render(drops, added)
expect("the file lays the dungeon over Classic's list without replacing one",
       'ns.Sources.DUNGEONS["2999"] = ns.Sources.DUNGEONS["2999"] or '
       '{ "Ruins of Lordaeron", 24, 27, "Tirisfal Glades", "" }' in text)
expect("a dungeon whose door is not known names itself",
       '"The Scarab Dais"' not in text and '"Karazhan Crypts", 1, 60, "Deadwind Pass"' in text)

# The file loads after Data/Sources.lua and the finder reads it as Classic's.
ns = lua.execute('return { Sources = { DUNGEONS = { ["43"] = { "Wailing Caverns" } } } }')
lua.execute(text.replace("local _, ns = ...", "local ns = ..."), ns)
expect("loaded, the Forever dungeon is in Sources.DUNGEONS", ns.Sources.DUNGEONS["2999"][1] == "Ruins of Lordaeron")
expect("and its drop in Sources.FOREVER", ns.Sources.FOREVER[200][1][2] == "2999")

# Facts known before anyone here looted them (tools/forever_facts.json).
sources = lua.execute("""
    return {
        DUNGEONS = { ["43"] = { "Wailing Caverns", 17, 24, "The Barrens", "" } },
        BOSSES = { [1] = { "Mutanus the Devourer", "43" } },
        ITEMS = { [500] = { 1, 20, 0, 0, 0, d = { 3654, 10 } }, [501] = { 1, 20, 0, 0, 0, q = { 1 } } },
    }
""")
facts = {
    "dungeons": {"3065": {"low": 13, "high": 18}, "2999": {"low": 15, "high": 20}},
    "loot": {
        "3065": {"Magmatus": [700, 701]},
        "2999": {"Scourge Ghoul": [200], "The Baron": [702]},
        "43": {"Mutanus the Devourer": [500, 501]},
        "9999": {"Nobody": [703]},
    },
}
drops, added = collect(sources, items, facts, known={200, 500, 501, 700, 702, 703})
expect("a fact's boss drop is added with no rate", drops[700] == {("Magmatus", "3065"): 0})
expect("an item the client lacks is left out", 701 not in drops)
expect("a fact never replaces what Farmer saw", drops[200][("Scourge Ghoul", "2999")] == 3)
expect("a new boss in a looted dungeon is added", drops[702] == {("The Baron", "2999"): 0})
expect("a dungeon only the facts know is added, at the known levels",
       added["3065"][1:3] == (13, 18) and added["3065"][3] == "Ironforge")
expect("the known range beats the looted mobs' levels", added["2999"][1:3] == (15, 20))
expect("a Classic drop Classic already lists is not added", 500 not in drops)
expect("new gear at a Classic boss is", drops[501] == {("Mutanus the Devourer", "43"): 0})
expect("a dungeon the addon does not know is skipped", 703 not in drops)

nothing, none = collect(sources, lua.execute("return {}"))
expect("the facts file is in the repo and names no site",
       load_facts()["dungeons"] and "http" not in open(FACTS, encoding="utf-8").read())
expect("with no Forever dungeon seen, nothing is added", none == {} and "DUNGEONS[" not in render(nothing, none))

print(f"{checks - failures}/{checks} checks passed")
sys.exit(1 if failures else 0)
