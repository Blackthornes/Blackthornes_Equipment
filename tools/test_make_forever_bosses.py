"""Tests for tools/make_forever_bosses.py. Run: python tools/test_make_forever_bosses.py"""

import os
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_forever_bosses as tool  # noqa: E402

checks = 0
failures = 0


def expect(label, ok):
    global checks, failures
    checks += 1
    if not ok:
        failures += 1
        print("FAIL: " + label)


def write(folder, name, text):
    with open(os.path.join(folder, name), "w", encoding="utf-8") as f:
        f.write(text)


folder = tempfile.mkdtemp()
try:
    write(folder, "DungeonQuests.lua",
          'ns.DUNGEON_QUESTS = {\n    [1] = { "36", "A Quest" },\n}\n'
          'ns.FOREVER_DUNGEON_PLACES = {\n'
          '    ["2999"] = { "Ruins of Lordaeron", "Tirisfal Glades" },\n'
          '    ["3065"] = { "The Hall of Thanes", "Ironforge" },\n'
          '    ["3109"] = { "Manor Mistmantle", "" },\n'
          '}\n')
    places = tool.read_places(os.path.join(folder, "DungeonQuests.lua"))
    expect("reads the Forever places", places == {"2999": "Ruins of Lordaeron", "3065": "The Hall of Thanes",
                                                   "3109": "Manor Mistmantle"})
    write(folder, "DungeonEncounter.csv",
          "Name_lang,ID,MapID,DifficultyID,OrderIndex,CompleteWorldStateID,Bit,Flags,SpellIconFileID,Faction,ItemSequenceLevel\n"
          "The Abandoned,1,2999,0,1,0,0,0,0,-1,0\n"
          "Witherfang,2,2999,0,0,0,0,0,0,-1,0\n"
          "Testwerk,3,2999,0,2,0,0,0,0,-1,0\n"
          "Heroic Witherfang,4,2999,1,0,0,0,0,0,-1,0\n"
          "Infurnus,5,3065,0,0,0,0,0,0,-1,0\n"
          "Ragnaros,6,409,0,0,0,0,0,0,-1,0\n"
          "\"Bjork, the \"\"Big\"\"\",7,2999,0,3,0,0,0,0,-1,0\n")
    found = tool.bosses(folder, places)
    expect("in the game's order", found["2999"][:2] == ["Witherfang", "The Abandoned"])
    expect("test bosses left out", "Testwerk" not in found["2999"])
    expect("only the normal difficulty", "Heroic Witherfang" not in found["2999"])
    expect("other maps left out", "409" not in found)
    expect("a dungeon with no bosses is left out", "3109" not in found)
    expect("the name in game wins", found["3065"] == ["Magmatus"])
    text = tool.render(found, places, "1.2.3.4")
    expect("names the build", "build 1.2.3.4" in text)
    expect("quotes are escaped", '"Bjork, the \\"Big\\""' in text)
    expect("one line a dungeon", '    ["3065"] = { "Magmatus" }, -- The Hall of Thanes' in text)
    expect("never names a site", "http" not in text and ".com" not in text)
finally:
    shutil.rmtree(folder)

print("%d checks, %d failed" % (checks, failures))
sys.exit(1 if failures else 0)
