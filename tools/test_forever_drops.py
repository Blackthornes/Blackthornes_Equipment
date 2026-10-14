"""Tests for tools/forever_drops.py. Run: python tools/test_forever_drops.py"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lupa import lua51  # noqa: E402
from forever_drops import collect, render  # noqa: E402

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

nothing, none = collect(sources, lua.execute("return {}"))
expect("with no Forever dungeon seen, nothing is added", none == {} and "DUNGEONS[" not in render(nothing, none))

print(f"{checks - failures}/{checks} checks passed")
sys.exit(1 if failures else 0)
