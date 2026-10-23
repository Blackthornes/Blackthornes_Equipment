"""Tests for tools/make_dungeon_doors.py. Run: python tools/test_make_dungeon_doors.py"""

import os
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_dungeon_doors as tool  # noqa: E402

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
    write(folder, "Sources.lua",
          'Sources.DUNGEONS = {\n'
          '    ["36"] = { "The Deadmines", 17, 26, "Westfall", "" },\n'
          '    ["189Library"] = { "Scarlet Monastery Library", 29, 39, "Westfall", "" },\n'
          '    ["229"] = { "Blackrock Spire", 55, 60, "Blackrock Mountain", "" },\n'
          '    ["533"] = { "Naxxramas", 60, 60, "Eastern Plaguelands", "", true },\n'
          '}\nSources.NPCS = {\n    [1] = { "Nobody", 12, 1, 1, "A" },\n}\n')
    write(folder, "DungeonQuests.lua",
          'ns.FOREVER_DUNGEON_PLACES = {\n    ["2784"] = { "Demon Fall Canyon", "Westfall" },\n}\n')
    dungeons = tool.read_dungeons(os.path.join(folder, "Sources.lua"), os.path.join(folder, "DungeonQuests.lua"))
    write(folder, "Map.csv", "ID,MapName_lang,Corpse_0,Corpse_1,CorpseMapID\n"
          "36,Deadmines,500,-250,0\n189,Scarlet Monastery,100,100,0\n229,Blackrock Spire,900,900,0\n"
          "533,Naxxramas,500,-250,0\n2784,Demon Fall Canyon,0,0,-1\n")
    write(folder, "AreaPOI.csv", "Name_lang,Pos_0,Pos_1,ContinentID\nDemon Fall Canyon,750,-500,0\n")
    write(folder, "UiMap.csv", "Name_lang,ID,Type\nWestfall,1,3\nSearing Gorge,2,3\nKalimdor,3,2\n")
    write(folder, "UiMapAssignment.csv",
          "UiMin_0,UiMin_1,UiMax_0,UiMax_1,Region_0,Region_1,Region_3,Region_4,UiMapID,MapID\n"
          "0,0,1,1,0,-1000,1000,0,1,0\n0,0,1,1,800,800,1000,1000,2,0\n0,0,1,1,-5000,-5000,5000,5000,3,0\n")
    found = tool.spots(folder, dungeons)
finally:
    shutil.rmtree(folder)

expect("dungeons and Forever's own are read", set(dungeons) == {"36", "189Library", "229", "533", "2784"})
expect("the entrance spot lands on the zone map", found.get("36") == ("Westfall", 25.0, 50.0))
expect("the map's own label is used", found.get("2784") == ("Westfall", 50.0, 25.0))
expect("a mountain door lands in Searing Gorge", found.get("229", ("",))[0] == "Searing Gorge")
expect("a spot outside the door's zone is left out", "533" not in found)
expect("a wing outside its door zone is left out", "189Library" not in found)
text = tool.render(found, "1.2.3")
expect("the file names the build", "build 1.2.3" in text)
expect("the file lists a spot", '["36"] = { "Westfall", 25.0, 50.0 },' in text)

print("%d checks, %d failures" % (checks, failures))
sys.exit(1 if failures else 0)
